defmodule ZebbraCredo.Presets.ForbiddenCallsTest do
  use ExUnit.Case, async: true

  alias ZebbraCredo.Presets.ForbiddenCalls

  @app ZebbraCredo.App.new(MyApp)

  defp rules(key), do: ForbiddenCalls.rules(@app, ForbiddenCalls.keys() -- [key])

  defp rule(key, module), do: key |> rules() |> Enum.find(&(&1[:module] == module))

  test "keys" do
    assert ForbiddenCalls.keys() ==
             [
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
  end

  test "token_resource stays out of the web" do
    assert [rule] = rules(:token_resource)
    assert rule[:module] == AshAuthentication.TokenResource
    assert rule[:functions] == :all
    assert rule[:only] == ["lib/my_app_web/**"]
    assert rule[:message] == "tokens are revoked and checked through MyApp.Accounts"
  end

  test "oban_run_trigger" do
    assert [rule] = rules(:oban_run_trigger)
    assert rule[:module] == AshOban
    assert rule[:functions] == [:run_trigger]
    assert rule[:message] == "use `change run_oban_trigger` in the action"
  end

  test "pubsub_door is three rules" do
    assert [door, endpoint, pub_sub] = rules(:pubsub_door)

    assert door[:module] == Phoenix.PubSub
    assert door[:functions] == :all
    assert door[:allowed] == ["lib/my_app/pub_sub.ex"]
    assert door[:message] == "use the domain's subscribe_*/broadcast_* functions (MyApp.PubSub)"

    assert endpoint[:module] == MyAppWeb.Endpoint
    assert endpoint[:functions] == [:subscribe]
    assert endpoint[:only] == ["lib/my_app_web/**"]
    assert endpoint[:message] == "subscribe through the domain's `subscribe_*(scope)`"

    assert pub_sub[:module] == MyApp.PubSub
    assert pub_sub[:functions] == :all
    assert pub_sub[:only] == ["lib/my_app_web/**"]
    assert pub_sub[:message] == endpoint[:message]
  end

  test "logger" do
    assert [rule] = rules(:logger)
    assert rule[:module] == Logger
    assert rule[:functions] == [:info, :notice, :warning, :warn, :error, :critical, :alert, :emergency, :log, :bare_log]

    assert rule[:allowed] ==
             ["lib/**/log_subscriber.ex", "lib/my_app/telemetry/**", "lib/my_app_web/**", "lib/mix/**"]

    assert rule[:message] == "emit a telemetry event and log it in the subsystem's LogSubscriber"
  end

  test "clock is five rules, allowed in LocalTime" do
    assert length(rules(:clock)) == 5
    assert rule(:clock, Date)[:functions] == [:utc_today]
    assert rule(:clock, Date)[:message] == "use MyApp.LocalTime.today/0"
    assert rule(:clock, DateTime)[:functions] == [:now, :now!, :utc_now]
    assert rule(:clock, DateTime)[:message] == "use MyApp.LocalTime (utc_now/0 for timestamps)"
    assert rule(:clock, NaiveDateTime)[:functions] == [:local_now, :utc_now]
    assert rule(:clock, Time)[:functions] == [:utc_now]
    assert rule(:clock, System)[:functions] == [:system_time, :os_time]

    for rule <- rules(:clock) do
      assert rule[:allowed] == ["lib/my_app/local_time.ex"]
      assert is_binary(rule[:message])
    end

    assert rule(:clock, Time)[:message] == "use MyApp.LocalTime"
  end

  test "http_door is three rules" do
    assert length(rules(:http_door)) == 3

    for module <- [Req, Finch, Mint.HTTP] do
      rule = rule(:http_door, module)
      assert rule[:functions] == :all
      assert rule[:allowed] == ["lib/my_app/http.ex", "lib/my_app/http/**"]
    end

    assert rule(:http_door, Req)[:message] ==
             "reach an external service through its client module (attach MyApp.HTTP)"

    assert rule(:http_door, Finch)[:message] == "outgoing HTTP goes through MyApp.HTTP"
    assert rule(:http_door, Mint.HTTP)[:message] == "outgoing HTTP goes through MyApp.HTTP"
  end

  test "decimal_from_float" do
    assert [rule] = rules(:decimal_from_float)
    assert rule[:module] == Decimal
    assert rule[:functions] == [:from_float]
    assert rule[:message] == "amounts/hours are exact: Decimal.new/1 from a string or an integer"
  end

  test "aes_ctr" do
    assert [rule] = rules(:aes_ctr)
    assert rule[:module] == Cloak.Ciphers.AES.CTR
    assert rule[:functions] == :all
    assert rule[:message] == "use Cloak.Ciphers.AES.GCM: AES-CTR does not authenticate the ciphertext"
  end

  test "mdex_to_heex" do
    assert [rule] = rules(:mdex_to_heex)
    assert rule[:module] == MDEx
    assert rule[:functions] == [:to_heex, :to_heex!]
    assert rule[:message] == "never to_heex on model output: it evaluates text as a template"
  end

  test "a web override changes the web paths and namespace" do
    app = ZebbraCredo.App.new(MyApp, web: MyApp.Web)
    rules = ForbiddenCalls.rules(app, ForbiddenCalls.keys() -- [:pubsub_door])
    assert Enum.at(rules, 1)[:module] == MyApp.Web.Endpoint
    assert Enum.at(rules, 1)[:only] == ["lib/my_app/web/**"]
  end

  test "except drops a key" do
    rules = ForbiddenCalls.rules(ZebbraCredo.App.new(MyApp), [:clock])
    refute Enum.any?(rules, &(&1[:module] in [Date, DateTime, NaiveDateTime, Time, System]))
  end

  test "unknown_except_key_raises" do
    assert_raise ArgumentError, ~r/:clok.*:clock/s, fn ->
      ForbiddenCalls.rules(ZebbraCredo.App.new(MyApp), [:clok])
    end
  end
end
