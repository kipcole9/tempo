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
  end

  def add_unit(time, :day, calendar) when is_list(time) do
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
  end

  def subtract_unit(time, :day, calendar) when is_list(time) do
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
  @spec add(Tempo.t(), Tempo.Duration.t()) :: Tempo.t()
  def add(%Tempo{} = tempo, %Tempo.Duration{time: duration_time}) do
    tempo =
      tempo
      |> ensure_resolution_for_duration(duration_time)

    duration_time = normalise_duration(duration_time)
    apply_duration(tempo, duration_time)
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
  @spec subtract(Tempo.t(), Tempo.Duration.t()) :: Tempo.t()
  def subtract(%Tempo{} = tempo, %Tempo.Duration{time: duration_time}) do
    negated =
      Enum.map(duration_time, fn {unit, amount} -> {unit, -amount} end)

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
    finest = finest_duration_unit(duration_time)

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
      |> clamp_day_to_month(calendar)

    %{tempo | time: new_time}
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
      nil ->
        time

      day when is_integer(day) ->
        year = Keyword.fetch!(time, :year)
        month = Keyword.fetch!(time, :month)
        days = calendar.days_in_month(year, month)

        if day > days do
          Keyword.replace!(time, :day, days)
        else
          time
        end

      _non_integer ->
        time
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
