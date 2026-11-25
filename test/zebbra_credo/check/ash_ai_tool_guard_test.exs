defmodule ZebbraCredo.Check.AshAiToolGuardTest do
  use Credo.Test.Case

  alias ZebbraCredo.Check.AshAiToolGuard

  setup_all do
    Application.ensure_all_started(:credo)
    :ok
  end

  defp issues(source, path \\ "lib/my_app/assistant/loop.ex", params \\ [loop: MyApp.Assistant.Loop]) do
    source
    |> to_source_file(path)
    |> run_check(AshAiToolGuard, params)
  end

  test "flags `tools: true` and `resources: true` anywhere" do
    """
    defmodule X do
      def a(c), do: AshAi.Mcp.Client.req_llm_tools(c, :s, resources: true)
      def b, do: run(tools: true)
    end
    """
    |> issues("lib/my_app/connectors/mcp/client.ex")
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [2, 3] end)
  end

  test "flags a prompt action with tools" do
    """
    defmodule X do
      use Ash.Resource
      actions do
        action :summarize, :string do
          run prompt(&model/2, tools: [:list_devices])
        end
      end
    end
    """
    |> issues("lib/my_app/agents/summary.ex")
    |> assert_issue(fn issue -> assert issue.message =~ "never gets tools" end)
  end

  for {name, call} <- [
        {"extra tools", "prompt(&model/2, extra_tools: tools)"},
        {"options it cannot read", "prompt(&model/2, opts)"},
        {"options it can only half read", "prompt(&model/2, [{:prompt, \"Hi\"} | opts])"},
        {"remote extra tools", "AshAi.Actions.prompt(&model/2, extra_tools: tools)"},
        {"the module the macro expands to", "{AshAi.Actions.Prompt, tools: [:list_devices]}"}
      ] do
    test "flags a prompt action with #{name}" do
      unquote(call)
      |> then(&"defmodule X do\n  def a(tools, opts), do: #{&1}\nend\n")
      |> issues("lib/my_app/agents/summary.ex")
      |> assert_issue(fn issue -> assert issue.message =~ "never gets tools" end)
    end
  end

  test "flags the prompt module through an alias" do
    "defmodule X do\n  alias AshAi.Actions.Prompt\n  def a, do: {Prompt, []}\nend\n"
    |> issues("lib/my_app/agents/summary.ex")
    |> assert_issue()
  end

  test "allows a prompt action without tools, and `tools: false`" do
    """
    defmodule X do
      def a, do: prompt(&model/2, tools: false)
      def b, do: AshAi.Actions.prompt(&model/2, prompt: "Hi")
      def c, do: prompt(&model/2, extra_tools: [])
      def d, do: prompt(&model/2)
    end
    """
    |> issues("lib/my_app/agents/summary.ex")
    |> refute_issues()
  end

  test "leaves the head of a function called prompt alone" do
    "defmodule X do\n  def prompt(model, opts), do: {model, opts}\nend\n"
    |> issues("lib/my_app/agents/summary.ex")
    |> refute_issues()
  end

  test "flags any mount of AshAi's MCP server, also through an alias" do
    """
    defmodule XWeb.Router do
      alias AshAi.Mcp.Router, as: Mcp
      forward "/mcp", Mcp
      forward "/other", AshAi.Mcp.Server
    end
    """
    |> issues("lib/my_app_web/router.ex")
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [3, 4] end)

    "defmodule X do\n  plug AshAi.Mcp.Dev, otp_app: :x\nend\n"
    |> issues("lib/my_app_web/endpoint.ex")
    |> assert_issue()
  end

  describe "a file that uses AshAi.ToolLoop" do
    test "never passes :approvals, however it builds the options" do
      """
      defmodule X do
        def a(ids), do: AshAi.ToolLoop.stream([], tools: false, approvals: ids)
        def b(opts, ids), do: Keyword.put(opts, :approvals, ids)
        def c(opts), do: AshAi.ToolLoop.run([], tools: false)
      end
      """
      |> issues()
      |> assert_issues(fn issues ->
        assert Enum.map(issues, & &1.line_no) == [2, 3]
        assert Enum.all?(issues, &(&1.message =~ "skips the gate"))
      end)
    end

    test "never calls resume/3, which passes :approvals itself" do
      """
      defmodule X do
        alias AshAi.ToolLoop
        def a(m, d, o), do: ToolLoop.resume(m, d, o)
        def b, do: &AshAi.ToolLoop.resume/3
      end
      """
      |> issues()
      |> assert_issues(fn issues ->
        assert Enum.map(issues, & &1.line_no) == [3, 4]
        assert Enum.all?(issues, &(&1.message =~ "skips the gate"))
      end)
    end

    test "calls the loop only by name" do
      """
      defmodule X do
        import AshAi.ToolLoop
        def a(m, d), do: apply(AshAi.ToolLoop, :resume, [m, d, []])
      end
      """
      |> issues()
      |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [2, 3] end)
    end

    test "never passes :actions, :otp_app or a tool list" do
      """
      defmodule X do
        def a, do: AshAi.ToolLoop.stream([], tools: false, actions: [{Res, :*}])
        def b, do: AshAi.ToolLoop.run([], tools: [:list_devices])
        def c, do: AshAi.ToolLoop.run([], tools: false, otp_app: :my_app)
      end
      """
      |> issues()
      |> assert_issues(fn issues ->
        assert issues |> Enum.map(& &1.line_no) |> Enum.sort() |> Enum.uniq() == [2, 3, 4]
      end)
    end

    test "always sets `tools: false`, in a literal it can read" do
      """
      defmodule X do
        def a(m), do: AshAi.ToolLoop.run(m, extra_tools: [])
        def b(m, opts), do: AshAi.ToolLoop.run(m, opts)
        def c(m), do: AshAi.ToolLoop.stream(m)
        def d(m, opts), do: m |> AshAi.ToolLoop.run(opts)
        def e(m, opts), do: AshAi.ToolLoop.run(m, [{:tools, false} | opts])
      end
      """
      |> issues()
      |> assert_issues(fn issues ->
        assert Enum.map(issues, & &1.line_no) == [2, 3, 4, 5, 6]
        assert Enum.all?(issues, &(&1.message =~ "literal keyword list"))
      end)
    end

    test "may pass `tools: false` with extra tools" do
      """
      defmodule X do
        alias AshAi.ToolLoop
        def a(tools), do: ToolLoop.stream([], tools: false, extra_tools: tools)
        def b(m, tools), do: m |> ToolLoop.run(tools: false, extra_tools: tools)
      end
      """
      |> issues()
      |> refute_issues()
    end

    test "may read the loop's result struct" do
      "defmodule X do\n  def a(%AshAi.ToolLoop.Result{} = result), do: result\nend\n"
      |> issues()
      |> refute_issues()
    end
  end

  test "leaves `:approvals` alone in a file without the loop" do
    "defmodule X do\n  def a(run), do: Ash.load(run, :approvals)\nend\n"
    |> issues("lib/my_app/execution/run.ex")
    |> refute_issues()
  end

  test "names the rules document in the messages when set" do
    "defmodule X do\n  def b, do: run(tools: true)\nend\n"
    |> issues("lib/my_app/x.ex", loop: MyApp.Assistant.Loop, rules_doc: "docs/rules.md")
    |> assert_issue(fn issue -> assert issue.message =~ "docs/rules.md" end)
  end

  test "raises a config error without loop" do
    log =
      ExUnit.CaptureLog.capture_log(fn ->
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          {_pid, ref} = spawn_monitor(fn -> issues("defmodule X do\nend\n", "lib/my_app/x.ex", []) end)

          assert_receive {:DOWN, ^ref, :process, _pid, {%ArgumentError{message: message}, _stacktrace}}
          assert message =~ "loop:"
        end)
      end)

    assert log =~ "ArgumentError"
  end
end
