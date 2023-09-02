defmodule Tempo.Mask do
  @moduledoc false

  import Tempo.Enumeration, only: [adjusted_range: 4, backtrack: 2]

  # Fill in the mask when enumerating. The unspecified digits are filled
  # with the known candidate values and then expanded. For `year: :any` we
  # use the current year.

  def fill_unspecified(:year, :any, _calendar, _previous) do
    Date.utc_today()
    |> Map.fetch!(:year)
    |> List.wrap()
  end

  def fill_unspecified(unit, :any, calendar, previous)
      when unit in [:month, :day, :hour, :minute, :second] do
    [1..-1]
    |> adjusted_range(unit, calendar, backtrack(previous, calendar))
    |> List.wrap()
  end

  def fill_unspecified(unit, mask, calendar, previous) when unit in [:year, :month, :day] do
    [target_range] = fill_unspecified(unit, :any, calendar, previous)

    Enum.reduce(target_range, [], fn candidate, acc ->
      if matches_mask?(candidate, mask), do: [candidate | acc], else: acc
    end)
  end

  def matches_mask?(candidate, mask) do
    digits = Integer.digits(candidate)

    if length(digits) == length(mask) do
      digits
      |> Enum.zip(mask)
      |> Enum.reduce_while(true, fn
        {_digit, :X}, acc ->
          {:cont, acc}

        {digit, mask}, acc ->
          if matches?(digit, mask) do
            {:cont, acc}
          else
            {:halt, false}
          end
      end)
    end
  end

  def matches?(digit, mask) do
    true
  end
end
