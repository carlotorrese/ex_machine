defmodule ExMachine do
  @moduledoc """
  Functional hierarchical state machines for Elixir.

  ExMachine implements the Statechart formalism (Harel 1987 / SCXML W3C) on top
  of pure-functional Elixir. A statechart is declared at compile-time via the
  `ExMachine.Statechart` DSL; the resulting `ExMachine.Definition` can be
  executed either functionally — via `ExMachine.Engine` — or as a long-lived
  GenServer process — via `ExMachine.Server`.

  ## Modules

    * `ExMachine.Statechart` — DSL to declare a statechart at compile time.
    * `ExMachine.Definition` — compiled, validated statechart definition.
    * `ExMachine.StateNode` — node in a definition (atomic, compound, parallel,
      region, final, history, choice).
    * `ExMachine.Transition` — single transition record.
    * `ExMachine.Step` — accumulator threaded through actions and guards.
    * `ExMachine.Configuration` — set of currently active states.
    * `ExMachine.Machine` — running statechart instance.
    * `ExMachine.Engine` — pure-functional execution engine.
    * `ExMachine.Trace` — audit trail of macro/microsteps.
    * `ExMachine.Server` — GenServer wrapper with delayed events,
      invoked services, pub/sub subscribers and `:telemetry`.
    * `ExMachine.Visualize` — render to Mermaid `stateDiagram-v2` and
      W3C SCXML XML.

  > #### Status {: .info}
  >
  > Version `0.2.0-alpha.1`. Engine is feature-complete for the SCXML
  > pure-execution subset (atomic, compound, parallel, region, final,
  > history, choice, internal/external transitions, eventless,
  > run-to-completion, `done.state.<id>` propagation). Server-mode adds
  > delayed events (`Step.send_after/4`), invoked services
  > (`Step.invoke/4`) and a pub/sub Registry. The public API may still
  > tighten before `0.2.0` proper.

  ## Hello, traffic light

      defmodule TrafficLight do
        use ExMachine.Statechart

        initial :red

        state :red,    do: on(:timer, target: :green)
        state :green,  do: on(:timer, target: :yellow)
        state :yellow, do: on(:timer, target: :red)
      end

      iex> machine = ExMachine.init(TrafficLight)
      iex> ExMachine.atomic_states(machine)
      [:red]
      iex> machine = ExMachine.dispatch(machine, :timer)
      iex> ExMachine.atomic_states(machine)
      [:green]
  """

  alias ExMachine.{Engine, Machine}

  @doc "Returns the library version."
  @spec version() :: String.t()
  def version, do: "0.2.0-alpha.1"

  @doc """
  Build and start a machine from a statechart module (or a precompiled
  `ExMachine.Definition`). Optionally override the initial context.

  Returns a running `ExMachine.Machine` whose initial entry actions have
  already executed.
  """
  @spec init(module() | ExMachine.Definition.t(), term()) :: Machine.t()
  def init(statechart_or_def, context \\ nil)

  def init(module, context) when is_atom(module) do
    init(module.__statechart__(), context)
  end

  def init(%ExMachine.Definition{} = definition, context) do
    definition
    |> Machine.new(context)
    |> Engine.init()
  end

  @doc """
  Dispatch an event to a running machine. Returns the new machine value
  after run-to-completion. See `ExMachine.Engine.dispatch/2`.
  """
  @spec dispatch(Machine.t(), term()) :: Machine.t()
  defdelegate dispatch(machine, event), to: Engine

  @doc "Atomic states currently active. See `ExMachine.Machine.atomic_states/1`."
  @spec atomic_states(Machine.t()) :: [atom()]
  defdelegate atomic_states(machine), to: Machine
end
