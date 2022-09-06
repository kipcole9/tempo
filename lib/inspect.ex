defmodule Tempo.Inspect do
  import Kernel, except: [inspect: 1]

  def inspect(%Tempo{time: time, shift: shift, calendar: Cldr.Calendar.Gregorian}) do
    ["~o\"", inspect(time), inspect_shift(shift), ?"]
    |> :erlang.iolist_to_binary()
  end

  def inspect(%Tempo{time: time, shift: shift, calendar: Cldr.Calendar.ISOWeek}) do
    ["~o\"", inspect(time), inspect_shift(shift), ?", ?W]
    |> :erlang.iolist_to_binary()
  end

  def inspect(%Tempo{time: time, shift: shift, calendar: calendar}) do
    ["Tempo.from_iso8601!(\"", inspect(time), inspect_shift(shift), "\", ", Kernel.inspect(calendar), ?)]
    |> :erlang.iolist_to_binary()
  end

  def inspect(%Tempo.Set{type: type, set: set}) do
    elements = Enum.map_join(set, ",", &inspect/1)
    ["~o\"", open(type), elements, close(type), ?"]
    |> :erlang.iolist_to_binary()
  end

  def inspect(%Tempo.Interval{recurrence: 1, from: from, to: :undefined = to, duration: nil}) do
    ["~o\"", inspect(from.time), ?/, inspect_value(to), ?"]
    |> :erlang.iolist_to_binary()
  end

  def inspect(%Tempo.Interval{recurrence: 1, from: :undefined = from, to: to, duration: nil}) do
    ["~o\"", inspect_value(from), ?/, inspect(to.time), ?"]
    |> :erlang.iolist_to_binary()
  end

  def inspect(%Tempo.Interval{recurrence: 1, from: from, to: to, duration: nil}) do
    ["~o\"", inspect(from.time), ?/, inspect(to.time), ?"]
    |> :erlang.iolist_to_binary()
  end

  def inspect(%Tempo.Interval{recurrence: :infinity, from: from, to: :undefined = to, duration: nil}) do
    ["~o\"R/", inspect(from.time), ?/, inspect_value(to), ?"]
    |> :erlang.iolist_to_binary()
  end

  def inspect(%Tempo.Interval{recurrence: :infinity, from: :undefined = from, to: to, duration: nil}) do
    ["~o\"R/", inspect_value(from), ?/, inspect(to.time), ?"]
    |> :erlang.iolist_to_binary()
  end

  def inspect(%Tempo.Interval{recurrence: :infinity, from: from, to: to, duration: nil}) do
    ["~o\"R/", inspect(from.time), ?/, inspect(to.time), ?"]
    |> :erlang.iolist_to_binary()
  end

  def inspect(%Tempo.Duration{time: time}) do
    ["~o\"P", inspect(time), ?"]
    |> :erlang.iolist_to_binary()
  end

  def inspect([{unit, {:group, range}} | t]) do
    [inspect_value({unit, {:group, range}}) | inspect(t)]
  end

  def inspect([{unit, _value1} = first, {time, _value2} = second | t])
      when unit in [:year, :month, :day, :week, :day_of_week] and time in [:hour, :minute, :second] do
    [inspect_value(first), ?T, inspect_value(second) | inspect(t)]
  end

  def inspect([h | t]) do
    [inspect_value(h) | inspect(t)]
  end

  def inspect([]) do
    []
  end

  def inspect_shift(_shift) do
    ""
  end

  def inspect_value(list) when is_list(list) do
    [?{, Enum.map_join(list, ",", &inspect_value/1), ?}]
  end

  def inspect_value(%Range{first: first, last: last}) do
    [inspect_value(first), "..", inspect_value(last)]
  end

  def inspect_value(number) when is_number(number) do
    Kernel.inspect(number)
  end

  def inspect_value({number, [margin_of_error: margin]}) do
    Kernel.inspect(number) <> "±" <> Kernel.inspect(margin)
  end

  def inspect_value({value, continuation}) when is_function(continuation) do
    Kernel.inspect(value)
  end

  def inspect_value(:undefined) do
    ".."
  end

  def inspect_value({unit, {:group, %Range{first: first, last: last}}}) do
    group_size = last - first + 1
    nth =  div(last, group_size)

    [_, unit_key] = inspect_value({unit, 1})
    [inspect_value(nth), ?G, inspect_value(group_size), unit_key, ?U]
  end

  def inspect_value({unit, {:group, {set_type, set_values}}, value}) do
    [_, unit_key] = inspect_value({unit, value})
    elements = Enum.map_join(set_values, ",", &inspect_value/1)
    [open(set_type), elements, close(set_type), ?G, inspect_value(value), unit_key, ?U]
  end

  def inspect_value({:year, year}), do: [inspect_value(year), "Y"]
  def inspect_value({:month, month}), do: [inspect_value(month), "M"]
  def inspect_value({:day, day}), do: [inspect_value(day), "D"]
  def inspect_value({:hour, hour}), do: [inspect_value(hour), "H"]
  def inspect_value({:minute, minute}), do: [inspect_value(minute), "M"]
  def inspect_value({:second, second}), do: [inspect_value(second), "S"]
  def inspect_value({:day_of_week, day}), do: [inspect_value(day), "K"]
  def inspect_value({:week, week}), do: [inspect_value(week), "W"]

  def insert_time_marker([{value1, unit}, {value2, time} | t])
      when unit in [:year, :month, :day, :week] and time in [:hour, :miniute, :second] do
    [{unit, value1}, ?T, {time, value2} | t]
  end

  def insert_time_marker([first | rest]) do
    [first, insert_time_marker(rest)]
  end

  def insert_time_marker([]) do
    []
  end

  def open(:all), do: ?{
  def open(:one), do: ?[
  def close(:all), do: ?}
  def close(:one), do: ?]
end