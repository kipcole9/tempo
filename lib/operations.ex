defmodule Tempo.Operations do
  @moduledoc """
  Set operations on Tempo values — union, intersection,
  complement, difference, symmetric difference — plus the
  companion predicates (`disjoint?/2`, `overlaps?/2`,
  `subset?/2`, `contains?/2`, `equal?/2`).

  Every operation accepts any Tempo value (implicit `%Tempo{}`,
  `%Tempo.Interval{}`, `%Tempo.IntervalSet{}`, or all-of
  `%Tempo.Set{}`) and routes through `align/2,3` — a single
  preflight that normalises operands to a common anchor class,
  resolution, calendar, and (where relevant) UTC reference frame.
  Set-op results are always `%Tempo.IntervalSet{}`; predicate
  results are booleans.

  See `plans/set-operations.md` for the design rationale
  including:

  * why IntervalSet (not rule-algebra) is the operational form,
  * how timezones and DST are handled,
  * why the `:bound` option is required for some operand
    combinations,
  * and the axis-compatibility rule (anchored vs non-anchored).

  The top-level user API lives on `Tempo` via delegation — callers
  should prefer `Tempo.union/2`, `Tempo.intersection/2`, etc. over
  calling `Tempo.Operations` directly.

  """

  alias Tempo.{Compare, Interval, IntervalSet}

  ## ---------------------------------------------------------------
  ## Preflight — `align/2,3`
  ## ---------------------------------------------------------------

  @doc """
  Normalise two operands to the same anchor class, resolution,
  and calendar, and return them both as `%Tempo.IntervalSet{}`.

  ### Arguments

  * `a` and `b` are any Tempo values that can be materialised to
    an interval set — `%Tempo{}`, `%Tempo.Interval{}`,
    `%Tempo.IntervalSet{}`, or `%Tempo.Set{type: :all}`.

  ### Options

  * `:bound` — a Tempo value (any of the above types) that
    bounds non-anchored or otherwise unbounded operands. Required
    when `a` and `b` belong to different anchor classes.

  ### Returns

  * `{:ok, {aligned_a, aligned_b}}` where both are `%Tempo.IntervalSet{}`.

  * `{:error, reason}` when a preflight check fails (duration
    operand, one-of set operand, incompatible anchor classes
    without `:bound`, calendar mismatch, etc.).

  """
  @spec align(operand, operand, keyword()) ::
          {:ok, {IntervalSet.t(), IntervalSet.t()}} | {:error, term()}
        when operand:
               Tempo.t()
               | Interval.t()
               | IntervalSet.t()
               | Tempo.Set.t()
  def align(a, b, opts \\ []) do
    with :ok <- validate_operand(a),
         :ok <- validate_operand(b),
         {:ok, class_a, class_b} <- compatible_classes(a, b, opts),
         {:ok, a_set} <- to_aligned_set(a, class_a, opts),
         {:ok, b_set} <- to_aligned_set(b, class_b, opts),
         {:ok, a_set, b_set} <- maybe_anchor_to_bound(a_set, b_set, class_a, class_b, opts),
         {:ok, a_set, b_set} <- maybe_split_midnight_crossers(a_set, b_set, class_a, class_b),
         {:ok, b_set} <- convert_calendar(b_set, a_set),
         {:ok, a_set, b_set} <- align_resolution(a_set, b_set) do
      {:ok, {a_set, b_set}}
    end
  end

  ## Midnight-crossing normalisation for time-of-day set ops.
  ##
  ## A non-anchored interval like `T23:30/T01:00` represents a
  ## 1.5-hour span that wraps around midnight on the time-of-day
  ## axis. For set operations to sweep-line cleanly, split any
  ## such interval into two non-wrapping sub-intervals:
  ##
  ##     [T23:30, T24:00) ∪ [T00:00, T01:00)
  ##
  ## The split only runs when both operands are non-anchored.
  ## Anchored intervals that cross midnight (after materialisation
  ## to a specific day) are already concrete — they live on the
  ## universal time line and their endpoints don't wrap.

  defp maybe_split_midnight_crossers(a, b, :non_anchored, :non_anchored) do
    {:ok, split_crossers(a), split_crossers(b)}
  end

  defp maybe_split_midnight_crossers(a, b, _class_a, _class_b), do: {:ok, a, b}

  defp split_crossers(%IntervalSet{intervals: intervals} = set) do
    split = Enum.flat_map(intervals, &maybe_split/1)

    case IntervalSet.new(split) do
      {:ok, sorted} -> sorted
      # Should never error — split intervals are always bounded.
      # Fall back to unsorted form rather than raise.
      _ -> %{set | intervals: split}
    end
  end

  defp maybe_split(%Interval{from: from, to: to} = interval) do
    if crosses_midnight?(from, to) do
      [
        %Interval{from: from, to: %{from | time: end_of_day_time(from.time)}},
        %Interval{from: %{to | time: start_of_day_time(to.time)}, to: to}
      ]
    else
      [interval]
    end
  end

  # For a time-of-day keyword list, replace `:hour` with 24 and
  # everything finer with 0 — yields a synthetic midnight-upper
  # endpoint that `compare_time/2` treats as later than any
  # `[hour: 23, minute: X, ...]` value.
  defp end_of_day_time(time) do
    Enum.map(time, fn
      {:hour, _} -> {:hour, 24}
      {unit, _} -> {unit, 0}
    end)
  end

  # Zero out every time-of-day unit — yields the start-of-day
  # endpoint for the second half of a midnight-crossing interval.
  defp start_of_day_time(time) do
    Enum.map(time, fn {unit, _} -> {unit, 0} end)
  end

  ## Cross-axis materialisation — when one operand is
  ## non-anchored and a `:bound` is supplied, anchor the
  ## non-anchored operand to every day in the bound.
  ##
  ## v1 scope: the non-anchored operand's intervals must not
  ## cross midnight (i.e. `from` and `to` share a wall-clock day).
  ## A Tempo like `T10:30` materialises cleanly to an hour- or
  ## minute-slot that fits within a single day.

  defp maybe_anchor_to_bound(a, b, class_a, class_b, _opts)
       when class_a == class_b,
       do: {:ok, a, b}

  defp maybe_anchor_to_bound(a, b, :empty, _class_b, _opts), do: {:ok, a, b}
  defp maybe_anchor_to_bound(a, b, _class_a, :empty, _opts), do: {:ok, a, b}

  defp maybe_anchor_to_bound(a, b, class_a, class_b, opts) do
    bound = Keyword.fetch!(opts, :bound)

    with {:ok, bound_set} <- Tempo.to_interval_set(bound) do
      if anchor_class(bound_set) != :anchored do
        {:error,
         "The `:bound` must be anchored (have a year component). " <>
           "A non-anchored bound cannot materialise a time-of-day operand."}
      else
        a_anchored = if class_a == :non_anchored, do: anchor_to_days(a, bound_set), else: {:ok, a}
        b_anchored = if class_b == :non_anchored, do: anchor_to_days(b, bound_set), else: {:ok, b}

        with {:ok, a2} <- a_anchored,
             {:ok, b2} <- b_anchored do
          {:ok, a2, b2}
        end
      end
    end
  end

  # For each interval in the bound, walk each day, and anchor
  # every non-anchored interval to that day. Returns {:ok,
  # IntervalSet} or {:error, _}.

  defp anchor_to_days(%IntervalSet{} = non_anchored_set, %IntervalSet{} = bound_set) do
    materialised =
      for bound_interval <- bound_set.intervals,
          day_tempo <- days_in(bound_interval),
          na_interval <- non_anchored_set.intervals do
        anchor_interval_to_day(na_interval, day_tempo)
      end

    IntervalSet.new(materialised)
  end

  # Iterate wall-clock days within a bound interval. Each yielded
  # value is a %Tempo{} with year/month/day filled in.
  defp days_in(%Interval{from: from, to: to}) do
    from_day = trunc_to_day(from)
    to_day = trunc_to_day(to)
    calendar = from.calendar

    Stream.unfold(from_day, fn day ->
      if Compare.compare_time(day.time, to_day.time) == :lt do
        next_time = Tempo.Math.add_unit(day.time, :day, calendar)
        {day, %{day | time: next_time}}
      else
        nil
      end
    end)
    |> Enum.to_list()
  end

  defp trunc_to_day(%Tempo{time: time} = tempo) do
    year = Keyword.fetch!(time, :year)
    month = Keyword.get(time, :month, 1)
    day = Keyword.get(time, :day, 1)
    %{tempo | time: [year: year, month: month, day: day]}
  end

  defp anchor_interval_to_day(
         %Interval{from: na_from, to: na_to},
         %Tempo{time: day_time, calendar: calendar}
       ) do
    if crosses_midnight?(na_from, na_to) do
      # Non-anchored interval like `T23:30/T01:00` anchored to
      # day D → `[D T23:30, (D+1) T01:00)`. Advance `to`'s day.
      next_day_time = Tempo.Math.add_unit(day_time, :day, calendar)
      new_from = %{na_from | time: day_time ++ na_from.time}
      new_to = %{na_to | time: next_day_time ++ na_to.time}
      %Interval{from: new_from, to: new_to}
    else
      new_from = %{na_from | time: day_time ++ na_from.time}
      new_to = %{na_to | time: day_time ++ na_to.time}
      %Interval{from: new_from, to: new_to}
    end
  end

  # A non-anchored interval "crosses midnight" when its `from`
  # time-of-day is at or after its `to` time-of-day — e.g.
  # `T23:30/T01:00`. Zero-width cases (`from == to`) are treated
  # as not crossing.
  defp crosses_midnight?(%Tempo{time: from_time}, %Tempo{time: to_time}) do
    Compare.compare_time(from_time, to_time) == :gt
  end

  ## Operand validation — reject durations and one-of sets up-front.

  defp validate_operand(%Tempo.Duration{}) do
    {:error,
     "Cannot apply set operations to a Tempo.Duration — " <>
       "a duration is a length, not a set of instants. Anchor it first " <>
       "(e.g. `1985-01/P3M` or `P1M/1985-06`) via an interval."}
  end

  defp validate_operand(%Tempo.Set{type: :one}) do
    {:error,
     "Cannot apply set operations to a one-of Tempo.Set " <>
       "(epistemic disjunction). Pick a specific member or handle the " <>
       "disjunction in calling code."}
  end

  defp validate_operand(_), do: :ok

  ## Anchor-class detection and compatibility check.

  defp compatible_classes(a, b, opts) do
    class_a = anchor_class(a)
    class_b = anchor_class(b)
    bound = Keyword.get(opts, :bound)

    cond do
      class_a == :empty ->
        {:ok, class_b, class_b}

      class_b == :empty ->
        {:ok, class_a, class_a}

      class_a == class_b ->
        {:ok, class_a, class_b}

      bound != nil ->
        {:ok, class_a, class_b}

      true ->
        {:error,
         "Set operations between a #{class_a} operand and a #{class_b} operand " <>
           "require a `:bound` option to anchor the non-anchored side. Alternatively, " <>
           "use `Tempo.anchor/2` to combine a date-like value with a time-of-day " <>
           "value before the operation."}
    end
  end

  # Classify a value's anchor class. `:anchored` = has year-level
  # position; `:non_anchored` = time-of-day only; `:empty` = empty
  # IntervalSet (identity element, compatible with any class).

  defp anchor_class(%IntervalSet{intervals: []}), do: :empty

  defp anchor_class(%IntervalSet{intervals: [first | _]}) do
    anchor_class(first)
  end

  defp anchor_class(%Interval{from: %Tempo{} = from}), do: anchor_class(from)
  defp anchor_class(%Interval{to: %Tempo{} = to}), do: anchor_class(to)
  defp anchor_class(%Interval{}), do: :empty

  defp anchor_class(%Tempo.Set{set: [first | _]}), do: anchor_class(first)
  defp anchor_class(%Tempo.Set{set: []}), do: :empty

  defp anchor_class(%Tempo{} = tempo) do
    if Tempo.anchored?(tempo), do: :anchored, else: :non_anchored
  end

  ## Conversion to IntervalSet.

  defp to_aligned_set(%IntervalSet{} = set, _class, _opts), do: {:ok, set}

  defp to_aligned_set(other, _class, _opts) do
    case Tempo.to_interval_set(other) do
      {:ok, %IntervalSet{} = set} -> {:ok, set}
      {:error, _} = err -> err
    end
  end

  ## Calendar alignment — second operand converts to first's
  ## calendar. Non-anchored intervals (pure time-of-day) skip this
  ## step because their time components are calendar-independent.
  ##
  ## For anchored intervals, we extend every endpoint to day+
  ## resolution, convert year/month/day via `Date.convert!/2`, and
  ## preserve hour/minute/second (those don't change under
  ## calendar conversion). The converted struct's `:calendar` is
  ## updated to match the target.

  defp convert_calendar(%IntervalSet{intervals: []} = empty, _other), do: {:ok, empty}

  defp convert_calendar(%IntervalSet{intervals: [b_first | _]} = b_set, %IntervalSet{
         intervals: [a_first | _]
       }) do
    a_cal = endpoint_calendar(a_first)
    b_cal = endpoint_calendar(b_first)

    cond do
      a_cal == b_cal ->
        {:ok, b_set}

      # Non-anchored intervals don't have calendar-bound components;
      # their time-of-day units work the same in any calendar.
      not Tempo.anchored?(b_first.from) ->
        {:ok, b_set}

      true ->
        convert_calendar_intervals(b_set, a_cal)
    end
  end

  defp convert_calendar(b_set, _a_set), do: {:ok, b_set}

  defp endpoint_calendar(%Interval{from: %Tempo{calendar: cal}}), do: cal
  defp endpoint_calendar(%Interval{to: %Tempo{calendar: cal}}), do: cal
  defp endpoint_calendar(_), do: nil

  defp convert_calendar_intervals(%IntervalSet{intervals: intervals} = set, target_calendar) do
    converted =
      Enum.map(intervals, fn %Interval{from: from, to: to} = interval ->
        %{
          interval
          | from: convert_tempo_calendar(from, target_calendar),
            to: convert_tempo_calendar(to, target_calendar)
        }
      end)

    {:ok, %{set | intervals: converted}}
  end

  # Convert a single %Tempo{}'s year/month/day into the target
  # calendar. Non-anchored Tempos (no :year) pass through
  # unchanged — their components are calendar-independent.
  defp convert_tempo_calendar(%Tempo{} = tempo, target_calendar) do
    if Tempo.anchored?(tempo) do
      source_calendar = tempo.calendar

      # Extend to day precision so we have year/month/day to
      # feed Date.convert.
      extended =
        case Tempo.extend_resolution(tempo, :day) do
          %Tempo{} = ext -> ext
          _ -> tempo
        end

      year = Keyword.fetch!(extended.time, :year)
      month = Keyword.fetch!(extended.time, :month)
      day = Keyword.fetch!(extended.time, :day)

      src_date = Date.new!(year, month, day, source_calendar)
      tgt_date = Date.convert!(src_date, target_calendar)

      # Preserve any hour/minute/second on the input.
      time_tail =
        extended.time
        |> Enum.drop_while(fn {k, _} -> k not in [:hour, :minute, :second] end)

      new_time =
        [year: tgt_date.year, month: tgt_date.month, day: tgt_date.day] ++ time_tail

      %{extended | time: new_time, calendar: target_calendar}
    else
      tempo
    end
  end

  ## Resolution alignment — extend the coarser operand's endpoints
  ## to the finer resolution.

  defp align_resolution(%IntervalSet{intervals: []} = a, b), do: {:ok, a, b}
  defp align_resolution(a, %IntervalSet{intervals: []} = b), do: {:ok, a, b}

  defp align_resolution(a_set, b_set) do
    a_res = finest_resolution(a_set)
    b_res = finest_resolution(b_set)

    target =
      case Tempo.Iso8601.Unit.compare(a_res, b_res) do
        :lt -> a_res
        _ -> b_res
      end

    with {:ok, a_aligned} <- apply_resolution(a_set, target),
         {:ok, b_aligned} <- apply_resolution(b_set, target) do
      {:ok, a_aligned, b_aligned}
    end
  end

  defp finest_resolution(%IntervalSet{intervals: intervals}) do
    intervals
    |> Enum.flat_map(fn %Interval{from: from, to: to} ->
      [Tempo.resolution(from), Tempo.resolution(to)]
    end)
    |> Enum.map(fn {unit, _span} -> unit end)
    |> Enum.min_by(&Tempo.Iso8601.Unit.sort_key/1, fn -> :day end)
  end

  defp apply_resolution(%IntervalSet{intervals: intervals} = set, target) do
    aligned =
      Enum.map(intervals, fn %Interval{from: from, to: to} = interval ->
        %{
          interval
          | from: extend_or_pass(from, target),
            to: extend_or_pass(to, target)
        }
      end)

    {:ok, %{set | intervals: aligned}}
  end

  defp extend_or_pass(%Tempo{} = tempo, target) do
    {current, _} = Tempo.resolution(tempo)

    case Tempo.Iso8601.Unit.compare(target, current) do
      :eq -> tempo
      :gt -> tempo
      :lt -> Tempo.extend_resolution(tempo, target)
    end
  end

  ## ---------------------------------------------------------------
  ## Core set operations
  ## ---------------------------------------------------------------

  @doc """
  Union of two operands — every instant in either operand.

  See the module doc and `plans/set-operations.md` for operand
  requirements.
  """
  @spec union(operand :: any(), operand :: any(), keyword()) ::
          {:ok, IntervalSet.t()} | {:error, term()}
  def union(a, b, opts \\ []) do
    with {:ok, {a_set, b_set}} <- align(a, b, opts) do
      IntervalSet.new(a_set.intervals ++ b_set.intervals)
    end
  end

  @doc """
  Intersection of two operands — every instant present in both.
  """
  @spec intersection(any(), any(), keyword()) ::
          {:ok, IntervalSet.t()} | {:error, term()}
  def intersection(a, b, opts \\ []) do
    with {:ok, {a_set, b_set}} <- align(a, b, opts) do
      IntervalSet.new(sweep_intersection(a_set.intervals, b_set.intervals))
    end
  end

  # Sweep-line intersection of two sorted interval lists. Each
  # step finds the overlap between the current A and current B
  # interval; if non-empty, add to the result; then advance
  # whichever interval ends first (it can't contribute more).

  defp sweep_intersection([], _b), do: []
  defp sweep_intersection(_a, []), do: []

  defp sweep_intersection([%Interval{} = a | a_rest], [%Interval{} = b | b_rest]) do
    overlap_from = later_endpoint(a.from, b.from)
    overlap_to = earlier_endpoint(a.to, b.to)

    case Compare.compare_endpoints(overlap_from, overlap_to) do
      :earlier ->
        [%Interval{from: overlap_from, to: overlap_to} | advance(a, a_rest, b, b_rest)]

      _ ->
        advance(a, a_rest, b, b_rest)
    end
  end

  # Advance whichever interval ends first — the other might
  # overlap more later.
  defp advance(a, a_rest, b, b_rest) do
    case Compare.compare_endpoints(a.to, b.to) do
      :later -> sweep_intersection([a | a_rest], b_rest)
      _ -> sweep_intersection(a_rest, [b | b_rest])
    end
  end

  defp later_endpoint(x, y) do
    case Compare.compare_endpoints(x, y) do
      :later -> x
      _ -> y
    end
  end

  defp earlier_endpoint(x, y) do
    case Compare.compare_endpoints(x, y) do
      :earlier -> x
      _ -> y
    end
  end

  @doc """
  Complement of `set` within `bound` — every instant in `bound`
  that is NOT in `set`.

  The `:bound` option is **required**. An unbounded complement
  is conceptually infinite; Tempo refuses to pick a universe
  implicitly.

  ### Options

  * `:bound` — the universe to complement within. Any Tempo
    value. Required.

  """
  @spec complement(any(), keyword()) :: {:ok, IntervalSet.t()} | {:error, term()}
  def complement(set, opts) do
    case Keyword.get(opts, :bound) do
      nil ->
        {:error,
         "`complement/2` requires an explicit `:bound` option. " <>
           "An unbounded complement is infinite; supply the universe to complement within."}

      bound ->
        difference(bound, set, opts)
    end
  end

  @doc """
  Difference `a \\ b` — every instant in `a` that is NOT in `b`.
  """
  @spec difference(any(), any(), keyword()) ::
          {:ok, IntervalSet.t()} | {:error, term()}
  def difference(a, b, opts \\ []) do
    with {:ok, {a_set, b_set}} <- align(a, b, opts) do
      IntervalSet.new(sweep_difference(a_set.intervals, b_set.intervals))
    end
  end

  # Sweep-line difference: for each A interval, walk through
  # B intervals that overlap it, emitting the uncovered portions.

  defp sweep_difference([], _b), do: []
  defp sweep_difference(a_list, []), do: a_list

  defp sweep_difference([%Interval{} = a | a_rest], b_list) do
    {emitted, remaining_b} = subtract_from(a, b_list)
    emitted ++ sweep_difference(a_rest, remaining_b)
  end

  # Subtract all overlapping B intervals from a single A interval.
  # Returns `{list_of_uncovered_parts_of_a, remaining_b_list}`.
  # The remaining B list is whatever B intervals haven't been
  # fully consumed (i.e. start at or after the current A's `from`
  # but also extend past A's `to`).

  defp subtract_from(%Interval{from: a_from, to: a_to}, []) do
    {maybe_emit(a_from, a_to), []}
  end

  defp subtract_from(%Interval{from: a_from, to: a_to}, [%Interval{} = b | b_rest]) do
    cond do
      # B is entirely before A — skip it.
      not after_or_eq?(b.to, a_from) ->
        subtract_from(%Interval{from: a_from, to: a_to}, b_rest)

      # B is entirely after A — no more overlaps; emit current A.
      not after_or_eq?(a_to, b.from) ->
        {[%Interval{from: a_from, to: a_to}], [b | b_rest]}

      # B starts inside A (or at its edge).
      true ->
        left = maybe_emit(a_from, b.from)
        rest_from = later_endpoint(b.to, a_from)

        cond do
          # B fully covers A's tail — stop emitting, B may extend further.
          not after_or_eq?(a_to, b.to) ->
            {left, [b | b_rest]}

          # B ends inside A — continue subtracting from the rest.
          true ->
            {right, remaining_b} =
              subtract_from(%Interval{from: rest_from, to: a_to}, b_rest)

            {left ++ right, remaining_b}
        end
    end
  end

  # Emit a one-interval list if `from < to`, empty otherwise.
  defp maybe_emit(from, to) do
    case Compare.compare_endpoints(from, to) do
      :earlier -> [%Interval{from: from, to: to}]
      _ -> []
    end
  end

  defp after_or_eq?(a, b) do
    Compare.compare_endpoints(a, b) != :earlier
  end

  @doc """
  Symmetric difference `a △ b` — instants in exactly one of
  `a` and `b`. Derived as `(a \\ b) ∪ (b \\ a)`.
  """
  @spec symmetric_difference(any(), any(), keyword()) ::
          {:ok, IntervalSet.t()} | {:error, term()}
  def symmetric_difference(a, b, opts \\ []) do
    with {:ok, a_minus_b} <- difference(a, b, opts),
         {:ok, b_minus_a} <- difference(b, a, opts) do
      IntervalSet.new(a_minus_b.intervals ++ b_minus_a.intervals)
    end
  end

  ## ---------------------------------------------------------------
  ## Predicates
  ## ---------------------------------------------------------------

  @doc """
  `true` when `a` and `b` share no instants.
  """
  @spec disjoint?(any(), any(), keyword()) :: boolean()
  def disjoint?(a, b, opts \\ []) do
    case intersection(a, b, opts) do
      {:ok, %IntervalSet{intervals: []}} -> true
      {:ok, _} -> false
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  `true` when `a` and `b` share at least one instant.
  """
  @spec overlaps?(any(), any(), keyword()) :: boolean()
  def overlaps?(a, b, opts \\ []), do: not disjoint?(a, b, opts)

  @doc """
  `true` when every instant of `a` is also in `b`.
  """
  @spec subset?(any(), any(), keyword()) :: boolean()
  def subset?(a, b, opts \\ []) do
    case difference(a, b, opts) do
      {:ok, %IntervalSet{intervals: []}} -> true
      {:ok, _} -> false
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  `true` when every instant of `b` is also in `a`. Alias for
  `subset?(b, a, opts)`.
  """
  @spec contains?(any(), any(), keyword()) :: boolean()
  def contains?(a, b, opts \\ []), do: subset?(b, a, opts)

  @doc """
  `true` when `a` and `b` span the same instants.
  """
  @spec equal?(any(), any(), keyword()) :: boolean()
  def equal?(a, b, opts \\ []) do
    with {:ok, {a_set, b_set}} <- align(a, b, opts) do
      a_set.intervals == b_set.intervals
    else
      {:error, reason} -> raise ArgumentError, reason
    end
  end
end
