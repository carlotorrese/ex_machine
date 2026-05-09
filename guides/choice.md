# Choice pseudostates

A **choice** pseudostate evaluates a set of guarded branches when it
is reached as a transition target, and delegates entry to the first
matching branch's target. It never appears in the active
configuration.

Choice resolution happens **before** LCCA computation: the resolved
target drives all set computation. Guards see the pre-exit context to
keep the choice deterministic relative to the dispatched event.

## Declaring a choice

```elixir
defmodule Router do
  use ExMachine.Statechart

  initial :lobby

  state :lobby, do: on(:enter, target: :gate)

  choice :gate do
    cond_branch &__MODULE__.admin?/1,  target: :admin_room
    cond_branch &__MODULE__.member?/1, target: :member_room
    otherwise                          target: :guest_room
  end

  state :admin_room
  state :member_room
  state :guest_room

  def admin?(%{role: :admin}),   do: true
  def admin?(_),                 do: false
  def member?(%{role: :member}), do: true
  def member?(_),                do: false
end
```

The first branch whose guard returns `true` wins; `otherwise` is the
default. If no branch matches and there is no `otherwise`, the engine
raises with the name of the offending choice.

## Recursive choices

A branch may target another `choice` — the engine follows the chain
recursively until it lands on a real state.

```elixir
choice :gate do
  cond_branch &__MODULE__.fast_path?/1, target: :direct_target
  otherwise                              target: :next_choice
end

choice :next_choice do
  cond_branch &__MODULE__.beta?/1, target: :beta_room
  otherwise                         target: :default_room
end
```

## Note for SCXML interop

W3C SCXML does not have a `choice` pseudostate; it expresses the same
intent with multiple guarded `<transition cond="...">` on the source.
`ExMachine.Visualize.to_scxml/2` therefore emits a comment in place
of a choice — translate by hand if you need a lossless round-trip.
