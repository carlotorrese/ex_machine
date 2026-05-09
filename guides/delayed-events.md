# Delayed events

In server-mode, an action can schedule an event to be delivered to
the same machine after a delay. Pure mode collects the request on
`machine.pending_delayed` for inspection, but does not act on it —
only `ExMachine.Server` honours delayed sends.

## Schedule

```elixir
defmodule Doorbell do
  use ExMachine.Statechart
  alias ExMachine.Step

  initial :idle

  state :idle, do: on(:press, target: :ringing)

  state :ringing do
    on_entry &__MODULE__.schedule_silence/1
    on :silence, target: :idle
    on :hush,    target: :idle
  end

  def schedule_silence(%Step{} = s) do
    {_ref, s} = Step.send_after(s, :silence, 50, :ringing)
    s
  end
end
```

`Step.send_after(step, event, ms, owner_state)`:

- schedules `event` to be re-dispatched to this server after `ms`
  milliseconds;
- returns `{ref, step}` so the caller can later `Step.cancel(step,
  ref)`;
- records `owner_state` so the timer is **cancelled automatically**
  when that state is exited.

## Auto-cancel on exit

In the example above, dispatching `:hush` exits `:ringing` before the
50ms delay elapses. The pending `:silence` timer is cancelled by the
server (because `:ringing` is in `machine.trace.exited` after the
macrostep). The user never sees a stale `:silence`.

## Explicit cancel

```elixir
def cancel_silence(%Step{} = s, ref), do: Step.cancel(s, ref)
```

Pass the ref returned by `send_after/4` to `Step.cancel/2`. The
server consumes `machine.pending_cancels` after the macrostep and
cancels the matching `Process.send_after` timer.

## Behaviour after the server has stopped

If the machine reaches a terminal configuration before a timer fires,
the timer is left to expire silently — the server is alive but
refuses events, so the timer message is observed and dropped without
side effect.
