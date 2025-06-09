defmodule ExMachine.Transition do
  @type t :: %__MODULE__{
          target: String.t(),
          guard: function | nil,
          action: function | nil
        }
  defstruct target: nil,
            guard: nil,
            action: nil

  def new(target) do
    %__MODULE__{target: target}
  end
end
