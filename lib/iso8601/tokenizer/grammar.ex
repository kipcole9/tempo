defmodule Tempo.Iso8601.Tokenizer.Grammar do
  import NimbleParsec
  import Tempo.Iso8601.Tokenizer.Numbers
  import Tempo.Iso8601.Tokenizer.Helpers

  # NOTES

  # Doesn't not correctly parse negative centuries and decades
  # since elixir does not support the idea of -0.
  # See ISO8601 4.4.1.7 and 4.4.1.8

  def iso8601_tokenizer do
    choice([
      interval_or_time_or_duration(),
      parsec(:set)
    ])
    |> label("ISO8601 interval, duration, date, time or datetime")
  end

  def interval_or_time_or_duration(combinator \\ empty()) do
    combinator
    |> choice([
      parsec(:interval_parser),
      parsec(:duration_parser),
      parsec(:datetime_or_date_or_time)
    ])
  end

  # Date Time

  def implicit_date_time do
    implicit_date() |> concat(implicit_time_of_day())
  end

  def extended_date_time do
    extended_date() |> concat(extended_time_of_day())
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

  def extended_date do
    choice([
      extended_week_date(),
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
      extended_ordinal_date()
    ])
    |> label("extended date")
  end

  def explicit_date do
    choice([
      # Year, month, day
      explicit_century_decade_or_year()
      |> concat(explicit_month())
      |> concat(explicit_day_of_month()),

      # Year, week, day of week
      explicit_century_decade_or_year()
      |> concat(explicit_week())
      |> concat(explicit_day_of_week()),

      # Year, month
      explicit_century_decade_or_year()
      |> concat(explicit_month()),

      # Year, day
      explicit_century_decade_or_year()
      |> concat(explicit_day_of_month()),

      # Year, week
      explicit_century_decade_or_year()
      |> concat(explicit_week()),

      # Month, day of month
      explicit_month()
      |> concat(explicit_day_of_month()),

      # Week, day of week
      explicit_week()
      |> concat(explicit_day_of_week()),

      # Ordinal Date (year-day_of_year)
      explicit_ordinal_date(),

      # Year
      explicit_century_decade_or_year(),

      # Month
      explicit_month()
      |> lookahead_not(explicit_time_of_day()),

      # Can create ambiguity with implicit week dates so care is required
      # This should also cater for looking ahead for interval separators
      # and probably other tokens
      explicit_week() |> lookahead_not(digit()),
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

  # Ordinal date

  def implicit_ordinal_date do
    implicit_year()
    |> concat(implicit_day_of_year())
  end

  def extended_ordinal_date do
    implicit_year()
    |> ignore(dash())
    |> concat(implicit_day_of_year())
  end

  def explicit_ordinal_date do
    explicit_year()
    |> concat(explicit_day_of_year())
  end

  # Week date

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

  def extended_week_date do
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
  end

  def extended_time_of_day do
    ignore(optional(string("T")))
    |> choice([
      implicit_hour()
      |> ignore(colon())
      |> concat(implicit_minute())
      |> ignore(colon())
      |> concat(implicit_second()),
      implicit_hour()
      |> ignore(colon())
      |> concat(implicit_minute()),
      implicit_hour()
      |> lookahead_not(digit())
    ])
    |> optional(fraction())
  end

  def explicit_time_of_day do
    ignore(optional(string("T")))
    |> choice([
      explicit_hour()
      |> optional(explicit_minute())
      |> optional(explicit_second()),
      explicit_minute()
      |> optional(explicit_second()),
      explicit_hour(),
      explicit_minute(),
      explicit_second()
    ])
  end

  # Durations

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

  def duration_time_elements(combinator \\ empty()) do
    combinator
    |> ignore(optional(string("T")))
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

  # Selections

  def selection_elements(combinator \\ empty()) do
    combinator
    |> choice([
      concat(selection_date_elements(), selection_time_elements()),
      selection_date_elements(),
      selection_time_elements()
    ])
  end

  def selection_date_elements do
    times(selection_date_element(), min: 1)
  end

  def selection_time_elements do
    ignore(string("T"))
    |> times(selection_time_element(), min: 1)
  end

  def selection_date_element do
    choice([
      maybe_negative_integer_or_integer_set("Y", :year, min: 1),
      maybe_negative_integer_or_integer_set("M", :month, min: 1),
      maybe_negative_integer_or_integer_set("W", :week, min: 1),
      maybe_negative_integer_or_integer_set("O", :day, min: 1),
      maybe_negative_integer_or_integer_set("D", :day, min: 1),
      maybe_negative_integer_or_integer_set("K", :day_of_week, min: 1),
      ignore(string("L")) |> parsec(:interval_parser) |> ignore(string("N"))
    ])
  end

  def selection_time_element do
    choice([
      maybe_negative_integer_or_integer_set("H", :hour, min: 1),
      maybe_negative_integer_or_integer_set("M", :minute, min: 1),
      maybe_negative_integer_or_integer_set("S", :second, min: 1),
      ignore(string("L")) |> parsec(:interval_parser) |> ignore(string("N"))
    ])
  end

  def selection_instance do
    maybe_negative_integer_or_integer_set("I", :instance, min: 1)
  end

  # Individual date and time components
  # Note that any component can be alternatively a group
  # or set

  def implicit_year do
    choice([
      parsec(:group),
      parsec(:integer_set_all) |> unwrap_and_tag(:year),
      ignore(string("Y")) |> maybe_negative_number(4) |> unwrap_and_tag(:year),
      maybe_negative_integer(4) |> unwrap_and_tag(:year)
    ])
    |> label("implicit year")
  end

  def explicit_year do
    choice([
      parsec(:group),
      parsec(:selection),
      explicit_year_bc() |> unwrap_and_tag(:year),
      explicit_year_with_sign() |> unwrap_and_tag(:year)
    ])
    |> label("explicit year")
  end

  def explicit_year_with_sign do
    choice([
      parsec(:integer_set_all) |> ignore(string("Y")),
      maybe_negative_number(min: 1) |> ignore(string("Y"))
    ])
    |> label("explicit year with sign")
  end

  def explicit_year_bc do
    choice([
      parsec(:integer_set_all) |> ignore(string("Y")),
      maybe_negative_number(min: 1) |> ignore(string("Y"))
    ])
    |> optional(string("B"))
    |> reduce(:convert_bc)
    |> label("explicit year BC")
  end

  # Months

  def implicit_month do
    choice([
      parsec(:group),
      positive_integer_or_integer_set(:month, 2),
      quarter(),
      half()
    ])
  end

  def explicit_month do
    choice([
      parsec(:group),
      parsec(:selection),
      maybe_negative_number_or_integer_set("M", :month, min: 1),
      quarter(),
      half()
    ])
  end

  # Weeks

  def implicit_week do
    ignore(string("W"))
    |> choice([
      parsec(:group),
      positive_integer_or_integer_set(:week, 2)
    ])
  end

  # Explicit month will consume the group
  # if there is one so this doesn't attempt
  # the impossible - no group can be here

  def explicit_week do
    choice([
      parsec(:group),
      parsec(:selection),
      maybe_negative_number_or_integer_set("W", :week, min: 1)
    ])
  end

  # Day of month

  def implicit_day_of_month do
    choice([
      parsec(:group),
      positive_integer_or_integer_set(:day, 2)
    ])
  end

  def explicit_day_of_month do
    choice([
      parsec(:group),
      parsec(:selection),
      maybe_negative_number_or_integer_set("D", :day, min: 1)
    ])
  end

  # Day of week

  def implicit_day_of_week do
    choice([
      parsec(:group),
      positive_integer_or_integer_set(:day_of_week, 1)
    ])
  end

  def explicit_day_of_week do
    choice([
      parsec(:group),
      parsec(:selection),
      maybe_negative_number_or_integer_set("K", :day_of_week, 1)
    ])
  end

  # Day of year

  def implicit_day_of_year do
    choice([
      parsec(:group),
      parsec(:integer_set_all) |> unwrap_and_tag(:day),
      positive_integer(3) |> unwrap_and_tag(:day)
    ])
  end

  def explicit_day_of_year do
    choice([
      parsec(:group),
      parsec(:selection),
      maybe_negative_number_or_integer_set("O", :day, min: 1)
    ])
  end

  # Decade and century, like week, cannot
  # ever encounter a group because the
  # Year combinator will consume it first since
  # Year has priority order over century and
  # decade

  def implicit_decade do
    maybe_negative_integer(3)
    |> unwrap_and_tag(:decade)
  end

  def explicit_decade do
    maybe_negative_number(min: 1)
    |> ignore(string("J"))
    |> unwrap_and_tag(:decade)
  end

  def implicit_century do
    maybe_negative_integer(2)
    |> lookahead_not(colon())
    |> unwrap_and_tag(:century)
  end

  def explicit_century do
    maybe_negative_number(min: 1)
    |> ignore(string("C"))
    |> unwrap_and_tag(:century)
  end

  # Time

  def implicit_hour do
    choice([
      parsec(:time_group),
      positive_number_or_integer_set(:hour, 2)
    ])
  end

  def explicit_hour do
    choice([
      parsec(:time_group),
      parsec(:selection),
      maybe_negative_number_or_integer_set("H", :hour, min: 1)
    ])
  end

  def implicit_minute do
    choice([
      parsec(:time_group),
      positive_number_or_integer_set(:minute, 2)
    ])
  end

  def explicit_minute do
    choice([
      parsec(:time_group),
      parsec(:selection),
      maybe_negative_number_or_integer_set("M", :minute, min: 1)
    ])
  end

  def implicit_second do
    choice([
      parsec(:time_group),
      positive_number_or_integer_set(:second, 2)
    ])
  end

  def explicit_second do
    choice([
      parsec(:time_group),
      parsec(:selection),
      maybe_negative_number_or_integer_set("S", :second, min: 1)
    ])
  end

  # Time Shift

  def implicit_time_shift do
    shift_indicator()
    |> choice([
      implicit_hour()
      |> ignore(optional(colon()))
      |> concat(implicit_minute()),
      implicit_hour(),
      lookahead_not(digit())
    ])
    |> reduce(:resolve_shift)
    |> unwrap_and_tag(:time_shift)
  end

  def extended_time_shift do
    shift_indicator()
    |> choice([
      implicit_hour()
      |> ignore(optional(colon()))
      |> concat(implicit_minute()),
      implicit_hour()
      |> lookahead_not(digit()),
      lookahead_not(digit())
    ])
    |> reduce(:resolve_shift)
    |> unwrap_and_tag(:time_shift)
  end

  def explicit_time_shift do
    shift_indicator()
    |> optional(explicit_hour())
    |> optional(explicit_minute())
    |> optional(explicit_second())
    |> lookahead_not(digit())
    |> reduce(:resolve_shift)
    |> unwrap_and_tag(:time_shift)
  end

  # A sign is required if no Z indicator
  # A sign is optional if there is a Z indicator

  def shift_indicator do
    choice([
      ignore(zulu()) |> concat(sign()) |> lookahead(digit()),
      sign() |> lookahead(digit()),
      zulu()
    ])
  end

  ## Helpers

  def recurrence(combinator \\ empty()) do
    combinator
    |> ignore(ascii_char([?r, ?R]))
    |> optional(integer(min: 1))
    |> ignore(string("/"))
    |> reduce(:recur)
    |> unwrap_and_tag(:recurrence)
    |> label("recurrence")
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
      |> reduce(:range),
      replace(string(".."), :undefined)
      |> interval_or_time_or_duration()
      |> reduce(:range),
      interval_or_time_or_duration()
      |> replace(string(".."), :undefined)
      |> reduce(:range),
      interval_or_time_or_duration()
    ])
    |> label("date, time, interval, duration or range")
  end

  def range(date: [{element, first}], date: [{element, last}])
      when is_integer(first) and is_integer(last) do
    {element, first..last}
  end

  def range([[first, "..", last]]) when is_integer(first) and is_integer(last) do
    first..last
  end

  def range([[first, "..", ?-, last]]) when is_integer(first) and is_integer(last) do
    first..-last
  end

  def range([[first, "..", last], step])
      when is_integer(first) and is_integer(last) and is_integer(step) do
    first..last//step
  end

  def range([[first, "..", ?-, last], step])
      when is_integer(first) and is_integer(last) and is_integer(step) do
    first..-last//step
  end

  def range([:undefined, {_type, other}]) do
    {:range, [:undefined, other]}
  end

  def range([{_type, other}, :undefined]) do
    {:range, [other, :undefined]}
  end

  def range([left, right]) do
    {:range, [left, right]}
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
      maybe_negative_integer(min: 1)
      |> string("..")
      |> maybe_negative_integer(min: 1)
      |> optional(ignore(string("//")) |> maybe_negative_integer(min: 1))
      |> reduce(:range),
      maybe_negative_integer(min: 1)
    ])
    |> label("integer or range")
  end

  def resolve_shift([{:sign, ?-}, {component, value} | rest]) do
    [{component, -value} | rest]
  end

  def resolve_shift([{:sign, ?+} | rest]) do
    rest
  end

  def resolve_shift([?Z]) do
    [{:hour, 0}]
  end

  def resolve_shift([?Z | rest]) do
    resolve_shift(rest)
  end

  def resolve_shift(other) do
    other
  end

  def adjust_interval(date: [year: year, month: month], date: [century: century]) do
    [date: [year: year, month: month], date: [month: century]]
  end

  def adjust_interval(other) do
    other
  end
end
