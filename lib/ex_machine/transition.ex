defmodule ExMachine.Transition do
  @moduledoc """
  Defines a state transition with optional guard functions and actions.

  Transitions specify how a state machine moves from one state to another in response
  to events. They can include conditional logic (guards) and side effects (actions).

  ## Structure

  A transition contains:

  - `target` - The destination state name  
  - `guard` - Optional function that must return `true` for the transition to fire
  - `action` - Optional function to execute when the transition is taken

  ## Guard Functions

  Guards are predicates that determine whether a transition should be taken.
  They receive the current context and must return a boolean:

      guard: fn context -> context.counter > 10 end

  If multiple transitions from the same state have the same trigger event,
  guards are used to determine which transition should fire.

  ## Action Functions  

  Actions are executed when a transition is taken and can modify the context:

      action: fn context -> %{context | counter: context.counter + 1} end

  Actions should be pure functions that return the new context state.

  ## Usage

  Transitions can be defined in several ways:

      # Simple transition (just target state)
      "event" => "target_state"
      
      # Transition with action
      "event" => %Transition{
        target: "target_state",
        action: fn context -> %{context | value: "new_value"} end
      }
      
      # Transition with guard and action  
      "event" => %Transition{
        target: "target_state",
        guard: fn context -> context.ready? end,
        action: fn context -> %{context | attempts: context.attempts + 1} end
      }

  ## Examples

      # Conditional transition based on context
      %Transition{
        target: "success",
        guard: fn context -> context.password == "secret" end,
        action: fn context -> %{context | authenticated: true} end
      }
      
      # Transition that modifies context
      %Transition{
        target: "counting", 
        action: fn context -> Map.update(context, :count, 1, &(&1 + 1)) end
      }

  """

  @type t :: %__MODULE__{
          target: String.t(),
          guard: function | nil,
          action: function | nil
        }
  defstruct target: nil,
            guard: nil,
            action: nil

  @doc """
  Create a new transition with just a target state.

  ## Examples

      Transition.new("target_state")

  """
  def new(target) do
    %__MODULE__{target: target}
  end
end
