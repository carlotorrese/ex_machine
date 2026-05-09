defmodule ExMachine.Scxml.Conformance.HierEntryExit do
  @moduledoc false
  # SCXML §3.4: entry order is parent-first; exit order is child-first.
  use ExMachine.Statechart
  initial(:outer)

  state :outer do
    initial(:inner)
    state(:inner, do: on(:done, target: :next))
  end

  state(:next)
end

defmodule ExMachine.Scxml.Conformance.SiblingsLCCA do
  @moduledoc false
  # SCXML §3.13: external transition between siblings of the same compound
  # MUST NOT exit/re-enter the parent compound.
  use ExMachine.Statechart
  initial(:p)

  state :p do
    initial(:a)
    state(:a, do: on(:flip, target: :b))
    state(:b, do: on(:flip, target: :a))
  end
end

defmodule ExMachine.Scxml.Conformance.ExternalSelf do
  @moduledoc false
  # SCXML §3.13: external self-transition (target == source, default type)
  # exits and re-enters the source.
  use ExMachine.Statechart
  initial(:s)

  state :s do
    on(:bump, target: :s)
  end
end

defmodule ExMachine.Scxml.Conformance.InternalSelf do
  @moduledoc false
  # SCXML §3.13: internal transition where target is a descendant of the
  # compound source MUST NOT exit the source.
  use ExMachine.Statechart
  initial(:p)

  state :p do
    initial(:a)
    on(:to_b, target: :b, type: :internal)
    state(:a)
    state(:b)
  end
end

defmodule ExMachine.Scxml.Conformance.EventlessChain do
  @moduledoc false
  # SCXML §3.13: eventless transitions are eligible after every microstep
  # and chained until none is enabled (run-to-completion).
  use ExMachine.Statechart
  initial(:a)

  state(:a, do: on(nil, target: :b))
  state(:b, do: on(nil, target: :c))
  state(:c)
end

defmodule ExMachine.Scxml.Conformance.DoneEvent do
  @moduledoc false
  # SCXML §3.7: when a compound enters its <final>, done.state.<parent>
  # is raised.
  use ExMachine.Statechart
  initial(:work)

  state :work do
    initial(:run)
    state(:run, do: on(:end, target: :wf))
    final(:wf)
    on(:"done.state.work", target: :after)
  end

  state(:after)
end

defmodule ExMachine.Scxml.Conformance.ParallelDoneBubble do
  @moduledoc false
  # SCXML §3.4 / §3.7: a <parallel> is "done" when every region is done;
  # done.state.<parallel> is raised once.
  use ExMachine.Statechart, type: :parallel

  region :left do
    initial(:lstart)
    state(:lstart, do: on(:done_l, target: :lf))
    final(:lf)
  end

  region :right do
    initial(:rstart)
    state(:rstart, do: on(:done_r, target: :rf))
    final(:rf)
  end
end

defmodule ExMachine.Scxml.Conformance.ShallowHistory do
  @moduledoc false
  # SCXML §3.10: shallow history restores the direct child that was active
  # at the time of exit.
  use ExMachine.Statechart
  initial(:idle)

  state(:idle, do: on(:enter, target: :h))

  state :p do
    initial(:a)
    history(:h, type: :shallow)
    on(:leave, target: :idle)
    state(:a, do: on(:next, target: :b))
    state(:b)
  end
end

defmodule ExMachine.Scxml.Conformance do
  use ExUnit.Case, async: true

  alias ExMachine.Scxml.Conformance.{
    DoneEvent,
    EventlessChain,
    ExternalSelf,
    HierEntryExit,
    InternalSelf,
    ParallelDoneBubble,
    ShallowHistory,
    SiblingsLCCA
  }

  test "entry order is parent-first; exit order is child-first" do
    initialised = ExMachine.init(HierEntryExit)
    init_micro = hd(initialised.trace.microsteps)
    # init enters the root, then :outer, then :inner — parent-first.
    assert init_micro.entered == [:hier_entry_exit, :outer, :inner]

    machine = ExMachine.dispatch(initialised, :done)
    # leaving via :done exits :inner before :outer (deepest-first).
    assert machine.trace.exited == [:inner, :outer]
  end

  test "sibling transition does NOT exit the LCCA parent" do
    machine =
      SiblingsLCCA
      |> ExMachine.init()
      |> ExMachine.dispatch(:flip)

    refute :p in machine.trace.exited
    assert :a in machine.trace.exited
    assert :b in machine.trace.entered
    assert MapSet.member?(machine.configuration, :p)
  end

  test "external self-transition exits and re-enters the source" do
    machine =
      ExternalSelf
      |> ExMachine.init()
      |> ExMachine.dispatch(:bump)

    assert machine.trace.exited == [:s]
    assert machine.trace.entered == [:s]
  end

  test "internal transition to a descendant keeps the source active" do
    machine =
      InternalSelf
      |> ExMachine.init()
      |> ExMachine.dispatch(:to_b)

    refute :p in machine.trace.exited
    assert :a in machine.trace.exited
    assert :b in machine.trace.entered
    assert MapSet.member?(machine.configuration, :p)
  end

  test "eventless transitions chain to completion in a single dispatch" do
    machine = ExMachine.init(EventlessChain)
    # init macrostep entered :a then chained eventlessly :a → :b → :c.
    assert ExMachine.atomic_states(machine) == [:c]
  end

  test "done.state.<parent> is raised when a compound enters its :final" do
    machine =
      DoneEvent
      |> ExMachine.init()
      |> ExMachine.dispatch(:end)

    assert ExMachine.atomic_states(machine) == [:after]

    events = Enum.map(machine.trace.transitions, & &1.event)
    assert :"done.state.work" in events
  end

  test "parallel completion bubbles done.state.<parallel> and stops the machine" do
    machine = ExMachine.init(ParallelDoneBubble)
    assert machine.running?
    machine = ExMachine.dispatch(machine, :done_l)
    assert machine.running?
    machine = ExMachine.dispatch(machine, :done_r)
    refute machine.running?
  end

  test "shallow history restores the previously-active direct child" do
    machine =
      ShallowHistory
      |> ExMachine.init()
      |> ExMachine.dispatch(:enter)

    # First entry via history with no recorded snapshot → parent's :initial.
    assert ExMachine.atomic_states(machine) == [:a]

    machine =
      machine
      |> ExMachine.dispatch(:next)
      |> ExMachine.dispatch(:leave)
      |> ExMachine.dispatch(:enter)

    # After a round-trip through :b → leave, history must restore :b.
    assert ExMachine.atomic_states(machine) == [:b]
  end
end
