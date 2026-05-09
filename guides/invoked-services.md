# Invoked services

In server-mode, an action can spawn a long-running task tied to a
state's lifetime. The task runs under a per-server `Task.Supervisor`;
on completion the server raises `done.invoke.<id>` (or
`error.invoke.<id>` on failure) which the statechart can react to.

Pure mode collects the request on `machine.pending_invokes` for
inspection but does not spawn anything — only `ExMachine.Server`
honours invocations.

## Declare

```elixir
defmodule Loader do
  use ExMachine.Statechart
  alias ExMachine.Step

  initial :idle

  state :idle, do: on(:start, target: :loading)

  state :loading do
    on_entry &__MODULE__.start_fetch/1
    on :"done.invoke.fetch",  target: :ready
    on :"error.invoke.fetch", target: :failed
    on :cancel,                target: :idle
  end

  state :ready
  state :failed

  def start_fetch(%Step{} = s) do
    Step.invoke(s, :fetch, fn -> HTTP.get!("/users/42") end, :loading)
  end
end
```

`Step.invoke(step, id, fun_or_mfa, owner_state)`:

- `id` is a **user-chosen atom**. The DSL must be able to declare a
  transition that matches `done.invoke.<id>` / `error.invoke.<id>` at
  compile time, so the id cannot be opaque.
- `fun_or_mfa` is either a zero-arity function or an
  `{module, function, args}` triple.
- `owner_state` is the state that owns the invocation. The task is
  killed automatically when this state is exited.

## Result delivery

- On success, the server raises `done.invoke.<id>` with the function's
  return value as event params. Pattern-match in a transition action:

  ```elixir
  on :"done.invoke.fetch", target: :ready, action: &__MODULE__.assign_user/1
  def assign_user(%Step{event: {_event, user}} = s), do: Step.assign(s, :user, user)
  ```

- On failure (raise, exit, `Process.exit/2`), the server raises
  `error.invoke.<id>` with the crash reason as event params.

## Auto-cancel on exit

In the example above, dispatching `:cancel` from `:loading` exits the
state. The server walks `machine.trace.exited`, finds the running
task whose `owner_state == :loading`, demonitors and kills it. The
result never arrives.

## Explicit cancel

```elixir
def stop_fetch(%Step{} = s), do: Step.cancel(s, :fetch)
```

Pass the same atom id you used in `Step.invoke/4`.

## Why a per-server Task.Supervisor

Each `ExMachine.Server` brings up its own `Task.Supervisor` linked to
the server. The server is `trap_exit: true` so a crashing
user-supplied task does not crash the server — the `:DOWN` lands in
`handle_info` and becomes an `error.invoke.<id>` event.
