defmodule Tempo.Algebra do

  # For grouping we need to ensure that the group
  # unit is a lesser unit than those preceeding and
  # a higher unit of those succeeding. We use this map
  # to define unit order.

  @unit_order %{
    century: 1,
    decade: 2,
    year: 3,

    month: 4,
    week_of_year: 4,
    day_of_year: 4,

    day_of_month: 5,
    day_of_week: 5,

    hour: 6,
    minute: 7,
    second: 8,
    fraction: 9
  }

  @tempo_types [:date, :time, :datetime, :interval, :duration, :all_of, :one_of]

  @doc """
  Traverse a parsed ISO8601 date/time while tracking
  the units already traversed and including
  an accumulator

  The function must return {:ok, acc} or {:error, message}

  """
  def traverse([{tempo_type, components}], fun) when tempo_type in @tempo_types do
    traverse(components, fun, {[], []})
  end

  defp traverse(components, fun, acc)  do
    Enum.reduce_while components, acc, fn
      {_unit, value}, acc when is_list(value) ->
        [traverse(value, fun) | acc]
      component, {previous_components, acc} ->
        case fun.(component, previous_components, acc) do
          {:ok, acc} -> {:cont, {[component | previous_components], acc}}
          {:error, message} -> {:halt, {:error, message}}
        end
    end
  end
end