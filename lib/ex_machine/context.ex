defmodule ExMachine.Context do
  @moduledoc """
  Utility functions for managing statechart execution context.

  The context is a map that holds the current state of data during statechart
  execution. It serves as the primary means of data storage and communication
  between different parts of the state machine, including actions, guards,
  and transitions.

  This module provides convenient wrapper functions around standard Map operations
  that are commonly used when working with statechart contexts. All functions
  are designed to be imported into state modules for ease of use.

  ## Context Structure

  The context is a regular Elixir map with some reserved keys used internally
  by ExMachine:

  * `:exm_params` - Parameters passed with the current event
  * `:exm_queue` - Internal event queue for raised events

  All other keys are available for application-specific data.

  ## Examples

      # Basic context operations
      context = %{}
      context = put(context, :user_id, 123)
      context = put(context, :status, :active)
      
      user_id = get(context, :user_id)  # => 123
      status = get(context, :status, :inactive)  # => :active
      
      context = delete(context, :status)

      # Working with event parameters
      context = put_params(context, %{action: :login, user: "john"})
      params = get_params(context)  # => %{action: :login, user: "john"}

      # Raising internal events
      context = raise_event(context, :auto_save)
      context = raise_event(context, {:notify, "Task completed"})

  ## Usage in State Definitions

      defmodule UserAuthStatechart do
        use ExMachine.Statechart,
          definition: %{
            initial: "logged_out",
            states: %{
              "logged_out" => %{
                entry: fn context ->
                  context 
                  |> delete(:user_id)
                  |> delete(:session_token)
                end,
                transitions: %{
                  "login" => %{
                    target: "logged_in",
                    action: fn context ->
                      params = get_params(context)
                      context
                      |> put(:user_id, params.user_id)
                      |> put(:session_token, generate_token())
                      |> raise_event(:session_started)
                    end
                  }
                }
              },
              "logged_in" => %{
                transitions: %{
                  "logout" => "logged_out"
                }
              }
            }
          }
      end

  """

  @doc """
  Puts the given value under key in context.

  Same as `Map.put/3`, useful because it's imported in state modules.

  ## Examples

      iex> context = put(%{}, :hello, :world)
      iex> context[:hello]
      :world

  """
  def put(context, key, value), do: Map.put(context, key, value)

  @doc """
  Delete a key from the context.

  Same as `Map.delete/2`, useful because it's imported in state modules.

  ## Examples

      iex> context = put(%{}, :hello, :world)
      iex> context[:hello]
      :world
      iex> context = delete(context, :hello)
      iex> context[:hello]
      nil

  """
  def delete(context, key), do: Map.delete(context, key)

  @doc """
  Get the value of key in context.

  Same as `Map.get/3`, useful because it's imported in state modules.

  ## Examples

      iex> context = put(%{}, :hello, :world)
      iex> get(context, :hello)
      :world

      iex> get(%{}, :missing_key, :default_value)
      :default_value

  """
  def get(context, key, default \\ nil), do: Map.get(context, key, default)

  @doc """
  Puts the given term under the event params key in context.

  Event parameters are typically provided when sending events to the state machine
  and can be accessed by actions and guards during transition processing.

  ## Examples

      iex> context = put_params(%{}, %{user_id: 123, action: :update})
      iex> get_params(context)
      %{user_id: 123, action: :update}

  """
  def put_params(context, params), do: put(context, :exm_params, params)

  @doc """
  Get the current event parameters from context.

  Returns `nil` if no parameters were set for the current event.

  ## Examples

      iex> context = put_params(%{}, %{id: 1})
      iex> get_params(context)
      %{id: 1}

      iex> get_params(%{})
      nil

  """
  def get_params(context), do: get(context, :exm_params, nil)

  @doc """
  Remove event parameters from context.

  This is typically done automatically by the state machine engine
  after processing an event.

  ## Examples

      iex> context = put_params(%{}, %{id: 1})
      iex> context = delete_params(context)
      iex> get_params(context)
      nil

  """
  def delete_params(context), do: delete(context, :exm_params)

  @doc """
  Raise an internal event during the execution of an action.

  Internal events are processed immediately after the current macrostep
  completes, allowing actions to trigger additional transitions without
  requiring external events.

  ## Parameters

  * `context` - The current execution context
  * `event` - The event to raise (atom or tuple with parameters)

  ## Examples

      # Simple internal event
      context = raise_event(context, :auto_save)

      # Internal event with parameters  
      context = raise_event(context, {:notify, %{message: "Process completed"}})

      # Multiple internal events can be queued
      context = context
                |> raise_event(:validate_data)
                |> raise_event(:send_notification)

  ## Usage in Actions

      action: fn context ->
        if should_auto_logout?(context) do
          raise_event(context, :auto_logout)
        else
          context
        end
      end

  """
  def raise_event(context, event) do
    case context[:exm_queue] do
      nil -> Map.put(context, :exm_queue, [event])
      queue -> Map.put(context, :exm_queue, queue ++ [event])
    end
  end
end
