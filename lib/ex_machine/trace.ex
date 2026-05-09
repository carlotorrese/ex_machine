defmodule ExMachine.Trace do
  @moduledoc """
  Audit trail of a single macrostep — the sequence of microsteps performed
  while processing one event (or initialising the machine).

  A macrostep is the unit of run-to-completion: it groups every microstep
  triggered by a single external event, plus any internal events those
  microsteps raised, until the machine reaches a stable configuration.

  Traces are pure data, suitable for logging, replay, and assertion in
  tests. They never reference the user's context (we do not snapshot it
  here — the caller can pair the trace with a context value if needed).

  ## Fields

    * `:event` — the event that started the macrostep, or `nil` for the
      initialisation macrostep.
    * `:microsteps` — ordered list of `Microstep` structs, oldest first.
    * `:entered` — flat list of state ids entered across all microsteps,
      in entry order (parent-first within each microstep, microsteps in
      occurrence order).
    * `:exited` — flat list of state ids exited, in exit order.
    * `:transitions` — list of `Transition` structs taken.

  ## Microstep

  Each microstep records:

    * `:event` — event that fired this transition (`nil` for eventless
      and initialisation).
    * `:transitions` — list of `Transition` structs taken atomically in
      this microstep. Empty for the initial microstep. Usually one
      element; multiple elements occur only when several non-conflicting
      transitions across parallel regions fire on the same event.
    * `:exited` — ordered list of state ids exited (child-first).
    * `:entered` — ordered list of state ids entered (parent-first).
  """

  alias __MODULE__
  alias ExMachine.{StateNode, Transition}

  defmodule Microstep do
    @moduledoc "A single atomic step within a macrostep."

    @type t :: %__MODULE__{
            event: term() | nil,
            transitions: [Transition.t()],
            exited: [StateNode.id()],
            entered: [StateNode.id()]
          }

    defstruct event: nil,
              transitions: [],
              exited: [],
              entered: []
  end

  @type t :: %Trace{
          event: term() | nil,
          microsteps: [Microstep.t()],
          entered: [StateNode.id()],
          exited: [StateNode.id()],
          transitions: [Transition.t()]
        }

  defstruct event: nil,
            microsteps: [],
            entered: [],
            exited: [],
            transitions: []

  @doc "Empty macrostep trace for `event`."
  @spec new(term() | nil) :: t()
  def new(event \\ nil), do: %Trace{event: event}

  @doc "Append a microstep to the trace, accumulating entered/exited/transitions."
  @spec push(t(), Microstep.t()) :: t()
  def push(%Trace{} = trace, %Microstep{} = ms) do
    %Trace{
      trace
      | microsteps: trace.microsteps ++ [ms],
        entered: trace.entered ++ ms.entered,
        exited: trace.exited ++ ms.exited,
        transitions: trace.transitions ++ ms.transitions
    }
  end
end
