defmodule ZebbraCredo do
  @moduledoc """
  zebbra's Credo checks for Elixir apps built on Ash and Phoenix.

  As a Credo plugin, it enables the house checks with one line in `.credo.exs`:

      plugins: [{ZebbraCredo, app: MyApp}]

  Params:

    * `app:` (required) - the app's root module; the checks derive `MyAppWeb`,
      `lib/my_app/` and `lib/my_app_web/` from it.
    * `web:` - the web namespace, when it is not `<app>Web`.
    * `repo:` - the Ecto repo, when it is not `<app>.Repo`.
    * `except:` - `ZebbraCredo.Presets.ForbiddenCalls` keys whose rules to drop.
    * `except_checks:` - checks the plugin adds to switch off; a check the
      project lists itself is switched off with `{check, false}`.
    * `checks:` - `{check, params}` tuples that add params to a check or turn on
      an opt-in check such as `ZebbraCredo.Check.AshAiToolGuard`.

  A check the project lists in its own `checks:` keeps the project's params and
  gets `app:` filled in; `{check, false}` keeps it off.
  """

  @doc false
  @spec init(Credo.Execution.t()) :: Credo.Execution.t()
  def init(exec), do: Credo.Plugin.prepend_task(exec, :validate_config, ZebbraCredo.AddChecks)
end
