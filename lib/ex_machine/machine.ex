defmodule ExMachine.Machine do
  @moduledoc """
  Running instance of a statechart.

  A `Machine` ties together a compiled `ExMachine.Definition`, the current
  active `ExMachine.Configuration`, the user's context, and the trace of
  the most recent macrostep. Machines are values: every transition returns
  a new struct, leaving the old one untouched.

  Use `ExMachine.init/1` and `ExMachine.dispatch/2` (or
  `ExMachine.Engine.init/1` and `ExMachine.Engine.dispatch/2` directly) to
  run a machine.

  ## Fields

    * `:definition` — the compiled statechart.
    * `:configuration` — `MapSet` of currently active state ids.
    * `:context` — user-defined data; the only thing actions can mutate.
    * `:running?` — `false` once the root has reached a top-level final
      state. A non-running machine raises on `dispatch/2`.
    * `:histories` — map of `composite_id => MapSet.t()` recording the
      sub-configuration of compounds with a history pseudostate when they
      are exited. Empty until milestone M4.
    * `:queue` — internal queue of events raised by actions, drained in
      the same macrostep (run-to-completion).
    * `:trace` — `ExMachine.Trace` of the latest macrostep. Reset at the
      start of each `dispatch/2`.
  """

  alias ExMachine.{Configuration, Definition, Trace}

  @type t :: %__MODULE__{
          definition: Definition.t(),
          configuration: Configuration.t(),
          context: term(),
          running?: boolean(),
          histories: %{atom() => MapSet.t(atom())},
          queue: [term()],
          trace: Trace.t()
        }

  @enforce_keys [:definition]
  defstruct definition: nil,
            configuration: nil,
            context: nil,
            running?: false,
            histories: %{},
            queue: [],
            trace: nil

  defmodule NotRunning do
    defexception message: "machine is not running (a top-level final has been entered)"
  end

  @doc """
  Build a machine value from a compiled definition. Does not yet enter the
  initial state — call `ExMachine.Engine.init/1` to start.
  """
  @spec new(Definition.t(), term()) :: t()
  def new(%Definition{} = def_, context \\ nil) do
    %__MODULE__{
      definition: def_,
      configuration: Configuration.new(),
      context: context || def_.initial_context,
      running?: false,
      trace: Trace.new()
    }
  end

  @doc "Convenience: list of currently active atomic state ids."
  @spec atomic_states(t()) :: [atom()]
  def atomic_states(%__MODULE__{} = machine) do
    Configuration.atomic_states(machine.configuration, machine.definition)
  end
end
