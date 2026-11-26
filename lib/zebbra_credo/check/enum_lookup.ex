defmodule ZebbraCredo.Check.EnumLookup do
  @moduledoc """
  Credo check: an enum is matched by its own functions. `Mod.values()` searched
  by comparing `to_string` hand-rolls `Mod.match/1`, and a string turned into an
  atom for `Mod.label/1`, `description/1` or `meta/1` repeats what they do.
  """
  use Credo.Check,
    base_priority: :high,
    category: :refactor,
    param_defaults: [files: %{included: ["lib/"]}],
    explanations: [
      check: """
      Every `Ash.Type.Enum` has `match/1` (`{:ok, value} | :error`) and
      `match?/1`, and the enum kernel's `label/1`, `description/1` and
      `meta/1` take a string as well as an atom:

          case Status.match(order.status) do
            {:ok, status} -> Status.label(status)
            :error -> order.status
          end

          Status.label(status)
      """,
      params: [
        files: "Files to check (Credo's `included`/`excluded` globs); defaults to `lib/`."
      ]
    ]

  @searches [:find, :any?, :member?, :filter, :find_value]
  @texts [:label, :description, :meta]
  @to_atom [:to_existing_atom, :to_atom]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    {_ast, lines} = Macro.prewalk(SourceFile.ast(source_file), [], &collect/2)

    lines
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(fn {line, message} -> format_issue(issue_meta, message: message, line_no: line) end)
  end

  # Enum.find(Mod.values(), &(to_string(&1) == value)), plain or piped.
  defp collect({{:., _, [{:__aliases__, _, [:Enum]}, search]}, meta, [values, fun]} = node, acc)
       when search in @searches do
    {node, if(values?(values) and stringifies?(fun), do: [{meta[:line], match()} | acc], else: acc)}
  end

  defp collect({:|>, meta, [values, {{:., _, [{:__aliases__, _, [:Enum]}, search]}, _, [fun]}]} = node, acc)
       when search in @searches do
    {node, if(values?(values) and stringifies?(fun), do: [{meta[:line], match()} | acc], else: acc)}
  end

  # Mod.label(String.to_existing_atom(value)), plain or piped.
  defp collect({{:., _, [{:__aliases__, _, _}, text]}, meta, [arg | _]} = node, acc) when text in @texts do
    {node, if(to_atom?(arg), do: [{meta[:line], text(text)} | acc], else: acc)}
  end

  defp collect({:|>, meta, [left, {{:., _, [{:__aliases__, _, _}, text]}, _, _args}]} = node, acc)
       when text in @texts do
    {node, if(to_atom?(last_stage(left)), do: [{meta[:line], text(text)} | acc], else: acc)}
  end

  defp collect(node, acc), do: {node, acc}

  defp values?({{:., _, [{:__aliases__, _, _}, :values]}, _, []}), do: true
  defp values?(_ast), do: false

  defp stringifies?(fun) do
    {_ast, found?} =
      Macro.prewalk(fun, false, fn
        {:to_string, _, [_]} = node, _found -> {node, true}
        {{:., _, [{:__aliases__, _, [:Atom]}, :to_string]}, _, _} = node, _found -> {node, true}
        node, found -> {node, found}
      end)

    found?
  end

  defp to_atom?({{:., _, [{:__aliases__, _, [:String]}, function]}, _, _args}), do: function in @to_atom
  defp to_atom?(_ast), do: false

  defp last_stage({:|>, _, [_left, right]}), do: right
  defp last_stage(ast), do: ast

  defp match, do: "Match an enum value with the enum's `match/1` or `match?/1`, not by comparing `to_string`."

  defp text(function), do: "`#{function}/1` takes the string as it is: no atom conversion."
end
