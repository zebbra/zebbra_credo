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
      |> literal_ast()
      |> actor_pairs()
      |> Enum.reject(fn {call_line, pair_line} ->
        Code.system_comment_above?(lines, call_line) or Code.system_comment_above?(lines, pair_line)
      end)
      |> Enum.map(fn {_call_line, pair_line} -> issue_for(issue_meta, pair_line) end)
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

  # Literals keep their line only when the parser wraps them in blocks.
  defp literal_ast(source_file) do
    case Elixir.Code.string_to_quoted(SourceFile.source(source_file),
           literal_encoder: &{:ok, {:__block__, &2, [&1]}},
           token_metadata: true
         ) do
      {:ok, ast} -> ast
      _error -> nil
    end
  end

  defp actor_pairs(ast) do
    {_ast, pairs} =
      Macro.prewalk(ast, [], fn
        {call, meta, args} = node, acc when is_list(args) and call != :__block__ ->
          {node, pairs(args, meta[:line]) ++ acc}

        node, acc ->
          {node, acc}
      end)

    pairs |> Enum.uniq() |> Enum.sort_by(&elem(&1, 1))
  end

  defp pairs(args, call_line) do
    for keyword <- Enum.map(args, &unwrap/1),
        is_list(keyword),
        {{:__block__, meta, [:actor]}, value} <- keyword,
        not match?({:__block__, _, [nil]}, value),
        do: {call_line, meta[:line]}
  end

  defp unwrap({:__block__, _, [list]}) when is_list(list), do: list
  defp unwrap(other), do: other

  defp issue_for(issue_meta, line_no) do
    format_issue(issue_meta,
      message: "Pass `scope: scope` instead of `actor:`; an explicit actor replaces the scope's.",
      trigger: "actor",
      line_no: line_no
    )
  end
end
