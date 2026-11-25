defmodule ZebbraCredo.Check.RawSql do
  @moduledoc """
  Credo check: raw SQL and plain Ecto (`Ecto.Query`, `Ecto.Adapters.SQL`,
  `Postgrex`, the repo's query functions), a resource's `custom_statements` and
  table names in `fragment(...)` only in the allowed files (`allowed:` globs).
  They bypass Ash and its policies.
  """
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [app: nil, repo: nil, allowed: [], repo_functions: [:all_tenants]],
    explanations: [
      check: """
      Use an Ash action or expression. Where Ash cannot express it, add the
      file to the check's `allowed:` list with a comment saying why.
      """,
      params: [
        app: "The app's root module; its repo defaults to `<app>.Repo`.",
        repo:
          "The repo; its functions besides transaction/rollback/in_transaction? and `repo_functions:` send queries.",
        allowed: "File globs that may send raw SQL.",
        repo_functions: "Repo functions that are not raw SQL."
      ]
    ]

  alias ZebbraCredo.App
  alias ZebbraCredo.Code

  # Ecto.Query with the modules under it; the SQL adapter and Postgrex themselves.
  @sql_namespaces [Ecto.Query]
  @sql_modules [Ecto.Adapters.SQL, Postgrex]
  @repo_without_sql [:transaction, :rollback, :in_transaction?]

  # A table named in a fragment (FROM/JOIN/INTO/UPDATE followed by a name, not an interpolation).
  @fragment_table ~r/\b(?:FROM|JOIN|INTO|UPDATE)\s+[a-z_"]/i

  @impl true
  def run(%SourceFile{} = source_file, params) do
    if Code.matches?(source_file.filename, Params.get(params, :allowed, __MODULE__)) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      ast = SourceFile.ast(source_file)
      repo = repo(params)
      without_sql = @repo_without_sql ++ Params.get(params, :repo_functions, __MODULE__)

      calls =
        for {module, function, line} <- Code.references(ast),
            sql?(module, function, repo, without_sql),
            uniq: true,
            do: issue_for(issue_meta, module, function, line)

      calls ++ statement_issues(ast, issue_meta) ++ fragment_issues(ast, issue_meta)
    end
  end

  defp repo(params) do
    case {Params.get(params, :repo, __MODULE__), Params.get(params, :app, __MODULE__)} do
      {nil, nil} -> nil
      {nil, app} -> App.new(app).repo
      {repo, _app} -> repo
    end
  end

  defp sql?(module, function, repo, without_sql) do
    Enum.any?(@sql_namespaces, &Code.within?(module, &1)) or module in @sql_modules or
      (module == repo and function != nil and function not in without_sql)
  end

  defp statement_issues(ast, issue_meta) do
    {_ast, lines} =
      Macro.prewalk(ast, [], fn
        {:custom_statements, meta, _args} = node, lines -> {node, [meta[:line] | lines]}
        node, lines -> {node, lines}
      end)

    for line <- Enum.reverse(lines) do
      format_issue(issue_meta,
        message: "custom_statements run raw SQL: add the file to the check's `allowed:` list with the reason.",
        trigger: "custom_statements",
        line_no: line
      )
    end
  end

  defp fragment_issues(ast, issue_meta) do
    {_ast, lines} =
      Macro.prewalk(ast, [], fn
        {:fragment, meta, [sql | _args]} = node, acc ->
          if sql |> literal_pieces() |> Enum.any?(&Regex.match?(@fragment_table, &1)),
            do: {node, [meta[:line] | acc]},
            else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    for line <- Enum.reverse(lines) do
      format_issue(issue_meta,
        message: "A table named in a fragment bypasses Ash and its policies: use an Ash expression.",
        trigger: "fragment",
        line_no: line
      )
    end
  end

  # The literal text of a string or `~s`/`~S` sigil; an interpolation splits it.
  defp literal_pieces(sql) when is_binary(sql), do: [sql]
  defp literal_pieces({:<<>>, _, pieces}), do: Enum.filter(pieces, &is_binary/1)

  defp literal_pieces({sigil, _, [string, _modifiers]}) when sigil in [:sigil_s, :sigil_S], do: literal_pieces(string)

  defp literal_pieces(_sql), do: []

  defp issue_for(issue_meta, module, function, line) do
    called = if function, do: "#{inspect(module)}.#{function}", else: inspect(module)

    format_issue(issue_meta,
      message: "#{called} sends raw SQL: use Ash, or add the file to the check's `allowed:` list.",
      trigger: called,
      line_no: line
    )
  end
end
