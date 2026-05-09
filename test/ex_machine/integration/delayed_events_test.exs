defmodule ExMachine.Integration.DelayedEventsTest.Doorbell do
  @moduledoc false
  # On entering :ringing the action schedules a :silence event 50ms later.
  # On :silence we transition back to :idle. If the user dispatches :hush
  # first, the timer must be cancelled (its owner state was exited).

  use ExMachine.Statechart

  alias ExMachine.Step

  initial(:idle)

  state :idle do
    on(:press, target: :ringing)
  end

  state :ringing do
    on_entry(&__MODULE__.schedule_silence/1)
    on(:silence, target: :idle)
    on(:hush, target: :idle)
  end

  def schedule_silence(%Step{} = s) do
    {_ref, s} = Step.send_after(s, :silence, 50, :ringing)
    s
  end
end

defmodule ExMachine.Integration.DelayedEventsTest.DoorbellServer do
  @moduledoc false
  use ExMachine.Server, statechart: ExMachine.Integration.DelayedEventsTest.Doorbell
end

defmodule ExMachine.Integration.DelayedEventsTest.SameMacrostepRace do
  @moduledoc false
  # Regression for bug_002: an action schedules a delayed send while
  # entering :a, then an eventless transition leaves :a in the SAME
  # macrostep. The orphan timer must NOT be scheduled (its owner state
  # has already been exited by the time the macrostep returns).

  use ExMachine.Statechart

  alias ExMachine.Step

  initial(:a)

  state :a do
    on_entry(&__MODULE__.schedule/1)
    on(nil, target: :b)
  end

  state :b do
    on(:ping, target: :surprise)
  end

  state(:surprise)

  def schedule(%Step{} = s) do
    {_ref, s} = Step.send_after(s, :ping, 30, :a)
    s
  end
end

defmodule ExMachine.Integration.DelayedEventsTest.RaceServer do
  @moduledoc false
  use ExMachine.Server, statechart: ExMachine.Integration.DelayedEventsTest.SameMacrostepRace
end

defmodule ExMachine.Integration.DelayedEventsTest do
  use ExUnit.Case, async: false

  alias ExMachine.Integration.DelayedEventsTest.DoorbellServer

  setup do
    {:ok, pid} = DoorbellServer.start_link()

    on_exit(fn ->
      try do
        if Process.alive?(pid), do: GenServer.stop(pid, :normal, 100)
      catch
        :exit, _ -> :ok
      end
    end)

    {:ok, server: pid}
  end

  test "a delayed event fires after the requested delay", %{server: server} do
    DoorbellServer.subscribe(server)
    {:ok, snap} = DoorbellServer.call_event(server, :press)
    assert snap.atomic_states == [:ringing]

    # ~50ms later the server should have fired :silence and gone back to :idle.
    assert_receive {:ex_machine, :transition, %{atomic_states: [:idle]}}, 200
  end

  test "a delayed event is cancelled when its owner state is exited",
       %{server: server} do
    DoorbellServer.subscribe(server)
    {:ok, _} = DoorbellServer.call_event(server, :press)

    # Synchronously hush before the timer fires; the owner :ringing exits, so
    # the queued :silence transition must NOT arrive.
    {:ok, snap} = DoorbellServer.call_event(server, :hush)
    assert snap.atomic_states == [:idle]

    # Drain the :transition messages we already triggered (press + hush).
    assert_receive {:ex_machine, :transition, %{atomic_states: [:ringing]}}, 100
    assert_receive {:ex_machine, :transition, %{atomic_states: [:idle]}}, 100

    # No further transitions should be delivered.
    refute_receive {:ex_machine, :transition, _}, 150
  end

  describe "regression: bug_002 — same-macrostep cancellation" do
    test "a delayed send scheduled in a state exited within the same macrostep is dropped" do
      alias ExMachine.Integration.DelayedEventsTest.RaceServer

      {:ok, pid} = RaceServer.start_link()

      on_exit(fn ->
        try do
          if Process.alive?(pid), do: GenServer.stop(pid, :normal, 100)
        catch
          :exit, _ -> :ok
        end
      end)

      # init macrostep enters :a (which schedules :ping in 30ms), then
      # the eventless transition fires :a -> :b, all in one macrostep.
      assert RaceServer.get_snapshot(pid).atomic_states == [:b]

      RaceServer.subscribe(pid)

      # Without the fix, ~30ms later :ping arrives and the machine
      # lands in :surprise. With the fix, the timer was never scheduled.
      refute_receive {:ex_machine, :transition, _}, 100
      assert RaceServer.get_snapshot(pid).atomic_states == [:b]
    end
  end
end
