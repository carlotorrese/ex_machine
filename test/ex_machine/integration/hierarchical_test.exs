defmodule ExMachine.Integration.HierarchicalTest.Player do
  @moduledoc false
  # Fixture defined outside the test module so the DSL's `on_exit/1` macro
  # does not collide with `ExUnit.Callbacks.on_exit/1`.
  use ExMachine.Statechart

  alias ExMachine.Step

  initial_context(%{plays: 0, started: false})
  initial(:stopped)

  state :stopped do
    on(:play, target: :playing)
  end

  state :playing do
    initial(:slow)
    on_entry(&__MODULE__.start/1)
    on_exit(&__MODULE__.stop/1)
    on(:pause, target: :paused)

    state :slow do
      on(:go_fast, target: :fast)
    end

    state :fast do
      on(:go_slow, target: :slow)
    end
  end

  state :paused do
    on(:play, target: :playing)
  end

  def start(%Step{} = step) do
    step
    |> Step.assign(:started, true)
    |> Step.update(:plays, &(&1 + 1))
  end

  def stop(%Step{} = step), do: Step.assign(step, :started, false)
end

defmodule ExMachine.Integration.HierarchicalTest do
  use ExUnit.Case, async: true

  alias ExMachine.Integration.HierarchicalTest.Player

  test "initial state cascades down to atomic via :initial" do
    machine = ExMachine.init(Player)
    assert ExMachine.atomic_states(machine) == [:stopped]
  end

  test "entering :playing follows its initial substate to :slow and runs entry of both" do
    machine = ExMachine.init(Player) |> ExMachine.dispatch(:play)
    assert ExMachine.atomic_states(machine) == [:slow]

    # The compound :playing was entered, its on_entry fired
    assert machine.context.started == true
    assert machine.context.plays == 1

    # Trace shows entered: [:playing, :slow] in parent-first order
    assert :playing in machine.trace.entered
    assert :slow in machine.trace.entered
  end

  test "transition between siblings under the same compound (:slow → :fast) does not exit :playing" do
    machine =
      Player
      |> ExMachine.init()
      |> ExMachine.dispatch(:play)
      |> ExMachine.dispatch(:go_fast)

    assert ExMachine.atomic_states(machine) == [:fast]
    # :playing's on_exit must NOT have fired again (plays counter stable)
    assert machine.context.plays == 1
    assert machine.context.started == true
  end

  test "transition out of :playing exits all descendants and runs on_exit" do
    machine =
      Player
      |> ExMachine.init()
      |> ExMachine.dispatch(:play)
      |> ExMachine.dispatch(:go_fast)
      |> ExMachine.dispatch(:pause)

    assert ExMachine.atomic_states(machine) == [:paused]
    assert machine.context.started == false
    # exited in deepest-first order: :fast then :playing
    assert machine.trace.exited == [:fast, :playing]
  end

  test "round-trip back into :playing re-enters :slow (not history) and bumps plays" do
    machine =
      Player
      |> ExMachine.init()
      |> ExMachine.dispatch(:play)
      |> ExMachine.dispatch(:go_fast)
      |> ExMachine.dispatch(:pause)
      |> ExMachine.dispatch(:play)

    assert ExMachine.atomic_states(machine) == [:slow]
    # plays bumped twice: first :play, then :play again after pause
    assert machine.context.plays == 2
  end
end
