defmodule ZebbraCredo.Check.EnumKernelTest do
  use Credo.Test.Case

  alias ZebbraCredo.Check.EnumKernel

  setup_all do
    Application.ensure_all_started(:credo)
    :ok
  end

  defp issues(source, path, params \\ [app: MyApp]) do
    source |> to_source_file(path) |> run_check(EnumKernel, params)
  end

  @enum """
  defmodule MyApp.Orders.Status do
    use Ash.Type.Enum, values: [:open, :closed]
  end
  """

  test "flags use Ash.Type.Enum outside the kernel" do
    @enum
    |> issues("lib/my_app/orders/status.ex")
    |> assert_issue(fn issue ->
      assert issue.line_no == 2
      assert issue.message =~ "MyApp.Type.Enum"
    end)
  end

  test "flags it through an alias" do
    """
    defmodule MyApp.Orders.Status do
      alias Ash.Type.Enum, as: E
      use E, values: [:open]
    end
    """
    |> issues("lib/my_app/orders/status.ex")
    |> assert_issue()
  end

  test "allows the kernel" do
    @enum |> issues("lib/my_app/type/enum.ex") |> refute_issues()
  end

  test "honours a kernel param" do
    @enum |> issues("lib/my_app/enum.ex", kernel: "lib/my_app/enum.ex") |> refute_issues()
  end

  test "allows allowed globs" do
    @enum
    |> issues("lib/my_app/types/locale.ex", app: MyApp, allowed: ["lib/my_app/types/locale.ex"])
    |> refute_issues()
  end

  test "accepts use MyApp.Type.Enum anywhere" do
    """
    defmodule MyApp.Orders.Status do
      use MyApp.Type.Enum, values: [:open, :closed]
    end
    """
    |> issues("lib/my_app/orders/status.ex")
    |> refute_issues()
  end

  test "names no kernel module without app or kernel" do
    @enum
    |> issues("lib/my_app/orders/status.ex", [])
    |> assert_issue(fn issue ->
      assert issue.message =~ "enum kernel"
      refute issue.message =~ "MyApp"
    end)
  end

  test "does not crash on __MODULE__ aliases" do
    """
    defmodule MyApp.Orders do
      alias __MODULE__.Child
      use Child
    end
    """
    |> issues("lib/my_app/orders.ex")
    |> refute_issues()
  end
end
