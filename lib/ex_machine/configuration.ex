defmodule ExMachine.Configuration do
  @moduledoc """
  Set of currently active states in a running machine.

  Statechart configurations are sets, not single chains: a parallel state has
  multiple atomic descendants active at once. We represent this as a
  `MapSet.t/1` of state ids and answer hierarchical queries against the
  compiled `ExMachine.Definition`.

  By construction, an *active configuration* is **closed under ancestry**: if
  an atomic state is active, every ancestor up to the root is also active.
  Functions in this module preserve that invariant.

  ## Operations

    * `initial/1` — starting configuration for a definition.
    * `initial_chain/2` — walk the `:initial` chain (handles compound,
      region, and parallel) down to atomic descendants.
    * `enter/3` — add a node and its initial chain.
    * `exit/2` — remove a set of nodes.
    * `active?/2` — membership test.
    * `atomic_states/2` — atomic states currently active (the "leaves").
    * `proper_ancestors_until/3` — ancestors up to (excluding) some boundary.

  Pseudostates (`:choice`, `:history`) are never present in a configuration.
  They are resolved during the entry-set computation in `ExMachine.Engine`.
  """

  alias ExMachine.{Definition, StateNode}

  @type t :: MapSet.t(StateNode.id())

  @doc "Empty configuration."
  @spec new() :: t()
  def new, do: MapSet.new()

  @doc """
  Initial configuration produced by entering the root and following its
  `:initial` chain down to atomic descendants. Parallel roots are
  expanded to include every region's initial chain.
  """
  @spec initial(Definition.t()) :: {t(), [StateNode.id()]}
  def initial(%Definition{root: root} = def_) do
    chain = initial_chain(def_, root)
    {MapSet.new(chain), chain}
  end

  @doc """
  Walk the `:initial` field down from `id` until reaching an atomic state.
  Returns the list of node ids from `id` (inclusive) to the leaf, in
  parent-first order — suitable for `on_entry` execution.

  Raises if a non-pseudostate composite has no `:initial` (validation should
  have caught this at compile time).
  """
  @spec initial_chain(Definition.t(), StateNode.id()) :: [StateNode.id()]
  def initial_chain(%Definition{} = def_, id) do
    node = Definition.fetch!(def_, id)

    case node.kind do
      :atomic -> [id]
      :final -> [id]
      kind when kind in [:compound, :region] -> [id | initial_chain(def_, node.initial)]
      :parallel -> [id | Enum.flat_map(node.substates, &initial_chain(def_, &1))]
      _ -> [id]
    end
  end

  @doc """
  Whether `id` is currently active.
  """
  @spec active?(t(), StateNode.id()) :: boolean()
  def active?(config, id), do: MapSet.member?(config, id)

  @doc """
  Atomic (leaf) states currently active.

  Both `:atomic` and `:final` count as leaves: a final state is the terminal
  configuration of its region. In a non-parallel machine this is a
  single-element list; in a parallel machine, one entry per region.
  """
  @spec atomic_states(t(), Definition.t()) :: [StateNode.id()]
  def atomic_states(config, %Definition{} = def_) do
    config
    |> Enum.filter(fn id -> Definition.fetch!(def_, id).kind in [:atomic, :final] end)
    |> Enum.sort()
  end

  @doc """
  Add `id` and its initial chain to the configuration. Returns
  `{new_config, entered_ids_in_order}` where the order matches what
  `on_entry` actions should follow (parent-first).
  """
  @spec enter(t(), Definition.t(), StateNode.id()) :: {t(), [StateNode.id()]}
  def enter(config, %Definition{} = def_, id) do
    chain = initial_chain(def_, id)
    {Enum.reduce(chain, config, &MapSet.put(&2, &1)), chain}
  end

  @doc """
  Remove every id in `ids` from the configuration.
  """
  @spec exit(t(), [StateNode.id()]) :: t()
  def exit(config, ids), do: Enum.reduce(ids, config, &MapSet.delete(&2, &1))

  @doc """
  Ancestors of `id` up to but excluding `boundary` (exclusive). Returns the
  list child-first (deepest first), suitable for `on_exit` ordering.

  If `boundary` is `nil`, walks all the way to the root.
  """
  @spec proper_ancestors_until(Definition.t(), StateNode.id(), StateNode.id() | nil) :: [
          StateNode.id()
        ]
  def proper_ancestors_until(%Definition{} = def_, id, boundary) do
    Definition.ancestors(def_, id)
    |> Enum.take_while(fn ancestor -> ancestor != boundary end)
  end
end
