defmodule ExMachine.Microstep do
  @moduledoc """
  Trace and record an execution step in the statechart

  (From SCXML): A microstep involves the processing of a single transition
  (or, in the case of parallel states, a single set of transitions.)
  A microstep may change the active configuration, update the data
  model and/or generate new (internal and/or external) events.
  This, by causality, may in turn enable additional transitions which
  will be handled in the next microstep in the sequence, and so on.

  (From SISMIC): The smallest, atomic step that a statechart can execute.
  A step consider event, takes a transition and results in a list of
  entered states and a list of exited states.
  Order in the two lists is REALLY important!

  Parameters:
  * `event`: event or `nil` in case of eventless transition.
  If event has parameters the term is in the form {event, params}
  * `transition`: a Transition or `nil` if no processed transition
  * `entered`: possibly empty list of entered states
  * `exited`: possibly empty list of exited states
  * `actions`: a possibly empty list of actions that are executed during the step

  """
  @type t :: %__MODULE__{
          params: term,
          transition: term,
          entered: list,
          exited: list,
          actions: list
        }

  defstruct params: nil,
            transition: nil,
            entered: [],
            exited: [],
            actions: []

  def new(), do: %__MODULE__{}
end
