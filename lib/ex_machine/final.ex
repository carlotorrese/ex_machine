defmodule ExMachine.Final do
  @moduledoc """
  Represents a final state in a statechart.

  A final state represents a completed region of a statechart. When a state machine
  enters a final state, it indicates that the associated region has completed its
  intended activity. In hierarchical state machines, entering a final state may
  trigger completion events that can be used by parent states.

  ## Fields

  * `:entry` - Optional function to execute when entering the final state.
    This is typically used for cleanup actions or to signal the completion
    of the state machine's purpose.

  ## Examples

      # Define a final state with an entry action
      %ExMachine.Final{
        entry: fn context ->
          # Log completion or cleanup resources
          IO.puts("Process completed successfully")
          context
        end
      }

      # Simple final state without entry action
      %ExMachine.Final{}

  ## Usage in Statechart

  Final states are typically used to represent the successful completion of a
  workflow or process:

      defmodule WorkflowStatechart do
        use ExMachine.Statechart, 
          definition: %{
            initial: "processing",
            states: %{
              "processing" => %{
                transitions: %{"completed" => "done"}
              },
              "done" => %ExMachine.Final{
                entry: fn context ->
                  send_completion_notification(context)
                  context
                end
              }
            }
          }
      end

  """
  @type t :: %__MODULE__{
          entry: function | nil
        }

  defstruct entry: nil
end
