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

  describe "regression: bug_005 — subscriptions survive a restart of a named server" do
    test "subscribing by name keeps receiving notifications after the named server is restarted" do
      name = :"light_#{System.unique_integer([:positive])}"

      {:ok, pid1} = LightServer.start_link(name: name)
      :ok = LightServer.subscribe(name)

      {:ok, _} = LightServer.call_event(name, :timer)
      assert_receive {:ex_machine, :transition, %Snapshot{atomic_states: [:green]}}, 100

      # Take down the named server. The supervisor would normally restart
      # it under the same name; here we simulate the restart manually.
      LightServer.stop(pid1)

      # Ensure the new process actually gets a different PID by waiting
      # for the registered name to be free.
      wait_until(fn -> Process.whereis(name) == nil end, 100)

      {:ok, pid2} = LightServer.start_link(name: name)
      assert pid2 != pid1

      # Without the fix, the subscription was keyed on pid1 and would
      # be silently orphaned. With the fix, it is keyed on `name` and
      # the new process's notifications still arrive.
      {:ok, _} = LightServer.call_event(name, :timer)
      assert_receive {:ex_machine, :transition, %Snapshot{atomic_states: [:green]}}, 100

      LightServer.stop(pid2)
    end

    defp wait_until(fun, timeout) do
      deadline = System.monotonic_time(:millisecond) + timeout

      Stream.repeatedly(fn -> nil end)
      |> Enum.reduce_while(:ok, fn _, _ ->
        if fun.() do
          {:halt, :ok}
        else
          if System.monotonic_time(:millisecond) >= deadline do
            {:halt, :timeout}
          else
            Process.sleep(5)
            {:cont, :ok}
          end
        end
      end)
    end
  end

  describe "regression: bug_002 (3rd pass) — via/global pubsub key" do
    test "subscribers to a {:via, _, _}-registered server actually receive notifications" do
      registry = :"reg_#{System.unique_integer([:positive])}"
      {:ok, _} = Registry.start_link(keys: :unique, name: registry)
      via = {:via, Registry, {registry, :tl}}

      {:ok, pid} = LightServer.start_link(name: via)

      on_exit(fn ->
        try do
          if Process.alive?(pid), do: GenServer.stop(pid, :normal, 100)
        catch
          :exit, _ -> :ok
        end
      end)

      :ok = LightServer.subscribe(via)
      {:ok, %Snapshot{atomic_states: [:green]}} = LightServer.call_event(via, :timer)

      # Without the fix, init/1 would cache the bare PID as pubsub_key
      # (Process.info doesn't see {:via, _, _} registrations) while
      # subscribe/1 keys off the via tuple — the two never match and
      # the message is silently dropped.
      assert_receive {:ex_machine, :transition, %Snapshot{atomic_states: [:green]}}, 100
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
