defmodule Tempo.Component do

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

  @units Map.keys(@unit_order)

  def unit_order do
    @unit_order
  end

  # Compare two components
  def compare({unit_1, _value_1}, {unit_2, _value_2}) when unit_1 in @units and unit_2 in @units do
    index_1 = Map.fetch!(unit_order(), unit_1)
    index_2 = Map.fetch!(unit_order(), unit_2)

    cond do
      index_1 == index_2 -> :eq
      index_1 > index_2 -> :gt
      true -> :lt
    end
  end

  # Compare two *lists* of components.
  # Note we are not comparing time values,
  # just the time units.
  #
  # We use Allens interval algebra
  # Each list is assumed to be sorted. This is
  # guaranteed for all parse results
  # exceot for groups and durations
  # so they need sorting before comparison
  def compare([{u1, _v1} | _] = l1, [{u2, _v2} | _] = l2) when u1 in @units and u2 in @units do
    {l1_start, l1_finish} = list_bounds(l1)
    {l2_start, l2_finish} = list_bounds(l2)

    cond do
      l1_finish == l2_start - 1 ->
        :meets

      l1_finish < l2_start ->
        :precedes

      l1_start < l2_start && l1_finish > l2_finish ->
        :contains

      l1_finish == l2_finish && l1_start < l2_start ->
        :finished_by

      l1_start < l2_start && l1_finish > l2_start ->
        :overlaps

      l1_start == l2_start && l1_finish < l2_finish ->
        :starts

      l2_finish == l1_start - 1 ->
        :met_by

      l2_finish < l1_start ->
        :preceded_by

      l2_finish == l1_finish && l2_start < l1_start ->
        :finishes

      l1_start > l2_start && l1_finish < l2_finish ->
        :during

      l2_start == l1_start && l1_finish > l2_finish ->
        :started_by

      l2_finish > l1_start && l2_finish < l1_finish ->
        :overlapped_by

      l1_start == l2_start && l1_finish == l2_finish ->
        :eq
    end
  end

  defp list_bounds([{u1, _} | _] = l1st) do
    start = Map.fetch!(unit_order(), u1)

    [{u2, _} | _] = Enum.reverse(l1st)
    finish = Map.fetch!(unit_order(), u2)

    {start, finish}
  end
end

