defmodule ExMachine.Test.Generators do
  @moduledoc """
  StreamData generators that produce small, valid `ExMachine.Definition`
  values. Used by the property tests in `test/property/`.

  Generated definitions are intentionally bounded: shallow trees, small
  alphabets of state ids and event names. The goal is broad coverage of
  the engine's invariants, not exhaustive corner-case search.

  All randomness is drawn from StreamData — no `:rand` / `Enum.random`
  calls — so a failing seed reliably regenerates the same input and
  StreamData can shrink the failing case.

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
    gen all(
          n <- StreamData.integer(2..5),
          counts <- StreamData.list_of(StreamData.integer(0..2), length: n),
          total = Enum.sum(counts),
          events <- list_of_events(total),
          target_picks <- list_of_target_picks(total)
        ) do
      ids = atomic_ids(n)
      transitions = assemble_transitions(ids, ids, counts, events, target_picks)

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

      nodes = Map.new([{root.id, root} | Enum.map(atomic_nodes, fn n -> {n.id, n} end)])
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
          inner_count <- StreamData.integer(2..3),
          outer_ids = Enum.map(1..outer_count, &:"o#{&1}"),
          inner_ids = Enum.map(1..inner_count, &:"i#{&1}"),
          compound_id = hd(outer_ids),
          atomic_outer = tl(outer_ids),
          all_atomics = atomic_outer ++ inner_ids,
          all_sources = all_atomics ++ [compound_id],
          all_targets = all_atomics ++ [compound_id],
          counts <- StreamData.list_of(StreamData.integer(0..2), length: length(all_sources)),
          total = Enum.sum(counts),
          events <- list_of_events(total),
          target_picks <- list_of_target_picks(total)
        ) do
      transitions =
        assemble_transitions(all_sources, all_targets, counts, events, target_picks)

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
    StreamData.constant(definition_for_small_parallel())
  end

  @doc """
  An event atom drawn from the same small alphabet used by the
  generators. Use this in property tests that need a random event to
  feed `Engine.dispatch/2`.
  """
  def event, do: StreamData.member_of(@event_names)

  # ── Internals ────────────────────────────────────────────────────────────

  defp atomic_ids(n), do: Enum.map(1..n, &:"a#{&1}")

  defp list_of_events(0), do: StreamData.constant([])

  defp list_of_events(n) when n > 0,
    do: StreamData.list_of(StreamData.member_of(@event_names), length: n)

  # Each pick is an integer that we index into the per-source candidate list
  # via `rem/2`, so the upper bound only needs to be reasonably large; pick
  # 0..63 to keep the StreamData generator small.
  defp list_of_target_picks(0), do: StreamData.constant([])

  defp list_of_target_picks(n) when n > 0,
    do: StreamData.list_of(StreamData.integer(0..63), length: n)

  # Walk the source list, consuming `counts[i]` events and target_picks for
  # each source, and pick targets from the source-specific candidate list
  # (`targets - source`). Pure consumption of pre-generated StreamData
  # values — no global randomness.
  defp assemble_transitions(sources, all_targets, counts, events, target_picks) do
    {transitions, _events_left, _picks_left} =
      sources
      |> Enum.zip(counts)
      |> Enum.reduce({[], events, target_picks}, fn {source, count}, {acc, evs, tps} ->
        {events_for_source, rest_evs} = Enum.split(evs, count)
        {picks_for_source, rest_tps} = Enum.split(tps, count)
        candidates = Enum.reject(all_targets, &(&1 == source))

        new_ts =
          if candidates == [] do
            []
          else
            events_for_source
            |> Enum.zip(picks_for_source)
            |> Enum.map(fn {event, pick} ->
              target = Enum.at(candidates, rem(pick, length(candidates)))
              %Transition{event: event, source: source, target: target}
            end)
          end

        {acc ++ new_ts, rest_evs, rest_tps}
      end)

    transitions
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
