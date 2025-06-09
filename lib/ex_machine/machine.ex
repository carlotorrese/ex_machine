defmodule ExMachine.Machine do
  @moduledoc """
  Core module for state machine execution and management.

  The `Machine` module represents a running state machine instance. It maintains the current
  state configuration, context data, execution history, and provides the core execution engine
  for processing events and managing state transitions.

  ## Machine Structure

  A machine contains:

  - `statechart` - The compiled state machine definition
  - `configuration` - Current active states (hierarchical paths)
  - `running?` - Whether the machine is currently running
  - `macrosteps` - History of transition sequences  
  - `queue` - Queue of internal events to process
  - `context` - Extended state data that travels with the machine
  - `states_histories` - History states for complex statecharts

  ## State Configuration

  Unlike simple finite state machines, a statechart machine can be in multiple states
  simultaneously due to hierarchical composition. The configuration represents all
  currently active states as a list of state paths from leaf states to the root.

  For example, if a machine is in state "playing/normal_speed", the configuration
  would be `[["normal_speed", "playing", "root"]]`.

  ## Event Processing

  Events are processed using run-to-completion semantics:

  1. An external event is received
  2. All possible transitions are evaluated
  3. Actions are executed and may generate internal events  
  4. Internal events are processed until no more transitions are possible
  5. The machine reaches a stable configuration

  ## Examples

      # Initialize a machine
      statechart = Statechart.build(MyMachine.definition())
      machine = Machine.init(statechart, %{counter: 0})
      
      # Process events
      machine = Machine.dispatch(machine, "start")
      machine = Machine.dispatch(machine, "increment")
      
      # Check current state
      IO.inspect(machine.configuration)
      IO.inspect(machine.context)

  """
  alias ExMachine.{Statechart, Macrostep, Microstep, Context}

  @type t :: %__MODULE__{
          statechart: Statechart.t(),
          configuration: [[String.t()]],
          running?: boolean,
          macrosteps: [%Macrostep{}],
          queue: list,
          context: term,
          states_histories: map
        }

  defstruct statechart: nil,
            configuration: nil,
            running?: false,
            macrosteps: nil,
            queue: [],
            context: nil,
            states_histories: %{}

  def new(statechart, context) do
    %__MODULE__{
      statechart: statechart,
      context: context,
      macrosteps: [Macrostep.new()]
    }
  end

  defmodule NotRunning do
    defexception [:message]

    @moduledoc """
    Raised when dispatching an event to a not running machine
    """
    @impl true
    def exception(_) do
      %__MODULE__{
        message: "Machine is not running"
      }
    end
  end

  @doc """
  Initialize the machine, performing all the necessary activities
  and returning the machine in its initial active configuration

  The log of the transition to initial state are recorded in the first
  Macrostep
  """
  def init(statechart, context) do
    microstep = build_initial_microstep(statechart)

    new(statechart, context)
    |> do_microstep(microstep)
    |> do_internal_transitions()
    |> Map.put(:running?, true)
  end

  @doc """
  Dispatch an event to the machine, performing all the necessary activities
  and returning the machine in the new active configuration.

  If during execution some activities raises internal events, the machine
  continues execution of these events until the internal queue is empty
  (run to completion)
  """
  def dispatch(machine, event) do
    unless machine.running?, do: raise(NotRunning)

    machine
    |> Map.replace!(:macrosteps, [Macrostep.new() | machine.macrosteps])
    |> do_transition(event)
    |> do_internal_transitions()
  end

  @doc """
  Returns last executed macrostep
  """
  def last_macrostep(machine) do
    hd(machine.macrosteps)
  end

  @doc """
  Returns last executed list of microstep
  """
  def last_microsteps(machine) do
    hd(machine.macrosteps).microsteps
  end

  @doc """
  Returns last executed list of transitions
  """
  def last_transitions(machine) do
    last_macrostep(machine).transitions
  end

  @doc """
  Returns list of currents active states.

  Generally, there is only one active state if the machine is not in a parallel
  (orthogonal) state, otherwise its the list of active states
  of each active region
  """
  def get_active_states(machine) do
    Enum.map(machine.configuration, &hd(&1))
  end

  defp build_initial_microstep(statechart) do
    initial = Statechart.get_initials(statechart, "root")

    Microstep.new()
    |> Map.replace!(:entered, initial)
    |> Map.replace!(:transition, %{name: nil, guard: nil, action: nil, target: List.last(initial)})
    |> Map.replace!(:actions, Statechart.get_entry_actions(statechart, initial))
  end

  defp do_transition(machine, "done.state.root") do
    Map.replace!(machine, :running?, false)
  end

  defp do_transition(machine, {event_name, params}) do
    # adds params to machine's context, before build microstep,
    # because they can be used by guard functions
    # TODO: refactor, I don't like
    microstep =
      machine
      |> add_params_to_context(params)
      |> build_microstep(event_name, params)

    machine
    |> do_microstep(microstep)
    |> remove_params_from_context()
  end

  defp do_transition(machine, event_name) when is_binary(event_name) do
    do_transition(machine, {event_name, nil})
  end

  defp do_internal_transitions(%{queue: []} = machine), do: machine

  defp do_internal_transitions(machine) do
    machine
    |> Map.put(:queue, tl(machine.queue))
    |> do_transition(hd(machine.queue))
    |> do_internal_transitions()
  end

  defp find_transition(machine, event_name) do
    # Find a valid transition for the `event_name`.
    # If a transition is fund with a guard function, it is verified that it return true
    # Return nil if no transition available
    # TODO: orthogonal regions

    Enum.reduce_while(hd(machine.configuration), nil, fn state_name, _acc ->
      case Statechart.get_transition_for(machine.statechart, state_name, event_name) do
        nil ->
          {:cont, nil}

        transition ->
          case transition.guard do
            nil ->
              {:halt, transition}

            guard ->
              if guard.(machine.context), do: {:halt, transition}, else: {:cont, nil}
          end
      end
    end)
  end

  defp build_microstep(machine, event_name, params) do
    case find_transition(machine, event_name) do
      nil ->
        nil

      transition ->
        # TODO: orthogonal
        source = hd(hd(machine.configuration))
        target = transition.target
        lcca = Statechart.find_lcca(machine.statechart, [source, target])

        exiting_states = Statechart.get_exiting_states(machine.statechart, source, lcca)

        # TODO: if target is an history must resume saved configuration (deep or shallow)
        entering_states = Statechart.get_entering_states(machine.statechart, target, lcca)

        actions =
          Statechart.get_exit_actions(machine.statechart, exiting_states) ++
            if(transition.action, do: [transition.action], else: []) ++
            Statechart.get_entry_actions(machine.statechart, entering_states)

        Microstep.new()
        |> Map.replace!(:transition, transition)
        |> Map.replace!(:params, params)
        |> Map.replace!(:exited, exiting_states)
        |> Map.replace!(:entered, entering_states)
        |> Map.replace!(:actions, actions)
    end
  end

  defp do_microstep(machine, nil), do: machine

  defp do_microstep(machine, microstep) do
    # TODO: orthogonal
    # set microstep as the last microstep of the last macrostep (current macrostep)
    # set configuration = [last entered_states state | last entered_states state ancestors]
    # modifies the context, executing all activities in order of execution

    next_state = List.last(microstep.entered)
    new_configuration = [[next_state | Statechart.get_ancestors(machine.statechart, next_state)]]
    macrostep = add_microstep(hd(machine.macrosteps), microstep)
    new_context = do_actions(microstep.actions, machine.context)

    machine
    |> save_histories(microstep.exited)
    |> Map.replace!(:macrosteps, [macrostep | tl(machine.macrosteps)])
    |> Map.replace!(:configuration, new_configuration)
    |> Map.replace!(:context, new_context)
    |> process_final_state()
    |> extract_raised_events()
  end

  defp save_histories(machine, exited_states) do
    Enum.reduce(exited_states, machine, fn state_name, machine ->
      save_state_configuration(machine, state_name)
    end)
  end

  defp save_state_configuration(machine, state_name) do
    if machine.statechart.states[state_name].history? do
      config = get_state_config(machine.configuration, state_name)
      machine
      |> put_in_history(state_name, config)
    else
      machine
    end
  end

  defp get_state_config(configuration, state_name) do
    # extract state configuration
    # example:
    # get_state_config([["s112", "s11", "s1", "root"],[...]], "s1") == ["s112", "s11"]ù
    case Enum.find(configuration, [], &Enum.member?(&1, state_name)) do
      [] ->
        []

      conf ->
        Enum.slice(conf, 0, Enum.find_index(conf, &(&1 == state_name)))
    end
  end

  defp put_in_history(machine, name, conf) do
    machine
    |> Map.replace!(:states_histories, Map.put(machine.states_histories, name, conf))
  end

  defp process_final_state(machine) do
    # if current state is a final state, must raise "done.state.id" event
    # where id = parent state
    # TODO: orthogonal
    state = machine.statechart.states[hd(get_active_states(machine))]

    case state.type do
      :final ->
        done_event = "done.state." <> state.parent
        context = Context.raise_event(machine.context, done_event)
        Map.replace!(machine, :context, context)

      _ ->
        machine
    end
  end

  defp do_actions(actions, context) do
    # apply all actions to context, in actions exact order
    Enum.reduce(actions, context, fn action, ctx -> action.(ctx) end)
  end

  defp extract_raised_events(machine) do
    # extract raise event from context and put it into machine queue
    machine
    |> Map.replace!(:queue, Map.get(machine.context, :exm_queue, []))
    |> Map.replace!(:context, Map.delete(machine.context, :exm_queue))
  end

  defp add_params_to_context(machine, params) do
    context_with_params = ExMachine.Context.put_params(machine.context, params)

    Map.replace!(machine, :context, context_with_params)
  end

  defp remove_params_from_context(machine) do
    context_wo_params = ExMachine.Context.delete_params(machine.context)

    Map.replace!(machine, :context, context_wo_params)
  end

  defp add_microstep(macrostep, microstep) do
    transitions_list =
      if microstep.transition do
        [microstep.transition]
      else
        []
      end

    macrostep
    |> Map.replace!(:microsteps, macrostep.microsteps ++ [microstep])
    |> Map.replace!(:entered, macrostep.entered ++ microstep.entered)
    |> Map.replace!(:exited, macrostep.exited ++ microstep.exited)
    |> Map.replace!(:actions, macrostep.actions ++ microstep.actions)
    |> Map.replace!(:transitions, macrostep.transitions ++ transitions_list)
  end
end
