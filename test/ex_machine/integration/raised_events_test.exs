defmodule ExMachine.Integration.RaisedEventsTest do
  use ExUnit.Case, async: true

  alias ExMachine.Step

  defmodule Chain do
    @moduledoc false
    # Pure run-to-completion: every state's entry raises the next event.
    # Dispatching :go from :s0 should land the machine in :s3 in a single
    # macrostep with three microsteps.
    use ExMachine.Statechart

    initial_context(%{})
    initial(:s0)

    state :s0 do
      on(:go, target: :s1)
    end

    state :s1 do
      on_entry(&Chain.raise_e2/1)
      on(:e2, target: :s2)
    end

    state :s2 do
      on_entry(&Chain.raise_e3/1)
      on(:e3, target: :s3)
    end

    state :s3 do
      on_entry(&Chain.mark_reached/1)
    end

    def raise_e2(step), do: Step.raise_event(step, :e2)
    def raise_e3(step), do: Step.raise_event(step, :e3)
    def mark_reached(step), do: Step.assign(step, :reached, true)
  end

  defmodule Eventless do
    @moduledoc false
    # Eventless transition: a guarded "always" transition fires automatically
    # during run-to-completion when its guard holds.
    use ExMachine.Statechart

    initial_context(%{ready: false})
    initial(:idle)

    state :idle do
      on(:prepare, target: :checking, action: &Eventless.flip/1)
    end

    state :checking do
      on(event: nil, target: :done, guard: &Eventless.ready?/1)
    end

    state(:done)

    def flip(step), do: Step.assign(step, :ready, true)
    def ready?(ctx), do: Map.get(ctx, :ready) == true
  end

  describe "Chain (raised events)" do
    test "single dispatch lands in :s3 after run-to-completion" do
      machine = ExMachine.init(Chain) |> ExMachine.dispatch(:go)
      assert ExMachine.atomic_states(machine) == [:s3]
      assert machine.context == %{reached: true}
    end

    test "trace records all three transitions in order" do
      machine = ExMachine.init(Chain) |> ExMachine.dispatch(:go)
      events = Enum.map(machine.trace.transitions, & &1.event)
      assert events == [:go, :e2, :e3]
    end
  end

  defmodule UnreadyAtStart do
    @moduledoc false
    use ExMachine.Statechart

    initial_context(%{ready: false})
    initial(:checking)

    state :checking do
      on(event: nil, target: :done, guard: &Eventless.ready?/1)
    end

    state(:done)
  end

  describe "Eventless (always transitions)" do
    test "guard false: stays in :checking" do
      machine = ExMachine.init(UnreadyAtStart)
      assert ExMachine.atomic_states(machine) == [:checking]
    end

    test "transition action flips guard, eventless fires immediately during RTC" do
      machine = ExMachine.init(Eventless) |> ExMachine.dispatch(:prepare)
      assert ExMachine.atomic_states(machine) == [:done]
      assert machine.context.ready == true
    end
  end
end
