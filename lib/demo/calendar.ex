defmodule Tempo.Demo.Calendar do
  def calendar(year, calendar \\ Cldr.Calendar.Gregorian) do
    Enum.map Tempo.new([year: year], calendar), fn month ->
      Enum.map month, &(&1)
    end
  end
end
