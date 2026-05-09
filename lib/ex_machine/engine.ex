defmodule ExMachine.Engine do
  @moduledoc """
  Pure-functional execution of statecharts.

  The engine is the only place where SCXML semantics live. It is **stateless**
  in itself: every public function takes a `Machine` value and returns a new
  one, never reading or writing process dictionary or globals.

  ## Algorithm overview (M3-M5 subset)

  The engine handles atomic, compound, parallel, region, and final states;
  event-driven and eventless transitions; run-to-completion;
  `done.state.<id>` events including bubble-up across parallel regions;
  internal transitions; choice and history pseudostates. Server-mode and
  delayed/invoked services are out of scope (M6-M7).

  ### Run-to-completion (`run_to_completion/1`)

  After every external `dispatch/2`, and at the end of `init/1`:

      loop:
        if any eventless transitions are enabled:
          select them (one per active atomic), remove conflicts,
          microstep with the surviving set
          continue loop
        if there is an internal raised event in the queue:
          pop it, microstep against it
          continue loop
        return machine

  ### Microstep

  A microstep applies a *set* of non-conflicting transitions atomically:

    1. For each active atomic state, walk its ancestor chain looking for
       the first transition whose event matches and whose guard passes.
    2. Reduce the resulting set with `remove_conflicting/2`: if two
       transitions' exit sets overlap, the one whose source is deeper in
       the tree wins; ties are broken by document order (set selection
       order).
    3. For each surviving transition: resolve choice/history, compute
       (exit_chain, entry_chain) via LCCA, then UNION across transitions.
    4. Snapshot history slots whose composite is in the combined exit set.
    5. Run `on_exit` actions (deepest-first), then every transition's
       action (in selection order), then `on_entry` actions (parent-first).
    6. Update configuration; drain raised events; emit `done.state.<id>`
       for any composite or parallel that just completed (recursive
       bubble-up). If the root is now in a terminal configuration, stop.

  ## Public API

  Three entry points: `init/1`, `dispatch/2`, `dispatch/3` (variant that
  accepts a tuple `{event, params}`). Direct callers usually prefer the
  thin façade in `ExMachine` (`init/1`, `dispatch/2`).
  """

  alias ExMachine.{Configuration, Definition, Machine, Step, Trace, Transition}
  alias ExMachine.Trace.Microstep

  # ── Public API ────────────────────────────────────────────────────────────

  @doc """
  Enter the initial configuration of `machine`, run all entry actions, drain
  raised events, and return a stable machine value.

  Resets `machine.trace` to an init-macrostep trace.
  """
  @spec init(Machine.t()) :: Machine.t()
  def init(%Machine{definition: def_} = machine) do
    chain = Configuration.initial_chain(def_, def_.root)
    config = MapSet.new(chain)

    step =
      machine.context
      |> Step.new(nil)
      |> apply_actions(entry_actions(def_, chain))
      |> then(&emit_done_events(def_, chain, config, &1))

    micro = %Microstep{event: nil, transitions: [], exited: [], entered: chain}
    trace = Trace.new(nil) |> Trace.push(micro)

    machine =
      %{
        machine
        | configuration: config,
          context: step.context,
          running?: not stopped?(def_, config),
          queue: machine.queue ++ step.raised,
          trace: trace
      }

    run_to_completion(machine)
  end

  @doc """
  Send `event` to the machine. Returns the new machine value after running to
  completion. If no transition is enabled the machine is returned unchanged
  (same configuration, same context, but with a fresh empty trace).

  Raises `ExMachine.Machine.NotRunning` if the machine has stopped (top-level
  final entered).
  """
  @spec dispatch(Machine.t(), term()) :: Machine.t()
  def dispatch(%Machine{running?: false}, _event), do: raise(Machine.NotRunning)

  def dispatch(%Machine{} = machine, event) do
    machine = %{machine | trace: Trace.new(event)}

    machine
    |> process_event(event)
    |> run_to_completion()
  end

  @doc """
  Variant that bundles event parameters. The `params` term is delivered to
  guards and actions via `Step.event` (as `{event_name, params}`).
  """
  @spec dispatch(Machine.t(), atom(), term()) :: Machine.t()
  def dispatch(%Machine{} = machine, event, params) do
    dispatch(machine, {event, params})
  end

  # ── Run-to-completion loop ────────────────────────────────────────────────

  @spec run_to_completion(Machine.t()) :: Machine.t()
  defp run_to_completion(%Machine{running?: false} = machine), do: machine

  defp run_to_completion(machine) do
    case select_eventless(machine) do
      [] -> drain_queue(machine)
      transitions -> machine |> microstep(transitions, nil) |> run_to_completion()
    end
  end

  defp drain_queue(%Machine{queue: []} = machine), do: machine

  defp drain_queue(%Machine{queue: [event | rest]} = machine) do
    machine = %{machine | queue: rest}

    machine
    |> process_event(event)
    |> run_to_completion()
  end

  # ── Event processing ──────────────────────────────────────────────────────

  defp process_event(%Machine{} = machine, event) do
    case select_transitions(machine, event) do
      [] -> machine
      transitions -> microstep(machine, transitions, event)
    end
  end

  # For each active atomic state, walk the ancestor chain and pick the first
  # transition that matches the predicate and whose guard passes. Combine
  # the per-atomic picks and remove conflicts. Returns a list of
  # `{source_id, %Transition{}}` pairs in atomic-state order (source-deepest
  # is preserved by remove_conflicting/2).
  defp select_transitions(%Machine{} = machine, event) do
    select_enabled(machine, fn t -> match_event?(t, event) end)
  end

  defp select_eventless(%Machine{} = machine) do
    select_enabled(machine, &Transition.eventless?/1)
  end

  defp select_enabled(%Machine{} = machine, predicate) do
    machine.configuration
    |> Configuration.atomic_states(machine.definition)
    |> Enum.flat_map(fn atomic ->
      case first_enabled_in_chain(machine, atomic, predicate) do
        nil -> []
        pair -> [pair]
      end
    end)
    |> remove_conflicting(machine)
  end

  defp first_enabled_in_chain(%Machine{} = machine, atomic, predicate) do
    ids_to_check = [atomic | Definition.ancestors(machine.definition, atomic)]

    Enum.find_value(ids_to_check, fn id ->
      machine.definition
      |> Definition.fetch!(id)
      |> Map.fetch!(:transitions)
      |> Enum.find(fn t -> predicate.(t) and guard_passes?(t, machine.context) end)
      |> case do
        nil -> nil
        transition -> {id, transition}
      end
    end)
  end

  # SCXML remove_conflicting: walk the selection in order; keep a transition
  # only if it does not conflict with any already-kept transition. When two
  # conflict, the deeper-source one wins (it dominates the shallower one,
  # which is then removed from the kept set).
  defp remove_conflicting([], _machine), do: []

  defp remove_conflicting(transitions, %Machine{} = machine) do
    Enum.reduce(transitions, [], fn t1, kept ->
      {kept_after, conflict?} =
        Enum.reduce(kept, {[], false}, fn t2, acc -> reconcile(t1, t2, acc, machine) end)

      kept_reversed = Enum.reverse(kept_after)
      if conflict?, do: kept_reversed, else: kept_reversed ++ [t1]
    end)
  end

  # Decide whether the kept-set entry `t2` should survive the addition of
  # `t1`. Returns the updated `{accumulator, t1_already_lost?}` pair so the
  # outer reduce can short-circuit further checks once t1 has lost.
  defp reconcile(_t1, t2, {acc, true}, _machine), do: {[t2 | acc], true}

  defp reconcile(t1, t2, {acc, false}, machine) do
    cond do
      not transitions_conflict?(t1, t2, machine) -> {[t2 | acc], false}
      source_descendant?(t1, t2, machine.definition) -> {acc, false}
      true -> {[t2 | acc], true}
    end
  end

  defp transitions_conflict?(t1, t2, %Machine{} = machine) do
    e1 = exit_set_for(t1, machine)
    e2 = exit_set_for(t2, machine)
    not MapSet.disjoint?(MapSet.new(e1), MapSet.new(e2))
  end

  defp exit_set_for({_source, %Transition{target: nil}}, _machine), do: []

  defp exit_set_for({source, %Transition{} = transition}, %Machine{} = machine) do
    %Machine{definition: def_, configuration: config, context: ctx} = machine
    target = resolve_choice(def_, transition.target, ctx)

    case Definition.fetch!(def_, target).kind do
      :history ->
        parent_id = Definition.fetch!(def_, target).parent
        compute_exit_chain(def_, config, lcca_external(def_, source, parent_id))

      _ ->
        lcca = compute_lcca(def_, source, target, transition.type)
        compute_exit_chain(def_, config, lcca)
    end
  end

  defp source_descendant?({s1, _}, {s2, _}, def_) do
    MapSet.member?(Definition.descendants(def_, s2), s1)
  end

  defp match_event?(%Transition{event: nil}, _event), do: false
  defp match_event?(%Transition{event: e}, e), do: true
  defp match_event?(%Transition{event: e}, {e, _params}), do: true
  defp match_event?(%Transition{}, _), do: false

  defp guard_passes?(%Transition{guard: nil}, _ctx), do: true
  defp guard_passes?(%Transition{guard: g}, ctx) when is_function(g, 1), do: g.(ctx) == true

  # ── Microstep ─────────────────────────────────────────────────────────────

  # Apply a non-empty set of non-conflicting transitions atomically. Each
  # element is a `{source_id, %Transition{}}` pair as returned by
  # `select_transitions/2` or `select_eventless/1`.
  defp microstep(%Machine{} = machine, [_ | _] = transitions, event) do
    %Machine{definition: def_, configuration: config, context: ctx, histories: histories} =
      machine

    chains =
      Enum.map(transitions, fn {source, %Transition{} = t} ->
        target = resolve_choice(def_, t.target, ctx)

        case target do
          nil ->
            {[], []}

          _ ->
            compute_microstep_sets(def_, config, histories, source, t, target)
        end
      end)

    exit_chain = combined_exit_chain(def_, chains)
    entry_chain = combined_entry_chain(chains)

    new_histories = record_histories(def_, exit_chain, config, histories)

    step =
      ctx
      |> Step.new(event)
      |> apply_actions(exit_actions(def_, exit_chain))
      |> then(fn s ->
        Enum.reduce(transitions, s, fn {_src, %Transition{action: a}}, acc ->
          apply_action(acc, a)
        end)
      end)
      |> apply_actions(entry_actions(def_, entry_chain))

    new_config =
      config
      |> Configuration.exit(exit_chain)
      |> add_chain(entry_chain)

    step = emit_done_events(def_, entry_chain, new_config, step)

    micro = %Microstep{
      event: event,
      transitions: Enum.map(transitions, fn {_s, t} -> t end),
      exited: exit_chain,
      entered: entry_chain
    }

    %{
      machine
      | configuration: new_config,
        context: step.context,
        histories: new_histories,
        queue: machine.queue ++ step.raised,
        trace: Trace.push(machine.trace, micro),
        running?: not stopped?(def_, new_config)
    }
  end

  # Union of per-transition exit chains, deepest-first. We sort the union so
  # that even if independent transitions contribute disjoint chains, the
  # final order remains a globally-correct deepest-first traversal.
  defp combined_exit_chain(def_, chains) do
    chains
    |> Enum.flat_map(fn {ec, _} -> ec end)
    |> Enum.uniq()
    |> Enum.sort_by(&node_depth(def_, &1), :desc)
  end

  # Union of per-transition entry chains. Each per-transition chain is
  # already parent-first within its own sub-tree; for non-conflicting
  # transitions across regions the sub-trees are disjoint, so concatenating
  # them in selection order preserves the parent-first invariant globally.
  defp combined_entry_chain(chains) do
    chains
    |> Enum.flat_map(fn {_, enc} -> enc end)
    |> Enum.uniq()
  end

  # Compute the (exit_chain, entry_chain) for a microstep, branching on
  # transition kind (external | internal) and on whether the resolved target
  # is a history pseudostate.
  defp compute_microstep_sets(def_, config, histories, source, transition, target) do
    case Definition.fetch!(def_, target).kind do
      :history ->
        compute_history_sets(def_, config, histories, source, target)

      _ ->
        lcca = compute_lcca(def_, source, target, transition.type)
        {compute_exit_chain(def_, config, lcca), compute_entry_chain(def_, lcca, target)}
    end
  end

  # Entering a history pseudostate restores the recorded sub-configuration
  # of its parent. The LCCA is computed against the parent (not the
  # pseudostate, which is never present in a configuration).
  defp compute_history_sets(def_, config, histories, source, hist_id) do
    hist_node = Definition.fetch!(def_, hist_id)
    parent_id = hist_node.parent
    lcca = lcca_external(def_, source, parent_id)
    exit_chain = compute_exit_chain(def_, config, lcca)

    parent_chain =
      parent_id
      |> ancestors_until(def_, lcca)
      |> Enum.reverse()
      |> Kernel.++([parent_id])

    restore_chain = history_restore_chain(def_, hist_node, histories)
    {exit_chain, parent_chain ++ restore_chain}
  end

  # ── LCCA & set computation ────────────────────────────────────────────────

  # LCCA for a transition. For an external transition, this is the deepest
  # proper ancestor of `source` that also has `target` as a descendant.
  #
  # For an internal transition where the source is a composite and the target
  # is one of its proper descendants, the LCCA is the source itself: the
  # source must NOT be exited and re-entered. Any other internal configuration
  # (target outside source, source not a composite) degrades to external
  # semantics, matching SCXML.
  defp compute_lcca(def_, source, target, :internal) do
    source_node = Definition.fetch!(def_, source)
    descendants = Definition.descendants(def_, source)

    if source_node.kind in [:compound, :region] and MapSet.member?(descendants, target) do
      source
    else
      lcca_external(def_, source, target)
    end
  end

  defp compute_lcca(def_, source, target, :external), do: lcca_external(def_, source, target)

  # Least Common Compound Ancestor for an external transition: the deepest
  # proper ancestor of `source` that also has `target` as a descendant (or
  # equals `target`'s ancestor list). Returns `nil` only if either is the
  # root and the other is the root itself, which the validator rejects.
  defp lcca_external(def_, source, target) do
    source_ancestors = Definition.ancestors(def_, source)

    Enum.find(source_ancestors, fn ancestor ->
      target == ancestor or
        MapSet.member?(Definition.descendants(def_, ancestor), target)
    end) ||
      raise "could not compute LCCA for #{inspect(source)} → #{inspect(target)}; this is a bug"
  end

  # All currently-active descendants of `lcca`, sorted deepest-first
  # (proper exit order).
  defp compute_exit_chain(def_, config, lcca) do
    descendants = Definition.descendants(def_, lcca)

    config
    |> MapSet.intersection(descendants)
    |> Enum.sort_by(&node_depth(def_, &1), :desc)
  end

  # Ancestors of `target` strictly between LCCA (excluded) and `target`
  # (excluded), parent-first, then the initial chain from `target` (which
  # already starts with `target` itself).
  defp compute_entry_chain(def_, lcca, target) do
    target
    |> ancestors_until(def_, lcca)
    |> Enum.reverse()
    |> Kernel.++(Configuration.initial_chain(def_, target))
  end

  defp ancestors_until(id, def_, boundary) do
    def_
    |> Definition.ancestors(id)
    |> Enum.take_while(fn a -> a != boundary end)
  end

  defp node_depth(def_, id), do: length(Definition.ancestors(def_, id))

  defp add_chain(config, chain), do: Enum.reduce(chain, config, &MapSet.put(&2, &1))

  # ── Action application ───────────────────────────────────────────────────

  defp entry_actions(def_, chain), do: collect_actions(def_, chain, :on_entry)
  defp exit_actions(def_, chain), do: collect_actions(def_, chain, :on_exit)

  defp collect_actions(def_, chain, key) do
    Enum.flat_map(chain, fn id -> Map.fetch!(Definition.fetch!(def_, id), key) end)
  end

  defp apply_actions(step, funs) do
    Enum.reduce(funs, step, fn fun, acc -> apply_action(acc, fun) end)
  end

  defp apply_action(step, nil), do: step
  defp apply_action(step, fun) when is_function(fun, 1), do: fun.(step)

  # ── Choice resolution ────────────────────────────────────────────────────

  # Resolve a target id through any number of `:choice` pseudostates. The
  # first branch whose guard returns `true` wins; an `:otherwise` branch is
  # encoded as `{nil, target}`. Recursion lets a choice point at another
  # choice. Raises if no branch matches and no `:otherwise` is declared.
  defp resolve_choice(_def, nil, _ctx), do: nil

  defp resolve_choice(def_, target, ctx) do
    case Definition.fetch!(def_, target) do
      %{kind: :choice} = node ->
        next = pick_choice_branch(node, ctx)
        resolve_choice(def_, next, ctx)

      _ ->
        target
    end
  end

  defp pick_choice_branch(%{id: id, choice_branches: branches}, ctx) do
    branch =
      Enum.find(branches, fn
        {nil, _t} -> true
        {guard, _t} when is_function(guard, 1) -> guard.(ctx) == true
      end)

    case branch do
      nil ->
        raise "choice #{inspect(id)} has no matching branch and no :otherwise default"

      {_guard, target} ->
        target
    end
  end

  # ── History recording & restoration ──────────────────────────────────────

  # For every composite (compound or region) about to be exited that has at
  # least one history child, snapshot the relevant sub-configuration so that
  # a future entry through the history pseudostate restores it.
  defp record_histories(def_, exit_chain, old_config, histories) do
    Enum.reduce(exit_chain, histories, fn id, acc ->
      node = Definition.fetch!(def_, id)

      case node.kind do
        kind when kind in [:compound, :region] ->
          node
          |> history_children(def_)
          |> Enum.reduce(acc, fn hist, acc2 ->
            Map.put(acc2, hist.id, history_snapshot(def_, node, hist, old_config))
          end)

        _ ->
          acc
      end
    end)
  end

  defp history_children(node, def_) do
    Enum.flat_map(node.substates, fn sub_id ->
      sub = Definition.fetch!(def_, sub_id)
      if sub.kind == :history, do: [sub], else: []
    end)
  end

  # Shallow: which direct children of the parent were active.
  # Deep: which atomic descendants were active.
  defp history_snapshot(_def, parent, %{history_type: :shallow}, old_config) do
    MapSet.intersection(old_config, MapSet.new(parent.substates))
  end

  defp history_snapshot(def_, parent, %{history_type: :deep}, old_config) do
    descendants = Definition.descendants(def_, parent.id)

    descendants
    |> MapSet.intersection(old_config)
    |> Enum.filter(fn id -> Definition.fetch!(def_, id).kind in [:atomic, :final] end)
    |> MapSet.new()
  end

  # Build the entry chain to add AFTER the parent has been entered, given a
  # history pseudostate. Falls back to `history_default` (or the parent's
  # `:initial`) when there is no recorded snapshot yet.
  defp history_restore_chain(def_, %{id: id} = hist, histories) do
    case Map.get(histories, id) do
      nil -> default_restore_chain(def_, hist)
      snapshot -> snapshot_restore_chain(def_, hist, snapshot)
    end
  end

  defp default_restore_chain(def_, %{history_default: nil, parent: parent_id}) do
    parent = Definition.fetch!(def_, parent_id)
    Configuration.initial_chain(def_, parent.initial)
  end

  defp default_restore_chain(def_, %{history_default: default}) do
    Configuration.initial_chain(def_, default)
  end

  defp snapshot_restore_chain(def_, %{history_type: :shallow}, snapshot) do
    snapshot
    |> Enum.sort()
    |> Enum.flat_map(&Configuration.initial_chain(def_, &1))
  end

  defp snapshot_restore_chain(def_, %{history_type: :deep, parent: parent_id}, snapshot) do
    snapshot
    |> Enum.sort()
    |> Enum.flat_map(fn leaf ->
      ancestor_chain =
        def_
        |> Definition.ancestors(leaf)
        |> Enum.take_while(&(&1 != parent_id))
        |> Enum.reverse()

      ancestor_chain ++ [leaf]
    end)
    |> Enum.uniq()
  end

  # ── Final detection & done events ────────────────────────────────────────

  # Emit `done.state.<id>` for every composite that just completed in this
  # microstep. A compound or region completes when one of its substates is
  # an entered :final. A parallel completes when ALL its regions have
  # completed (recursively bubbled). The check sweeps every entered final
  # leaf and walks up its ancestor chain, raising at each newly-completed
  # ancestor and stopping when an ancestor is not yet complete.
  defp emit_done_events(def_, entry_chain, new_config, %Step{} = step) do
    finals_entered =
      Enum.filter(entry_chain, fn id -> Definition.fetch!(def_, id).kind == :final end)

    Enum.reduce(finals_entered, step, fn final_id, acc ->
      bubble_done(def_, Definition.fetch!(def_, final_id).parent, new_config, acc)
    end)
  end

  defp bubble_done(_def, nil, _config, step), do: step

  defp bubble_done(def_, completed_id, config, step) do
    step = Step.raise_event(step, done_event(completed_id))
    parent_id = Definition.fetch!(def_, completed_id).parent

    cond do
      parent_id == nil ->
        step

      parallel_done?(def_, parent_id, config) ->
        bubble_done(def_, parent_id, config, step)

      true ->
        step
    end
  end

  # `parent_id` is "done" when it is a :parallel whose every region contains
  # an active :final. Returns false for non-parallel parents.
  defp parallel_done?(def_, parent_id, config) do
    parent = Definition.fetch!(def_, parent_id)

    parent.kind == :parallel and
      Enum.all?(parent.substates, fn region_id -> region_done?(def_, region_id, config) end)
  end

  # A region is done when it currently contains an active :final descendant.
  defp region_done?(def_, region_id, config) do
    Definition.descendants(def_, region_id)
    |> Enum.any?(fn d ->
      MapSet.member?(config, d) and Definition.fetch!(def_, d).kind == :final
    end)
  end

  # The machine stops when the root has reached a terminal configuration:
  # for a compound root, an active :final direct child; for a parallel root,
  # every region must be done.
  defp stopped?(def_, config) do
    root = Definition.fetch!(def_, def_.root)

    case root.kind do
      :compound ->
        Enum.any?(root.substates, fn s ->
          MapSet.member?(config, s) and Definition.fetch!(def_, s).kind == :final
        end)

      :parallel ->
        parallel_done?(def_, def_.root, config)

      _ ->
        false
    end
  end

  @doc """
  Atom representing the SCXML "done.state.<id>" event for a given parent.
  Exposed for callers (and tests) that want to subscribe or assert.

  ## Examples

      iex> ExMachine.Engine.done_event(:my_compound)
      :"done.state.my_compound"
  """
  @spec done_event(atom()) :: atom()
  def done_event(parent_id) when is_atom(parent_id) do
    String.to_atom("done.state." <> Atom.to_string(parent_id))
  end
end
