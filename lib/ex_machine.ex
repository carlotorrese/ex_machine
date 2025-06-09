defmodule ExMachine do
  alias ExMachine.Machine

  @moduledoc """

  """
  def init(statechart, context) do
    Machine.init(statechart, context)
  end

  def dispatch(machine, event) do
    Machine.dispatch(machine, event)
  end
end
