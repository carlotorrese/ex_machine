defmodule ExMachine.Statechart do
  @moduledoc """
  Module for building and validating statechart definitions.

  A Statechart is a compiled representation of a hierarchical state machine definition.
  It provides the foundation for creating and running state machines with complex
  hierarchical structures, transitions, actions, and guards.

  ## Statechart Structure

  A compiled statechart contains:

  - `states` - A flattened map of all states in the hierarchy with their full paths
  
  The statechart compiler takes a nested `State` definition and:
  
  1. Validates the state machine structure
  2. Flattens the hierarchy into addressable state paths  
  3. Validates all transitions reference valid states
  4. Ensures there are no duplicate state names in the same scope
  5. Verifies initial states are valid

  ## State Addressing

  States in a statechart are addressed using dot notation paths:
  
  - `"root"` - The root state
  - `"root.playing"` - A top-level state called "playing"  
  - `"root.playing.normal_speed"` - A nested state "normal_speed" inside "playing"

  ## Configuration

  The active configuration represents which states are currently active.
  Due to hierarchical composition, multiple states can be active simultaneously.
  
  For example, if a media player is in "normal speed" mode:
  - Configuration: `[["normal_speed", "playing", "root"]]`
  - Active states: "normal_speed", "playing", and "root"

  ## Building a Statechart

      # Define your state machine structure
      definition = %State{
        initial: "idle",
        substates: %{
          "idle" => %State{transitions: %{"start" => "running"}},
          "running" => %State{transitions: %{"stop" => "idle"}}
        }
      }
      
      # Compile into a statechart
      statechart = Statechart.build(definition)

  ## Validation

  The build process performs comprehensive validation:

  - All referenced states must exist
  - Initial states must be valid substates
  - No duplicate state names in the same scope
  - Transitions must reference valid target states
  - State hierarchy must be well-formed

  If validation fails, specific exceptions are raised describing the problem.

  ## Usage with __using__ macro

  You can also define statecharts using the `__using__` macro:

      defmodule MyMachine do
        use ExMachine.Statechart
        
        def definition do
          %State{
            # ... your state definition
          }
        end
      end

  """
  alias ExMachine.{State, Transition, Final, History}

  @type t :: %__MODULE__{
          states: map
        }

  defstruct states: nil

  defmacro __using__(_opts) do
    quote do
      alias ExMachine.{Statechart, State, Final, History, Transition}
      import ExMachine.Context
    end
  end

  def new() do
    %__MODULE__{}
  end

  defmodule InvalidDefinition do
    defexception [:message]

    @moduledoc """
    Raised when submitted an invalid definition
    """
    @impl true
    def exception(definition) do
      %__MODULE__{
        message: "Definition #{inspect(definition)} is not valid"
      }
    end
  end

  defmodule NotDefinedState do
    defexception [:message]

    @moduledoc """
    Raised when a state name is used that is not defined
    """
    @impl true
    def exception(state_name) do
      %__MODULE__{
        message: "State name \"#{state_name}\" is not defined"
      }
    end
  end

  defmodule DuplicatedState do
    defexception [:message]

    @moduledoc """
    Raised when a state name is used more than once
    """
    @impl true
    def exception(names_list) do
      %__MODULE__{
        message: "State names \"#{names_list}\" are not unique"
      }
    end
  end

  defmodule NotValidInitial do
    defexception [:message]

    @moduledoc """
    Raised when initial state of a composite state is not defined or is not
    a descendants of the state
    """
    @impl true
    def exception({initial, state_name}) do
      %__MODULE__{
        message:
          "Initial state \"#{initial}\" is not valid or not a descendant of composite state \"#{
            state_name
          }\""
      }
    end
  end

  @doc """
  Build and return a `Statechart` struct that contains the compiled and
  validated version of the statechart in `definition` argument,
  ready to be executed in a Machine.

  During compilation, Statechart verifies that the definition is valid and raise
  an exception if there is a problem.

  ## Examples
      iex> eng = Statechart.build(%State{initial: "s1", substates: %{ "s1" => %State{}}})
      iex> Enum.count(eng.states)
      2

      iex> Statechart.build("invalid")
      ** (ExMachine.Statechart.InvalidDefinition) Definition "invalid" is not valid

      iex> defs = %State{initial: "invalid_state", substates: %{ "s1" => %State{}}}
      iex> Statechart.build(defs)
      ** (ExMachine.Statechart.NotValidInitial) Initial state "invalid_state" is not valid or not a descendant of composite state "root"

  """
  def build(%State{substates: s} = definition) when s == %{},
    do: raise(InvalidDefinition, definition)

  def build(%State{} = definition) do
    new()
    |> Map.put(:states, build_state("root", definition))
    |> checks_states()
  end

  def build(definition), do: raise(InvalidDefinition, definition)

  defp new_state_definition(name, type, parent) do
    %{}
    |> Map.put(:name, name)
    |> Map.put(:type, type)
    |> Map.put(:parent, parent)
    |> Map.put(:children, MapSet.new())
    |> Map.put(:initial, nil)
    |> Map.put(:transitions, nil)
    |> Map.put(:entry, nil)
    |> Map.put(:exit, nil)
    |> Map.put(:macrosteps?, false)
    |> Map.put(:history?, false)
  end

  defp build_state(name, state, parent \\ nil)

  defp build_state(name, %State{substates: subst} = state, parent) when subst == %{} do
    state_def =
      new_state_definition(name, :simple, parent)
      |> Map.put(:transitions, build_transitions(state.transitions))
      |> Map.put(:entry, state.entry)
      |> Map.put(:exit, state.exit)

    %{name => state_def}
  end

  defp build_state(name, %State{} = state, parent) do
    substates_def =
      Enum.map(state.substates, fn {sub_name, sub_def} ->
        build_state(sub_name, sub_def, name)
      end)
      |> Enum.reduce(%{}, &Map.merge(&1, &2))

    children = MapSet.new(Map.keys(state.substates))

    state_def =
      new_state_definition(name, :composite, parent)
      |> Map.put(:children, children)
      |> Map.put(:initial, state.initial)
      |> Map.put(:transitions, build_transitions(state.transitions))
      |> Map.put(:entry, state.entry)
      |> Map.put(:exit, state.exit)
      |> check_history(children, substates_def)

    Map.merge(%{name => state_def}, substates_def)
  end

  defp build_state(name, %Final{entry: entry}, parent) do
    state_def =
      new_state_definition(name, :final, parent)
      |> Map.put(:entry, entry)

    %{name => state_def}
  end

  defp build_state(name, %History{type: type}, parent) do
    state_def = new_state_definition(name, type, parent)

    %{name => state_def}
  end

  defp check_history(state_definition, children, substates_def) do
    if Enum.any?(children, &(substates_def[&1][:type] == :deep or substates_def[&1][:type] == :shallow)) do
      Map.put(state_definition, :history?, true)
    else
      Map.put(state_definition, :history?, false)
    end
  end

  defp build_transitions(transitions) do
    for {event, tran} <- transitions, into: %{} do
      build_transition({event, tran})
    end
  end

  defp build_transition({event, %Transition{} = transition}) do
    {event,
     %{target: transition.target, guard: transition.guard, name: event, action: transition.action}}
  end

  defp build_transition({event, target}) when is_binary(target) do
    {event, %{target: target, guard: nil, name: event, action: nil}}
  end

  defp checks_states(statechart) do
    Enum.map(statechart.states, fn {name, state} ->
      statechart
      |> check_initial(name, state)
    end)

    statechart
  end

  defp check_initial(statechart, name, %{initial: initial, type: :composite}) do
    unless Enum.member?(get_descendants(statechart, name), initial),
      do: raise(NotValidInitial, {initial, name})

    statechart
  end

  defp check_initial(statechart, _name, _state), do: statechart

  # defp check_duplicates_states(states_list) do
  #   states =
  #     Enum.map(states_list, fn {name, _} -> name end)
  #     |> Enum.group_by(& &1)
  #     |> Enum.filter(fn
  #       {_, [_, _ | _]} -> true
  #       _ -> false
  #     end)
  #     |> Enum.map(fn {x, _} -> x end)

  #   unless Enum.empty?(states) do
  #     raise(DuplicatedState, states)
  #   else
  #     states_list
  #   end
  # end

  @doc """
  Returns the ancestors of `state` (parent of state, parent of parent, etc),
  in form of a list of string, ordered from nearest parent to (and always)
  the "root" state.

  ## Examples
      iex> defs = %State{initial: "s1", substates: %{ "s1" => %State{ initial: "s11", substates: %{ "s11" => %State{}}}}}
      iex> eng = Statechart.build(defs)
      iex> Statechart.get_ancestors(eng, "s11")
      ["s1", "root"]
  """
  def get_ancestors(statechart, state_name) do
    case statechart.states[state_name].parent do
      nil ->
        []

      parent ->
        [parent | get_ancestors(statechart, parent)]
    end
  end

  @doc """
  Returns the ancestors of `state` (parent of state, parent of parent, etc),
  in form of a list of string, ordered from nearest parent to (and excluded)
  the `until` state.

  ## Examples
      iex> defs = %State{initial: "s1", substates: %{ "s1" => %State{ initial: "s11", substates: %{ "s11" => %State{}}}}}
      iex> eng = Statechart.build(defs)
      iex> Statechart.get_ancestors_until(eng, "s11", "root")
      ["s1"]
  """
  def get_ancestors_until(statechart, state_name, until) do
    case statechart.states[state_name].parent do
      nil ->
        []

      parent ->
        if parent == until do
          []
        else
          [parent | get_ancestors_until(statechart, parent, until)]
        end
    end
  end

  @doc """
  Returns the descendants of `state`, in form of an unordered MapSet of string,
  containing all the descendants (children, children of children, etc) of `state`.

  ## Examples
      iex> defs = %State{initial: "s1", substates: %{ "s1" => %State{ initial: "s11", substates: %{ "s11" => %State{}}}}}
      iex> eng = Statechart.build(defs)
      iex> Statechart.get_descendants(eng, "root")
      MapSet.new(["s1", "s11"])
  """
  def get_descendants(statechart, state_name) when is_binary(state_name) do
    state = statechart.states[state_name]

    case MapSet.size(state[:children]) do
      0 -> MapSet.new()
      _ -> MapSet.union(state.children, get_descendants(statechart, state.children))
    end
  end

  def get_descendants(statechart, %MapSet{} = states) when is_map(states) do
    Enum.reduce(states, MapSet.new(), fn name, acc ->
      MapSet.union(acc, get_descendants(statechart, name))
    end)
  end

  @doc """
  Return list of initial states from argument `state` deep to a leaf state.

  The function uses `:initial` key in the `%State{}` definition,
  unless it encounter a history state (to be implemented)

    ## Examples
      iex> defs = %State{initial: "s1", substates: %{ "s1" => %State{ initial: "s11", substates: %{ "s11" => %State{}}}}}
      iex> eng = Statechart.build(defs)
      iex> Statechart.get_initials(eng, "root")
      ["root", "s1", "s11"]
      iex> Statechart.get_initials(eng, "s1")
      ["s1", "s11"]

  """
  def get_initials(statechart, state) do
    # TODO: implements history
    case statechart.states[state][:initial] do
      nil -> [state]
      initial -> [state | get_initials(statechart, initial)]
    end
  end

  @doc """
  Return the list of enter actions for each state in list `states_list`,
  if defined for the state,  in the same exact order of `states_list`
  """
  def get_entry_actions(statechart, states_list) do
    for state_name <- states_list, statechart.states[state_name][:entry] do
      statechart.states[state_name].entry
    end
  end

  @doc """
  Return the list of exit actions for each state in list `states_list`,
  if defined for the state, in the same exact order of `states_list`
  """
  def get_exit_actions(statechart, states_list) do
    for state_name <- states_list, statechart.states[state_name][:exit] do
      statechart.states[state_name].exit
    end
  end

  @doc """
  Return a transition map if `state` have a transition defined
  to handle `event`, otherwise `nil`
  """
  def get_transition_for(statechart, state, {event, _params}) do
    statechart.states[state][:transitions][event]
  end

  def get_transition_for(statechart, state, event) do
    statechart.states[state][:transitions][event]
  end

  @doc """
  Return the Least Common Compound Ancestor of `states` list.

  LCCA of a list `states` is the lowest (i.e. deepest) state in the state
  hierarchy that has all state in `states` as descendants.

  In other words LCCA is the state `s` such that `s` is a ancestor of all
  states on `states` list and no descendants of `s` has this property.

  Return `nil` if in the `states` list is present the root state because can't
  exist a state that is parent of root state.

  Note that since we are speaking of ancestor (parent or parent
  of a parent, etc.) the LCCA is never a member of `state` list.

  """

  def find_lcca(statechart, states) when is_list(states) do
    ancestors = get_ancestors(statechart, hd(states))

    Enum.reduce_while(ancestors, nil, fn ancestor, _acc ->
      if Enum.all?(tl(states), fn state ->
           Enum.member?(get_descendants(statechart, ancestor), state)
         end) do
        {:halt, ancestor}
      else
        {:cont, nil}
      end
    end)
  end

  @doc """
  Returns a list of states that must be exited when the machine is exiting
  from the state `source`, considering the `lcca`
  """
  def get_exiting_states(statechart, source, lcca) do
    [source | get_ancestors_until(statechart, source, lcca)]
  end

  @doc """
  Returns a list of states that must be entered when the machine is entering
  in the state `target`, considering the `lcca`
  """
  def get_entering_states(statechart, target, lcca) do
    Enum.reverse(get_ancestors_until(statechart, target, lcca)) ++
      get_initials(statechart, target)
  end
end
