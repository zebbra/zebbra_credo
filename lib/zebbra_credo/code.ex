defmodule ZebbraCredo.Code do
  @moduledoc """
  Helpers of the project's Credo checks: the module references of a source
  file with its aliases resolved, and file globs.
  """

  @typespec_attributes [:spec, :type, :typep, :opaque, :callback, :macrocallback]

  @doc """
  The module references in `ast`, each `{module, function | nil, line}`:
  a remote call names its function, a plain alias reference nil. Aliases
  (`alias A.B`, `alias A.B, as: C`, `alias A.{B, C}`) are resolved for the
  whole file; typespecs are skipped (they only name the data a function gets).
  """
  @spec references(Macro.t()) :: [{module(), atom() | nil, pos_integer()}]
  def references(ast) do
    aliases = aliases(ast)

    {_ast, references} =
      Macro.prewalk(ast, [], fn
        {:@, _meta, [{attribute, _, _}]}, acc when attribute in @typespec_attributes ->
          {nil, acc}

        {:alias, _meta, _args}, acc ->
          {nil, acc}

        {{:., _, [{:__aliases__, meta, parts}, function]}, _, _args} = node, acc
        when is_atom(function) ->
          {skip_call_target(node), [{resolve(parts, aliases), function, meta[:line]} | acc]}

        {:__aliases__, meta, parts}, acc ->
          {nil, [{resolve(parts, aliases), nil, meta[:line]} | acc]}

        node, acc ->
          {node, acc}
      end)

    references |> Enum.reject(&is_nil(elem(&1, 0))) |> Enum.reverse()
  end

  # Walks a call's arguments, not its target again (already recorded).
  defp skip_call_target({{:., _, [_target, _function]}, meta, args}), do: {:__block__, meta, args}

  @doc """
  The remote calls in `ast`, each `{module, function, args, line}`, aliases
  resolved. A piped call has its piped argument missing from `args`.
  """
  @spec calls(Macro.t()) :: [{module(), atom(), [Macro.t()], pos_integer()}]
  def calls(ast) do
    aliases = aliases(ast)

    {_ast, calls} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, meta, parts}, function]}, _, args} = node, acc
        when is_atom(function) and is_list(args) ->
          {node, [{resolve(parts, aliases), function, args, meta[:line]} | acc]}

        node, acc ->
          {node, acc}
      end)

    calls |> Enum.reject(&is_nil(elem(&1, 0))) |> Enum.reverse()
  end

  @doc "Whether `module` is `namespace` or a module under it."
  @spec within?(module(), module()) :: boolean()
  def within?(module, namespace) do
    name = inspect(module)
    name == inspect(namespace) or String.starts_with?(name, inspect(namespace) <> ".")
  end

  @doc "Whether the file path matches one of the globs (`*` within a segment, `**` across segments)."
  @spec matches?(String.t(), [String.t()]) :: boolean()
  def matches?(path, globs), do: Enum.any?(globs, &Regex.match?(glob_regex(&1), path))

  defp glob_regex(glob) do
    glob
    |> Regex.escape()
    |> String.replace("\\*\\*", ".*")
    |> String.replace("\\*", "[^/]*")
    |> then(&Regex.compile!("\\A" <> &1 <> "\\z"))
  end

  @doc "Short name => full name parts, from every alias form in `ast`."
  @spec aliases(Macro.t()) :: %{atom() => [atom() | Macro.t()]}
  def aliases(ast) do
    {_ast, aliases} =
      Macro.prewalk(ast, %{}, fn
        {:alias, _, [{:__aliases__, _, parts}]} = node, acc ->
          {node, Map.put(acc, List.last(parts), parts)}

        {:alias, _, [{:__aliases__, _, parts}, [as: {:__aliases__, _, [short]}]]} = node, acc ->
          {node, Map.put(acc, short, parts)}

        {:alias, _, [{{:., _, [{:__aliases__, _, base}, :{}]}, _, children}]} = node, acc ->
          {node, Enum.reduce(children, acc, &add_child(&1, base, &2))}

        node, acc ->
          {node, acc}
      end)

    aliases
  end

  defp add_child({:__aliases__, _, parts}, base, acc), do: Map.put(acc, List.last(parts), base ++ parts)

  defp add_child(_child, _base, acc), do: acc

  @doc "The module the alias parts name, or nil for `__MODULE__.Foo` and similar (not resolvable from the source)."
  @spec resolve([atom() | Macro.t()], map()) :: module() | nil
  def resolve([first | rest], aliases) do
    parts = Map.get(aliases, first, [first]) ++ rest
    if Enum.all?(parts, &is_atom/1), do: Module.concat(parts)
  end
end
