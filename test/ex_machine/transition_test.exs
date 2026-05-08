defmodule ExMachine.TransitionTest do
  use ExUnit.Case, async: true

  alias ExMachine.Transition

  doctest Transition

  describe "new/1" do
    test "builds with required :source" do
      assert %Transition{source: :a, target: :b, event: :go, type: :external} =
               Transition.new(source: :a, event: :go, target: :b)
    end

    test "defaults type to :external" do
      assert %Transition{type: :external} = Transition.new(source: :a)
    end

    test "raises if :source is missing" do
      assert_raise ArgumentError, fn -> Transition.new(target: :a) end
    end

    test "raises on invalid :type" do
      assert_raise ArgumentError, ~r/transition :type/, fn ->
        Transition.new(source: :a, type: :weird)
      end
    end
  end

  describe "eventless?/1" do
    test "true when event is nil" do
      assert Transition.eventless?(Transition.new(source: :a))
    end

    test "false when event is set" do
      refute Transition.eventless?(Transition.new(source: :a, event: :go))
    end
  end
end
