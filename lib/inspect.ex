defmodule Tempo.Inspect do
  import Kernel, except: [inspect: 1]

  def inspect(%Tempo{time: time, shift: shift, calendar: calendar}) do
    ["Tempo.from_iso8601(\"", inspect(time), inspect_shift(shift), "\", ", Kernel.inspect(calendar), ?)]
    |> :erlang.iolist_to_binary()
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
end