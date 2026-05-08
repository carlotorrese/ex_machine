defmodule ExMachine.Statechart.Builder do
  @moduledoc false
  # Internal helpers driven by the DSL macros in `ExMachine.Statechart`.
  # Mutates module attributes during compilation. Not part of the public API.

  alias ExMachine.{StateNode, Transition}

  # Module attributes used during compilation:
  #   @exm_root              :: atom            (root id, set by use)
  #   @exm_root_kind         :: :compound | :parallel
  #   @exm_initial_context   :: term
  #   @exm_nodes             :: %{atom => %StateNode{}}
  #   @exm_stack             :: [atom]          (current parent path; head is current)

  @placeholder_state_kind :__state_placeholder__

  @doc "Initialise the per-module DSL attributes. Called from `__using__`."
  def init_module(module, root_id, root_kind) do
    Module.put_attribute(module, :exm_root, root_id)
    Module.put_attribute(module, :exm_root_kind, root_kind)
    Module.put_attribute(module, :exm_initial_context, nil)

    Module.put_attribute(module, :exm_nodes, %{
      root_id => StateNode.new(root_id, root_kind, parent: nil)
    })

    Module.put_attribute(module, :exm_stack, [root_id])
  end

  @doc "Set the initial-context map (or any term)."
  def set_initial_context(module, term) do
    Module.put_attribute(module, :exm_initial_context, term)
  end

  @doc "Set the initial substate of the current parent (root, compound, or region)."
  def set_initial(module, id) do
    parent_id = current_id(module)
    update_node!(module, parent_id, &%{&1 | initial: id})
  end

  @doc """
  Push a new node onto the stack. `kind_hint` may be one of:
    * `:state`     — provisional, promoted to :compound or :atomic in `end_node`
    * `:parallel`  — final
    * `:region`    — final
    * `:history`   — final, leaf (no block expected)
    * `:choice`    — final
    * `:final`     — final, leaf
  """
  def start_node(module, id, opts, kind_hint) do
    parent_id = current_id(module)
    nodes = Module.get_attribute(module, :exm_nodes)

    if Map.has_key?(nodes, id) do
      raise ArgumentError,
            "duplicate state id #{inspect(id)} (already declared in this statechart)"
    end

    kind =
      case kind_hint do
        :state -> @placeholder_state_kind
        other -> other
      end

    node =
      StateNode.new(id, kind,
        parent: parent_id,
        initial: Keyword.get(opts, :initial),
        history_type: if(kind == :history, do: Keyword.fetch!(opts, :type)),
        history_default: if(kind == :history, do: Keyword.get(opts, :default))
      )

    Module.put_attribute(module, :exm_nodes, Map.put(nodes, id, node))

    # Append to parent's substates in declaration order.
    update_node!(module, parent_id, &%{&1 | substates: &1.substates ++ [id]})

    # If this state was declared as the initial substate of its parent,
    # propagate that to the parent's :initial field.
    if Keyword.get(opts, :initial?) do
      update_node!(module, parent_id, &%{&1 | initial: id})
    end

    Module.put_attribute(module, :exm_stack, [id | Module.get_attribute(module, :exm_stack)])
    :ok
  end

  @doc "Pop the current node off the stack and finalise its kind if provisional."
  def end_node(module, id) do
    case Module.get_attribute(module, :exm_stack) do
      [^id | rest] ->
        Module.put_attribute(module, :exm_stack, rest)

      stack ->
        raise "Builder.end_node/2 stack mismatch: expected #{inspect(id)} on top, got #{inspect(stack)}"
    end

    update_node!(module, id, fn
      %StateNode{kind: unquote(@placeholder_state_kind), substates: []} = n ->
        %{n | kind: :atomic}

      %StateNode{kind: unquote(@placeholder_state_kind)} = n ->
        %{n | kind: :compound}

      n ->
        n
    end)

    :ok
  end

  @doc "Append an entry action to the current node."
  def add_entry(module, fun) when is_function(fun, 1) do
    update_current!(module, &%{&1 | on_entry: &1.on_entry ++ [fun]})
  end

  @doc "Append an exit action to the current node."
  def add_exit(module, fun) when is_function(fun, 1) do
    update_current!(module, &%{&1 | on_exit: &1.on_exit ++ [fun]})
  end

  @doc """
  Append a transition to the current node.
  `opts` accepts: `:event`, `:target`, `:guard`, `:action`, `:type`.
  """
  def add_transition(module, opts) when is_list(opts) do
    source = current_id(module)
    transition = Transition.new([{:source, source} | opts])
    update_current!(module, &%{&1 | transitions: &1.transitions ++ [transition]})
  end

  @doc "Append a choice branch to the current node (must be a :choice)."
  def add_choice_branch(module, guard, target)
      when (is_function(guard, 1) or is_nil(guard)) and is_atom(target) do
    update_current!(module, fn node ->
      unless node.kind == :choice do
        raise "cond_branch/otherwise can only appear inside a `choice` block"
      end

      %{node | choice_branches: node.choice_branches ++ [{guard, target}]}
    end)
  end

  @doc "Read the current parent id (top of stack)."
  def current_id(module) do
    case Module.get_attribute(module, :exm_stack) do
      [id | _] -> id
      [] -> raise "DSL stack is empty (call site outside of a statechart block?)"
    end
  end

  @doc "Read the assembled definition fields. Used by `__before_compile__`."
  def collect(module) do
    %{
      root: Module.get_attribute(module, :exm_root),
      nodes: Module.get_attribute(module, :exm_nodes),
      initial_context: Module.get_attribute(module, :exm_initial_context)
    }
  end

  # ── private ───────────────────────────────────────────────────────────────

  defp update_node!(module, id, fun) do
    nodes = Module.get_attribute(module, :exm_nodes)
    node = Map.fetch!(nodes, id)
    Module.put_attribute(module, :exm_nodes, Map.put(nodes, id, fun.(node)))
  end

  defp update_current!(module, fun) do
    update_node!(module, current_id(module), fun)
  end
end
