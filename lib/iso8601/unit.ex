defmodule Tempo.Iso8601.Unit do

  @sort_keys %{
    century: 40,
    decade: 35,
    year: 30,
    month: 25,
    day: 20,
    day_of_year: 20,
    day_of_month: 20,
    day_of_week: 20,
    hour: 15,
    minute: 10,
    second: 5
  }

  def sort_key(time_unit) do
    Map.fetch!(@sort_keys, time_unit)
  end

  # Sort a keyword list of duration elements
  # by the key

  def sort(duration, direction \\ :asc) do
    Enum.sort_by(duration, &sort_key(elem(&1, 0)), direction)
  end

  def compare(unit_1, unit_2) when is_atom(unit_1) and is_atom(unit_2) do
    u1 = sort_key(unit_1)
    u2 = sort_key(unit_2)

    cond do
      u1 < u2 -> :lt
      u1 > u2 -> :gt
      true -> :eq
    end
  end
end