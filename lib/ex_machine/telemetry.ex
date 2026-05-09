defmodule ExMachine.Telemetry do
  @moduledoc """
  Centralised emission of `:telemetry` events for `ExMachine.Server`.

  Direct callers of `ExMachine.Engine` (pure mode) do not emit telemetry —
  the engine stays free of side effects. The server wraps every event
  dispatch (and the initial entry) in this module so observers can attach
  with `:telemetry.attach/4` or via `ExMachine.Logger.attach/1`.

  ## Events

    * `[:ex_machine, :macrostep, :start]` — measurements `%{system_time: t}`,
      metadata `%{server: pid, event: term}`.
    * `[:ex_machine, :macrostep, :stop]` — measurements `%{duration: native}`,
      metadata `%{server: pid, event: term, snapshot: %Snapshot{}}`.
    * `[:ex_machine, :macrostep, :exception]` — measurements `%{duration:
      native}`, metadata `%{server: pid, event: term, kind, reason,
      stacktrace}`. Re-raised after emission.
    * `[:ex_machine, :transition]` — measurements `%{count: N}` where N is
      the number of transitions in the macrostep, metadata `%{server: pid,
      event: term, transitions: [Transition.t()]}`.
    * `[:ex_machine, :stopped]` — measurements `%{system_time: t}`,
      metadata `%{server: pid, reason: term, snapshot: %Snapshot{}}`.

  Callers are free to attach to any subset.
  """

  alias ExMachine.{Snapshot, Trace}

  @doc """
  Wrap `fun.()` in a `[:ex_machine, :macrostep]` span. `fun` must return
  the new `%ExMachine.Machine{}`. The :stop event metadata is enriched
  with the resulting snapshot, and `[:ex_machine, :transition]` is
  emitted once with the macrostep's transitions.
  """
  @spec macrostep(map(), (-> ExMachine.Machine.t())) :: ExMachine.Machine.t()
  def macrostep(metadata, fun) when is_function(fun, 0) do
    new_machine =
      :telemetry.span([:ex_machine, :macrostep], metadata, fn ->
        machine = fun.()
        {machine, Map.put(metadata, :snapshot, Snapshot.from_machine(machine))}
      end)

    emit_transitions(metadata, new_machine.trace)
    new_machine
  end

  @doc "Emit the `[:ex_machine, :stopped]` event."
  @spec stopped(pid(), term(), Snapshot.t()) :: :ok
  def stopped(server, reason, %Snapshot{} = snapshot) do
    :telemetry.execute(
      [:ex_machine, :stopped],
      %{system_time: System.system_time()},
      %{server: server, reason: reason, snapshot: snapshot}
    )
  end

  defp emit_transitions(_metadata, nil), do: :ok

  defp emit_transitions(_metadata, %Trace{transitions: []}), do: :ok

  defp emit_transitions(metadata, %Trace{transitions: ts}) do
    :telemetry.execute(
      [:ex_machine, :transition],
      %{count: length(ts)},
      Map.put(metadata, :transitions, ts)
    )
  end
end
