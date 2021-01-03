defmodule Tempo.Iso8601.Parser.Helpers do
  import NimbleParsec

  # NOTES

  # Doesn't not correctly parse negative centuries and decades
  # since elixir does not support the idea of -0.
  # See ISO8601 4.4.1.7 and 4.4.1.8

  def integer_or_unknown(combinator \\ empty(), opts)

  # Used parsing implicit forms
  def integer_or_unknown(combinator, n) when is_integer(n) do
    combinator
    |> choice([
      optional(negative()) |> integer(n) |> reduce(:detect_sign),
      ascii_char([?0..?9, ?X]) |> times(n)
    ])
    |> reduce(:detect_unknown)
  end

  # Used parsing explicit forms
  def integer_or_unknown(combinator, opts) do
    combinator
    |> choice([
      optional(negative()) |> integer(opts) |> reduce(:detect_sign),
      string("X*"),
      ascii_char([?0..?9, ?X]) |> times(opts)
    ])
    |> reduce(:detect_unknown)
  end

  def integer_or_unknown_year(combinator \\ empty(), opts) do
    combinator
    |> choice([
      maybe_exponent_integer(opts),
      string("X*"),
      ascii_char([?0..?9, ?X]) |> times(opts)
    ])
    |> reduce(:detect_unknown)
  end

  def maybe_exponent_integer(opts) do
    optional(negative())
    |> integer(opts)
    |> optional(string("E") |> integer(min: 1))
    |> optional(string("S") |> integer(min: 1))
    |> reduce(:detect_sign)
  end

  def iso8601_parser do
    choice([
      date_time_x(),
      date_time(),
      implicit_date_x(),
      implicit_date(),
      ordinal_date_x(),
      ordinal_date(),
      implicit_week_date_x(),
      implicit_week_date(),
      time_of_day_x(),
      time_of_day(),
      duration()
    ])
  end

  def implicit_year do
    integer_or_unknown(4)
    |> unwrap_and_tag(:year)
  end

  # Detect is a sign was presented in which case
  # apply it.

  def detect_sign([?-, integer]) do
    -integer
  end

  def detect_sign([?+, integer]) do
    integer
  end

  def detect_sign([integer]) when is_integer(integer) do
    integer
  end

  def detect_sign([?- | rest]) do
    case detect_sign(rest) do
      int when is_integer(int) -> -int
      {int, significance} -> {-int, significance}
    end
  end

  def detect_sign([int, "E", exp]) do
    int * :math.pow(10, exp) |> trunc
  end

  def detect_sign([int, "S", significance]) do
    {int, significance}
  end

  def detect_sign([int, "E", exp, "S", significance]) do
    {int * :math.pow(10, exp) |> trunc, significance}
  end

  # In many cases an integer can also have "placeholders"
  # represented by one or more `X`'s and these need to be
  # detected

  def detect_unknown(["X*"]) do
    [:undefined]
  end

  def detect_unknown([integer]) when is_integer(integer) do
    integer
  end

  def detect_unknown([tuple]) when is_tuple(tuple) do
    tuple
  end

  def detect_unknown(chars) when is_list(chars) do
    Enum.map chars, fn
      char when char in ?0..?9 -> char - ?0
      ?X -> :undefined
    end
  end

  def explicit_year do
    choice([
      explicit_year_bc(),
      explicit_year_with_sign()
    ])
  end

  def explicit_year_with_sign do
    integer_or_unknown_year(min: 1)
    |> ignore(string("Y"))
    |> unwrap_and_tag(:year)
  end

  def explicit_year_bc do
    integer_or_unknown_year(min: 1)
    |> ignore(string("Y"))
    |> optional(string("B"))
    |> reduce(:convert_bc)
    |> unwrap_and_tag(:year)
  end

  def convert_bc(["B", int]) do
    -(int - 1)
  end

  def convert_bc([other]) do
    other
  end

  def implicit_month do
    integer_or_unknown(2)
    |> unwrap_and_tag(:month)
  end

  def explicit_month do
    integer_or_unknown(min: 1)
    |> ignore(string("M"))
    |> unwrap_and_tag(:month)
  end

  def implicit_week do
    ignore(string("W"))
    |> integer_or_unknown(2)
    |> unwrap_and_tag(:week)
  end

  def explicit_weeks do
    integer_or_unknown(min: 1)
    |> ignore(string("W"))
    |> unwrap_and_tag(:week)
  end

  def implicit_day_of_month do
    integer_or_unknown(2)
    |> unwrap_and_tag(:day_of_month)
  end

  def explicit_day_of_month do
    integer_or_unknown(min: 1)
    |> ignore(string("D"))
    |> unwrap_and_tag(:day_of_month)
  end

  def implicit_day_of_week do
    choice([
      ascii_char([?1..?7]) |> reduce({List, :to_integer, []}),
      ascii_char([?X])
    ])
    |> unwrap_and_tag(:day_of_week)
  end

  def explicit_day_of_week do
    choice([
      ascii_char([?1..?7]) |> reduce({List, :to_integer, []}),
      ascii_char([?X])
    ])
    |> ignore(string("K"))
    |> unwrap_and_tag(:day_of_week)
  end

  def implicit_day_of_year do
    integer_or_unknown(3)
    |> unwrap_and_tag(:day_of_year)
  end

  def explicit_day_of_year do
    optional(negative())
    |> integer_or_unknown(min: 1)
    |> ignore(string("O"))
    |> reduce({List, :to_integer, []})
    |> unwrap_and_tag(:day_of_year)
  end

  def implicit_decade do
    integer_or_unknown(3)
    |> unwrap_and_tag(:decade)
  end

  def explicit_decade do
    integer_or_unknown(min: 1)
    |> ignore(string("J"))
    |> unwrap_and_tag(:decade)
  end

  def implicit_century do
    integer_or_unknown(2)
    |> unwrap_and_tag(:century)
  end

  def explicit_century do
    integer_or_unknown(min: 1)
    |> ignore(string("C"))
    |> unwrap_and_tag(:century)
  end

  def clock_hour do
    integer_or_unknown(2)
    |> unwrap_and_tag(:hour)
  end

  def explicit_hours do
    integer_or_unknown(min: 1)
    |> ignore(string("H"))
    |> unwrap_and_tag(:hour)
  end

  def clock_minute do
    integer_or_unknown(2)
    |> unwrap_and_tag(:minute)
  end

  def explicit_minutes do
    integer_or_unknown(min: 1)
    |> ignore(string("M"))
    |> unwrap_and_tag(:minute)
  end

  def clock_second do
    integer_or_unknown(2)
    |> unwrap_and_tag(:second)
  end

  def explicit_seconds do
    integer_or_unknown(min: 1)
    |> ignore(string("S"))
    |> unwrap_and_tag(:second)
  end

  def sign do
    ascii_char([?+, ?-])
    |> unwrap_and_tag(:sign)
  end

  def zulu do
    ascii_char([?Z])
  end

  def colon do
    ascii_char([?:])
  end

  def dash do
    ascii_char([?-])
  end

  def time_shift do
    choice([
      sign() |> concat(clock_hour()) |> concat(clock_minute()),
      sign() |> concat(clock_hour()),
      zulu()
    ])
    |> reduce({:resolve_shift, []})
    |> unwrap_and_tag(:time_shift)
  end

  def time_shift_x do
    choice([
      sign() |> concat(clock_hour()) |> ignore(colon()) |> concat(clock_minute()),
      sign() |> concat(clock_hour()),
      zulu()
    ])
    |> reduce({:resolve_shift, []})
    |> unwrap_and_tag(:time_shift)
  end

  def resolve_shift([{:sign, ?-} | rest]) do
    [{:sign, :negative} | rest]
  end

  def resolve_shift([{:sign, ?+} | rest]) do
    [{:sign, :postitive} | rest]
  end

  def resolve_shift([?Z | rest]) do
    [{:sign, :postitive}, {:hour, 0} | rest]
  end

  def implicit_date do
    choice([
      implicit_year() |> concat(implicit_month()) |> concat(implicit_day_of_month()),
      implicit_year() |> ignore(dash()) |> concat(implicit_month()),
      implicit_year(),
      implicit_decade(),
      implicit_century()
    ])
  end

  def implicit_date_x do
    choice([
      implicit_year() |> ignore(dash()) |> concat(implicit_month()) |> ignore(dash()) |> concat(implicit_day_of_month()),
      implicit_year() |> ignore(dash()) |> concat(implicit_month()),
      implicit_year(),
      implicit_decade(),
      implicit_century()
    ])
  end

  def ordinal_date do
    implicit_year() |> concat(implicit_day_of_year())
  end

  def ordinal_date_x do
    implicit_year() |> ignore(dash()) |> concat(implicit_day_of_year())
  end

  def implicit_week_date do
    choice([
      implicit_year() |> concat(implicit_week()) |> concat(implicit_day_of_week()),
      implicit_year() |> concat(implicit_week())
    ])
  end

  def implicit_week_date_x do
    choice([
      implicit_year() |> ignore(dash()) |> concat(implicit_week()) |> ignore(dash()) |> concat(implicit_day_of_week()),
      implicit_year() |> ignore(dash()) |> concat(implicit_week())
    ])
  end

  def time_of_day do
    ignore(string("T"))
    |> choice([
      clock_hour() |> concat(clock_minute()) |> concat(clock_second()),
      clock_hour() |> concat(clock_minute()),
      clock_hour()
    ])
    |> optional(fraction())
    |> optional(time_shift())
  end

  def time_of_day_x do
    ignore(optional(string("T")))
    |> choice([
      clock_hour() |> ignore(colon()) |> concat(clock_minute()) |> ignore(colon()) |> concat(clock_second()),
      clock_hour() |> ignore(colon()) |> concat(clock_minute()),
      clock_hour()
    ])
    |> optional(fraction())
    |> optional(time_shift_x())
  end

  def fraction do
    ignore(decimal_separator()) |> times(ascii_char([?0..?9]), min: 1)
    |> reduce({List, :to_integer, []})
    |> unwrap_and_tag(:fraction)
  end

  def decimal_separator do
    ascii_char([?,, ?.])
  end

  def negative do
    ascii_char([?-])
  end

  def date_time do
    implicit_date() |> ignore(string("T")) |> concat(time_of_day())
  end

  def date_time_x do
    implicit_date_x() |> ignore(string("T")) |> concat(time_of_day_x())
  end

  def duration do
    optional(negative() |> replace({:direction, :negative}))
    |> ignore(string("P"))
    |> choice([
      explicit_date() |> concat(explicit_time()),
      explicit_date(),
      explicit_time(),
      explicit_weeks()
    ])
    |> tag(:duration)
  end

  def explicit_date do
    choice([
      explicit_year() |> concat(explicit_month()) |> concat(explicit_day_of_month()),
      explicit_year() |> concat(explicit_month()),
      explicit_year()
    ])
  end

  def explicit_time do
    ignore(string("T"))
    |> choice([
      explicit_hours() |> concat(explicit_minutes()) |> concat(explicit_seconds()),
      explicit_hours() |> concat(explicit_minutes()),
      explicit_hours()
    ])
  end
end