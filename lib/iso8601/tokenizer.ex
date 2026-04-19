defmodule Tempo.Iso8601.Tokenizer do
  @moduledoc """
  Tokenizes an ISO 8601 (parts 1 and 2) or IXDTF string into a
  list of tagged tokens that the `Tempo.Iso8601.Parser` then
  converts into a `t:Tempo.t/0` struct.

  `tokenize/1` returns a 2-tuple `{tokens, extended_info}` where
  `extended_info` is either `nil` or a map of parsed
  [IXDTF](https://www.ietf.org/archive/id/draft-ietf-sedate-datetime-extended-09.html)
  suffix information.  See `Tempo.Iso8601.Tokenizer.Extended` for
  the shape of the extended map.

  """

  import NimbleParsec
  import Tempo.Iso8601.Tokenizer.Numbers
  import Tempo.Iso8601.Tokenizer.Grammar
  import Tempo.Iso8601.Tokenizer.Helpers

  alias Tempo.Iso8601.Tokenizer.Extended

  @doc """
  Tokenize an ISO 8601 or IXDTF string.

  ### Arguments

  * `string` is any ISO 8601 formatted string, optionally with an
    [IXDTF](https://www.ietf.org/archive/id/draft-ietf-sedate-datetime-extended-09.html)
    suffix (such as `[Europe/Paris][u-ca=hebrew]`).

  ### Returns

  * `{:ok, {tokens, extended_info}}` where `tokens` is the list of
    ISO 8601 tokens produced by the parser and `extended_info` is
    either `nil` (when no IXDTF suffix was present) or a map with
    keys `:calendar`, `:zone_id`, `:zone_offset` and `:tags`.

  * `{:error, reason}` when the string cannot be parsed or a
    critical IXDTF suffix is unrecognised.

  """
  def tokenize(string) do
    string
    |> iso8601()
    |> return(string)
  end

  defp return(result, string) do
    case result do
      {:ok, tokens, "", %{}, {_, _}, _} ->
        Extended.split_extended(tokens)

      {:ok, _tokens, remaining, _, {_line, _}, _char} ->
        {:error, "Could not parse #{inspect(string)}. Error detected at #{inspect(remaining)}"}

      {:error, message, detected_at, _, _, _} ->
        {:error, String.capitalize(message) <> ". Error detected at #{inspect(detected_at)}"}
    end
  end

  defparsec :iso8601, iso8601_tokenizer()

  defcombinator :set,
                choice([
                  parsec(:set_all),
                  parsec(:set_one),
                  parsec(:interval_parser),
                  parsec(:datetime_or_date_or_time)
                ])

  defparsec :integer_or_integer_set,
            choice([
              integer(min: 1) |> unwrap_and_tag(:nth),
              parsec(:integer_set_all),
              parsec(:integer_set_one)
            ])
            |> label("integer or integer set")

  defparsec :set_all,
            ignore(string("{"))
            |> list_of_time_or_range()
            |> ignore(string("}"))
            |> tag(:all_of)

  defparsec :set_one,
            ignore(string("["))
            |> list_of_time_or_range()
            |> ignore(string("]"))
            |> tag(:one_of)

  defparsec :integer_set_all,
            ignore(string("{"))
            |> list_of_integer_or_range()
            |> ignore(string("}"))
            |> tag(:all_of)

  defparsec :integer_set_one,
            ignore(string("["))
            |> list_of_integer_or_range()
            |> ignore(string("]"))
            |> tag(:one_of)

  defparsec :interval_parser,
            optional(recurrence())
            |> choice([
              parsec(:datetime_or_date_or_time)
              |> ignore(string("/"))
              |> parsec(:datetime_or_date_or_time),
              parsec(:datetime_or_date_or_time)
              |> ignore(string("/"))
              |> parsec(:duration_parser),
              parsec(:duration_parser)
              |> ignore(string("/"))
              |> parsec(:datetime_or_date_or_time),
              parsec(:datetime_or_date_or_time)
              |> ignore(string("/"))
              |> replace(string(".."), :undefined),
              replace(string(".."), :undefined)
              |> ignore(string("/"))
              |> parsec(:datetime_or_date_or_time)
            ])
            |> optional(parsec(:repeat_rule))
            |> reduce(:adjust_interval)
            |> unwrap_and_tag(:interval)
            |> label("interval")

  defparsec :datetime_or_date_or_time,
            choice([
              parsec(:datetime_parser),
              parsec(:date_parser),
              parsec(:time_parser)
            ])
            |> label("datetime_or_date_or_time")

  # Private parsec definitions to reduce compile-time code expansion.
  # Each defparsecp creates a function call boundary instead of inlining
  # the combinator, significantly reducing generated code size.

  # Date combinators
  defparsecp :implicit_date_p, implicit_date()
  defparsecp :extended_date_p, extended_date()
  defparsecp :explicit_date_p, explicit_date()

  # Time-of-day combinators
  defparsecp :implicit_time_of_day_p, implicit_time_of_day()
  defparsecp :extended_time_of_day_p, extended_time_of_day()
  defparsecp :explicit_time_of_day_p, explicit_time_of_day()

  # Time shift combinators
  defparsecp :implicit_time_shift_p, implicit_time_shift()
  defparsecp :extended_time_shift_p, extended_time_shift()
  defparsecp :explicit_time_shift_p, explicit_time_shift()

  # Low-level component combinators
  defparsecp :implicit_year_p, implicit_year()
  defparsecp :implicit_month_p, implicit_month()
  defparsecp :implicit_day_of_month_p, implicit_day_of_month()
  defparsecp :implicit_hour_p, implicit_hour()
  defparsecp :implicit_minute_p, implicit_minute()
  defparsecp :implicit_week_p, implicit_week()

  # Duration and remaining implicit component combinators
  defparsecp :duration_elements_p, duration_elements()
  defparsecp :duration_time_elements_p, duration_time_elements()
  defparsecp :implicit_second_p, implicit_second()
  defparsecp :implicit_day_of_week_p, implicit_day_of_week()
  defparsecp :implicit_day_of_year_p, implicit_day_of_year()

  # Explicit composite combinators (only those called 3+ times)
  defparsecp :explicit_century_decade_or_year_p, explicit_century_decade_or_year()
  defparsecp :explicit_month_p, explicit_month()
  defparsecp :explicit_week_p, explicit_week()

  defparsec :datetime_parser,
            choice([
              explicit_date_time() |> optional(parsec(:explicit_time_shift_p)),
              extended_date_time() |> optional(parsec(:extended_time_shift_p)),
              implicit_date_time() |> optional(parsec(:implicit_time_shift_p)),
              explicit_time_shift()
            ])
            |> tag(:datetime)
            |> label("datetime")

  defparsec :date_parser,
            choice([
              parsec(:explicit_date_p)
              |> optional(parsec(:explicit_time_shift_p)),
              parsec(:extended_date_p)
              |> optional(fraction())
              |> optional(parsec(:extended_time_shift_p)),
              parsec(:implicit_date_p)
              |> optional(fraction())
              |> optional(parsec(:implicit_time_shift_p)),
              explicit_time_shift()
            ])
            |> reduce(:apply_fraction)
            |> post_traverse({:check_valid_date, []})
            |> unwrap_and_tag(:date)
            |> label("date")

  defparsec :time_parser,
            choice([
              parsec(:explicit_time_of_day_p) |> optional(parsec(:explicit_time_shift_p)),
              parsec(:extended_time_of_day_p) |> optional(parsec(:extended_time_shift_p)),
              parsec(:implicit_time_of_day_p) |> optional(parsec(:implicit_time_shift_p)),
              explicit_time_shift()
            ])
            |> tag(:time_of_day)
            |> label("time of day")

  defparsec :group,
            parsec(:integer_or_integer_set)
            |> ignore(string("G"))
            |> parsec(:duration_elements_p)
            |> ignore(string("U"))
            |> tag(:group)
            |> label("group")

  defparsec :time_group,
            parsec(:integer_or_integer_set)
            |> ignore(string("G"))
            |> parsec(:duration_time_elements_p)
            |> ignore(string("U"))
            |> tag(:group)
            |> label("time group")

  defparsec :selection,
            ignore(string("L"))
            |> selection_elements()
            |> optional(selection_instance())
            |> ignore(string("N"))
            |> tag(:selection)
            |> label("selection")

  defparsec :duration_parser,
            optional(negative() |> replace({:direction, :negative}))
            |> ignore(string("P"))
            |> concat(parsec(:duration_elements_p))
            |> tag(:duration)
            |> label("duration")

  defparsec :repeat_rule,
            ignore(string("/F"))
            |> parsec(:datetime_or_date_or_time)
            |> reduce(:extract_repeat_rule)
            |> label("repeat_rule")
            |> unwrap_and_tag(:repeat_rule)
end
