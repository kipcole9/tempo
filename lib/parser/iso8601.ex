defmodule Tempo.Iso8601.Parser do
  import NimbleParsec
  import Tempo.Iso8601.Parser.Helpers

  defparsec :iso8601, iso8601_parser()
  defparsec :date, implicit_date()
  defparsec :date_x, implicit_date_x()

  defparsec :dt, date_time()
  defparsec :dt_x, date_time_x()

  defparsec :explicit_year, explicit_year()
end