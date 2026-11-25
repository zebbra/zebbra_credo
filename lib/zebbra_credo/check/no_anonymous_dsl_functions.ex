defmodule ZebbraCredo.Check.NoAnonymousDslFunctions do
  @moduledoc """
  Credo check: no anonymous functions (`fn` or `&`) as the argument of Ash DSL
  macros such as `change`, `run`, `prepare` and `validate`.
  """
  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [
      files: %{included: ["lib/"]},
      macros: [:run, :change, :prepare, :validate],
      allowed: []
    ],
    explanations: [
      check: """
      `change fn ... end`, `run &Mod.fun/2`, `prepare fn ...` and
      `validate fn ...` hide logic in anonymous functions that cannot be named,
      reused, tested or found. Put each in its own module and reference it:
      `change MyApp.Orders.Changes.Slugify` or `change {Module, opts}`.
      """,
      params: [
        files: "Files to check (Credo's `included`/`excluded` globs); defaults to `lib/`.",
        macros: "The DSL macros whose first argument must not be an anonymous function.",
        allowed: "File globs that may use anonymous functions in these macros."
      ]
    ]

  alias ZebbraCredo.Code

  @impl true
  def run(%SourceFile{} = source_file, params) do
    if Code.matches?(source_file.filename, Params.get(params, :allowed, __MODULE__)) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      macros = Params.get(params, :macros, __MODULE__)

      {_ast, issues} =
        source_file
        |> SourceFile.ast()
        |> Macro.prewalk([], fn
          {name, meta, [{kind, _, _} | _]} = node, acc when is_atom(name) and kind in [:fn, :&] ->
            {node, if(name in macros, do: [issue_for(issue_meta, name, meta[:line]) | acc], else: acc)}

          node, acc ->
            {node, acc}
        end)

      Enum.reverse(issues)
    end
  end

  defp issue_for(issue_meta, name, line_no) do
    format_issue(issue_meta,
      message: "Anonymous function in `#{name}`: move it into its own module and reference that.",
      trigger: to_string(name),
      line_no: line_no
    )
  end
end
