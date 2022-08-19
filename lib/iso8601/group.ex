defmodule Tempo.Iso8601.Group do
  def expand_groups(tempo, calendar \\ Cldr.Calendar.Gregorian)

  def expand_groups({:ok, tempo}, calendar) do
    expand_groups(tempo, calendar)
  end

  def expand_groups(%Tempo{time: time} = tempo, calendar) do
    case expand_groups(time, calendar) do
      {:error, reason} -> {:error, reason}
      time -> {:ok, %{tempo | time: time}}
    end
  end

  def expand_groups(%Tempo.Duration{time: time} = tempo, calendar) do
    case expand_groups(time, calendar) do
      {:error, reason} -> {:error, reason}
      time -> {:ok, %{tempo | time: time}}
    end
  end

  def expand_groups(%Tempo.Interval{} = tempo, calendar) do
    {:ok, from} = expand_groups(tempo.from, calendar)
    {:ok, to} = expand_groups(tempo.to, calendar)
    {:ok, duration} = expand_groups(tempo.duration, calendar)

    {:ok, %{tempo | from: from, to: to, duration: duration}}
  end

  def expand_groups(nil, _calendar) do
    {:ok, nil}
  end

  # For simple groups of a single unit
  def expand_groups([{:year, year}, {:group, [{:nth, nth}, {:month, value}]} | rest], calendar)
      when is_integer(year) do
    months_in_year = calendar.months_in_year(year)
    first = (nth - 1) * value + 1
    last = nth * value

    if first <= months_in_year do
      last = min(last, months_in_year)
      expand_groups([{:year, year}, {:month, first..last} | rest])
    else
      {:error,
        "Group would resolve to the range of months #{inspect first..last} which " <>
        "is outside the number of months for the year #{inspect year} in the " <>
        "calendar #{inspect calendar}."
      }
    end
  end

  def expand_groups([{:year, year}, {:month, month}, {:group, [{:nth, nth}, {:day, value}]} | rest], calendar)
      when is_integer(year) and is_integer(month) do
    days_in_month = calendar.days_in_month(year, month)
    first = (nth - 1) * value + 1
    last = nth * value

    if first <= days_in_month do
      last = min(last, days_in_month)
      expand_groups([{:year, year}, {:month, month}, {:day, first..last} | rest])
    else
      {:error,
        "Group would resolve to the range of days #{inspect first..last} which " <>
        "is outside the number of days for the month #{inspect year}-#{inspect month} in the " <>
        "calendar #{inspect calendar}."
      }
    end
  end

  def expand_groups([{:year, year}, {:group, [{:nth, nth}, {:day, value}]} | rest], calendar)
      when is_integer(year) do
    days_in_year = calendar.days_in_year(year)
    first = (nth - 1) * value + 1
    last = nth * value

    if first <= days_in_year do
      last = min(last, days_in_year)
      expand_groups([{:year, year}, {:day, first..last} | rest])
    else
      {:error,
        "Group would resolve to the range of days #{inspect first..last} which " <>
        "is outside the number of days for the year #{inspect year} in the " <>
        "calendar #{inspect calendar}."
      }
    end
  end

  def expand_groups([{:year, year}, {:month, month}, {:group, [{:nth, nth}, {:day, value}]} | rest], _calendar)
      when is_integer(year) do
    first = (nth - 1) * value + 1
    last = nth * value

    expand_groups([{:year, year}, {:month, month}, {:day, first..last} | rest])
  end

  def expand_groups([{:group, [{:nth, nth}, {unit, value}]} | rest], calendar) do
    first = (nth - 1) * value + 1
    last = nth * value

    expand_groups([{unit, first..last} | rest], calendar)
  end

  def expand_groups([{:group, group} | _rest], _calendar) do
    {:error, "Complex groupings not yet supported. Found #{inspect group}"}
  end

  def expand_groups([first | rest], calendar) do
    case expand_groups(rest, calendar) do
      {:error, reason} -> {:error, reason}
      time -> [first | time]
    end
  end

  def expand_groups(other, _calendar) do
    other
  end

end