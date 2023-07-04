defmodule Tempo.Inspect do
  @moduledoc false

  import Kernel, except: [inspect: 1]

  @from_iso8601 "Tempo.from_iso8601!(\""
  @sigil_o "~o\""

  def inspect(%Tempo{calendar: Cldr.Calendar.Gregorian} = tempo) do
    [@sigil_o, inspect_value(tempo), ?"]
    |> :erlang.iolist_to_binary()
  end

  def inspect(%Tempo{calendar: Cldr.Calendar.ISOWeek} = tempo) do
    [@sigil_o, inspect_value(tempo), ?", ?W]
    |> :erlang.iolist_to_binary()
  end

  # For when the calendar isn't Calendar.ISO or Cldr.Calendar.Gregorian
  def inspect(%Tempo{calendar: calendar} = tempo) do
    [@from_iso8601, inspect_value(tempo), "\", ", Kernel.inspect(calendar), ?)]
    |> :erlang.iolist_to_binary()
  end

  def inspect(%Tempo.Interval{} = interval) do
    [@sigil_o, inspect_value(interval), ?"]
    |> :erlang.iolist_to_binary()
  end

  def inspect(%Tempo.Duration{} = duration) do
    [@sigil_o, inspect_value(duration), ?"]
    |> :erlang.iolist_to_binary()
  end

  def inspect(%Tempo.Set{} = set) do
    [@sigil_o, inspect_value(set), ?"]
    |> :erlang.iolist_to_binary()
  end

  # Inspect value for everything else

  defp inspect_value([{unit, _value1} = first, {time, _value2} = second | t])
       when unit in [:year, :month, :day, :week, :day_of_week] and
              time in [:hour, :minute, :second] do
    [inspect_value(first), inspect_value([second | t])]
  end

  # The next three clauses are to ensure we only put one "T"
  # in the output. Three because :hour, :minute, :second

  defp inspect_value([{unit, _value1} = first, second, third])
       when unit in [:hour, :minute, :second] do
    [?T, inspect_value(first), inspect_value(second), inspect_value(third)]
  end

  defp inspect_value([{unit, _value1} = first, second])
       when unit in [:hour, :minute, :second] do
    [?T, inspect_value(first) | inspect_value(second)]
  end

  defp inspect_value([{unit, _value1} = first])
       when unit in [:hour, :minute, :second] do
    [?T, inspect_value(first)]
  end

  defp inspect_value([{:selection, selection} | rest]) do
    selection =
      Enum.reduce(selection, [], fn
        {:interval, interval}, acc -> [[?L, inspect_value(interval), ?N] | acc]
        other, acc -> [inspect_value(other) | acc]
      end)
      |> Enum.reverse()

    [?L, selection, ?N | inspect_value(rest)]
  end

  defp inspect_value([h | t]) do
    [inspect_value(h) | inspect_value(t)]
  end

  defp inspect_value([]) do
    []
  end

  defp inspect_value(list) when is_list(list) do
    [?{, Enum.map_join(list, ",", &inspect_value/1), ?}]
  end

  defp inspect_value(%Range{first: first, last: last}) do
    [inspect_value(first), "..", inspect_value(last)]
  end

  defp inspect_value(number) when is_number(number) do
    Kernel.inspect(number)
  end

  defp inspect_value({number, [margin_of_error: margin]}) do
    Kernel.inspect(number) <> "±" <> Kernel.inspect(margin)
  end

  defp inspect_value({value, continuation}) when is_function(continuation) do
    Kernel.inspect(value)
  end

  defp inspect_value({unit, {:group, %Range{first: first, last: last}}}) do
    group_size = last - first + 1
    nth = div(last, group_size)

    [_, unit_key] = inspect_value({unit, 1})
    [inspect_value(nth), ?G, inspect_value(group_size), unit_key, ?U]
  end

  defp inspect_value({unit, {:group, {set_type, set_values}}, value}) do
    [_, unit_key] = inspect_value({unit, value})
    elements = Enum.map_join(set_values, ",", &inspect_value/1)
    [open(set_type), elements, close(set_type), ?G, inspect_value(value), unit_key, ?U]
  end

  defp inspect_value(%Tempo{time: time, shift: shift}) do
    [inspect_value(time), inspect_shift(shift)]
  end

  defp inspect_value(%Tempo.Set{set: set, type: type}) do
    elements = Enum.map_join(set, ",", &inspect_value/1)

    [open(type), elements, close(type)]
  end

  defp inspect_value(%Tempo.Interval{
         recurrence: 1,
         from: from,
         to: :undefined = to,
         duration: nil
       }) do
    [inspect_value(from.time), ?/, inspect_value(to)]
  end

  defp inspect_value(%Tempo.Interval{
         recurrence: 1,
         from: :undefined = from,
         to: to,
         duration: nil
       }) do
    [inspect_value(from), ?/, inspect_value(to.time)]
  end

  defp inspect_value(%Tempo.Interval{recurrence: 1, from: from, to: to, duration: nil}) do
    [inspect_value(from.time), ?/, inspect_value(to.time)]
  end

  defp inspect_value(%Tempo.Interval{recurrence: 1, from: from, to: nil, duration: duration}) do
    [inspect_value(from.time), ?/, inspect_value(duration)]
  end

  defp inspect_value(%Tempo.Interval{
         recurrence: :infinity,
         from: from,
         to: :undefined = to,
         duration: nil
       }) do
    ["R/", inspect_value(from.time), ?/, inspect_value(to)]
  end

  defp inspect_value(%Tempo.Interval{
         recurrence: :infinity,
         from: :undefined = from,
         to: to,
         duration: nil
       }) do
    ["R/", inspect_value(from), ?/, inspect_value(to.time)]
  end

  defp inspect_value(%Tempo.Interval{recurrence: :infinity, from: from, to: to, duration: nil}) do
    ["R/", inspect_value(from.time), ?/, inspect_value(to.time)]
  end

  defp inspect_value(%Tempo.Duration{time: time}) do
    [?P, inspect_value(time)]
  end

  defp inspect_value(%Tempo.Range{first: first, last: :undefined}) do
    [inspect_value(first), inspect_value(:undefined)]
    |> :erlang.iolist_to_binary()
  end

  defp inspect_value(%Tempo.Range{first: :undefined, last: last}) do
    [inspect_value(:undefined), inspect_value(last)]
    |> :erlang.iolist_to_binary()
  end

  defp inspect_value(%Tempo.Range{first: first, last: last}) do
    [inspect_value(first), "..", inspect_value(last)]
    |> :erlang.iolist_to_binary()
  end

  defp inspect_value({:year, year}), do: [inspect_value(year), ?Y]
  defp inspect_value({:month, month}), do: [inspect_value(month), ?M]
  defp inspect_value({:day, day}), do: [inspect_value(day), ?D]
  defp inspect_value({:hour, hour}), do: [inspect_value(hour), ?H]
  defp inspect_value({:minute, minute}), do: [inspect_value(minute), ?M]
  defp inspect_value({:second, second}), do: [inspect_value(second), ?S]
  defp inspect_value({:day_of_week, day}), do: [inspect_value(day), ?K]
  defp inspect_value({:week, week}), do: [inspect_value(week), ?W]
  defp inspect_value({:instance, instance}), do: [inspect_value(instance), ?I]
  defp inspect_value({:interval, interval}), do: inspect_value(interval)
  defp inspect_value({:duration, duration}), do: inspect_value(duration)
  defp inspect_value(:undefined), do: ".."
  defp inspect_shift(_shift), do: ""

  defp open(:all), do: ?{
  defp open(:one), do: ?[
  defp close(:all), do: ?}
  defp close(:one), do: ?]
end
