defmodule ExMachine.Visualize.ScxmlTest.Flat do
  @moduledoc false
  use ExMachine.Statechart
  initial(:red)
  state(:red, do: on(:timer, target: :green))
  state(:green, do: on(:timer, target: :yellow))
  state(:yellow, do: on(:timer, target: :red))
end

defmodule ExMachine.Visualize.ScxmlTest.Nested do
  @moduledoc false
  use ExMachine.Statechart
  initial(:running)

  state :running do
    initial(:slow)
    on(:halt, target: :off)
    state(:slow, do: on(:go_fast, target: :fast))
    state(:fast, do: on(:go_slow, target: :slow))
  end

  final(:off)
end

defmodule ExMachine.Visualize.ScxmlTest.Workflow do
  @moduledoc false
  use ExMachine.Statechart
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
end

defmodule ExMachine.Visualize.ScxmlTest.ParallelRoot do
  @moduledoc false
  # Regression for bug_003: when the root is :parallel, the XML body
  # must be wrapped in <parallel id=...> and the <scxml> element must
  # carry initial=<root>, otherwise a conformant interpreter treats
  # the regions as a compound and activates only the first.

  use ExMachine.Statechart, type: :parallel

  region :left do
    initial(:l1)
    state(:l1)
  end

  region :right do
    initial(:r1)
    state(:r1)
  end
end

defmodule ExMachine.Visualize.ScxmlTest.HistoryNoDefault do
  @moduledoc false
  # Regression for bug_002: <history> emits MUST contain a child
  # <transition target="..."/> per W3C SCXML XSD. When :default is
  # omitted, the renderer must fall back to parent.initial.

  use ExMachine.Statechart
  initial(:idle)

  state(:idle, do: on(:resume, target: :h))

  state :playing do
    initial(:slow)
    history(:h, type: :shallow)
    state(:slow)
    state(:fast)
  end
end

defmodule ExMachine.Visualize.ScxmlTest.AmpEvent do
  @moduledoc false
  # Regression for bug_004: an event atom containing an XML
  # metacharacter (&, <, >, ") must be escaped in the
  # `event="..."` attribute.

  use ExMachine.Statechart
  initial(:a)
  state(:a, do: on(:"a&b", target: :z))
  state(:z)
end

defmodule ExMachine.Visualize.ScxmlTest.WithHistory do
  @moduledoc false
  use ExMachine.Statechart
  initial(:idle)

  state :idle do
    on(:resume, target: :h)
  end

  state :playing do
    initial(:slow)
    history(:h, type: :deep, default: :fast)
    state(:slow)
    state(:fast)
  end
end

defmodule ExMachine.Visualize.ScxmlTest do
  use ExUnit.Case, async: true

  alias ExMachine.Visualize

  alias ExMachine.Visualize.ScxmlTest.{
    AmpEvent,
    Flat,
    HistoryNoDefault,
    Nested,
    ParallelRoot,
    WithHistory,
    Workflow
  }

  test "flat FSM emits a top-level <scxml initial=...> with one <state> per node" do
    out = Visualize.to_scxml(Flat)

    assert out =~ ~s(<?xml version="1.0" encoding="UTF-8"?>)
    assert out =~ ~s(<scxml xmlns="http://www.w3.org/2005/07/scxml" version="1.0" initial="red")
    assert out =~ ~s(<state id="red">)
    assert out =~ ~s(<transition event="timer" target="green"/>)
    assert out =~ "</scxml>"
  end

  test "compound state declares initial; nested state and final render" do
    out = Visualize.to_scxml(Nested)
    assert out =~ ~s(<state id="running" initial="slow">)
    assert out =~ ~s(<state id="slow">)
    assert out =~ ~s(<final id="off"/>)
    assert out =~ ~s(<transition event="halt" target="off"/>)
  end

  test "parallel uses <parallel> with one <state> per region (no <region> tag)" do
    out = Visualize.to_scxml(Workflow)
    assert out =~ ~s(<parallel id="work">)
    assert out =~ ~s(<state id="left" initial="la">)
    assert out =~ ~s(<state id="right" initial="ra">)
    refute out =~ "<region"
    assert out =~ ~s(<final id="lf"/>)
  end

  test "history renders with type and default-target child <transition>" do
    out = Visualize.to_scxml(WithHistory)
    assert out =~ ~s(<history id="h" type="deep">)
    assert out =~ ~s(<transition target="fast"/>)
    assert out =~ "</history>"
  end

  describe "regression: bug_002 — history emits a default <transition>" do
    test "history without :default falls back to the parent's :initial" do
      out = Visualize.to_scxml(HistoryNoDefault)
      # The history sits inside :playing whose :initial is :slow.
      assert out =~ ~s(<history id="h" type="shallow">)
      assert out =~ ~s(<transition target="slow"/>)
      assert out =~ "</history>"
      # The previous (broken) output emitted an empty <history></history>.
      refute out =~ ~r/<history[^>]*>\s*<\/history>/
    end
  end

  describe "regression: bug_004 — event attribute is XML-escaped" do
    test "an event with `&` in its name is escaped as &amp;" do
      out = Visualize.to_scxml(AmpEvent)
      assert out =~ ~s(event="a&amp;b")
      refute out =~ ~s(event="a&b")
    end
  end

  describe "regression: bug_003 — parallel root wrapper" do
    test "parallel root wraps regions in <parallel> and sets initial= on <scxml>" do
      out = Visualize.to_scxml(ParallelRoot)

      assert out =~
               ~s(<scxml xmlns="http://www.w3.org/2005/07/scxml" version="1.0" initial="parallel_root")

      assert out =~ ~s(<parallel id="parallel_root">)
      assert out =~ "</parallel>"
      assert out =~ ~s(<state id="left" initial="l1">)
      assert out =~ ~s(<state id="right" initial="r1">)
    end
  end
end
