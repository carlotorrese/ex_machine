# CLAUDE.md

Instructions and current context for Claude (or any LLM agent) working in this
repo. Loaded automatically by Claude Code at session start.

## Current work

This branch is **`v0.2`**, an in-flight ground-up rewrite of ExMachine. The
0.1.x line is gone; there is no migration path. The full plan, status table,
and architectural decisions live in:

- **`docs/v0.2-rewrite-plan.md`** — read this first when picking up work.
  Contains the milestone table, completed/remaining work, lessons learned
  from earlier milestones, and the definition of done.

Strategy: one git commit per milestone, authored by Carlo Torrese. Branch
`main` is left untouched until the final merge at M10.

## How to resume

```bash
cd /Users/carlotorrese/Projects/ex_machine
git checkout v0.2
git log --oneline v0.2 ^main      # what's done
mix test                          # confirm green
```

Then open `docs/v0.2-rewrite-plan.md`, find the next ⏳ milestone in the
*Implementation status* table, and proceed.

## Quality gates (run before every commit)

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test --warnings-as-errors
mix credo --strict
```

All four must be green. CI also runs `mix dialyzer` (slow locally — skip
unless investigating typespec issues).

## Project layout

```
lib/ex_machine/
  statechart.ex          DSL macros (use ExMachine.Statechart)
  statechart/builder.ex  internal compile-time helpers
  definition.ex          %Definition{} + validation
  state_node.ex          %StateNode{} (atomic|compound|parallel|region|final|history|choice)
  transition.ex          %Transition{}
  step.ex                %Step{} (accumulator threaded through actions)
  configuration.ex       MapSet of active states + queries
  machine.ex             running instance struct
  engine.ex              SCXML-aligned execution (init/dispatch/microstep/RTC)
  trace.ex               audit trail (macrostep / microstep)
test/ex_machine/
  *_test.exs             unit tests per module
  integration/           end-to-end fixtures + tests
```

## Design constraints (non-obvious, learned the hard way)

- **DSL `action` and `guard` accept only remote captures `&Mod.fun/1`.**
  Inline `fn x -> ... end` closures are rejected by `Macro.escape/1` during
  `__before_compile__`. Always extract closures into named functions of the
  statechart module (or another module).

- **`on_entry/1` and `on_exit/1` collide with `ExUnit.Callbacks.on_exit/1`.**
  When writing test fixtures, define the statechart module **outside** (or
  before) the `defmodule SomeTest do use ExUnit.Case end` block. Nested
  defmodules inherit macro imports from the surrounding module.

- **`Configuration.atomic_states/2` includes both `:atomic` and `:final`
  nodes** — finals are leaves of the statechart hierarchy.

- **`mix.exs` version is single-source via the `@version` module attribute.**
  Don't duplicate the literal in `docs[:source_ref]` or anywhere else.

- **Engine raises** when asked to enter a `:parallel` substate or to
  cross regions. Parallel arrives in M5. History, choice, and internal
  transitions are live since M4.

## Milestone commit convention

```
<scope>(M<n>): <one-line summary>

<body explaining what was added, removed, modified — see commit 79258b3
for the established style>

Build: mix compile --warnings-as-errors, mix test (X doctests + Y tests,
0 failures), mix format --check-formatted, mix credo --strict (0 issues).
```

`<scope>` is `feat` for new functionality, `chore` for tooling, `docs` for
documentation-only changes.

## Things to avoid

- Do not commit on `main` until the rewrite is complete (M10).
- Do not skip the format / credo / warnings-as-errors gates "to come back to
  later". They become harder to fix when accumulated.
- Do not add features outside the current milestone's scope. The plan is
  granular for a reason: M4 should not slip into parallel work (M5).
- Do not use `--no-verify` to push past hooks. If a hook fails, fix the
  cause.
