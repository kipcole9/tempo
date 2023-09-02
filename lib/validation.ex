defmodule Tempo.Validation do
  @moduledoc false

  # This function performs two roles (and maybe should be split):
  #
  # 1. Expand groups into basic time units where there is enough information to do so and
  # 2. Ensures that basic units are valid (days in months, months in year etc)

  # There is ample room to refactor into a more generalised solution for much of
  # the resolution task. For now, being completely explicit aids implementation and
  # debugging. Refactoring to a generalised case will come later.

  @hours_per_day 24
  @minutes_per_hour 60
  @rounding_precision 10

  def validate(tempo, calendar \\ Cldr.Calendar.Gregorian)

  def validate(%Tempo{time: units} = tempo, calendar) do
    case resolve(units, calendar) do
      {:error, reason} -> {:error, reason}
      other -> {:ok, %{tempo | time: other}}
    end
  end

  # TODO Check that the second time is after the first (ISO expectation)
  # TODO Adjust the second time if its time shift is different to the first

  def validate(%Tempo.Interval{} = tempo, calendar) do
    with {:ok, from} <- validate(tempo.from, calendar),
         {:ok, to} <- validate(tempo.to, calendar),
         {:ok, duration} <- validate(tempo.duration, calendar) do
      {:ok, %{tempo | from: from, to: to, duration: duration}}
    end
  end

  def validate(%Tempo.Duration{} = duration, _calendar) do
    {:ok, duration}
  end

  def validate(%Tempo.Set{set: set} = tempo, calendar) do
    validated =
      Enum.reduce_while(set, [], fn elem, acc ->
        case resolve(elem, calendar) do
          {:error, reason} -> {:halt, {:error, reason}}
          units -> {:cont, [units | acc]}
        end
      end)

    case validated do
      {:error, reason} -> {:error, reason}
      resolved -> {:ok, %{tempo | set: Enum.reverse(resolved)}}
    end
  end

  def validate(nil, _calendar) do
    {:ok, nil}
  end

  def validate(:undefined, _calendar) do
    {:ok, :undefined}
  end

  # Resolution is the process of pre-calculating concrete
  # time units from groups whereever possible.

  def resolve([{:day_of_week, day} | rest], calendar) when is_integer(day) do
    days_in_week = calendar.days_in_week()

    with {:ok, day} <- conform(day, 1..days_in_week) do
      case resolve(rest, calendar) do
        {:error, reason} -> {:error, reason}
        resolved -> [{:day_of_week, day} | resolved]
      end
    end
  end

  # When a group of years succeeds a century or decade
  # Here we merge into a set.

  def resolve(
        [{unit, {:group, %Range{} = range1}}, {unit, {:group, %Range{} = range2}} | rest],
        calendar
      ) do
    first = range1.first + range2.first - 1

    if first in 1..range1.last do
      last = min(range1.last, first + range2.last - range2.first)
      resolve([{unit, [first..last]} | rest], calendar)
    else
      {:error,
       "#{inspect(first)} is outside the #{unit} range #{inspect(range1)} " <>
         "for the calendar #{inspect(calendar)}"}
    end
  end

  def resolve([{:year, {:group, %Range{} = years}}, {:month, month} | rest], calendar)
      when is_integer(month) do
    months_in_group =
      years
      |> Enum.map(&calendar.months_in_year/1)
      |> Enum.sum()

    with {:ok, month} <- conform(month, 1..months_in_group) do
      {:ok, year, month} = year_and_month(years, month, calendar)
      resolve([{:year, year}, {:month, month} | rest], calendar)
    end
  end

  def resolve(
        [{:year, year}, {:month, {:group, %Range{} = months}}, {:day, day} | rest],
        calendar
      )
      when is_integer(year) and is_integer(day) do
    days_in_group =
      months
      |> Enum.map(&calendar.days_in_month(year, &1))
      |> Enum.sum()

    with {:ok, day} <- conform(day, 1..days_in_group) do
      {:ok, month, day} = month_and_day(year, months, day, calendar)
      resolve([{:year, year}, {:month, month}, {:day, day} | rest], calendar)
    end
  end

  # TODO Make sure that the day of week fits into the available
  # days in the last week

  def resolve([{:year, year}, {:week, week}, {:day_of_week, day} | rest], calendar)
      when is_integer(year) and is_integer(week) and is_integer(day) do
    {weeks_in_year, _days_in_last_week} = calendar.weeks_in_year(year)

    with {:ok, week} <- conform(week, 1..weeks_in_year),
         [day_of_week: day] <- resolve([day_of_week: day], calendar) do
      year_week_day(year, week, day, rest, calendar.calendar_base, calendar)
    end
  end

  def resolve([{:year, year}, {:day, day_of_year} | rest], calendar)
      when is_integer(year) and is_integer(day_of_year) do
    days_in_year = calendar.days_in_year(year)

    with {:ok, day_of_year} <- conform(day_of_year, 1..days_in_year) do
      %{year: year, month: month, day: day} =
        Cldr.Calendar.date_from_day_of_year(year, day_of_year, calendar)

      resolve([{:year, year}, {:month, month}, {:day, day} | rest], calendar)
    end
  end

  def resolve(
        [{:year, year}, {:day, {:group, %Range{} = days_of_year}}, {:day, day} | rest],
        calendar
      )
      when is_integer(year) and is_integer(day) do
    %{first: first, last: last} = days_of_year
    days_in_year = calendar.days_in_year(year)
    last = min(last, days_in_year)
    day = if day < 0, do: last + day + 1, else: first + day - 1

    if first in 1..days_in_year and day <= last do
      %{year: year, month: month, day: day} =
        Cldr.Calendar.date_from_day_of_year(year, day, calendar)

      resolve([{:year, year}, {:month, month}, {:day, day} | rest], calendar)
    else
      {:error,
       "#{inspect(abs(day))} is outside the group #{inspect(days_of_year)} " <>
         "for the calendar #{inspect(calendar)}"}
    end
  end

  def resolve(
        [{:year, year}, {:hour, {:group, %Range{} = hours_of_year}}, {:hour, hour} | rest],
        calendar
      )
      when is_integer(year) and is_integer(hour) do
    %{first: first, last: last} = hours_of_year
    hours_in_year = calendar.days_in_year(year) * @hours_per_day
    last = min(last, hours_in_year)
    hour = if hour < 0, do: last + hour + 1, else: first + hour - 1

    with {:ok, _first} <- conform(first, 1..hours_in_year) do
      day = div(hour, @hours_per_day) + 1
      hour = rem(hour, @hours_per_day)

      %{year: year, month: month, day: day} =
        Cldr.Calendar.date_from_day_of_year(year, day, calendar)

      resolve([{:year, year}, {:month, month}, {:day, day}, {:hour, hour} | rest], calendar)
    end
  end

  def resolve(
        [{:year, year}, {:month, month}, {:day, {:group, %Range{} = days}} | rest],
        calendar
      )
      when is_integer(year) and is_integer(month) do
    months_in_year = calendar.months_in_year(year)

    with {:ok, month} <- conform(month, 1..months_in_year) do
      max_days = calendar.days_in_month(year, month)

      case resolve([{:day, {:group, %{days | last: min(max_days, days.last)}}} | rest], calendar) do
        {:error, reason} -> {:error, reason}
        resolved -> [{:year, year}, {:month, month} | resolved]
      end
    end
  end

  # days needs to start at 1
  def resolve([{:day, {:group, %Range{} = range}}, {:hour, hours} | rest], calendar)
      when is_integer(hours) do
    first = (range.first - 1) * @hours_per_day
    last = range.last * @hours_per_day - 1
    hours = hours + first

    with {:ok, hours} <- conform(hours, first..last) do
      days = div(hours, @hours_per_day)
      hours = rem(hours, @hours_per_day)
      resolve([{:day, days + 1}, {:hour, hours} | rest], calendar)
    end
  end

  # hours start at 0
  def resolve([{:hour, {:group, %Range{} = range}}, {:minute, minutes} | rest], calendar)
      when is_integer(minutes) do
    first = (range.first - 1) * @minutes_per_hour
    last = range.last * @minutes_per_hour - 1
    minutes = minutes + first

    with {:ok, minutes} <- conform(minutes, first..last) do
      hours = div(minutes, @minutes_per_hour)
      minutes = rem(minutes, @minutes_per_hour)

      resolve([{:hour, hours}, {:minute, minutes} | rest], calendar)
    end
  end

  # minutes start at 0
  def resolve([{:minute, {:group, %Range{} = range}}, {:second, seconds} | rest], calendar)
      when is_integer(seconds) do
    first = (range.first - 1) * @minutes_per_hour
    last = range.last * @minutes_per_hour - 1
    seconds = seconds + first

    with {:ok, seconds} <- conform(seconds, first..last) do
      minutes = div(seconds, @minutes_per_hour)
      seconds = rem(seconds, @minutes_per_hour)

      resolve([{:minute, minutes}, {:second, seconds} | rest], calendar)
    end
  end

  def resolve([{:year, year}, {:month, month}, {:day, day} | rest], calendar)
      when is_integer(year) and is_integer(month) and (is_number(day) or is_struct(day, Range)) do
    with [{:year, year}, {:month, month}] <- resolve([{:year, year}, {:month, month}], calendar) do
      days_in_month = calendar.days_in_month(year, month)

      with {:ok, day} <- conform(day, 1..days_in_month) do
        case resolve([{:day, day} | rest], calendar) do
          {:error, reason} -> {:error, reason}
          resolved -> [{:year, year}, {:month, month} | resolved]
        end
      end
    end
  end

  def resolve([{:year, year}, {:month, month}, {:day, day} | rest], calendar)
      when (is_integer(year) and is_integer(month)) or is_list(month) do
    with [{:year, year}, {:month, month}] <- resolve([{:year, year}, {:month, month}], calendar) do
      case resolve(rest, calendar) do
        {:error, reason} -> {:error, reason}
        resolved -> [{:year, year}, {:month, month}, {:day, day} | resolved]
      end
    end
  end

  def resolve([{:year, year}, {:month, months}], calendar)
      when is_integer(year) and (is_list(months) or is_integer(months)) do
    months_in_year = calendar.months_in_year(year)

    with {:ok, month} <- conform(months, 1..months_in_year) do
      [{:year, year}, {:month, month}]
    end
  end

  def resolve([{:year, year}, {:week, weeks}], calendar)
      when is_integer(year) and (is_list(weeks) or is_integer(weeks)) do
    {weeks_in_year, _} = calendar.weeks_in_year(year)

    with {:ok, weeks} <- conform(weeks, 1..weeks_in_year) do
      [{:year, year}, {:week, weeks}]
    end
  end

  def resolve([{:year, year}, {:day, days}], calendar)
      when is_integer(year) and (is_list(days) or is_integer(days)) do
    days_in_year = calendar.days_in_year(year)

    with {:ok, day} <- conform(days, 1..days_in_year) do
      [{:year, year}, {:day, day}]
    end
  end

  def resolve([{:month, month}, {:day, days} | _rest], calendar)
      when is_integer(month) and is_list(days) do
    with days_in_month when is_integer(days_in_month) <- calendar.days_in_month(month),
         {:ok, days} <- conform(days, 1..days_in_month) do
      [{:month, month}, {:day, days}]
    else
      {:ambiguous, _values} ->
        {:error, "Cannot resolve days in month #{month} without knowing the year"}

      other ->
        other
    end
  end

  # Calculating the result of fractional time units
  # TODO Support negative time fractions

  def resolve([{:year, year}], calendar) when is_float(year) and year > 0 do
    int_year = trunc(year)
    fraction_of_year = year - int_year
    days_in_year = calendar.days_in_year(int_year)

    if fraction_of_year == 0 do
      resolve([{:year, int_year}], calendar)
    else
      days = Cldr.Math.round(days_in_year * fraction_of_year, @rounding_precision)
      days = if trunc(days) == days, do: trunc(days), else: days
      resolve([{:year, int_year}, {:day, days}], calendar)
    end
  end

  def resolve([{:year, year}, {:month, month}], calendar)
      when is_integer(year) and is_float(month) and month > 0 do
    int_month = trunc(month)
    fraction_of_month = month - int_month
    days_in_month = calendar.days_in_month(year, int_month)

    if fraction_of_month == 0 do
      resolve([{:year, year}, {:month, int_month}], calendar)
    else
      days = Cldr.Math.round(days_in_month * fraction_of_month, @rounding_precision)
      days = if trunc(days) == days, do: trunc(days), else: days
      resolve([{:year, year}, {:month, int_month}, {:day, days}], calendar)
    end
  end

  def resolve([{:year, year}, {:day, day}], calendar)
      when is_integer(year) and is_float(day) and day > 0 do
    int_day = trunc(day)
    fraction_of_day = day - int_day

    if fraction_of_day == 0 do
      resolve([{:year, year}, {:day, int_day}], calendar)
    else
      hours = Cldr.Math.round(@hours_per_day * fraction_of_day, @rounding_precision)
      hours = if trunc(hours) == hours, do: trunc(hours), else: hours
      resolve([{:year, year}, {:day, int_day}, {:hour, hours}], calendar)
    end
  end

  def resolve([{:day, day}], calendar) when is_float(day) and day > 0 do
    int_day = trunc(day)
    fraction_of_day = day - int_day

    if fraction_of_day == 0 do
      [{:day, int_day}]
    else
      hours = Cldr.Math.round(@hours_per_day * fraction_of_day, @rounding_precision)
      hours = if trunc(hours) == hours, do: trunc(hours), else: hours
      resolve([{:day, int_day}, {:hour, hours}], calendar)
    end
  end

  def resolve([{:hour, hour}], _calendar) when is_float(hour) and hour > 0 do
    int_hour = trunc(hour)
    fraction_of_hour = hour - int_hour

    if fraction_of_hour == 0 do
      [{:hour, int_hour}]
    else
      minutes = Cldr.Math.round(60 * fraction_of_hour, @rounding_precision)
      minutes = if trunc(minutes) == minutes, do: trunc(minutes), else: minutes
      [{:hour, int_hour}, {:minute, minutes}]
    end
  end

  def resolve([{:minute, minute}], _calendar) when is_float(minute) do
    int_minute = trunc(minute)
    fraction_of_minute = minute - int_minute

    if fraction_of_minute == 0 do
      [{:minute, int_minute}]
    else
      seconds = Cldr.Math.round(60 * fraction_of_minute, @rounding_precision)
      seconds = if trunc(seconds) == seconds, do: trunc(seconds), else: seconds
      [{:minute, int_minute}, {:second, seconds}]
    end
  end

  # Fill in the blanks with default unit values
  def resolve([{unit_1, value_1}, {:minute, minute} | rest], calendar) when unit_1 != :hour do
    resolve([{unit_1, value_1}, {:hour, 0}, {:minute, minute} | rest], calendar)
  end

  def resolve([{unit_1, value_1}, {:second, second} | rest], calendar) when unit_1 != :minute do
    resolve([{unit_1, value_1}, {:minute, 0}, {:second, second} | rest], calendar)
  end

  # Make sure only the last element is a fraction

  def resolve([{_unit, fraction}, {_unit_2, _value} | _rest], _calendar)
      when is_float(fraction) do
    {:error,
     "A fractional unit can only be used for the highest resolution unit (smallest time unit)"}
  end

  def resolve([{:hour, hour} | rest], calendar) when is_integer(hour) do
    with {:ok, hour} <- conform(hour, 0..(@hours_per_day - 1)) do
      case resolve(rest, calendar) do
        {:error, reason} -> {:error, reason}
        resolved -> [{:hour, hour} | resolved]
      end
    end
  end

  def resolve([{:hour, %Range{first: first, last: last, step: step}} | rest], calendar)
      when first > 0 and last < 0 do
    with {:ok, last} <- conform(last, 0..(@hours_per_day - 1)) do
      case resolve(rest, calendar) do
        {:error, reason} -> {:error, reason}
        resolved -> [{:hour, first..last//abs(step)} | resolved]
      end
    end
  end

  def resolve([{unit, requested} | rest], calendar)
      when unit in [:minute, :second] and is_integer(requested) do
    with {:ok, part} <- conform(requested, 0..(@minutes_per_hour - 1)) do
      case resolve(rest, calendar) do
        {:error, reason} -> {:error, reason}
        resolved -> [{unit, part} | resolved]
      end
    end
  end

  def resolve([{unit, _value} = first | rest], calendar) do
    with {^unit, _} = first <- resolve(first, calendar),
         rest when is_list(rest) <- resolve(rest, calendar) do
      [first | rest]
    end
  end

  def resolve(other, _calendar) do
    other
  end

  ### Helpers

  def year_week_day(year, week, day, rest, :month, calendar) do
    {weeks_in_year, days_in_last_week} = calendar.weeks_in_year(year)

    if day <= days_in_last_week do
      %Date.Range{first: start_of_week} = calendar.week(year, week)
      iso_days = Cldr.Calendar.date_to_iso_days(start_of_week) + day - 1
      {year, month, day} = calendar.date_from_iso_days(iso_days)

      case resolve([{:month, month}, {:day, day} | rest], calendar) do
        {:error, reason} -> {:error, reason}
        resolved -> [{:year, year} | resolved]
      end
    else
      {:error,
       "Day of week #{inspect(day)} is not valid. " <>
         "There are #{inspect(days_in_last_week)} days in #{inspect(year)}-W#{inspect(weeks_in_year)}."}
    end
  end

  def year_week_day(year, week, day, rest, :week, calendar) do
    case resolve([{:week, week}, {:day, day} | rest], calendar) do
      {:error, reason} -> {:error, reason}
      resolved -> [{:year, year} | resolved]
    end
  end

  def year_and_month(years, month, calendar) do
    return =
      Enum.reduce_while(years, {calendar.months_in_year(years.first), month}, fn year,
                                                                                 {acc, to_go} ->
        months_in_year = calendar.months_in_year(year)

        if to_go <= months_in_year do
          {:halt, {:ok, year, to_go}}
        else
          {:cont, {acc + months_in_year, to_go - months_in_year}}
        end
      end)

    case return do
      {:ok, year, month} -> {:ok, year, month}
      _other -> {:error, :invalid_date}
    end
  end

  def month_and_day(year, months, day, calendar) do
    return =
      Enum.reduce_while(months, {calendar.days_in_month(year, months.first), day}, fn month,
                                                                                      {acc, to_go} ->
        days_in_month = calendar.days_in_month(year, month)

        if to_go <= days_in_month do
          {:halt, {:ok, month, to_go}}
        else
          {:cont, {acc + days_in_month, to_go - days_in_month}}
        end
      end)

    case return do
      {:ok, month, day} -> {:ok, month, day}
      _other -> {:error, :invalid_date}
    end
  end

  def conform(integer, %Range{first: first, last: last})
      when is_integer(integer) and integer in first..last do
    {:ok, integer}
  end

  def conform(float, %Range{first: first, last: last})
      when is_float(float) and float >= first and float <= last do
    {:ok, float}
  end

  def conform(integer, %Range{last: last} = range) when is_integer(integer) and integer < 0 do
    value = last + integer + 1

    case value >= 0 && conform(value, range) do
      {:ok, value} ->
        {:ok, value}

      {:error, _} ->
        normalized_error(integer, value, range)

      false ->
        normalized_error(integer, value, range)
    end
  end

  def conform(%Range{first: f1, last: t1} = from, %Range{first: f2, last: t2})
      when f1 in f2..t2 and t1 in f2..t2 do
    {:ok, from}
  end

  def conform(%Range{first: f1, last: t1, step: step}, %Range{} = to) do
    with {:ok, from} <- conform(f1, to),
         {:ok, to} <- conform(t1, to) do
      {:ok, from..to//abs(step)}
    end
  end

  def conform(from, to) when is_list(from) do
    conformed =
      Enum.reduce_while(from, {:ok, []}, fn unit, {:ok, acc} ->
        case conform(unit, to) do
          {:ok, conformed} -> {:cont, {:ok, [conformed | acc]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case conformed do
      {:error, reason} -> {:error, reason}
      {:ok, other} -> {:ok, Enum.reverse(other)}
    end
  end

  def conform(from, to) do
    {:error, "#{inspect(from)} is not valid. The valid values are #{inspect(to)}"}
  end

  defp normalized_error(value, normalized, range) do
    {:error,
     "#{inspect(value)} is not valid. The normalized value of #{inspect(normalized)} " <>
       "is outside the range #{inspect(range)}"}
  end
end
