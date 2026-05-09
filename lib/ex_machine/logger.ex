defmodule ExMachine.Logger do
  @moduledoc """
  Attachable `:telemetry` handler that logs ExMachine events through
  Elixir's `Logger`.

  ## Usage

      # During application start, or from IEx:
      ExMachine.Logger.attach(level: :debug)

      # Detach (e.g. in test cleanup):
      ExMachine.Logger.detach()

  Each event is rendered as a single line. Subscriber callbacks receive
  the raw event and metadata; this module is intentionally thin so users
  can swap in their own handler.
  """

  require Logger

  @handler_id "ex_machine_logger"

  @events [
    [:ex_machine, :macrostep, :stop],
    [:ex_machine, :macrostep, :exception],
    [:ex_machine, :transition],
    [:ex_machine, :stopped]
  ]

  @doc """
  Attach a logger that emits one log line per macrostep / transition /
  stopped / exception event.

  ## Options

    * `:level` — log level (default `:info`).
  """
  @spec attach(keyword()) :: :ok | {:error, :already_exists}
  def attach(opts \\ []) do
    level = Keyword.get(opts, :level, :info)
    :telemetry.attach_many(@handler_id, @events, &__MODULE__.handle_event/4, %{level: level})
  end

  @doc "Detach the logger handler."
  @spec detach() :: :ok | {:error, :not_found}
  def detach, do: :telemetry.detach(@handler_id)

  @doc false
  def handle_event([:ex_machine, :macrostep, :stop], measurements, metadata, %{level: level}) do
    log(level, fn ->
      "macrostep server=#{inspect(metadata[:server])} event=#{inspect(metadata[:event])} " <>
        "duration_us=#{System.convert_time_unit(measurements.duration, :native, :microsecond)}"
    end)
  end

  def handle_event(
        [:ex_machine, :macrostep, :exception],
        _measurements,
        metadata,
        %{level: level}
      ) do
    log(level, fn ->
      "macrostep CRASH server=#{inspect(metadata[:server])} event=#{inspect(metadata[:event])} " <>
        "kind=#{inspect(metadata[:kind])} reason=#{inspect(metadata[:reason])}"
    end)
  end

  def handle_event([:ex_machine, :transition], measurements, metadata, %{level: level}) do
    log(level, fn ->
      "transition count=#{measurements.count} event=#{inspect(metadata[:event])}"
    end)
  end

  def handle_event([:ex_machine, :stopped], _measurements, metadata, %{level: level}) do
    log(level, fn ->
      "stopped server=#{inspect(metadata[:server])} reason=#{inspect(metadata[:reason])}"
    end)
  end

  defp log(level, fun), do: Logger.log(level, fun)
end
