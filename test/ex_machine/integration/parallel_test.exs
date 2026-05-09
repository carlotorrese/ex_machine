defmodule ExMachine.Integration.ParallelTest.Workflow do
  @moduledoc false
  # A compound root with a nested parallel under :running. When BOTH
  # regions reach their finals, done.state.work bubbles up and the
  # parent transitions to :completed.

  use ExMachine.Statechart

  initial(:running)

  state :running do
    initial(:work)

    parallel :work do
      on(:abort, target: :aborted)

      region :a do
        initial(:a1)

        state :a1 do
          on(:finish_a, target: :a_done)
        end

        final(:a_done)
      end

      region :b do
        initial(:b1)

        state :b1 do
          on(:finish_b, target: :b_done)
        end

        final(:b_done)
      end
    end

    on(:"done.state.work", target: :completed)
  end

  state(:completed)
  state(:aborted)
end

defmodule ExMachine.Integration.ParallelTest.TopParallel do
  @moduledoc false
  # Parallel root. When both regions reach final the machine stops.

  use ExMachine.Statechart, type: :parallel

  region :left do
    initial(:lstart)

    state(:lstart, do: on(:done_l, target: :lfinal))
    final(:lfinal)
  end

  region :right do
    initial(:rstart)

    state(:rstart, do: on(:done_r, target: :rfinal))
    final(:rfinal)
  end
end

defmodule ExMachine.Integration.ParallelTest.SharedFinish do
  @moduledoc false
  # Regression for bug_001: when both regions reach their final in the
  # SAME microstep (shared event), done.state.<parallel> must be raised
  # exactly once, not once per region final.

  use ExMachine.Statechart, type: :parallel

  region :a do
    initial(:a1)
    state(:a1, do: on(:end, target: :a_done))
    final(:a_done)
  end

  region :b do
    initial(:b1)
    state(:b1, do: on(:end, target: :b_done))
    final(:b_done)
  end
end

defmodule ExMachine.Integration.ParallelTest.HalfEnter do
  @moduledoc false
  # Regression for bug_004: a transition into one region of a non-root
  # parallel must populate every sibling region (SCXML
  # addAncestorStatesToEnter), not leave the parallel half-entered.

  use ExMachine.Statechart

  initial(:outside)

  state(:outside, do: on(:enter, target: :l1))

  parallel :work do
    region :left do
      initial(:l1)
      state(:l1)
    end

    region :right do
      initial(:r1)
      state(:r1)
    end
  end
end

defmodule ExMachine.Integration.ParallelTest.CrossRegion do
  @moduledoc false
  # Regression for the third-pass bug_001: a transition whose source is
  # in one region and target is in another region of the same parallel
  # must NOT pick the parallel as the LCCA — that strands the source's
  # original region. SCXML §3.13 requires a non-parallel LCCA when one
  # exists; this test exercises a non-root parallel (LCCA must be the
  # outer compound).

  use ExMachine.Statechart

  initial(:work)

  state :work do
    initial(:p)

    parallel :p do
      region :left do
        initial(:l1)
        state(:l1, do: on(:cross, target: :r2))
        state(:l1b)
      end

      region :right do
        initial(:r1)
        state(:r1)
        state(:r2)
      end
    end
  end
end

defmodule ExMachine.Integration.ParallelTest.CrossRegionInRoot do
  @moduledoc false
  # Same defect, but with a parallel ROOT — there is no non-parallel
  # ancestor, so the LCCA must fall back to the parallel itself and
  # `compute_entry_chain` must still re-populate every region.

  use ExMachine.Statechart, type: :parallel

  region :left do
    initial(:l1)
    state(:l1, do: on(:cross, target: :r2))
    state(:l1b)
  end

  region :right do
    initial(:r1)
    state(:r1)
    state(:r2)
  end
end

defmodule ExMachine.Integration.ParallelTest.Conflict do
  @moduledoc false
  # Both regions react to :abort. Each transition's exit set includes
  # :inside (the parallel) and all its descendants, so the two are in
  # conflict. The first one in atomic-state order (left.l1) wins; the
  # second is removed by remove_conflicting/2.

  use ExMachine.Statechart

  initial(:inside)

  state :inside do
    initial(:work)

    parallel :work do
      region :left do
        initial(:l1)
        state(:l1, do: on(:abort, target: :outside))
      end

      region :right do
        initial(:r1)
        state(:r1, do: on(:abort, target: :outside))
      end
    end
  end

  state(:outside)
end

defmodule ExMachine.Integration.ParallelTest do
  use ExUnit.Case, async: true

  alias ExMachine.Integration.ParallelTest.{
    Conflict,
    CrossRegion,
    CrossRegionInRoot,
    HalfEnter,
    SharedFinish,
    TopParallel,
    Workflow
  }

  describe "done events under parallel" do
    test "done.state.<region> is raised when a region reaches final" do
      machine =
        Workflow
        |> ExMachine.init()
        |> ExMachine.dispatch(:finish_a)

      # :a region is done; :b is not, so the parallel is not yet done.
      assert :a_done in machine.configuration
      assert :b1 in machine.configuration
    end

    test "done.state.<parallel> bubbles when ALL regions complete" do
      machine =
        Workflow
        |> ExMachine.init()
        |> ExMachine.dispatch(:finish_a)
        |> ExMachine.dispatch(:finish_b)

      # The parent compound observes done.state.work and moves to :completed.
      assert ExMachine.atomic_states(machine) == [:completed]

      events = Enum.map(machine.trace.transitions, & &1.event)
      assert :"done.state.work" in events
    end
  end

  describe "top-level parallel completion" do
    test "machine stops when all regions of a parallel root complete" do
      machine = ExMachine.init(TopParallel)
      assert machine.running?

      machine = ExMachine.dispatch(machine, :done_l)
      assert machine.running?

      machine = ExMachine.dispatch(machine, :done_r)
      refute machine.running?

      assert_raise ExMachine.Machine.NotRunning, fn ->
        ExMachine.dispatch(machine, :done_l)
      end
    end
  end

  describe "cross-region transitions and conflict" do
    test "two transitions on the same event in different regions: deeper or earlier wins" do
      machine =
        Conflict
        |> ExMachine.init()
        |> ExMachine.dispatch(:abort)

      assert ExMachine.atomic_states(machine) == [:outside]

      # Only ONE transition was applied — the second was removed as conflicting.
      assert length(machine.trace.transitions) == 1
    end

    test "cross-region transition exits the entire parallel cleanly" do
      # :abort declared on :work (the parallel itself) takes priority over
      # the per-region transitions when fired from any active atomic.
      machine =
        Workflow
        |> ExMachine.init()
        |> ExMachine.dispatch(:abort)

      assert ExMachine.atomic_states(machine) == [:aborted]
      # Both regions and the parallel were exited.
      assert :a1 in machine.trace.exited
      assert :b1 in machine.trace.exited
      assert :work in machine.trace.exited
    end
  end

  describe "regression: bug_001 — done bubble dedup" do
    test "done.state.<parallel> raised exactly once when regions finalize together" do
      machine = SharedFinish |> ExMachine.init() |> ExMachine.dispatch(:end)

      # Top-level parallel completed, machine stopped, the bubbled
      # done.state.<root> sits in machine.queue (run_to_completion is a
      # no-op once running? becomes false).
      refute machine.running?

      done_count = Enum.count(machine.queue, &(&1 == :"done.state.shared_finish"))
      assert done_count == 1, "expected one done.state.<root>, got #{done_count}"
    end
  end

  describe "regression: bug_001 (3rd pass) — cross-region transition LCCA" do
    test "non-root parallel: LCCA must NOT be the parallel itself" do
      machine = CrossRegion |> ExMachine.init() |> ExMachine.dispatch(:cross)

      # Both regions must remain populated; only :l1 → :r2 should move.
      assert MapSet.member?(machine.configuration, :l1) or
               MapSet.member?(machine.configuration, :l1b),
             "left region was stranded"

      assert MapSet.member?(machine.configuration, :r2)
      assert MapSet.member?(machine.configuration, :left)
      assert MapSet.member?(machine.configuration, :right)
      assert MapSet.member?(machine.configuration, :p)

      # atomic_states should report two atomics, not one.
      assert length(ExMachine.atomic_states(machine)) == 2
    end

    test "parallel root: LCCA falls back to the parallel and still re-enters siblings" do
      machine = CrossRegionInRoot |> ExMachine.init() |> ExMachine.dispatch(:cross)

      assert MapSet.member?(machine.configuration, :left)
      assert MapSet.member?(machine.configuration, :right)
      assert MapSet.member?(machine.configuration, :r2)
      # Sibling region must have its initial restored, not be stranded.
      assert MapSet.member?(machine.configuration, :l1) or
               MapSet.member?(machine.configuration, :l1b)

      assert length(ExMachine.atomic_states(machine)) == 2
    end
  end

  describe "regression: bug_004 — parallel half-entry" do
    test "transition into one region of a non-root parallel populates every sibling region" do
      machine = HalfEnter |> ExMachine.init() |> ExMachine.dispatch(:enter)

      assert MapSet.member?(machine.configuration, :work)
      assert MapSet.member?(machine.configuration, :left)
      assert MapSet.member?(machine.configuration, :right)
      assert MapSet.member?(machine.configuration, :l1)
      assert MapSet.member?(machine.configuration, :r1)

      # And atomic_states reflects both regions, not just the on-path one.
      assert ExMachine.atomic_states(machine) == [:l1, :r1]
    end
  end

  describe "independent progress" do
    test "regions advance independently with their own events" do
      machine =
        Workflow
        |> ExMachine.init()

      assert :a1 in machine.configuration
      assert :b1 in machine.configuration

      machine = ExMachine.dispatch(machine, :finish_a)
      assert :a_done in machine.configuration
      assert :b1 in machine.configuration

      machine = ExMachine.dispatch(machine, :finish_b)
      # Both finals reached → :work is done → parent transitions to :completed.
      assert ExMachine.atomic_states(machine) == [:completed]
    end
  end
end
