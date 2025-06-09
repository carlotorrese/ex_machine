defmodule ExMachine.Macrostep do
  @moduledoc """
  (From SCXML): A macrostep consists of a sequence (a chain) of microsteps,
  at the end of which the state machine is in a stable state and ready
  to process an external event.
  Each external event causes an SCXML state machine to take
  exactly one macrostep.
  However, if the external event does not enable any transitions,
  no microstep will be taken, and the corresponding macrostep will be empty.

  (From SISMIC): A macro step corresponds to the process of
  consuming an event, regardless of the number and the type
  (eventless or not) of triggered transitions.
  A macro step also includes every consecutive stabilization step
  (i.e., the steps that are needed to enter nested states,
  or to switch into the configuration of a history state).

  NOTE: microsteps list in in reverse order of execution, so the first
  in list is the last executed. This is for performance reason
  considered that lists are LIFO structure.
  """
  @type t :: %__MODULE__{
          timestamp: NaiveDateTime.t(),
          event: list,
          transitions: list,
          entered: list,
          exited: list,
          actions: list,
          microsteps: list
        }

  defstruct timestamp: nil,
            event: nil,
            transitions: [],
            entered: [],
            exited: [],
            microsteps: [],
            actions: []

  def new() do
    %__MODULE__{timestamp: NaiveDateTime.utc_now()}
  end

end
