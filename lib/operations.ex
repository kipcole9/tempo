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

  alias Tempo.Compare
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.Iso8601.Unit
  alias Tempo.MaterialisationError
  alias Tempo.Math
  alias Tempo.NonAnchoredError
  alias Tempo.ResolutionError
  alias Tempo.UnboundedRecurrenceError
  alias Tempo.Validation

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
         {:ok, a_set, b_set} <- canonicalize_axes(a_set, b_set),
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

    with {:ok, bound_set} <- Tempo.to_interval_set(bound),
         :ok <- ensure_anchored_bound(bound_set, bound),
         {:ok, a2} <- anchor_if_non_anchored(class_a, a, bound_set),
         {:ok, b2} <- anchor_if_non_anchored(class_b, b, bound_set) do
      {:ok, a2, b2}
    end
  end

  defp ensure_anchored_bound(bound_set, bound) do
    if anchor_class(bound_set) == :anchored do
      :ok
    else
      {:error, NonAnchoredError.exception(operation: "use as :bound", value: bound)}
    end
  end

  defp anchor_if_non_anchored(:non_anchored, value, bound_set),
    do: anchor_to_days(value, bound_set)

  defp anchor_if_non_anchored(_class, value, _bound_set), do: {:ok, value}

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
        next_time = Math.add_unit(day.time, :day, calendar)
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
      next_day_time = Math.add_unit(day_time, :day, calendar)
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

  defp validate_operand(%Tempo.Duration{} = value) do
    {:error,
     MaterialisationError.exception(
       value: value,
       reason: :bare_duration
     )}
  end

  defp validate_operand(%Tempo.Set{type: :one} = value) do
    {:error,
     MaterialisationError.exception(
       value: value,
       reason: :one_of_set
     )}
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

      # Two non-anchored operands only share a timeline when they sit on the
      # same resolution axis. `~o"1M31D"` (a month/day) and `~o"15D"` (a bare
      # day) recur on different cycles — annual vs monthly — so aligning them
      # would silently compare incomparable spans. Require a matching leading
      # unit; otherwise it needs an anchor, like the mixed-class case.
      class_a == :non_anchored and class_b == :non_anchored and not same_axis?(a, b) ->
        {:error,
         NonAnchoredError.exception(
           operation:
             "combine non-anchored operands on different resolution axes " <>
               "(leading #{inspect(leading_unit(a))} vs #{inspect(leading_unit(b))}) " <>
               "in a set operation (anchor them, or give both the same leading unit)"
         )}

      class_a == class_b ->
        {:ok, class_a, class_b}

      bound != nil ->
        {:ok, class_a, class_b}

      true ->
        {:error,
         NonAnchoredError.exception(
           operation:
             "combine a #{class_a} operand with a #{class_b} operand " <>
               "in a set operation (use a `:bound` option, or anchor the " <>
               "non-anchored side via `Tempo.anchor/2`)"
         )}
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

  # Two non-anchored operands are comparable only when they lead with the same
  # (coarsest) unit — the axis they recur on. A bare-day value has no month, so
  # it cannot be placed against a month/day value.
  defp same_axis?(a, b), do: leading_unit(a) == leading_unit(b)

  defp leading_unit(%IntervalSet{intervals: [first | _]}), do: leading_unit(first)
  defp leading_unit(%IntervalSet{intervals: []}), do: nil
  defp leading_unit(%Interval{from: %Tempo{} = from}), do: leading_unit(from)
  defp leading_unit(%Interval{to: %Tempo{} = to}), do: leading_unit(to)
  defp leading_unit(%Interval{}), do: nil
  defp leading_unit(%Tempo.Set{set: [first | _]}), do: leading_unit(first)
  defp leading_unit(%Tempo{time: [{unit, _value} | _]}), do: unit
  defp leading_unit(_other), do: nil

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

  ## Axis canonicalisation — week-axis endpoints
  ## (`[year, week, day_of_week]`) have no common unit vocabulary
  ## with month-axis endpoints (`[year, month, day]`), so the
  ## sweep cannot compare them. When exactly one operand is
  ## week-axis, rewrite its endpoints as month-axis calendar dates
  ## via `Tempo.Validation.resolve/2` (ISO week semantics,
  ## converted into the endpoint's own calendar). Same-axis pairs
  ## pass through untouched — week-on-week set operations stay on
  ## the week axis.

  defp canonicalize_axes(a_set, b_set) do
    case {week_axis?(a_set), week_axis?(b_set)} do
      {true, false} -> month_axis_operands(a_set, b_set, :first)
      {false, true} -> month_axis_operands(a_set, b_set, :second)
      _same_axis -> {:ok, a_set, b_set}
    end
  end

  defp month_axis_operands(a_set, b_set, :first) do
    with {:ok, converted} <- map_endpoints(a_set, &month_axis_endpoint/1) do
      {:ok, converted, b_set}
    end
  end

  defp month_axis_operands(a_set, b_set, :second) do
    with {:ok, converted} <- map_endpoints(b_set, &month_axis_endpoint/1) do
      {:ok, a_set, converted}
    end
  end

  defp week_axis?(%IntervalSet{intervals: intervals}) do
    Enum.any?(intervals, fn %Interval{from: from, to: to} ->
      week_axis_endpoint?(from) or week_axis_endpoint?(to)
    end)
  end

  defp week_axis_endpoint?(%Tempo{time: time}), do: Keyword.has_key?(time, :week)
  defp week_axis_endpoint?(_other), do: false

  # Rewrite one week-axis endpoint as a month-axis calendar date.
  # A week-resolution endpoint denotes the start of its week under
  # the half-open convention, so a missing `:day_of_week` pads to 1
  # before resolution.
  defp month_axis_endpoint(%Tempo{time: time, calendar: calendar} = tempo) do
    if Keyword.has_key?(time, :week) do
      resolved = time |> pad_day_of_week() |> Validation.resolve(calendar)
      month_axis_time(resolved, tempo)
    else
      {:ok, tempo}
    end
  end

  defp month_axis_endpoint(other), do: {:ok, other}

  defp month_axis_time({:error, _} = error, _tempo), do: error

  defp month_axis_time(resolved, tempo) when is_list(resolved) do
    if Keyword.has_key?(resolved, :week) do
      {:error,
       ResolutionError.exception(
         current: :week,
         target: :month,
         operation: :align,
         calendar: tempo.calendar,
         reason:
           "Cannot express #{inspect(tempo)} as a month-axis calendar date " <>
             "under #{inspect(tempo.calendar)}"
       )}
    else
      {:ok, %{tempo | time: resolved}}
    end
  end

  defp pad_day_of_week(time) do
    if Keyword.has_key?(time, :day_of_week) do
      time
    else
      Enum.flat_map(time, fn
        {:week, _} = week -> [week, {:day_of_week, 1}]
        other -> [other]
      end)
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
      case Unit.compare(a_res, b_res) do
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
    |> Enum.min_by(&Unit.sort_key/1, fn -> :day end)
  end

  defp apply_resolution(%IntervalSet{} = set, target) do
    map_endpoints(set, &extend_or_pass(&1, target))
  end

  defp extend_or_pass(%Tempo{} = tempo, target) do
    {current, _} = Tempo.resolution(tempo)

    case Unit.compare(target, current) do
      :lt -> extend_endpoint(tempo, target)
      _eq_or_gt -> {:ok, tempo}
    end
  end

  defp extend_endpoint(tempo, target) do
    case Tempo.extend_resolution(tempo, target) do
      %Tempo{} = extended -> {:ok, extended}
      {:error, _} = error -> error
    end
  end

  # Apply `mapper` to every interval endpoint in `set`, preserving
  # member order and propagating the first `{:error, _}` returned.
  # Both callers apply monotone per-endpoint transforms, so the
  # from-sorted precondition the sweeps rely on is preserved.
  defp map_endpoints(%IntervalSet{intervals: intervals} = set, mapper) do
    with {:ok, mapped} <- map_interval_endpoints(intervals, mapper, []) do
      {:ok, %{set | intervals: mapped}}
    end
  end

  defp map_interval_endpoints([], _mapper, acc), do: {:ok, Enum.reverse(acc)}

  defp map_interval_endpoints([%Interval{from: from, to: to} = interval | rest], mapper, acc) do
    with {:ok, mapped_from} <- mapper.(from),
         {:ok, mapped_to} <- mapper.(to) do
      map_interval_endpoints(rest, mapper, [
        %{interval | from: mapped_from, to: mapped_to} | acc
      ])
    end
  end

  ## ---------------------------------------------------------------
  ## Core set operations
  ## ---------------------------------------------------------------

  @doc """
  Union of two operands — every member of either operand, kept
  as a distinct interval with its original metadata.

  Under Tempo's member-preserving semantics, two inputs that
  happen to cover the same time range produce **two** members in
  the result, not one. If you want the canonical instant-set form
  (touching members merged), call `Tempo.IntervalSet.coalesce/1`
  on the result.

  """
  @spec union(operand, operand, keyword()) ::
          {:ok, IntervalSet.t()} | {:error, term()}
        when operand: Tempo.t() | Interval.t() | IntervalSet.t() | Tempo.Set.t()
  def union(a, b, opts \\ []) do
    with {:ok, {a_set, b_set}} <- align(a, b, opts) do
      IntervalSet.new(a_set.intervals ++ b_set.intervals, metadata: a_set.metadata)
    end
  end

  @doc """
  Intersection of two operands — every instant present in both
  operands, returned as one or more trimmed intervals.

  Each result interval is the portion of an `a` member trimmed
  to its overlap with some `b` member. Members of `a` can be
  split into multiple fragments if `b` covers only part of them.
  Each emitted fragment carries the source `a` member's metadata.

  This is the canonical set-theoretic intersection: `A ∩ B`.
  Use it when the question is about *covered time* — "the parts
  of my meetings that fall inside business hours", "the overlap
  between two date ranges".

  For the member-preserving filter (return whole `a` members
  that overlap any `b` member, untrimmed), use
  `members_overlapping/3`.

  """
  @spec intersection(operand, operand, keyword()) ::
          {:ok, IntervalSet.t()} | {:error, term()}
        when operand: Tempo.t() | Interval.t() | IntervalSet.t() | Tempo.Set.t()
  def intersection(a, b, opts \\ []) do
    with {:ok, {a_set, b_set}} <- align(a, b, opts) do
      IntervalSet.new(sweep_intersection(a_set.intervals, b_set.intervals),
        metadata: a_set.metadata
      )
    end
  end

  @doc """
  Member-preserving overlap filter — the **members of `a`** that
  overlap any member of `b`, kept as distinct intervals with
  their original metadata.

  This is the "which of these bookings hit the query window?"
  query. Each surviving member is an entire member of `a` — not
  a trimmed portion.

  For the canonical instant-level intersection (each survivor
  trimmed to its overlap with `b`), use `intersection/3`.

  """
  @spec members_overlapping(operand, operand, keyword()) ::
          {:ok, IntervalSet.t()} | {:error, term()}
        when operand: Tempo.t() | Interval.t() | IntervalSet.t() | Tempo.Set.t()
  def members_overlapping(a, b, opts \\ []) do
    with {:ok, {a_set, b_set}} <- align(a, b, opts) do
      result = sweep_members(a_set.intervals, b_set.intervals, :overlapping)
      IntervalSet.new(result, metadata: a_set.metadata)
    end
  end

  # Member-preserving overlap scan over two from-sorted member lists
  # (the `IntervalSet` constructor sorts unconditionally, and `align/3`
  # only applies per-member monotone transforms, so both lists arrive
  # sorted). O(len(a) + len(b)): each step either classifies and
  # advances the leading A member, or permanently discards the leading
  # B member — a B that ends at-or-before the current A starts can
  # never overlap any later A member either, because A is from-sorted.
  #
  # Two half-open intervals share an instant iff `a.from < b.to` and
  # `b.from < a.to` — boundary touches (`:meets`/`:met_by`) are not
  # overlap. `mode` selects which A members survive: `:overlapping`
  # keeps the sharers, `:outside` keeps the rest.

  defp sweep_members([], _b_list, _mode), do: []
  defp sweep_members(a_list, [], :outside), do: a_list
  defp sweep_members(_a_list, [], :overlapping), do: []

  defp sweep_members([a | a_rest] = a_list, [b | b_rest] = b_list, mode) do
    cond do
      # B ends at-or-before A starts — discard B for good.
      Compare.compare_endpoints(b.to, a.from) != :later ->
        sweep_members(a_list, b_rest, mode)

      # B ends after A starts (from above) and starts before A ends:
      # they share an instant.
      Compare.compare_endpoints(b.from, a.to) == :earlier ->
        emit_member(a, mode == :overlapping, a_rest, b_list, mode)

      # B — and, B being from-sorted, every later B — starts at-or-
      # after A ends: this A overlaps nothing.
      true ->
        emit_member(a, mode == :outside, a_rest, b_list, mode)
    end
  end

  defp emit_member(a, true, a_rest, b_list, mode) do
    [a | sweep_members(a_rest, b_list, mode)]
  end

  defp emit_member(_a, false, a_rest, b_list, mode) do
    sweep_members(a_rest, b_list, mode)
  end

  # Sweep-line instant-level intersection. Each step finds the
  # overlap between the current A and current B interval; if
  # non-empty, emit; advance whichever ends first. Used by
  # `intersection/3` and by `complement/2`'s internal pipeline.

  defp sweep_intersection([], _b), do: []
  defp sweep_intersection(_a, []), do: []

  defp sweep_intersection([%Interval{} = a | a_rest], [%Interval{} = b | b_rest]) do
    overlap_from = later_endpoint(a.from, b.from)
    overlap_to = earlier_endpoint(a.to, b.to)

    case Compare.compare_endpoints(overlap_from, overlap_to) do
      :earlier ->
        result = %Interval{from: overlap_from, to: overlap_to, metadata: a.metadata}
        [result | advance(a, a_rest, b, b_rest)]

      _ ->
        advance(a, a_rest, b, b_rest)
    end
  end

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
  Complement of `set` within `bound` — the instants in `bound`
  that are NOT covered by any member of `set`.

  Unlike `difference/3` (which is member-preserving),
  `complement/2` returns the **instant-set** form: one member
  per gap in the covered region. This is the right semantics
  for "find all free time in the workday" style queries.

  The `:bound` option is required — an unbounded complement is
  infinite, and Tempo refuses to pick a universe implicitly.

  ### Options

  * `:bound` — the universe to complement within. Any Tempo
    value. Required.

  """
  @spec complement(operand, keyword()) :: {:ok, IntervalSet.t()} | {:error, term()}
        when operand: Tempo.t() | Interval.t() | IntervalSet.t() | Tempo.Set.t()
  def complement(set, opts) do
    case Keyword.get(opts, :bound) do
      nil ->
        {:error,
         UnboundedRecurrenceError.exception(
           reason:
             "`complement/2` requires an explicit `:bound` option. " <>
               "An unbounded complement is infinite; supply the universe to " <>
               "complement within."
         )}

      bound ->
        with {:ok, {bound_set, input_set}} <- align(bound, set, opts) do
          # Coalesce the input so gaps are computed against the
          # union-of-covered-instants, not against overlapping
          # members individually.
          coalesced_input = IntervalSet.coalesce(input_set)

          IntervalSet.new(
            sweep_difference(bound_set.intervals, coalesced_input.intervals),
            metadata: bound_set.metadata
          )
        end
    end
  end

  @doc """
  Difference `a \\ b` — every instant in `a` that is NOT in `b`,
  returned as one or more trimmed intervals.

  Each member of `a` is trimmed to its portions that don't
  overlap any member of `b`. A single `a` member can split into
  multiple fragments if `b` covers only its middle. Each emitted
  fragment carries the source `a` member's metadata.

  This is the canonical set-theoretic difference: `A ∖ B`. Use
  it when the question is about *covered time* — "the parts of
  the workday that aren't lunch", "free time around a busy
  schedule".

  For the member-preserving filter (keep whole `a` members that
  don't overlap any `b` member, drop the rest), use
  `members_outside/3`.

  """
  @spec difference(operand, operand, keyword()) ::
          {:ok, IntervalSet.t()} | {:error, term()}
        when operand: Tempo.t() | Interval.t() | IntervalSet.t() | Tempo.Set.t()
  def difference(a, b, opts \\ []) do
    with {:ok, {a_set, b_set}} <- align(a, b, opts) do
      IntervalSet.new(sweep_difference(a_set.intervals, b_set.intervals),
        metadata: a_set.metadata
      )
    end
  end

  @doc """
  Member-preserving anti-overlap filter — the **members of `a`**
  that do NOT overlap any member of `b`, kept whole with their
  original metadata.

  This is the "which workdays aren't holidays?" query. A member
  of `a` is dropped entirely if any member of `b` overlaps it,
  even partially.

  For the canonical instant-level difference (trim each member
  of `a` to its non-overlapping portion of `b`, splitting if
  necessary), use `difference/3`.

  """
  @spec members_outside(operand, operand, keyword()) ::
          {:ok, IntervalSet.t()} | {:error, term()}
        when operand: Tempo.t() | Interval.t() | IntervalSet.t() | Tempo.Set.t()
  def members_outside(a, b, opts \\ []) do
    with {:ok, {a_set, b_set}} <- align(a, b, opts) do
      result = sweep_members(a_set.intervals, b_set.intervals, :outside)
      IntervalSet.new(result, metadata: a_set.metadata)
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
  # Every emitted fragment carries A's metadata — the surviving
  # portions of A "are" A, with its event identity intact.

  defp subtract_from(%Interval{from: a_from, to: a_to, metadata: a_meta}, []) do
    {maybe_emit(a_from, a_to, a_meta), []}
  end

  defp subtract_from(
         %Interval{from: a_from, to: a_to, metadata: a_meta} = a,
         [%Interval{} = b | b_rest]
       ) do
    cond do
      # B is entirely before A — skip it.
      not after_or_eq?(b.to, a_from) ->
        subtract_from(a, b_rest)

      # B is entirely after A — no more overlaps; emit current A
      # (only if it has positive width — a tail residue from a
      # previous full-cover step can be zero-width).
      not after_or_eq?(a_to, b.from) ->
        {maybe_emit(a_from, a_to, a_meta), [b | b_rest]}

      # B starts inside A (or at its edge).
      true ->
        left = maybe_emit(a_from, b.from, a_meta)
        rest_from = later_endpoint(b.to, a_from)

        if after_or_eq?(a_to, b.to) do
          # B ends inside A — continue subtracting from the rest.
          rest_a = %Interval{from: rest_from, to: a_to, metadata: a_meta}
          {right, remaining_b} = subtract_from(rest_a, b_rest)
          {left ++ right, remaining_b}
        else
          # B fully covers A's tail — stop emitting, B may extend further.
          {left, [b | b_rest]}
        end
    end
  end

  # Emit a one-interval list if `from < to`, empty otherwise.
  # `metadata` is carried on the emitted interval.
  defp maybe_emit(from, to, metadata) do
    case Compare.compare_endpoints(from, to) do
      :earlier -> [%Interval{from: from, to: to, metadata: metadata}]
      _ -> []
    end
  end

  defp after_or_eq?(a, b) do
    Compare.compare_endpoints(a, b) != :earlier
  end

  @doc """
  Symmetric difference `a △ b` — every instant in exactly one
  of the operands, returned as trimmed intervals. Derived as
  `(a \\ b) ∪ (b \\ a)` using the instant-level `difference/3`.

  Use this when the question is about *covered time* — "the
  hours that one of us has free but the other doesn't". For
  the member-preserving filter (whole members of either
  operand that don't overlap any member of the other), use
  `members_in_exactly_one/3`.
  """
  @spec symmetric_difference(operand, operand, keyword()) ::
          {:ok, IntervalSet.t()} | {:error, term()}
        when operand: Tempo.t() | Interval.t() | IntervalSet.t() | Tempo.Set.t()
  def symmetric_difference(a, b, opts \\ []) do
    with {:ok, a_minus_b} <- difference(a, b, opts),
         {:ok, b_minus_a} <- difference(b, a, opts) do
      IntervalSet.new(a_minus_b.intervals ++ b_minus_a.intervals,
        metadata: a_minus_b.metadata
      )
    end
  end

  @doc """
  Member-preserving symmetric-difference filter — the members
  of either operand that do NOT overlap any member of the
  other, kept whole with their original metadata. Derived as
  `members_outside(a, b) ∪ members_outside(b, a)`.

  This is the "which events appear on exactly one calendar?"
  query. For the canonical instant-level form, use
  `symmetric_difference/3`.
  """
  @spec members_in_exactly_one(operand, operand, keyword()) ::
          {:ok, IntervalSet.t()} | {:error, term()}
        when operand: Tempo.t() | Interval.t() | IntervalSet.t() | Tempo.Set.t()
  def members_in_exactly_one(a, b, opts \\ []) do
    with {:ok, a_minus_b} <- members_outside(a, b, opts),
         {:ok, b_minus_a} <- members_outside(b, a, opts) do
      IntervalSet.new(a_minus_b.intervals ++ b_minus_a.intervals,
        metadata: a_minus_b.metadata
      )
    end
  end

  ## ---------------------------------------------------------------
  ## Predicates
  ## ---------------------------------------------------------------

  @doc """
  `true` when `a` and `b` share no instants — no member of `a`
  overlaps any member of `b`.
  """
  @spec disjoint?(operand, operand, keyword()) :: boolean()
        when operand: Tempo.t() | Interval.t() | IntervalSet.t() | Tempo.Set.t()
  def disjoint?(a, b, opts \\ []) do
    case intersection(a, b, opts) do
      {:ok, %IntervalSet{intervals: []}} -> true
      {:ok, _} -> false
      {:error, exception} -> raise exception
    end
  end

  @doc """
  `true` when `a` and `b` share at least one instant.
  """
  @spec overlaps?(operand, operand, keyword()) :: boolean()
        when operand: Tempo.t() | Interval.t() | IntervalSet.t() | Tempo.Set.t()
  def overlaps?(a, b, opts \\ []), do: not disjoint?(a, b, opts)

  @doc """
  `true` when every instant covered by `a` is also covered by
  `b`. Operates at the instant-set level (both operands
  coalesced internally) — not member-by-member.
  """
  @spec subset?(operand, operand, keyword()) :: boolean()
        when operand: Tempo.t() | Interval.t() | IntervalSet.t() | Tempo.Set.t()
  def subset?(a, b, opts \\ []) do
    case difference(a, b, opts) do
      {:ok, %IntervalSet{intervals: []}} -> true
      {:ok, _} -> false
      {:error, exception} -> raise exception
    end
  end

  @doc """
  `true` when every instant covered by `b` is also covered by
  `a`. Alias for `subset?(b, a, opts)`.
  """
  @spec contains?(operand, operand, keyword()) :: boolean()
        when operand: Tempo.t() | Interval.t() | IntervalSet.t() | Tempo.Set.t()
  def contains?(a, b, opts \\ []), do: subset?(b, a, opts)

  @doc """
  `true` when `a` and `b` cover the same instants — i.e. they
  are mutual subsets at the instant-set level. Member identity
  and metadata are ignored; only the covered instants matter.
  """
  @spec equal?(operand, operand, keyword()) :: boolean()
        when operand: Tempo.t() | Interval.t() | IntervalSet.t() | Tempo.Set.t()
  def equal?(a, b, opts \\ []) do
    case align(a, b, opts) do
      {:ok, {a_set, b_set}} ->
        coalesced_a = IntervalSet.coalesce(a_set)
        coalesced_b = IntervalSet.coalesce(b_set)
        coalesced_a.intervals == coalesced_b.intervals

      {:error, exception} ->
        raise exception
    end
  end
end
