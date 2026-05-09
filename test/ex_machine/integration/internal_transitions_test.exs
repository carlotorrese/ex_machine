defmodule ExMachine.Integration.InternalTransitionsTest.Counter do
  @moduledoc false
  # An internal transition on a compound state must NOT exit and re-enter
  # the compound when the target is one of its descendants. on_entry/on_exit
  # of the compound should fire exactly once, while the descendant moves.

  use ExMachine.Statechart

  alias ExMachine.Step

  initial_context(%{enters: 0, exits: 0, ticks: 0})
  initial(:running)

  state :running do
    on_entry(&__MODULE__.bump_enter/1)
    on_exit(&__MODULE__.bump_exit/1)

    # External self-transition: should re-enter :running and bump enters/exits.
    on(:reset, target: :a)

    # Internal transition: stays inside :running, just touches the context.
    on(:tick, action: &__MODULE__.bump_tick/1, type: :internal)

    # Internal transition with a descendant target: jumps :a → :b without
    # exiting :running.
    on(:to_b, target: :b, type: :internal)

    initial(:a)
    state(:a, do: on(:next, target: :b))
    state(:b, do: on(:next, target: :a))
  end

  def bump_enter(%Step{} = s), do: Step.update(s, :enters, &(&1 + 1))
  def bump_exit(%Step{} = s), do: Step.update(s, :exits, &(&1 + 1))
  def bump_tick(%Step{} = s), do: Step.update(s, :ticks, &(&1 + 1))
end

defmodule ExMachine.Integration.InternalTransitionsTest do
  use ExUnit.Case, async: true

  alias ExMachine.Integration.InternalTransitionsTest.Counter

  test "internal action-only transition does not exit/re-enter the compound" do
    machine = ExMachine.init(Counter)
    assert machine.context.enters == 1
    assert machine.context.exits == 0
    assert machine.context.ticks == 0

    machine = ExMachine.dispatch(machine, :tick)
    assert machine.context.enters == 1
    assert machine.context.exits == 0
    assert machine.context.ticks == 1
    assert ExMachine.atomic_states(machine) == [:a]
    assert machine.trace.exited == []
    assert machine.trace.entered == []
  end

  test "internal transition to a descendant moves only the descendant" do
    machine =
      Counter
      |> ExMachine.init()
      |> ExMachine.dispatch(:to_b)

    assert ExMachine.atomic_states(machine) == [:b]
    assert machine.context.enters == 1
    assert machine.context.exits == 0
    assert machine.trace.exited == [:a]
    assert machine.trace.entered == [:b]
  end

  test "external transition to a sibling under the same parent re-enters parent" do
    machine =
      Counter
      |> ExMachine.init()
      |> ExMachine.dispatch(:reset)

    assert ExMachine.atomic_states(machine) == [:a]
    assert machine.context.enters == 2
    assert machine.context.exits == 1
  end
end
