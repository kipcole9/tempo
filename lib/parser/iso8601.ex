defmodule Tempo.Iso8601.Parser do
  import NimbleParsec
  import Tempo.Iso8601.Parser.Grammar
  import Tempo.Iso8601.Parser.Helpers

  defparsec :iso8601, iso8601_parser()

  defcombinator :interval,
    choice([
      parsec(:datetime_or_date_or_time) |> ignore(string("/")) |> parsec(:duration),
      parsec(:duration) |> ignore(string("/")) |> parsec(:datetime_or_date_or_time)
    ])
    |> tag(:interval)

  defcombinator :datetime_or_date_or_time,
    choice([
      parsec(:datetime),
      parsec(:date),
      parsec(:time)
    ])

  defcombinator :datetime,
    choice([
      explicit_date_time(),
      date_time_x(),
      date_time()
    ])
    |> tag(:dattime)

  defcombinator :date,
    choice([
      explicit_date(),
      implicit_date_x(),
      implicit_date()
    ])
    |> tag(:date)

  defcombinator :time,
    choice([
      explicit_time_of_day(),
      time_of_day_x(),
      time_of_day()
    ])
    |> tag(:time)

  defcombinator :group,
    optional(integer(min: 1) |> tag(:nth))
    |> ignore(string("G"))
    |> optional(explicit_date())
    |> optional(explicit_time())
    |> ignore(string("U"))
    |> tag(:group)

  defcombinator :duration,
    optional(negative() |> replace({:direction, :negative}))
    |> ignore(string("P"))
    |> times(duration_element(), min: 1)
    |> tag(:duration)
end