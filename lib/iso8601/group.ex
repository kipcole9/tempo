defmodule Tempo.Iso8601.Group do
  @quarters_in_year 4
  @quadrimesters_in_year 3
  @semestrals_in_year 2

  def expand_groups(tempo, calendar \\ Cldr.Calendar.Gregorian)

  def expand_groups(%Tempo{time: time} = tempo, calendar) do
    case expand_groups(time, calendar) do
      {:error, reason} -> {:error, reason}
      %Tempo.Interval{} = interval -> {:ok, interval}
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

  def expand_groups(%Tempo.Set{set: set} = tempo, calendar) do
    set = Enum.map(set, &expand_groups(&1, calendar))
    {:ok, %{tempo | set: set}}
  end

  def expand_groups(nil, _calendar) do
    {:ok, nil}
  end

  def expand_groups(:undefined, _calendar) do
    {:ok, :undefined}
  end

  # Seasons:  These are meteorological seasons, not
  # astronomical
  # TODO implement astronomical seasons as an option

  # Northern Spring March-May
  # Southern Autumn - March-May
  def expand_groups([{:year, year}, {:month, month} | rest], calendar) when month in [25, 31] do
    {:ok, interval} =
      [
        interval: [
          datetime: [{:year, year}, {:month, 3}] ++ rest,
          datetime: [{:year, year}, {:month, 5}] ++ rest
        ]
      ]
      |> Tempo.Iso8601.Parser.parse()
      |> Tempo.Iso8601.Group.expand_groups(calendar)

    interval
  end

  # Northern Summer June-August
  # Southern Winter - June-August
  def expand_groups([{:year, year}, {:month, month} | rest], calendar) when month in [26, 32] do
    {:ok, interval} =
      [
        interval: [
          datetime: [{:year, year}, {:month, 6}] ++ rest,
          datetime: [{:year, year}, {:month, 8}] ++ rest
        ]
      ]
      |> Tempo.Iso8601.Parser.parse()
      |> Tempo.Iso8601.Group.expand_groups(calendar)

    interval
  end

  # Northern Autumn September-November
  # Southern Spring - September-November
  def expand_groups([{:year, year}, {:month, month} | rest], calendar) when month in [27, 29] do
    {:ok, interval} =
      [
        interval: [
          datetime: [{:year, year}, {:month, 9}] ++ rest,
          datetime: [{:year, year}, {:month, 11}] ++ rest
        ]
      ]
      |> Tempo.Iso8601.Parser.parse()
      |> Tempo.Iso8601.Group.expand_groups(calendar)

    interval
  end

  # Northern Winter Jan-Feb and December (of the previous year)
  # Southern Summer - December, January-February (of the next year)
  def expand_groups([{:year, year}, {:month, month} | rest], calendar) when month in [28, 30] do
    {:ok, interval} =
      [
        interval: [
          datetime: [{:year, year - 1}, {:month, 12}] ++ rest,
          datetime: [{:year, year}, {:month, 2}] ++ rest
        ]
      ]
      |> Tempo.Iso8601.Parser.parse()
      |> Tempo.Iso8601.Group.expand_groups(calendar)

    interval
  end

  # Reformat quarters as groups of months
  def expand_groups([{:year, year}, {:month, month} | rest], calendar)
      when is_integer(year) and month in 33..36 do
    months_in_year = calendar.months_in_year(year)
    months_in_quarter = div(months_in_year, @quarters_in_year)

    quarter = month - 32
    start = (quarter - 1) * months_in_quarter + 1

    finish =
      if quarter == @quarters_in_year, do: months_in_year, else: start + months_in_quarter - 1

    expand_groups([{:year, year}, {:month, {:group, start..finish}} | rest], calendar)
  end

  # Reformat quadrimester (third of a year) as groups of months
  def expand_groups([{:year, year}, {:month, month} | rest], calendar)
      when is_integer(year) and month in 37..39 do
    months_in_year = calendar.months_in_year(year)
    months_in_quadrimester = div(months_in_year, @quadrimesters_in_year)

    quadrimester = month - 36
    start = (quadrimester - 1) * months_in_quadrimester + 1

    finish =
      if quadrimester == @quadrimesters_in_year,
        do: months_in_year,
        else: start + months_in_quadrimester - 1

    expand_groups([{:year, year}, {:month, {:group, start..finish}} | rest], calendar)
  end

  # Reformat semestrals (half a year) as groups of months
  def expand_groups([{:year, year}, {:month, month} | rest], calendar)
      when is_integer(year) and month in 40..41 do
    months_in_year = calendar.months_in_year(year)
    months_in_semestral = div(months_in_year, @semestrals_in_year)

    semestral = month - 39
    start = (semestral - 1) * months_in_semestral + 1

    finish =
      if semestral == @semestrals_in_year,
        do: months_in_year,
        else: start + months_in_semestral - 1

    expand_groups([{:year, year}, {:month, {:group, start..finish}} | rest], calendar)
  end

  def expand_groups([{:group, [{:nth, nth}, {unit, value}]} | rest], calendar) do
    first = (nth - 1) * value + 1
    last = nth * value

    expand_groups([{unit, {:group, first..last}} | rest], calendar)
  end

  def expand_groups([{:group, [{:all_of, set}, {unit, value}]} | rest], calendar) do
    [{unit, {:group, {:all, set}}, value} | expand_groups(rest, calendar)]
  end

  def expand_groups([{:group, [{:one_of, set}, {unit, value}]} | rest], calendar) do
    [{unit, {:group, {:one, set}}, value} | expand_groups(rest, calendar)]
  end

  def expand_groups([{:group, group} | _rest], _calendar) do
    {:error, "Complex groupings not yet supported. Found #{inspect(group)}"}
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
