defmodule Tempo.IntervalSet.Backend.List do
  @moduledoc """
  The default `Tempo.IntervalSet.Backend`: a sorted, disjoint plain
  list of member intervals.

  The backend state is the member list itself, so a struct literal
  `%Tempo.IntervalSet{intervals: [...]}` is a valid list-backed set and
  two list-backed sets with the same members compare equal with `==`.
  Construction is O(n log n) (the sort in `Tempo.IntervalSet.new/2`),
  the walk is the list, and every query is a linear scan — the right
  trade for the small-to-medium sets that dominate ordinary use.

  """

  use Tempo.IntervalSet.Backend

  @impl true
  def from_list(intervals, _options), do: intervals

  @impl true
  def to_list(state), do: state

  @impl true
  def walk(state), do: state

  @impl true
  def bounded?(_state), do: true

  @impl true
  def count(state), do: length(state)

  @impl true
  def empty?(state), do: state == []

  @impl true
  def first([]), do: nil
  def first([first | _rest]), do: first
end
