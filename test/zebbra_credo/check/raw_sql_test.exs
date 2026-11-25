defmodule ZebbraCredo.Check.RawSqlTest do
  use Credo.Test.Case

  alias ZebbraCredo.Check.RawSql

  setup_all do
    Application.ensure_all_started(:credo)
    :ok
  end

  defp issues(source, path, params \\ []) do
    source
    |> to_source_file(path)
    |> run_check(RawSql, Keyword.merge([app: MyApp, allowed: ["lib/my_app/legacy/importer.ex"]], params))
  end

  test "flags Ecto.Query, Ecto.Adapters.SQL, Postgrex and the repo's query functions" do
    """
    defmodule MyApp.Accounts.X do
      import Ecto.Query
      alias MyApp.Repo

      def a, do: Repo.query!("SELECT 1")
      def b, do: Ecto.Adapters.SQL.query!(Repo, "SELECT 1")
      def c(fun), do: Repo.transaction(fun)
      def d, do: Repo.in_transaction?()
    end
    """
    |> issues("lib/my_app/accounts/x.ex")
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [2, 5, 6] end)
  end

  test "flags a table named in a fragment, not one built with an interpolation or in a doc" do
    ~S'''
    defmodule MyApp.Accounts.X do
      @doc "Uses fragment(\"SELECT 1 FROM users\")."
      def a, do: expr(fragment("(SELECT count(*) FROM documents)"))
      def b, do: expr(fragment("(SELECT 1 FROM #{table})"))
    end
    '''
    |> issues("lib/my_app/accounts/x.ex")
    |> assert_issue(fn issue -> assert issue.line_no == 3 end)
  end

  test "flags a fragment in a ~s sigil and in a heredoc" do
    ~S'''
    defmodule MyApp.Accounts.X do
      def a, do: expr(fragment(~s|EXISTS (SELECT 1 FROM users)|))

      def b,
        do:
          expr(
            fragment("""
            EXISTS (SELECT 1 FROM users)
            """)
          )
    end
    '''
    |> issues("lib/my_app/accounts/x.ex")
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [2, 7] end)
  end

  test "flags custom_statements blocks" do
    """
    defmodule MyApp.Accounts.X do
      postgres do
        custom_statements do
          statement :a do
            up "SELECT 1"
          end
        end
      end
    end
    """
    |> issues("lib/my_app/accounts/x.ex")
    |> assert_issue(fn issue -> assert issue.line_no == 3 end)
  end

  test "allows the listed files" do
    "defmodule MyApp.Legacy.Importer do\n  def a, do: MyApp.Repo.query!(\"SELECT 1\")\nend\n"
    |> issues("lib/my_app/legacy/importer.ex")
    |> refute_issues()
  end

  test "all_tenants is not raw SQL" do
    "defmodule MyApp.Accounts.X do\n  def a, do: MyApp.Repo.all_tenants()\nend\n"
    |> issues("lib/my_app/accounts/x.ex")
    |> refute_issues()
  end

  test "repo_functions replaces the functions that are not raw SQL" do
    "defmodule MyApp.Accounts.X do\n  def a, do: MyApp.Repo.all_tenants()\nend\n"
    |> issues("lib/my_app/accounts/x.ex", repo_functions: [])
    |> assert_issue()
  end

  test "message names the allowed list" do
    "defmodule MyApp.Accounts.X do\n  def a, do: MyApp.Repo.query!(\"SELECT 1\")\nend\n"
    |> issues("lib/my_app/accounts/x.ex")
    |> assert_issue(fn issue ->
      assert issue.message =~ "add the file to the check's `allowed:` list"
    end)
  end

  test "repo derives from app" do
    "defmodule Acme.Accounts.X do\n  def a, do: Acme.Repo.query!(\"select 1\")\nend\n"
    |> issues("lib/acme/accounts/x.ex", app: Acme)
    |> assert_issue()
  end

  test "an explicit repo wins over the app's" do
    """
    defmodule MyApp.X do
      def a, do: Other.Repo.query!("select 1")
      def b, do: MyApp.Repo.query!("select 1")
    end
    """
    |> issues("lib/my_app/x.ex", repo: Other.Repo)
    |> assert_issue(fn issue -> assert issue.line_no == 2 end)
  end

  test "without app or repo only the SQL modules and fragments are flagged" do
    """
    defmodule MyApp.X do
      def a, do: MyApp.Repo.query!("select 1")
      def b, do: Ecto.Adapters.SQL.query!(MyApp.Repo, "select 1")
    end
    """
    |> to_source_file("lib/my_app/x.ex")
    |> run_check(RawSql)
    |> assert_issue(fn issue -> assert issue.line_no == 3 end)
  end

  test "survives alias __MODULE__.Child" do
    """
    defmodule MyApp.Accounts.X do
      alias __MODULE__.Child

      def a, do: Child.run(Repo.query!("select 1"))
    end
    """
    |> issues("lib/my_app/accounts/x.ex")
    |> refute_issues()
  end
end
