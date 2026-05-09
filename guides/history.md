# History pseudostates

A **history** pseudostate, when targeted by a transition, restores
the sub-configuration of its parent compound at the time it was last
exited.

Two flavours, both supported:

- `:shallow` — restores the direct child of the parent that was
  active.
- `:deep` — restores the entire active substate hierarchy under the
  parent (every nested atomic).

## Declaring history

```elixir
defmodule Player do
  use ExMachine.Statechart

  initial :stopped

  state :stopped do
    on :play,   target: :playing       # always re-enter from the initial
    on :resume, target: :h_play        # re-enter from history
  end

  state :playing do
    initial :slow

    history :h_play, type: :shallow, default: :fast

    on :pause, target: :stopped

    state :slow, do: on(:go_fast, target: :fast)
    state :fast, do: on(:go_slow, target: :slow)
  end
end
```

`default:` is the substate to enter when no history snapshot has been
recorded yet. If you omit `default:`, the parent's `:initial` is used
as the fallback.

## Behaviour

- The snapshot is taken **as the parent compound is exited**, BEFORE
  its children are removed from the configuration.
- The snapshot lives on `machine.histories`, keyed by the history
  pseudostate id. It survives across transitions and is overwritten
  on the next exit of the parent.
- A transition targeting the history pseudostate is treated as a
  transition into the parent: the parent's `on_entry` fires once,
  then the recorded sub-configuration is restored (re-running each
  restored state's `on_entry`).

## Deep history

Use `type: :deep` to restore every nested atomic descendant — useful
when the compound contains a sub-compound that itself has its own
sub-state.

```elixir
state :playing do
  initial :mode

  history :h_deep, type: :deep        # no default needed if mode.initial covers it

  state :mode do
    initial :slow
    state :slow, do: on(:go_fast, target: :fast)
    state :fast, do: on(:go_slow, target: :slow)
  end
end
```

A round-trip out of `:playing` and back via `:h_deep` restores
`:mode → :fast` (or whichever leaf was active), not just `:mode →
:slow` from `:initial`.
