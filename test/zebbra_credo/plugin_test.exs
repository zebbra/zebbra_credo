defmodule ZebbraCredo.PluginTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  setup_all do
    Application.ensure_all_started(:credo)
    :ok
  end

  @formats [
    enabled: "%{enabled: [{Credo.Check.Readability.ModuleDoc, []}]}",
    extra: "%{extra: [{Credo.Check.Readability.ModuleDoc, []}]}",
    list: "[{Credo.Check.Readability.ModuleDoc, []}]"
  ]

  @tag :tmp_dir
  test "plugin adds checks for every config format", %{tmp_dir: dir} do
    File.mkdir_p!(Path.join(dir, "lib/my_app"))

    File.write!(Path.join(dir, "lib/my_app/foo.ex"), """
    defmodule MyApp.Foo do
      @moduledoc false
      def now, do: DateTime.utc_now()
    end
    """)

    for {format, checks} <- @formats do
      config = Path.join(dir, "#{format}.credo.exs")

      File.write!(config, """
      %{configs: [%{name: "default", plugins: [{ZebbraCredo, app: MyApp}], checks: #{checks}}]}
      """)

      checks =
        for issue <- Jason.decode!(credo(["--strict", "--format", "json", "--config-file", config, dir]))["issues"],
            do: issue["check"]

      assert "ZebbraCredo.Check.ForbiddenCalls" in checks, "#{format}: #{inspect(checks)}"
    end
  end

  @tag :tmp_dir
  test "plugin checks lib/ but not test/", %{tmp_dir: dir} do
    source = fn module ->
      """
      defmodule #{module} do
        @moduledoc false
        def seed, do: Ash.Seed.seed!(MyApp.User, %{})
        def stub, do: Req.Test.stub(MyApp.HTTP, fn conn -> conn end)
        def now, do: DateTime.utc_now()
      end
      """
    end

    for {path, module} <- [{"lib/my_app/fake.ex", MyApp.Fake}, {"test/support/fake.ex", MyApp.TestFake}] do
      File.mkdir_p!(Path.join(dir, Path.dirname(path)))
      File.write!(Path.join(dir, path), source.(inspect(module)))
    end

    config = Path.join(dir, ".credo.exs")

    File.write!(
      config,
      ~s(%{configs: [%{name: "default", plugins: [{ZebbraCredo, app: MyApp}], checks: %{enabled: []}}]})
    )

    issues = Jason.decode!(credo(["--strict", "--format", "json", "--config-file", config, dir]))["issues"]
    files = issues |> Enum.map(&Path.relative_to(Path.expand(&1["filename"]), Path.expand(dir))) |> Enum.uniq()

    assert files == ["lib/my_app/fake.ex"]
    assert length(issues) == 3
  end

  @tag :tmp_dir
  test "a bad plugin config stops the run before any file is checked", %{tmp_dir: dir} do
    config = Path.join(dir, ".credo.exs")
    File.write!(config, ~s(%{configs: [%{name: "default", plugins: [{ZebbraCredo, app: MyApp, except: [:clok]}]}]}))

    assert_raise ArgumentError, ~r/:clok.*:clock/s, fn -> credo(["--config-file", config, dir]) end
  end

  # Credo prints from its Shell server, so its group leader has to point at the capture.
  defp credo(argv) do
    shell = Process.whereis(Credo.CLI.Output.Shell)
    leader = Process.group_leader()

    capture_io(fn ->
      Process.group_leader(shell, Process.group_leader())

      try do
        Credo.run(argv)
      after
        Process.group_leader(shell, leader)
      end
    end)
  end
end
