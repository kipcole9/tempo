defmodule Tempo.Mask do
  @moduledoc false
  @dialyzer {:nowarn_function, matches_mask?: 2}

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
    [1..-1//1]
    |> adjusted_range(unit, calendar, backtrack(previous, calendar))
    |> List.wrap()
  end

  def fill_unspecified(unit, [:negative | rest_mask], calendar, previous)
      when unit in [:year, :month, :day] do
    # Negative-year mask (e.g. `-1XXX` → `[:negative, 1, :X, :X, :X]`).
    # Generate negative candidates whose absolute-value digits match
    # the mask pattern.
    [target_range] = fill_unspecified(unit, :any, calendar, previous)
    digit_count = length(rest_mask)
    # Bound the negative range to numbers with `digit_count` digits.
    min = -(integer_pow10(digit_count) - 1)
    max = -integer_pow10(digit_count - 1)

    Enum.reduce(target_range, [], fn candidate, acc ->
      neg = -candidate

      if neg in max..min//-1 and matches_mask?(abs(neg), rest_mask) do
        [neg | acc]
      else
        acc
      end
    end)
  end

  def fill_unspecified(unit, mask, calendar, previous) when unit in [:year, :month, :day] do
    [target_range] = fill_unspecified(unit, :any, calendar, previous)

    Enum.reduce(target_range, [], fn candidate, acc ->
      if matches_mask?(candidate, mask), do: [candidate | acc], else: acc
    end)
  end

  def matches_mask?(candidate, [:negative | rest_mask]) when candidate < 0 do
    matches_mask?(abs(candidate), rest_mask)
  end

  def matches_mask?(_candidate, [:negative | _rest_mask]), do: false

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
    else
      false
    end
  end

  defp integer_pow10(0), do: 1
  defp integer_pow10(n) when n > 0, do: 10 * integer_pow10(n - 1)

  def matches?(_digit, _mask) do
    true
  end
end
