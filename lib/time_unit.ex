# defmodule Tempo.TimeUnit do
#   @unit_order %{
#     century: 1,
#     decade: 2,
#     year: 3,
#     month: 4,
#     week_of_year: 4,
#     day_of_year: 4,
#     day_of_month: 5,
#     day_of_week: 5,
#     hour: 6,
#     minute: 7,
#     second: 8,
#     fraction: 9
#   }
#
#   @units Map.keys(@unit_order)
#
#   def unit_order do
#     @unit_order
#   end
#
#   def compare({unit_1, value_1}, {unit_2, value_2})
#       when unit_1 in @units and unit_2 in @units and is_number(value_1) and is_number(value_2) do
#     comparison = unit_compare(unit_1, unit_2)
#
#     if comparison == :eq do
#       compare_values(value_1, value_2)
#     else
#       comparison
#     end
#   end
#
#   # Compare two *lists* of components.
#   # Note we are not comparing time values,
#   # just the time units.
#   #
#   # We use Allens interval algebra
#   # Each list is assumed to be sorted. This is
#   # guaranteed for all parse results
#   # except for groups and durations
#   # so they need sorting before comparison
#
#   # FIXME This is too naive and doesn't work for many cases
#   def compare([{u1, _v1} | _] = l1, [{u2, _v2} | _] = l2) when u1 in @units and u2 in @units do
#     {l1_start, l1_finish} = list_bounds(l1)
#     {l2_start, l2_finish} = list_bounds(l2)
#
#     cond do
#       l1_finish == l2_start - 1 ->
#         :meets
#
#       l1_finish < l2_start ->
#         :precedes
#
#       l1_start < l2_start && l1_finish > l2_finish ->
#         :contains
#
#       l1_finish == l2_finish && l1_start < l2_start ->
#         :finished_by
#
#       l1_start < l2_start && l1_finish > l2_start ->
#         :overlaps
#
#       l1_start == l2_start && l1_finish < l2_finish ->
#         :starts
#
#       l2_finish == l1_start - 1 ->
#         :met_by
#
#       l2_finish < l1_start ->
#         :preceded_by
#
#       l2_finish == l1_finish && l2_start < l1_start ->
#         :finishes
#
#       l1_start > l2_start && l1_finish < l2_finish ->
#         :during
#
#       l2_start == l1_start && l1_finish > l2_finish ->
#         :started_by
#
#       l2_finish > l1_start && l2_finish < l1_finish ->
#         :overlapped_by
#
#       l1_start == l2_start && l1_finish == l2_finish ->
#         :eq
#     end
#   end
#
#   # Compare two time units
#   defp unit_compare(unit_1, unit_2) when unit_1 in @units and unit_2 in @units do
#     index_1 = Map.fetch!(unit_order(), unit_1)
#     index_2 = Map.fetch!(unit_order(), unit_2)
#
#     cond do
#       index_1 == index_2 -> :eq
#       index_1 > index_2 -> :lt
#       true -> :gt
#     end
#   end
#
#   # FIXME Not all values are numbers: :groups, :selections, ranges, sets
#   defp compare_values(value_1, value_2) when is_number(value_1) and is_number(value_2) do
#     cond do
#       value_1 == value_2 -> :eq
#       value_1 < value_2 -> :lt
#       true -> :gt
#     end
#   end
#
#   defp list_bounds([{u1, _} | _] = l1st) do
#     start = Map.fetch!(unit_order(), u1)
#
#     [{u2, _} | _] = Enum.reverse(l1st)
#     finish = Map.fetch!(unit_order(), u2)
#
#     {start, finish}
#   end
# end
