defmodule ExMachine.Integration.FinalsTest do
  use ExUnit.Case, async: true

  alias ExMachine.{Engine, Machine, Step}

  defmodule TopFinal do
    @moduledoc false
    use ExMachine.Statechart

    initial_context(%{})
    initial(:alive)

    state :alive do
      on(:die, target: :dead)
    end

    final :dead do
      on_entry(&__MODULE__.rip/1)
    end

    def rip(step), do: Step.assign(step, :rip, true)
  end

  defmodule NestedFinal do
    @moduledoc false
    # Compound :workflow finishes when its substate :complete is entered.
    # The engine must raise `done.state.workflow`, which we catch with a
    # transition on the root taking us to :archived.
    use ExMachine.Statechart

    initial_context(%{})
    initial(:workflow)

    state :workflow do
      initial(:step1)
      on(Engine.done_event(:workflow), target: :archived)

      state :step1 do
        on(:next, target: :step2)
      end

      state :step2 do
        on(:finish, target: :complete)
      end

      final(:complete)
    end

    state(:archived)
  end

  describe "TopFinal" do
    test "entering top-level final stops the machine" do
      machine = ExMachine.init(TopFinal) |> ExMachine.dispatch(:die)
      assert ExMachine.atomic_states(machine) == [:dead]
      refute machine.running?
      assert machine.context == %{rip: true}
    end

    test "dispatching to a stopped machine raises" do
      machine = ExMachine.init(TopFinal) |> ExMachine.dispatch(:die)
      assert_raise Machine.NotRunning, fn -> ExMachine.dispatch(machine, :anything) end
    end
  end

  describe "NestedFinal (done.state.<id>)" do
    test "reaching :complete raises done.state.workflow and triggers transition to :archived" do
      machine =
        NestedFinal
        |> ExMachine.init()
        |> ExMachine.dispatch(:next)
        |> ExMachine.dispatch(:finish)

      assert ExMachine.atomic_states(machine) == [:archived]
      assert machine.running?

      events = Enum.map(machine.trace.transitions, & &1.event)
      assert events == [:finish, Engine.done_event(:workflow)]
    end
  end
end
