defmodule S2 do
  @moduledoc false
  use ExMachine.Statechart

  def  definition() do
     %State{
      initial: "s21",
      substates: %{
        "s21" => %State{},
        "s22" => %State{},
        "exit" => %Final{entry: &(Map.put(&1, :exit, true))}
      },
      transitions: %{
        "a" => "s1"
      }
    }
  end
end
