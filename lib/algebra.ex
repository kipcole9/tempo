defmodule Tempo.Algebra do

  # For grouping we need to ensure that the group
  # unit is a lesser unit than those preceeding and
  # a higher unit of those succeeding. We use this map
  # to define unit order.

  @tempo_types [:date, :time_of_day, :datetime, :interval, :duration, :all_of, :one_of]

  @doc """
  Traverse a parsed ISO8601 date/time while tracking
  the units already traversed and including
  an accumulator

  The function must return {:ok, acc} or {:error, message}

  """
  def traverse([{tempo_type, components}], fun) when tempo_type in @tempo_types and is_function(fun, 3) do
    traverse(components, fun, {[], []})
  end

  defp traverse(components, fun, acc)  do
    Enum.reduce_while components, acc, fn
      {_unit, value}, acc when is_list(value) ->
        [traverse(value, fun, acc) | acc]
      component, {previous_components, acc} ->
        case fun.(component, previous_components, acc) do
          {:ok, acc} ->
            {:cont, {[component | previous_components], acc}}
          {:error, message} ->
            {:halt, {:error, message}}
          other ->
            raise RuntimeError, "Function return must be {:ok, acc} or {:error, reason}. Found #{inspect other}"
        end
    end
  end
end