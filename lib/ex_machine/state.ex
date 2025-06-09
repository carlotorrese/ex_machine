defmodule ExMachine.State do
  @moduledoc """
  Represents a state in a hierarchical statechart.

  A state is the fundamental building block of a statechart and can itself
  be a statechart (containing hierarchical substates). States can be simple
  (leaf nodes) or composite (containing other states), and they define the
  structure and behavior of your state machine.

  ## State Types

  ExMachine supports several types of states:

  * **Simple states** - Leaf nodes with no substates
  * **Composite states** - Container states with substates  
  * **Final states** - Terminal states indicating completion
  * **History states** - Pseudo-states that remember previous configurations

  ## Fields

  * `:initial` - Name of the initial substate (required for composite states)
  * `:substates` - Map of substate name to state definition
  * `:transitions` - Map of event names to transition definitions
  * `:entry` - Optional function executed when entering the state
  * `:exit` - Optional function executed when exiting the state

  ## State Composition

  States can be composed in a hierarchical manner, where a composite state
  contains multiple substates. This allows for modeling complex behaviors
  with clear organization and state inheritance.

  ## Examples

  ### Simple State

      %ExMachine.State{
        transitions: %{
          "start" => "working"
        },
        entry: fn context ->
          IO.puts("Entering idle state")
          context
        end
      }

  ### Composite State with Substates

      %ExMachine.State{
        initial: "connecting",
        substates: %{
          "connecting" => %ExMachine.State{
            transitions: %{
              "connected" => "authenticated",
              "timeout" => "failed"
            },
            entry: fn context ->
              start_connection_timer(context)
            end
          },
          "authenticated" => %ExMachine.State{
            transitions: %{
              "disconnect" => "disconnected"
            }
          },
          "failed" => %ExMachine.Final{
            entry: fn context ->
              log_connection_failure(context)
            end
          }
        },
        transitions: %{
          "reset" => "connecting"
        }
      }

  ### State with Entry and Exit Actions

      %ExMachine.State{
        entry: fn context ->
          # Initialize resources, start timers, etc.
          context
          |> put(:start_time, System.system_time(:second))
          |> put(:status, :active)
        end,
        exit: fn context ->
          # Cleanup resources, stop timers, etc.
          cleanup_resources(context)
          delete(context, :start_time)
        end,
        transitions: %{
          "complete" => "finished",
          "cancel" => "cancelled"
        }
      }

  ## State Definition Best Practices

  ### 1. Clear State Names
  Use descriptive names that clearly indicate the state's purpose:

      # Good
      "user_authenticated"
      "payment_processing"  
      "document_uploading"

      # Avoid
      "state1"
      "temp"
      "misc"

  ### 2. Proper State Hierarchy
  Organize related states under common parent states:

      %ExMachine.State{
        initial: "idle",
        substates: %{
          "idle" => %{...},
          "active" => %ExMachine.State{
            initial: "processing",
            substates: %{
              "processing" => %{...},
              "waiting" => %{...},
              "complete" => %{...}
            }
          }
        }
      }

  ### 3. Meaningful Actions
  Keep entry and exit actions focused and idempotent:

      entry: fn context ->
        # Good: specific, focused action
        context
        |> start_session_timer()
        |> log_state_entry("authenticated")
      end

  ### 4. Consistent Transition Events
  Use consistent event naming across your statechart:

      # Consistent event names
      "user_login", "user_logout"
      "payment_start", "payment_complete", "payment_failed"
      "doc_upload", "doc_process", "doc_complete"

  ## Usage in Statechart Definitions

      defmodule WorkflowStatechart do
        use ExMachine.Statechart,
          definition: %{
            initial: "draft",
            states: %{
              "draft" => %ExMachine.State{
                entry: fn context ->
                  put(context, :created_at, DateTime.utc_now())
                end,
                transitions: %{
                  "submit" => %{
                    target: "review",
                    guard: fn context -> 
                      validate_document(context) 
                    end
                  }
                }
              },
              "review" => %ExMachine.State{
                initial: "pending",
                substates: %{
                  "pending" => %ExMachine.State{
                    transitions: %{
                      "approve" => "approved",
                      "reject" => "rejected"
                    }
                  },
                  "approved" => %ExMachine.Final{},
                  "rejected" => %ExMachine.State{
                    transitions: %{
                      "revise" => "draft"
                    }
                  }
                }
              }
            }
          }
      end

  ## State Lifecycle

  When a state machine transitions between states, the following lifecycle
  events occur in order:

  1. **Exit actions** of exited states (most nested first)
  2. **Transition action** (if any)
  3. **Entry actions** of entered states (least nested first)

  This ensures proper cleanup and initialization of state-specific resources.

  """
  @type t :: %__MODULE__{
          initial: String.t() | nil,
          substates: %{required(String.t()) => t()},
          transitions: %{required(String.t()) => String.t() | map()},
          entry: function() | nil,
          exit: function() | nil
        }

  defstruct initial: nil,
            substates: %{},
            transitions: %{},
            entry: nil,
            exit: nil
end
