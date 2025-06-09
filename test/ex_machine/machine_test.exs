defmodule MachineTest do
  use ExUnit.Case, async: true

  alias ExMachine.{State, Final, History, Transition, Machine, Statechart, Context}

  test "turn on the machine" do
    definition = %State{
      initial: "s1",
      substates: %{
        "s1" => %State{},
        "s2" => %State{}
      }
    }

    statechart = Statechart.build(definition)
    machine = Machine.init(statechart, %{})

    assert machine.running?
    assert machine.configuration == [["s1", "root"]]
    assert length(machine.macrosteps) == 1
    assert machine.context == %{}
  end

  test "initial configuration" do
    definition = %State{
      initial: "s1",
      substates: %{
        "s1" => %State{entry: &Map.put(&1, :foo, "bar")},
        "s2" => %State{}
      }
    }

    statechart = Statechart.build(definition)
    machine = Machine.init(statechart, %{})

    assert machine.configuration == [["s1", "root"]]
    assert length(machine.macrosteps) == 1
    assert machine.context == %{foo: "bar"}
  end

  test "initial configuration with entry that raise an internal event" do
    definition = %State{
      initial: "s1",
      substates: %{
        "s1" => %State{entry: &Context.raise_event(&1, "evt"), transitions: %{"evt" => "s2"}},
        "s2" => %State{}
      }
    }

    statechart = Statechart.build(definition)
    machine = Machine.init(statechart, %{})

    assert machine.configuration == [["s2", "root"]]
    assert length(machine.macrosteps) == 1
  end

  test "change state" do
    definition = %State{
      initial: "s1",
      substates: %{
        "s1" => %State{
          entry: &Map.put(&1, :foo, 1),
          transitions: %{"e1" => "s2"}
        },
        "s2" => %State{
          entry: &Map.put(&1, :foo, 2),
          transitions: %{"e2" => "s1"}
        }
      }
    }

    statechart = Statechart.build(definition)
    machine = Machine.init(statechart, %{foo: 0})
    assert machine.configuration == [["s1", "root"]]
    assert machine.context == %{foo: 1}

    machine = Machine.dispatch(machine, "e1")
    assert machine.configuration == [["s2", "root"]]
    assert machine.context == %{foo: 2}

    machine = Machine.dispatch(machine, "e2")
    assert machine.configuration == [["s1", "root"]]
    assert machine.context == %{foo: 1}

    machine = Machine.dispatch(machine, "unknown")
    assert machine.configuration == [["s1", "root"]]
    assert machine.context == %{foo: 1}
  end

  test "run to completion when raising internal event" do
    definition = %State{
      initial: "s1",
      substates: %{
        "s1" => %State{
          entry: &Map.put(&1, :foo, 1),
          transitions: %{"e1" => "s2"}
        },
        "s2" => %State{
          entry: &Context.raise_event(&1, "e2"),
          transitions: %{"e2" => "s3"}
        },
        "s3" => %State{
          entry: &Context.raise_event(&1, "e3"),
          transitions: %{"e3" => "s4"}
        },
        "s4" => %State{
          entry: &Map.put(&1, :foo, 4)
        }
      }
    }

    statechart = Statechart.build(definition)
    machine = Machine.init(statechart, %{foo: 0})
    assert machine.configuration == [["s1", "root"]]
    assert machine.context == %{foo: 1}

    machine = Machine.dispatch(machine, "e1")
    assert machine.configuration == [["s4", "root"]]
    assert machine.context == %{foo: 4}
    assert length(Machine.last_microsteps(machine)) == 3
    assert Enum.map(Machine.last_transitions(machine), & &1.name) == ["e1", "e2", "e3"]
  end

  test "entry/exit/transition action" do
    definition = %State{
      initial: "s1",
      substates: %{
        "s1" => %State{
          entry: &Map.put(&1, :foo, 1),
          exit: &Map.put(&1, :bar, 1),
          transitions: %{"e1" => %Transition{target: "s2", action: &Map.put(&1, :baz, 1)}}
        },
        "s2" => %State{
          entry: &Map.put(&1, :foo, 2),
          exit: &Map.put(&1, :bar, 2),
          transitions: %{"e2" => %Transition{target: "s1", action: &Map.put(&1, :baz, 2)}}
        }
      }
    }

    statechart = Statechart.build(definition)
    machine = Machine.init(statechart, %{foo: 0, bar: 0, baz: 0})
    assert machine.context == %{foo: 1, bar: 0, baz: 0}

    machine = Machine.dispatch(machine, "e1")
    assert machine.configuration == [["s2", "root"]]
    assert machine.context == %{foo: 2, bar: 1, baz: 1}

    machine = Machine.dispatch(machine, "e2")
    assert machine.configuration == [["s1", "root"]]
    assert machine.context == %{foo: 1, bar: 2, baz: 2}

    machine = Machine.dispatch(machine, "unknown")
    assert machine.configuration == [["s1", "root"]]
    assert machine.context == %{foo: 1, bar: 2, baz: 2}
  end

  test "final state root" do
    definition = %State{
      initial: "s1",
      substates: %{
        "s1" => %State{
          entry: &Map.put(&1, :foo, 1),
          transitions: %{"e1" => "exit"}
        },
        "exit" => %Final{
          entry: &Map.put(&1, :bar, 2)
        }
      }
    }

    statechart = Statechart.build(definition)
    machine = Machine.init(statechart, %{foo: 0})
    assert machine.context == %{foo: 1}

    machine = Machine.dispatch(machine, "e1")
    assert machine.configuration == [["exit", "root"]]
    assert machine.context == %{foo: 1, bar: 2}
    refute machine.running?

    assert_raise(Machine.NotRunning, fn ->
      Machine.dispatch(machine, "e1")
    end)
  end

  test "final internal state" do
    definition = %State{
      initial: "s1",
      transitions: %{"done.state.s1" => "s2"},
      substates: %{
        "s1" => %State{
          initial: "s11",
          substates: %{
            "s11" => %State{
              entry: &Map.put(&1, :foo, 11),
              transitions: %{"e1" => "exit"}
            },
            "exit" => %Final{entry: &Map.put(&1, :bar, 0)}
          }
        },
        "s2" => %State{entry: &Map.put(&1, :foo, 2)}
      }
    }

    statechart = Statechart.build(definition)
    machine = Machine.init(statechart, %{foo: 11})
    assert machine.configuration == [["s11", "s1", "root"]]

    machine = Machine.dispatch(machine, "e1")
    assert machine.configuration == [["s2", "root"]]
    assert machine.context == %{foo: 2, bar: 0}
    assert machine.running?
  end

  test "deep history state" do
    definition = %State{
      initial: "s1",
      transitions: %{"done.state.s1" => "s2"},
      substates: %{
        "s1" => %State{
          initial: "s11",
          substates: %{
            "s11" => %State{
              initial: "s111",
              substates: %{"s111" => %State{}, "s112" => %State{}}
            },
            "s12" => %State{
              initial: "s121",
              substates: %{"s121" => %State{}, "s122" => %State{}}
            },
            "s1.deep" => %History{type: :deep},
            "s1.shallow" => %History{type: :shallow}
          },
          transitions: %{
            "e1" => "s122",
            "e2" => "s2"
          }
        },
        "s2" => %State{
          transitions: %{"d" => "s1.deep", "s" => "s1.shallow"}
        }
      }
    }

    statechart = Statechart.build(definition)
    machine = Machine.init(statechart, %{foo: 11})
    assert machine.configuration == [["s111", "s11", "s1", "root"]]
    assert machine.statechart.states["s1"].history?

    machine = Machine.dispatch(machine, "e1")
    assert machine.configuration == [["s122", "s12", "s1", "root"]]

    machine = Machine.dispatch(machine, "e2")
    assert machine.configuration == [["s2", "root"]]
    # machine = Machine.dispatch(machine, "d")
    # assert machine.configuration == [["s122", "s12", "s1", "root"]]

    # machine = Machine.dispatch(machine, "e2")
    # assert machine.configuration == [["s2", "root"]]
    # machine = Machine.dispatch(machine, "s")
    # assert machine.configuration == [["s121", "s12", "s1", "root"]]

  end
end
