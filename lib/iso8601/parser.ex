defmodule Tempo.Iso8601.Parser do
  @moduledoc false

  alias Tempo.Iso8601.Unit

  def parse(tokens, calendar) do
    tokens
    |> parse()
    |> put_calendar(calendar)
    |> wrap(:ok)
  rescue
    e in Tempo.ParseError ->
      {:error, e.message}
  end

  def parse([{type, tokens}]) when type in [:date, :time_of_day, :datetime] do
    with parsed <- parse_date(tokens) do
      Tempo.new(parsed)
    end
  end

  def parse(interval: tokens) do
    with parsed <- parse_date(tokens) do
      Tempo.Interval.new(parsed)
    end
  end

  def parse(duration: tokens) do
    with parsed <- parse_date(tokens) do
      parsed
      |> adjust_for_direction()
      |> Tempo.Duration.new()
    end
  end

  def parse(all_of: tokens) do
    tokens
    |> parse_set
    |> Tempo.Set.new(:all)
  end

  def parse(one_of: tokens) do
    tokens
    |> parse_set
    |> Tempo.Set.new(:one)
  end

  def parse_set(set) do
    Enum.map(set, fn
      {:range, [{_, from}, {_, to}]} ->
        from = parse_date(from)
        to = parse_date(to)
        validate_range(from, to)

      {:range, [from, :undefined]} ->
        {:range, [parse_date(from), :undefined]}

      {:range, [:undefined, to]} ->
        {:range, [:undefined, parse_date(to)]}

      {unit, %Range{first: first, last: last}} ->
        {:range, [[{unit, first}], [{unit, last}]]}

      tempo ->
        tempo
        |> elem(1)
        |> parse_date()
    end)
  end

  # Date and time parsing

  def parse_date([{:date, date} | rest]) do
    [{:date, parse_date(date)} | parse_date(rest)]
  end

  def parse_date([{:repeat_rule, date} | rest]) do
    [{:repeat_rule, parse_date(date)} | parse_date(rest)]
  end

  def parse_date([{:century, century} | rest]) do
    parse_date([{:year, {:group, (century * 100)..((century + 1) * 100 - 1)}} | rest])
  end

  def parse_date([{:decade, century} | rest]) do
    parse_date([{:year, {:group, (century * 10)..((century + 1) * 10 - 1)}} | rest])
  end

  # TODO what if prior unit is a selection
  def parse_date([{:group, group_1}, {:group, group_2} | rest]) do
    {_min_1, max_1} = group_min_max(group_1)
    {min_2, _max} = group_min_max(group_1)

    if Unit.compare(max_1, min_2) == :lt do
      raise Tempo.ParseError,
            "Group max of #{inspect(group_1)} is less than the group min of #{inspect(group_2)}"
    else
      [{:group, parse_date(group_1)} | parse_date([{:group, group_2} | rest])]
    end
  end

  def parse_date([{unit_1, value_1}, {:group, group} | rest]) do
    {min, _max} = group_min_max(group)

    if Unit.compare(unit_1, min) == :lt do
      raise Tempo.ParseError, "#{inspect(unit_1)} is less than the group min of #{inspect(min)}"
    else
      [parse_date({unit_1, value_1}) | parse_date([{:group, group} | rest])]
    end
  end

  # TODO what if successor unit is a selection or a group
  def parse_date([{:group, group}, {unit_2, value_2} | rest]) do
    {_min, max} = group_min_max(group)

    if Unit.compare(max, unit_2) == :lt do
      raise Tempo.ParseError,
            "#{inspect(unit_2)} is greater than the group max of #{inspect(max)}"
    else
      [{:group, parse_date(group)} | parse_date([{unit_2, value_2} | rest])]
    end
  end

  def parse_date([{unit_1, value_1}, {:selection, selection} | rest]) do
    {min, _max} = selection_min_max(selection)

    if Unit.compare(unit_1, min) == :lt do
      raise Tempo.ParseError,
            "#{inspect(unit_1)} is less than the selection min of #{inspect(min)}"
    else
      [parse_date({unit_1, value_1}) | parse_date([{:selection, selection} | rest])]
    end
  end

  def parse_date([{:selection, selection}, {unit_2, value_2} | rest]) do
    {_min, max} = selection_min_max(selection)

    unless Unit.ordered?(selection) do
      raise Tempo.ParseError,
            "Selection time units must be in decreasing time scale order. Found #{inspect(selection)}."
    end

    if Unit.compare(max, unit_2) == :lt do
      raise Tempo.ParseError,
            "#{inspect(unit_2)} is greater than the selection max of #{inspect(max)}"
    else
      selection = parse_date(selection) |> reduce_list()
      [{:selection, selection} | parse_date([{unit_2, value_2} | rest])]
    end
  end

  def parse_date([{:selection, selection} | rest]) do
    unless Unit.ordered?(selection) do
      raise Tempo.ParseError,
            "Selection time units must be in decreasing time scale order. Found #{inspect(selection)}."
    end

    selection = parse_date(selection) |> reduce_list()
    [{:selection, selection} | parse_date(rest)]
  end

  def parse_date([{:interval, interval} | rest]) do
    interval = parse([{:interval, interval}])
    [{:interval, interval} | parse_date(rest)]
  end

  def parse_date([{:duration, duration} | rest]) do
    duration = adjust_for_direction(duration)
    [{:duration, duration} | parse_date(rest)]
  end

  def parse_date([{:group, group} | rest]) do
    [{:group, parse_date(group)} | parse_date(rest)]
  end

  def parse_date([{component, {:all_of, list}} | rest]) do
    [{component, reduce_list(list)} | parse_date(rest)]
  end

  def parse_date([{component, list} | rest]) when is_list(list) do
    [{component, reduce_list(list)} | parse_date(rest)]
  end

  def parse_date([{component, {:mask, list}} | rest]) when is_list(list) do
    [{component, {:mask, reduce_list(list)}} | parse_date(rest)]
  end

  def parse_date([h | t]) do
    [h | parse_date(t)]
  end

  def parse_date([]) do
    []
  end

  def parse_date({unit, value}) do
    [{unit, value}]
    |> parse_date()
    |> hd()
  end

  # Time

  def parse_time([h | t]) do
    [h | parse_time(t)]
  end

  def parse_time([]) do
    []
  end

  # Datetime

  def parse_datetime([h | t]) do
    [h | parse_datetime(t)]
  end

  def parse_datetime([]) do
    []
  end

  # Interval

  def parse_interval([{:date, date} | t]) do
    [{:date, parse_date(date)} | parse_interval(t)]
  end

  def parse_interval([h | t]) do
    [h | parse_interval(t)]
  end

  def parse_interval([]) do
    []
  end

  # Duration

  def parse_duration(datetime: tokens) do
    parse_duration(tokens)
  end

  def parse_duration(date: tokens) do
    parse_duration(tokens)
  end

  def parse_duration([h | t]) do
    [h | parse_duration(t)]
  end

  def parse_duration([]) do
    []
  end

  # Helpers

  def group_min_max(group) do
    group = Keyword.delete(group, :nth) |> Keyword.delete(:all_of) |> Keyword.delete(:one_of)
    sorted = Unit.sort(group)
    Tempo.unit_min_max(sorted)
  end

  def selection_min_max(selection) do
    Tempo.unit_min_max(selection)
  end

  # Keyword list
  def reduce_list([{key, _value} | _rest] = list) when is_atom(key) do
    list
  end

  def reduce_list([%module{} | _rest] = list) when module != Range do
    list
  end

  # The "unknown" marker
  def reduce_list([:X | rest]) do
    [:X | reduce_list(rest)]
  end

  def reduce_list(["X*"]) do
    "X*"
  end

  # The list has a set in it, we need to reduce
  # the set
  def reduce_list([first | rest]) when is_list(first) do
    [reduce_list(first) | reduce_list(rest)]
  end

  # Number or range list
  def reduce_list(list) when is_list(list) do
    list
    |> Enum.sort_by(fn
      a when is_integer(a) -> a
      %Range{} = a -> a.first
    end)
    |> consolidate_ranges()
  end

  def reduce_list(other) do
    other
  end

  # Consolidate overlapping, adjacent and enclosing
  # ranges. Remove integers that fit within or are
  # adjacent to ranges. Collapse sequences of integers
  # into a range.

  def consolidate_ranges([]) do
    []
  end

  def consolidate_ranges([h]) do
    [h]
  end

  def consolidate_ranges([a, a | rest]) do
    consolidate_ranges([a | rest])
  end

  def consolidate_ranges([a, b | rest]) when a + 1 == b do
    consolidate_ranges([a..b | rest])
  end

  def consolidate_ranges([a, b | rest]) when is_integer(a) and is_integer(b) do
    [a | consolidate_ranges([b | rest])]
  end

  def consolidate_ranges([a, %Range{first: first, last: last} = range | rest])
      when is_integer(a) do
    cond do
      a >= first && a <= last ->
        consolidate_ranges([range | rest])

      a + 1 == first ->
        consolidate_ranges([%{range | first: a} | rest])

      true ->
        [a | consolidate_ranges([range | rest])]
    end
  end

  def consolidate_ranges([%Range{last: last} = range, b | rest]) when is_integer(b) do
    cond do
      b <= last ->
        consolidate_ranges([range | rest])

      last + 1 == b ->
        consolidate_ranges([%{range | last: b} | rest])

      true ->
        [range | consolidate_ranges([b | rest])]
    end
  end

  def consolidate_ranges([%Range{step: step} = r1, %Range{step: step} = r2 | rest]) do
    cond do
      # Overlapping
      r1.last >= r2.first && r1.last <= r2.last ->
        consolidate_ranges([%{r1 | last: r2.last} | rest])

      # Adjacent
      r1.last + 1 == r2.first ->
        consolidate_ranges([%{r1 | last: r2.last} | rest])

      # Enclosing
      r1.last >= r2.last ->
        [r1 | consolidate_ranges(rest)]

      true ->
        [r1 | consolidate_ranges([r2 | rest])]
    end
  end

  def consolidate_ranges([struct | rest]) when is_struct(struct) do
    [struct | consolidate_ranges(rest)]
  end

  # Ranges must have the same keys. Assumption
  # is that ranges can be in either direction
  # (ie increasing or decreasing)

  defp validate_range(from, to) do
    if Keyword.keys(from) == Keyword.keys(to) do
      {:range, [from, to]}
    else
      raise Tempo.ParseError,
            "Time ranges must have the same time units on both sides. Found #{inspect(from)}..#{inspect(to)}"
    end
  end

  # If the duratation direction is negative, negate all the
  # units.

  def adjust_for_direction([{:direction, :negative} | rest]) do
    Enum.map(rest, fn {k, v} -> {k, -v} end)
  end

  def adjust_for_direction(other) do
    other
  end

  defp put_calendar(%Tempo{} = tempo, calendar) do
    %{tempo | calendar: calendar}
  end

  defp put_calendar(%Tempo.Interval{from: from, to: to} = interval, calendar) do
    to = put_calendar(to, calendar)
    from = put_calendar(from, calendar)
    %{interval | from: from, to: to}
  end

  defp put_calendar(other, _calendar) do
    other
  end

  def wrap(term, atom) do
    {atom, term}
  end
end
