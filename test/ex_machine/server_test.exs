defmodule ExMachine.ServerTest.Light do
  @moduledoc false
  use ExMachine.Statechart

  alias ExMachine.Step

  initial_context(%{cycles: 0})
  initial(:red)

  state(:red, do: on(:timer, target: :green))
  state(:green, do: on(:timer, target: :yellow))

  state :yellow do
    on(:timer, target: :red, action: &__MODULE__.bump/1)
    on(:halt, target: :off)
  end

  final(:off)

  def bump(%Step{} = s), do: Step.update(s, :cycles, &(&1 + 1))
end

defmodule ExMachine.ServerTest.LightServer do
  @moduledoc false
  use ExMachine.Server, statechart: ExMachine.ServerTest.Light
end

defmodule ExMachine.ServerTest.TelemetryRelay do
  @moduledoc false
  # Module-level handler so :telemetry doesn't warn about anonymous local
  # functions during attach.
  def relay(event, measurements, metadata, {test_pid, ref}) do
    send(test_pid, {ref, event, measurements, metadata})
  end
end

defmodule ExMachine.ServerTest do
  use ExUnit.Case, async: false

  alias ExMachine.ServerTest.LightServer
  alias ExMachine.Snapshot

  setup do
    {:ok, pid} = LightServer.start_link()

    on_exit(fn ->
      try do
        if Process.alive?(pid), do: GenServer.stop(pid, :normal, 100)
      catch
        :exit, _ -> :ok
      end
    end)

    {:ok, server: pid}
  end

  test "start_link enters the initial configuration", %{server: server} do
    snap = LightServer.get_snapshot(server)
    assert %Snapshot{atomic_states: [:red], running?: true} = snap
  end

  test "send_event/2 advances the configuration asynchronously", %{server: server} do
    :ok = LightServer.send_event(server, :timer)
    # wait for the cast to be processed; a synchronous read serialises after
    snap = LightServer.get_snapshot(server)
    assert snap.atomic_states == [:green]
  end

  test "call_event/2 replies with {:ok, snapshot} of the new state", %{server: server} do
    assert {:ok, %Snapshot{atomic_states: [:green]}} = LightServer.call_event(server, :timer)
    assert {:ok, %Snapshot{atomic_states: [:yellow]}} = LightServer.call_event(server, :timer)
  end

  test "call_event/3 forwards params to the engine and reflects context updates",
       %{server: server} do
    {:ok, _} = LightServer.call_event(server, :timer)
    {:ok, _} = LightServer.call_event(server, :timer)
    {:ok, snap} = LightServer.call_event(server, :timer)
    assert snap.context.cycles == 1
  end

  test "get_configuration / get_context return raw machine state", %{server: server} do
    assert MapSet.member?(LightServer.get_configuration(server), :red)
    assert LightServer.get_context(server) == %{cycles: 0}
  end

  test "subscribe receives a :transition message after each macrostep", %{server: server} do
    :ok = LightServer.subscribe(server)
    {:ok, _} = LightServer.call_event(server, :timer)
    assert_receive {:ex_machine, :transition, %Snapshot{atomic_states: [:green]}}, 100
  end

  test "subscribe + unsubscribe stops further messages", %{server: server} do
    :ok = LightServer.subscribe(server)
    :ok = LightServer.unsubscribe(server)
    {:ok, _} = LightServer.call_event(server, :timer)
    refute_receive {:ex_machine, :transition, _}, 100
  end

  test "subscribing twice still delivers exactly once per event (dedup)",
       %{server: server} do
    :ok = LightServer.subscribe(server)
    :ok = LightServer.subscribe(server)
    {:ok, _} = LightServer.call_event(server, :timer)
    assert_receive {:ex_machine, :transition, _}, 100
    refute_receive {:ex_machine, :transition, _}, 50
  end

  describe "terminal configurations" do
    test "call_event returns {:error, :not_running} after top-level final", %{server: server} do
      {:ok, _} = LightServer.call_event(server, :timer)
      {:ok, _} = LightServer.call_event(server, :timer)
      {:ok, snap} = LightServer.call_event(server, :halt)
      refute snap.running?

      assert {:error, :not_running} = LightServer.call_event(server, :timer)
    end

    test "send_event is silently dropped after top-level final", %{server: server} do
      LightServer.call_event(server, :timer)
      LightServer.call_event(server, :timer)
      LightServer.call_event(server, :halt)
      :ok = LightServer.send_event(server, :timer)
      assert LightServer.get_snapshot(server).atomic_states == [:off]
    end

    test "subscriber receives :stopped when the machine reaches a final", %{server: server} do
      :ok = LightServer.subscribe(server)
      LightServer.call_event(server, :timer)
      LightServer.call_event(server, :timer)
      LightServer.call_event(server, :halt)
      assert_receive {:ex_machine, :stopped, :normal}, 100
    end
  end

  describe "telemetry" do
    setup do
      ref = make_ref()
      test_pid = self()

      handler_id = "test-#{inspect(ref)}"

      :telemetry.attach_many(
        handler_id,
        [
          [:ex_machine, :macrostep, :start],
          [:ex_machine, :macrostep, :stop],
          [:ex_machine, :transition]
        ],
        &ExMachine.ServerTest.TelemetryRelay.relay/4,
        {test_pid, ref}
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)
      {:ok, ref: ref}
    end

    test "macrostep span fires :start and :stop with metadata", %{server: server, ref: ref} do
      {:ok, _} = LightServer.call_event(server, :timer)
      assert_receive {^ref, [:ex_machine, :macrostep, :start], _, %{event: :timer}}, 100
      assert_receive {^ref, [:ex_machine, :macrostep, :stop], measurements, meta}, 100
      assert is_integer(measurements.duration)
      assert meta.event == :timer
      assert %Snapshot{} = meta.snapshot
    end

    test "[:ex_machine, :transition] is emitted with the actual transitions",
         %{server: server, ref: ref} do
      {:ok, _} = LightServer.call_event(server, :timer)
      assert_receive {^ref, [:ex_machine, :transition], %{count: 1}, %{transitions: [t]}}, 100
      assert t.event == :timer
      assert t.target == :green
    end
  end
end
