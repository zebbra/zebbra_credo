defmodule ZebbraCredo.CodeTest do
  use ExUnit.Case, async: true

  alias ZebbraCredo.Code, as: Helper

  test "resolve_returns_nil_for_module_attribute_parts" do
    assert Helper.resolve([{:__MODULE__, [], nil}, :Child], %{}) == nil
  end

  test "calls returns module, function, args and line" do
    ast = Code.string_to_quoted!("Foo.bar(1, x: 2)")
    assert [{Foo, :bar, [1, [x: 2]], 1}] = Helper.calls(ast)
  end

  test "calls resolves aliases" do
    ast = Code.string_to_quoted!("alias A.B\nB.run()")
    assert [{A.B, :run, [], 2}] = Helper.calls(ast)
  end

  test "references resolves aliases and skips typespecs" do
    ast = Code.string_to_quoted!("alias A.B\n@spec f() :: C.t()\nB.run()\nB")
    assert [{A.B, :run, 3}, {A.B, nil, 4}] = Helper.references(ast)
  end

  test "references does not crash on __MODULE__ children" do
    ast = Code.string_to_quoted!("alias __MODULE__.Child\n__MODULE__.Child.run()")
    assert Helper.references(ast) == []
  end

  test "within? matches the namespace and its children only" do
    assert Helper.within?(A.B, A)
    assert Helper.within?(A, A)
    refute Helper.within?(AB, A)
  end

  test "matches? treats * as one segment and ** as many" do
    assert Helper.matches?("lib/a/b.ex", ["lib/**"])
    refute Helper.matches?("lib/a/b.ex", ["lib/*"])
    assert Helper.matches?("lib/b.ex", ["lib/*"])
  end
end
