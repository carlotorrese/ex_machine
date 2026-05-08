defmodule ExMachine.Definition do
  @moduledoc """
  Compiled, validated representation of a statechart.

  Produced at compile-time by the `ExMachine.Statechart` DSL. Each module
  using `use ExMachine.Statechart` gets a `__statechart__/0` function that
  returns its frozen `%Definition{}`.

  A definition is a flat map of nodes (`%ExMachine.StateNode{}`) keyed by id,
  plus the root id and the initial context. The hierarchy is encoded inside
  each node via `:parent` and `:substates`. This shape lets the engine answer
  ancestor / descendant / leaf queries in O(depth) without walking trees.

  ## Validation

  `build!/1` performs the following checks. Any failure raises
  `ExMachine.Definition.Error` with a precise message:

    * the root must exist in `nodes`
    * every node id is unique
    * every node's `:parent` matches the parent's `:substates`
    * every transition `:source` matches an existing node
    * every transition `:target` (when not `nil`) matches an existing node
    * a `:compound` and a `:region` must declare a valid `:initial` substate
    * a `:parallel` must have at least 2 region children
    * a `:history` must live inside a composite (compound or region)
    * a `:history` must have a valid `:history_default` if its compound has
      no other initial-eligible substate
    * a `:choice` must have at least one branch (cond_branch or otherwise)

  Validation is intentionally exhaustive: a malformed statechart should fail
  to compile, not at runtime.
  """

  alias ExMachine.{StateNode, Transition}
  alias __MODULE__

  defmodule Error do
    @moduledoc "Raised when a statechart definition is invalid."
    defexception [:message]
  end

  @type t :: %Definition{
          root: StateNode.id(),
          nodes: %{StateNode.id() => StateNode.t()},
          initial_context: term()
        }

  @enforce_keys [:root]
  defstruct root: nil,
            nodes: %{},
            initial_context: nil

  @doc """
  Build and validate a definition from raw fields.

  Raises `ExMachine.Definition.Error` if the definition is invalid.
  """
  @spec build!(keyword() | map()) :: t()
  def build!(fields) when is_list(fields), do: fields |> Map.new() |> build!()

  def build!(%{root: root, nodes: nodes} = fields) do
    initial_context = Map.get(fields, :initial_context)

    %Definition{root: root, nodes: nodes, initial_context: initial_context}
    |> validate!()
  end

  @doc """
  Run all validation checks. Returns the unchanged definition on success,
  raises `ExMachine.Definition.Error` otherwise.
  """
  @spec validate!(t()) :: t()
  def validate!(%Definition{} = def_) do
    def_
    |> check_root_exists!()
    |> check_parent_consistency!()
    |> check_initial_targets!()
    |> check_parallel_structure!()
    |> check_history_placement!()
    |> check_choice_branches!()
    |> check_transition_targets!()
  end

  @doc "Fetch a node by id, raising if missing."
  @spec fetch!(t(), StateNode.id()) :: StateNode.t()
  def fetch!(%Definition{nodes: nodes}, id) do
    case Map.fetch(nodes, id) do
      {:ok, node} -> node
      :error -> raise Error, "unknown state id: #{inspect(id)}"
    end
  end

  @doc "Return the chain of ancestor ids of `id`, from immediate parent up to root inclusive."
  @spec ancestors(t(), StateNode.id()) :: [StateNode.id()]
  def ancestors(%Definition{} = def_, id) do
    case fetch!(def_, id).parent do
      nil -> []
      parent -> [parent | ancestors(def_, parent)]
    end
  end

  @doc "Return the set of all descendants of `id` (children, grandchildren, ...)."
  @spec descendants(t(), StateNode.id()) :: MapSet.t(StateNode.id())
  def descendants(%Definition{} = def_, id) do
    fetch!(def_, id).substates
    |> Enum.reduce(MapSet.new(), fn child, acc ->
      acc
      |> MapSet.put(child)
      |> MapSet.union(descendants(def_, child))
    end)
  end

  # ── Validation helpers ────────────────────────────────────────────────────

  defp check_root_exists!(%Definition{root: root, nodes: nodes} = def_) do
    if Map.has_key?(nodes, root) do
      def_
    else
      raise Error, "root state #{inspect(root)} is not present in nodes"
    end
  end

  defp check_parent_consistency!(%Definition{nodes: nodes} = def_) do
    Enum.each(nodes, fn {id, node} ->
      cond do
        is_nil(node.parent) and id != def_.root ->
          raise Error,
                "node #{inspect(id)} has no parent but is not the root #{inspect(def_.root)}"

        not is_nil(node.parent) ->
          parent = nodes[node.parent]

          unless parent && id in parent.substates do
            raise Error,
                  "node #{inspect(id)} declares parent #{inspect(node.parent)} but is not in its substates"
          end

        true ->
          :ok
      end
    end)

    def_
  end

  defp check_initial_targets!(%Definition{nodes: nodes} = def_) do
    Enum.each(nodes, fn {id, node} ->
      if node.kind in [:compound, :region] do
        check_initial_for_composite!(id, node)
      end
    end)

    def_
  end

  defp check_initial_for_composite!(id, node) do
    cond do
      is_nil(node.initial) ->
        raise Error, "#{node.kind} #{inspect(id)} has no :initial substate"

      node.initial not in node.substates ->
        raise Error,
              "#{node.kind} #{inspect(id)} has :initial #{inspect(node.initial)} which is not one of its substates #{inspect(node.substates)}"

      true ->
        :ok
    end
  end

  defp check_parallel_structure!(%Definition{nodes: nodes} = def_) do
    Enum.each(nodes, fn {id, node} ->
      case node.kind do
        :parallel -> check_parallel_node!(id, node, nodes)
        :region -> check_region_node!(id, node, nodes)
        _ -> :ok
      end
    end)

    def_
  end

  defp check_parallel_node!(id, node, nodes) do
    if length(node.substates) < 2 do
      raise Error,
            "parallel #{inspect(id)} must have at least 2 region children, got #{length(node.substates)}"
    end

    for sub <- node.substates do
      child = Map.get(nodes, sub)

      unless child && child.kind == :region do
        raise Error,
              "parallel #{inspect(id)} child #{inspect(sub)} must be a :region, got #{inspect(child && child.kind)}"
      end
    end
  end

  defp check_region_node!(id, node, nodes) do
    parent = Map.get(nodes, node.parent)

    unless parent && parent.kind == :parallel do
      raise Error,
            "region #{inspect(id)} must have a :parallel parent, got #{inspect(parent && parent.kind)}"
    end
  end

  defp check_history_placement!(%Definition{nodes: nodes} = def_) do
    Enum.each(nodes, fn {id, node} ->
      if node.kind == :history do
        parent = nodes[node.parent]

        unless parent && parent.kind in [:compound, :region] do
          raise Error,
                "history #{inspect(id)} must live inside a :compound or :region, got #{inspect(parent && parent.kind)}"
        end

        unless node.history_type in [:deep, :shallow] do
          raise Error,
                "history #{inspect(id)} must declare :type :deep or :shallow, got #{inspect(node.history_type)}"
        end

        if node.history_default && node.history_default not in parent.substates do
          raise Error,
                "history #{inspect(id)} default #{inspect(node.history_default)} is not a substate of parent #{inspect(parent.id)}"
        end
      end
    end)

    def_
  end

  defp check_choice_branches!(%Definition{nodes: nodes} = def_) do
    Enum.each(nodes, fn {id, node} ->
      if node.kind == :choice, do: check_choice_node!(id, node, nodes)
    end)

    def_
  end

  defp check_choice_node!(id, node, nodes) do
    if node.choice_branches == [] do
      raise Error, "choice #{inspect(id)} must declare at least one branch"
    end

    for {_guard, target} <- node.choice_branches,
        not Map.has_key?(nodes, target) do
      raise Error, "choice #{inspect(id)} branch targets unknown state #{inspect(target)}"
    end
  end

  defp check_transition_targets!(%Definition{nodes: nodes} = def_) do
    for {_id, node} <- nodes,
        %Transition{source: source, target: target} <- node.transitions do
      unless Map.has_key?(nodes, source) do
        raise Error, "transition source #{inspect(source)} is not a known state"
      end

      if not is_nil(target) and not Map.has_key?(nodes, target) do
        raise Error,
              "transition #{inspect(source)} → #{inspect(target)} targets unknown state"
      end
    end

    def_
  end
end
