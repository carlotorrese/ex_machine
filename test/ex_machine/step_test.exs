defmodule ExMachine.StepTest do
  use ExUnit.Case, async: true

  alias ExMachine.Step

  doctest Step

  describe "new/2" do
    test "builds with context and optional event" do
      assert %Step{context: %{}, event: nil} = Step.new(%{})
      assert %Step{event: :tick} = Step.new(%{}, :tick)
    end
  end

  describe "context manipulation" do
    test "put_context replaces context entirely" do
      step = Step.new(%{a: 1}) |> Step.put_context(%{b: 2})
      assert step.context == %{b: 2}
    end

    test "assign sets a key" do
      step = Step.new(%{}) |> Step.assign(:x, 42)
      assert step.context == %{x: 42}
    end

    test "update raises if key absent" do
      assert_raise KeyError, fn ->
        Step.new(%{}) |> Step.update(:missing, &(&1 + 1))
      end
    end

    test "update transforms existing key" do
      step = Step.new(%{n: 1}) |> Step.update(:n, &(&1 * 10))
      assert step.context == %{n: 10}
    end
  end

  describe "raise_event/2" do
    test "appends in order" do
      step =
        Step.new(%{})
        |> Step.raise_event(:a)
        |> Step.raise_event(:b)
        |> Step.raise_event({:c, %{p: 1}})

      assert step.raised == [:a, :b, {:c, %{p: 1}}]
    end
  end

  describe "send_after/4" do
    test "records owner state and returns ref" do
      {ref, step} = Step.send_after(Step.new(%{}), :ping, 100, :running)
      assert is_reference(ref)
      assert [{^ref, :ping, 100, :running}] = step.delayed
    end
  end

  describe "invoke/4" do
    test "stores invocation spec under user-chosen id" do
      spec = {Kernel, :+, [1, 2]}
      step = Step.invoke(Step.new(%{}), :sum, spec, :running)
      assert step.invokes == [{:sum, spec, :running}]
    end
  end

  describe "cancel/2" do
    test "appends a ref to cancels" do
      ref = make_ref()
      step = Step.new(%{}) |> Step.cancel(ref)
      assert step.cancels == [ref]
    end

    test "also accepts an invoke id (atom)" do
      step = Step.new(%{}) |> Step.cancel(:sum)
      assert step.cancels == [:sum]
    end
  end
end
