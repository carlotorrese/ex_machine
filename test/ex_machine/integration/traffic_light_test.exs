defmodule ExMachine.Integration.TrafficLightTest do
  use ExUnit.Case, async: true

  alias ExMachine.Step

  defmodule Light do
    @moduledoc false
    use ExMachine.Statechart

    initial_context(%{cycles: 0, last: nil})
    initial(:red)

    state :red do
      on_entry(&Light.note/1)
      on(:timer, target: :green)
    end

    state :green do
      on_entry(&Light.note/1)
      on(:timer, target: :yellow)
    end

    state :yellow do
      on_entry(&Light.note/1)
      on(:timer, target: :red, action: &Light.bump/1)
    end

    @doc "Record the latest event seen on entry — `nil` for the initial entry."
    def note(%Step{} = step), do: Step.assign(step, :last, step.event)

    def bump(%Step{} = step), do: Step.update(step, :cycles, &(&1 + 1))
  end

  test "starts in :red and runs entry actions" do
    machine = ExMachine.init(Light)
    assert ExMachine.atomic_states(machine) == [:red]
    assert machine.context.cycles == 0
    assert machine.running?
  end

  test "single :timer event moves :red → :green" do
    machine = ExMachine.init(Light) |> ExMachine.dispatch(:timer)
    assert ExMachine.atomic_states(machine) == [:green]
  end

  test "full cycle :red → :green → :yellow → :red bumps cycles once" do
    machine =
      Light
      |> ExMachine.init()
      |> ExMachine.dispatch(:timer)
      |> ExMachine.dispatch(:timer)
      |> ExMachine.dispatch(:timer)

    assert ExMachine.atomic_states(machine) == [:red]
    assert machine.context.cycles == 1
  end

  test "unknown events leave the machine unchanged" do
    machine = ExMachine.init(Light)
    machine2 = ExMachine.dispatch(machine, :nope)
    assert ExMachine.atomic_states(machine2) == ExMachine.atomic_states(machine)
    assert machine2.context == machine.context
  end

  test "trace records entered/exited per dispatch" do
    machine = ExMachine.init(Light) |> ExMachine.dispatch(:timer)
    assert machine.trace.entered == [:green]
    assert machine.trace.exited == [:red]
    assert [%{event: :timer, target: :green}] = machine.trace.transitions
  end
end
