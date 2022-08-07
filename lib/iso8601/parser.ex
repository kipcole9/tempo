defmodule Tempo.Iso8601.Parser do
  def parse({:error, _reason} = return) do
    return
  end

  def parse({:ok, tokens}) do
    {:ok, parse(tokens)}
  rescue e in Tempo.ParseError ->
    {:error, e.message}
  end

  def parse([date: tokens]) do
    {:ok, parse_date(tokens)}
  end

  def parse([time: tokens]) do
    parse_time(tokens)
  end

  def parse([datetime: tokens]) do
    parse_datetime(tokens)
  end

  def parse([interval: tokens]) do
    parse_interval(tokens)
  end

  def parse([duration: tokens]) do
    parse_duration(tokens)
  end

  # Date

  def parse_date([{component, {:all_of, list}} | rest]) do
    parse_date([{component, list} | rest])
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

  def parse_interval([h | t]) do
    [h | parse_interval(t)]
  end

  def parse_interval([]) do
    []
  end

  # Duration

  def parse_duration([datetime: tokens]) do
    parse_duration(tokens)
  end

  def parse_duration([date: tokens]) do
    parse_duration(tokens)
  end

  def parse_duration([h | t]) do
    [h | parse_duration(t)]
  end

  def parse_duration([]) do
    []
  end

  # Helpers

  # Keyword list
  def reduce_list([{key, _value} | _rest] = list) when is_atom(key) do
    list
  end

  # The list has a set in it, we need to reduce
  # the set
  def reduce_list([first | rest]) when is_list(first) do
    [reduce_list(first) | reduce_list(rest)]
  end

  # The "unknown" marker
  def reduce_list([:X | rest]) do
    [:X | reduce_list(rest)]
  end

  # Number or range list
  def reduce_list(list) when is_list(list) do
    list
    |> IO.inspect
    |> Enum.sort_by(fn
      a when is_integer(a) -> a
      %Range{} = a -> a.first
    end)
    |> consolidate_ranges()
  end

  def reduce_list([]) do
    []
  end

  # Consolidate overlapping, adjacent and enclosing
  # ranges. Remove integers that fit within or are
  # adjancent to ranges. Collapse sequences of integers
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

  def consolidate_ranges([a, %Range{first: first, last: last} = range | rest]) when is_integer(a) do
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
end