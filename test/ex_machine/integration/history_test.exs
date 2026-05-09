defmodule ExMachine.Integration.HistoryTest.ShallowPlayer do
  @moduledoc false
  # Shallow history on the :playing compound. After leaving and re-entering
  # via :resume (which targets the history pseudostate), the previously
  # active direct child is restored.

  use ExMachine.Statechart

  initial_context(%{})
  initial(:stopped)

  state :stopped do
    on(:play, target: :playing)
    on(:resume, target: :h_play)
  end

  state :playing do
    initial(:slow)

    history(:h_play, type: :shallow, default: :fast)

    on(:pause, target: :stopped)

    state(:slow, do: on(:go_fast, target: :fast))
    state(:fast, do: on(:go_slow, target: :slow))
  end
end

defmodule ExMachine.Integration.HistoryTest.DeepPlayer do
  @moduledoc false
  # Deep history on the :playing compound. The compound has a nested
  # compound :mode whose own initial is :slow. Deep history restores the
  # full active sub-configuration.

  use ExMachine.Statechart

  initial_context(%{})
  initial(:stopped)

  state :stopped do
    on(:play, target: :playing)
    on(:resume, target: :h_deep)
  end

  state :playing do
    initial(:mode)

    history(:h_deep, type: :deep)

    on(:pause, target: :stopped)

    state :mode do
      initial(:slow)
      state(:slow, do: on(:go_fast, target: :fast))
      state(:fast, do: on(:go_slow, target: :slow))
    end
  end
end

defmodule ExMachine.Integration.HistoryTest.NoDefaultPlayer do
  @moduledoc false
  # No history_default declared. The first entry through the history
  # pseudostate (with no recorded snapshot) must fall back to the parent's
  # :initial substate.

  use ExMachine.Statechart

  initial_context(%{})
  initial(:idle)

  state :idle do
    on(:resume, target: :h)
  end

  state :playing do
    initial(:slow)

    history(:h, type: :shallow)

    state(:slow)
    state(:fast)
  end
end

defmodule ExMachine.Integration.HistoryTest do
  use ExUnit.Case, async: true

  alias ExMachine.Integration.HistoryTest.{DeepPlayer, NoDefaultPlayer, ShallowPlayer}

  describe "shallow history" do
    test "first entry via history uses :default when no snapshot recorded" do
      machine =
        ShallowPlayer
        |> ExMachine.init()
        |> ExMachine.dispatch(:resume)

      assert ExMachine.atomic_states(machine) == [:fast]
      assert MapSet.member?(machine.configuration, :playing)
    end

    test "restores the previously active direct child after a round-trip" do
      machine =
        ShallowPlayer
        |> ExMachine.init()
        |> ExMachine.dispatch(:play)
        |> ExMachine.dispatch(:go_fast)
        |> ExMachine.dispatch(:pause)

      assert ExMachine.atomic_states(machine) == [:stopped]

      machine = ExMachine.dispatch(machine, :resume)
      assert ExMachine.atomic_states(machine) == [:fast]
    end

    test "subsequent restores reflect the latest snapshot" do
      machine =
        ShallowPlayer
        |> ExMachine.init()
        |> ExMachine.dispatch(:play)
        |> ExMachine.dispatch(:go_fast)
        |> ExMachine.dispatch(:pause)
        |> ExMachine.dispatch(:resume)
        |> ExMachine.dispatch(:go_slow)
        |> ExMachine.dispatch(:pause)
        |> ExMachine.dispatch(:resume)

      assert ExMachine.atomic_states(machine) == [:slow]
    end
  end

  describe "deep history" do
    test "first entry via history follows the parent's :initial chain" do
      machine =
        DeepPlayer
        |> ExMachine.init()
        |> ExMachine.dispatch(:resume)

      assert ExMachine.atomic_states(machine) == [:slow]
      assert MapSet.member?(machine.configuration, :mode)
    end

    test "restores the leaf state inside a nested compound" do
      machine =
        DeepPlayer
        |> ExMachine.init()
        |> ExMachine.dispatch(:play)
        |> ExMachine.dispatch(:go_fast)
        |> ExMachine.dispatch(:pause)
        |> ExMachine.dispatch(:resume)

      assert ExMachine.atomic_states(machine) == [:fast]
      assert MapSet.member?(machine.configuration, :mode)
    end
  end

  describe "history without explicit default" do
    test "falls back to the parent's :initial substate" do
      machine =
        NoDefaultPlayer
        |> ExMachine.init()
        |> ExMachine.dispatch(:resume)

      assert ExMachine.atomic_states(machine) == [:slow]
    end
  end
end
