# ExMachine

[![Hex Version](https://img.shields.io/hexpm/v/ex_machine.svg)](https://hex.pm/packages/ex_machine)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/ex_machine/)
[![CI](https://github.com/carlotorrese/ex_machine/workflows/CI/badge.svg)](https://github.com/carlotorrese/ex_machine/actions)
[![License](https://img.shields.io/hexpm/l/ex_machine.svg)](https://github.com/carlotorrese/ex_machine/blob/main/LICENSE)
[![Development Status](https://img.shields.io/badge/status-alpha-orange.svg)](https://github.com/carlotorrese/ex_machine)

> ⚠️ **Early Development Warning**: This project is in active development and the API may change. Use with caution in production environments.

An Elixir functional implementation of a finite state machine,
based on Statechart.

ExMachine is a purely functional implementation of a finite
state machine which definition is based on the Statechart formalism
proposed by David Harel in 1987 and subsequently adopted by
Unified Modelling Language as its standard for state machine definition.

It can be used as a simple library, using a function to dispatch an event to the machine,
receiving back the new machine, that include the new state and the modified context.
Alternatively, it can be wrapped in a GenServer to run in a separate process
as a real and fully independent machine, influenced by events sended to it.

State machine are defined as static structures inside Elixir modules and
can be validated and loaded at compile time for better efficiency.
Moreover State definitions are composable, allowing realization of
independent components, based on statechart.

## Statechart basics

The primary feature of statecharts is that
states can be organized in a hierarchy:  
a statechart is a state machine where each state
in the state machine may define its own subordinate state machines,
called substates.
Those states can again define substates.

Main supported statechart feature supported by ExMachine are:

- [x] Entry and exit actions
- [x] Transition actions
- [x] Guard functions
- [x] Extended state (context)
- [x] Internal events (run to completion)
- [x] Final pseudostates
- [ ] History pseudostate
- [ ] Choice pseudostates ()
- [ ] Internal/external transitions ()

Future implementation:

- [ ] Orthogonal regions i.e. parallel state

Not supported:

- [ ] Do actions

### Finite State Machine

[Statechart](https://en.wikipedia.org/wiki/Statechart),
or [Hierarchical State Machine](https://en.wikipedia.org/wiki/UML_state_machine),
is a formalism to define a particular type of state machine called
[Finite State Machine (FSM)](https://en.wikipedia.org/wiki/Finite-state_machine).
A FSM is an abstract machine that can be in exactly one of a finite number
of states at any given time.
FSM can change from one state to another in response to some external inputs,
this changes are called transitions.
An FSM is defined by the complete list of its states, its initial state,
and the conditions for each transition.

### State machine definition and execution

- A way to _*define*_ the machine, listing the complete set of possible
  states and transitions
- A way to _*execute*_ the machine, starting it from a specific definition and
  sending changes to it to observing the consequent evolution.

ExMachine supplies both this parts

### States

In statechart, a state can be either a _simple_ state (i.e., a normal state)
or a _composite_ state, parent of other substates (children).
When a statechart machine is in a simple state, it is also in it's parent state.
Moreover, in a statechart, two or more composite state can be active at the
same time (orthogonal regions), modelling the situation in which the machine
is made up of different independent parts, each one interacting with each other.

For statechart machine we can't say that the machine is in a state,
but that it is in a particular _configuration_: a set of one or more
hierarchy of states, each one from a simple state up to the root state,
following the parent's tree.
All of the states in a configuration are actives at the same time.

### Context

Statechart is defined not only by the states but also by a so-called
_extended state_:
a kind of data structure that models the world (the `context`) in which
the machine lives and that influences and is influenced by the
machine during it's evolution (transitions).
So the configuration of a machine at a given time must contain not only
all active states but also the context of the machine in that time.
The context is the main data structure manipulated by the code executed in
the actions by a state machine and the output to the world.

### Transitions

A transition is a binary relation between two states of any type, that
specifies at which conditions the machine can move to a new configuration.
Transitions defines how the machine react to a stimulus from the outside world
(an event) and how it changes the machine itself.

### Events

Events are the way in which changes are submitted to the machine and in
which this evolves from a state (configuration) to another one.

An event can induce a change in the state machine if in the statechart
definition exist a transition that declares this event as a trigger.

An event can also carry some information, called event parameters,
that can be used by the machine to decide if the transition must be taken or
if it must modify the context after the transition is performed.

### Guards

The transitions of a machine are influenced either by the event and
its parameter, that by the current context.
These influences are made by particular functions, linked to transitions
definitions, called _guard_.
These functions are called when transition is fired by an event,
and perform a check against event parameters and the context, allowing or
negating the transition execution.
Guard functions never modified directly the context,
they return only if the transition must be taken.

### Actions

Statechart defines special functions, called _actions_, that can be performed
each time a transition happens, changing the configuration.
This actions are the only way a machine can change its context and they
can also send other events to the machine (internal events),
thus influencing the final configuration that the machine will take.

## Installation

The package can be installed by adding `ex_machine` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_machine, "~> 0.1.2"}
  ]
end
```

## Usage

ExMachine provides two main ways to use state machines:

1. **Functional approach**: Direct function calls
2. **Process-based approach**: Using GenServer integration

### Basic Example: Simple Traffic Light

```elixir
defmodule TrafficLight do
  use ExMachine.Statechart

  alias ExMachine.{State, Transition}

  def definition do
    %State{
      initial: "red",
      substates: %{
        "red" => %State{
          entry: fn context ->
            IO.puts("🔴 Red light - STOP")
            context
          end,
          transitions: %{
            "timer" => "green"
          }
        },
        "green" => %State{
          entry: fn context ->
            IO.puts("🟢 Green light - GO")
            context
          end,
          transitions: %{
            "timer" => "yellow"
          }
        },
        "yellow" => %State{
          entry: fn context ->
            IO.puts("🟡 Yellow light - CAUTION")
            context
          end,
          transitions: %{
            "timer" => "red"
          }
        }
      }
    }
  end
end

# Usage
alias ExMachine.{Machine, Statechart}

# Create and initialize the machine
statechart = Statechart.build(TrafficLight.definition())
machine = Machine.init(statechart, %{})

# Send events to transition between states
machine = Machine.dispatch(machine, "timer")  # red -> green
machine = Machine.dispatch(machine, "timer")  # green -> yellow
machine = Machine.dispatch(machine, "timer")  # yellow -> red
```

### Advanced Example: User Authentication Flow

```elixir
defmodule UserAuth do
  use ExMachine.Statechart

  alias ExMachine.{State, Transition, Final}

  def definition do
    %State{
      initial: "logged_out",
      substates: %{
        "logged_out" => %State{
          transitions: %{
            "login_attempt" => "checking_credentials"
          }
        },
        "checking_credentials" => %State{
          transitions: %{
            "success" => %Transition{
              target: "logged_in",
              action: &log_successful_login/1
            },
            "failure" => %Transition{
              target: "login_failed",
              action: &increment_attempts/1
            }
          }
        },
        "login_failed" => %State{
          transitions: %{
            "retry" => %Transition{
              target: "logged_out",
              guard: &can_retry?/1
            },
            "retry" => "locked"  # If guard fails
          }
        },
        "locked" => %State{
          entry: &set_lock_time/1
        },
        "logged_in" => %State{
          entry: &clear_attempts/1,
          transitions: %{
            "logout" => "logged_out",
            "session_timeout" => "logged_out"
          }
        }
      }
    }
  end

  # Action functions
  defp log_successful_login(context) do
    context
    |> Map.put(:last_login, DateTime.utc_now())
    |> Map.put(:attempts, 0)
  end

  defp increment_attempts(context) do
    Map.update(context, :attempts, 1, &(&1 + 1))
  end

  defp clear_attempts(context) do
    Map.put(context, :attempts, 0)
  end

  defp set_lock_time(context) do
    Map.put(context, :locked_at, DateTime.utc_now())
  end

  # Guard functions
  defp can_retry?(context) do
    Map.get(context, :attempts, 0) < 3
  end
end

# Usage example
statechart = Statechart.build(UserAuth.definition())
machine = Machine.init(statechart, %{attempts: 0})

# Simulate authentication flow
machine = Machine.dispatch(machine, "login_attempt")
machine = Machine.dispatch(machine, "failure")      # First failure
machine = Machine.dispatch(machine, "retry")
machine = Machine.dispatch(machine, "login_attempt")
machine = Machine.dispatch(machine, "success")      # Success!

IO.inspect(machine.configuration)  # [["logged_in", "root"]]
IO.inspect(machine.context)        # %{attempts: 0, last_login: ~U[...]}
```

### Hierarchical States Example: Media Player

```elixir
defmodule MediaPlayer do
  use ExMachine.Statechart

  alias ExMachine.{State, Transition, Final}

  def definition do
    %State{
      initial: "stopped",
      substates: %{
        "stopped" => %State{
          transitions: %{
            "play" => "playing"
          }
        },
        "playing" => %State{
          initial: "normal_speed",
          entry: &start_playback/1,
          exit: &pause_playback/1,
          substates: %{
            "normal_speed" => %State{
              transitions: %{
                "fast_forward" => "fast_forwarding",
                "rewind" => "rewinding"
              }
            },
            "fast_forwarding" => %State{
              entry: &set_speed_2x/1,
              transitions: %{
                "normal" => "normal_speed"
              }
            },
            "rewinding" => %State{
              entry: &set_speed_reverse/1,
              transitions: %{
                "normal" => "normal_speed"
              }
            }
          },
          transitions: %{
            "pause" => "paused",
            "stop" => "stopped"
          }
        },
        "paused" => %State{
          transitions: %{
            "play" => "playing",
            "stop" => "stopped"
          }
        }
      }
    }
  end

  # Action functions
  defp start_playback(context), do: Map.put(context, :status, :playing)
  defp pause_playback(context), do: Map.put(context, :status, :paused)
  defp set_speed_2x(context), do: Map.put(context, :speed, 2.0)
  defp set_speed_reverse(context), do: Map.put(context, :speed, -1.0)
end
```

### Using with GenServer

For long-running state machines, you can wrap them in a GenServer:

```elixir
defmodule PlayerServer do
  use GenServer
  alias ExMachine.{Machine, Statechart}

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def play, do: GenServer.cast(__MODULE__, {:event, "play"})
  def pause, do: GenServer.cast(__MODULE__, {:event, "pause"})
  def stop, do: GenServer.cast(__MODULE__, {:event, "stop"})

  def get_state, do: GenServer.call(__MODULE__, :get_state)

  @impl true
  def init(_opts) do
    statechart = Statechart.build(MediaPlayer.definition())
    machine = Machine.init(statechart, %{})
    {:ok, machine}
  end

  @impl true
  def handle_cast({:event, event}, machine) do
    new_machine = Machine.dispatch(machine, event)
    {:noreply, new_machine}
  end

  @impl true
  def handle_call(:get_state, _from, machine) do
    {:reply, machine.configuration, machine}
  end
end

# Usage
{:ok, _pid} = PlayerServer.start_link()
PlayerServer.play()
PlayerServer.get_state()  # [["normal_speed", "playing", "root"]]
```

### Key Concepts

- **States**: Define the possible states your machine can be in
- **Transitions**: Define how to move between states based on events
- **Actions**: Functions that modify the context during transitions
- **Guards**: Functions that conditionally allow or prevent transitions
- **Context**: The extended state that travels with your machine
- **Events**: Messages that trigger state transitions

For more examples, check the `lib/samples/` directory in the repository.

## Curiosity

The first machine was officially turned on at 21:26:41 on 2018-10-11, italian time.
Here is the `iex` session:

```elixir
Erlang/OTP 20 [erts-9.2] [source] [64-bit] [smp:2:2] [ds:2:2:10] [async-threads:10] [hipe] [kernel-poll:false] [dtrace]

Interactive Elixir (1.7.2) - press Ctrl+C to exit (type h() ENTER for help)
iex(1)> m = Machine.init(S0.statechart, %{foo: 0})
%ExMachine.Machine{
  configuration: [["s11", "s1", "root"]],
  context: %{bar: :baz, foo: 1},
  statechart: %ExMachine.Statechart{...},
  macrosteps: [
    %ExMachine.Macrostep{
      actions: [&S1.set_foo_one/1, &S1.add_bar_baz/1],
      entered: ["root", "s1", "s11"],
      event: nil,
      exited: [],
      microsteps: %ExMachine.Microstep{
        actions: [&S1.set_foo_one/1, &S1.add_bar_baz/1],
        entered: ["root", "s1", "s11"],
        event: nil,
        exited: [],
        transition: nil
      },
      timestamp: ~N[2018-10-11 21:26:41.726698],
      transitions: []
    }
  ],
  queue: [],
  running?: true
}
iex(2)>

```

## Development Status & Roadmap

ExMachine is currently in **alpha stage**. While the core functionality is working and tested, the API may undergo changes as we gather feedback from the community.

### Current State

- ✅ Core state machine functionality implemented
- ✅ Statechart formalism support (hierarchical states, transitions, guards)
- ✅ GenServer integration for process-based state machines
- ✅ Comprehensive test suite (30+ tests)
- ✅ Documentation and examples

### Roadmap

- [ ] API stabilization based on community feedback
- [ ] Performance optimizations
- [ ] Additional guard and action features
- [ ] More comprehensive examples and tutorials
- [ ] Integration with other Elixir/OTP patterns

### Contributing

We welcome contributions! Please see our [contribution guidelines](CONTRIBUTING.md) and feel free to open issues or pull requests.

## Inspiration

- [Statecharts: a visual formalism for complex systems (David Harel)](https://ac.els-cdn.com/0167642387900359/1-s2.0-0167642387900359-main.pdf?_tid=a9d41960-080a-49d4-b051-5ed409afb933&acdnat=1538686934_8d122d2d37b601ed2f3c06a462a03fa5)
- [SCXML](https://www.w3.org/TR/scxml/)
- [StateX: a state management library for modern web applications](https://github.com/rintoj/statex)
- [The World of Statechart](https://statecharts.github.io/)
- [SISMIC Interactive Statechart Model Interpreter and Checker](https://github.com/AlexandreDecan/sismic)
- [UML State Machine](https://www.omg.org/spec/UML/About-UML/)
