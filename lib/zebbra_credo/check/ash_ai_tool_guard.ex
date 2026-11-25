defmodule ZebbraCredo.Check.AshAiToolGuard do
  @moduledoc """
  Credo check (opt-in): the hard rules for AshAi tool use, each a way around
  the Tool Guard that a door in `ForbiddenCalls` alone would not catch.
  Params: `loop:` (required), `rules_doc:`.

  - No `tools: true` or `resources: true`, anywhere: they hand the model
    unwrapped tools.
  - No prompt action with tools or `extra_tools`, and none whose options the
    check cannot read: its inner loop has no gate. `AshAi.Actions.Prompt`, what
    the `prompt` macro expands to, is never named directly.
  - No `AshAi.Mcp.Router`, `AshAi.Mcp.Server` or `AshAi.Mcp.Dev` (which mounts
    the router): they run tools directly.
  - In a file that uses `AshAi.ToolLoop`: only `run/2` and `stream/2`, called by
    name, each with a literal keyword list holding `tools: false`. Left out,
    `tools` defaults to `true`. `resume/3` passes `:approvals`, which skips the
    gate. Never `:approvals`, `:actions`, `:otp_app` or a tool list.

  Credo sees one file, so it cannot read options built elsewhere: that is why
  the options must be a literal at the call, and why the `loop:` module
  sets them itself.
  """
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [loop: nil, rules_doc: nil],
    explanations: [
      check: """
      Every tool call passes the Tool Guard. The loop takes `tools: false`, and
      domain tools come from `build_tools_and_registry/1` with their names,
      wrapped and passed as `extra_tools`. Only the `loop:` module runs
      `AshAi.ToolLoop`, and it sets these options itself.
      """,
      params: [
        loop: "The module that runs `AshAi.ToolLoop` (required).",
        rules_doc: "Path of the document that states these rules; named in the messages when set."
      ]
    ]

  alias ZebbraCredo.Code

  @mcp_servers [AshAi.Mcp.Router, AshAi.Mcp.Server, AshAi.Mcp.Dev]
  @prompt_message "a prompt action never gets tools: its inner loop has no gate."

  @impl true
  def run(%SourceFile{} = source_file, params) do
    loop = Params.get(params, :loop, __MODULE__)

    if is_nil(loop),
      do: raise(ArgumentError, "#{inspect(__MODULE__)} needs the `loop:` param: the module that runs AshAi.ToolLoop")

    issue_meta = IssueMeta.for(source_file, params)
    rules_doc = Params.get(params, :rules_doc, __MODULE__)
    ast = SourceFile.ast(source_file)
    references = Code.references(ast)

    loop? =
      Enum.any?(references, fn {module, _function, _line} ->
        Code.within?(module, AshAi.ToolLoop)
      end)

    (server_issues(references) ++
       prompt_module_issues(references) ++
       loop_reference_issues(references) ++
       loop_call_issues(ast) ++
       option_issues(ast, loop?))
    |> Enum.uniq()
    |> Enum.map(fn {line, trigger, message} ->
      format_issue(issue_meta, message: with_doc(message, rules_doc, loop), trigger: trigger, line_no: line)
    end)
  end

  defp with_doc(message, nil, loop), do: "#{message} Only #{inspect(loop)} runs the loop."
  defp with_doc(message, doc, loop), do: "#{with_doc(message, nil, loop)} See #{doc}."

  defp server_issues(references) do
    for {module, _function, line} <- references, module in @mcp_servers do
      {line, inspect(module), "#{inspect(module)} runs tools without the Tool Guard: never mount it."}
    end
  end

  defp prompt_module_issues(references) do
    for {module, _function, line} <- references, Code.within?(module, AshAi.Actions.Prompt) do
      {line, inspect(module), @prompt_message}
    end
  end

  # `import`, `apply`, `defdelegate` and passing the module around all hide
  # which function runs and with which options.
  defp loop_reference_issues(references) do
    Enum.flat_map(references, fn
      {AshAi.ToolLoop, function, _line} when function in [:run, :stream] ->
        []

      {AshAi.ToolLoop, :resume, line} ->
        [
          {line, "AshAi.ToolLoop.resume", "AshAi.ToolLoop.resume/3 passes `:approvals`, which skips the gate."}
        ]

      {AshAi.ToolLoop, function, line} ->
        [
          {line, "AshAi.ToolLoop", "call `AshAi.ToolLoop.run/2` or `stream/2` by name, not #{loop_name(function)}."}
        ]

      _reference ->
        []
    end)
  end

  defp loop_name(nil), do: "through the module"
  defp loop_name(function), do: "`#{function}`"

  defp loop_call_issues(ast) do
    for {AshAi.ToolLoop, function, args, line} when function in [:run, :stream] <- Code.calls(ast),
        not tools_off?(List.last(args)) do
      {line, "AshAi.ToolLoop.#{function}",
       "pass `tools: false` in a literal keyword list: left out, the loop exposes every domain tool unwrapped."}
    end
  end

  defp tools_off?(options), do: Keyword.keyword?(options) and Keyword.get(options, :tools) == false

  # Keyword pairs carry no line of their own: the enclosing call's line is
  # the nearest one, so the walk keeps it in the accumulator. A function's
  # head is skipped: `def prompt(model, opts)` calls nothing.
  defp option_issues(ast, loop?) do
    {_ast, {_line, issues}} =
      Macro.prewalk(ast, {1, []}, fn node, {line, issues} ->
        line = line(node) || line
        node = without_head(node)
        {node, {line, node_issues(node, line, loop?) ++ issues}}
      end)

    Enum.reverse(issues)
  end

  defp without_head({kind, meta, [_head | body]}) when kind in [:def, :defp, :defmacro, :defmacrop],
    do: {kind, meta, body}

  defp without_head(node), do: node

  defp line({_form, meta, _args}) when is_list(meta), do: meta[:line]
  defp line(_node), do: nil

  defp node_issues({:tools, true}, line, _loop?),
    do: [{line, "tools: true", "`tools: true` hands the model unwrapped tools."}]

  defp node_issues({:resources, true}, line, _loop?),
    do: [{line, "resources: true", "`resources: true` adds tools that are in no catalogue."}]

  defp node_issues({:prompt, _meta, args}, line, _loop?) when is_list(args), do: prompt_issues(args, line)

  defp node_issues({{:., _, [_module, :prompt]}, _meta, args}, line, _loop?), do: prompt_issues(args, line)

  defp node_issues({:tools, value}, line, true) when value != false,
    do: [{line, "tools:", "the tool loop takes `tools: false`, with the wrapped tools as `extra_tools`."}]

  defp node_issues(:approvals, line, true),
    do: [{line, "approvals", "never pass `:approvals` to AshAi.ToolLoop: it skips the gate."}]

  defp node_issues(:actions, line, true),
    do: [{line, "actions", "never pass `:actions` to AshAi.ToolLoop: domain tools run unwrapped."}]

  defp node_issues(:otp_app, line, true),
    do: [{line, "otp_app", "never pass `:otp_app` to AshAi.ToolLoop: domain tools run unwrapped."}]

  defp node_issues(_node, _line, _loop?), do: []

  # `prompt(model)` has no options; in `prompt(model, options)` they must be
  # a literal this check can read.
  defp prompt_issues([options], line) when is_list(options), do: prompt_option_issues(options, line)

  defp prompt_issues([_model], _line), do: []
  defp prompt_issues(args, line), do: args |> List.last() |> prompt_option_issues(line)

  defp prompt_option_issues(options, line) do
    if Keyword.keyword?(options) and not Enum.any?(options, &tools_option?/1),
      do: [],
      else: [{line, "prompt", @prompt_message}]
  end

  defp tools_option?({:tools, false}), do: false
  defp tools_option?({:extra_tools, []}), do: false
  defp tools_option?({option, _value}), do: option in [:tools, :extra_tools]
end
