defmodule Tempo.Validation do
  @hours_per_day 24
  # @minutes_per_hour 60
  # @seconds_per_minute 60
  @rounding_precision 10

  def validate(tempo, calendar)

  def validate({:ok, %Tempo{} = tempo}, calendar) do
    validate(tempo, calendar)
  end

  def validate(%Tempo{time: units} = tempo, calendar) do
    case resolve(units, calendar) do
      {:error, reason} -> {:error, reason}
      other -> {:ok, %{tempo | time: other}}
    end
  end

  # TODO Check that the second time is after the first (ISO expectation)
  # TODO Adjust the second time if its time shift is different to the first
  def validate({:ok, %Tempo.Interval{} = tempo}, calendar) do
    with {:ok, from} <- validate(tempo.from, calendar),
         {:ok, to} <- validate(tempo.to, calendar),
         {:ok, duration} <- validate(tempo.duration, calendar) do
      {:ok, %{tempo | from: from, to: to, duration: duration}}
    end
  end

  def validate({:ok, %Tempo.Duration{} = duration}, calendar) do
    validate(duration, calendar)
  end

  def validate(%Tempo.Duration{} = duration, _calendar) do
    {:ok, duration}
  end

  def validate({:ok, %Tempo.Set{set: set} = tempo}, calendar) do
    validated =
      Enum.reduce_while set, [], fn elem, acc ->
        case resolve(elem, calendar) do
          {:error, reason} -> {:halt, {:error, reason}}
          units -> {:cont, [units | acc]}
        end
      end

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

  def validate({:error, reason}, _calendar) do
    {:error, reason}
  end

  def resolve([{:day_of_week, day} | rest], calendar) do
    days_in_week = calendar.days_in_week()
    day = if day < 0, do: days_in_week + day + 1, else: day

    if abs(day) in 1..days_in_week do
      [{:day_of_week, day} | resolve(rest, calendar)]
    else
      {:error,
        "#{inspect abs(day)} is greater than #{days_in_week} which is the number " <>
         "of days in a week for the calendar #{inspect calendar}"
      }
    end
  end

  # When a group of years succeeds a century or decade
  # Here we merge into a set
  def resolve([{unit, %Range{} = range1}, {unit, %Range{} = range2} | rest], calendar) do
    first = range1.first + range2.first - 1

    if first in 1..range1.last do
      last = min(range1.last, first + range2.last - range2.first)
      resolve([{unit, [first..last]} | rest], calendar)
    else
      {:error,
        "#{inspect first} is outside the #{unit} range #{inspect range1} " <>
         "for the calendar #{inspect calendar}"
      }
    end
  end

  def resolve([{:year, %Range{} = years}, {:month, month} | rest], calendar) when is_integer(month) do
    months_in_group =
      years
      |> Enum.map(&calendar.months_in_year/1)
      |> Enum.sum()

    if abs(month) in 1..months_in_group do
      month = if month < 0, do: months_in_group + month + 1, else: month
      {:ok, year, month} = year_and_month(years, month, calendar)
      resolve([{:year, year}, {:month, month} | rest], calendar)
    else
      {:error,
        "#{inspect abs(month)} is greater than #{inspect months_in_group} which " <>
         "is the number of months in the group of years #{inspect years} for the calendar #{inspect calendar}"
      }
    end
  end

  def resolve([{:year, year}, {:month, %Range{} = months}, {:day, day} | rest], calendar)
      when is_integer(year) and is_integer(day) do
    days_in_group =
      months
      |> Enum.map(&calendar.days_in_month(year, &1))
      |> Enum.sum()

    if abs(day) in 1..days_in_group do
      day = if day < 0, do: days_in_group + day + 1, else: day
      {:ok, month, day} = month_and_day(year, months, day, calendar)
      resolve([{:year, year}, {:month, month}, {:day, day} | rest], calendar)
    else
      {:error,
        "#{inspect abs(day)} is greater than #{inspect days_in_group} which " <>
         "is the number of days in the group of months #{inspect months} for the calendar #{inspect calendar}"
      }
    end
  end

  def resolve([{:year, year}, {:week, week}, {:day_of_week, day} | rest], calendar)
      when is_integer(year) and is_integer(week) and is_integer(day) do
    weeks_in_year = calendar.weeks_in_year(year)
    week = if week < 0, do: weeks_in_year + week - 1, else: week

    with [day_of_week: day] <- resolve([day_of_week: day], calendar) do
      if week in 1..weeks_in_year do
        if calendar.calendar_base == :month do
          %Date.Range{first: start_of_week} = calendar.week(year, week)
          iso_days = Cldr.Calendar.date_to_iso_days(start_of_week) + day - 1
          {year, month, day} = calendar.date_from_iso_days(iso_days)
          [{:year, year} | resolve([{:month, month}, {:day, day} | rest], calendar)]
        else
          [{:year, year} | resolve([{:week, week}, {:day, day} | rest], calendar)]
        end
      else
        {:error,
          "#{inspect abs(week)} is greater than #{inspect weeks_in_year} which " <>
           "is the number of weeks in #{inspect year} for the calendar #{inspect calendar}"
        }
      end
    end
  end

  def resolve([{:year, year}, {:day, day_of_year} | rest], calendar)
      when is_integer(year) and is_integer(day_of_year) do
    days_in_year = calendar.days_in_year(year)
    day_of_year = if day_of_year < 0, do: days_in_year + day_of_year + 1, else: day_of_year
    day_of_year = min(day_of_year, days_in_year)

    if day_of_year in 1..days_in_year do
      %{year: year, month: month, day: day} = Cldr.Calendar.date_from_day_of_year(year, day_of_year, calendar)
      resolve([{:year, year}, {:month, month}, {:day, day} | rest], calendar)
    else
      {:error,
        "#{inspect abs(day_of_year)} is outside the #{inspect days_in_year} days of the year #{inspect year} " <>
         "for the calendar #{inspect calendar}"
      }
    end
  end

  def resolve([{:year, year}, {:day, %Range{} = days_of_year}, {:day, day} | rest], calendar)
      when is_integer(year) and is_integer(day) do
    %{first: first, last: last} = days_of_year
    days_in_year = calendar.days_in_year(year)
    last = min(last, days_in_year)
    day = if day < 0, do: last + day + 1, else: first + day - 1

    if first in 1..days_in_year and day <= last do
      %{year: year, month: month, day: day} = Cldr.Calendar.date_from_day_of_year(year, day, calendar)
      resolve([{:year, year}, {:month, month}, {:day, day} | rest], calendar)
    else
      {:error,
        "#{inspect abs(day)} is outside the group #{inspect days_of_year} " <>
         "for the calendar #{inspect calendar}"
      }
    end
  end

  def resolve([{:year, year}, {:hour, %Range{} = hours_of_year}, {:hour, hour} | rest], calendar)
      when is_integer(year) and is_integer(hour) do
    %{first: first, last: last} = hours_of_year
    hours_in_year = calendar.days_in_year(year) * @hours_per_day
    last = min(last, hours_in_year)
    hour = if hour < 0, do: last + hour + 1, else: first + hour - 1

    if first in 1..hours_in_year and hour <= last do
      day = div(hour, @hours_per_day) + 1
      hour = rem(hour, @hours_per_day)
      %{year: year, month: month, day: day} = Cldr.Calendar.date_from_day_of_year(year, day, calendar)
      resolve([{:year, year}, {:month, month}, {:day, day}, {:hour, hour} | rest], calendar)
    else
      {:error,
        "#{inspect abs(hour)} is outside the group #{inspect hours_of_year} " <>
         "for the calendar #{inspect calendar}"
      }
    end
  end

  def resolve([{:year, year}, {:month, month}, {:day, day} | rest], calendar)
      when is_integer(year) and is_integer(month) and is_integer(day) do
    with [{:year, year}, {:month, month}] <- resolve([{:year, year}, {:month, month}], calendar) do
      days_in_month = calendar.days_in_month(year, month)
      day = if day < 0, do: days_in_month + day + 1, else: day

      if day in 1..days_in_month do
        case resolve(rest, calendar) do
          {:error, reason} -> {:error, reason}
          other -> [{:year, year}, {:month, month}, {:day, day} | other]
        end
      else
        {:error,
          "#{inspect day} is greater than #{inspect days_in_month} which " <>
           "is the number of days in #{inspect year}-#{inspect month} for the calendar #{inspect calendar}"
        }
      end
    end
  end

  def resolve([{:year, year}, {:month, month}, {:day, %Range{} = days} | rest], calendar)
      when is_integer(year) and is_integer(month) do

    max_days = calendar.days_in_month(year, month)
    [{:year, year}, {:month, month}, {:day, %{days | last: min(max_days, days.last)}} | resolve(rest, calendar)]
  end

  def resolve([{:year, year}, {:month, month} | rest], calendar)
      when is_integer(year) and is_integer(month) and month < 0 do
    months_in_year = calendar.months_in_year(year)

    if abs(month) in 1..months_in_year do
      resolve([{:year, year}, {:month, months_in_year + month + 1} | rest], calendar)
    else
      {:error,
        "#{inspect abs(month)} is greater than #{inspect months_in_year} which " <>
         "is the number of months in #{inspect year} for the calendar #{inspect calendar}"
      }
    end
  end

  def resolve([{:year, year}, {:month, requested_month} | rest], calendar)
      when is_integer(year) and is_integer(requested_month) do
    months_in_year = calendar.months_in_year(year)
    month = if requested_month < 0, do: months_in_year + requested_month + 1, else: requested_month

    if month in 1..months_in_year do
       [{:year, year} | resolve([{:month, month} | rest], calendar)]
    else
      {:error,
        "#{inspect abs(requested_month)} is greater than #{inspect months_in_year} which " <>
         "is the number of months in #{inspect year} for the calendar #{inspect calendar}"
      }
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
  def resolve([{_unit, fraction}, {_unit_2, _value} | _rest], _calendar) when is_float(fraction) do
    {:error, "A fractional unit can only be used for the highest resolution unit (smallest time unit)"}
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

  def year_and_month(years, month, calendar) do
    return =
      Enum.reduce_while years, {calendar.months_in_year(years.first), month}, fn year, {acc, to_go} ->
        months_in_year = calendar.months_in_year(year)

        if to_go <= months_in_year do
          {:halt, {:ok, year, to_go}}
        else
          {:cont, {acc + months_in_year, to_go - months_in_year}}
        end
      end

    case return do
      {:ok, year, month} -> {:ok, year, month}
      _other -> {:error, :invalid_date}
    end
  end

  def month_and_day(year, months, day, calendar) do
    return =
      Enum.reduce_while months, {calendar.days_in_month(year, months.first), day}, fn month, {acc, to_go} ->
        days_in_month = calendar.days_in_month(year, month)

        if to_go <= days_in_month do
          {:halt, {:ok, month, to_go}}
        else
          {:cont, {acc + days_in_month, to_go - days_in_month}}
        end
      end

    case return do
      {:ok, month, day} -> {:ok, month, day}
      _other -> {:error, :invalid_date}
    end
  end
end