defmodule ExMachine.History do
  @moduledoc """
  Represents a history state in a statechart.

  History states provide a way to remember the most recent active state 
  configuration when exiting a composite state, allowing the state machine
  to resume from where it left off when re-entering that region.

  ExMachine supports two types of history states:

  * `:shallow` - Remembers only the immediate child state that was active
  * `:deep` - Remembers the entire active state configuration, including
    nested states at all levels

  ## Fields

  * `:type` - The type of history state (`:shallow` or `:deep`)

  ## Examples

      # Shallow history - remembers only immediate child
      %ExMachine.History{type: :shallow}

      # Deep history - remembers full nested configuration
      %ExMachine.History{type: :deep}

  ## Usage in Statechart

  History states are particularly useful in scenarios where you want to
  preserve user context when temporarily leaving a region:

      defmodule MediaPlayerStatechart do
        use ExMachine.Statechart,
          definition: %{
            initial: "stopped",
            states: %{
              "stopped" => %{
                transitions: %{"play" => "playing"}
              },
              "playing" => %{
                initial: "normal_speed",
                transitions: %{
                  "pause" => "paused",
                  "stop" => "stopped"
                },
                states: %{
                  "normal_speed" => %{
                    transitions: %{"fast_forward" => "fast"}
                  },
                  "fast" => %{
                    transitions: %{"normal" => "normal_speed"}
                  }
                }
              },
              "paused" => %{
                transitions: %{
                  "play" => "playing.history",  # Resume from where paused
                  "stop" => "stopped"
                }
              },
              "playing.history" => %ExMachine.History{type: :deep}
            }
          }
      end

  In this example, when the media player is paused and then resumed,
  it will return to the exact same playback mode (normal or fast forward)
  that was active before pausing.

  """
  @type t :: %__MODULE__{
          type: :deep | :shallow
        }

  defstruct type: nil
end
