defmodule Tempo.Rounding do
  @moduledoc false

  def round(%Tempo{time: time, calendar: calendar} = tempo, time_unit) do
    {resolution, _} = Tempo.resolution(tempo)
    round(time, calendar, resolution, time_unit)
  end

  # Round to year

  defp round(time, calendar, :day, :year) do
    time
    |> round(calendar, :day, :month)
    |> round(calendar, :month, :year)
  end

  defp round([year: year, month: month], calendar, :month, :year) do
    if month <= div(calendar.months_in_year(year), 2) do
      [year: year]
    else
      {year, _month, _day} = calendar.plus(year, 1, 1, :years, 1)
      [year: year]
    end
  end

  defp round(time, _calendar, :year, :year) do
    time
  end

  # Round to month

  defp round([year: year, month: month, day: day], calendar, :day, :month) do
    if day <= div(calendar.days_in_month(year, month), 2) do
      [year: year, month: month]
    else
      {year, month, _day} = calendar.plus(year, month, 1, :months, 1)
      [year: year, month: month]
    end
  end

  defp round(time, _calendar, :month, :month) do
    time
  end

  # Round to week


  # Round to day

  defp round(time, _calendar, :day, :day) do
    time
  end

  # All others are error

  defp round(time, _calendar, resolution, time_unit) do
    {:error, rounding_error(time, resolution, time_unit)}
  end

  defp rounding_error(time, resolution, time_unit) do
    {Tempo.RoundingError, "Time #{inspect time} resolution #{inspect resolution} cannot be rounded to #{inspect time_unit}"}
  end

end