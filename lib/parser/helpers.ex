defmodule Tempo.Iso8601.Parser.Helpers do
  import NimbleParsec

  def iso8601_parser do
    choice([
      date_time_x(),
      date_time(),
      calendar_date_x(),
      calendar_date(),
      ordinal_date_x(),
      ordinal_date(),
      calendar_week_date_x(),
      calendar_week_date(),
      ignore(optional(string("T"))) |> concat(time_of_day_x()),
      ignore(string("T")) |> concat(time_of_day()),
    ])
  end

  def calendar_year do
    optional(negative())
    |> ascii_char([?0..?9])
    |> times(4)
    |> reduce({List, :to_integer, []})
    |> unwrap_and_tag(:year)
  end

  def explicit_years do
    choice([
      explicit_years_bc(),
      explicit_years_with_sign()
    ])
  end

  def explicit_years_with_sign do
    optional(negative())
    |> ascii_char([?0..?9])
    |> times(min: 1)
    |> ignore(string("Y"))
    |> reduce({List, :to_integer, []})
    |> unwrap_and_tag(:years)
  end

  def explicit_years_bc do
    ascii_char([?0..?9])
    |> times(min: 1)
    |> ignore(string("Y"))
    |> reduce({List, :to_integer, []})
    |> optional(string("B"))
    |> post_traverse(:convert_bc)
    |> unwrap_and_tag(:years)
  end

  def convert_bc(_rest, ["B", int], context, _line, _offset) do
    {[-(int - 1)], context}
  end

  def convert_bc(_rest, args, context, _line, _offset) do
    IO.inspect args
    {args, context}
  end

  def calendar_month do
    ascii_char([?0..?9])
    |> times(2)
    |> reduce({List, :to_integer, []})
    |> unwrap_and_tag(:month)
  end

  def explicit_months do
    ascii_char([?0..?9])
    |> times(min: 1)
    |> ignore(string("M"))
    |> reduce({List, :to_integer, []})
    |> unwrap_and_tag(:nonths)
  end

  def calendar_week do
    string("W")
    |> ascii_char([?0..?9])
    |> times(2)
    |> reduce({List, :to_integer, []})
    |> unwrap_and_tag(:week)
  end

  def explicit_weeks do
    optional(negative())
    |> ascii_char([?0..?9])
    |> times(min: 1)
    |> ignore(string("W"))
    |> reduce({List, :to_integer, []})
    |> unwrap_and_tag(:weeks)
  end

  def calendar_day_of_month do
    ascii_char([?0..?9])
    |> times(2)
    |> reduce({List, :to_integer, []})
    |> unwrap_and_tag(:day_of_month)
  end

  def explicit_day_of_month do
    optional(negative())
    |> ascii_char([?0..?9])
    |> times(min: 1)
    |> ignore(string("D"))
    |> reduce({List, :to_integer, []})
    |> unwrap_and_tag(:days)
  end

  def calendar_day_of_week do
    ascii_char([?1..?7])
    |> reduce({List, :to_integer, []})
    |> unwrap_and_tag(:day_of_week)
  end

  def explicit_day_of_week do
    ascii_char([?1..?7])
    |> ignore(string("K"))
    |> reduce({List, :to_integer, []})
    |> unwrap_and_tag(:day_of_week)
  end

  def calendar_day_of_year do
    ascii_char([?0..?9])
    |> times(3)
    |> reduce({List, :to_integer, []})
    |> unwrap_and_tag(:day_of_year)
  end

  def explicit_day_of_year do
    optional(negative())
    |> ascii_char([?0..?9])
    |> times(min: 1)
    |> ignore(string("O"))
    |> reduce({List, :to_integer, []})
    |> unwrap_and_tag(:day_of_year)
  end

  def calendar_decade do
    ascii_char([?0..?9])
    |> times(3)
    |> reduce({List, :to_integer, []})
    |> unwrap_and_tag(:decade)
  end

  def explicit_decade do
    ascii_char([?0..?9])
    |> times(min: 1)
    |> ignore(string("J"))
    |> reduce({List, :to_integer, []})
    |> unwrap_and_tag(:decade)
  end

  def calendar_century do
    ascii_char([?0..?9])
    |> times(2)
    |> reduce({List, :to_integer, []})
    |> unwrap_and_tag(:century)
  end

  def explicit_century do
    ascii_char([?0..?9])
    |> times(min: 1)
    |> ignore(string("C"))
    |> reduce({List, :to_integer, []})
    |> unwrap_and_tag(:century)
  end

  def clock_hour do
    ascii_char([?0..?9])
    |> times(2)
    |> reduce({List, :to_integer, []})
    |> unwrap_and_tag(:hour)
  end

  def explicit_hours do
    ascii_char([?0..?9])
    |> times(min: 1)
    |> ignore(string("H"))
    |> reduce({List, :to_integer, []})
    |> unwrap_and_tag(:minutes)
  end

  def clock_minute do
    ascii_char([?0..?9])
    |> times(2)
    |> reduce({List, :to_integer, []})
    |> unwrap_and_tag(:minute)
  end

  def explicit_minutes do
    ascii_char([?0..?9])
    |> times(min: 1)
    |> ignore(string("M"))
    |> reduce({List, :to_integer, []})
    |> unwrap_and_tag(:minutes)
  end

  def clock_second do
    ascii_char([?0..?9])
    |> times(2)
    |> reduce({List, :to_integer, []})
    |> unwrap_and_tag(:second)
  end

  def explicit_seconds do
    ascii_char([?0..?9])
    |> times(min: 1)
    |> ignore(string("S"))
    |> reduce({List, :to_integer, []})
    |> unwrap_and_tag(:seconds)
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
    |> tag(:time_shift)
  end

  def time_shift_x do
    choice([
      sign() |> concat(clock_hour()) |> ignore(colon()) |> concat(clock_minute()),
      sign() |> concat(clock_hour()),
      zulu()
    ])
    |> tag(:time_shift)
  end

  def calendar_date do
    choice([
      calendar_year() |> concat(calendar_month()) |> concat(calendar_day_of_month()),
      calendar_year() |> ignore(dash()) |> concat(calendar_month()),
      calendar_year(),
      calendar_decade(),
      calendar_century()
    ])
    |> tag(:date)
  end

  def calendar_date_x do
    choice([
      calendar_year() |> ignore(dash()) |> concat(calendar_month()) |> ignore(dash()) |> concat(calendar_day_of_month()),
      calendar_year() |> ignore(dash()) |> concat(calendar_month()),
      calendar_year(),
      calendar_decade(),
      calendar_century()
    ])
    |> tag(:date)
  end

  def ordinal_date do
    calendar_year() |> concat(calendar_day_of_year())
    |> tag(:ordinal_date)
  end

  def ordinal_date_x do
    calendar_year() |> ignore(dash()) |> concat(calendar_day_of_year())
    |> tag(:ordinal_date)
  end

  def calendar_week_date do
    choice([
      calendar_year() |> concat(calendar_week()) |> concat(calendar_day_of_week()),
      calendar_year() |> concat(calendar_week())
    ])
    |> tag(:week_date)
  end

  def calendar_week_date_x do
    choice([
      calendar_year() |> ignore(dash()) |> concat(calendar_week()) |> ignore(dash()) |> concat(calendar_day_of_week()),
      calendar_year() |> ignore(dash()) |> concat(calendar_week())
    ])
    |> tag(:week_date)
  end

  def time_of_day do
    choice([
      clock_hour() |> concat(clock_minute()) |> concat(clock_second()),
      clock_hour() |> concat(clock_minute()),
      clock_hour()
    ])
    |> optional(fraction())
    |> optional(time_shift())
    |> tag(:time)
  end

  def time_of_day_x do
    choice([
      clock_hour() |> ignore(colon()) |> concat(clock_minute()) |> ignore(colon()) |> concat(clock_second()),
      clock_hour() |> ignore(colon()) |> concat(clock_minute()),
      clock_hour()
    ])
    |> optional(fraction())
    |> optional(time_shift_x())
    |> tag(:time)
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
    calendar_date() |> ignore(string("T")) |> concat(time_of_day())
    |> tag(:date_time)
  end

  def date_time_x do
    calendar_date_x() |> ignore(string("T")) |> concat(time_of_day_x())
    |> tag(:date_time)
  end

  def explicit do
    string("P")
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
      explicit_years() |> concat(explicit_months()) |> concat(explicit_day_of_month()),
      explicit_years() |> concat(explicit_months()),
      explicit_years()
    ])
  end

  def explicit_time do
    string("T")
    |> choice([
      explicit_hours() |> concat(explicit_minutes()) |> concat(explicit_seconds()),
      explicit_hours() |> concat(explicit_minutes()),
      explicit_hours()
    ])
  end
end