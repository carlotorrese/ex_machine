defmodule ExMachine.StateNode do
  @moduledoc """
  Compiled representation of a single state in a statechart.

  Every node in a `ExMachine.Definition` is a `StateNode` keyed by its `:id`.
  The DSL (`ExMachine.Statechart`) produces these nodes during compile-time;
  user code does not construct them directly.

  ## Node kinds

    * `:atomic` — a leaf state with no substates.
    * `:compound` — a parent state with at least one substate; one substate
      must be marked as `:initial`.
    * `:parallel` — a parent state whose children are all `:region` nodes that
      execute concurrently. The configuration must contain exactly one active
      atomic descendant per region.
    * `:region` — direct child of a `:parallel` node. Behaves like a compound
      state but cannot exist outside a parallel.
    * `:final` — a leaf marker indicating a region or compound has completed.
      Triggers a `done.state.<parent>` event.
    * `:history` — a pseudostate that, when entered, restores the last active
      configuration of its parent (`:shallow` or `:deep`).
    * `:choice` — a pseudostate that, when entered, evaluates its branches and
      delegates entry to the first matching target. `:otherwise` is the default.

  ## Field semantics

    * `:id` — atom, unique within the definition.
    * `:kind` — see above.
    * `:parent` — id of the enclosing node, or `nil` for the root.
    * `:initial` — id of the initial substate (only for `:compound` and
      `:region`).
    * `:substates` — ordered list of child ids (declaration order).
    * `:on_entry` / `:on_exit` — list of arity-1 functions
      `(ExMachine.Step.t() -> ExMachine.Step.t())`. Multiple declarations
      accumulate in declaration order.
    * `:transitions` — list of `ExMachine.Transition.t()` whose `:source` is
      this node. Includes both event-triggered and eventless transitions.
    * `:history_type` — `:shallow | :deep | nil`. Set only for `:history`.
    * `:history_default` — id used when no history has been recorded yet.
    * `:choice_branches` — list of `{guard | nil, target_id}` pairs in
      declaration order. The last `nil`-guard entry is the `:otherwise`
      fallback. Set only for `:choice`.
  """

  alias __MODULE__

  @type id :: atom()
  @type kind ::
          :atomic
          | :compound
          | :parallel
          | :region
          | :final
          | :history
          | :choice
  @type history_kind :: :deep | :shallow

  @type t :: %StateNode{
          id: id(),
          kind: kind(),
          parent: id() | nil,
          initial: id() | nil,
          substates: [id()],
          on_entry: [(ExMachine.Step.t() -> ExMachine.Step.t())],
          on_exit: [(ExMachine.Step.t() -> ExMachine.Step.t())],
          transitions: [ExMachine.Transition.t()],
          history_type: history_kind() | nil,
          history_default: id() | nil,
          choice_branches: [{(term() -> boolean()) | nil, id()}]
        }

  @enforce_keys [:id, :kind]
  defstruct id: nil,
            kind: nil,
            parent: nil,
            initial: nil,
            substates: [],
            on_entry: [],
            on_exit: [],
            transitions: [],
            history_type: nil,
            history_default: nil,
            choice_branches: []

  @doc "Build a new node with the given id, kind, and optional fields."
  @spec new(id(), kind(), keyword()) :: t()
  def new(id, kind, opts \\ []) when is_atom(id) and is_atom(kind) do
    struct!(__MODULE__, [{:id, id}, {:kind, kind} | opts])
  end

  @doc "True if the node can have substates."
  @spec composite?(t()) :: boolean()
  def composite?(%StateNode{kind: kind}) when kind in [:compound, :parallel, :region], do: true
  def composite?(%StateNode{}), do: false

  @doc "True if the node is a pseudostate (no run-time activity, used for routing only)."
  @spec pseudostate?(t()) :: boolean()
  def pseudostate?(%StateNode{kind: kind}) when kind in [:history, :choice], do: true
  def pseudostate?(%StateNode{}), do: false

  @doc "True if the node terminates a region."
  @spec final?(t()) :: boolean()
  def final?(%StateNode{kind: :final}), do: true
  def final?(%StateNode{}), do: false
end
