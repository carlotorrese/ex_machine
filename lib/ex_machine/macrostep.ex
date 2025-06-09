defmodule ExMachine.Macrostep do
  @moduledoc """
  Represents a macrostep in statechart execution.

  A macrostep consists of a sequence (a chain) of microsteps, at the end of which
  the state machine is in a stable state and ready to process an external event.
  Each external event causes an ExMachine state machine to take exactly one macrostep.
  However, if the external event does not enable any transitions, no microstep
  will be taken, and the corresponding macrostep will be empty.

  ## Definition (From SCXML)

  A macrostep consists of a sequence (a chain) of microsteps, at the end of which
  the state machine is in a stable state and ready to process an external event.
  Each external event causes an SCXML state machine to take exactly one macrostep.
  However, if the external event does not enable any transitions, no microstep
  will be taken, and the corresponding macrostep will be empty.

  ## Definition (From SISMIC)

  A macro step corresponds to the process of consuming an event, regardless of
  the number and the type (eventless or not) of triggered transitions.
  A macro step also includes every consecutive stabilization step
  (i.e., the steps that are needed to enter nested states, or to switch into
  the configuration of a history state).

  ## Fields

  * `:timestamp` - When the macrostep started execution
  * `:event` - The external event that triggered this macrostep
  * `:transitions` - List of all transitions taken during this macrostep
  * `:entered` - List of all states entered during this macrostep
  * `:exited` - List of all states exited during this macrostep  
  * `:actions` - List of all actions executed during this macrostep
  * `:microsteps` - List of microsteps that comprise this macrostep

  ## Important Notes

  * The microsteps list is in reverse order of execution (LIFO structure)
    for performance reasons. The first element in the list is the last
    executed microstep.
  * A macrostep may contain multiple microsteps if internal events are
    raised or if eventless transitions are triggered.

  ## Examples

      # Create a new macrostep
      macrostep = ExMachine.Macrostep.new()

      # A typical macrostep after processing a "login" event might look like:
      %ExMachine.Macrostep{
        timestamp: ~N[2023-06-09 10:30:45],
        event: {:login, %{username: "john", password: "secret"}},
        transitions: ["logged_out -> logged_in"],
        entered: ["logged_in"],
        exited: ["logged_out"],
        actions: [:validate_credentials, :create_session],
        microsteps: [
          %ExMachine.Microstep{...},  # Last executed (reverse order)
          %ExMachine.Microstep{...}   # First executed
        ]
      }

  ## Usage in Debugging and Monitoring

  Macrosteps provide a complete audit trail of state machine execution,
  making them invaluable for debugging, monitoring, and understanding
  the behavior of complex statecharts:

      # In a GenServer-based state machine
      def handle_event(event, state) do
        {new_state, macrostep} = ExMachine.Machine.process_event(state, event)
        
        # Log macrostep for debugging
        Logger.info("Macrostep completed", %{
          event: macrostep.event,
          transitions: length(macrostep.transitions),
          states_entered: macrostep.entered,
          states_exited: macrostep.exited,
          duration: NaiveDateTime.diff(NaiveDateTime.utc_now(), macrostep.timestamp, :microsecond)
        })
        
        {:noreply, new_state}
      end

  """
  @type t :: %__MODULE__{
          timestamp: NaiveDateTime.t(),
          event: term(),
          transitions: list(String.t()),
          entered: list(String.t()),
          exited: list(String.t()),
          actions: list(atom()),
          microsteps: list(ExMachine.Microstep.t())
        }

  defstruct timestamp: nil,
            event: nil,
            transitions: [],
            entered: [],
            exited: [],
            microsteps: [],
            actions: []

  @doc """
  Create a new macrostep with current timestamp.

  ## Examples

      iex> macrostep = ExMachine.Macrostep.new()
      iex> is_struct(macrostep, ExMachine.Macrostep)
      true
      iex> is_struct(macrostep.timestamp, NaiveDateTime)
      true

  """
  def new() do
    %__MODULE__{timestamp: NaiveDateTime.utc_now()}
  end
end
