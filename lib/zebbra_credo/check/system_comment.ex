defmodule ZebbraCredo.Check.SystemComment do
  @moduledoc """
  Credo check: every `authorize?: false` (also `:authorize?, false`) has a
  `# system: <why>` comment in the comment lines right above it, saying
  why the call may skip the policies. With `policy_bypasses: true`, every
  policy `bypass` needs the same comment.
  """
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [include_tests: false, policy_bypasses: false],
    explanations: [
      check: """
      A call with `authorize?: false` skips every policy. Say why on the line
      above, starting with `# system:`:

          # system: the nightly purge runs without a user.
          QueryLog.purge_expired_rows(cutoff, authorize?: false)

      A policy `bypass` skips the policies below it the same way, so it needs
      the same comment when `policy_bypasses` is on.
      """,
      params: [
        include_tests: "Also check files under `test/`.",
        policy_bypasses: "Also require the comment above a `bypass` inside `policies do ... end`."
      ]
    ]

  alias ZebbraCredo.Code, as: Helper

  @impl true
  def run(%SourceFile{} = source_file, params) do
    if skip?(source_file, params) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      lines = Helper.line_map(source_file)

      source_file
      |> unauthorized_lines()
      |> Enum.concat(bypass_lines(source_file, params))
      |> Enum.uniq()
      |> Enum.reject(fn {line_no, _kind} -> Helper.system_comment_above?(lines, line_no) end)
      |> Enum.map(&issue_for(issue_meta, &1))
    end
  end

  defp skip?(source_file, params) do
    not Params.get(params, :include_tests, __MODULE__) and
      Regex.match?(~r{(^|/)test/}, source_file.filename)
  end

  defp unauthorized_lines(source_file) do
    source_file |> Credo.Code.to_tokens() |> authorize_false_lines()
  end

  defp authorize_false_lines([{:kw_identifier, {line, _, _}, :authorize?}, {false, _} | rest]),
    do: [{line, :authorize} | authorize_false_lines(rest)]

  defp authorize_false_lines([{:atom, {line, _, _}, :authorize?}, {:",", _}, {false, _} | rest]),
    do: [{line, :authorize} | authorize_false_lines(rest)]

  defp authorize_false_lines([_token | rest]), do: authorize_false_lines(rest)
  defp authorize_false_lines([]), do: []

  defp bypass_lines(source_file, params) do
    if Params.get(params, :policy_bypasses, __MODULE__) do
      source_file |> SourceFile.ast() |> policy_bypasses()
    else
      []
    end
  end

  defp policy_bypasses(ast) do
    {_ast, lines} =
      Macro.prewalk(ast, [], fn
        {:policies, _, [[do: body]]} = node, acc -> {node, bypasses_in(body) ++ acc}
        node, acc -> {node, acc}
      end)

    Enum.reverse(lines)
  end

  defp bypasses_in(body) do
    {_ast, lines} =
      Macro.prewalk(body, [], fn
        {:bypass, meta, [_ | _]} = node, acc -> {node, [{meta[:line], :bypass} | acc]}
        node, acc -> {node, acc}
      end)

    lines
  end

  defp issue_for(issue_meta, {line_no, :authorize}) do
    format_issue(issue_meta,
      message: "`authorize?: false` needs a `# system: <why>` comment on the line above.",
      trigger: "authorize?",
      line_no: line_no
    )
  end

  defp issue_for(issue_meta, {line_no, :bypass}) do
    format_issue(issue_meta,
      message: "A policy `bypass` needs a `# system: <why>` comment on the line above.",
      trigger: "bypass",
      line_no: line_no
    )
  end
end
