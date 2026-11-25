defmodule ZebbraCredo.Check.SystemCommentTest do
  use Credo.Test.Case

  alias ZebbraCredo.Check.SystemComment

  setup_all do
    Application.ensure_all_started(:credo)
    :ok
  end

  test "flags authorize?: false without a system comment" do
    """
    defmodule Fixture do
      def read(id) do
        # Reads the record.
        MyApp.Accounts.get_user(id, authorize?: false)
      end

      def put(opts), do: Keyword.put(opts, :authorize?, false)
    end
    """
    |> to_source_file()
    |> run_check(SystemComment)
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [4, 7] end)
  end

  test "accepts a system comment in the comment lines right above" do
    """
    defmodule Fixture do
      def read(id) do
        # system: host resolution runs before anyone acts.
        MyApp.Accounts.get_user(id, authorize?: false)
      end

      def opts(context) do
        Ash.Context.to_opts(context,
          # system: the job's own bookkeeping,
          # without a user.
          authorize?: false
        )
      end
    end
    """
    |> to_source_file()
    |> run_check(SystemComment)
    |> refute_issues()
  end

  test "ignores the words in docs and strings" do
    ~S'''
    defmodule Fixture do
      @moduledoc "Callers pass `authorize?: false`."
      def text, do: "authorize?: false"
    end
    '''
    |> to_source_file()
    |> run_check(SystemComment)
    |> refute_issues()
  end

  @test_fixture """
  defmodule FooTest do
    def read(id), do: MyApp.Accounts.get_user(id, authorize?: false)
  end
  """

  test "ignores test files by default" do
    @test_fixture
    |> to_source_file("test/my_app/foo_test.exs")
    |> run_check(SystemComment)
    |> refute_issues()
  end

  test "include_tests flags test files" do
    @test_fixture
    |> to_source_file("test/my_app/foo_test.exs")
    |> run_check(SystemComment, include_tests: true)
    |> assert_issue()
  end

  test "ignores test files in an umbrella app by default" do
    @test_fixture
    |> to_source_file("apps/x/test/foo_test.exs")
    |> run_check(SystemComment)
    |> refute_issues()
  end

  describe "policy_bypasses" do
    test "flags a bypass without a comment" do
      """
      defmodule Fixture do
        policies do
          bypass always() do
            authorize_if always()
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(SystemComment, policy_bypasses: true)
      |> assert_issue(fn issue -> assert issue.line_no == 3 end)
    end

    test "accepts a bypass with a system comment" do
      """
      defmodule Fixture do
        policies do
          # system: the support role audits every record.
          bypass always() do
            authorize_if always()
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(SystemComment, policy_bypasses: true)
      |> refute_issues()
    end

    test "is off by default" do
      """
      defmodule Fixture do
        policies do
          bypass always() do
            authorize_if always()
          end
        end
      end
      """
      |> to_source_file()
      |> run_check(SystemComment)
      |> refute_issues()
    end
  end
end
