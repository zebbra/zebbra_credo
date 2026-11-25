defmodule ZebbraCredo.Check.ScopeNotActor do
  @moduledoc """
  Credo check: the web layer passes `scope: scope` to actions and code
  interfaces, never `actor:`. `actor: nil` and a `# system: <why>` comment
  above the pair are allowed.
  """
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [app: nil, web: nil],
    explanations: [
      check: """
      Explicit options beat the scope, so `scope: scope, actor: user` silently
      replaces the scope's actor. Pass `scope: scope` and nothing else.

      Trusted system code with no user may pass `actor:` with a comment above:

          # system: the nightly purge runs without a user.
          Orders.purge(actor: system_actor)

      `actor: nil` is allowed. Only files under the app's web directory are
      checked, never `test/`.
      """,
      params: [
        app: "The app's root module; its web directory is the only place checked.",
        web: "The app's web namespace when it is not `<app>Web`."
      ]
    ]

  alias ZebbraCredo.App
  alias ZebbraCredo.Code

  @impl true
  def run(%SourceFile{} = source_file, params) do
    if checked?(source_file.filename, params) do
      issue_meta = IssueMeta.for(source_file, params)
      lines = Code.line_map(source_file)

      source_file
      |> SourceFile.ast()
      |> actor_lines()
      |> Enum.reject(&Code.system_comment_above?(lines, &1))
      |> Enum.map(&issue_for(issue_meta, &1))
    else
      []
    end
  end

  defp checked?(filename, params) do
    web = Params.get(params, :web, __MODULE__)

    web_lib =
      case Params.get(params, :app, __MODULE__) do
        nil -> web && App.new(web, web: web).web_lib
        app -> App.new(app, web: web).web_lib
      end

    web_lib != nil and not Regex.match?(~r{(^|/)test/}, filename) and
      Regex.match?(~r{(^|/)#{Regex.escape(web_lib)}/}, filename)
  end

  defp actor_lines(ast) do
    {_ast, lines} =
      Macro.prewalk(ast, [], fn
        {_call, meta, args} = node, acc when is_list(args) -> {node, pairs(args, meta[:line]) ++ acc}
        node, acc -> {node, acc}
      end)

    lines |> Enum.uniq() |> Enum.sort()
  end

  defp pairs(args, call_line) do
    for keyword <- args,
        is_list(keyword),
        {:actor, value} <- keyword,
        value != nil,
        do: line_of(value) || call_line
  end

  defp line_of({_, meta, _}) when is_list(meta), do: meta[:line]
  defp line_of(_), do: nil

  defp issue_for(issue_meta, line_no) do
    format_issue(issue_meta,
      message: "Pass `scope: scope` instead of `actor:`; an explicit actor replaces the scope's.",
      trigger: "actor",
      line_no: line_no
    )
  end
end
