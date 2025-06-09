defmodule ExMachine.Final do
  @type t :: %__MODULE__{
          entry: function | nil
        }

  defstruct entry: nil
end
