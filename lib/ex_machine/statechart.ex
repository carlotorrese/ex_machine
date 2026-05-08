defmodule ExMachine.Statechart do
  @moduledoc """
  Compile-time DSL for declaring a statechart.

  Each module that calls `use ExMachine.Statechart` becomes a statechart: at
  compile time the DSL accumulates state nodes, transitions, and actions; at
  `__before_compile__` time it produces a frozen `ExMachine.Definition` that
  is exposed via `__statechart__/0`.

  ## Quick start

      defmodule TrafficLight do
        use ExMachine.Statechart

        initial_context %{cycles: 0}
        initial :red

        state :red do
          on_entry &__MODULE__.log/1
          on :timer, target: :green
        end

        state :green do
          on :timer, target: :yellow
        end

        state :yellow do
          on :timer, target: :red, action: &__MODULE__.incr/1
        end

        def log(step), do: step
        def incr(step), do: ExMachine.Step.update(step, :cycles, &(&1 + 1))
      end

      iex> def_ = TrafficLight.__statechart__()
      iex> def_.root
      :traffic_light
      iex> map_size(def_.nodes)
      4

  ## Top-level options

  `use ExMachine.Statechart` accepts:

    * `:type` — `:compound` (default) or `:parallel`. A `:parallel` root
      requires that every direct child be a `region`.
    * `:root` — atom override for the root node id. Defaults to
      `Macro.underscore(module_basename) |> String.to_atom/1`.

  ## DSL surface

  Top-level (module-level) macros:

    * `initial id` — set the initial substate of the root.
    * `initial_context term` — set the initial context returned to fresh
      machines.
    * `state id, opts \\\\ [], do: block` — declare a substate. Without a
      block, becomes `:atomic`; with a block containing `state` declarations,
      becomes `:compound`.
    * `parallel id, opts \\\\ [], do: block` — declare a parallel substate
      whose children must all be `region`.
    * `region id, opts, do: block` — declare a region (only inside `parallel`).
    * `history id, type: :deep | :shallow [, default: id]` — declare a
      history pseudostate.
    * `choice id, do: block` — declare a choice pseudostate with branches.
    * `final id, opts \\\\ [], do: block` — declare a final state.

  Inside a `state` / `region` body:

    * `on_entry fun` — append an entry action `(Step -> Step)`.
    * `on_exit fun` — append an exit action `(Step -> Step)`.
    * `on event, opts` — declare a transition. `opts`:
        * `:target` — destination state id (or `nil` for an action-only
          transition);
        * `:guard` — `(context -> boolean)`;
        * `:action` — `(Step -> Step)`;
        * `:type` — `:external` (default) or `:internal`.
      Use `event: nil` (or pass `nil`) for an eventless transition.

  Inside a `choice` body:

    * `cond_branch guard, target: id` — guarded branch.
    * `otherwise target: id` — default fallback branch (must be last).

  ## Validation

  All declarations are validated at compile-time via
  `ExMachine.Definition.validate!/1`. Any structural error raises
  `ExMachine.Definition.Error` with a precise message and points to the
  offending state.

  ## State of the implementation {: .info}

  Milestone M2 introduces the DSL and the compiled `Definition`. The
  execution engine, history, choice resolution, parallel selection, and
  server-mode arrive in milestones M3-M7.
  """

  alias ExMachine.Statechart.Builder

  @doc false
  defmacro __using__(opts) do
    type = Keyword.get(opts, :type, :compound)

    unless type in [:compound, :parallel] do
      raise ArgumentError, "use ExMachine.Statechart, :type must be :compound or :parallel"
    end

    quote bind_quoted: [type: type, opts: opts] do
      Module.register_attribute(__MODULE__, :exm_root, persist: false)
      Module.register_attribute(__MODULE__, :exm_root_kind, persist: false)
      Module.register_attribute(__MODULE__, :exm_initial_context, persist: false)
      Module.register_attribute(__MODULE__, :exm_nodes, persist: false)
      Module.register_attribute(__MODULE__, :exm_stack, persist: false)

      root_id =
        Keyword.get_lazy(opts, :root, fn ->
          __MODULE__
          |> Module.split()
          |> List.last()
          |> Macro.underscore()
          |> String.to_atom()
        end)

      ExMachine.Statechart.Builder.init_module(__MODULE__, root_id, type)

      import ExMachine.Statechart,
        only: [
          initial: 1,
          initial_context: 1,
          state: 1,
          state: 2,
          state: 3,
          parallel: 1,
          parallel: 2,
          parallel: 3,
          region: 2,
          region: 3,
          history: 2,
          choice: 1,
          choice: 2,
          final: 1,
          final: 2,
          on_entry: 1,
          on_exit: 1,
          on: 1,
          on: 2,
          cond_branch: 2,
          otherwise: 1
        ]

      @before_compile ExMachine.Statechart
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    fields = Builder.collect(env.module)
    definition = ExMachine.Definition.build!(fields)
    escaped = Macro.escape(definition)

    quote do
      @doc """
      Returns the compiled and validated `ExMachine.Definition` for this
      statechart. Computed at compile-time and inlined; callable at runtime
      with no overhead.
      """
      @spec __statechart__() :: ExMachine.Definition.t()
      def __statechart__, do: unquote(escaped)
    end
  end

  # ── Top-level declarations ────────────────────────────────────────────────

  @doc "Set the initial substate of the root (or current parent in nested usage)."
  defmacro initial(id) when is_atom(id) do
    quote do
      ExMachine.Statechart.Builder.set_initial(__MODULE__, unquote(id))
    end
  end

  @doc "Set the initial context shipped with fresh machines."
  defmacro initial_context(term) do
    quote do
      ExMachine.Statechart.Builder.set_initial_context(__MODULE__, unquote(term))
    end
  end

  # ── state ────────────────────────────────────────────────────────────────

  defmacro state(id), do: do_state(id, [], nil)

  defmacro state(id, opts_or_block) do
    {block, opts} = pop_block(opts_or_block)
    do_state(id, opts, block)
  end

  defmacro state(id, opts, do: block), do: do_state(id, opts, block)

  defp do_state(id, opts, block) do
    quote do
      ExMachine.Statechart.Builder.start_node(
        __MODULE__,
        unquote(id),
        unquote(opts),
        :state
      )

      unquote(block || :ok)
      ExMachine.Statechart.Builder.end_node(__MODULE__, unquote(id))
    end
  end

  # ── final ────────────────────────────────────────────────────────────────

  defmacro final(id), do: do_final(id, [], nil)

  defmacro final(id, opts_or_block) do
    {block, opts} = pop_block(opts_or_block)
    do_final(id, opts, block)
  end

  defp do_final(id, opts, block) do
    quote do
      ExMachine.Statechart.Builder.start_node(
        __MODULE__,
        unquote(id),
        unquote(opts),
        :final
      )

      unquote(block || :ok)
      ExMachine.Statechart.Builder.end_node(__MODULE__, unquote(id))
    end
  end

  # ── parallel ─────────────────────────────────────────────────────────────

  defmacro parallel(id), do: do_parallel(id, [], nil)

  defmacro parallel(id, opts_or_block) do
    {block, opts} = pop_block(opts_or_block)
    do_parallel(id, opts, block)
  end

  defmacro parallel(id, opts, do: block), do: do_parallel(id, opts, block)

  defp do_parallel(id, opts, block) do
    quote do
      ExMachine.Statechart.Builder.start_node(
        __MODULE__,
        unquote(id),
        unquote(opts),
        :parallel
      )

      unquote(block || :ok)
      ExMachine.Statechart.Builder.end_node(__MODULE__, unquote(id))
    end
  end

  # ── region (parallel-only child) ─────────────────────────────────────────

  defmacro region(id, opts_or_block) do
    {block, opts} = pop_block(opts_or_block)
    do_region(id, opts, block)
  end

  defmacro region(id, opts, do: block), do: do_region(id, opts, block)

  defp do_region(id, opts, block) do
    quote do
      ExMachine.Statechart.Builder.start_node(
        __MODULE__,
        unquote(id),
        unquote(opts),
        :region
      )

      unquote(block || :ok)
      ExMachine.Statechart.Builder.end_node(__MODULE__, unquote(id))
    end
  end

  # ── history (leaf) ───────────────────────────────────────────────────────

  defmacro history(id, opts) when is_atom(id) and is_list(opts) do
    quote do
      ExMachine.Statechart.Builder.start_node(
        __MODULE__,
        unquote(id),
        unquote(opts),
        :history
      )

      ExMachine.Statechart.Builder.end_node(__MODULE__, unquote(id))
    end
  end

  # ── choice ───────────────────────────────────────────────────────────────

  defmacro choice(id), do: do_choice(id, [], nil)

  defmacro choice(id, opts_or_block) do
    {block, opts} = pop_block(opts_or_block)
    do_choice(id, opts, block)
  end

  defp do_choice(id, opts, block) do
    quote do
      ExMachine.Statechart.Builder.start_node(
        __MODULE__,
        unquote(id),
        unquote(opts),
        :choice
      )

      unquote(block || :ok)
      ExMachine.Statechart.Builder.end_node(__MODULE__, unquote(id))
    end
  end

  @doc "Declare a guarded branch inside a `choice` block."
  defmacro cond_branch(guard, opts) when is_list(opts) do
    target = Keyword.fetch!(opts, :target)

    quote do
      ExMachine.Statechart.Builder.add_choice_branch(
        __MODULE__,
        unquote(guard),
        unquote(target)
      )
    end
  end

  @doc "Declare the default branch (no guard) inside a `choice` block."
  defmacro otherwise(opts) when is_list(opts) do
    target = Keyword.fetch!(opts, :target)

    quote do
      ExMachine.Statechart.Builder.add_choice_branch(__MODULE__, nil, unquote(target))
    end
  end

  # ── Inside-state declarations ────────────────────────────────────────────

  @doc "Append an entry action `(Step -> Step)` to the current state."
  defmacro on_entry(fun) do
    quote do
      ExMachine.Statechart.Builder.add_entry(__MODULE__, unquote(fun))
    end
  end

  @doc "Append an exit action `(Step -> Step)` to the current state."
  defmacro on_exit(fun) do
    quote do
      ExMachine.Statechart.Builder.add_exit(__MODULE__, unquote(fun))
    end
  end

  @doc """
  Declare a transition. Two forms:

      on :event, target: :foo            # event-triggered
      on event: nil, target: :foo        # eventless (also `on nil, target: :foo`)
  """
  defmacro on(event_or_opts) when is_list(event_or_opts) do
    do_on(Keyword.fetch!(event_or_opts, :event), Keyword.delete(event_or_opts, :event))
  end

  defmacro on(event), do: do_on(event, [])

  defmacro on(event, opts) when is_list(opts), do: do_on(event, opts)

  defp do_on(event, opts) do
    transition_opts =
      [event: event] ++
        Keyword.take(opts, [:target, :guard, :action, :type])

    quote do
      ExMachine.Statechart.Builder.add_transition(__MODULE__, unquote(transition_opts))
    end
  end

  # ── helpers ──────────────────────────────────────────────────────────────

  # Splits `[opt1: x, do: block]` into `{block, [opt1: x]}` and treats
  # a bare AST `do: block` keyword the same way. If the argument is an AST
  # block (from `state :foo do ... end` parsed without keyword), returns
  # `{block, []}`.
  defp pop_block(opts_or_block) when is_list(opts_or_block) do
    case Keyword.pop(opts_or_block, :do) do
      {nil, opts} -> {nil, opts}
      {block, opts} -> {block, opts}
    end
  end

  defp pop_block(other), do: {other, []}
end
