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
  `ArgumentError` on a missing `app:`, an unknown `except:` key or a param of
  the wrong shape.
  """
  @spec house_checks(keyword()) :: [{module(), keyword()}]
  def house_checks(params) do
    app_params = app_params(params)
    validate!(params)
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
    app = Keyword.get(params, :app)

    unless module?(app),
      do: invalid!(:app, "the app's root module, such as `MyApp` (not the OTP app name)", app)

    [app: app] ++ Keyword.take(params, [:web, :repo])
  end

  defp validate!(params) do
    for {key, example} <- [web: "MyAppWeb", repo: "MyApp.Repo"],
        Keyword.has_key?(params, key),
        not module?(params[key]),
        do: invalid!(key, "a module, such as `#{example}`", params[key])

    except = Keyword.get(params, :except, [])
    unless list_of_atoms?(except), do: invalid!(:except, "a list of preset keys", except)

    except_checks = Keyword.get(params, :except_checks, [])
    unless list_of_atoms?(except_checks), do: invalid!(:except_checks, "a list of check modules", except_checks)
    Enum.each(except_checks, &check!(:except_checks, &1))

    checks = Keyword.get(params, :checks, [])

    unless is_list(checks) and Enum.all?(checks, &check_entry?/1),
      do: invalid!(:checks, "a list of `{check, params}` tuples with keyword params", checks)

    Enum.each(checks, fn {check, _own} -> check!(:checks, check) end)
  end

  defp check_entry?({check, own}) when is_atom(check), do: Keyword.keyword?(own)
  defp check_entry?(_entry), do: false

  defp check!(key, module) do
    unless Code.ensure_loaded?(module) and function_exported?(module, :param_names, 0),
      do: raise(ArgumentError, "ZebbraCredo `#{key}:` names #{inspect(module)}, which is not a Credo check")
  end

  defp module?(value), do: is_atom(value) and String.starts_with?(Atom.to_string(value), "Elixir.")

  defp list_of_atoms?(value), do: is_list(value) and Enum.all?(value, &is_atom/1)

  defp invalid!(:app, expected, value),
    do: raise(ArgumentError, "the ZebbraCredo plugin needs `app:`, #{expected}, got: #{inspect(value)}")

  defp invalid!(key, expected, value),
    do: raise(ArgumentError, "ZebbraCredo `#{key}:` must be #{expected}, got: #{inspect(value)}")

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
