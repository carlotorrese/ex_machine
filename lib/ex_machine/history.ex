defmodule ExMachine.History do
  @type t :: %__MODULE__{
          type: :deep | :shallow
        }

  defstruct type: nil
end
