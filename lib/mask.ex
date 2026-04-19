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
    # The list wrapping is load-bearing: `adjusted_range/4` routes
    # through `Validation.resolve/2`, whose clause matching the
    # `year+month` or `year+month+day` shapes guards on
    # `is_list(value) or is_integer(value)`. Passing the range
    # wrapped in a list lets that clause conform `1..-1//1` to
    # the concrete `1..months_in_year`/`1..days_in_month` range.
    [1..-1//1]
    |> adjusted_range(unit, calendar, backtrack(previous, calendar))
    |> List.wrap()
  end

  # Year masks are bounded entirely by their digit pattern — there
  # is no calendar context that narrows them further. Compute the
  # `min..max` range directly from the mask (each `:X` spans
  # `0..9` at its position) and filter to candidates that match
  # the concrete digits.
  def fill_unspecified(:year, [:negative | rest_mask], _calendar, _previous) do
    {min, max} = mask_bounds(rest_mask)

    Enum.reduce(max..min//-1, [], fn candidate, acc ->
      if matches_mask?(candidate, rest_mask), do: [-candidate | acc], else: acc
    end)
  end

  def fill_unspecified(:year, mask, _calendar, _previous) when is_list(mask) do
    {min, max} = mask_bounds(mask)

    Enum.reduce(min..max, [], fn candidate, acc ->
      if matches_mask?(candidate, mask), do: [candidate | acc], else: acc
    end)
    |> Enum.reverse()
  end

  # Month and day masks still need calendar context (month-of-year
  # bounds, days-in-month), so they route through `:any` which
  # returns a calendar-adjusted range.
  def fill_unspecified(unit, [:negative | rest_mask], calendar, previous)
      when unit in [:month, :day] do
    [target_range] = fill_unspecified(unit, :any, calendar, previous)
    digit_count = length(rest_mask)
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

  def fill_unspecified(unit, mask, calendar, previous) when unit in [:month, :day] do
    [target_range] = fill_unspecified(unit, :any, calendar, previous)

    Enum.reduce(target_range, [], fn candidate, acc ->
      if matches_mask?(candidate, mask), do: [candidate | acc], else: acc
    end)
  end

  # For mask `[1, 5, 6, :X]` returns `{1560, 1569}`.
  # For mask `[:X, :X, :X, :X]` returns `{0, 9999}`.
  defp mask_bounds(mask) when is_list(mask) do
    {min_digits, max_digits} =
      Enum.reduce(mask, {[], []}, fn
        :X, {lo, hi} -> {[0 | lo], [9 | hi]}
        d, {lo, hi} when is_integer(d) -> {[d | lo], [d | hi]}
      end)

    {Integer.undigits(Enum.reverse(min_digits)),
     Integer.undigits(Enum.reverse(max_digits))}
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
