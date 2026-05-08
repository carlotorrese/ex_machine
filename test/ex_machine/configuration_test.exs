defmodule ExMachine.ConfigurationTest do
  use ExUnit.Case, async: true

  alias ExMachine.{Configuration, Definition, StateNode}

  defp tiny_def do
    Definition.build!(%{
      root: :root,
      nodes: %{
        root: StateNode.new(:root, :compound, initial: :a, substates: [:a, :b]),
        a:
          StateNode.new(:a, :compound,
            parent: :root,
            initial: :a1,
            substates: [:a1, :a2]
          ),
        a1: StateNode.new(:a1, :atomic, parent: :a),
        a2: StateNode.new(:a2, :atomic, parent: :a),
        b: StateNode.new(:b, :atomic, parent: :root)
      }
    })
  end

  test "new/0 returns an empty MapSet" do
    assert Configuration.new() == MapSet.new()
  end

  test "initial/1 enters root and follows initial chain" do
    {config, chain} = Configuration.initial(tiny_def())
    assert chain == [:root, :a, :a1]
    assert config == MapSet.new([:root, :a, :a1])
  end

  test "initial_chain/2 follows :initial down to atomic" do
    assert Configuration.initial_chain(tiny_def(), :a) == [:a, :a1]
    assert Configuration.initial_chain(tiny_def(), :a1) == [:a1]
  end

  test "atomic_states/2 returns only atomic active ids" do
    config = MapSet.new([:root, :a, :a1])
    assert Configuration.atomic_states(config, tiny_def()) == [:a1]
  end

  test "active?/2 is membership" do
    config = MapSet.new([:a])
    assert Configuration.active?(config, :a)
    refute Configuration.active?(config, :b)
  end

  test "enter/3 adds id and its initial chain" do
    {config, chain} = Configuration.enter(MapSet.new(), tiny_def(), :a)
    assert chain == [:a, :a1]
    assert config == MapSet.new([:a, :a1])
  end

  test "exit/2 removes ids" do
    config = MapSet.new([:root, :a, :a1])
    assert Configuration.exit(config, [:a, :a1]) == MapSet.new([:root])
  end

  test "proper_ancestors_until/3 stops before boundary" do
    assert Configuration.proper_ancestors_until(tiny_def(), :a1, :root) == [:a]
    assert Configuration.proper_ancestors_until(tiny_def(), :a1, nil) == [:a, :root]
  end
end
