defmodule ZebbraCredo.Check.ForbiddenCalls do
  @moduledoc """
  Credo check: calls (or any use) of modules that only some files may make.
  Each rule is a keyword list: `module:`, `functions:` (a list, or `:all`
  for any reference to the module or a module under it), `except:` (modules
  a `:all` rule leaves out, with the modules under them), `allowed:` (file
  globs that may use it), `only:` (file globs the rule applies to; default
  every file) and `message:` (why, and what to use instead).

  With `app:` the house rules of `ZebbraCredo.Presets.ForbiddenCalls` apply
  first; `rules:` adds the project's own.
  """
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [files: %{included: ["lib/"]}, app: nil, web: nil, except: [], rules: []],
    explanations: [
      check: """
      Some modules and functions belong to one place: the token resource and
      direct PubSub subscriptions stay out of the web, `AshOban.run_trigger` is
      replaced by `change run_oban_trigger`, only LogSubscribers log, the clock
      is read in one module and HTTP leaves through one door. The rules name the
      module, the functions and the files allowed to use them.
      """,
      params: [
        files: "Files to check (Credo's `included`/`excluded` globs); defaults to `lib/`.",
        app: "The app's root module; turns on the house rules. Without it only `rules:` apply.",
        web: "The app's web namespace when it is not `<app>Web`.",
        except: "Keys of the house rules to leave out, see `ZebbraCredo.Presets.ForbiddenCalls.keys/0`.",
        rules:
          "The project's own rules, added to the house rules: `[module:, functions:, except:, allowed:, only:, message:]` each."
      ]
    ]

  alias ZebbraCredo.App
  alias ZebbraCredo.Code
  alias ZebbraCredo.Presets

  @impl true
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    path = source_file.filename
    rules = Enum.filter(rules(params), &applies?(&1, path))

    if rules == [] do
      []
    else
      references = source_file |> SourceFile.ast() |> Code.references()

      for rule <- rules,
          {module, function, line} <- references,
          forbidden?(rule, module, function),
          uniq: true,
          do: issue_for(issue_meta, rule, module, function, line)
    end
  end

  defp rules(params) do
    own = Params.get(params, :rules, __MODULE__)

    case Params.get(params, :app, __MODULE__) do
      nil ->
        own

      app ->
        web = Params.get(params, :web, __MODULE__)
        except = Params.get(params, :except, __MODULE__)
        Presets.ForbiddenCalls.rules(App.new(app, web: web), except) ++ own
    end
  end

  defp applies?(rule, path) do
    Code.matches?(path, Keyword.get(rule, :only, ["**"])) and
      not Code.matches?(path, Keyword.get(rule, :allowed, []))
  end

  defp forbidden?(rule, module, function) do
    case Keyword.fetch!(rule, :functions) do
      :all -> Code.within?(module, Keyword.fetch!(rule, :module)) and not excepted?(rule, module)
      functions -> module == Keyword.fetch!(rule, :module) and function in functions
    end
  end

  defp excepted?(rule, module), do: rule |> Keyword.get(:except, []) |> Enum.any?(&Code.within?(module, &1))

  defp issue_for(issue_meta, rule, module, function, line) do
    name = if function, do: "#{inspect(module)}.#{function}", else: inspect(module)

    format_issue(issue_meta,
      message: "#{name} is not allowed here: #{Keyword.fetch!(rule, :message)}",
      trigger: name,
      line_no: line
    )
  end
end
