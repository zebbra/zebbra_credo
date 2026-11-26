defmodule ZebbraCredo.Check.EnumLookupTest do
  use Credo.Test.Case

  alias ZebbraCredo.Check.EnumLookup

  setup_all do
    Application.ensure_all_started(:credo)
    :ok
  end

  test "flags an enum searched by to_string, and a string made an atom for label, description or meta" do
    ~S'''
    defmodule Fixture do
      def status(value), do: Enum.find(Status.values(), &(Atom.to_string(&1) == value))
      def known?(value), do: Status.values() |> Enum.any?(&(to_string(&1) == value))
      def label(state), do: Status.label(String.to_existing_atom(state))
      def tip(state), do: state |> String.to_existing_atom() |> Status.description()
    end
    '''
    |> to_source_file()
    |> run_check(EnumLookup)
    |> assert_issues(fn issues -> assert Enum.map(issues, & &1.line_no) == [2, 3, 4, 5] end)
  end

  test "accepts match, a string passed as it is, and a search of values by other means" do
    ~S'''
    defmodule Fixture do
      def status(value), do: Status.match(value)
      def label(state), do: Status.label(state)
      def first(rows), do: Enum.find(Step.values(), fn group -> group in rows end)
      def column(name), do: Map.fetch!(%{}, String.to_existing_atom(name))
    end
    '''
    |> to_source_file()
    |> run_check(EnumLookup)
    |> refute_issues()
  end
end
