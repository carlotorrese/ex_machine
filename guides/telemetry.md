# Telemetry

`ExMachine.Server` emits `:telemetry` events around every macrostep.
The pure engine emits **nothing** — it stays free of side effects so
direct callers of `ExMachine.dispatch/2` can reason about it like any
other pure function.

## Events

| Event | Measurements | Metadata |
|------|--------------|----------|
| `[:ex_machine, :macrostep, :start]` | `system_time` | `server`, `event` |
| `[:ex_machine, :macrostep, :stop]`  | `duration`    | `server`, `event`, `snapshot` |
| `[:ex_machine, :macrostep, :exception]` | `duration` | `server`, `event`, `kind`, `reason`, `stacktrace` |
| `[:ex_machine, :transition]`        | `count`       | `server`, `event`, `transitions` |
| `[:ex_machine, :stopped]`           | `system_time` | `server`, `reason`, `snapshot` |

`:macrostep` is a `:telemetry.span/3`: every `:start` is matched by a
`:stop` or `:exception`. `:transition` fires once per macrostep with
the list of `%Transition{}` taken (typically one element; multiple
when several non-conflicting transitions across parallel regions
fire on the same event). `:stopped` fires once when the machine
reaches a terminal configuration.

## Attaching

Module-function handler (recommended — `:telemetry` warns about
local anonymous handlers):

```elixir
defmodule MyTelemetry do
  def handle(event, measurements, metadata, _config) do
    Logger.info("#{inspect(event)} #{inspect(metadata[:event])} " <>
                "duration_us=#{System.convert_time_unit(measurements.duration || 0, :native, :microsecond)}")
  end
end

:telemetry.attach_many(
  "my-handler",
  [
    [:ex_machine, :macrostep, :stop],
    [:ex_machine, :transition]
  ],
  &MyTelemetry.handle/4,
  nil
)
```

## Built-in logger

```elixir
ExMachine.Logger.attach(level: :debug)
# ...
ExMachine.Logger.detach()
```

Logs one line per `:macrostep, :stop`, `:transition`, `:exception`,
and `:stopped`. Useful in development; replace with your own handler
in production.
