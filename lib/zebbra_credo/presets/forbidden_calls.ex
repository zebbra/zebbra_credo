defmodule ZebbraCredo.Presets.ForbiddenCalls do
  @moduledoc """
  The house `ZebbraCredo.Check.ForbiddenCalls` rules, derived from an
  `t:ZebbraCredo.App.t/0`. Each key names one rule or a group of related rules;
  `except:` of the check drops keys.
  """

  alias ZebbraCredo.App

  @keys [
    :token_resource,
    :oban_run_trigger,
    :pubsub_door,
    :logger,
    :clock,
    :http_door,
    :decimal_from_float,
    :aes_ctr,
    :mdex_to_heex
  ]

  @logger_functions [:info, :notice, :warning, :warn, :error, :critical, :alert, :emergency, :log, :bare_log]

  @doc "The rule keys that `rules/2` accepts in `except`."
  @spec keys() :: [atom()]
  def keys, do: @keys

  @doc "The preset's rules for `app`, without the rules of the `except` keys. Raises on an unknown key."
  @spec rules(App.t(), [atom()]) :: [keyword()]
  def rules(%App{} = app, except \\ []) do
    case except -- @keys do
      [] ->
        @keys |> Enum.reject(&(&1 in except)) |> Enum.flat_map(&rules_for(&1, app))

      unknown ->
        raise ArgumentError,
              "unknown ForbiddenCalls preset key(s) in except: #{inspect(unknown)}; valid keys: #{inspect(@keys)}"
    end
  end

  defp rules_for(:token_resource, app) do
    [
      [
        module: AshAuthentication.TokenResource,
        functions: :all,
        only: [web_glob(app)],
        message: "tokens are revoked and checked through #{inspect(app.module)}.Accounts"
      ]
    ]
  end

  defp rules_for(:oban_run_trigger, _app) do
    [[module: AshOban, functions: [:run_trigger], message: "use `change run_oban_trigger` in the action"]]
  end

  defp rules_for(:pubsub_door, app) do
    subscribe = "subscribe through the domain's `subscribe_*(scope)`"

    [
      [
        module: Phoenix.PubSub,
        functions: :all,
        allowed: [Path.join(app.lib, "pub_sub.ex"), Path.join(app.lib, "application.ex")],
        message: "use the domain's subscribe_*/broadcast_* functions (#{inspect(app.module)}.PubSub)"
      ],
      [module: Module.concat(app.web, Endpoint), functions: [:subscribe], only: [web_glob(app)], message: subscribe],
      [module: Module.concat(app.module, PubSub), functions: :all, only: [web_glob(app)], message: subscribe]
    ]
  end

  defp rules_for(:logger, app) do
    [
      [
        module: Logger,
        functions: @logger_functions,
        allowed: [
          "lib/**/log_subscriber.ex",
          Path.join(app.lib, "telemetry/**"),
          web_glob(app),
          "lib/mix/**"
        ],
        message: "emit a telemetry event and log it in the subsystem's LogSubscriber"
      ]
    ]
  end

  defp rules_for(:clock, app) do
    allowed = [Path.join(app.lib, "local_time.ex")]
    local_time = "#{inspect(app.module)}.LocalTime"

    for {module, functions, message} <- [
          {Date, [:utc_today], "use #{local_time}.today/0"},
          {DateTime, [:now, :now!, :utc_now], "use #{local_time} (utc_now/0 for timestamps)"},
          {NaiveDateTime, [:local_now, :utc_now], "use #{local_time}"},
          {Time, [:utc_now], "use #{local_time}"},
          {System, [:system_time, :os_time], "use #{local_time}"}
        ] do
      [module: module, functions: functions, allowed: allowed, message: message]
    end
  end

  defp rules_for(:http_door, app) do
    allowed = [Path.join(app.lib, "http.ex"), Path.join(app.lib, "http/**")]
    http = "#{inspect(app.module)}.HTTP"

    for {module, message} <- [
          {Req, "reach an external service through its client module (attach #{http})"},
          {Finch, "outgoing HTTP goes through #{http}"},
          {Mint.HTTP, "outgoing HTTP goes through #{http}"}
        ] do
      [module: module, functions: :all, allowed: allowed, message: message]
    end
  end

  defp rules_for(:decimal_from_float, _app) do
    [
      [
        module: Decimal,
        functions: [:from_float],
        message: "amounts/hours are exact: Decimal.new/1 from a string or an integer"
      ]
    ]
  end

  defp rules_for(:aes_ctr, _app) do
    [
      [
        module: Cloak.Ciphers.AES.CTR,
        functions: :all,
        message: "use Cloak.Ciphers.AES.GCM: AES-CTR does not authenticate the ciphertext"
      ]
    ]
  end

  defp rules_for(:mdex_to_heex, _app) do
    [
      [
        module: MDEx,
        functions: [:to_heex, :to_heex!],
        message: "never to_heex on model output: it evaluates text as a template"
      ]
    ]
  end

  defp web_glob(app), do: Path.join(app.web_lib, "**")
end
