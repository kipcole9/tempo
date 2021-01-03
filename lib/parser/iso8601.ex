defmodule Tempo.Iso8601.Parser do
  import NimbleParsec
  import Tempo.Iso8601.Parser.Grammar
  import Tempo.Iso8601.Parser.Helpers

  defparsec :iso8601, iso8601_parser()
  defparsec :date, implicit_date()

end