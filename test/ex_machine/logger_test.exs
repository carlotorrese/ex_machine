defmodule ExMachine.LoggerTest.Tiny do
  @moduledoc false
  use ExMachine.Statechart

  initial(:on)

  state(:on, do: on(:flip, target: :off))
  state(:off)
end

defmodule ExMachine.LoggerTest.TinyServer do
  @moduledoc false
  use ExMachine.Server, statechart: ExMachine.LoggerTest.Tiny
end

defmodule ExMachine.LoggerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias ExMachine.Logger
  alias ExMachine.LoggerTest.TinyServer

  setup do
    on_exit(fn -> Logger.detach() end)
    :ok
  end

  test "attach returns :ok and emits a log line per macrostep" do
    assert :ok = Logger.attach(level: :info)

    log =
      capture_log(fn ->
        {:ok, pid} = TinyServer.start_link()
        {:ok, _} = TinyServer.call_event(pid, :flip)
        TinyServer.stop(pid)
      end)

    assert log =~ "macrostep server="
    assert log =~ "transition count=1"
  end

  test "detach stops further log lines" do
    Logger.attach(level: :info)
    Logger.detach()

    log =
      capture_log(fn ->
        {:ok, pid} = TinyServer.start_link()
        {:ok, _} = TinyServer.call_event(pid, :flip)
        TinyServer.stop(pid)
      end)

    refute log =~ "macrostep server="
  end
end
