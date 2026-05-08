defmodule S0 do
  @moduledoc false
  use ExMachine.Statechart

  def definition do
    %State{
      initial: "s1",
      substates: %{
        "s1" => S1.definition(),
        "s2" => S2.definition(),
        "end" => %Final{}
      },
      transitions: %{
        "done.state.s1" => "end"
      }
    }
  end
end
