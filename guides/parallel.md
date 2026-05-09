# Parallel regions

A **parallel** state is a state whose direct children are
**regions**, all of which are active simultaneously. Each region
behaves like a small compound with its own initial and its own
transitions.

## Declaring a parallel

```elixir
defmodule Workflow do
  use ExMachine.Statechart

  initial :running

  state :running do
    initial :work

    parallel :work do
      on :abort, target: :aborted        # cross-region: exits the parallel

      region :a do
        initial :a1
        state :a1, do: on(:finish_a, target: :a_done)
        final :a_done
      end

      region :b do
        initial :b1
        state :b1, do: on(:finish_b, target: :b_done)
        final :b_done
      end
    end

    on :"done.state.work", target: :completed
  end

  state :completed
  state :aborted
end
```

A `parallel` requires **at least 2 regions**, all of which must be
declared as `region`.

## Multi-transition microsteps

When an event matches transitions in more than one region, the engine
fires **all of them in a single microstep**, in document order. This
is SCXML's `selectTransitions` algorithm.

When two transitions' exit sets overlap, they are in **conflict**.
The engine resolves with `remove_conflicting/2`: the one whose source
is deeper in the tree wins; otherwise document order breaks the tie.

## Done events

Each region raises `done.state.<region>` when its current substate
becomes a `final`. When **every** region of a parallel is done, the
engine raises `done.state.<parallel>` and the walk continues up the
ancestor chain. A top-level parallel that completes stops the
machine.

In the example above, dispatching `:finish_a` then `:finish_b` causes
`done.state.work` to bubble, which the parent compound `:running`
catches with `on(:"done.state.work", target: :completed)`.

## See also

- [Hierarchy](hierarchy.md) — non-parallel compounds.
- [Server-mode](server-mode.md) — top-level parallel completion stops
  the machine; the server stays alive but refuses events.
