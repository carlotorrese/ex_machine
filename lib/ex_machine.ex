defmodule ExMachine do
  alias ExMachine.Machine

  @moduledoc """
  ExMachine - A functional implementation of hierarchical state machines based on Statechart formalism.

  ExMachine provides a purely functional approach to defining and executing finite state machines
  that follow the Statechart specification proposed by David Harel in 1987. It supports 
  hierarchical states, entry/exit actions, guard functions, and extended state management.

  ## Features

  - **Hierarchical States**: States can contain substates, creating complex state hierarchies
  - **Entry/Exit Actions**: Execute functions when entering or leaving states  
  - **Transition Actions**: Execute functions during state transitions
  - **Guard Functions**: Conditional logic to control when transitions can occur
  - **Extended State**: Maintain context data that travels with the state machine
  - **Internal Events**: Support for run-to-completion semantics
  - **Compile-time Validation**: State machine definitions are validated at compile time

  ## Basic Usage

      # Define a simple state machine
      defmodule TrafficLight do
        use ExMachine.Statechart
        
        alias ExMachine.State
        
        def definition do
          %State{
            initial: "red",
            substates: %{
              "red" => %State{transitions: %{"timer" => "green"}},
              "green" => %State{transitions: %{"timer" => "yellow"}},
              "yellow" => %State{transitions: %{"timer" => "red"}}
            }
          }
        end
      end
      
      # Use the state machine
      alias ExMachine.{Machine, Statechart}
      
      statechart = Statechart.build(TrafficLight.definition())
      machine = ExMachine.init(statechart, %{})
      machine = ExMachine.dispatch(machine, "timer")

  ## State Machine Execution

  State machines in ExMachine follow these principles:

  1. **Immutable**: Each transition returns a new machine instance
  2. **Functional**: No side effects during transitions (except through actions)
  3. **Deterministic**: Given the same state and event, the result is always the same
  4. **Run-to-completion**: Events are processed completely before the next event

  See the main modules for detailed documentation:

  - `ExMachine.Machine` - Core machine execution logic
  - `ExMachine.Statechart` - State machine definition and validation
  - `ExMachine.State` - Individual state definitions
  - `ExMachine.Transition` - Transition definitions with actions and guards
  """
  @doc """
  Initialize a state machine with the given statechart definition and initial context.

  This is a convenience function that delegates to `ExMachine.Machine.init/2`.

  ## Parameters

  - `statechart` - A compiled statechart definition from `ExMachine.Statechart.build/1`
  - `context` - Initial context data (any term)

  ## Returns

  A running `ExMachine.Machine` in its initial configuration.

  ## Examples

      statechart = Statechart.build(MyStateMachine.definition())
      machine = ExMachine.init(statechart, %{counter: 0})
      
  """
  def init(statechart, context) do
    Machine.init(statechart, context)
  end

  @doc """
  Dispatch an event to a running state machine.

  This is a convenience function that delegates to `ExMachine.Machine.dispatch/2`.

  ## Parameters

  - `machine` - A running `ExMachine.Machine` instance
  - `event` - The event to dispatch (string or atom)

  ## Returns

  A new `ExMachine.Machine` instance with the updated state and context.

  ## Examples

      machine = ExMachine.dispatch(machine, "start")
      machine = ExMachine.dispatch(machine, :stop)

  """
  def dispatch(machine, event) do
    Machine.dispatch(machine, event)
  end
end
