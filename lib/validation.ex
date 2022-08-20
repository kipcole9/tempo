defmodule Tempo.Validation do
  @hours_per_day 24
  # @minutes_per_hour 60
  # @seconds_per_minute 60

  def validate(tempo, calendar \\ Cldr.Calendar.Gregorian)

  def validate({:ok, %Tempo{time: units}}, calendar) do
    case resolve(units, calendar) do
      {:error, reason} -> {:error, reason}
      other -> {:ok, %Tempo{time: other}}
    end
  end

  def validate({:ok, %Tempo.Interval{} = tempo}, calendar) do
    from = resolve(tempo.from, calendar)
    to = resolve(tempo.to, calendar)
    duration = resolve(tempo.duration, calendar)

    {:ok, %{tempo | from: from, to: to, duration: duration}}
  end

  def validate({:error, reason}, _calendar) do
    {:error, reason}
  end

  # When a group of years succeeds a century or decade
  # Here we merge into a set
  def resolve([{unit, %Range{} = range1}, {unit, %Range{} = range2} | rest], calendar) do
    first = range1.first + range2.first - 1

    if first <= range1.last do
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

    if abs(month) <= months_in_group do
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

    if abs(day) <= days_in_group do
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

  def resolve([{:year, year}, {:day, %Range{} = days_of_year}, {:day, day} | rest], calendar)
      when is_integer(year) and is_integer(day) do
    %{first: first, last: last} = days_of_year
    days_in_year = calendar.days_in_year(year)
    last = min(last, days_in_year)
    day = if day < 0, do: last + day + 1, else: first + day - 1

    if first <= days_in_year and day <= last do
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

    if first <= hours_in_year and hour <= last do
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
      when is_integer(year) and is_integer(month) and month > 0 and is_integer(day) and day < 0 do
    days_in_month = calendar.days_in_month(year, month)
    day = days_in_month + day + 1

    if day <= days_in_month do
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

  def resolve([{:year, year}, {:month, month}, {:day, %Range{} = days} | rest], calendar)
      when is_integer(year) and is_integer(month) do

    max_days = calendar.days_in_month(year, month)
    [{:year, year}, {:month, month}, {:day, %{days | last: min(max_days, days.last)}} | resolve(rest, calendar)]
  end

  def resolve([{:year, year}, {:month, month} | rest], calendar)
      when is_integer(year) and is_integer(month) and month < 0 do
    months_in_year = calendar.months_in_year(year)

    if abs(month) <= months_in_year do
      resolve([{:year, year}, {:month, months_in_year + month + 1} | rest], calendar)
    else
      {:error,
        "#{inspect abs(month)} is greater than #{inspect months_in_year} which " <>
         "is the number of months in #{inspect year} for the calendar #{inspect calendar}"
      }
    end
  end

  def resolve(other, _calendar) do
    other
  end

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