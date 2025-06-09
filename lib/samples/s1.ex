defmodule S1 do
  @moduledoc false
  use ExMachine.Statechart

  def definition() do
    %State{
      initial: "s11",
      entry: &%{&1 | foo: 1},
      exit: &%{&1 | foo: 0},
      substates: %{
        "s11" => %State{
          entry: &__MODULE__.add_bar_baz/1,
          exit: &__MODULE__.remove_bar_baz/1
        },
        "s12" => %State{},
        "end" => %Final{}
      },
      transitions: %{
        "a" => %Transition{
          target: "s2",
          action: &%{&1 | foo: 2}
        },
        "c" => %Transition{
          target: "s21",
          guard: &(&1[:foo] == 0)
        },
        "e" => "end"
      }
    }
  end

  def add_bar_baz(context) do
    Map.put(context, :bar, :baz)
  end

  def remove_bar_baz(context) do
    Map.delete(context, :bar)
  end
end
