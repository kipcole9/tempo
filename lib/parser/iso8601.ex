defmodule Tempo.Iso8601.Parser do
  import NimbleParsec
  import Tempo.Iso8601.Parser.Grammar
  import Tempo.Iso8601.Parser.Helpers

  defparsec :iso8601, iso8601_parser()

  defcombinator :datetime,
    choice([
      explicit_date_time(),
      date_time_x(),
      date_time()
    ])

  defcombinator :date,
    choice([
      explicit_date(),
      implicit_date_x(),
      implicit_date()
    ])

  defcombinator :time,
    choice([
      explicit_time_of_day(),
      time_of_day_x() |> eos(),
      time_of_day()
    ])

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
    |> choice([
      explicit_date() |> concat(explicit_time()),
      explicit_date(),
      explicit_time(),
      explicit_century(),
      explicit_decade(),
      explicit_week()
    ])
    |> tag(:duration)
end