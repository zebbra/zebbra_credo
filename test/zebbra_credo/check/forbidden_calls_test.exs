defmodule ZebbraCredo.Check.ForbiddenCallsTest do
  use Credo.Test.Case

  alias ZebbraCredo.Check.ForbiddenCalls

  @rules [
    [module: MyApp.Repo, functions: :all, only: ["lib/my_app_web/**"], message: "use a domain"],
    [module: AshOban, functions: [:run_trigger], message: "use run_oban_trigger"],
    [
      module: Logger,
      functions: [:info, :warning],
      allowed: ["lib/**/log_subscriber.ex"],
      message: "emit telemetry"
    ]
  ]

  setup_all do
    Application.ensure_all_started(:credo)
    :ok
  end

  defp issues(source, path, params \\ [rules: @rules]) do
    source
    |> to_source_file(path)
    |> run_check(ForbiddenCalls, params)
  end

  defp preset_issues(source, path, params \\ []) do
    issues(source, path, Keyword.merge([app: MyApp], params))
  end

  test "flags a forbidden module in the files a rule applies to, also through an alias" do
    """
    defmodule MyAppWeb.Page do
      alias MyApp.Repo, as: R
      def a, do: MyApp.Repo.all(Foo)
      def b, do: R.one(Foo)
    end
    """
    |> issues("lib/my_app_web/page.ex")
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [3, 4] end)
  end

  test "leaves the module alone outside the rule's files" do
    "defmodule MyApp.Accounts.X do\n  def a, do: MyApp.Repo.all(Foo)\nend\n"
    |> issues("lib/my_app/accounts/x.ex")
    |> refute_issues()
  end

  test "flags only the listed functions" do
    """
    defmodule MyApp.Accounts.X do
      def a(r), do: AshOban.run_trigger(r, :t)
      def b(r), do: AshOban.Info.oban_triggers(r)
    end
    """
    |> issues("lib/my_app/accounts/x.ex")
    |> assert_issue(fn issue ->
      assert issue.message =~ "AshOban.run_trigger is not allowed here"
    end)
  end

  test "allows the listed files" do
    source = "defmodule X do\n  require Logger\n  def a, do: Logger.info(\"hi\")\nend\n"

    source |> issues("lib/my_app/accounts/log_subscriber.ex") |> refute_issues()
    source |> issues("lib/my_app/accounts/alert.ex") |> assert_issue()
  end

  test "skips `__MODULE__`-relative names instead of crashing" do
    """
    defmodule MyAppWeb.Page do
      alias __MODULE__.Repo
      def a, do: Repo.all(Foo)
    end
    """
    |> issues("lib/my_app_web/page.ex")
    |> refute_issues()
  end

  test "survives alias __MODULE__.Child with the preset on" do
    """
    defmodule MyApp.Page do
      alias __MODULE__.Child
      def a, do: Child.all(Foo)
    end
    """
    |> preset_issues("lib/my_app/page.ex")
    |> refute_issues()
  end

  test "functions :all with except skips the listed modules" do
    rules = [[module: ReqLLM, functions: :all, except: [ReqLLM.Tool], message: "use Models"]]

    "defmodule X do\n  def a, do: ReqLLM.Tool.new(1)\nend\n"
    |> issues("lib/my_app/x.ex", rules: rules)
    |> refute_issues()

    "defmodule X do\n  def a, do: ReqLLM.generate_text(1, 2)\nend\n"
    |> issues("lib/my_app/x.ex", rules: rules)
    |> assert_issue()
  end

  test "preset and project rules both apply" do
    rules = [[module: MyApp.Platform, functions: :all, allowed: [], message: "m"]]

    "defmodule X do\n  def a, do: DateTime.utc_now()\n  def b, do: MyApp.Platform.x()\nend\n"
    |> preset_issues("lib/my_app/foo.ex", rules: rules)
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  test "without app only the project's rules apply" do
    "defmodule X do\n  def a, do: DateTime.utc_now()\nend\n"
    |> issues("lib/my_app/foo.ex", rules: [])
    |> refute_issues()
  end

  test "except drops preset keys through the check" do
    "defmodule X do\n  def a, do: DateTime.utc_now()\nend\n"
    |> preset_issues("lib/my_app/foo.ex", except: [:clock])
    |> refute_issues()
  end

  test "an unknown except key stops the run, naming the valid keys" do
    log =
      ExUnit.CaptureLog.capture_log(fn ->
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          {_pid, ref} =
            spawn_monitor(fn -> preset_issues("defmodule X do\nend\n", "lib/my_app/foo.ex", except: [:clok]) end)

          assert_receive {:DOWN, ^ref, :process, _pid, {%ArgumentError{message: message}, _stacktrace}}
          assert message =~ ~r/:clok.*:clock/s
        end)
      end)

    assert log =~ "ArgumentError"
  end

  test "web: overrides the web namespace" do
    source =
      "defmodule X do\n  def a, do: Phoenix.PubSub.subscribe(S, \"t\")\n  def b, do: MyApp.Web.Endpoint.subscribe(\"t\")\nend\n"

    source |> preset_issues("lib/my_app/pub_sub.ex", web: MyApp.Web) |> refute_issues()

    source
    |> preset_issues("lib/my_app/web/live.ex", web: MyApp.Web)
    |> assert_issues(fn issues -> assert length(issues) == 2 end)
  end

  describe "the preset" do
    test "the clock is read only in MyApp.LocalTime" do
      source = """
      defmodule X do
        def a, do: Date.utc_today()
        def b, do: DateTime.utc_now()
        def c, do: NaiveDateTime.utc_now()
        def d, do: DateTime.now!("Europe/Zurich")
        def e, do: NaiveDateTime.local_now()
        def f, do: DateTime.from_unix!(0)
        def g, do: DateTime.now("Europe/Zurich")
        def h, do: Time.utc_now()
        def i, do: System.system_time()
        def j, do: System.os_time(:second)
        def k, do: System.monotonic_time()
      end
      """

      source |> preset_issues("lib/my_app/local_time.ex") |> refute_issues()
      source |> preset_issues("apps/my_app/lib/my_app/local_time.ex") |> refute_issues()
      source |> preset_issues("/home/me/proj/lib/my_app/local_time.ex") |> refute_issues()

      source
      |> preset_issues("lib/my_app/harvest/plan.ex")
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.line_no) |> Enum.sort() == [2, 3, 4, 5, 6, 8, 9, 10, 11]
      end)
    end

    test "the clock is forbidden through an alias too" do
      "defmodule X do\n  alias DateTime, as: DT\n  def a, do: DT.utc_now()\nend\n"
      |> preset_issues("lib/my_app_web/live/page.ex")
      |> assert_issue(fn issue -> assert issue.message =~ "MyApp.LocalTime" end)
    end

    test "domain code logs through a subscriber, whichever function of Logger it calls" do
      for call <- [
            "Logger.info(\"x\")",
            "Logger.error(\"x\")",
            "Logger.log(:info, \"x\")",
            "Logger.bare_log(:info, \"x\")"
          ] do
        source = "defmodule X do\n  require Logger\n  def a, do: #{call}\nend\n"

        source |> preset_issues("lib/my_app/finance/loader.ex") |> assert_issue()

        for path <- [
              "lib/my_app/finance/log_subscriber.ex",
              "lib/my_app/telemetry/action_log.ex",
              "lib/my_app_web/error.ex",
              "lib/mix/tasks/my_app.report.ex"
            ] do
          source |> preset_issues(path) |> refute_issues()
        end
      end
    end

    test "Logger functions that do not log are fine" do
      "defmodule X do\n  require Logger\n  def a, do: Logger.metadata(request_id: \"x\")\nend\n"
      |> preset_issues("lib/my_app/finance/loader.ex")
      |> refute_issues()
    end

    test "only MyApp.HTTP and its clients use Req" do
      source = "defmodule X do\n  def a, do: Req.new(base_url: \"https://api.example.com\")\nend\n"

      source |> preset_issues("lib/my_app/http.ex") |> refute_issues()
      source |> preset_issues("lib/my_app/http/log_subscriber.ex") |> refute_issues()
      source |> preset_issues("lib/my_app/harvest/sync.ex") |> assert_issue()
      source |> preset_issues("lib/my_app_web/live/page.ex") |> assert_issue()
    end

    test "only MyApp.PubSub calls Phoenix.PubSub" do
      source = "defmodule X do\n  def a, do: Phoenix.PubSub.subscribe(S, \"t\")\nend\n"

      source |> preset_issues("lib/my_app/pub_sub.ex") |> refute_issues()
      source |> preset_issues("lib/my_app/accounts.ex") |> assert_issue()
      source |> preset_issues("lib/my_app_web/live/page.ex") |> assert_issue()
    end

    test "the web subscribes through a domain, not through MyApp.PubSub or the endpoint" do
      source = """
      defmodule X do
        def a, do: MyApp.PubSub.subscribe("t")
        def b, do: MyAppWeb.Endpoint.subscribe("t")
      end
      """

      source |> preset_issues("lib/my_app/accounts.ex") |> refute_issues()

      source
      |> preset_issues("lib/my_app_web/live/page.ex")
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.line_no) |> Enum.sort() == [2, 3]
      end)
    end

    test "jobs come from the actions, not from AshOban.run_trigger" do
      "defmodule X do\n  def a(r), do: AshOban.run_trigger(r, :sync)\nend\n"
      |> preset_issues("lib/my_app/harvest/x.ex")
      |> assert_issue(fn issue -> assert issue.message =~ "run_oban_trigger" end)
    end

    test "the token resource stays out of the web" do
      source = "defmodule X do\n  def a, do: AshAuthentication.TokenResource.revoke(Token, \"jti\")\nend\n"

      source |> preset_issues("lib/my_app/accounts/x.ex") |> refute_issues()

      source
      |> preset_issues("lib/my_app_web/live/page.ex")
      |> assert_issue(fn issue -> assert issue.message =~ "MyApp.Accounts" end)
    end

    test "Decimal.from_float is forbidden everywhere, Decimal itself is fine" do
      "defmodule X do\n  def a(h), do: Decimal.from_float(h)\nend\n"
      |> preset_issues("lib/my_app/harvest/mapping.ex")
      |> assert_issue(fn issue -> assert issue.message =~ "exact" end)

      "defmodule X do\n  def a(h), do: Decimal.new(h)\nend\n"
      |> preset_issues("lib/my_app/harvest/mapping.ex")
      |> refute_issues()
    end
  end
end
