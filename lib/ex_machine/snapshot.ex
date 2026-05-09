defmodule ExMachine.Snapshot do
  @moduledoc """
  Read-only view of a `ExMachine.Machine` returned by
  `ExMachine.Server.get_snapshot/1`, the synchronous reply of
  `ExMachine.Server.call_event/2`, and broadcast to subscribers as
  `{:ex_machine, :transition, %ExMachine.Snapshot{}}`.

  Snapshots are pure data and safe to copy across process boundaries:
  they never reference the running `GenServer` or its definition. Carry
  only what callers and observers need to introspect the machine.

  ## Fields

    * `:configuration` — `MapSet.t/1` of currently active state ids.
    * `:context` — the user's context after run-to-completion.
    * `:atomic_states` — sorted list of active leaf state ids.
    * `:running?` — `false` once the machine has reached a terminal
      configuration; subsequent events are refused by the server.
    * `:trace` — the `ExMachine.Trace` of the macrostep that produced
      this snapshot. The init snapshot carries the init macrostep.
  """

  alias ExMachine.{Machine, Trace}

  @type t :: %__MODULE__{
          configuration: MapSet.t(atom()),
          context: term(),
          atomic_states: [atom()],
          running?: boolean(),
          trace: Trace.t() | nil
        }

  defstruct [:configuration, :context, :atomic_states, :running?, :trace]

  @doc "Build a snapshot from a `%Machine{}`."
  @spec from_machine(Machine.t()) :: t()
  def from_machine(%Machine{} = m) do
    %__MODULE__{
      configuration: m.configuration,
      context: m.context,
      atomic_states: Machine.atomic_states(m),
      running?: m.running?,
      trace: m.trace
    }
  end
end
