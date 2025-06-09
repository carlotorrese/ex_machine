defmodule ExMachine.Microstep do
  @moduledoc """
  Represents an atomic execution step in statechart processing.

  A microstep is the smallest, atomic step that a statechart can execute.
  It involves the processing of a single transition (or, in the case of
  parallel states, a single set of transitions). A microstep may change
  the active configuration, update the data model and/or generate new
  (internal and/or external) events.

  ## Definition (From SCXML)

  A microstep involves the processing of a single transition (or, in the case
  of parallel states, a single set of transitions.) A microstep may change
  the active configuration, update the data model and/or generate new
  (internal and/or external) events. This, by causality, may in turn enable
  additional transitions which will be handled in the next microstep in the
  sequence, and so on.

  ## Definition (From SISMIC)

  The smallest, atomic step that a statechart can execute. A step considers
  an event, takes a transition and results in a list of entered states and
  a list of exited states. Order in the two lists is REALLY important!

  ## Fields

  * `:params` - Event parameters or `nil` for eventless transitions.
    If event has parameters, the term is in the form `{event, params}`
  * `:transition` - The `ExMachine.Transition` processed or `nil` if no transition
  * `:entered` - Ordered list of states entered during this microstep
  * `:exited` - Ordered list of states exited during this microstep  
  * `:actions` - List of actions executed during this microstep

  ## State Order Importance

  The order of states in the `:entered` and `:exited` lists is critical
  for correct statechart behavior:

  * **Exit order**: States are exited from most nested to least nested
    (children before parents)
  * **Entry order**: States are entered from least nested to most nested
    (parents before children)

  This ensures that exit actions run before entry actions, and that
  parent states are properly initialized before their children.

  ## Examples

      # Microstep for a simple transition
      %ExMachine.Microstep{
        params: {:login, %{username: "john"}},
        transition: %ExMachine.Transition{
          source: "logged_out",
          target: "logged_in",
          event: "login"
        },
        entered: ["logged_in"],
        exited: ["logged_out"],
        actions: [:validate_credentials, :create_session]
      }

      # Microstep for entering nested states
      %ExMachine.Microstep{
        params: {:start_game, %{level: 1}},
        transition: %ExMachine.Transition{
          source: "menu",
          target: "playing.level1.normal"
        },
        entered: ["playing", "level1", "normal"],  # Parent to child order
        exited: ["menu"],
        actions: [:initialize_game, :load_level]
      }

      # Eventless microstep (internal transition)  
      %ExMachine.Microstep{
        params: nil,
        transition: %ExMachine.Transition{
          source: "processing",
          target: "completed"
        },
        entered: ["completed"],
        exited: ["processing"],
        actions: [:finalize_process]
      }

  ## Usage in Debugging

  Microsteps provide detailed information about individual state changes,
  making them invaluable for debugging statechart behavior:

      # Example function to analyze microstep execution
      defp analyze_microstep(microstep) do
        IO.puts("Microstep Analysis:")
        IO.puts("  Event: \#{inspect(microstep.params)}")
        if microstep.transition do
          IO.puts("  Transition: \#{microstep.transition.source} -> \#{microstep.transition.target}")
        end
        IO.puts("  States exited: \#{inspect(microstep.exited)}")
        IO.puts("  States entered: \#{inspect(microstep.entered)}")
        IO.puts("  Actions executed: \#{inspect(microstep.actions)}")
      end

  """
  @type t :: %__MODULE__{
          params: term(),
          transition: ExMachine.Transition.t() | nil,
          entered: list(String.t()),
          exited: list(String.t()),
          actions: list(atom())
        }

  defstruct params: nil,
            transition: nil,
            entered: [],
            exited: [],
            actions: []

  @doc """
  Create a new empty microstep.

  ## Examples

      iex> microstep = ExMachine.Microstep.new()
      iex> is_struct(microstep, ExMachine.Microstep)
      true
      iex> microstep.entered
      []
      iex> microstep.exited
      []

  """
  def new(), do: %__MODULE__{}
end
