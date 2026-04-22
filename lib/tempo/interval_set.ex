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
          intervals: [Interval.t()],
          metadata: map()
        }

  defstruct intervals: [], metadata: %{}

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
  @spec new([Interval.t()], keyword()) :: {:ok, t()} | {:error, term()}
  def new(intervals, opts \\ []) when is_list(intervals) do
    with :ok <- validate_all_bounded(intervals) do
      # `coalesce: false` is the default: IntervalSet preserves
      # member identity by design. Callers who want canonical
      # instant-set form (touching or overlapping intervals merged
      # into larger spans) must either pass `coalesce: true` here
      # or apply `coalesce/1` explicitly after construction.
      coalesce? = Keyword.get(opts, :coalesce, false)

      sorted = Enum.sort(intervals, &compare_from/2)
      final = if coalesce?, do: coalesce_intervals(sorted), else: sorted
      metadata = Keyword.get(opts, :metadata, %{})

      {:ok, %__MODULE__{intervals: final, metadata: metadata}}
    end
  end

  @doc """
  Raising version of `new/1`.
  """
  @spec new!([Interval.t()], keyword()) :: t()
  def new!(intervals, opts \\ []) do
    case new(intervals, opts) do
      {:ok, set} -> set
      {:error, reason} -> raise ArgumentError, inspect(reason)
    end
  end

  @doc """
  Return the member intervals as a plain list.

  The `Enumerable` protocol implementation for an IntervalSet
  walks every sub-point inside each interval (consistent with
  the Tempo and Tempo.Interval `Enumerable` implementations —
  every Tempo value is a span, iteration walks its sub-points at
  the next-finer resolution).

  When you want to operate on the **member intervals** instead
  — filter them, count them, map them — `to_list/1` gives you
  a plain list you can pipe into `Enum`.

  ### Examples

      iex> {:ok, set} = Tempo.IntervalSet.new([
      ...>   %Tempo.Interval{from: ~o"2026-06-01", to: ~o"2026-06-10"},
      ...>   %Tempo.Interval{from: ~o"2026-07-01", to: ~o"2026-07-10"}
      ...> ])
      iex> set |> Tempo.IntervalSet.to_list() |> length()
      2

  Pair with the interval predicates for expressive scheduling:

      set
      |> Tempo.IntervalSet.to_list()
      |> Enum.filter(&Tempo.at_least?(&1, ~o"PT1H"))

  """
  @spec to_list(t()) :: [Interval.t()]
  def to_list(%__MODULE__{intervals: intervals}), do: intervals

  @doc """
  Return the number of member intervals in the set.

  A named helper so callers never have to write
  `length(set.intervals)` or `length(to_list(set))` in
  user-facing code.

  ### Arguments

  * `set` is a `t:t/0`.

  ### Returns

  * The count of member intervals as a non-negative integer.

  ### Examples

      iex> set = Tempo.IntervalSet.new!([
      ...>   %Tempo.Interval{from: ~o"2026-06-01", to: ~o"2026-06-10"},
      ...>   %Tempo.Interval{from: ~o"2026-07-01", to: ~o"2026-07-10"}
      ...> ])
      iex> Tempo.IntervalSet.count(set)
      2

  """
  @spec count(t()) :: non_neg_integer()
  def count(%__MODULE__{intervals: intervals}), do: length(intervals)

  @doc """
  Apply `fun` to each member interval and return the results as
  a plain list.

  Unlike the `Enumerable` protocol for `IntervalSet` — which
  walks each sub-point inside every interval at the next-finer
  resolution — `map/2` operates on the **member intervals
  themselves**. It's the set-as-sequence-of-spans view.

  The result is a plain list, not an IntervalSet, because the
  mapper may return anything (integers, tuples, arbitrary values).

  ### Arguments

  * `set` is a `t:t/0`.

  * `fun` is a 1-arity function applied to each member
    `t:Tempo.Interval.t/0`.

  ### Returns

  * A list of whatever `fun` returns, in the set's sort order.

  ### Examples

      iex> set = Tempo.IntervalSet.new!([
      ...>   %Tempo.Interval{from: ~o"2026-06-15", to: ~o"2026-06-16"},
      ...>   %Tempo.Interval{from: ~o"2026-06-20", to: ~o"2026-06-21"}
      ...> ])
      iex> Tempo.IntervalSet.map(set, &Tempo.day/1)
      [15, 20]

  """
  @spec map(t(), (Interval.t() -> any())) :: [any()]
  def map(%__MODULE__{intervals: intervals}, fun) when is_function(fun, 1) do
    Enum.map(intervals, fun)
  end

  @doc """
  Keep only the member intervals for which `fun` returns `true`,
  returning a new `t:t/0`.

  ### Arguments

  * `set` is a `t:t/0`.

  * `fun` is a 1-arity predicate applied to each member
    `t:Tempo.Interval.t/0`.

  ### Returns

  * A new `t:t/0` containing only the members where `fun`
    returned a truthy value. The input's invariants (sorted,
    coalesced) are preserved — filtering cannot create overlap.

  ### Examples

      iex> set = Tempo.IntervalSet.new!([
      ...>   %Tempo.Interval{from: ~o"2026-06-15", to: ~o"2026-06-16"},
      ...>   %Tempo.Interval{from: ~o"2026-06-20", to: ~o"2026-06-25"}
      ...> ])
      iex> long = Tempo.IntervalSet.filter(set, &Tempo.at_least?(&1, ~o"P2D"))
      iex> Tempo.IntervalSet.count(long)
      1

  """
  @spec filter(t(), (Interval.t() -> as_boolean(any()))) :: t()
  def filter(%__MODULE__{intervals: intervals} = set, fun) when is_function(fun, 1) do
    %__MODULE__{set | intervals: Enum.filter(intervals, fun)}
  end

  @doc """
  Build the Allen-relation matrix between every member of `a`
  and every member of `b`.

  Allen's algebra is defined on pairs of intervals, not sets —
  two multi-member sets can relate several different ways
  simultaneously. `relation_matrix/2` returns the complete
  per-pair classification so you can reason about mixed
  conflicts, merge logic, or scheduling visualisations.

  ### Arguments

  * `a` and `b` are `t:t/0` (single intervals and Tempo points
    are coerced to single-member sets for convenience).

  ### Returns

  * `[{a_index, b_index, relation}]` — one tuple per pair.
    Indexes are 0-based into each set's `.intervals` list. The
    relation is one of `t:Tempo.Interval.relation/0`.

  * `{:error, reason}` when either input can't be reduced to an
    IntervalSet of bounded intervals.

  ### Examples

      iex> a = Tempo.IntervalSet.new!([
      ...>   %Tempo.Interval{from: ~o"2026-06-01", to: ~o"2026-06-03"},
      ...>   %Tempo.Interval{from: ~o"2026-06-05", to: ~o"2026-06-07"}
      ...> ], coalesce: false)
      iex> b = Tempo.IntervalSet.new!([
      ...>   %Tempo.Interval{from: ~o"2026-06-04", to: ~o"2026-06-06"}
      ...> ], coalesce: false)
      iex> Tempo.IntervalSet.relation_matrix(a, b)
      [{0, 0, :precedes}, {1, 0, :overlapped_by}]

  """
  # Dialyzer over-widens the return type when a `with` clause
  # has no explicit `else` — it includes the bound intermediate
  # `{:ok, IntervalSet{intervals: []}}` shape even though that
  # path always produces a list via the comprehension. The spec
  # below is humanly correct; suppress the warning rather than
  # widen the spec with a fictitious return.
  @dialyzer {:nowarn_function, relation_matrix: 2}

  @spec relation_matrix(t() | Interval.t() | Tempo.t(), t() | Interval.t() | Tempo.t()) ::
          [
            {non_neg_integer(), non_neg_integer(), Interval.relation() | {:error, term()}}
          ]
          | {:error, term()}
  def relation_matrix(a, b) do
    with {:ok, %__MODULE__{intervals: a_ivs}} <- coerce(a),
         {:ok, %__MODULE__{intervals: b_ivs}} <- coerce(b) do
      for {iv_a, ai} <- Enum.with_index(a_ivs),
          {iv_b, bi} <- Enum.with_index(b_ivs) do
        {ai, bi, Interval.compare(iv_a, iv_b)}
      end
    end
  end

  defp coerce(%__MODULE__{} = set), do: {:ok, set}
  defp coerce(%Interval{} = iv), do: new([iv], coalesce: false)
  defp coerce(%Tempo{} = point), do: Tempo.to_interval_set(point)

  defp coerce(other) do
    {:error, Tempo.ConversionError.exception(value: other, target: Tempo.IntervalSet)}
  end

  ## Validation

  defp validate_all_bounded(intervals) do
    Enum.reduce_while(intervals, :ok, fn interval, :ok ->
      case bounded?(interval) do
        true ->
          {:cont, :ok}

        false ->
          {:halt,
           {:error,
            Tempo.IntervalEndpointsError.exception(
              interval: interval,
              operation: "include open-ended interval in a set"
            )}}
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

  ## ---------------------------------------------------------
  ## Coalesce — canonical instant-set form
  ## ---------------------------------------------------------

  @doc """
  Merge touching or overlapping member intervals into larger
  spans, returning a new `t:t/0` in **canonical instant-set
  form**.

  `IntervalSet` preserves member identity by default — each
  interval stays a distinct member with its own metadata. That
  shape is right for event management, bookings, and any query
  that asks about individual members.

  Some questions are about the *instants covered* by the set,
  not the members: "is this point covered?", "what's the total
  duration?", "are these two schedules equivalent?". For those,
  the canonical instant-set form is the right shape — two
  touching intervals merge into one, and the set has exactly
  one member per contiguous covered region.

  Under the half-open `[from, to)` convention, intervals merge
  when the later one's `from` is at or before the earlier one's
  `to`. Touching (`[a, b) ++ [b, c) == [a, c)`) and overlapping
  cases both merge.

  ### Metadata

  When two members merge, the earlier member's metadata is kept
  on the merged span and the later member's is dropped. If
  metadata matters for your query, filter or project before
  coalescing.

  ### Arguments

  * `set` is a `t:t/0`.

  ### Returns

  * A `t:t/0` with touching and overlapping intervals merged.

  ### Examples

      iex> set = Tempo.IntervalSet.new!([
      ...>   %Tempo.Interval{from: ~o"2026-06-15", to: ~o"2026-06-16"},
      ...>   %Tempo.Interval{from: ~o"2026-06-16", to: ~o"2026-06-17"}
      ...> ])
      iex> Tempo.IntervalSet.count(set)
      2
      iex> coalesced = Tempo.IntervalSet.coalesce(set)
      iex> Tempo.IntervalSet.count(coalesced)
      1

  """
  @spec coalesce(t()) :: t()
  def coalesce(%__MODULE__{intervals: intervals} = set) do
    %{set | intervals: coalesce_intervals(intervals)}
  end

  @doc """
  `true` when any member interval of `set` covers `point`.

  Coalesces internally — a point is "covered" iff it falls inside
  at least one member span. For the common booking/scheduling
  question "is this slot occupied?", this is the right predicate.

  ### Arguments

  * `set` is a `t:t/0`.

  * `point` is any `t:Tempo.t/0`.

  ### Returns

  * `true` or `false`.

  ### Examples

      iex> set = Tempo.IntervalSet.new!([
      ...>   %Tempo.Interval{from: ~o"2026-06-15", to: ~o"2026-06-20"}
      ...> ])
      iex> Tempo.IntervalSet.covered?(set, ~o"2026-06-17")
      true
      iex> Tempo.IntervalSet.covered?(set, ~o"2026-06-25")
      false

  """
  @spec covered?(t(), Tempo.t()) :: boolean()
  def covered?(%__MODULE__{intervals: intervals}, %Tempo{} = point) do
    Enum.any?(intervals, fn interval -> Tempo.Interval.within?(point, interval) end)
  end

  @doc """
  Total duration covered by the set's members, as a
  `t:Tempo.Duration.t/0`.

  Coalesces internally so overlapping members are not
  double-counted — the returned duration is the length of the
  union of covered instants, not the sum of individual member
  durations. For the "sum of member durations" semantics, use
  `map(set, &Tempo.Interval.duration/1) |> Enum.sum()` with
  explicit arithmetic.

  ### Arguments

  * `set` is a `t:t/0`.

  ### Returns

  * A `t:Tempo.Duration.t/0`.

  ### Examples

      iex> set = Tempo.IntervalSet.new!([
      ...>   %Tempo.Interval{from: ~o"2026-06-15T09:00:00", to: ~o"2026-06-15T10:00:00"},
      ...>   %Tempo.Interval{from: ~o"2026-06-15T11:00:00", to: ~o"2026-06-15T12:00:00"}
      ...> ])
      iex> Tempo.IntervalSet.total_duration(set)
      ~o"PT7200S"

  """
  @spec total_duration(t()) :: Tempo.Duration.t()
  def total_duration(%__MODULE__{} = set) do
    set
    |> coalesce()
    |> Map.fetch!(:intervals)
    |> Enum.reduce(Tempo.Duration.new([]), fn interval, acc ->
      add_durations(acc, Tempo.Interval.duration(interval))
    end)
  end

  defp add_durations(%Tempo.Duration{time: a}, %Tempo.Duration{time: b}) do
    merged =
      Keyword.merge(a, b, fn _key, v1, v2 -> v1 + v2 end)

    Tempo.Duration.new(merged)
  end

  # Single forward pass. At each step, decide whether the next
  # interval should merge with the current "accumulator" interval
  # (overlap OR touch) or start a new span. Half-open semantics:
  # `[a, b)` and `[b, c)` touch at `b` and merge to `[a, c)`.
  #
  # Private helper used by `new/2` (when `coalesce: true` is
  # passed) and by the public `coalesce/1` wrapper above.

  defp coalesce_intervals([]), do: []

  defp coalesce_intervals([interval | rest]) do
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
