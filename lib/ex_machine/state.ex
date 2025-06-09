defmodule ExMachine.State do
  @moduledoc """
  Module for defining a state in a statechart.

  A state is the main building block of a statechart and is itself
  a statechart (the root state of a hierarchy of states).
  Typically a state is made up of one or more substates, each one a simple
  state or composed by another substates and so on.

  A substate can be totally defined in the State definition or can reference a
  State defined in other module (state composability)

  ExStatechart support the following type of state:
  * `:simple`
  * `:composite`
  * `:final` pseudostate
  * `choice`???

  When you define a state module, you must supply a well formed state definition
  through the `:definition` options, in the `use ExStatechart.State`.
  The definition is loaded and verified at compile time and without
  this definition the state is unusable.

  """
  @type t :: %__MODULE__{
          initial: String.t(),
          substates: %{required(String.t()) => t},
          transitions: %{required(String.t()) => String.t()},
          entry: function | nil,
          exit: function | nil
        }

  defstruct initial: nil,
            substates: %{},
            transitions: %{},
            entry: nil,
            exit: nil
end
