defmodule Tempo.Comparison do
  # This implementation is badly wrong
  # Just a template to get started

  # Compare two *lists* of components.
  # Note we are not comparing time values,
  # just the time units.
  #
  # We use Allens interval algebra
  # Each list is assumed to be sorted. This is
  # guaranteed for all parse results
  # except for groups and durations
  # so they need sorting before comparison

  # FIXME This is too naive and doesn't work for many cases
  @units Tempo.Iso8601.Unit.units()

  def compare([{u1, _v1} | _] = l1, [{u2, _v2} | _] = l2) when u1 in @units and u2 in @units do
    {l1_start, l1_finish} = Tempo.unit_min_max(l1)
    {l2_start, l2_finish} = Tempo.unit_min_max(l2)

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

end
