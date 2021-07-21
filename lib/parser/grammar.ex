defmodule Tempo.Iso8601.Parser.Grammar do
  import NimbleParsec
  import Tempo.Iso8601.Parser.Numbers
  import Tempo.Iso8601.Parser.Helpers

  # NOTES

  # Doesn't not correctly parse negative centuries and decades
  # since elixir does not support the idea of -0.
  # See ISO8601 4.4.1.7 and 4.4.1.8

  def iso8601_parser do
    choice([
      parsec(:set),
      interval_or_time_or_duration()
    ])
    |> label("ISO8601 interval, duration, date, time or datetime")
  end

  def interval_or_time_or_duration(combinator \\ empty()) do
    combinator
    |> choice([
      parsec(:interval_parser),
      parsec(:datetime_or_date_or_time),
      parsec(:duration_parser)
    ])
  end

  def recurrence(combinator \\ empty()) do
    combinator
    |> ignore(ascii_char([?r, ?R]))
    |> optional(integer(min: 1))
    |> ignore(string("/"))
    |> reduce(:recur)
    |> unwrap_and_tag(:recurrence)
    |> label("recurrence")
  end

  def set_all do
    ignore(string("{"))
    |> list_of_time_or_range()
    |> ignore(string("}"))
    |> tag(:all_of)
  end

  def set_one do
    ignore(string("["))
    |> list_of_time_or_range()
    |> ignore(string("]"))
    |> tag(:one_of)
  end

  def list_of_time_or_range(combinator \\ empty()) do
    combinator
    |> time_or_range()
    |> repeat(ignore(string(",")) |> time_or_range())
    |> label("list of times or ranges")
  end

  def time_or_range(combinator \\ empty()) do
    combinator
    |> choice([
      interval_or_time_or_duration()
      |> ignore(string(".."))
      |> interval_or_time_or_duration()
      |> wrap(),
      replace(string(".."), :undefined)
      |> interval_or_time_or_duration()
      |> wrap(),
      interval_or_time_or_duration()
      |> replace(string(".."), :undefined)
      |> wrap(),
      interval_or_time_or_duration()
    ])
    |> label("date, time, interval, duration or range")
  end

  # Date Time

  def implicit_date_time do
    implicit_date() |> concat(implicit_time_of_day())
  end

  def implicit_date_time_x do
    implicit_date_x() |> concat(implicit_time_of_day_x())
  end

  def explicit_date_time do
    explicit_date() |> concat(explicit_time_of_day())
  end

  # Date

  def implicit_date do
    choice([
      implicit_week_date(),
      implicit_year()
      |> concat(implicit_month())
      |> concat(implicit_day_of_month()),
      implicit_year()
      |> concat(implicit_month())
      |> lookahead_not(digit()),
      implicit_ordinal_date(),
      implicit_year(),
      implicit_decade(),
      implicit_century(),
      implicit_month()
      |> concat(implicit_day_of_month())
    ])
    |> label("implicit date")
  end

  def implicit_date_x do
    choice([
      implicit_week_date_x(),
      implicit_year()
      |> ignore(dash())
      |> concat(implicit_month())
      |> ignore(dash())
      |> concat(implicit_day_of_month()),
      implicit_year()
      |> ignore(dash())
      |> concat(implicit_month())
      |> lookahead_not(digit()),
      implicit_month()
      |> ignore(dash())
      |> concat(implicit_day_of_month()),
      implicit_ordinal_date_x()
    ])
    |> label("extended date")
  end

  def explicit_date do
    choice([
      explicit_century_decade_or_year()
      |> concat(explicit_month())
      |> concat(explicit_day_of_month()),
      explicit_century_decade_or_year()
      |> concat(explicit_week())
      |> concat(explicit_day_of_week()),
      explicit_century_decade_or_year()
      |> concat(explicit_month()),
      explicit_century_decade_or_year()
      |> concat(explicit_week()),
      explicit_month()
      |> concat(explicit_day_of_month()),
      explicit_week()
      |> concat(explicit_day_of_week()),
      explicit_ordinal_date(),
      explicit_century_decade_or_year(),
      explicit_month()
      |> lookahead_not(explicit_time_of_day()),

      # Can create ambiguity with implicit week dates so care is required
      # This should also cater for looking ahead for interval separators
      # an probably other tokens
      explicit_week() |> eos(),
      explicit_day_of_year(),
      explicit_day_of_month(),
      explicit_day_of_week()
    ])
    |> label("explicit date")
  end

  def explicit_century_decade_or_year do
    choice([
      explicit_year(),
      explicit_century(),
      explicit_decade()
    ])
    |> label("century, decade or year")
  end

  def implicit_ordinal_date do
    implicit_year()
    |> concat(implicit_day_of_year())
  end

  def implicit_ordinal_date_x do
    implicit_year()
    |> ignore(dash())
    |> concat(implicit_day_of_year())
  end

  def explicit_ordinal_date do
    explicit_year()
    |> concat(explicit_day_of_year())
  end

  def implicit_week_date do
    choice([
      implicit_year()
      |> concat(implicit_week())
      |> concat(implicit_day_of_week()),
      implicit_year()
      |> concat(implicit_week()),
      implicit_week()
    ])
  end

  def implicit_week_date_x do
    choice([
      implicit_year()
      |> ignore(dash())
      |> concat(implicit_week())
      |> ignore(dash())
      |> concat(implicit_day_of_week()),
      implicit_year()
      |> ignore(dash())
      |> concat(implicit_week())
    ])
  end

  def explicit_week_date do
    choice([
      explicit_century_decade_or_year()
      |> concat(explicit_week())
      |> concat(explicit_day_of_week()),
      explicit_century_decade_or_year()
      |> concat(explicit_week()),
      explicit_week()
      |> concat(explicit_day_of_week()),
      explicit_week()
    ])
  end

  # Time

  def implicit_time_of_day do
    ignore(optional(string("T")))
    |> choice([
      implicit_hour()
      |> concat(implicit_minute())
      |> concat(implicit_second()),
      implicit_hour()
      |> concat(implicit_minute()),
      implicit_hour()
    ])
    |> optional(fraction())
    |> optional(time_shift())
  end

  def implicit_time_of_day_x do
    ignore(optional(string("T")))
    |> choice([
      implicit_hour()
      |> ignore(colon())
      |> concat(implicit_minute())
      |> ignore(colon())
      |> concat(implicit_second()),
      implicit_hour()
      |> ignore(colon())
      |> concat(implicit_minute())
    ])
    |> optional(fraction())
    |> optional(time_shift_x())
  end

  def explicit_time_of_day do
    ignore(optional(string("T")))
    |> choice([
      explicit_hour()
      |> concat(explicit_minute())
      |> concat(explicit_second()),
      explicit_hour()
      |> concat(explicit_minute()),
      explicit_minute()
      |> concat(explicit_second()),
      explicit_hour(),
      explicit_minute(),
      explicit_second()
    ])
    |> optional(time_shift())
  end

  # Parsing of durations
  # Does not current support fractional elements

  def duration_elements(combinator \\ empty()) do
    combinator
    |> choice([
      concat(duration_date_elements(), duration_time_elements()),
      duration_date_elements(),
      duration_time_elements(),
      parsec(:datetime_or_date_or_time)
    ])
  end

  def duration_date_elements do
    times(duration_date_element(), min: 1)
  end

  def duration_time_elements do
    ignore(string("T"))
    |> times(duration_time_element(), min: 1)
  end

  def duration_date_element do
    choice([
      maybe_negative_number(min: 1) |> ignore(string("C")) |> unwrap_and_tag(:century),
      maybe_negative_number(min: 1) |> ignore(string("J")) |> unwrap_and_tag(:decade),
      maybe_negative_number(min: 1) |> ignore(string("Y")) |> unwrap_and_tag(:year),
      maybe_negative_number(min: 1) |> ignore(string("M")) |> unwrap_and_tag(:month),
      maybe_negative_number(min: 1) |> ignore(string("W")) |> unwrap_and_tag(:week),
      maybe_negative_number(min: 1) |> ignore(string("D")) |> unwrap_and_tag(:day)
    ])
  end

  def duration_time_element do
    choice([
      maybe_negative_number(min: 1) |> ignore(string("H")) |> unwrap_and_tag(:hour),
      maybe_negative_number(min: 1) |> ignore(string("M")) |> unwrap_and_tag(:minute),
      maybe_negative_number(min: 1) |> ignore(string("S")) |> unwrap_and_tag(:second)
    ])
  end

  # Parsing of integer sets

  def integer_or_integer_set do
    choice([
      integer(min: 1) |> unwrap_and_tag(:nth),
      integer_set_all(),
      integer_set_one()
    ])
    |> label("integer or integer set")
  end

  def integer_set_all do
    ignore(string("{"))
    |> list_of_integer_or_range()
    |> ignore(string("}"))
    |> tag(:all_of)
  end

  def integer_set_one do
    ignore(string("["))
    |> list_of_integer_or_range()
    |> ignore(string("]"))
    |> tag(:one_of)
  end

  def list_of_integer_or_range(combinator \\ empty()) do
    combinator
    |> integer_or_range()
    |> repeat(ignore(string(",")) |> integer_or_range())
    |> label("list of integers or ranges")
  end

  def integer_or_range(combinator \\ empty()) do
    combinator
    |> choice([
      integer(min: 1) |> ignore(string("..")) |> integer(min: 1) |> wrap(),
      integer(min: 1)
    ])
    |> label("integer or range")
  end

  # Individual date and time components
  # Note that any component can be alternatively a group

  def implicit_year do
    choice([
      parsec(:group),
      ignore(optional(string("Y"))) |> maybe_negative_number(4)
    ])
    |> unwrap_and_tag(:year)
    |> label("implicit year")
  end

  def explicit_year do
    choice([
      explicit_year_bc(),
      explicit_year_with_sign()
    ])
    |> label("explicit year")
  end

  def explicit_year_with_sign do
    choice([
      parsec(:group),
      maybe_negative_number(min: 1)
      |> ignore(string("Y"))
    ])
    |> unwrap_and_tag(:year)
    |> label("explicit year with sign")
  end

  def explicit_year_bc do
    choice([
      parsec(:group),
      maybe_negative_number(min: 1)
      |> ignore(string("Y"))
      |> optional(string("B"))
    ])
    |> reduce(:convert_bc)
    |> unwrap_and_tag(:year)
    |> label("explicit year BC")
  end

  def implicit_month do
    choice([
      parsec(:group),
      positive_number(2)
    ])
    |> unwrap_and_tag(:month)
  end

  def explicit_month do
    choice([
      parsec(:group),
      maybe_negative_number(min: 1)
      |> ignore(string("M"))
    ])
    |> unwrap_and_tag(:month)
  end

  def implicit_week do
    ignore(string("W"))
    |> choice([
      parsec(:group),
      positive_number(2)
    ])
    |> unwrap_and_tag(:week)
  end

  # Explicit month will consume the group
  # if there is one so this doesn't attempt
  # the impossible - no group can be here
  def explicit_week do
    maybe_negative_number(min: 1)
    |> ignore(string("W"))
    |> unwrap_and_tag(:week)
  end

  def implicit_day_of_month do
    choice([
      parsec(:group),
      positive_number(2)
    ])
    |> unwrap_and_tag(:day_of_month)
  end

  def explicit_day_of_month do
    choice([
      parsec(:group),
      maybe_negative_number(min: 1)
      |> ignore(string("D"))
    ])
    |> unwrap_and_tag(:day_of_month)
  end

  def implicit_day_of_week do
    choice([
      parsec(:group),
      choice([
        ascii_char([?1..?7])
        |> reduce({List, :to_integer, []}),
        ascii_char([?X])
      ])
    ])
    |> unwrap_and_tag(:day_of_week)
  end

  def explicit_day_of_week do
    choice([
      parsec(:group),
      choice([
        day_of_week()
        |> reduce({List, :to_integer, []}),
        unknown()
      ])
      |> ignore(string("K"))
    ])
    |> unwrap_and_tag(:day_of_week)
  end

  def implicit_day_of_year do
    choice([
      parsec(:group),
      positive_number(3)
    ])
    |> unwrap_and_tag(:day_of_year)
  end

  def explicit_day_of_year do
    choice([
      parsec(:group),
      maybe_negative_number(min: 1)
      |> ignore(string("O"))
    ])
    |> unwrap_and_tag(:day_of_year)
  end

  # Decade and century, like week, cannot
  # ever encounter a group because the
  # Year combinator will consume it first since
  # Year has priority order over centure and
  # decade

  def implicit_decade do
    maybe_negative_number(3)
    |> unwrap_and_tag(:decade)
  end

  def explicit_decade do
    maybe_negative_number(min: 1)
    |> ignore(string("J"))
    |> unwrap_and_tag(:decade)
  end

  def implicit_century do
    maybe_negative_number(2)
    |> unwrap_and_tag(:century)
  end

  def explicit_century do
    maybe_negative_number(min: 1)
    |> ignore(string("C"))
    |> unwrap_and_tag(:century)
  end

  def implicit_hour do
    choice([
      parsec(:group),
      positive_number(2)
    ])
    |> unwrap_and_tag(:hour)
  end

  def explicit_hour do
    choice([
      parsec(:group),
      maybe_negative_number(min: 1)
      |> ignore(string("H"))
    ])
    |> unwrap_and_tag(:hour)
  end

  def implicit_minute do
    choice([
      parsec(:group),
      positive_number(2)
    ])
    |> unwrap_and_tag(:minute)
  end

  def explicit_minute do
    choice([
      parsec(:group),
      maybe_negative_number(min: 1)
      |> ignore(string("M"))
    ])
    |> unwrap_and_tag(:minute)
  end

  def implicit_second do
    choice([
      parsec(:group),
      positive_number(2)
    ])
    |> unwrap_and_tag(:second)
  end

  def explicit_second do
    choice([
      parsec(:group),
      maybe_negative_number(min: 1)
      |> ignore(string("S"))
    ])
    |> unwrap_and_tag(:second)
  end

  def time_shift do
    choice([
      sign()
      |> concat(implicit_hour())
      |> concat(implicit_minute()),
      sign()
      |> concat(implicit_hour()),
      zulu()
    ])
    |> reduce({:resolve_shift, []})
    |> unwrap_and_tag(:time_shift)
  end

  def time_shift_x do
    choice([
      sign()
      |> concat(implicit_hour())
      |> ignore(colon()) |> concat(implicit_minute()),
      sign()
      |> concat(implicit_hour()),
      zulu()
    ])
    |> reduce({:resolve_shift, []})
    |> unwrap_and_tag(:time_shift)
  end

  def resolve_shift([{:sign, ?-} | rest]) do
    [{:sign, :negative} | rest]
  end

  def resolve_shift([{:sign, ?+} | rest]) do
    [{:sign, :positive} | rest]
  end

  def resolve_shift([?Z | rest]) do
    [{:sign, :positive}, {:hour, 0} | rest]
  end
end
