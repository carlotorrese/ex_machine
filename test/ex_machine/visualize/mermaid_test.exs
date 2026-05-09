defmodule ExMachine.Visualize.MermaidTest.Flat do
  @moduledoc false
  use ExMachine.Statechart
  initial(:red)
  state(:red, do: on(:timer, target: :green))
  state(:green, do: on(:timer, target: :yellow))
  state(:yellow, do: on(:timer, target: :red))
end

defmodule ExMachine.Visualize.MermaidTest.Nested do
  @moduledoc false
  use ExMachine.Statechart
  initial(:stopped)

  state :stopped do
    on(:play, target: :playing)
  end

  state :playing do
    initial(:slow)
    on(:pause, target: :paused)

    state(:slow, do: on(:go_fast, target: :fast))
    state(:fast, do: on(:go_slow, target: :slow))
  end

  state :paused do
    on(:play, target: :playing)
  end
end

defmodule ExMachine.Visualize.MermaidTest.Workflow do
  @moduledoc false
  use ExMachine.Statechart
  initial(:running)

  state :running do
    initial(:work)

    parallel :work do
      region :left do
        initial(:la)
        state(:la, do: on(:done_l, target: :lf))
        final(:lf)
      end

      region :right do
        initial(:ra)
        state(:ra, do: on(:done_r, target: :rf))
        final(:rf)
      end
    end

    on(:"done.state.work", target: :completed)
  end

  state(:completed)
end

defmodule ExMachine.Visualize.MermaidTest do
  use ExUnit.Case, async: true

  alias ExMachine.Visualize
  alias ExMachine.Visualize.MermaidTest.{Flat, Nested, Workflow}

  test "flat FSM renders one initial arrow plus one line per transition" do
    out = Visualize.to_mermaid(Flat)

    assert out == """
           stateDiagram-v2
             [*] --> red
             red --> green: timer
             green --> yellow: timer
             yellow --> red: timer\
           """
  end

  test "compound substate renders as a nested `state Name { ... }` block" do
    out = Visualize.to_mermaid(Nested)

    assert out =~ "[*] --> stopped"
    assert out =~ "state playing {"
    assert out =~ "    [*] --> slow"
    assert out =~ "    slow --> fast: go_fast"
    assert out =~ "    fast --> slow: go_slow"
    # The compound's outgoing transition is at the PARENT level, not inside.
    assert out =~ ~r/^  playing --> paused: pause$/m
    assert out =~ "stopped --> playing: play"
    assert out =~ "paused --> playing: play"
  end

  test "parallel renders region blocks separated by --" do
    out = Visualize.to_mermaid(Workflow)

    assert out =~ "state work {"
    assert out =~ "state left {"
    assert out =~ "state right {"
    assert out =~ ~r/^      --$/m
    # final targets become [*]
    assert out =~ "la --> [*]: done_l"
    assert out =~ "ra --> [*]: done_r"
  end
end
