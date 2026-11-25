defmodule ZebbraCredo.Check.NoAnonymousDslFunctionsTest do
  use Credo.Test.Case

  alias ZebbraCredo.Check.NoAnonymousDslFunctions

  setup_all do
    Application.ensure_all_started(:credo)
    :ok
  end

  defp issues(source, params \\ [], path \\ "lib/my_app/orders/order.ex") do
    source |> to_source_file(path) |> run_check(NoAnonymousDslFunctions, params)
  end

  test "flags change fn" do
    """
    defmodule MyApp.Orders.Order do
      actions do
        update :save do
          change fn changeset, _ -> changeset end
        end
      end
    end
    """
    |> issues()
    |> assert_issue(fn issue -> assert issue.line_no == 4 end)
  end

  test "flags run &" do
    """
    defmodule MyApp.Orders.Order do
      actions do
        action :go do
          run &MyApp.Foo.bar/2
        end
      end
    end
    """
    |> issues()
    |> assert_issue()
  end

  test "allows a module" do
    """
    defmodule MyApp.Orders.Order do
      change MyApp.Changes.Slugify
    end
    """
    |> issues()
    |> refute_issues()
  end

  test "allows {Module, opts}" do
    """
    defmodule MyApp.Orders.Order do
      change {MyApp.Changes.Slugify, field: :name}
    end
    """
    |> issues()
    |> refute_issues()
  end

  test "allows allowed globs" do
    """
    defmodule MyApp.Legacy.Order do
      change fn changeset, _ -> changeset end
    end
    """
    |> issues([allowed: ["lib/my_app/legacy/**"]], "lib/my_app/legacy/order.ex")
    |> refute_issues()
  end

  test "ignores qualified calls and other macros" do
    """
    defmodule MyApp.Orders.Order do
      Ash.Changeset.change(fn -> :ok end)
      other fn -> :ok end
    end
    """
    |> issues()
    |> refute_issues()
  end

  test "respects macros param" do
    "defmodule A do\n  other fn -> :ok end\nend\n"
    |> issues(macros: [:other])
    |> assert_issue()
  end
end
