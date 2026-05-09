defmodule ExMachine.Integration.ChoiceTest.Router do
  @moduledoc false
  # A choice pseudostate dispatches to one of three branches based on the
  # value of `:role` in the context. The third branch chains through a
  # nested choice to exercise recursive resolution.

  use ExMachine.Statechart

  initial_context(%{role: :guest, score: 0})
  initial(:lobby)

  state :lobby do
    on(:enter, target: :gate)
  end

  choice :gate do
    cond_branch(&__MODULE__.admin?/1, target: :admin_room)
    cond_branch(&__MODULE__.member?/1, target: :member_room)
    otherwise(target: :nested_gate)
  end

  choice :nested_gate do
    cond_branch(&__MODULE__.high_score?/1, target: :vip_room)
    otherwise(target: :guest_room)
  end

  state(:admin_room)
  state(:member_room)
  state(:guest_room)
  state(:vip_room)

  def admin?(%{role: :admin}), do: true
  def admin?(_), do: false
  def member?(%{role: :member}), do: true
  def member?(_), do: false
  def high_score?(%{score: s}), do: s >= 100
end

defmodule ExMachine.Integration.ChoiceTest.NoMatch do
  @moduledoc false
  use ExMachine.Statechart

  initial_context(%{flag: false})
  initial(:start)

  state :start do
    on(:go, target: :pick)
  end

  choice :pick do
    cond_branch(&__MODULE__.flag?/1, target: :landed)
  end

  state(:landed)

  def flag?(%{flag: true}), do: true
  def flag?(_), do: false
end

defmodule ExMachine.Integration.ChoiceTest do
  use ExUnit.Case, async: true

  alias ExMachine.Integration.ChoiceTest.{NoMatch, Router}

  test "first matching branch wins (admin)" do
    machine = ExMachine.init(Router)
    machine = %{machine | context: %{role: :admin, score: 0}}
    machine = ExMachine.dispatch(machine, :enter)

    assert ExMachine.atomic_states(machine) == [:admin_room]
  end

  test "second branch wins when first fails (member)" do
    machine = ExMachine.init(Router)
    machine = %{machine | context: %{role: :member, score: 0}}
    machine = ExMachine.dispatch(machine, :enter)

    assert ExMachine.atomic_states(machine) == [:member_room]
  end

  test "otherwise routes through a nested choice" do
    machine = ExMachine.init(Router)
    machine = %{machine | context: %{role: :guest, score: 200}}
    machine = ExMachine.dispatch(machine, :enter)

    assert ExMachine.atomic_states(machine) == [:vip_room]
  end

  test "nested choice falls back to its own otherwise" do
    machine = ExMachine.init(Router)
    machine = %{machine | context: %{role: :guest, score: 0}}
    machine = ExMachine.dispatch(machine, :enter)

    assert ExMachine.atomic_states(machine) == [:guest_room]
  end

  test "raises if no branch matches and no :otherwise is declared" do
    machine = ExMachine.init(NoMatch)

    assert_raise RuntimeError, ~r/choice :pick has no matching branch/, fn ->
      ExMachine.dispatch(machine, :go)
    end
  end
end
