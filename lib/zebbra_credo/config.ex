defmodule ZebbraCredo.Config do
  @moduledoc """
  Turns the plugin params into the checks to enable and merges them into the
  checks a project's `.credo.exs` enables.
  """

  alias ZebbraCredo.Check
  alias ZebbraCredo.Presets.ForbiddenCalls

  @defaults [
    Check.SystemComment,
    Check.AshEntryPoints,
    Check.RawSql,
    Check.ForbiddenCalls,
    Check.AssignInRender,
    Check.EnumKernel,
    Check.NoAnonymousDslFunctions,
    Check.ScopeNotActor
  ]

  @doc """
  The default-enabled checks with their params derived from the plugin params,
  without `except_checks:`, plus the checks listed in `checks:`. Raises
  `ArgumentError` on a missing `app:` or an unknown `except:` key.
  """
  @spec house_checks(keyword()) :: [{module(), keyword()}]
  def house_checks(params) do
    app_params = app_params(params)
    except = except(params)
    extra = Keyword.get(params, :checks, [])
    checks = Enum.uniq(@defaults ++ Keyword.keys(extra)) -- Keyword.get(params, :except_checks, [])

    for check <- checks do
      derived = Keyword.take(app_params, check.param_names())
      derived = if check == Check.ForbiddenCalls and except != [], do: derived ++ [except: except], else: derived

      {check, Keyword.merge(derived, Keyword.get(extra, check, []))}
    end
  end

  @doc """
  Merges the house checks into a project's enabled checks: the project's params
  win over the house params, and a project's `false` stays `false`.
  """
  @spec merge([{module(), keyword() | false}], keyword()) :: [{module(), keyword() | false}]
  def merge(enabled, params) do
    house = house_checks(params)

    merged =
      Enum.map(enabled, fn
        {check, false} -> {check, false}
        {check, own} -> {check, Keyword.merge(Keyword.get(house, check, []), own)}
      end)

    merged ++ Enum.reject(house, fn {check, _params} -> Keyword.has_key?(enabled, check) end)
  end

  defp app_params(params) do
    case Keyword.get(params, :app) do
      app when is_atom(app) and app not in [nil, true, false] ->
        [app: app] ++ Keyword.take(params, [:web, :repo])

      other ->
        raise ArgumentError, "the ZebbraCredo plugin needs `app:`, the app's root module, got: #{inspect(other)}"
    end
  end

  defp except(params) do
    except = Keyword.get(params, :except, [])

    case except -- ForbiddenCalls.keys() do
      [] ->
        except

      unknown ->
        raise ArgumentError,
              "unknown ZebbraCredo `except:` key(s) #{inspect(unknown)}; valid keys: #{inspect(ForbiddenCalls.keys())}"
    end
  end
end
