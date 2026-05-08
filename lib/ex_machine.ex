defmodule ExMachine do
  @moduledoc """
  Functional hierarchical state machines for Elixir.

  ExMachine implements the Statechart formalism (Harel 1987 / SCXML W3C) on top
  of pure-functional Elixir. A statechart is declared at compile-time via the
  `ExMachine.Statechart` DSL; the resulting `ExMachine.Definition` can be
  executed either functionally — via `ExMachine.Engine` — or as a supervised
  GenServer process — via `ExMachine.Server` (M6).

  ## Modules

    * `ExMachine.Statechart` — DSL to declare a statechart at compile time.
    * `ExMachine.Definition` — compiled, validated statechart definition.
    * `ExMachine.StateNode` — node in a definition (atomic, compound, parallel,
      region, final, history, choice).
    * `ExMachine.Transition` — single transition record.
    * `ExMachine.Step` — accumulator threaded through actions and guards;
      replaces the legacy practice of polluting the user context with engine
      bookkeeping.

  > #### Status {: .info}
  >
  > Version `0.2.0-alpha.1` is a ground-up rewrite. The 0.1.x line is gone:
  > there is no migration path, but the surface area is small and the new DSL
  > should be familiar to anyone who has used XState or SCXML.

  ## Hello, traffic light

      defmodule TrafficLight do
        use ExMachine.Statechart

        initial :red

        state :red,    do: on(:timer, target: :green)
        state :green,  do: on(:timer, target: :yellow)
        state :yellow, do: on(:timer, target: :red)
      end

      iex> def_ = TrafficLight.__statechart__()
      iex> def_.root
      :traffic_light

  See `ExMachine.Statechart` for the full DSL surface.
  """

  @doc "Returns the library version, in sync with `mix.exs`."
  @spec version() :: String.t()
  def version, do: "0.2.0-alpha.1"
end
