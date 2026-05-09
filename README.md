# ExMachine

[![Hex Version](https://img.shields.io/hexpm/v/ex_machine.svg)](https://hex.pm/packages/ex_machine)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/ex_machine/)
[![License](https://img.shields.io/hexpm/l/ex_machine.svg)](https://github.com/carlotorrese/ex_machine/blob/main/LICENSE)
[![Status](https://img.shields.io/badge/status-alpha-orange.svg)](https://github.com/carlotorrese/ex_machine)

Functional hierarchical state machines for Elixir, aligned with the
[SCXML](https://www.w3.org/TR/scxml/) algorithm and the
[Statechart](https://en.wikipedia.org/wiki/UML_state_machine) formalism.

> **Status — `0.2.0-alpha.1`.** A ground-up rewrite of the 0.1.x line.
> The old API and storage shapes are gone; there is no migration path.
> The engine and server-mode are feature-complete for the SCXML
> pure-execution subset; the public API may still tighten before
> `0.2.0` proper.

## Why ExMachine

- Statecharts in pure Elixir, not a port of XState or SCXML XML.
- Engine is **side-effect-free** (`ExMachine.Engine.dispatch/2`
  returns a new `%Machine{}` value) — trivial to test, trivial to
  reason about.
- Optional **server-mode** wraps the engine in a `GenServer` with
  delayed events, invoked services, pub/sub subscribers, and
  `:telemetry` spans.
- Compile-time validation of the statechart shape (initial substates,
  history placement, transition targets, parallel structure).
- Renderers to **Mermaid** `stateDiagram-v2` and **W3C SCXML XML**.

## Install

```elixir
def deps do
  [{:ex_machine, "~> 0.2.0-alpha.1"}]
end
```

The library's OTP application is registered automatically (the
`mix.exs` `mod:` entry starts a `Registry` for server-mode
subscribers); you do not need to add anything to your own supervision
tree.

## Quick start — pure mode

```elixir
defmodule TrafficLight do
  use ExMachine.Statechart

  initial :red

  state :red,    do: on(:timer, target: :green)
  state :green,  do: on(:timer, target: :yellow)
  state :yellow, do: on(:timer, target: :red)
end

machine = ExMachine.init(TrafficLight)
ExMachine.atomic_states(machine)  # => [:red]

machine = ExMachine.dispatch(machine, :timer)
ExMachine.atomic_states(machine)  # => [:green]
```

## Quick start — server-mode

```elixir
defmodule TrafficLight.Server do
  use ExMachine.Server, statechart: TrafficLight
end

{:ok, _pid} = TrafficLight.Server.start_link(name: :tl)

TrafficLight.Server.subscribe(:tl)
{:ok, snap} = TrafficLight.Server.call_event(:tl, :timer)
snap.atomic_states  # => [:green]

receive do
  {:ex_machine, :transition, %ExMachine.Snapshot{atomic_states: states}} ->
    IO.inspect(states)
end
```

## Features (v0.2)

Engine — pure functional core, SCXML-aligned:

- Atomic, compound, parallel, region, final states
- History pseudostates (shallow + deep)
- Choice pseudostates (recursive)
- Internal vs external transitions
- Eventless ("always") transitions
- Run-to-completion with raised internal events
- `done.state.<id>` propagation, with bubble-up across parallel regions

Server-mode — `GenServer` wrapper:

- `send_event` (cast) and `call_event` (sync, returns snapshot)
- `subscribe` / `unsubscribe` for `{:ex_machine, :transition, snapshot}`
- Delayed events via `Step.send_after/4`
- Invoked services via `Step.invoke/4`, with auto-cancellation when
  the owner state is exited
- `:telemetry` spans around every macrostep

Tooling:

- `ExMachine.Visualize.to_mermaid/2` and `to_scxml/2`
- `ExMachine.Logger.attach/1` for structured logs

## Documentation

Full API documentation on [HexDocs](https://hexdocs.pm/ex_machine).
Topical guides:

- [Getting started](guides/getting-started.md)
- [DSL reference](guides/dsl.md)
- [Hierarchy and compound states](guides/hierarchy.md)
- [Parallel regions](guides/parallel.md)
- [History pseudostates](guides/history.md)
- [Choice pseudostates](guides/choice.md)
- [Transitions: external, internal, eventless](guides/transitions.md)
- [Server-mode](guides/server-mode.md)
- [Delayed events](guides/delayed-events.md)
- [Invoked services](guides/invoked-services.md)
- [Telemetry](guides/telemetry.md)
- [Visualisation](guides/visualisation.md)

## Contributing

Issues and PRs welcome. The current development plan lives in
[`docs/v0.2-rewrite-plan.md`](https://github.com/carlotorrese/ex_machine/blob/main/docs/v0.2-rewrite-plan.md).
Please run the quality gates before opening a PR:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test --warnings-as-errors
mix credo --strict
```

## License

MIT — see [LICENSE](LICENSE).
