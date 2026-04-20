defmodule Tempo.IntervalSet do
  @moduledoc """
  A sorted, non-overlapping, coalesced list of `t:Tempo.Interval.t/0`
  values — the multi-interval counterpart to `Tempo.Interval`.

  `IntervalSet` is the operational form for set operations. Every
  AST shape that expands to a disjoint list of bounded spans
  (non-contiguous masks, stepped ranges, iterated groups, bounded
  recurrences, all-of sets) materialises to an `IntervalSet` via
  `Tempo.to_interval/1`.

  ## Invariants

  The constructor `new/1` guarantees:

  * Intervals are sorted ascending by `from`.

  * Adjacent or overlapping intervals are coalesced. Half-open
    semantics means `[a, b) ++ [b, c) == [a, c)` — the coalesce
    pass merges both overlap and touch cases.

  * No `:undefined` endpoints. (Open-ended intervals cannot
    participate in a set; the caller must bound them first.)

  ## Timezone handling

  An IntervalSet preserves the wall-clock + zone form of its member
  intervals on the struct. Any set operation that needs to compare
  endpoints across zones derives a UTC projection on demand; no
  UTC cache is stored on the struct. This keeps results stable when
  `Tzdata` updates — re-running the operation simply uses whatever
  zone rules are current at the time of the call.

  See `guides/enumeration-semantics.md` for the full discussion of
  wall-clock-vs-UTC authority.

  """

  alias Tempo.Interval

  @type t :: %__MODULE__{
          intervals: [Interval.t()]
        }

  defstruct intervals: []

  @doc """
  Construct a `t:t/0` from a list of intervals.

  The input list is sorted ascending by `from` endpoint and
  coalesced — adjacent or overlapping intervals are merged under
  the half-open `[from, to)` convention.

  ### Arguments

  * `intervals` is a list of `t:Tempo.Interval.t/0` values. Open-
    ended intervals (`from: :undefined` or `to: :undefined`) are
    rejected.

  ### Returns

  * `{:ok, interval_set}` where `interval_set` is a `t:t/0`, or

  * `{:error, reason}` when an input interval is open-ended or
    otherwise cannot participate in a set.

  ### Examples

      iex> {:ok, a} = Tempo.to_interval(~o"2022Y1M")
      iex> {:ok, b} = Tempo.to_interval(~o"2022Y3M")
      iex> {:ok, set} = Tempo.IntervalSet.new([b, a])
      iex> length(set.intervals)
      2
      iex> hd(set.intervals).from.time
      [year: 2022, month: 1, day: 1]

  """
  @spec new([Interval.t()]) :: {:ok, t()} | {:error, term()}
  def new(intervals) when is_list(intervals) do
    with :ok <- validate_all_bounded(intervals) do
      sorted =
        intervals
        |> Enum.sort(&compare_from/2)
        |> coalesce()

      {:ok, %__MODULE__{intervals: sorted}}
    end
  end

  @doc """
  Raising version of `new/1`.
  """
  @spec new!([Interval.t()]) :: t()
  def new!(intervals) do
    case new(intervals) do
      {:ok, set} -> set
      {:error, reason} -> raise ArgumentError, inspect(reason)
    end
  end

  ## Validation

  defp validate_all_bounded(intervals) do
    Enum.reduce_while(intervals, :ok, fn interval, :ok ->
      case bounded?(interval) do
        true -> {:cont, :ok}
        false -> {:halt, {:error, "Cannot include open-ended interval in a set: #{inspect(interval)}"}}
      end
    end)
  end

  defp bounded?(%Interval{from: from, to: to})
       when from == :undefined or to == :undefined,
       do: false

  defp bounded?(%Interval{}), do: true

  ## Ordering

  # Sort ascending by `from` endpoint. Ties break by `to` (shorter
  # first) so that a pointwise interval comes before a longer one
  # sharing the same start — matches intuition and makes the
  # coalesce pass deterministic.

  defp compare_from(%Interval{from: a_from, to: a_to}, %Interval{from: b_from, to: b_to}) do
    case compare_time(a_from.time, b_from.time) do
      :lt -> true
      :gt -> false
      :eq -> compare_time(a_to.time, b_to.time) != :gt
    end
  end

  # Compare two time keyword lists as start-moments, padding
  # missing trailing units with their unit minimum. Mirrors the
  # helper in `Enumerable.Tempo.Interval` — kept local here to
  # avoid a cross-module dependency.

  defp compare_time([], []), do: :eq

  defp compare_time([{unit, v} | rest], []) do
    min = unit_minimum(unit)

    cond do
      v < min -> :lt
      v > min -> :gt
      true -> compare_time(rest, [])
    end
  end

  defp compare_time([], [{unit, v} | rest]) do
    min = unit_minimum(unit)

    cond do
      min < v -> :lt
      min > v -> :gt
      true -> compare_time([], rest)
    end
  end

  defp compare_time([{unit, v1} | t1], [{unit, v2} | t2]) do
    cond do
      v1 < v2 -> :lt
      v1 > v2 -> :gt
      true -> compare_time(t1, t2)
    end
  end

  defp compare_time(_, _), do: :eq

  defp unit_minimum(:month), do: 1
  defp unit_minimum(:day), do: 1
  defp unit_minimum(:week), do: 1
  defp unit_minimum(:day_of_year), do: 1
  defp unit_minimum(:day_of_week), do: 1
  defp unit_minimum(_), do: 0

  ## Coalesce

  # Single forward pass. At each step, decide whether the next
  # interval should merge with the current "accumulator" interval
  # (overlap OR touch) or start a new span. Half-open semantics:
  # `[a, b)` and `[b, c)` touch at `b` and merge to `[a, c)`.

  defp coalesce([]), do: []

  defp coalesce([interval | rest]) do
    coalesce_step(rest, [interval])
  end

  defp coalesce_step([], acc), do: Enum.reverse(acc)

  defp coalesce_step([next | rest], [current | tail] = acc) do
    case merge_if_touching(current, next) do
      {:merged, merged} ->
        coalesce_step(rest, [merged | tail])

      :separate ->
        coalesce_step(rest, [next | acc])
    end
  end

  # Two intervals merge if the later one starts at or before the
  # earlier one's end. Under `[from, to)`:
  # * `next.from < current.to` → overlap
  # * `next.from == current.to` → touch (half-open concatenation)
  # In both cases the merged interval spans from `current.from` to
  # `max(current.to, next.to)`.

  defp merge_if_touching(%Interval{} = current, %Interval{} = next) do
    case compare_time(next.from.time, current.to.time) do
      order when order in [:lt, :eq] ->
        merged_to =
          case compare_time(next.to.time, current.to.time) do
            :gt -> next.to
            _ -> current.to
          end

        {:merged, %{current | to: merged_to}}

      :gt ->
        :separate
    end
  end
end
