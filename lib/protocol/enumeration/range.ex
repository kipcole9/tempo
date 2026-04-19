defimpl Enumerable, for: Tempo.Interval do
  @moduledoc false

  # An interval represents a span on the time line. Enumerating it
  # walks forward one resolution-unit at a time from the `:from`
  # endpoint. This is a different iteration semantics from
  # `Enumerable.Tempo`:
  #
  #   * `Enum.take(%Tempo{time: [year: 1985]}, 3)` yields
  #     `[1985-Jan, 1985-Feb, 1985-Mar]` — drilling INTO the year at
  #     the implicit next-finer unit (month).
  #
  #   * `Enum.take(%Tempo.Interval{from: ~o"1985Y", to: :undefined}, 3)`
  #     yields `[1985, 1986, 1987]` — stepping FORWARD at the
  #     endpoint's own resolution.
  #
  # Open-lower and fully-open intervals have no anchor to iterate
  # from, so `reduce/3` raises a clear `ArgumentError`.
  #
  # `count/1`, `member?/2`, and `slice/1` currently return
  # `{:error, __MODULE__}`. Computing them precisely requires a
  # Tempo-to-Tempo comparison and difference in wall-clock days that
  # is being developed alongside the set-operations milestone.

  @impl Enumerable
  def count(_interval) do
    {:error, __MODULE__}
  end

  @impl Enumerable
  def member?(_interval, _element) do
    {:error, __MODULE__}
  end

  @impl Enumerable
  def slice(_interval) do
    {:error, __MODULE__}
  end

  @impl Enumerable
  def reduce(%Tempo.Interval{from: :undefined, to: :undefined}, _acc, _fun) do
    raise ArgumentError,
          "Cannot enumerate a fully open interval `../..` — " <>
            "no anchor from which to start iteration."
  end

  def reduce(%Tempo.Interval{from: :undefined, to: %Tempo{}, duration: nil}, _acc, _fun) do
    raise ArgumentError,
          "Cannot enumerate an interval with an open lower bound `../to` — " <>
            "Enumerable iterates forward from the lower bound, which is not defined."
  end

  def reduce(
        %Tempo.Interval{from: :undefined, to: %Tempo{}, duration: %Tempo.Duration{}},
        _acc,
        _fun
      ) do
    # `P1M/1985-06` — duration + to. `from` could be computed as
    # `to - duration`, but Tempo.Duration subtraction isn't yet a
    # public API. Raise with a clear message rather than mislead.
    raise ArgumentError,
          "Cannot enumerate a duration-anchored interval of the shape `P…/to` yet. " <>
            "Tempo-duration subtraction is required to compute the lower bound and is " <>
            "not yet implemented."
  end

  def reduce(%Tempo.Interval{from: %Tempo{} = from, to: to}, acc, fun)
      when is_struct(to, Tempo) or to in [:undefined, nil] do
    # `to: nil` arises from `from + duration` intervals (`1985-01/P3M`)
    # where the upper bound is expressed as a Duration rather than a
    # concrete Tempo. We treat it as open-upper for iteration — the
    # sequence is bounded by the duration but computing that bound
    # requires Tempo-Duration arithmetic (not yet implemented).
    # Callers relying on termination should use `Enum.take/2` or a
    # `{:halt, acc}` accumulator. Once Tempo-Duration addition lands,
    # this clause can compute `to = from + duration` and delegate to
    # the closed-interval path.
    do_reduce(from, to, acc, fun)
  end

  def reduce(%Tempo.Interval{}, _acc, _fun) do
    raise ArgumentError,
          "Cannot enumerate this interval shape — only closed `from/to`, " <>
            "open-upper `from/..`, and `from/duration` intervals are iterable."
  end

  defp do_reduce(_current, _to, {:halt, acc}, _fun) do
    {:halted, acc}
  end

  defp do_reduce(current, to, {:suspend, acc}, fun) do
    {:suspended, acc, &do_reduce(current, to, &1, fun)}
  end

  defp do_reduce(current, to, {:cont, acc}, fun) do
    case past_end?(current, to) do
      true ->
        {:done, acc}

      false ->
        do_reduce(increment(current), to, fun.(current, acc), fun)
    end
  end

  # Open-upper: `to` is `:undefined` (explicit `../` in source) or
  # `nil` (from+duration shape with no computed upper bound yet).
  # Both mean "no bound to check — never terminate on the upper".

  defp past_end?(_current, :undefined), do: false
  defp past_end?(_current, nil), do: false

  # Half-open `[from, to)` convention: the upper bound is EXCLUSIVE.
  # `current >= to` terminates. See `CLAUDE.md`:
  #   "Every span is inclusive of the first boundary and exclusive of
  #    the last boundary — `[first, last)`."

  defp past_end?(%Tempo{time: current_time}, %Tempo{time: to_time}) do
    case compare_time(current_time, to_time) do
      :lt -> false
      _ -> true
    end
  end

  # Compare two keyword-list time representations as start-moments:
  # missing trailing units are implicitly filled with their unit
  # minimum (month/day minimum is 1, hour/minute/second/week minimum
  # is 0). This lets `1985` (start = 1985-01-01) compare correctly
  # against `1986-06` (start = 1986-06-01) and against `1986` itself.
  #
  # Both lists are assumed sorted descending-by-unit (the invariant
  # the tokenizer and `Unit.sort/2` maintain).

  defp compare_time([], []), do: :eq

  defp compare_time([{unit, v} | rest], []) do
    min = unit_minimum(unit)

    cond do
      v < min -> :lt
      v > min -> :gt
      true -> compare_time(rest, [])
    end
  end

  defp compare_time([], [{unit, v} | rest]) do
    min = unit_minimum(unit)

    cond do
      min < v -> :lt
      min > v -> :gt
      true -> compare_time([], rest)
    end
  end

  defp compare_time([{unit, v1} | t1], [{unit, v2} | t2]) do
    cond do
      v1 < v2 -> :lt
      v1 > v2 -> :gt
      true -> compare_time(t1, t2)
    end
  end

  # Mismatched units at the same position (e.g. week vs month) —
  # conservative bailout. A well-formed interval has endpoints
  # using the same unit vocabulary.
  defp compare_time(_, _), do: :eq

  # The start-of-unit minimum when a trailing unit is unspecified:
  # `:month` and `:day` count from 1, everything else from 0.
  defp unit_minimum(:month), do: 1
  defp unit_minimum(:day), do: 1
  defp unit_minimum(:week), do: 1
  defp unit_minimum(:day_of_year), do: 1
  defp unit_minimum(:day_of_week), do: 1
  defp unit_minimum(_), do: 0

  # Advance a Tempo by 1 unit at its declared resolution, carrying
  # over into coarser units as needed. Calendar-aware for months
  # (variable months-per-year) and days (variable days-per-month).

  defp increment(%Tempo{time: time, calendar: calendar} = tempo) do
    {unit, _span} = Tempo.resolution(tempo)
    %{tempo | time: increment_time(time, unit, calendar)}
  end

  # All updates use `Keyword.replace!/3` (preserves position) rather
  # than `Keyword.put/3` (removes + prepends). Keyword-list order is
  # the invariant maintained elsewhere in Tempo — compare_time/2
  # depends on it, as do inspect and to_iso8601.

  defp increment_time(time, :year, _calendar) do
    Keyword.update!(time, :year, &(&1 + 1))
  end

  defp increment_time(time, :month, calendar) do
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

  defp increment_time(time, :day, calendar) do
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

  defp increment_time(time, :hour, calendar) do
    hour = Keyword.fetch!(time, :hour)

    if hour < 23 do
      Keyword.replace!(time, :hour, hour + 1)
    else
      time
      |> Keyword.replace!(:hour, 0)
      |> increment_time(:day, calendar)
    end
  end

  defp increment_time(time, :minute, calendar) do
    minute = Keyword.fetch!(time, :minute)

    if minute < 59 do
      Keyword.replace!(time, :minute, minute + 1)
    else
      time
      |> Keyword.replace!(:minute, 0)
      |> increment_time(:hour, calendar)
    end
  end

  defp increment_time(time, :second, calendar) do
    second = Keyword.fetch!(time, :second)

    if second < 59 do
      Keyword.replace!(time, :second, second + 1)
    else
      time
      |> Keyword.replace!(:second, 0)
      |> increment_time(:minute, calendar)
    end
  end

  defp increment_time(time, :week, calendar) do
    year = Keyword.fetch!(time, :year)
    week = Keyword.fetch!(time, :week)
    {weeks_in_year, _} = calendar.weeks_in_year(year)

    if week < weeks_in_year do
      Keyword.replace!(time, :week, week + 1)
    else
      time
      |> Keyword.replace!(:year, year + 1)
      |> Keyword.replace!(:week, 1)
    end
  end

  defp increment_time(time, :day_of_year, calendar) do
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

  defp increment_time(time, :day_of_week, calendar) do
    day_of_week = Keyword.fetch!(time, :day_of_week)
    days_in_week = calendar.days_in_week()

    if day_of_week < days_in_week do
      Keyword.replace!(time, :day_of_week, day_of_week + 1)
    else
      time
      |> Keyword.replace!(:day_of_week, 1)
      |> increment_time(:week, calendar)
    end
  end

  defp increment_time(_time, unit, _calendar) do
    raise ArgumentError,
          "Cannot increment a Tempo at #{inspect(unit)} resolution — " <>
            "no increment rule is defined for this unit."
  end

end
