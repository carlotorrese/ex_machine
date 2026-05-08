defmodule ExMachine.Transition do
  @moduledoc """
  Represents a single transition in a statechart definition.

  A transition is the binding between an event (or eventless trigger), a guard
  condition, an optional action, and a target state. Transitions are produced by
  the `ExMachine.Statechart` DSL via `on/2` declarations and never constructed
  by hand in user code.

  Transitions follow SCXML semantics:

    * `:event` — atom, or `nil` for an eventless transition (fired during
      run-to-completion when the guard, if any, holds).
    * `:source` — id of the state that owns the transition.
    * `:target` — id of the destination state, or `nil` for a pure side-effect
      transition (action only, no state change). Always `nil` when `:type` is
      `:internal` and the transition is acting only on the context.
    * `:guard` — `(context -> boolean)` arity-1 function or `nil`.
    * `:action` — `(step -> step)` arity-1 function or `nil`. Receives the
      current `ExMachine.Step` and returns an updated one.
    * `:type` — `:external` (default) or `:internal`. An external transition
      exits and re-enters the source's compound when `target` is a descendant;
      an internal transition stays inside.

  `Transition` is a plain struct: it carries no behaviour. The actual matching
  and resolution lives in `ExMachine.Engine` (added in milestone M3).
  """

  alias __MODULE__

  @type guard_fun :: (context :: term() -> boolean())
  @type action_fun :: (ExMachine.Step.t() -> ExMachine.Step.t())
  @type kind :: :external | :internal

  @type t :: %Transition{
          event: atom() | nil,
          source: atom(),
          target: atom() | nil,
          guard: guard_fun() | nil,
          action: action_fun() | nil,
          type: kind()
        }

  @enforce_keys [:source]
  defstruct event: nil,
            source: nil,
            target: nil,
            guard: nil,
            action: nil,
            type: :external

  @doc """
  Build a transition from a keyword list.

  Used internally by the DSL. Validates that `:source` is provided and that
  `:type` is one of `:external | :internal`. Other keys default to `nil`.

  ## Examples

      iex> ExMachine.Transition.new(source: :red, event: :timer, target: :green)
      %ExMachine.Transition{event: :timer, source: :red, target: :green, type: :external}

      iex> ExMachine.Transition.new(source: :foo, event: :tick, type: :internal)
      %ExMachine.Transition{event: :tick, source: :foo, target: nil, type: :internal}
  """
  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts) do
    type = Keyword.get(opts, :type, :external)

    unless type in [:external, :internal] do
      raise ArgumentError,
            "transition :type must be :external or :internal, got: #{inspect(type)}"
    end

    struct!(__MODULE__, opts)
  end

  @doc """
  Returns true if the transition has no event, i.e. is eventless (also called
  "automatic" or "always" transition).
  """
  @spec eventless?(t()) :: boolean()
  def eventless?(%Transition{event: nil}), do: true
  def eventless?(%Transition{}), do: false
end
