# Server-mode

`use ExMachine.Server, statechart: Mod` wraps a statechart in a
`GenServer` you can `cast` and `call` events at.

```elixir
defmodule TrafficLight.Server do
  use ExMachine.Server, statechart: TrafficLight
end
```

## Lifecycle

```elixir
{:ok, pid} = TrafficLight.Server.start_link(name: :tl, context: %{cycles: 0})
```

- `:name` — registered name.
- `:context` — overrides the statechart's `initial_context`.
- Other keys are passed through to `GenServer.start_link/3`.

## Sending events

```elixir
:ok                              = TrafficLight.Server.send_event(:tl, :timer)
{:ok, %ExMachine.Snapshot{}}     = TrafficLight.Server.call_event(:tl, :timer)
{:ok, %ExMachine.Snapshot{}}     = TrafficLight.Server.call_event(:tl, :timer, %{from: :ui})
```

`send_event/2` is `GenServer.cast` — fire-and-forget. `call_event/2`
is synchronous and returns the snapshot of the new state.

## Reading state

```elixir
TrafficLight.Server.get_configuration(:tl)  # %MapSet{}
TrafficLight.Server.get_context(:tl)        # term
TrafficLight.Server.get_snapshot(:tl)       # %Snapshot{}
```

## Subscribing

```elixir
TrafficLight.Server.subscribe(:tl)

# Then in the receive loop:
receive do
  {:ex_machine, :transition, %ExMachine.Snapshot{atomic_states: states}} -> ...
  {:ex_machine, :stopped, reason} -> ...
end

TrafficLight.Server.unsubscribe(:tl)
```

A subscriber that registers twice still receives one message per
event — duplicates are dropped at the dispatch site.

When `server` is a registered name (or a `{:via, _, _}` /
`{name, node}` reference), the subscription is keyed by that name,
not by the server's PID. This means subscriptions **survive a
supervised restart** — a `restart: :transient` child that comes
back under the same name keeps delivering notifications without
re-subscribing.

## Terminal configurations

When the machine reaches a terminal configuration (top-level final or
every region of a parallel root done), the server **does not
terminate**. It stays alive so subscribers can still query the final
snapshot, but refuses further events:

- `send_event/2` is silently dropped.
- `call_event/2` returns `{:error, :not_running}`.

Use `stop/1` to terminate explicitly:

```elixir
TrafficLight.Server.stop(:tl)
```

## See also

- [Delayed events](delayed-events.md)
- [Invoked services](invoked-services.md)
- [Telemetry](telemetry.md)
