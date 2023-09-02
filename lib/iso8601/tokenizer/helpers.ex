defmodule Tempo.Iso8601.Tokenizer.Helpers do
  @doc false

  import NimbleParsec

  def recur([]), do: :infinity
  def recur([other]), do: other

  def sign do
    utf8_char([?+, ?-, ?−])
    |> unwrap_and_tag(:sign)
  end

  def zulu do
    ascii_char([?Z])
  end

  def colon do
    ascii_char([?:])
  end

  def dash do
    utf8_char([?-, ?‐])
  end

  def decimal_separator do
    ascii_char([?,, ?.])
  end

  def negative do
    ascii_char([?-])
  end

  def digit do
    ascii_char([?0..?9])
  end

  def unspecified do
    ascii_char([?X])
  end

  def all_unspecified do
    string("X*")
    |> replace(:"X*")
  end

  def day_of_week do
    ascii_char([?1..?7])
    |> reduce({List, :to_integer, []})
  end

  def quarter do
    ascii_char([?1..?4])
    |> ascii_char([?Q])
    |> reduce(:reduce_quarter)
    |> unwrap_and_tag(:month)
  end

  def half do
    ascii_char([?1..?2])
    |> ascii_char([?H])
    |> reduce(:reduce_half)
    |> unwrap_and_tag(:month)
  end

  # Converts quarters to the ISO Standard quarters
  # which are "months" of 33, 34, 35, 36
  def reduce_quarter([int, ?Q]) do
    int - 16
  end

  # Converts semestral (half) to the ISO Standard semestrals
  # which are "months" of 40 and 41
  def reduce_half([int, ?H]) do
    int - 9
  end

  def convert_bc([int, "B"]) do
    -(int - 1)
  end

  def convert_bc([other]) do
    other
  end

  def extract_repeat_rule([{_type, rule}]) do
    rule
  end

  # Some calendars have 13 months
  # Seasons are recognised as months 21..32 so we have to allow them
  # Quarters are recognised as months 33..36 so we have to allow them
  # Quadrimesters are recognised as months 36..39 so we have to allow them
  # Semestrals are recognised as momths 40..41 so we have to allow them

  def check_valid_date(
        _rest,
        [[{:year, _year}, {:month, month} | _remaining]],
        _context,
        _line,
        _offset
      )
      when is_number(month) and month > 13 and month not in 21..41 do
    {:error, :invalid_month}
  end

  def check_valid_date(_rest, [[{:month, month}, _remaining]], _context, _line, _offset)
      when is_number(month) and month > 13 and month not in 21..41 do
    {:error, :invalid_month}
  end

  # No supported calendars have more than 31 days in a month
  def check_valid_date(
        _rest,
        [[{:year, _year}, {:month, _month}, {:day, day} | _remaining]],
        _context,
        _line,
        _offset
      )
      when is_number(day) and day > 31 do
    {:error, :invalid_day}
  end

  def check_valid_date(
        _rest,
        [[{:month, _month}, {:day, day} | _remaining]],
        _context,
        _line,
        _offset
      )
      when is_number(day) and day > 31 do
    {:error, :invalid_day}
  end

  def check_valid_date(_rest, [[{:day, day}, _remaining]], _context, _line, _offset)
      when is_number(day) and day > 31 do
    {:error, :invalid_day}
  end

  def check_valid_date(rest, args, context, _line, _offset) do
    {rest, args, context}
  end
end
