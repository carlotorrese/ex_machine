defmodule ExMachine.PropertyTest.EngineProperties do
  @moduledoc """
  Property-based tests over the SCXML invariants the engine must
  preserve. Generators produce small valid `%Definition{}` values; for
  each one we run a sequence of random events and check the invariants
  after every macrostep.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias ExMachine.{Configuration, Definition, Engine, Machine}
  alias ExMachine.Test.Generators

  @max_dispatches 6

  defp definitions do
    StreamData.one_of([
      Generators.flat_fsm(),
      Generators.nested_compound(),
      Generators.small_parallel()
    ])
  end

  property "init/1 never raises and produces a stable configuration" do
    check all(def_ <- definitions()) do
      machine = Machine.new(def_) |> Engine.init()
      assert %Machine{} = machine
      assert_invariants(machine)
    end
  end

  property "configuration is closed under ancestry after init and after every dispatch" do
    check all(
            def_ <- definitions(),
            events <- StreamData.list_of(Generators.event(), max_length: @max_dispatches)
          ) do
      machine = Machine.new(def_) |> Engine.init()
      assert_ancestry_closed(machine)

      Enum.reduce(events, machine, fn event, m ->
        m = if m.running?, do: Engine.dispatch(m, event), else: m
        assert_ancestry_closed(m)
        m
      end)
    end
  end

  property "atomic_states returns only :atomic or :final node ids" do
    check all(def_ <- definitions()) do
      machine = Machine.new(def_) |> Engine.init()

      for id <- Configuration.atomic_states(machine.configuration, def_) do
        assert Definition.fetch!(def_, id).kind in [:atomic, :final]
      end
    end
  end

  property "an unknown event does not change configuration or context" do
    check all(def_ <- definitions()) do
      machine = Machine.new(def_) |> Engine.init()

      if machine.running? do
        new_machine = Engine.dispatch(machine, :__no_such_event_in_any_fixture__)
        assert new_machine.configuration == machine.configuration
        assert new_machine.context == machine.context
      end
    end
  end

  property "every microstep records exited ⊆ prior config and entered ⊆ new config" do
    check all(
            def_ <- definitions(),
            events <- StreamData.list_of(Generators.event(), max_length: @max_dispatches)
          ) do
      machine = Machine.new(def_) |> Engine.init()

      Enum.reduce(events, machine, fn event, prev ->
        if prev.running? do
          next = Engine.dispatch(prev, event)
          # Every exited id was active before the macrostep.
          for id <- next.trace.exited do
            assert MapSet.member?(prev.configuration, id),
                   "exited #{inspect(id)} not present in prior configuration"
          end

          # Every entered id is active after the macrostep.
          for id <- next.trace.entered do
            assert MapSet.member?(next.configuration, id),
                   "entered #{inspect(id)} not present in new configuration"
          end

          next
        else
          prev
        end
      end)
    end
  end

  # ── helpers ──────────────────────────────────────────────────────────────

  defp assert_invariants(machine) do
    assert_ancestry_closed(machine)

    for id <- Configuration.atomic_states(machine.configuration, machine.definition) do
      assert Definition.fetch!(machine.definition, id).kind in [:atomic, :final]
    end
  end

  defp assert_ancestry_closed(%Machine{configuration: config, definition: def_}) do
    for id <- config do
      ancestors = Definition.ancestors(def_, id)

      for a <- ancestors do
        assert MapSet.member?(config, a),
               "ancestor #{inspect(a)} of active state #{inspect(id)} is not in configuration"
      end
    end
  end
end
