defmodule ExMachine.Integration.ParallelSmokeTest.TwoRegions do
  @moduledoc false
  # Two independent regions. Each has its own atomic states and its own
  # event. Used as a smoke test for the parallel infrastructure: init
  # should put both regions' initials in the configuration; dispatching
  # an event scoped to one region should leave the other untouched.

  use ExMachine.Statechart, type: :parallel

  region :left do
    initial(:l1)

    state(:l1, do: on(:tick_l, target: :l2))
    state(:l2)
  end

  region :right do
    initial(:r1)

    state(:r1, do: on(:tick_r, target: :r2))
    state(:r2)
  end
end

defmodule ExMachine.Integration.ParallelSmokeTest do
  use ExUnit.Case, async: true

  alias ExMachine.Integration.ParallelSmokeTest.TwoRegions

  test "init enters both regions to their initial atomics" do
    machine = ExMachine.init(TwoRegions)
    assert ExMachine.atomic_states(machine) == [:l1, :r1]
  end

  test "an event in one region must leave the other unchanged" do
    machine =
      TwoRegions
      |> ExMachine.init()
      |> ExMachine.dispatch(:tick_l)

    assert ExMachine.atomic_states(machine) == [:l2, :r1]

    machine = ExMachine.dispatch(machine, :tick_r)
    assert ExMachine.atomic_states(machine) == [:l2, :r2]
  end
end

defmodule ExMachine.Integration.ParallelSmokeTest.SharedEvent do
  @moduledoc false
  # Both regions react to the same event :go. With proper select_transitions
  # the engine should fire BOTH transitions in a single microstep.

  use ExMachine.Statechart, type: :parallel

  region :left do
    initial(:la)

    state(:la, do: on(:go, target: :lb))
    state(:lb)
  end

  region :right do
    initial(:ra)

    state(:ra, do: on(:go, target: :rb))
    state(:rb)
  end
end

defmodule ExMachine.Integration.ParallelSmokeTest.SharedTest do
  use ExUnit.Case, async: true

  alias ExMachine.Integration.ParallelSmokeTest.SharedEvent

  test "a shared event fires the matching transition in every region" do
    machine =
      SharedEvent
      |> ExMachine.init()
      |> ExMachine.dispatch(:go)

    assert ExMachine.atomic_states(machine) == [:lb, :rb]
  end
end
