defmodule ZebbraCredo.Check.NoAnonymousDslFunctions do
  @moduledoc """
  Credo check: no anonymous functions (`fn` or `&`) as the argument of Ash DSL
  macros such as `change`, `run`, `prepare` and `validate`. Only the Ash DSL is
  checked: a module that uses `Ash.Resource`, and `actions`, `changes`,
  `preparations` and `validations` blocks anywhere.
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

  @dsl_blocks [:actions, :changes, :preparations, :validations]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    if Code.matches?(source_file.filename, Params.get(params, :allowed, __MODULE__)) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      ast = SourceFile.ast(source_file)
      context = %{macros: Params.get(params, :macros, __MODULE__), aliases: Code.aliases(ast)}

      ast
      |> walk(false, context)
      |> Enum.map(fn {name, line} -> issue_for(issue_meta, name, line) end)
    end
  end

  defp walk({:defmodule, _, [_name, [do: body]]}, dsl?, context),
    do: walk(body, dsl? or resource?(body, context.aliases), context)

  defp walk({block, _, [[do: body]]}, _dsl?, context) when block in @dsl_blocks, do: walk(body, true, context)

  defp walk({name, meta, [first | _] = args}, true, context) when is_atom(name) do
    found = if name in context.macros and anonymous?(first), do: [{name, meta[:line]}], else: []
    found ++ walk(args, true, context)
  end

  defp walk({form, _meta, args}, dsl?, context), do: walk(form, dsl?, context) ++ walk(args, dsl?, context)
  defp walk({left, right}, dsl?, context), do: walk(left, dsl?, context) ++ walk(right, dsl?, context)
  defp walk(list, dsl?, context) when is_list(list), do: Enum.flat_map(list, &walk(&1, dsl?, context))
  defp walk(_leaf, _dsl?, _context), do: []

  defp resource?({:__block__, _, statements}, aliases), do: Enum.any?(statements, &resource?(&1, aliases))
  defp resource?({:use, _, [{:__aliases__, _, parts} | _]}, aliases), do: Code.resolve(parts, aliases) == Ash.Resource
  defp resource?(_statement, _aliases), do: false

  # `&1` is a placeholder in someone else's capture, not a function.
  defp anonymous?({:&, _, [n]}) when is_integer(n), do: false
  defp anonymous?({kind, _, _}), do: kind in [:fn, :&]
  defp anonymous?(_arg), do: false

  defp issue_for(issue_meta, name, line_no) do
    format_issue(issue_meta,
      message: "Anonymous function in `#{name}`: move it into its own module and reference that.",
      trigger: to_string(name),
      line_no: line_no
    )
  end
end
