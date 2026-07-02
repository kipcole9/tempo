defmodule Tempo.Math do
  @moduledoc """
  Time-unit arithmetic primitives used by enumeration, interval
  materialisation (`Tempo.to_interval/1`), and eventually
  `Tempo + Duration` / `Tempo − Duration` operations.

  The core function is `add_unit/3`: given a keyword-list time
  representation (or a `%Tempo{}`), advance it by exactly one unit
  at a specified resolution, carrying into coarser units as needed.
  Carry is calendar-aware — months per year and days per month vary
  by calendar, week counts too.

  `unit_minimum/1` answers "what is the start-of-unit value?" —
  used when reasoning about mixed-resolution intervals and when
  constructing the lower bound of an implicit span.

  The module is kept deliberately minimal and pure: no Tempo struct
  construction, no side effects, no exceptions beyond the
  `ArgumentError` raised when a unit has no known carry rule.

  """

  alias Tempo.IntervalSet
  alias Tempo.Mask

  @doc """
  Advance a `%Tempo{}` or a keyword-list time representation by
  exactly one unit at the given resolution.

  Uses `Keyword.replace!/3` (preserves position) rather than
  `Keyword.put/3` (removes + prepends). Keyword-list order is an
  invariant maintained elsewhere in Tempo: `compare_time/2`,
  `inspect`, and `to_iso8601` all depend on it.

  ### Arguments

  * `tempo_or_time` is either a `t:Tempo.t/0` or the keyword list
    stored in its `:time` field.

  * `unit` is the unit at which to increment. Supported units:
    `:year`, `:month`, `:day`, `:hour`, `:minute`, `:second`,
    `:week`, `:day_of_year`, `:day_of_week`.

  * `calendar` is the calendar module used for calendar-sensitive
    carry (months per year, days per month, weeks per year).

  ### Returns

  * The input with the unit advanced by 1, carrying into coarser
    units as needed. Shape matches the input — a `%Tempo{}` in
    yields a `%Tempo{}` out; a keyword list yields a keyword list.

  ### Raises

  * `ArgumentError` when no increment rule is defined for the
    requested unit.

  ### Examples

      iex> Tempo.Math.add_unit(~o"2022Y12M31D", :day, Calendrical.Gregorian)
      ~o"2023Y1M1D"

      iex> Tempo.Math.add_unit(~o"2022Y6M", :month, Calendrical.Gregorian)
      ~o"2022Y7M"

  """
  def add_unit(%Tempo{time: time, calendar: calendar} = tempo, unit, calendar) do
    %{tempo | time: add_unit(time, unit, calendar)}
  end

  def add_unit(%Tempo{time: time, calendar: struct_calendar} = tempo, unit, calendar)
      when struct_calendar != calendar do
    # If caller explicitly passes a calendar that differs from the
    # struct's own, honour the explicit one but keep the struct
    # shape. (Normal callers pass the struct's calendar.)
    %{tempo | time: add_unit(time, unit, calendar)}
  end

  def add_unit(time, :year, _calendar) when is_list(time) do
    Keyword.update!(time, :year, &(&1 + 1))
  end

  def add_unit(time, :month, calendar) when is_list(time) do
    if Keyword.has_key?(time, :year) do
      year = Keyword.fetch!(time, :year)
      month = Keyword.fetch!(time, :month)
      months_in_year = calendar.months_in_year(year)

      if month < months_in_year do
        Keyword.replace!(time, :month, month + 1)
      else
        time
        |> Keyword.replace!(:year, year + 1)
        |> Keyword.replace!(:month, 1)
      end
    else
      advance_month_unanchored(time, calendar)
    end
  end

  def add_unit(time, :day, calendar) when is_list(time) do
    if Keyword.has_key?(time, :year) do
      year = Keyword.fetch!(time, :year)
      month = Keyword.fetch!(time, :month)
      day = Keyword.fetch!(time, :day)
      days_in_month = calendar.days_in_month(year, month)

      cond do
        day < days_in_month ->
          Keyword.replace!(time, :day, day + 1)

        month < calendar.months_in_year(year) ->
          time
          |> Keyword.replace!(:month, month + 1)
          |> Keyword.replace!(:day, 1)

        true ->
          time
          |> Keyword.replace!(:year, year + 1)
          |> Keyword.replace!(:month, 1)
          |> Keyword.replace!(:day, 1)
      end
    else
      advance_day_unanchored(time, calendar)
    end
  end

  def add_unit(time, :hour, calendar) when is_list(time) do
    hour = Keyword.fetch!(time, :hour)

    if hour < 23 do
      Keyword.replace!(time, :hour, hour + 1)
    else
      time
      |> Keyword.replace!(:hour, 0)
      |> add_unit(:day, calendar)
    end
  end

  def add_unit(time, :minute, calendar) when is_list(time) do
    minute = Keyword.fetch!(time, :minute)

    if minute < 59 do
      Keyword.replace!(time, :minute, minute + 1)
    else
      time
      |> Keyword.replace!(:minute, 0)
      |> add_unit(:hour, calendar)
    end
  end

  def add_unit(time, :second, calendar) when is_list(time) do
    second = Keyword.fetch!(time, :second)

    if second < 59 do
      Keyword.replace!(time, :second, second + 1)
    else
      time
      |> Keyword.replace!(:second, 0)
      |> add_unit(:minute, calendar)
    end
  end

  # Step one unit-in-the-last-place at the microsecond's precision:
  # 10^(6 - precision) microseconds (1 ms for precision 3, 1 µs for
  # precision 6), carrying into the second at 1_000_000.
  def add_unit(time, :microsecond, calendar) when is_list(time) do
    {value, precision} = Keyword.fetch!(time, :microsecond)
    incremented = value + Integer.pow(10, 6 - precision)

    if incremented >= 1_000_000 do
      time
      |> Keyword.delete(:microsecond)
      |> add_unit(:second, calendar)
      |> Kernel.++([{:microsecond, {incremented - 1_000_000, precision}}])
    else
      Keyword.replace(time, :microsecond, {incremented, precision})
    end
  end

  def add_unit(time, :week, calendar) when is_list(time) do
    year = Keyword.fetch!(time, :year)
    week = Keyword.fetch!(time, :week)
    {weeks_in_year, _days_in_last_week} = calendar.weeks_in_year(year)

    if week < weeks_in_year do
      Keyword.replace!(time, :week, week + 1)
    else
      time
      |> Keyword.replace!(:year, year + 1)
      |> Keyword.replace!(:week, 1)
    end
  end

  def add_unit(time, :day_of_year, calendar) when is_list(time) do
    year = Keyword.fetch!(time, :year)
    day_of_year = Keyword.fetch!(time, :day_of_year)
    days_in_year = calendar.days_in_year(year)

    if day_of_year < days_in_year do
      Keyword.replace!(time, :day_of_year, day_of_year + 1)
    else
      time
      |> Keyword.replace!(:year, year + 1)
      |> Keyword.replace!(:day_of_year, 1)
    end
  end

  def add_unit(time, :day_of_week, calendar) when is_list(time) do
    day_of_week = Keyword.fetch!(time, :day_of_week)
    days_in_week = calendar.days_in_week()

    if day_of_week < days_in_week do
      Keyword.replace!(time, :day_of_week, day_of_week + 1)
    else
      time
      |> Keyword.replace!(:day_of_week, 1)
      |> add_unit(:week, calendar)
    end
  end

  def add_unit(_time, unit, _calendar) do
    raise ArgumentError,
          "Cannot increment a Tempo at #{inspect(unit)} resolution — " <>
            "no increment rule is defined for this unit."
  end

  # ── Un-anchored arithmetic (no :year) ──────────────────────────
  #
  # A value with no `:year` lives on a repeating month/day axis, so
  # some arithmetic is still answerable — "the 31st of a month + one
  # day" is the 1st of the next month because every January has 31
  # days. We resolve those cases with the calendar's year-less
  # `days_in_month/1` and `months_in_year/0`; where the answer would
  # depend on the missing year (a February day count, a lunisolar
  # year's last month, or a calendar that can't answer without a
  # year) we throw `:requires_anchor`, which `add/2` converts to
  # `{:error, :requires_anchor}` rather than crashing.

  defp advance_day_unanchored(time, calendar) do
    month = Keyword.fetch!(time, :month)
    day = Keyword.fetch!(time, :day)

    case calendar.days_in_month(month) do
      count when is_integer(count) ->
        if day < count,
          do: Keyword.replace!(time, :day, day + 1),
          else: start_of_next_month_unanchored(time, calendar)

      {:ambiguous, range} ->
        cond do
          day < Enum.min(range) -> Keyword.replace!(time, :day, day + 1)
          day >= Enum.max(range) -> start_of_next_month_unanchored(time, calendar)
          true -> throw({:tempo_math, :requires_anchor})
        end

      _undefined ->
        throw({:tempo_math, :requires_anchor})
    end
  end

  defp start_of_next_month_unanchored(time, calendar) do
    time
    |> advance_month_unanchored(calendar)
    |> Keyword.replace!(:day, 1)
  end

  defp advance_month_unanchored(time, calendar) do
    month = Keyword.fetch!(time, :month)

    case months_in_year_unanchored(calendar) do
      count when is_integer(count) ->
        Keyword.replace!(time, :month, if(month < count, do: month + 1, else: 1))

      {:ambiguous, range} ->
        if month < Enum.min(range),
          do: Keyword.replace!(time, :month, month + 1),
          else: throw({:tempo_math, :requires_anchor})

      _undefined ->
        throw({:tempo_math, :requires_anchor})
    end
  end

  # `months_in_year/0` is an optional calendar callback — a calendar
  # that can't state its month count without a year simply doesn't
  # implement it, so guard the call and treat its absence as "needs
  # an anchor".
  defp months_in_year_unanchored(calendar) do
    if function_exported?(calendar, :months_in_year, 0) do
      calendar.months_in_year()
    else
      {:error, :undefined}
    end
  end

  # Mirrors of the advance helpers for `subtract_unit/3`.

  defp retreat_month_unanchored(time, calendar) do
    month = Keyword.fetch!(time, :month)

    if month > 1 do
      Keyword.replace!(time, :month, month - 1)
    else
      case months_in_year_unanchored(calendar) do
        count when is_integer(count) -> Keyword.replace!(time, :month, count)
        _undefined -> throw({:tempo_math, :requires_anchor})
      end
    end
  end

  defp retreat_day_unanchored(time, calendar) do
    month = Keyword.fetch!(time, :month)
    day = Keyword.fetch!(time, :day)

    cond do
      day > 1 ->
        Keyword.replace!(time, :day, day - 1)

      month > 1 ->
        end_of_previous_month_unanchored(time, month - 1, calendar)

      true ->
        case months_in_year_unanchored(calendar) do
          count when is_integer(count) -> end_of_previous_month_unanchored(time, count, calendar)
          _undefined -> throw({:tempo_math, :requires_anchor})
        end
    end
  end

  defp end_of_previous_month_unanchored(time, previous_month, calendar) do
    case calendar.days_in_month(previous_month) do
      count when is_integer(count) ->
        time
        |> Keyword.replace!(:month, previous_month)
        |> Keyword.replace!(:day, count)

      _ambiguous_or_undefined ->
        throw({:tempo_math, :requires_anchor})
    end
  end

  @doc """
  The mirror of `add_unit/3`: advance a `%Tempo{}` or keyword-list
  time representation backward by exactly one unit at the given
  resolution, borrowing from coarser units as needed.

  Used internally by `subtract/2` and by any future
  backward-walking iteration.

  ### Arguments

  * `tempo_or_time` is a `t:Tempo.t/0` or its time keyword list.
  * `unit` is the unit to decrement. Same vocabulary as `add_unit/3`.
  * `calendar` is the calendar module used for borrow lookups.

  ### Returns

  * The input with the unit decremented by 1.

  ### Examples

      iex> Tempo.Math.subtract_unit(~o"2023Y1M1D", :day, Calendrical.Gregorian)
      ~o"2022Y12M31D"

      iex> Tempo.Math.subtract_unit(~o"2022Y1M", :month, Calendrical.Gregorian)
      ~o"2021Y12M"

  """
  def subtract_unit(%Tempo{time: time, calendar: calendar} = tempo, unit, calendar) do
    %{tempo | time: subtract_unit(time, unit, calendar)}
  end

  def subtract_unit(%Tempo{time: time} = tempo, unit, calendar) do
    %{tempo | time: subtract_unit(time, unit, calendar)}
  end

  def subtract_unit(time, :year, _calendar) when is_list(time) do
    Keyword.update!(time, :year, &(&1 - 1))
  end

  def subtract_unit(time, :month, calendar) when is_list(time) do
    if Keyword.has_key?(time, :year) do
      year = Keyword.fetch!(time, :year)
      month = Keyword.fetch!(time, :month)

      if month > 1 do
        Keyword.replace!(time, :month, month - 1)
      else
        prev_year = year - 1

        time
        |> Keyword.replace!(:year, prev_year)
        |> Keyword.replace!(:month, calendar.months_in_year(prev_year))
      end
    else
      retreat_month_unanchored(time, calendar)
    end
  end

  def subtract_unit(time, :day, calendar) when is_list(time) do
    if Keyword.has_key?(time, :year) do
      year = Keyword.fetch!(time, :year)
      month = Keyword.fetch!(time, :month)
      day = Keyword.fetch!(time, :day)

      cond do
        day > 1 ->
          Keyword.replace!(time, :day, day - 1)

        month > 1 ->
          prev_month = month - 1

          time
          |> Keyword.replace!(:month, prev_month)
          |> Keyword.replace!(:day, calendar.days_in_month(year, prev_month))

        true ->
          prev_year = year - 1
          prev_month = calendar.months_in_year(prev_year)

          time
          |> Keyword.replace!(:year, prev_year)
          |> Keyword.replace!(:month, prev_month)
          |> Keyword.replace!(:day, calendar.days_in_month(prev_year, prev_month))
      end
    else
      retreat_day_unanchored(time, calendar)
    end
  end

  def subtract_unit(time, :hour, calendar) when is_list(time) do
    hour = Keyword.fetch!(time, :hour)

    if hour > 0 do
      Keyword.replace!(time, :hour, hour - 1)
    else
      time
      |> Keyword.replace!(:hour, 23)
      |> subtract_unit(:day, calendar)
    end
  end

  def subtract_unit(time, :minute, calendar) when is_list(time) do
    minute = Keyword.fetch!(time, :minute)

    if minute > 0 do
      Keyword.replace!(time, :minute, minute - 1)
    else
      time
      |> Keyword.replace!(:minute, 59)
      |> subtract_unit(:hour, calendar)
    end
  end

  def subtract_unit(time, :second, calendar) when is_list(time) do
    second = Keyword.fetch!(time, :second)

    if second > 0 do
      Keyword.replace!(time, :second, second - 1)
    else
      time
      |> Keyword.replace!(:second, 59)
      |> subtract_unit(:minute, calendar)
    end
  end

  def subtract_unit(time, :week, calendar) when is_list(time) do
    year = Keyword.fetch!(time, :year)
    week = Keyword.fetch!(time, :week)

    if week > 1 do
      Keyword.replace!(time, :week, week - 1)
    else
      prev_year = year - 1
      {weeks, _} = calendar.weeks_in_year(prev_year)

      time
      |> Keyword.replace!(:year, prev_year)
      |> Keyword.replace!(:week, weeks)
    end
  end

  def subtract_unit(time, :day_of_year, calendar) when is_list(time) do
    year = Keyword.fetch!(time, :year)
    day_of_year = Keyword.fetch!(time, :day_of_year)

    if day_of_year > 1 do
      Keyword.replace!(time, :day_of_year, day_of_year - 1)
    else
      prev_year = year - 1

      time
      |> Keyword.replace!(:year, prev_year)
      |> Keyword.replace!(:day_of_year, calendar.days_in_year(prev_year))
    end
  end

  def subtract_unit(time, :day_of_week, calendar) when is_list(time) do
    day_of_week = Keyword.fetch!(time, :day_of_week)

    if day_of_week > 1 do
      Keyword.replace!(time, :day_of_week, day_of_week - 1)
    else
      time
      |> Keyword.replace!(:day_of_week, calendar.days_in_week())
      |> subtract_unit(:week, calendar)
    end
  end

  def subtract_unit(_time, unit, _calendar) do
    raise ArgumentError,
          "Cannot decrement a Tempo at #{inspect(unit)} resolution — " <>
            "no decrement rule is defined for this unit."
  end

  @doc """
  Add a `t:Tempo.Duration.t/0` to a `t:Tempo.t/0`.

  The duration's components are applied largest-unit-first
  (year → month → day → hour → minute → second), with week
  components expanded to days (`P2W` = 14 days). After the
  month-level arithmetic, the day field is clamped to the valid
  range for the resulting month — so `2022-01-31 + P1M` yields
  `2022-02-28`, matching the semantics used by
  `java.time.LocalDate.plus/2`.

  Single add operations are atomic: `Jan 31 + P1M = Feb 28`, but
  `Jan 31 + P1M + P1M` is not the same as `Jan 31 + P2M` — date
  arithmetic is not associative. If you need the "absorb" chained
  semantic, do the add in one call with a single `P2M` duration.

  Negative duration components subtract. `~o"P-100D"` added to
  `~o"2022Y1M10D"` yields a date 100 days earlier.

  The input Tempo must carry every unit referenced by the
  duration. If the duration has a `:hour` component but the Tempo
  is at year resolution, the Tempo is extended via
  `Tempo.extend_resolution/2` first.

  ### Arguments

  * `tempo` is any `t:Tempo.t/0`.
  * `duration` is any `t:Tempo.Duration.t/0`.

  ### Returns

  * A new `t:Tempo.t/0` with the duration applied.

  ### Examples

      iex> Tempo.Math.add(~o"2022Y1M1D", ~o"P1M")
      ~o"2022Y2M1D"

      iex> Tempo.Math.add(~o"2022Y1M31D", ~o"P1M")
      ~o"2022Y2M28D"

      iex> Tempo.Math.add(~o"2022Y12M31D", ~o"P1D")
      ~o"2023Y1M1D"

      iex> Tempo.Math.add(~o"2022Y1M1D", ~o"P2W")
      ~o"2022Y1M15D"

  """
  @spec add(Tempo.t(), Tempo.Duration.t()) ::
          Tempo.t() | Tempo.Set.t() | Tempo.IntervalSet.t() | {:error, :requires_anchor}
  def add(%Tempo{} = tempo, %Tempo.Duration{time: duration_time} = duration) do
    masks = find_masks(tempo.time)

    # Route to the mask path only when the shift actually reaches a mask.
    # A shift coarser than every mask (or a value with no masks) never
    # touches a masked component, so the crisp path shifts around them and
    # keeps the masks intact (`2020-XX` + `P1Y` → `2021-XX`).
    #
    # Un-anchored arithmetic that would depend on the missing year
    # throws `:requires_anchor` from deep in the stepper; catch it here
    # and surface a clean error rather than letting it crash the caller.
    try do
      if Enum.any?(masks, fn {unit, _mask} -> duration_reaches?(duration_time, unit) end) do
        shift_masked(tempo, masks, duration)
      else
        add_crisp(tempo, duration)
      end
    catch
      {:tempo_math, :requires_anchor} -> {:error, :requires_anchor}
    end
  end

  # Coarse → fine. A duration "reaches" a mask when it carries a
  # non-zero component at the masked unit or finer (which is where the
  # arithmetic reads or writes the masked value).
  @unit_depth [year: 0, month: 1, week: 2, day: 2, hour: 3, minute: 4, second: 5, microsecond: 6]

  defp duration_reaches?(duration_time, mask_unit) do
    mask_depth = Keyword.fetch!(@unit_depth, mask_unit)

    Enum.any?(duration_time, fn {unit, amount} ->
      amount != 0 and Keyword.get(@unit_depth, unit, 0) >= mask_depth
    end)
  end

  # The crisp arithmetic path. ISO 8601-2 margin-of-error (`±`) and
  # significant-digits (`S`) annotations ride on a component value as
  # `{integer, keyword}`; they are crisp-inert, so peel them off before
  # the duration is applied and re-attach each to its (shifted) component
  # afterwards — `Tempo.shift(~o"2018±2Y", ~o"P1Y") == ~o"2019±2Y"` rather
  # than crashing the integer arithmetic on the tuple.
  defp add_crisp(%Tempo{} = tempo, %Tempo.Duration{time: duration_time}) do
    {crisp_time, annotations} = strip_component_annotations(tempo.time)

    tempo =
      %{tempo | time: crisp_time}
      |> ensure_resolution_for_duration(duration_time)

    duration_time = normalise_duration(duration_time)

    tempo
    |> apply_duration(duration_time)
    |> Map.update!(:time, &reapply_component_annotations(&1, annotations))
  end

  # ------------------------------------------------------------------
  # Unspecified-digit mask arithmetic
  #
  # A mask (`195X`, `2020-XX`, `19XX-XX`) denotes a *block* of candidate
  # values. A shift moves the block: fill *every* mask to its min and max
  # candidate, shift both crisply, then re-express the result. A
  # block-aligned single-year shift stays a mask (`195X` + `P10Y` →
  # `196X`); anything else becomes a one-of set spanning the shifted block
  # (`195X` + `P1Y` → `~o"[1951Y..1960Y]"`).

  # Masks are only resolved on units the arithmetic understands; a mask on
  # any other unit falls through to the crisp path unchanged.
  @maskable_units [:year, :month, :day, :hour, :minute, :second]

  defp find_masks(time) do
    Enum.flat_map(time, fn
      {unit, {:mask, mask}} when is_list(mask) and unit in @maskable_units -> [{unit, mask}]
      _ -> []
    end)
  end

  defp shift_masked(%Tempo{time: time, calendar: calendar} = tempo, masks, duration) do
    if trailing_masks?(time) do
      # A contiguous (trailing) block shifts as a whole, so its min and
      # max candidate bound it exactly.
      first = add_crisp(%{tempo | time: fill_masks(time, calendar, :min)}, duration)
      last = add_crisp(%{tempo | time: fill_masks(time, calendar, :max)}, duration)
      remask_or_set(masks, first, last)
    else
      # A mask with a concrete component after it denotes *disjoint*
      # blocks (`19XX-06-XX` is only the Junes), which a single range
      # can't represent — shift each candidate and collect the exact
      # spans into a coalesced IntervalSet.
      shift_masked_disjoint(tempo, duration)
    end
  end

  # Masks form a contiguous suffix — every component from the first mask
  # onward is also masked. Such a value is a single block; a mask with a
  # concrete component after it (`19XX-06-XX`) is not.
  defp trailing_masks?(time) do
    time
    |> Enum.drop_while(fn {_unit, value} -> not match?({:mask, _mask}, value) end)
    |> Enum.all?(fn {_unit, value} -> match?({:mask, _mask}, value) end)
  end

  defp shift_masked_disjoint(masked, duration) do
    intervals =
      Enum.map(masked, fn candidate ->
        {:ok, interval} = Tempo.to_interval(add_crisp(candidate, duration))
        interval
      end)

    {:ok, set} = IntervalSet.new(intervals)
    IntervalSet.coalesce(set)
  end

  # Replace every masked component with its minimum (or maximum) candidate,
  # coarse to fine so a sub-year mask sees the concrete coarser values it
  # depends on (a month's valid range needs its year).
  defp fill_masks(time, calendar, which) do
    time
    |> Enum.reduce([], fn
      {unit, {:mask, mask}}, filled ->
        {min_value, max_value} = mask_candidate_bounds(unit, mask, Enum.reverse(filled), calendar)
        [{unit, if(which == :min, do: min_value, else: max_value)} | filled]

      entry, filled ->
        [entry | filled]
    end)
    |> Enum.reverse()
  end

  # Year masks are digit-bounded; sub-year masks are calendar-bounded by
  # the already-filled coarser components.
  defp mask_candidate_bounds(:year, [:negative | rest], _previous, _calendar) do
    {min, max} = Mask.mask_bounds(rest)
    {-max, -min}
  end

  defp mask_candidate_bounds(:year, mask, _previous, _calendar) do
    Mask.mask_bounds(mask)
  end

  defp mask_candidate_bounds(unit, mask, previous, calendar) do
    candidates = Mask.valid_values(unit, mask, previous, calendar)
    {Enum.min(candidates), Enum.max(candidates)}
  end

  # A single, same-width, block-aligned year mask re-masks; everything
  # else (misaligned, negative, or multi-component) is a one-of set
  # spanning the shifted candidates.
  defp remask_or_set(
         [{:year, mask}],
         %Tempo{time: [year: lo]} = first,
         %Tempo{time: [year: hi]} = last
       )
       when is_integer(lo) and is_integer(hi) and lo >= 0 do
    unspecified = Enum.count(mask, &(&1 == :X))
    block = Integer.pow(10, unspecified)
    digits = Integer.digits(lo)

    if hi - lo + 1 == block and rem(lo, block) == 0 and length(digits) == length(mask) do
      remasked =
        Enum.take(digits, length(digits) - unspecified) ++ List.duplicate(:X, unspecified)

      %{first | time: [year: {:mask, remasked}]}
    else
      one_of_range(first, last)
    end
  end

  defp remask_or_set(_masks, first, last), do: one_of_range(first, last)

  defp one_of_range(first, last) do
    %Tempo.Set{type: :one, set: [%Tempo.Range{first: first, last: last}]}
  end

  # Peel `{integer, keyword}` value annotations (margin-of-error,
  # significant-digits) into a `%{unit => keyword}` map, leaving the
  # crisp integer in the time. Masks (`{:mask, list}`) and microsecond
  # `{value, precision}` values are untouched — only an integer value
  # with a keyword-list tail is an annotation.
  defp strip_component_annotations(time) do
    Enum.map_reduce(time, %{}, fn
      {unit, {value, opts}}, annotations when is_integer(value) and is_list(opts) ->
        {{unit, value}, Map.put(annotations, unit, opts)}

      entry, annotations ->
        {entry, annotations}
    end)
  end

  defp reapply_component_annotations(time, annotations) when annotations == %{}, do: time

  defp reapply_component_annotations(time, annotations) do
    Enum.map(time, fn
      {unit, value} = entry when is_integer(value) ->
        case annotations do
          %{^unit => opts} -> {unit, {value, opts}}
          _ -> entry
        end

      entry ->
        entry
    end)
  end

  @doc """
  Subtract a `t:Tempo.Duration.t/0` from a `t:Tempo.t/0`.

  Equivalent to `add/2` with every duration component negated.
  Month arithmetic still clamps day-of-month at the end.

  ### Arguments

  * `tempo` is any `t:Tempo.t/0`.
  * `duration` is any `t:Tempo.Duration.t/0`.

  ### Returns

  * A new `t:Tempo.t/0` with the duration subtracted.

  ### Examples

      iex> Tempo.Math.subtract(~o"2022Y3M1D", ~o"P1M")
      ~o"2022Y2M1D"

      iex> Tempo.Math.subtract(~o"2022Y3M31D", ~o"P1M")
      ~o"2022Y2M28D"

      iex> Tempo.Math.subtract(~o"2022Y1M1D", ~o"P1D")
      ~o"2021Y12M31D"

  """
  @spec subtract(Tempo.t(), Tempo.Duration.t()) ::
          Tempo.t() | Tempo.Set.t() | Tempo.IntervalSet.t()
  def subtract(%Tempo{} = tempo, %Tempo.Duration{time: duration_time}) do
    negated =
      Enum.map(duration_time, fn
        # Negate the microsecond amount by sign of the value; the
        # `{value, precision}` shape is preserved (a transient negative
        # value drives the borrow in `shift_microseconds/3`).
        {:microsecond, {value, precision}} -> {:microsecond, {-value, precision}}
        {unit, amount} -> {unit, -amount}
      end)

    add(tempo, %Tempo.Duration{time: negated})
  end

  # Weeks in a duration are unambiguously 7 days. Normalise to
  # days so the apply-duration loop doesn't need a `:week` clause.
  defp normalise_duration(duration_time) do
    {weeks, rest} = Keyword.pop(duration_time, :week, 0)

    case weeks do
      0 ->
        rest

      _ ->
        Keyword.update(rest, :day, weeks * 7, &(&1 + weeks * 7))
    end
  end

  # If the duration references a unit finer than the tempo's
  # current resolution, extend the tempo with minimums so the
  # add/subtract_unit calls have a slot to operate on.
  defp ensure_resolution_for_duration(%Tempo{} = tempo, duration_time) do
    # A microsecond component needs a `:second` slot to carry into, so
    # force at least second resolution when one is present.
    finest =
      if Keyword.has_key?(duration_time, :microsecond) do
        :second
      else
        finest_duration_unit(duration_time)
      end

    if finest == nil do
      tempo
    else
      case Tempo.extend_resolution(tempo, finest) do
        %Tempo{} = extended -> extended
        _ -> tempo
      end
    end
  end

  @unit_order_coarse_to_fine [:year, :month, :week, :day, :hour, :minute, :second]

  defp finest_duration_unit(duration_time) do
    duration_units = Keyword.keys(duration_time)

    @unit_order_coarse_to_fine
    |> Enum.reverse()
    |> Enum.find(&(&1 in duration_units))
  end

  # Apply duration components largest-to-smallest, then clamp day
  # to the valid range for the resulting month.
  @duration_apply_order [:year, :month, :day, :hour, :minute, :second]

  defp apply_duration(%Tempo{time: time, calendar: calendar} = tempo, duration_time) do
    new_time =
      @duration_apply_order
      |> Enum.reduce(time, fn unit, acc ->
        case Keyword.get(duration_time, unit, 0) do
          0 -> acc
          n -> apply_n_units(acc, unit, n, calendar)
        end
      end)
      |> apply_microsecond_duration(Keyword.get(duration_time, :microsecond), calendar)
      |> clamp_day_to_month(calendar)

    %{tempo | time: new_time}
  end

  # Sub-second durations are applied as a single signed shift of the
  # microsecond value rather than iterated `add_unit` calls (which
  # would be O(value)). A negative value (produced by `subtract/2`)
  # borrows from the second.
  defp apply_microsecond_duration(time, nil, _calendar), do: time
  defp apply_microsecond_duration(time, {0, _precision}, _calendar), do: time

  defp apply_microsecond_duration(time, {value, _precision}, calendar) do
    shift_microseconds(time, value, calendar)
  end

  @microseconds_per_second 1_000_000
  defp shift_microseconds(time, delta, calendar) do
    {current, precision} =
      case Keyword.get(time, :microsecond) do
        {v, p} -> {v, p}
        nil -> {0, 6}
      end

    total = current + delta
    whole_seconds = Integer.floor_div(total, @microseconds_per_second)
    remainder = Integer.mod(total, @microseconds_per_second)

    time
    |> put_microsecond(remainder, precision)
    |> apply_n_units(:second, whole_seconds, calendar)
  end

  # Set the microsecond component, preserving position if present and
  # appending (after the second) if absent.
  defp put_microsecond(time, value, precision) do
    if Keyword.has_key?(time, :microsecond) do
      Keyword.replace(time, :microsecond, {value, precision})
    else
      time ++ [{:microsecond, {value, precision}}]
    end
  end

  # Apply N steps of `add_unit` (or `subtract_unit` for negative N).
  # Simple iteration — correct for any calendar at the cost of
  # O(N) calls. For the durations we see in practice (months,
  # days, hours), this is fine; we can switch to calendar-specific
  # arithmetic if profiling demands it.
  defp apply_n_units(time, _unit, 0, _calendar), do: time

  defp apply_n_units(time, unit, n, calendar) when n > 0 do
    time
    |> add_unit(unit, calendar)
    |> apply_n_units(unit, n - 1, calendar)
  end

  defp apply_n_units(time, unit, n, calendar) when n < 0 do
    time
    |> subtract_unit(unit, calendar)
    |> apply_n_units(unit, n + 1, calendar)
  end

  # After month arithmetic, the day field may exceed days-in-month
  # (e.g. Jan 31 + 1 month = "Feb 31"). Clamp once at the end.
  defp clamp_day_to_month(time, calendar) do
    case Keyword.get(time, :day) do
      nil -> time
      day when is_integer(day) -> clamp_integer_day(time, day, calendar)
      _non_integer -> time
    end
  end

  defp clamp_integer_day(time, day, calendar) do
    if Keyword.has_key?(time, :year) do
      clamp_day_to_month_anchored(time, day, calendar)
    else
      clamp_day_to_month_unanchored(time, day, calendar)
    end
  end

  defp clamp_day_to_month_anchored(time, day, calendar) do
    year = Keyword.fetch!(time, :year)
    month = Keyword.fetch!(time, :month)
    days = calendar.days_in_month(year, month)

    if day > days, do: Keyword.replace!(time, :day, days), else: time
  end

  # Clamp without a year: a day that fits every possible length of the
  # month is kept; one that overflows an unambiguous month is clamped;
  # anything whose validity depends on the missing year (a 29th/30th of
  # a variable-length month) throws `:requires_anchor`.
  defp clamp_day_to_month_unanchored(time, day, calendar) do
    case calendar.days_in_month(Keyword.fetch!(time, :month)) do
      count when is_integer(count) ->
        if day > count, do: Keyword.replace!(time, :day, count), else: time

      {:ambiguous, range} ->
        if day <= Enum.min(range), do: time, else: throw({:tempo_math, :requires_anchor})

      _undefined ->
        throw({:tempo_math, :requires_anchor})
    end
  end

  @doc """
  Return the start-of-unit minimum value — used when a trailing
  unit is unspecified in a mixed-resolution comparison or when
  constructing the lower bound of an implicit span.

  ### Arguments

  * `unit` is any time unit atom.

  ### Returns

  * `1` for `:month`, `:day`, `:week`, `:day_of_year`, and
    `:day_of_week` — these count from 1.

  * `0` for every other unit (including `:hour`, `:minute`,
    `:second`, `:year`, and any unrecognised atom).

  ### Examples

      iex> Tempo.Math.unit_minimum(:month)
      1

      iex> Tempo.Math.unit_minimum(:hour)
      0

  """
  def unit_minimum(:month), do: 1
  def unit_minimum(:day), do: 1
  def unit_minimum(:week), do: 1
  def unit_minimum(:day_of_year), do: 1
  def unit_minimum(:day_of_week), do: 1
  def unit_minimum(_), do: 0
end
