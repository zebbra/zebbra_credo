defmodule ZebbraCredo.Check.ScopeNotActorTest do
  use Credo.Test.Case

  alias ZebbraCredo.Check.ScopeNotActor

  setup_all do
    Application.ensure_all_started(:credo)
    :ok
  end

  defp check(source, filename, params \\ [app: MyApp]) do
    source |> to_source_file(filename) |> run_check(ScopeNotActor, params)
  end

  test "flags actor: in the web" do
    "MyApp.Orders.list(actor: user)"
    |> check("lib/my_app_web/live/foo.ex")
    |> assert_issue(fn issue -> assert issue.message =~ "scope:" end)
  end

  test "flags actor: next to scope:" do
    "MyApp.Orders.list(scope: s, actor: u)"
    |> check("lib/my_app_web/live/foo.ex")
    |> assert_issue()
  end

  test "flags files in an umbrella app's web dir" do
    "MyApp.Orders.list(actor: user)"
    |> check("apps/x/lib/my_app_web/live/foo.ex")
    |> assert_issue()
  end

  test "allows actor: nil" do
    "MyApp.Orders.list(actor: nil)"
    |> check("lib/my_app_web/live/foo.ex")
    |> refute_issues()
  end

  test "allows a system comment above" do
    """
    # system: the nightly job has no user.
    MyApp.Orders.list(actor: user)
    """
    |> check("lib/my_app_web/live/foo.ex")
    |> refute_issues()
  end

  test "ignores lib/my_app" do
    "MyApp.Orders.list(actor: user)" |> check("lib/my_app/orders.ex") |> refute_issues()
  end

  test "ignores test/" do
    "MyApp.Orders.list(actor: user)" |> check("test/my_app_web/foo_test.exs") |> refute_issues()
  end

  test "honours the web override" do
    "MyApp.Orders.list(actor: user)"
    |> check("lib/portal/foo.ex", app: MyApp, web: Portal)
    |> assert_issue()
  end

  test "reports nothing without app or web" do
    "MyApp.Orders.list(actor: user)"
    |> check("lib/my_app_web/live/foo.ex", [])
    |> refute_issues()
  end

  for {name, value} <- [variable: "sys", literal: ":system"] do
    test "accepts a system comment above the call or the actor line of a multi-line call (#{name})" do
      above_call = """
      # system: no user here.
      Orders.purge(
        actor: #{unquote(value)}
      )
      """

      above_pair = """
      Orders.purge(
        # system: no user here.
        actor: #{unquote(value)}
      )
      """

      above_call |> check("lib/my_app_web/foo.ex") |> refute_issues()
      above_pair |> check("lib/my_app_web/foo.ex") |> refute_issues()
    end

    test "flags a multi-line call without a comment (#{name})" do
      """
      Orders.purge(
        actor: #{unquote(value)}
      )
      """
      |> check("lib/my_app_web/foo.ex")
      |> assert_issue()
    end
  end

  test "ignores actor in map and struct literals" do
    """
    x = %{actor: user}
    y = %Event{actor: user}
    """
    |> check("lib/my_app_web/foo.ex")
    |> refute_issues()
  end
end
