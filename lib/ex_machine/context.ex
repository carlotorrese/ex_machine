defmodule ExMachine.Context do
  @doc """
  Puts the given value under key in context.
  Same as Map.put/3, useful because its imported in state module
  ## Examples
      iex> context = put(%{}, :hello, :world)
      iex> context[:hello]
      :world
  """
  def put(context, key, value), do: Map.put(context, key, value)

  @doc """
  Delete a key from the context.
  Same as Map.delete/2, useful because its imported in state module

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
  Same as Map.get/3, useful because its imported in state module
  ## Examples
      iex> context = put(%{}, :hello, :world)
      iex> get(context, :hello)
      :world
  """
  def get(context, key, default \\ nil), do: Map.get(context, key, default)

  @doc """
  Puts the given term under the event params key in context.
  """
  def put_params(context, params), do: put(context, :exm_params, params)

  def get_params(context), do: get(context, :exm_params, nil)

  def delete_params(context), do: delete(context, :exm_params)

  @doc """
  Raise an internal event during the execution of an action
  """
  def raise_event(context, event) do
    case context[:exm_queue] do
      nil -> Map.put(context, :exm_queue, [event])
      queue -> Map.put(context, :exm_queue, queue ++ [event])
    end
  end
end
