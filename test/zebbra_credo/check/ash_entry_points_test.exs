defmodule ZebbraCredo.Check.AshEntryPointsTest do
  use Credo.Test.Case

  alias ZebbraCredo.Check.AshEntryPoints

  setup_all do
    Application.ensure_all_started(:credo)
    :ok
  end

  test "flags Ash entry points in a module that composes no Ash, also through an alias" do
    """
    defmodule MyAppWeb.Live do
      alias Ash.Query, as: Q

      def a(r), do: r |> Q.filter(x: 1) |> Ash.read!()
      def b(r), do: Ash.Resource.Info.attributes(r)
    end
    """
    |> to_source_file("lib/my_app_web/live.ex")
    |> run_check(AshEntryPoints)
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [4, 4] end)
  end

  test "accepts resources, callback modules and verifiers, and typespecs anywhere" do
    """
    defmodule MyApp.Accounts.Changes.Touch do
      use Ash.Resource.Change
      def change(changeset, _opts, _context), do: Ash.Changeset.force_change_attribute(changeset, :x, 1)
    end

    defmodule MyApp.Accounts.Changes.Aliased do
      alias Ash.Resource.Change
      @behaviour Change
      def change(changeset, _opts, _context), do: Ash.Changeset.force_change_attribute(changeset, :x, 1)
    end

    defmodule MyApp.Accounts.Verifier do
      use Spark.Dsl.Verifier
      def verify(dsl), do: Ash.Policy.Info.policies(dsl) && :ok
    end

    defmodule MyApp.Accounts.Plain do
      @spec a(Ash.Query.t()) :: Ash.Query.t()
      def a(query), do: query
      def b(record), do: Ash.Resource.put_metadata(record, :x, 1)
    end
    """
    |> to_source_file("lib/my_app/accounts/x.ex")
    |> run_check(AshEntryPoints)
    |> refute_issues()
  end

  test "a nested module does not inherit its parent's composition" do
    """
    defmodule MyApp.Accounts.Alert do
      use Ash.Resource

      defmodule Helper do
        def a(q), do: Ash.Query.limit(q, 1)
      end
    end
    """
    |> to_source_file("lib/my_app/accounts/alert.ex")
    |> run_check(AshEntryPoints)
    |> assert_issue(fn issue -> assert issue.message =~ "Helper uses Ash.Query.limit" end)
  end

  test "skips `__MODULE__`-relative names instead of crashing" do
    """
    defmodule MyApp.Accounts.Parent do
      alias __MODULE__.Child
      use __MODULE__.Using
      def a, do: Child.run()

      defmodule __MODULE__.Child do
        def run(q), do: Ash.Query.limit(q, 1)
      end
    end
    """
    |> to_source_file("lib/my_app/accounts/parent.ex")
    |> run_check(AshEntryPoints)
    |> assert_issue(fn issue ->
      assert issue.message =~ "__MODULE__.Child uses Ash.Query.limit"
    end)
  end

  test "accepts a resource's own code interface and the code calling it" do
    """
    defmodule MyApp.Accounts.McpServer do
      use Ash.Resource

      code_interface do
        define :touch
      end
    end

    defmodule MyApp.Accounts.Poller do
      alias MyApp.Accounts.McpServer

      def poll(server), do: McpServer.touch(server)
    end
    """
    |> to_source_file("lib/my_app/accounts/mcp_server.ex")
    |> run_check(AshEntryPoints)
    |> refute_issues()
  end

  test "allows a notifier to compose Ash" do
    """
    defmodule MyApp.Accounts.Notifier do
      use Ash.Notifier

      def notify(_notification), do: Ash.read!(MyApp.Accounts.User)
    end
    """
    |> to_source_file("lib/my_app/accounts/notifier.ex")
    |> run_check(AshEntryPoints)
    |> refute_issues()
  end

  test "survives alias __MODULE__.Child" do
    """
    defmodule MyApp.Accounts.Holder do
      alias __MODULE__.Child

      def a, do: Child.run()
    end
    """
    |> to_source_file("lib/my_app/accounts/holder.ex")
    |> run_check(AshEntryPoints)
    |> refute_issues()
  end
end
