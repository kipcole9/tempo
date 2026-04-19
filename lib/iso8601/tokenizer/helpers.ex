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

  @doc """
  ISO 8601-2 / EDTF qualification suffix.

  `?` marks a date as **uncertain** (the value is a best guess).
  `~` marks it as **approximate** (the value is approximately correct,
  e.g. "circa 1850").  `%` marks both.

  """
  def qualification(combinator \\ empty()) do
    combinator
    |> choice([
      replace(string("?"), :uncertain),
      replace(string("~"), :approximate),
      replace(string("%"), :uncertain_and_approximate)
    ])
    |> unwrap_and_tag(:qualification)
  end

  @doc """
  Qualification that attaches to a specific component.

  Emitted as `{unit_qualification: qualifier}` so that downstream
  consumers can identify which component is being qualified
  (e.g. `{:year_qualification, :uncertain}`).

  """
  def component_qualification(combinator \\ empty(), unit) do
    tag = :"#{unit}_qualification"

    combinator
    |> choice([
      replace(string("?"), :uncertain),
      replace(string("~"), :approximate),
      replace(string("%"), :uncertain_and_approximate)
    ])
    |> unwrap_and_tag(tag)
  end

  @doc """
  Merge a trailing `{:qualification, _}` token into the preceding
  tagged date/datetime/time inner list. Used by the
  `:qualified_endpoint` parsec to keep each interval endpoint and
  its qualification paired.

  Returns a single tuple so that the reduce emits one value into
  the enclosing parser accumulator, matching the shape emitted by
  `parsec(:datetime_or_date_or_time)` when no qualifier is present.

  """
  def merge_endpoint_qualification([{tag, inner}]) when tag in [:date, :datetime, :time_of_day] do
    {tag, inner}
  end

  def merge_endpoint_qualification([{tag, inner}, {:qualification, q}])
      when tag in [:date, :datetime, :time_of_day] do
    {tag, inner ++ [qualification: q]}
  end

  def merge_endpoint_qualification([{:qualification, q}, {tag, inner}])
      when tag in [:date, :datetime, :time_of_day] do
    {tag, inner ++ [qualification: q]}
  end

  # Both leading and trailing qualifiers present. The leading
  # applies to the whole expression; the trailing applies to the
  # last component. We keep the leading one on the expression-level
  # field and leave the trailing to be handled as a component
  # qualifier by the inner grammar.
  def merge_endpoint_qualification([{:qualification, q1}, {tag, inner}, {:qualification, q2}])
      when tag in [:date, :datetime, :time_of_day] do
    {tag, inner ++ [qualification: q1] ++ [trailing_qualification: q2]}
  end

  # Single-value pass-through (e.g. a duration or interval token that
  # was not wrapped by date/datetime/time_of_day).
  def merge_endpoint_qualification(other), do: other

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
