defmodule ExMachine.Step do
  @moduledoc """
  Mutable accumulator threaded through actions and guards during a transition.

  A `Step` is the value passed to every entry action, exit action, and
  transition action while the engine is processing a single event. It carries
  the user's context, the event being processed, and side-effect requests
  (raised events, delayed sends, invocations, cancellations) that the engine
  will collect at the end of the microstep.

  This separation keeps the user's context **pure** — `:exm_queue` and
  `:exm_params` no longer leak into it, fixing a long-standing wart of the
  legacy 0.1.x API.

  ## Fields

    * `:context` — application-defined term, the only thing that survives a
      microstep.
    * `:event` — the event currently being processed (atom, tuple
      `{name, params}`, or `nil` for entry/eventless steps).
    * `:raised` — list of internal events queued from this microstep, processed
      synchronously before the next external event (run-to-completion).
    * `:delayed` — list of `{ref, event, ms, owner_state}` for `send_after/3`.
      Honored only in server-mode (`ExMachine.Server`); ignored in pure
      functional dispatch.
    * `:invokes` — list of `{ref, spec, owner_state}` for `invoke/3`. Same
      remark as `:delayed`.
    * `:cancels` — list of refs to cancel previously scheduled timers/invokes.

  ## Helpers

  This module exposes a small surface for use inside actions:

      def my_action(step) do
        step
        |> Step.assign(:counter, step.context.counter + 1)
        |> Step.raise_event(:tick)
      end

  Action functions never mutate the engine state directly — they return a new
  `%Step{}`. This module is intentionally lean: heavier concerns (timers,
  invocations) are implemented by `ExMachine.Server` in milestone M6/M7.

  > #### Status {: .info}
  >
  > Helpers for `send_after/3` and `invoke/3` are **stubs** in M2; the storage
  > shape is final but the engine does not yet honor them. Full semantics arrive
  > in milestones M3 (raised events) and M7 (delayed + invoked).
  """

  alias __MODULE__

  @type ref :: reference()
  @type event :: atom() | {atom(), term()} | nil
  @type delayed_entry :: {ref(), event(), pos_integer(), atom()}
  @type invoke_spec :: mfa() | (Step.t() -> term())
  @type invoke_entry :: {ref(), invoke_spec(), atom()}

  @type t :: %Step{
          context: term(),
          event: event(),
          raised: [event()],
          delayed: [delayed_entry()],
          invokes: [invoke_entry()],
          cancels: [ref()]
        }

  defstruct context: nil,
            event: nil,
            raised: [],
            delayed: [],
            invokes: [],
            cancels: []

  @doc "Build a fresh step with the given context and (optional) event."
  @spec new(term(), event()) :: t()
  def new(context, event \\ nil), do: %Step{context: context, event: event}

  @doc """
  Replace the entire context.

  Prefer `assign/3` or `update/3` for targeted edits — they make intent clear.

  ## Examples

      iex> step = ExMachine.Step.new(%{a: 1})
      iex> ExMachine.Step.put_context(step, %{a: 2}).context
      %{a: 2}
  """
  @spec put_context(t(), term()) :: t()
  def put_context(%Step{} = step, context), do: %{step | context: context}

  @doc """
  Set a key in a map context. Raises if the context is not a map.

  ## Examples

      iex> step = ExMachine.Step.new(%{counter: 0})
      iex> step = ExMachine.Step.assign(step, :counter, 7)
      iex> step.context
      %{counter: 7}
  """
  @spec assign(t(), atom(), term()) :: t()
  def assign(%Step{context: ctx} = step, key, value) when is_map(ctx) do
    %{step | context: Map.put(ctx, key, value)}
  end

  @doc """
  Update a key in a map context with a function. Raises if not a map.

  ## Examples

      iex> step = ExMachine.Step.new(%{counter: 1})
      iex> step = ExMachine.Step.update(step, :counter, &(&1 + 1))
      iex> step.context
      %{counter: 2}
  """
  @spec update(t(), atom(), (term() -> term())) :: t()
  def update(%Step{context: ctx} = step, key, fun) when is_map(ctx) and is_function(fun, 1) do
    %{step | context: Map.update!(ctx, key, fun)}
  end

  @doc """
  Queue an internal event to be processed in the same macrostep, after the
  current microstep completes (run-to-completion).

  Order is preserved: events fire in the order they are raised across all
  microsteps of the macrostep.

  ## Examples

      iex> step = ExMachine.Step.new(%{}) |> ExMachine.Step.raise_event(:tick)
      iex> step.raised
      [:tick]
  """
  @spec raise_event(t(), event()) :: t()
  def raise_event(%Step{raised: r} = step, event), do: %{step | raised: r ++ [event]}

  @doc """
  Schedule an event to be sent to the machine after `ms` milliseconds.

  The owning state is recorded so the timer is cancelled automatically when
  that state is exited. Honored only in server-mode (`ExMachine.Server`); the
  pure functional engine drops delayed entries silently.

  Returns a `{ref, step}` tuple so the caller can later `cancel/2` if needed.
  """
  @spec send_after(t(), event(), pos_integer(), atom()) :: {ref(), t()}
  def send_after(%Step{} = step, event, ms, owner_state)
      when is_integer(ms) and ms > 0 and is_atom(owner_state) do
    ref = make_ref()
    {ref, %{step | delayed: step.delayed ++ [{ref, event, ms, owner_state}]}}
  end

  @doc """
  Request the engine to spawn an invoked service when entering this state.

  `spec` may be an `{module, function, args}` triple or an arity-1 function
  receiving the step. Honored only in server-mode (`ExMachine.Server`).
  """
  @spec invoke(t(), invoke_spec(), atom()) :: {ref(), t()}
  def invoke(%Step{} = step, spec, owner_state) when is_atom(owner_state) do
    ref = make_ref()
    {ref, %{step | invokes: step.invokes ++ [{ref, spec, owner_state}]}}
  end

  @doc "Cancel a previously scheduled delayed event or invocation by ref."
  @spec cancel(t(), ref()) :: t()
  def cancel(%Step{cancels: c} = step, ref) when is_reference(ref) do
    %{step | cancels: c ++ [ref]}
  end
end
