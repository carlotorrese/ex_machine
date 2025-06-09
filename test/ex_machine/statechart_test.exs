defmodule StatechartTest do
  use ExUnit.Case, async: true

  alias ExMachine.{Statechart, State, Final}

  doctest Statechart

  def valid_definition() do
    %State{
      initial: "s1",
      substates: %{
        "s1" => %State{
          initial: "s11",
          entry: &StatechartTest.fun1/1,
          exit: &StatechartTest.fun3/1,
          substates: %{
            "s11" => %State{
              entry: &StatechartTest.fun2/1,
              exit: &StatechartTest.fun4/1
            },
            "s12" => %State{
              entry: &StatechartTest.fun5/1
            },
            "exit" => %Final{}
          },
          transitions: %{
            "tick" => "s2",
            "exit" => "exit",
            "rtc" => "s12",
            "tack" => "s3"
          }
        },
        "s2" => %State{
          transitions: %{"tock" => "s1"}
        },
        "s3" => %State{
          entry: &StatechartTest.fun6/1,
          transitions: %{
            "tuck" => "s2"
          }
        }
      }
    }
  end

  def fun1(ctx), do: ctx
  def fun2(ctx), do: ctx
  def fun3(ctx), do: ctx
  def fun4(ctx), do: ctx

  def fun5(ctx) do
    import ExMachine.Context

    ctx
    |> raise_event("tack")
  end

  def fun6(ctx) do
    import ExMachine.Context

    ctx
    |> put(:hello, "world")
    |> raise_event("tuck")
  end

  test "invalid definition" do
    assert_raise(Statechart.InvalidDefinition, fn ->
      Statechart.build(%{})
    end)
  end

  test "invalid empty definition" do
    assert_raise(Statechart.InvalidDefinition, fn ->
      Statechart.build(%State{})
    end)
  end

  test "not valid initial state" do
    definition = %State{
      substates: %{
        "s1" => %State{},
        "s2" => %State{}
      }
    }

    assert_raise(Statechart.NotValidInitial, fn ->
      Statechart.build(definition)
    end)
  end

  # @tag :skip
  # test "invalid duplicate states" do
  #   definition = %State{
  #     initial: "s1",
  #     substates: %{
  #       "s1" => %State{},
  #       "s2" => %State{
  #         initial: "s1",
  #         substates: %{"s1" => %State{}}
  #       }
  #     }
  #   }
  #
  #   assert_raise(Statechart.DuplicatedState, fn ->
  #     Statechart.build(definition)
  #   end)
  # end

  test "valid definition" do
    statechart = Statechart.build(valid_definition())
    assert Enum.count(statechart.states) == 7
    assert statechart.states["s12"].name == "s12"
  end

  test "get_descendants/2" do
    statechart = Statechart.build(valid_definition())
    assert MapSet.size(Statechart.get_descendants(statechart, "root")) == 6
    assert MapSet.size(Statechart.get_descendants(statechart, "s1")) == 3
    assert MapSet.size(Statechart.get_descendants(statechart, "s2")) == 0

    assert MapSet.equal?(
             Statechart.get_descendants(statechart, "root"),
             MapSet.new(["s11", "s12", "s2", "s1", "exit", "s3"])
           )
  end

  test "get_ancestors/2" do
    statechart = Statechart.build(valid_definition())
    assert Statechart.get_ancestors(statechart, "s12") == ["s1", "root"]
    assert statechart.states["s12"].name == "s12"
  end

  test "get_initials/2" do
    statechart = Statechart.build(valid_definition())
    assert Statechart.get_initials(statechart, "root") == ["root", "s1", "s11"]
    assert Statechart.get_initials(statechart, "s11") == ["s11"]
  end

  test "get_entry_actions/2" do
    statechart = Statechart.build(valid_definition())

    assert Statechart.get_entry_actions(statechart, ["root", "s1", "s11"]) == [
             &StatechartTest.fun1/1,
             &StatechartTest.fun2/1
           ]

    assert Statechart.get_entry_actions(statechart, ["s11"]) == [&StatechartTest.fun2/1]
  end

  test "get_exit_actions/2" do
    statechart = Statechart.build(valid_definition())

    assert Statechart.get_exit_actions(statechart, ["s11", "s1", "root"]) == [
             &StatechartTest.fun4/1,
             &StatechartTest.fun3/1
           ]

    assert Statechart.get_exit_actions(statechart, ["s11"]) == [&StatechartTest.fun4/1]
  end

  test "get_transition_for/3" do
    statechart = Statechart.build(valid_definition())
    assert Statechart.get_transition_for(statechart, "s1", "tick")
    assert Statechart.get_transition_for(statechart, "s2", "tock")
    refute Statechart.get_transition_for(statechart, "s2", "tick")

    assert is_map(Statechart.get_transition_for(statechart, "s1", "tick"))
  end

  test "find_lcca/2" do
    statechart = Statechart.build(valid_definition())
    assert Statechart.find_lcca(statechart, ["s1", "s2"]) == "root"
    assert Statechart.find_lcca(statechart, ["s11", "s12"]) == "s1"
    assert Statechart.find_lcca(statechart, ["s12", "s2"]) == "root"
    assert Statechart.find_lcca(statechart, ["s12", "root"]) == nil
  end
end
