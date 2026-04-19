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
