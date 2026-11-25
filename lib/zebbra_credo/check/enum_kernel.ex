defmodule ZebbraCredo.Check.EnumKernel do
  @moduledoc """
  Credo check: `use Ash.Type.Enum` only in the app's enum kernel (`kernel:`,
  default `<app lib>/type/enum.ex`) and the allowed files (`allowed:` globs).
  Every other enum is `use <App>.Type.Enum, values: [...]`.
  """
  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [app: nil, kernel: nil, allowed: []],
    explanations: [
      check: """
      Enums share one kernel module that wraps `Ash.Type.Enum` (labels,
      translations, shared options). Define each enum with
      `use <App>.Type.Enum, values: [...]`; only the kernel itself uses
      `Ash.Type.Enum`.
      """,
      params: [
        app: "The app's root module; the kernel is `<app>.Type.Enum` in `<app lib>/type/enum.ex`.",
        kernel: "The kernel's file path when it is not `<app lib>/type/enum.ex`.",
        allowed: "File globs that may `use Ash.Type.Enum` besides the kernel."
      ]
    ]

  alias ZebbraCredo.App
  alias ZebbraCredo.Code

  @impl true
  def run(%SourceFile{} = source_file, params) do
    app = app(params)
    kernel = Params.get(params, :kernel, __MODULE__) || (app && Path.join(app.lib, "type/enum.ex"))
    exempt = Enum.reject([kernel | Params.get(params, :allowed, __MODULE__)], &is_nil/1)

    if Code.matches?(source_file.filename, exempt) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      ast = SourceFile.ast(source_file)
      aliases = Code.aliases(ast)

      {_ast, issues} =
        Macro.prewalk(ast, [], fn
          {:use, meta, [{:__aliases__, _, parts} | _opts]} = node, acc ->
            {node, add_issue(acc, Code.resolve(parts, aliases), issue_meta, app, meta[:line])}

          node, acc ->
            {node, acc}
        end)

      Enum.reverse(issues)
    end
  end

  defp add_issue(issues, Ash.Type.Enum, issue_meta, app, line), do: [issue_for(issue_meta, app, line) | issues]
  defp add_issue(issues, _module, _issue_meta, _app, _line), do: issues

  defp app(params) do
    case Params.get(params, :app, __MODULE__) do
      nil -> nil
      app -> App.new(app)
    end
  end

  defp issue_for(issue_meta, app, line_no) do
    format_issue(issue_meta,
      message: "`use Ash.Type.Enum` outside the kernel: #{instead(app)}.",
      trigger: "Ash.Type.Enum",
      line_no: line_no
    )
  end

  defp instead(nil), do: "use the project's enum kernel"
  defp instead(app), do: "use #{inspect(Module.concat(app.module, Type.Enum))} instead"
end
