defmodule ExMachine.Integration.InvocationsTest.Loader do
  @moduledoc false
  # On entering :loading, invoke a function that returns the payload.
  # done.invoke.<id> moves us to :ready, error.invoke.<id> to :failed.

  use ExMachine.Statechart

  alias ExMachine.Step

  initial(:idle)

  state :idle do
    on(:start, target: :loading)
    on(:start_bad, target: :loading_bad)
    on(:start_slow, target: :loading_slow)
  end

  state :loading do
    on_entry(&__MODULE__.invoke_ok/1)
    on(:"done.invoke.fetch", target: :ready)
    on(:"error.invoke.fetch", target: :failed)
  end

  state :loading_bad do
    on_entry(&__MODULE__.invoke_bad/1)
    on(:"done.invoke.fetch", target: :ready)
    on(:"error.invoke.fetch", target: :failed)
  end

  state :loading_slow do
    on_entry(&__MODULE__.invoke_slow/1)
    on(:cancel, target: :idle)
    on(:"done.invoke.slow", target: :ready)
  end

  state(:ready)
  state(:failed)

  def invoke_ok(%Step{} = s),
    do: Step.invoke(s, :fetch, fn -> :ok_payload end, :loading)

  def invoke_bad(%Step{} = s),
    do: Step.invoke(s, :fetch, {__MODULE__, :boom, []}, :loading_bad)

  def invoke_slow(%Step{} = s),
    do:
      Step.invoke(
        s,
        :slow,
        fn ->
          Process.sleep(500)
          :too_late
        end,
        :loading_slow
      )

  def boom, do: raise("nope")
end

defmodule ExMachine.Integration.InvocationsTest.LoaderServer do
  @moduledoc false
  use ExMachine.Server, statechart: ExMachine.Integration.InvocationsTest.Loader
end

defmodule ExMachine.Integration.InvocationsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias ExMachine.Integration.InvocationsTest.LoaderServer

  setup do
    {:ok, pid} = LoaderServer.start_link()

    on_exit(fn ->
      try do
        if Process.alive?(pid), do: GenServer.stop(pid, :normal, 100)
      catch
        :exit, _ -> :ok
      end
    end)

    {:ok, server: pid}
  end

  test "successful invoke raises done.invoke.<id> and transitions to :ready",
       %{server: server} do
    LoaderServer.subscribe(server)
    {:ok, _} = LoaderServer.call_event(server, :start)

    assert_receive {:ex_machine, :transition, %{atomic_states: [:loading]}}, 100
    assert_receive {:ex_machine, :transition, %{atomic_states: [:ready]}}, 200
  end

  test "failed invoke raises error.invoke.<id> and transitions to :failed",
       %{server: server} do
    LoaderServer.subscribe(server)

    capture_log(fn ->
      {:ok, _} = LoaderServer.call_event(server, :start_bad)
      assert_receive {:ex_machine, :transition, %{atomic_states: [:loading_bad]}}, 100
      assert_receive {:ex_machine, :transition, %{atomic_states: [:failed]}}, 200
    end)
  end

  test "an invocation is killed when its owner state is exited",
       %{server: server} do
    LoaderServer.subscribe(server)
    {:ok, _} = LoaderServer.call_event(server, :start_slow)
    assert_receive {:ex_machine, :transition, %{atomic_states: [:loading_slow]}}, 100

    {:ok, snap} = LoaderServer.call_event(server, :cancel)
    assert snap.atomic_states == [:idle]
    assert_receive {:ex_machine, :transition, %{atomic_states: [:idle]}}, 100

    # The slow task would otherwise emit done.invoke.slow ~500ms later.
    refute_receive {:ex_machine, :transition, _}, 700
  end
end
