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

  # Reformat quarters as groups of months
  def expand_groups([{:month, month} | rest], calendar) when month in 33..36 do
    quarter = month - 32
    start = (quarter - 1) * 3 + 1
    finish = start + 2

    expand_groups([{:month, start..finish} | rest], calendar)
  end

  def expand_groups([{:group, [{:nth, nth}, {unit, value}]} | rest], calendar) do
    first = (nth - 1) * value + 1
    last = nth * value

    expand_groups([{unit, first..last} | rest], calendar)
  end

  def expand_groups([{:group, [{:all_of, set}, other]} | rest], calendar) do
    [{:group, [{:all_of, set}, other]} | expand_groups(rest, calendar)]
  end

  def expand_groups([{:group, [{:one_of, set}, other]} | rest], calendar) do
    [{:group, [{:one_of, set}, other]} | expand_groups(rest, calendar)]
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