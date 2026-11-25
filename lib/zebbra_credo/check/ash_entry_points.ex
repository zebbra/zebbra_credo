defmodule ZebbraCredo.Check.AshEntryPoints do
  @moduledoc """
  Credo check: only Ash domains, resources, resource fragments, Ash callback
  modules (changes, preparations, validations, calculations, manual actions,
  generic action implementations, policy checks, tracers) and Spark verifiers compose
  Ash (`Ash.read`, `Ash.Query`, `Ash.Changeset`, `Ash.ActionInput`, `Ash.Seed`, ...).
  Other modules call a domain's code interface. The modules any module may use
  (introspection, types, errors, values) are listed in `@anywhere`.
  """
  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [files: %{included: ["lib/"]}],
    explanations: [
      check: """
      A LiveView, worker or other domain that builds an `Ash.Query` or
      `Ash.Changeset`, or calls `Ash.read/2` and friends itself, bypasses the
      domain's public interface. Define an action with arguments and a code
      interface on the domain instead, and call that.
      """,
      params: [
        files: "Files to check (Credo's `included`/`excluded` globs); defaults to `lib/`."
      ]
    ]

  alias ZebbraCredo.Code

  # Ash modules (with the modules under them) any module may use.
  @anywhere [
    Ash.Resource.Info,
    Ash.ToTenant,
    Ash.Scope,
    Ash.Error,
    Ash.Expr,
    Ash.TypedStruct,
    Ash.Type,
    # Union values (`%Ash.Union{type:, value:}`).
    Ash.Union,
    # Introspection.
    Ash.Domain.Info,
    Ash.Info,
    Ash.Policy.Info,
    Ash.Notifier.PubSub.Info,
    Ash.Signals.Graph,
    # The message a domain's `subscribe_*(scope)` delivers.
    Ash.Notifier.Notification,
    # Actor, tenant and context on a conn (ash_authentication_phoenix).
    Ash.PlugHelpers,
    # Values.
    Ash.UUID,
    Ash.CiString,
    Ash.NotLoaded
  ]

  # Any module may use these, but not the modules under them: record
  # metadata (`Ash.Resource.put_metadata/3`).
  @anywhere_exactly [Ash.Resource]

  # A module that uses (or declares the behaviour of) one of these composes Ash.
  @composers [
    Ash.Domain,
    Ash.Resource,
    Spark.Dsl.Fragment,
    Ash.Signals,
    Ash.Resource.Change,
    Ash.Resource.Preparation,
    Ash.Resource.Validation,
    Ash.Resource.Calculation,
    Ash.Resource.ManualRead,
    Ash.Resource.ManualCreate,
    Ash.Resource.ManualUpdate,
    Ash.Resource.ManualDestroy,
    Ash.Resource.ManualRelationship,
    Ash.Resource.Actions.Implementation,
    Ash.Policy.Check,
    Ash.Policy.SimpleCheck,
    Ash.Policy.FilterCheck,
    Ash.CustomExpression,
    Ash.Notifier,
    Ash.Tracer,
    Spark.Dsl.Verifier
  ]

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)

    for {name, body} <- source_file |> SourceFile.ast() |> modules(),
        not composer?(body),
        {module, function, line} <- Code.references(body),
        entry_point?(module),
        uniq: true,
        do: issue_for(issue_meta, name, module, function, line)
  end

  # Each `defmodule` with its own body (nested modules are listed on their own).
  defp modules(ast) do
    {_ast, modules} =
      Macro.prewalk(ast, [], fn
        {:defmodule, _, [{:__aliases__, _, parts}, [do: body]]} = node, acc ->
          {node, [{Macro.to_string({:__aliases__, [], parts}), without_nested(body)} | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(modules)
  end

  defp without_nested(body) do
    Macro.prewalk(body, fn
      {:defmodule, _, _} -> nil
      node -> node
    end)
  end

  defp composer?(body) do
    aliases = Code.aliases(body)

    {_ast, found?} =
      Macro.prewalk(body, false, fn
        {:use, _, [{:__aliases__, _, parts} | _rest]} = node, acc ->
          {node, acc or Code.resolve(parts, aliases) in @composers}

        {:@, _, [{:behaviour, _, [{:__aliases__, _, parts}]}]} = node, acc ->
          {node, acc or Code.resolve(parts, aliases) in @composers}

        node, acc ->
          {node, acc}
      end)

    found?
  end

  defp entry_point?(module) do
    Code.within?(module, Ash) and module not in @anywhere_exactly and
      not Enum.any?(@anywhere, &Code.within?(module, &1))
  end

  defp issue_for(issue_meta, name, module, function, line) do
    called = if function, do: "#{inspect(module)}.#{function}", else: inspect(module)

    format_issue(issue_meta,
      message: "#{name} uses #{called}: only domains, resources and Ash callback modules compose Ash.",
      trigger: called,
      line_no: line
    )
  end
end
