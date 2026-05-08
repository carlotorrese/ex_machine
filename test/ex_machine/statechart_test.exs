defmodule ExMachine.StatechartTest do
  use ExUnit.Case, async: true

  alias ExMachine.{Definition, Transition}

  # ── Compile-time fixtures ─────────────────────────────────────────────────

  defmodule TrafficLight do
    @moduledoc false
    use ExMachine.Statechart

    initial_context(%{cycles: 0})
    initial(:red)

    state :red do
      on(:timer, target: :green)
    end

    state :green do
      on(:timer, target: :yellow)
    end

    state :yellow do
      on(:timer, target: :red, action: &TrafficLight.bump/1)
    end

    def bump(step), do: ExMachine.Step.update(step, :cycles, &(&1 + 1))
  end

  defmodule Hierarchical do
    @moduledoc false
    use ExMachine.Statechart

    initial(:idle)

    state :idle do
      on(:start, target: :running)
    end

    state :running do
      initial(:slow)
      on(:stop, target: :idle)

      state :slow do
        on(:go_fast, target: :fast)
      end

      state :fast do
        on(:go_slow, target: :slow)
      end
    end
  end

  defmodule WithFinal do
    @moduledoc false
    use ExMachine.Statechart

    initial(:alive)

    state :alive do
      on(:die, target: :dead)
    end

    final(:dead)
  end

  defmodule WithChoice do
    @moduledoc false
    use ExMachine.Statechart

    initial(:start)

    state :start do
      on(:decide, target: :router)
    end

    state(:allowed)
    state(:denied)

    choice :router do
      cond_branch(&__MODULE__.allowed?/1, target: :allowed)
      otherwise(target: :denied)
    end

    def allowed?(ctx), do: Map.get(ctx, :allowed, false)
  end

  defmodule ParallelMachine do
    @moduledoc false
    use ExMachine.Statechart, type: :parallel

    region :speed, initial: :slow do
      state(:slow, do: on(:go, target: :fast))
      state(:fast)
    end

    region :wipers, initial: :off do
      state(:off, do: on(:rain, target: :on))
      state(:on)
    end
  end

  defmodule WithHistory do
    @moduledoc false
    use ExMachine.Statechart

    initial(:off)

    state :off do
      on(:switch_on, target: :on)
    end

    state :on do
      initial(:idle)
      on(:switch_off, target: :off)

      history(:hist, type: :deep, default: :idle)

      state(:idle, do: on(:work, target: :busy))
      state(:busy)
    end
  end

  # ── Tests ─────────────────────────────────────────────────────────────────

  describe "TrafficLight" do
    test "compiles and exposes a definition" do
      def_ = TrafficLight.__statechart__()
      assert %Definition{} = def_
      assert def_.root == :traffic_light
      assert def_.initial_context == %{cycles: 0}
    end

    test "root is compound with three atomic substates" do
      def_ = TrafficLight.__statechart__()
      root = Definition.fetch!(def_, def_.root)
      assert root.kind == :compound
      assert root.initial == :red
      assert root.substates == [:red, :green, :yellow]

      for id <- [:red, :green, :yellow] do
        assert Definition.fetch!(def_, id).kind == :atomic
      end
    end

    test "yellow's transition has an action" do
      def_ = TrafficLight.__statechart__()

      assert [%Transition{event: :timer, target: :red, action: act}] =
               Definition.fetch!(def_, :yellow).transitions

      assert is_function(act, 1)
    end
  end

  describe "Hierarchical" do
    test "running is compound with two atomic substates" do
      def_ = Hierarchical.__statechart__()
      running = Definition.fetch!(def_, :running)
      assert running.kind == :compound
      assert running.initial == :slow
      assert running.substates == [:slow, :fast]
    end

    test "ancestors of :fast" do
      def_ = Hierarchical.__statechart__()
      assert Definition.ancestors(def_, :fast) == [:running, :hierarchical]
    end

    test "descendants of :running" do
      def_ = Hierarchical.__statechart__()
      assert Definition.descendants(def_, :running) == MapSet.new([:slow, :fast])
    end
  end

  describe "WithFinal" do
    test "final is recognised" do
      def_ = WithFinal.__statechart__()
      assert Definition.fetch!(def_, :dead).kind == :final
    end
  end

  describe "WithChoice" do
    test "choice node carries branches in declaration order" do
      def_ = WithChoice.__statechart__()
      router = Definition.fetch!(def_, :router)
      assert router.kind == :choice

      assert [
               {guard, :allowed},
               {nil, :denied}
             ] = router.choice_branches

      assert is_function(guard, 1)
      assert guard.(%{allowed: true}) == true
      assert guard.(%{allowed: false}) == false
    end
  end

  describe "ParallelMachine" do
    test "root is parallel with two regions" do
      def_ = ParallelMachine.__statechart__()
      root = Definition.fetch!(def_, def_.root)
      assert root.kind == :parallel
      assert root.substates == [:speed, :wipers]
    end

    test "each region has its initial substate" do
      def_ = ParallelMachine.__statechart__()
      assert Definition.fetch!(def_, :speed).kind == :region
      assert Definition.fetch!(def_, :speed).initial == :slow
      assert Definition.fetch!(def_, :wipers).kind == :region
      assert Definition.fetch!(def_, :wipers).initial == :off
    end
  end

  describe "WithHistory" do
    test "history pseudostate carries type and default" do
      def_ = WithHistory.__statechart__()
      hist = Definition.fetch!(def_, :hist)
      assert hist.kind == :history
      assert hist.history_type == :deep
      assert hist.history_default == :idle
      assert hist.parent == :on
    end
  end

  describe "compile-time errors" do
    test "duplicate state id raises" do
      assert_raise ArgumentError, ~r/duplicate state id/, fn ->
        defmodule Duped do
          use ExMachine.Statechart
          initial(:a)
          state(:a)
          state(:a)
        end
      end
    end

    test "missing :initial raises during validation" do
      assert_raise ExMachine.Definition.Error, ~r/has no :initial/, fn ->
        defmodule NoInitial do
          use ExMachine.Statechart
          state(:a)
          state(:b)
        end
      end
    end

    test "unknown transition target raises" do
      assert_raise ExMachine.Definition.Error, ~r/targets unknown state/, fn ->
        defmodule BadTarget do
          use ExMachine.Statechart
          initial(:a)
          state(:a, do: on(:x, target: :ghost))
        end
      end
    end
  end
end
