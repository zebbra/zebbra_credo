defmodule ZebbraCredo.ConfigTest do
  use ExUnit.Case, async: true

  alias ZebbraCredo.Check
  alias ZebbraCredo.Config

  @defaults [
    Check.SystemComment,
    Check.AshEntryPoints,
    Check.RawSql,
    Check.ForbiddenCalls,
    Check.AssignInRender,
    Check.EnumKernel,
    Check.EnumLookup,
    Check.NoAnonymousDslFunctions,
    Check.ScopeNotActor
  ]

  test "house_checks enables the nine default checks" do
    assert [app: MyApp] |> Config.house_checks() |> Keyword.keys() |> Enum.sort() == Enum.sort(@defaults)
  end

  test "house_checks passes app to the checks that need it" do
    checks = Config.house_checks(app: MyApp, except: [:clock])

    for check <- [Check.ForbiddenCalls, Check.RawSql, Check.AssignInRender, Check.EnumKernel, Check.ScopeNotActor] do
      assert checks[check][:app] == MyApp
    end

    for check <- [Check.SystemComment, Check.AshEntryPoints, Check.EnumLookup, Check.NoAnonymousDslFunctions] do
      assert checks[check] == []
    end

    assert checks[Check.ForbiddenCalls][:except] == [:clock]
  end

  test "house_checks passes web and repo only to the checks that take them" do
    checks = Config.house_checks(app: MyApp, web: MyApp.Web, repo: MyApp.Store)

    assert checks[Check.ForbiddenCalls] == [app: MyApp, web: MyApp.Web]
    assert checks[Check.ScopeNotActor] == [app: MyApp, web: MyApp.Web]
    assert checks[Check.EnumKernel] == [app: MyApp]
    assert checks[Check.RawSql] == [app: MyApp, repo: MyApp.Store]
  end

  test "except_checks removes a check" do
    checks = Config.house_checks(app: MyApp, except_checks: [Check.EnumKernel])

    refute Keyword.has_key?(checks, Check.EnumKernel)
    assert length(checks) == 8
  end

  test "checks adds params and turns on AshAiToolGuard" do
    refute Keyword.has_key?(Config.house_checks(app: MyApp), Check.AshAiToolGuard)

    checks =
      Config.house_checks(
        app: MyApp,
        checks: [{Check.RawSql, allowed: ["lib/my_app/health.ex"]}, {Check.AshAiToolGuard, loop: MyApp.Loop}]
      )

    assert checks[Check.RawSql] == [app: MyApp, allowed: ["lib/my_app/health.ex"]]
    assert checks[Check.AshAiToolGuard] == [loop: MyApp.Loop]
  end

  test "merge respects project entries" do
    enabled = [{Credo.Check.Readability.ModuleDoc, []}, {Check.RawSql, [allowed: ["x.ex"]]}]
    merged = Config.merge(enabled, app: MyApp, checks: [{Check.RawSql, allowed: ["y.ex"], repo_functions: []}])

    assert [params] = for({Check.RawSql, params} <- merged, do: params)
    assert params[:allowed] == ["x.ex"]
    assert params[:app] == MyApp
    assert params[:repo_functions] == []
    assert hd(merged) == {Credo.Check.Readability.ModuleDoc, []}
    assert length(merged) == 10
  end

  test "merge keeps a project's false" do
    merged = Config.merge([{Check.EnumKernel, false}], app: MyApp)

    assert for({Check.EnumKernel, params} <- merged, do: params) == [false]
  end

  test "missing app raises" do
    assert_raise ArgumentError, ~r/app:/, fn -> Config.house_checks([]) end
    assert_raise ArgumentError, ~r/app:/, fn -> Config.house_checks(except: [:clock]) end
    assert_raise ArgumentError, ~r/app:/, fn -> Config.house_checks(app: "MyApp") end
  end

  test "unknown except key raises" do
    assert_raise ArgumentError, ~r/:clok.*:clock/s, fn -> Config.house_checks(app: MyApp, except: [:clok]) end
  end

  test "an OTP app name as app raises" do
    assert_raise ArgumentError, ~r/`app:`.*module.*:my_app/s, fn -> Config.house_checks(app: :my_app) end
  end

  test "web and repo that are not modules raise" do
    assert_raise ArgumentError, ~r/`web:`.*:my_app_web/s, fn -> Config.house_checks(app: MyApp, web: :my_app_web) end

    assert_raise ArgumentError, ~r/`repo:`.*"MyApp.Repo"/s, fn ->
      Config.house_checks(app: MyApp, repo: "MyApp.Repo")
    end
  end

  test "except that is not a list raises" do
    assert_raise ArgumentError, ~r/`except:`.*list.*:clock/s, fn -> Config.house_checks(app: MyApp, except: :clock) end
  end

  test "except_checks that is not a list raises" do
    assert_raise ArgumentError, ~r/`except_checks:`.*list/s, fn ->
      Config.house_checks(app: MyApp, except_checks: Check.EnumKernel)
    end
  end

  test "checks that is not a list of {check, params} raises" do
    assert_raise ArgumentError, ~r/`checks:`.*false/s, fn -> Config.house_checks(app: MyApp, checks: false) end

    assert_raise ArgumentError, ~r/`checks:`/, fn ->
      Config.house_checks(app: MyApp, checks: [{Check.RawSql, "lib/x.ex"}])
    end
  end

  test "a check module that does not exist raises" do
    assert_raise ArgumentError, ~r/`checks:`.*ZebbraCredo.Check.Typo.*not a Credo check/s, fn ->
      Config.house_checks(app: MyApp, checks: [{Check.Typo, []}])
    end

    assert_raise ArgumentError, ~r/`except_checks:`.*ZebbraCredo.Check.Typo.*not a Credo check/s, fn ->
      Config.house_checks(app: MyApp, except_checks: [Check.Typo])
    end
  end

  test "a module that is not a Credo check raises" do
    assert_raise ArgumentError, ~r/`checks:`.*Enum.*not a Credo check/s, fn ->
      Config.house_checks(app: MyApp, checks: [{Enum, []}])
    end
  end
end
