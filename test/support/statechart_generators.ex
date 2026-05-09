defmodule ExMachine.Test.Generators do
  @moduledoc """
  StreamData generators that produce small, valid `ExMachine.Definition`
  values. Used by the property tests in `test/property/`.

  Generated definitions are intentionally bounded: shallow trees, small
  alphabets of state ids and event names. The goal is broad coverage of
  the engine's invariants, not exhaustive corner-case search.

  All generators return a value that passes
  `ExMachine.Definition.validate!/1`.
  """

  use ExUnitProperties

  alias ExMachine.{Definition, StateNode, Transition}

  @event_names [:e1, :e2, :e3, :e4, :tick, :tock, :ping]

  # ── Public generators ────────────────────────────────────────────────────

  @doc """
  Flat FSM: a compound root with N atomic substates and a few random
  transitions among them.
  """
  def flat_fsm do
    gen all(n <- StreamData.integer(2..5)) do
      ids = atomic_ids(n)
      transitions = random_transitions(ids, ids)

      atomic_nodes =
        Enum.map(ids, fn id ->
          ts = Enum.filter(transitions, fn t -> t.source == id end)
          StateNode.new(id, :atomic, parent: :root, substates: [], transitions: ts)
        end)

      root =
        StateNode.new(:root, :compound,
          parent: nil,
          substates: ids,
          initial: hd(ids)
        )

      nodes =
        Map.new([{root.id, root} | Enum.map(atomic_nodes, fn n -> {n.id, n} end)])

      Definition.build!(root: :root, nodes: nodes, initial_context: nil)
    end
  end

  @doc """
  Two-level compound: the root has 2-3 children; one of them is itself
  a compound with 2-3 atomic substates. A few random transitions across
  all atomic leaves.
  """
  def nested_compound do
    gen all(
          outer_count <- StreamData.integer(2..3),
          inner_count <- StreamData.integer(2..3)
        ) do
      outer_ids = Enum.map(1..outer_count, &:"o#{&1}")
      inner_ids = Enum.map(1..inner_count, &:"i#{&1}")

      compound_id = hd(outer_ids)
      atomic_outer = tl(outer_ids)
      all_atomics = atomic_outer ++ inner_ids

      transitions = random_transitions(all_atomics, all_atomics ++ [compound_id])

      inner_nodes =
        Enum.map(inner_ids, fn id ->
          ts = Enum.filter(transitions, fn t -> t.source == id end)
          StateNode.new(id, :atomic, parent: compound_id, substates: [], transitions: ts)
        end)

      compound_node =
        StateNode.new(compound_id, :compound,
          parent: :root,
          substates: inner_ids,
          initial: hd(inner_ids),
          transitions: Enum.filter(transitions, fn t -> t.source == compound_id end)
        )

      atomic_outer_nodes =
        Enum.map(atomic_outer, fn id ->
          ts = Enum.filter(transitions, fn t -> t.source == id end)
          StateNode.new(id, :atomic, parent: :root, substates: [], transitions: ts)
        end)

      root =
        StateNode.new(:root, :compound,
          parent: nil,
          substates: outer_ids,
          initial: compound_id
        )

      nodes_list = [root, compound_node | inner_nodes ++ atomic_outer_nodes]
      nodes = Map.new(nodes_list, fn n -> {n.id, n} end)

      Definition.build!(root: :root, nodes: nodes, initial_context: nil)
    end
  end

  @doc """
  Parallel root with 2 regions, each a compound with 2 atomic substates.
  Transitions stay within their region (one per region's first atomic).
  """
  def small_parallel do
    gen all(_seed <- StreamData.constant(:ok)) do
      definition_for_small_parallel()
    end
  end

  @doc """
  An event atom drawn from the same small alphabet used by the
  generators. Use this in property tests that need a random event to
  feed `Engine.dispatch/2`.
  """
  def event, do: StreamData.member_of(@event_names)

  # ── Internals ────────────────────────────────────────────────────────────

  defp atomic_ids(n), do: Enum.map(1..n, &:"a#{&1}")

  defp random_transitions(sources, targets) do
    Enum.flat_map(sources, fn s ->
      others = Enum.reject(targets, &(&1 == s))

      case others do
        [] ->
          []

        candidates ->
          # 0-2 transitions per source, with random event + target.
          count = :rand.uniform(3) - 1
          Enum.map(1..count//1, fn _ -> random_transition(s, candidates) end)
      end
    end)
  end

  defp random_transition(source, candidates) do
    %Transition{
      event: Enum.random(@event_names),
      source: source,
      target: Enum.random(candidates)
    }
  end

  defp definition_for_small_parallel do
    region_a_atomics = [:la, :lb]
    region_b_atomics = [:ra, :rb]

    la =
      StateNode.new(:la, :atomic,
        parent: :left,
        substates: [],
        transitions: [%Transition{event: :tick, source: :la, target: :lb}]
      )

    lb = StateNode.new(:lb, :atomic, parent: :left, substates: [])

    ra =
      StateNode.new(:ra, :atomic,
        parent: :right,
        substates: [],
        transitions: [%Transition{event: :tick, source: :ra, target: :rb}]
      )

    rb = StateNode.new(:rb, :atomic, parent: :right, substates: [])

    left =
      StateNode.new(:left, :region,
        parent: :root,
        substates: region_a_atomics,
        initial: :la
      )

    right =
      StateNode.new(:right, :region,
        parent: :root,
        substates: region_b_atomics,
        initial: :ra
      )

    root = StateNode.new(:root, :parallel, parent: nil, substates: [:left, :right])

    nodes = Map.new([root, left, right, la, lb, ra, rb], fn n -> {n.id, n} end)
    Definition.build!(root: :root, nodes: nodes, initial_context: nil)
  end
end
