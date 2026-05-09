defmodule ExMachine.Application do
  @moduledoc false
  # Top-level OTP application: starts the duplicate-keyed pub/sub Registry
  # used by `ExMachine.Server` for subscribers, and any future
  # process-level infrastructure.

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :duplicate, name: ExMachine.PubSub}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: ExMachine.Supervisor)
  end
end
