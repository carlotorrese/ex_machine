# Getting started

ExMachine lets you declare a hierarchical state machine at compile
time and run it either as a value (pure mode) or as a `GenServer`
(server mode).

## Install

```elixir
def deps do
  [{:ex_machine, "~> 0.2.0-alpha.1"}]
end
```

The library's OTP application is registered automatically — you do
not need to add anything to your supervision tree.

## Your first statechart

```elixir
defmodule TrafficLight do
  use ExMachine.Statechart

  initial :red

  state :red,    do: on(:timer, target: :green)
  state :green,  do: on(:timer, target: :yellow)
  state :yellow, do: on(:timer, target: :red)
end
```

Each `state` declaration adds a node. `on(event, target: id)` declares
a transition. `initial` picks the starting substate of the root.

## Run it (pure mode)

```elixir
machine = ExMachine.init(TrafficLight)
ExMachine.atomic_states(machine)  # => [:red]

machine = ExMachine.dispatch(machine, :timer)
ExMachine.atomic_states(machine)  # => [:green]
```

`dispatch/2` returns a new `%ExMachine.Machine{}` value. The engine is
side-effect-free; the same `machine` is unchanged.

## Run it (server mode)

```elixir
defmodule TrafficLight.Server do
  use ExMachine.Server, statechart: TrafficLight
end

{:ok, _pid} = TrafficLight.Server.start_link(name: :tl)
{:ok, snap} = TrafficLight.Server.call_event(:tl, :timer)
snap.atomic_states  # => [:green]
```

See [Server-mode](server-mode.md) for `subscribe`, telemetry, and the
async `send_event/2` (cast).

## Where to next

- [DSL reference](dsl.md) — every macro and option.
- [Hierarchy](hierarchy.md) — compound states.
- [Transitions](transitions.md) — internal vs external, eventless,
  guards, actions.
