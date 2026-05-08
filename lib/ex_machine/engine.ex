defmodule ExMachine.Engine do
  @moduledoc """
  Pure-functional execution of statecharts.

  The engine is the only place where SCXML semantics live. It is **stateless**
  in itself: every public function takes a `Machine` value and returns a new
  one, never reading or writing process dictionary or globals.

  ## Algorithm overview (M3 subset)

  Milestone M3 supports atomic, compound, and final states with event-driven
  and eventless transitions, run-to-completion, and `done.state.<id>` events.
  History pseudostates, choice pseudostates, parallel regions, and internal
  transitions arrive in M4 and M5; their data is already validated by the
  DSL but the engine raises if asked to execute them.

  ### Run-to-completion (`run_to_completion/1`)

  After every external `dispatch/2`, and at the end of `init/1`:

      loop:
        if an eventless transition is enabled:
          microstep with that transition
          continue loop
        if there is an internal raised event in the queue:
          pop it, microstep against it
          continue loop
        return machine

  ### Microstep (`microstep/4`)

  A single transition application:

    1. Compute LCCA(source, target) — the least state that has both as
       descendants (or `nil` for action-only transitions).
    2. exit_set = active states that are descendants of LCCA, deepest first.
    3. entry_set = ancestors of target up to (excluding) LCCA, parent-first,
       followed by the initial chain from target.
    4. Run `on_exit` actions (exit_set order), then transition action, then
       `on_entry` actions (entry_set order). Each receives and returns an
       `ExMachine.Step`.
    5. Update configuration, drain raised events into the machine queue.
    6. If the entered leaf is `:final`, emit `done.state.<parent>`. If the
       parent is the root, the machine stops running.

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
      |> then(&maybe_emit_done(def_, chain, &1))

    micro = %Microstep{event: nil, transition: nil, exited: [], entered: chain}
    trace = Trace.new(nil) |> Trace.push(micro)

    machine =
      %{
        machine
        | configuration: config,
          context: step.context,
          running?: not stopped_after_entering?(def_, chain),
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
    case find_eventless(machine) do
      {source, transition} ->
        machine
        |> microstep(source, transition, nil)
        |> run_to_completion()

      nil ->
        drain_queue(machine)
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
    case find_transition(machine, event) do
      nil -> machine
      {source, transition} -> microstep(machine, source, transition, event)
    end
  end

  # Walk every active atomic state's ancestor chain (atomic itself first), pick
  # the first transition that matches and whose guard passes. Atomic-state
  # ordering is deterministic via `Configuration.atomic_states/2`.
  defp find_transition(%Machine{} = machine, event) do
    do_find_transition(machine, fn t -> match_event?(t, event) end)
  end

  defp find_eventless(%Machine{} = machine) do
    do_find_transition(machine, &Transition.eventless?/1)
  end

  defp do_find_transition(%Machine{} = machine, predicate) do
    Configuration.atomic_states(machine.configuration, machine.definition)
    |> Enum.find_value(fn atomic ->
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
    end)
  end

  defp match_event?(%Transition{event: nil}, _event), do: false
  defp match_event?(%Transition{event: e}, e), do: true
  defp match_event?(%Transition{event: e}, {e, _params}), do: true
  defp match_event?(%Transition{}, _), do: false

  defp guard_passes?(%Transition{guard: nil}, _ctx), do: true
  defp guard_passes?(%Transition{guard: g}, ctx) when is_function(g, 1), do: g.(ctx) == true

  # ── Microstep ─────────────────────────────────────────────────────────────

  # Action-only transition (no target).
  defp microstep(machine, _source, %Transition{target: nil} = transition, event) do
    step = Step.new(machine.context, event)
    step = apply_action(step, transition.action)

    micro = %Microstep{event: event, transition: transition, exited: [], entered: []}

    %{
      machine
      | context: step.context,
        queue: machine.queue ++ step.raised,
        trace: Trace.push(machine.trace, micro)
    }
  end

  defp microstep(_machine, source, %Transition{type: :internal}, _event) do
    raise "internal transitions are not supported in M3 (source=#{inspect(source)}); coming in M4"
  end

  defp microstep(machine, source, %Transition{} = transition, event) do
    %Machine{definition: def_, configuration: config} = machine
    target = transition.target

    case Definition.fetch!(def_, target).kind do
      kind when kind in [:choice, :history] ->
        raise "transition target #{inspect(target)} of kind #{kind} is not supported in M3 (coming in M4)"

      _ ->
        :ok
    end

    lcca = lcca_external(def_, source, target)
    exit_chain = compute_exit_chain(def_, config, lcca)
    entry_chain = compute_entry_chain(def_, lcca, target)

    step =
      machine.context
      |> Step.new(event)
      |> apply_actions(exit_actions(def_, exit_chain))
      |> apply_action(transition.action)
      |> apply_actions(entry_actions(def_, entry_chain))

    # Ensure init/1 also benefits from the same pipe order. (apply_action takes
    # `step` first, returning a step; apply_actions same.)

    new_config =
      config
      |> Configuration.exit(exit_chain)
      |> add_chain(entry_chain)

    step = maybe_emit_done(def_, entry_chain, step)

    micro = %Microstep{
      event: event,
      transition: transition,
      exited: exit_chain,
      entered: entry_chain
    }

    %{
      machine
      | configuration: new_config,
        context: step.context,
        queue: machine.queue ++ step.raised,
        trace: Trace.push(machine.trace, micro),
        running?: not stopped_after_entering?(def_, entry_chain)
    }
  end

  # ── LCCA & set computation ────────────────────────────────────────────────

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

  # ── Final detection & done events ────────────────────────────────────────

  defp maybe_emit_done(def_, entry_chain, %Step{} = step) do
    case List.last(entry_chain) do
      nil ->
        step

      leaf ->
        node = Definition.fetch!(def_, leaf)

        if node.kind == :final and node.parent != nil do
          Step.raise_event(step, done_event(node.parent))
        else
          step
        end
    end
  end

  defp stopped_after_entering?(def_, entry_chain) do
    case List.last(entry_chain) do
      nil ->
        false

      leaf ->
        node = Definition.fetch!(def_, leaf)
        node.kind == :final and node.parent == def_.root
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
