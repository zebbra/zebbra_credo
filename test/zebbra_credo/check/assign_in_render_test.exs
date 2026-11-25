defmodule ZebbraCredo.Check.AssignInRenderTest do
  use Credo.Test.Case

  alias ZebbraCredo.Check.AssignInRender

  setup_all do
    Application.ensure_all_started(:credo)
    :ok
  end

  test "flags assign, assign_new and update in a LiveView's or LiveComponent's render" do
    ~S'''
    defmodule Fixture.Index do
      use MyAppWeb, :live_view

      def render(assigns) do
        assigns = assign(assigns, hidden: [])
        ~H"<p>{@hidden}</p>"
      end
    end

    defmodule Fixture.Toolbar do
      use Phoenix.LiveComponent

      def render(assigns) do
        assigns
        |> assign_new(:open, fn -> false end)
        |> Phoenix.Component.update(:count, &(&1 + 1))
        |> then(&~H"<p>{@open}</p>")
      end
    end
    '''
    |> to_source_file()
    |> run_check(AssignInRender, app: MyApp)
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [5, 15, 16] end)
  end

  test "accepts assigns elsewhere in a LiveView, and in function components" do
    ~S'''
    defmodule Fixture.Index do
      use MyAppWeb, :live_view

      def mount(_params, _session, socket), do: {:ok, assign(socket, hidden: [])}

      def render(assigns), do: ~H"<.row hidden={Map.update(%{}, :a, 1, & &1)} />"

      defp row(assigns) do
        assigns = assign(assigns, :label, "Row")
        ~H"<p>{@label}</p>"
      end
    end

    defmodule Fixture.Components do
      use MyAppWeb, :html

      def render(assigns) do
        assigns = assign(assigns, :label, "Row")
        ~H"<p>{@label}</p>"
      end
    end
    '''
    |> to_source_file()
    |> run_check(AssignInRender, app: MyApp)
    |> refute_issues()
  end

  test "recognises a custom web namespace" do
    ~S'''
    defmodule Fixture.Index do
      use Acme.Portal, :live_view

      def render(assigns) do
        assigns = assign(assigns, hidden: [])
        ~H"<p>{@hidden}</p>"
      end
    end
    '''
    |> to_source_file()
    |> run_check(AssignInRender, app: Acme.Core, web: Acme.Portal)
    |> assert_issue()
  end

  test "without app it still checks Phoenix.LiveView" do
    ~S'''
    defmodule Fixture.Index do
      use Phoenix.LiveView

      def render(assigns) do
        assigns = assign(assigns, hidden: [])
        ~H"<p>{@hidden}</p>"
      end
    end

    defmodule Fixture.Other do
      use MyAppWeb, :live_view

      def render(assigns), do: assign(assigns, hidden: [])
    end
    '''
    |> to_source_file()
    |> run_check(AssignInRender)
    |> assert_issue(fn issue -> assert issue.line_no == 5 end)
  end
end
