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

  @doc """
  Return the list of valid values a mask can take at a given
  unit, constrained by the calendar and the preceding units.

  Unlike `fill_unspecified/4` (which drives enumeration and
  folds a heuristic for multi-digit widths), this function
  returns the exact candidate set: for `:month` with no leading
  constraint, that's `1..months_in_year(year)` filtered by the
  zero-padded digit pattern.

  ### Arguments

  * `unit` is one of `:year`, `:month`, `:day`, `:hour`,
    `:minute`, `:second`.

  * `mask` is the digit-pattern list (e.g. `[:X, :X]` or
    `[:X, 5]`).

  * `previous` is a keyword list of already-resolved units
    coarser than `unit` (e.g. `[year: 1985]` when matching
    `:month`).

  * `calendar` is the calendar module used to derive valid
    ranges (`months_in_year`, `days_in_month`, etc.).

  ### Returns

  * A sorted list of integers that are (a) in the valid range
    for the unit given `previous`, and (b) match the mask
    pattern when formatted to the mask's width with zero-padding.

  ### Examples

      iex> Tempo.Mask.valid_values(:month, [:X, :X], [year: 1985], Calendrical.Gregorian)
      [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]

      iex> Tempo.Mask.valid_values(:month, [:X, 5], [year: 1985], Calendrical.Gregorian)
      [5]

      iex> Tempo.Mask.valid_values(:day, [:X, :X], [year: 1985, month: 2], Calendrical.Gregorian)
      [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28]

  """
  @spec valid_values(
          unit :: atom(),
          mask :: list(),
          previous :: keyword(),
          calendar :: module()
        ) :: [integer()]
  def valid_values(unit, mask, previous, calendar) do
    width = length(mask)

    unit
    |> valid_range(previous, calendar)
    |> Enum.filter(&padded_matches_mask?(&1, mask, width))
  end

  defp valid_range(:month, previous, calendar) do
    year = Keyword.fetch!(previous, :year)
    1..calendar.months_in_year(year)
  end

  defp valid_range(:day, previous, calendar) do
    year = Keyword.fetch!(previous, :year)
    month = Keyword.fetch!(previous, :month)
    1..calendar.days_in_month(year, month)
  end

  defp valid_range(:hour, _previous, _calendar), do: 0..23
  defp valid_range(:minute, _previous, _calendar), do: 0..59
  defp valid_range(:second, _previous, _calendar), do: 0..59

  # Pad candidate to the mask's width with leading zeros, then
  # compare digit-by-digit: `:X` matches any digit; any other
  # element must match exactly.
  defp padded_matches_mask?(candidate, mask, width) do
    padded =
      candidate
      |> Integer.to_string()
      |> String.pad_leading(width, "0")

    digits =
      padded
      |> String.graphemes()
      |> Enum.map(&String.to_integer/1)

    length(digits) == width and digits_match?(digits, mask)
  end

  defp digits_match?([], []), do: true

  defp digits_match?([_digit | rest_d], [:X | rest_m]) do
    digits_match?(rest_d, rest_m)
  end

  defp digits_match?([digit | rest_d], [digit | rest_m]) when is_integer(digit) do
    digits_match?(rest_d, rest_m)
  end

  defp digits_match?(_, _), do: false

  @doc """
  Return the `{min, max}` numeric range spanned by a digit mask.

  Each `:X` position contributes `0..9` at its digit weight; each
  concrete digit contributes itself. Used by `fill_unspecified/4`
  to bound the candidate enumeration, and by `Tempo.to_interval/1`
  to compute the enclosing span of a masked value.

  ### Examples

      iex> Tempo.Mask.mask_bounds([1, 5, 6, :X])
      {1560, 1569}

      iex> Tempo.Mask.mask_bounds([:X, :X, :X, :X])
      {0, 9999}

  """
  def mask_bounds(mask) when is_list(mask) do
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
