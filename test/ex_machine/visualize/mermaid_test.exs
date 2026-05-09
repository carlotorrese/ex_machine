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

defmodule ExMachine.Visualize.MermaidTest.ParallelRoot do
  @moduledoc false
  # Regression for bug_007: a parallel root must be wrapped in
  # `state Root { ... }` so the `--` separator sits inside a state
  # block, where Mermaid's stateDiagram-v2 grammar accepts it.

  use ExMachine.Statechart, type: :parallel

  region :left do
    initial(:la)
    state(:la)
  end

  region :right do
    initial(:ra)
    state(:ra)
  end
end

defmodule ExMachine.Visualize.MermaidTest.ActionOnly do
  @moduledoc false
  # Regression for bug_003: an action-only transition (target: nil)
  # must not be rendered as `Source --> [*]`, which Mermaid reads as
  # "transitions to the end pseudostate". Render as a self-loop.

  use ExMachine.Statechart

  initial(:running)

  state :running do
    on(:tick, action: &__MODULE__.bump/1, type: :internal)
  end

  def bump(s), do: s
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
  alias ExMachine.Visualize.MermaidTest.{ActionOnly, Flat, Nested, ParallelRoot, Workflow}

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

  describe "regression: bug_007 — parallel root wrapped in a state block" do
    test "a parallel root nests its regions inside `state Root { ... }`" do
      out = Visualize.to_mermaid(ParallelRoot)

      assert out =~ "[*] --> parallel_root"
      assert out =~ "state parallel_root {"
      assert out =~ "    state left {"
      assert out =~ "    state right {"
      # The -- separator must sit INSIDE the wrapper (level 2), not at
      # the top of the diagram (level 1).
      assert out =~ ~r/^    --$/m
      refute out =~ ~r/^  --$/m
    end
  end

  describe "regression: bug_003 — action-only transitions render as self-loops" do
    test "target: nil renders Source --> Source, not Source --> [*]" do
      out = Visualize.to_mermaid(ActionOnly)

      # The transition is internal action-only on :running.
      assert out =~ "running --> running: tick /action (internal)"
      refute out =~ "running --> [*]"
    end
  end
end
