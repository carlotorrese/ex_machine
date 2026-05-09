# Transitions

A transition binds an event (or eventless trigger) and an optional
guard to an optional target and an optional action.

```elixir
on event_or_nil, opts
```

`opts`:

- `:target` — destination state id, or omitted for action-only
  transitions.
- `:guard` — `(context -> boolean)`; the transition fires only if the
  guard returns `true`.
- `:action` — `(Step -> Step)`; runs after `on_exit` of the source
  chain and before `on_entry` of the target chain.
- `:type` — `:external` (default) or `:internal`.

## External vs internal

An **external** transition exits and re-enters the LCCA of source and
target. If the target is a sibling of the source under a compound
parent, the parent itself stays active (LCCA is the parent compound,
not above).

An **internal** transition is honoured ONLY when:

- the source is a `:compound` or `:region`, AND
- the target is a proper descendant of the source.

In that case the LCCA is the source itself: the source is **not**
exited, and the descendant moves freely. Outside that case the
transition degrades to `:external` semantics — this is SCXML §3.13.

```elixir
state :running do
  initial :a
  on :tick, action: &__MODULE__.bump/1, type: :internal   # action-only, no exit/enter
  on :to_b, target: :b, type: :internal                   # moves :a -> :b without exiting :running

  state :a, do: on(:next, target: :b)
  state :b, do: on(:next, target: :a)
end
```

## Eventless transitions

Pass `nil` (or `event: nil`) to declare an eventless ("always")
transition. It is eligible after every microstep and chains until
none is enabled.

```elixir
state :a, do: on(nil, target: :b)
state :b, do: on(nil, target: :c)
state :c
```

`ExMachine.init/1` for that fixture lands directly in `:c`.

## Self-transitions

`on(:bump, target: :s)` from inside `state :s` is an external
self-transition: source exits, then re-enters. Use
`type: :internal` if you only want the action to fire (without
re-running entry/exit).

## Run-to-completion

Actions can raise internal events with `Step.raise_event/2`. They are
processed in the same macrostep, in order, before any further
external event is read. Eventless transitions interleave with raised
events: the engine prefers eventless until none is enabled, then
drains the raised queue.
