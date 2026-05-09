defmodule ExMachine.DefinitionTest do
  use ExUnit.Case, async: true

  alias ExMachine.{Definition, StateNode, Transition}

  describe "build!/1 — happy path" do
    test "builds a flat compound with two atomics" do
      def_ =
        Definition.build!(%{
          root: :root,
          nodes: %{
            root: StateNode.new(:root, :compound, initial: :a, substates: [:a, :b]),
            a:
              StateNode.new(:a, :atomic,
                parent: :root,
                transitions: [Transition.new(source: :a, event: :go, target: :b)]
              ),
            b: StateNode.new(:b, :atomic, parent: :root)
          }
        })

      assert def_.root == :root
      assert map_size(def_.nodes) == 3
    end
  end

  describe "validation errors" do
    defp build_invalid(nodes) do
      Definition.build!(%{root: :root, nodes: Map.new(nodes, fn n -> {n.id, n} end)})
    end

    test "raises if root is not in nodes" do
      assert_raise Definition.Error, ~r/root state :root/, fn ->
        Definition.build!(%{root: :root, nodes: %{}})
      end
    end

    test "raises if a non-root node has no parent" do
      assert_raise Definition.Error, ~r/has no parent/, fn ->
        build_invalid([
          StateNode.new(:root, :compound, initial: :a, substates: [:a]),
          # :a missing parent
          StateNode.new(:a, :atomic)
        ])
      end
    end

    test "raises if parent does not list the child" do
      assert_raise Definition.Error, ~r/not in its substates/, fn ->
        build_invalid([
          StateNode.new(:root, :compound, initial: :a, substates: [:a]),
          StateNode.new(:a, :atomic, parent: :root),
          StateNode.new(:b, :atomic, parent: :root)
        ])
      end
    end

    test "raises if compound has no :initial" do
      assert_raise Definition.Error, ~r/has no :initial/, fn ->
        build_invalid([
          StateNode.new(:root, :compound, substates: [:a]),
          StateNode.new(:a, :atomic, parent: :root)
        ])
      end
    end

    test "raises if :initial is not a substate" do
      assert_raise Definition.Error, ~r/not one of its substates/, fn ->
        build_invalid([
          StateNode.new(:root, :compound, initial: :nope, substates: [:a]),
          StateNode.new(:a, :atomic, parent: :root)
        ])
      end
    end

    test "raises if parallel has fewer than 2 regions" do
      assert_raise Definition.Error, ~r/at least 2 region children/, fn ->
        build_invalid([
          StateNode.new(:root, :parallel, substates: [:r1]),
          StateNode.new(:r1, :region, parent: :root, initial: :a, substates: [:a]),
          StateNode.new(:a, :atomic, parent: :r1)
        ])
      end
    end

    test "raises if parallel child is not a region" do
      assert_raise Definition.Error, ~r/must be a :region/, fn ->
        build_invalid([
          StateNode.new(:root, :parallel, substates: [:r1, :a]),
          StateNode.new(:r1, :region, parent: :root, initial: :x, substates: [:x]),
          StateNode.new(:x, :atomic, parent: :r1),
          StateNode.new(:a, :atomic, parent: :root)
        ])
      end
    end

    test "raises if history is outside a composite" do
      assert_raise Definition.Error, ~r/must live inside/, fn ->
        build_invalid([
          StateNode.new(:root, :compound, initial: :a, substates: [:a]),
          # `:a` is atomic but lists `:h` as a substate so parent-consistency
          # passes and we reach the history placement check below.
          StateNode.new(:a, :atomic, parent: :root, substates: [:h]),
          StateNode.new(:h, :history, parent: :a, history_type: :deep)
        ])
      end
    end

    test "raises on transition target unknown" do
      assert_raise Definition.Error, ~r/targets unknown state/, fn ->
        build_invalid([
          StateNode.new(:root, :compound, initial: :a, substates: [:a]),
          StateNode.new(:a, :atomic,
            parent: :root,
            transitions: [Transition.new(source: :a, event: :go, target: :ghost)]
          )
        ])
      end
    end

    test "regression bug_006: rejects a transition whose source is the root" do
      assert_raise Definition.Error, ~r/root state :root cannot be the source/, fn ->
        build_invalid([
          StateNode.new(:root, :compound,
            initial: :a,
            substates: [:a],
            transitions: [Transition.new(source: :root, event: :reset, target: :a)]
          ),
          StateNode.new(:a, :atomic, parent: :root)
        ])
      end
    end

    test "raises on choice with no branches" do
      assert_raise Definition.Error, ~r/at least one branch/, fn ->
        build_invalid([
          StateNode.new(:root, :compound, initial: :a, substates: [:a, :c]),
          StateNode.new(:a, :atomic, parent: :root),
          StateNode.new(:c, :choice, parent: :root)
        ])
      end
    end
  end

  describe "graph queries" do
    setup do
      def_ =
        Definition.build!(%{
          root: :root,
          nodes: %{
            root: StateNode.new(:root, :compound, initial: :outer, substates: [:outer]),
            outer:
              StateNode.new(:outer, :compound,
                parent: :root,
                initial: :inner,
                substates: [:inner]
              ),
            inner: StateNode.new(:inner, :atomic, parent: :outer)
          }
        })

      {:ok, def_: def_}
    end

    test "ancestors walks up to root", %{def_: def_} do
      assert Definition.ancestors(def_, :inner) == [:outer, :root]
      assert Definition.ancestors(def_, :outer) == [:root]
      assert Definition.ancestors(def_, :root) == []
    end

    test "descendants is a MapSet", %{def_: def_} do
      assert Definition.descendants(def_, :root) == MapSet.new([:outer, :inner])
      assert Definition.descendants(def_, :outer) == MapSet.new([:inner])
      assert Definition.descendants(def_, :inner) == MapSet.new()
    end

    test "fetch! raises on unknown id", %{def_: def_} do
      assert_raise Definition.Error, ~r/unknown state/, fn ->
        Definition.fetch!(def_, :nope)
      end
    end
  end
end
