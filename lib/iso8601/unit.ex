defmodule Tempo.Iso8601.Unit do
  @sort_keys %{
    interval: 50,
    century: 40,
    decade: 35,
    year: 30,
    month: 25,
    day: 20,
    day_of_year: 19,
    day_of_month: 18,
    day_of_week: 17,
    hour: 15,
    minute: 10,
    second: 5,
    instance: 3
  }

  @unit_after %{
    year: {:month, 1..-1},
    month: {:day, 1..-1},
    week: {:day_of_week, 1..7},
    day: {:hour, 0..23},
    hour: {:minute, 0..59},
    minute: {:second, 0..59}
  }

  @units Map.keys(@sort_keys)

  def units do
    @units
  end

  def implicit_enumerator(:year = unit, calendar) do
    if calendar.calendar_base == :month do
      Map.get(@unit_after, unit)
    else
      {:week, 1..-1}
    end
  end

  def implicit_enumerator(unit, _calendar) do
    Map.get(@unit_after, unit)
  end

  def sort_key(time_unit) do
    Map.fetch!(@sort_keys, time_unit)
  end

  # Sort a keyword list of duration elements
  # by the key

  def sort([{_unit, _value} | _rest] = units, direction \\ :desc) do
    Enum.sort_by(units, &sort_key(elem(&1, 0)), direction)
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

  def compare({unit1, _value1}, {unit2, _value2}) do
    compare(unit1, unit2)
  end

  def compare({unit1, _value1}, unit2) when is_atom(unit1) and is_atom(unit2) do
    compare(unit1, unit2)
  end

  # Returns a boolean depending on whether the units are
  # in an appropriate order of increasing resolution

  def ordered?([unit, :group | rest]) when is_atom(unit) do
    ordered?([unit | rest])
  end

  def ordered?([unit, :select | rest]) when is_atom(unit) do
    ordered?([unit | rest])
  end

  def ordered?([unit, {:group, _value} | rest]) do
    ordered?([unit | rest])
  end

  def ordered?([unit, {:select, _value} | rest]) do
    ordered?([unit | rest])
  end

  def ordered?([unit_1, unit_2 | rest]) when is_atom(unit_1) and is_atom(unit_2) do
    if compare(unit_1, unit_2) == :gt, do: ordered?([unit_2 | rest]), else: false
  end

  def ordered?([{unit_1, _value_1}, {unit_2, _value_2} | rest]) do
    if compare(unit_1, unit_2) == :gt, do: ordered?([unit_2 | rest]), else: false
  end

  def ordered?([unit_1, {unit_2, _value_2} | rest]) when is_atom(unit_1) do
    if compare(unit_1, unit_2) == :gt, do: ordered?([unit_2 | rest]), else: false
  end

  def ordered?([_unit]) do
    true
  end
end
