# DSL reference

`use ExMachine.Statechart` turns the host module into a statechart.
Every declaration is processed at compile time; the resulting
`%ExMachine.Definition{}` is exposed via `__statechart__/0` and is
already validated.

## Module options

```elixir
use ExMachine.Statechart, type: :compound | :parallel, root: :id
```

- `:type` — `:compound` (default) or `:parallel` for the root.
- `:root` — id atom for the root node. Defaults to the module's
  basename underscored.

## Top-level declarations

| Macro | Purpose |
|------|---------|
| `initial id` | Initial substate of the root. |
| `initial_context term` | Default context for fresh machines. |
| `state id [, opts] [, do: body]` | Declare a substate. |
| `parallel id [, opts] [, do: body]` | Declare a parallel substate. |
| `region id, do: body` | Direct child of `parallel`. |
| `final id` | Terminal leaf; emits `done.state.<parent>`. |
| `history id, type: :shallow \| :deep, default: id` | History pseudostate. |
| `choice id, do: body` | Choice pseudostate (cond_branch / otherwise). |

## Inside a `state` / `region`

```elixir
state :running do
  on_entry &__MODULE__.log_enter/1
  on_exit  &__MODULE__.log_exit/1

  on :tick, target: :next, guard: &__MODULE__.allowed?/1, action: &__MODULE__.bump/1
  on nil, target: :auto                       # eventless
  on :inner, target: :child, type: :internal  # internal transition
end
```

- `on_entry/1` and `on_exit/1` append `(Step -> Step)` actions.
- `on event, opts` declares a transition. Options:
  `target`, `guard`, `action`, `type` (`:external` default,
  `:internal` keeps the source active).
- An eventless transition uses `event: nil` (or pass `nil` directly).

## Inside a `choice` body

```elixir
choice :gate do
  cond_branch &__MODULE__.admin?/1, target: :admin_room
  cond_branch &__MODULE__.member?/1, target: :member_room
  otherwise target: :guest_room
end
```

The first branch whose guard returns `true` wins; `otherwise` is the
default fallback. Branches may target another choice — the engine
follows the chain recursively.

## Constraints learned the hard way

- `action`, `guard`, `on_entry`, `on_exit` accept **only remote
  captures** (`&Mod.fun/1`). Inline `fn -> ... end` is rejected by
  `Macro.escape/1` in `__before_compile__`. Always extract the
  closure into a named function.
- The DSL macro `on_exit/1` collides with `ExUnit.Callbacks.on_exit/1`.
  In test files, define statechart fixtures as **separate top-level
  modules**, not nested inside `defmodule SomeTest do use ExUnit.Case`.
