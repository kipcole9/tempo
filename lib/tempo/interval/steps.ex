defmodule Tempo.Interval.Steps do
  @moduledoc """
  Closed-form step arithmetic for interval enumeration.

  Backs `Enumerable.Tempo.Interval`'s `count/1`, `slice/1`, and
  `member?/2` callbacks with O(1) (or near-O(1)) implementations
  driven by the calendar's date algebra rather than walking the
  interval one step at a time.

  Each function takes the iteration unit and the calendar in addition
  to the endpoints:

  * `count_steps/4` — how many `unit`-wide steps fit in
    `[from, to)`.

  * `nth_step/4` — the `n`-th element from `from` at `unit`
    granularity.

  * `on_step?/4` — whether `element` falls on a `unit`-step
    boundary anchored at `from`.

  Phase 1 covers `:year`, `:month`, and `:day`. Sub-day units
  (`:hour`, `:minute`, `:second`, `:microsecond`) are added in
  subsequent phases.

  """

  alias Tempo.Iso8601.AST

  @seconds_per_minute 60
  @seconds_per_hour 3_600
  @seconds_per_day 86_400
  @microseconds_per_second 1_000_000
  @max_precision 6

  @doc """
  Count the number of `unit`-wide steps in the half-open span
  `[from, to)`.

  ### Arguments

  * `from` is the lower-bound `t:Tempo.t/0`.

  * `to` is the exclusive upper-bound `t:Tempo.t/0`.

  * `unit` is one of `:year`, `:month`, `:day` (Phase 1 scope).

  * `calendar` is the shared calendar module of both endpoints.

  ### Returns

  * A non-negative integer count, or

  * `:not_supported` when the unit / calendar combination has no
    closed-form path. Callers should fall back to walking.

  ### Examples

      iex> from = Tempo.from_iso8601!("2026Y")
      iex> to = Tempo.from_iso8601!("2030Y")
      iex> Tempo.Interval.Steps.count_steps(from, to, :year, Calendrical.Gregorian)
      4

      iex> from = Tempo.from_iso8601!("2026-01")
      iex> to = Tempo.from_iso8601!("2027-03")
      iex> Tempo.Interval.Steps.count_steps(from, to, :month, Calendrical.Gregorian)
      14

      iex> from = Tempo.from_iso8601!("2026-01-01")
      iex> to = Tempo.from_iso8601!("2026-02-01")
      iex> Tempo.Interval.Steps.count_steps(from, to, :day, Calendrical.Gregorian)
      31

  """
  @spec count_steps(Tempo.t(), Tempo.t(), atom(), module()) ::
          non_neg_integer() | :not_supported
  def count_steps(%Tempo{time: from_time}, %Tempo{time: to_time}, :year, _calendar) do
    Keyword.fetch!(to_time, :year) - Keyword.fetch!(from_time, :year)
  end

  def count_steps(%Tempo{time: from_time}, %Tempo{time: to_time}, :month, calendar) do
    from_y = Keyword.fetch!(from_time, :year)
    from_m = Keyword.fetch!(from_time, :month)
    to_y = Keyword.fetch!(to_time, :year)
    to_m = Keyword.fetch!(to_time, :month)
    months_between(from_y, from_m, to_y, to_m, calendar)
  end

  def count_steps(%Tempo{time: from_time}, %Tempo{time: to_time}, :day, calendar) do
    to_days_since_epoch(to_time, calendar) - to_days_since_epoch(from_time, calendar)
  end

  def count_steps(%Tempo{time: from_time}, %Tempo{time: to_time}, :hour, calendar) do
    div(wall_seconds(to_time, calendar) - wall_seconds(from_time, calendar), @seconds_per_hour)
  end

  def count_steps(%Tempo{time: from_time}, %Tempo{time: to_time}, :minute, calendar) do
    div(wall_seconds(to_time, calendar) - wall_seconds(from_time, calendar), @seconds_per_minute)
  end

  def count_steps(%Tempo{time: from_time}, %Tempo{time: to_time}, :second, calendar) do
    wall_seconds(to_time, calendar) - wall_seconds(from_time, calendar)
  end

  def count_steps(%Tempo{time: from_time}, %Tempo{time: to_time}, :microsecond, calendar) do
    {_value, precision} = Keyword.fetch!(from_time, :microsecond)
    step = Integer.pow(10, @max_precision - precision)
    div(wall_microseconds(to_time, calendar) - wall_microseconds(from_time, calendar), step)
  end

  def count_steps(_from, _to, _unit, _calendar), do: :not_supported

  @doc """
  Return the Tempo at step `n` from `from` at `unit` granularity.

  ### Arguments

  * `from` is the anchor `t:Tempo.t/0`.

  * `n` is a non-negative integer step count (0 returns `from`).

  * `unit` is one of `:year`, `:month`, `:day` (Phase 1 scope).

  * `calendar` is the calendar module.

  ### Returns

  * The Tempo at step `n`, or

  * `:not_supported` for unhandled units.

  ### Examples

      iex> from = Tempo.from_iso8601!("2026-01-01")
      iex> Tempo.Interval.Steps.nth_step(from, 30, :day, Calendrical.Gregorian)
      ~o"2026Y1M31D"

      iex> from = Tempo.from_iso8601!("2026-01")
      iex> Tempo.Interval.Steps.nth_step(from, 14, :month, Calendrical.Gregorian)
      ~o"2027Y3M"

  """
  @spec nth_step(Tempo.t(), non_neg_integer(), atom(), module()) ::
          Tempo.t() | :not_supported
  def nth_step(%Tempo{time: time} = tempo, n, :year, _calendar) do
    year = Keyword.fetch!(time, :year)
    %{tempo | time: Keyword.replace(time, :year, year + n)}
  end

  def nth_step(%Tempo{time: time} = tempo, n, :month, calendar) do
    year = Keyword.fetch!(time, :year)
    month = Keyword.fetch!(time, :month)
    {new_year, new_month} = add_months(year, month, n, calendar)

    %{
      tempo
      | time:
          time
          |> Keyword.replace(:year, new_year)
          |> Keyword.replace(:month, new_month)
    }
  end

  def nth_step(%Tempo{time: time, calendar: calendar} = tempo, n, :day, calendar) do
    days = to_days_since_epoch(time, calendar) + n
    {y, m, d} = from_days_since_epoch(days, calendar)

    %{
      tempo
      | time:
          time
          |> Keyword.replace(:year, y)
          |> Keyword.replace(:month, m)
          |> Keyword.replace(:day, d)
    }
  end

  def nth_step(%Tempo{time: time, calendar: calendar} = tempo, n, :hour, calendar) do
    new_seconds = wall_seconds(time, calendar) + n * @seconds_per_hour
    %{tempo | time: replace_date_time(time, new_seconds, calendar)}
  end

  def nth_step(%Tempo{time: time, calendar: calendar} = tempo, n, :minute, calendar) do
    new_seconds = wall_seconds(time, calendar) + n * @seconds_per_minute
    %{tempo | time: replace_date_time(time, new_seconds, calendar)}
  end

  def nth_step(%Tempo{time: time, calendar: calendar} = tempo, n, :second, calendar) do
    new_seconds = wall_seconds(time, calendar) + n
    %{tempo | time: replace_date_time(time, new_seconds, calendar)}
  end

  def nth_step(%Tempo{time: time, calendar: calendar} = tempo, n, :microsecond, calendar) do
    {_value, precision} = Keyword.fetch!(time, :microsecond)
    step = Integer.pow(10, @max_precision - precision)
    new_micros = wall_microseconds(time, calendar) + n * step
    new_seconds = Integer.floor_div(new_micros, @microseconds_per_second)
    new_us_value = Integer.mod(new_micros, @microseconds_per_second)

    new_time =
      time
      |> replace_date_time(new_seconds, calendar)
      |> Keyword.replace(:microsecond, {new_us_value, precision})

    %{tempo | time: new_time}
  end

  def nth_step(_from, _n, _unit, _calendar), do: :not_supported

  @doc """
  Return `true` when `element` falls on a `unit`-step boundary
  anchored at `from`.

  ### Arguments

  * `element` is any `t:Tempo.t/0`.

  * `from` is the anchor `t:Tempo.t/0`.

  * `unit` is one of `:year`, `:month`, `:day` (Phase 1 scope).

  * `calendar` is the calendar module.

  ### Returns

  * `true` if `element` equals `from` advanced by some non-negative
    integer number of `unit` steps, `false` otherwise, or
    `:not_supported`.

  ### Examples

      iex> from = Tempo.from_iso8601!("2026-01-01")
      iex> elt = Tempo.from_iso8601!("2026-01-31")
      iex> Tempo.Interval.Steps.on_step?(elt, from, :day, Calendrical.Gregorian)
      true

  """
  @spec on_step?(Tempo.t(), Tempo.t(), atom(), module()) :: boolean() | :not_supported
  def on_step?(element, from, unit, calendar) do
    case count_steps(from, element, unit, calendar) do
      :not_supported -> :not_supported
      n when n >= 0 -> step_matches?(element, from, n, unit, calendar)
      _ -> false
    end
  end

  # Verify the candidate element exactly matches `nth_step(from, n, unit)`.
  # `count_steps` may produce a positive integer for an element that is
  # not on a step boundary (e.g. a finer-resolution element); the round-trip
  # check ensures element is precisely the n-th step.
  defp step_matches?(element, from, n, unit, calendar) do
    case nth_step(from, n, unit, calendar) do
      :not_supported -> :not_supported
      %Tempo{time: time} -> Keyword.equal?(time, element.time)
    end
  end

  ## ----------------------------------------------------------
  ## Helpers
  ## ----------------------------------------------------------

  # Calendar-aware month difference. For calendars with constant 12
  # months per year (Gregorian, Julian, Coptic, Ethiopic, Persian),
  # this is the pure modular formula. For varying-month calendars
  # (Hebrew/Metonic), we sum across the spanned years — bounded by
  # the 19-year Metonic cycle in practice.
  defp months_between(from_y, from_m, to_y, to_m, calendar) do
    if constant_twelve_months?(calendar, from_y, to_y) do
      (to_y - from_y) * 12 + (to_m - from_m)
    else
      months_in_years_between(from_y, to_y, calendar) + (to_m - from_m)
    end
  end

  defp constant_twelve_months?(calendar, from_y, to_y) do
    calendar.months_in_year(from_y) == 12 and calendar.months_in_year(to_y) == 12
  end

  defp months_in_years_between(from_y, to_y, _calendar) when from_y == to_y, do: 0

  defp months_in_years_between(from_y, to_y, calendar) when from_y < to_y do
    Enum.reduce(from_y..(to_y - 1)//1, 0, fn y, acc ->
      acc + calendar.months_in_year(y)
    end)
  end

  # Month addition in calendar-month-modular space. For 12-month
  # calendars, this is the closed-form formula. For Hebrew, we walk
  # across the 19-year cycle (bounded).
  defp add_months(year, month, n, calendar) do
    if calendar.months_in_year(year) == 12 and
         calendar.months_in_year(year + div(n, 12) + 1) == 12 do
      total = year * 12 + (month - 1) + n
      {Integer.floor_div(total, 12), Integer.mod(total, 12) + 1}
    else
      walk_months(year, month, n, calendar)
    end
  end

  defp walk_months(year, month, 0, _calendar), do: {year, month}

  defp walk_months(year, month, n, calendar) when n > 0 do
    months_this_year = calendar.months_in_year(year)

    if month + 1 > months_this_year do
      walk_months(year + 1, 1, n - 1, calendar)
    else
      walk_months(year, month + 1, n - 1, calendar)
    end
  end

  defp walk_months(year, month, n, calendar) when n < 0 do
    if month - 1 < 1 do
      months_prev_year = calendar.months_in_year(year - 1)
      walk_months(year - 1, months_prev_year, n + 1, calendar)
    else
      walk_months(year, month - 1, n + 1, calendar)
    end
  end

  defp to_days_since_epoch(time, calendar) do
    year = Keyword.fetch!(time, :year)
    month = Keyword.fetch!(time, :month)
    day = Keyword.fetch!(time, :day)
    calendar.date_to_iso_days(year, month, day)
  end

  defp from_days_since_epoch(days, calendar) do
    calendar.date_from_iso_days(days)
  end

  # Wall-clock seconds since the calendar's ISO-days epoch — purely
  # arithmetic, ignoring time-zone offset. For two endpoints in the
  # same zone (or both UTC, or both fixed-offset), the offset cancels
  # in the difference, so step counts are correct *as long as no DST
  # transition falls in the interval*. DST correction lives in Phase 3.
  defp wall_seconds(time, calendar) do
    day_seconds = to_days_since_epoch(time, calendar) * @seconds_per_day
    hour = Keyword.get(time, :hour, 0)
    minute = Keyword.get(time, :minute, 0)
    second = Keyword.get(time, :second, 0)
    day_seconds + hour * @seconds_per_hour + minute * @seconds_per_minute + second
  end

  defp wall_microseconds(time, calendar) do
    base = wall_seconds(time, calendar) * @microseconds_per_second

    case Keyword.get(time, :microsecond) do
      {value, _precision} -> base + value
      nil -> base
    end
  end

  # Convert a total wall-clock second count back into the date / time-
  # of-day components of `time`, preserving the original component
  # set: an hour-resolution endpoint stays hour-resolution (no minute
  # / second added), a minute-resolution endpoint stays minute-
  # resolution, and so on.
  defp replace_date_time(time, total_seconds, calendar) do
    days = Integer.floor_div(total_seconds, @seconds_per_day)
    time_of_day_seconds = Integer.mod(total_seconds, @seconds_per_day)
    hour = div(time_of_day_seconds, @seconds_per_hour)
    minute = div(rem(time_of_day_seconds, @seconds_per_hour), @seconds_per_minute)
    second = rem(time_of_day_seconds, @seconds_per_minute)
    {y, m, d} = from_days_since_epoch(days, calendar)

    time
    |> Keyword.replace(:year, y)
    |> Keyword.replace(:month, m)
    |> Keyword.replace(:day, d)
    |> maybe_replace(:hour, hour)
    |> maybe_replace(:minute, minute)
    |> maybe_replace(:second, second)
  end

  defp maybe_replace(time, key, value) do
    if Keyword.has_key?(time, key), do: Keyword.replace(time, key, value), else: time
  end

  # Suppress an unused-alias warning if `AST` ends up unreferenced in
  # later edits. Keeping the alias declaration documents the future
  # intent of using `AST.build/1,2` for reconstruction shortcuts.
  _ = AST
end
