defmodule ExMachine.StateNodeTest do
  use ExUnit.Case, async: true

  alias ExMachine.StateNode

  describe "new/3" do
    test "builds an atomic node" do
      assert %StateNode{id: :foo, kind: :atomic, parent: :root} =
               StateNode.new(:foo, :atomic, parent: :root)
    end

    test "carries optional fields" do
      assert %StateNode{initial: :a, substates: [:a, :b]} =
               StateNode.new(:c, :compound, initial: :a, substates: [:a, :b])
    end
  end

  describe "predicates" do
    test "composite? is true for compound, parallel, region" do
      assert StateNode.composite?(StateNode.new(:c, :compound))
      assert StateNode.composite?(StateNode.new(:p, :parallel))
      assert StateNode.composite?(StateNode.new(:r, :region))
    end

    test "composite? is false for leaves and pseudostates" do
      refute StateNode.composite?(StateNode.new(:a, :atomic))
      refute StateNode.composite?(StateNode.new(:f, :final))
      refute StateNode.composite?(StateNode.new(:h, :history))
      refute StateNode.composite?(StateNode.new(:c, :choice))
    end

    test "pseudostate? is true for history and choice" do
      assert StateNode.pseudostate?(StateNode.new(:h, :history))
      assert StateNode.pseudostate?(StateNode.new(:c, :choice))
      refute StateNode.pseudostate?(StateNode.new(:a, :atomic))
    end

    test "final? identifies final nodes" do
      assert StateNode.final?(StateNode.new(:f, :final))
      refute StateNode.final?(StateNode.new(:a, :atomic))
    end
  end
end
