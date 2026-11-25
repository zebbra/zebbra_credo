defmodule ZebbraCredo.AddChecks do
  @moduledoc false

  use Credo.Execution.Task

  alias ZebbraCredo.Config

  @params [:app, :web, :repo, :except, :except_checks, :checks]

  # Runs after the project config is merged, so `checks` has one shape whatever format the project used.
  def call(%Execution{checks: %{enabled: enabled} = checks} = exec, _opts) do
    params =
      for key <- @params, value = Execution.get_plugin_param(exec, ZebbraCredo, key), value != nil, do: {key, value}

    %{exec | checks: %{checks | enabled: Config.merge(enabled, params)}}
  end
end
