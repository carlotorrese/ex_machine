# Hierarchy and compound states

A **compound** state is a state that contains other states. Exactly
one of its substates is active at any time; that substate plus all of
its ancestors form the active configuration.

## Declaring a compound

```elixir
defmodule Player do
  use ExMachine.Statechart

  initial :stopped

  state :stopped, do: on(:play, target: :playing)

  state :playing do
    initial :slow                 # required for compound
    on_entry &__MODULE__.start/1  # fires once when entering :playing
    on_exit  &__MODULE__.stop/1   # fires once when exiting :playing
    on :pause, target: :paused

    state :slow, do: on(:go_fast, target: :fast)
    state :fast, do: on(:go_slow, target: :slow)
  end

  state :paused, do: on(:play, target: :playing)
end
```

A compound MUST declare `initial`. The validator rejects compounds
without one at compile time.

## Entry and exit order

When entering a compound, actions fire in **parent-first** order:
`on_entry` of `:playing`, then of `:slow`. When exiting, in
**child-first** order: `on_exit` of `:slow`, then of `:playing`.

Sibling transitions inside the same compound do NOT exit and re-enter
the parent. With `:slow → :fast` above, `:playing.on_exit` does not
fire and `:playing.on_entry` does not fire again.

## LCCA — Least Common Compound Ancestor

The engine computes the LCCA of (source, target) to decide what to
exit and what to enter. For a sibling transition, the LCCA is the
parent compound; only the source and the target are touched. For a
transition that leaves the compound entirely, the LCCA is one level
up; the parent compound's `on_exit` fires.

This is standard SCXML §3.13 behaviour.

## See also

- [Parallel regions](parallel.md) — multiple compounds active at once.
- [History pseudostates](history.md) — restore a previous
  sub-configuration.
- [Transitions](transitions.md) — internal transitions, which override
  LCCA inside a single compound.
