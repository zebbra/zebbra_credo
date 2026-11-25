defmodule ZebbraCredo.Check.AssignInRender do
  @moduledoc """
  Credo check: a LiveView's or LiveComponent's `render/1` assigns nothing — no
  `assign`, `assign_new` or `update` — so a patch re-renders only what changed.
  """
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [app: nil, web: nil],
    explanations: [
      check: """
      An assign made in a LiveView's or LiveComponent's `render/1` counts as
      changed on every render, so every patch re-renders whatever reads it: a
      whole table, if its rows do. Compute the value where its inputs change
      (`mount`, `handle_params`, `handle_event`, `update`) or read it in the
      template:

          hidden_columns={Map.get(@collection_hidden_columns, @collection_id, [])}

      Function components assign as usual; this check reads only `render/1`.
      """,
      params: [
        app: "The app's root module; its web module is where `use <Web>, :live_view` is recognised.",
        web: "The app's web namespace when it is not `<app>Web`."
      ]
    ]

  alias ZebbraCredo.App
  alias ZebbraCredo.Code

  @kinds [:live_view, :live_component]
  @uses [Phoenix.LiveView, Phoenix.LiveComponent]
  @assigns [:assign, :assign_new, :update]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    web = web(params)

    {_ast, issues} =
      Macro.prewalk(SourceFile.ast(source_file), [], fn
        {:defmodule, _meta, [_name, [do: body]]} = node, acc ->
          {node, acc ++ module_issues(statements(body), web, issue_meta)}

        node, acc ->
          {node, acc}
      end)

    issues
  end

  defp module_issues(statements, web, issue_meta) do
    if Enum.any?(statements, &live?(&1, web)) do
      for {kind, _, [{:render, _, [_assigns]}, [do: body]]} <- statements,
          kind in [:def, :defp],
          line <- assign_lines(body),
          do: issue_for(issue_meta, line)
    else
      []
    end
  end

  defp statements({:__block__, _meta, statements}), do: statements
  defp statements(statement), do: [statement]

  defp web(params) do
    web = Params.get(params, :web, __MODULE__)

    case Params.get(params, :app, __MODULE__) do
      nil -> web
      app -> App.new(app, web: web).web
    end
  end

  defp live?({:use, _, [{:__aliases__, _, parts}, kind]}, web) when kind in @kinds and not is_nil(web),
    do: Code.resolve(parts, %{}) == web

  defp live?({:use, _, [{:__aliases__, _, parts} | _opts]}, _web), do: Code.resolve(parts, %{}) in @uses
  defp live?(_statement, _web), do: false

  defp assign_lines(body) do
    {_ast, lines} =
      Macro.prewalk(body, [], fn
        {function, meta, args} = node, acc when function in @assigns and is_list(args) ->
          {node, [meta[:line] | acc]}

        {{:., _, [{:__aliases__, _, [:Phoenix, :Component]}, function]}, meta, _args} = node, acc
        when function in @assigns ->
          {node, [meta[:line] | acc]}

        node, acc ->
          {node, acc}
      end)

    lines |> Enum.uniq() |> Enum.sort()
  end

  defp issue_for(issue_meta, line_no) do
    format_issue(issue_meta,
      message: "`render/1` assigns, so every patch re-renders what reads it: assign where the inputs change.",
      trigger: "render",
      line_no: line_no
    )
  end
end
