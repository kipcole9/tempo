defmodule Tempo.Iso8601.Parser do
  import NimbleParsec
  import Tempo.Iso8601.Parser.Grammar
  import Tempo.Iso8601.Parser.Helpers

  def date(string) do
    string
    |> date_parser()
    |> return(string)
  end

  def time(string) do
    string
    |> time_parser()
    |> return(string)
  end

  def date_time(string) do
    string
    |> datetime_parser()
    |> return(string)
  end

  def interval(string) do
    string
    |> interval_parser()
    |> return(string)
  end

  defp return(result, string) do
    case result do
      {:ok, tokens, "", %{}, {_, _}, _} ->
        {:ok, tokens}

      {:ok, tokens, remaining, _, {_line, _}, _char} ->
        IO.inspect tokens
        {:error, "Could not parse #{inspect string}. Error detected at #{inspect remaining}"}

      {:error, message, detected_at, _, _, _} ->
        {:error, String.capitalize(message) <> ". Error deteted at #{inspect detected_at}"}
    end
  end

  defparsec :iso8601, iso8601_parser()

  defcombinator :set,
    choice([
      set_all(),
      set_one(),
      parsec(:interval_parser),
      parsec(:datetime_or_date_or_time)
    ])

  defparsec :interval_parser,
    choice([
      parsec(:datetime_or_date_or_time) |> ignore(string("/")) |> parsec(:datetime_or_date_or_time),
      parsec(:datetime_or_date_or_time) |> ignore(string("/")) |> parsec(:duration),
      parsec(:duration) |> ignore(string("/")) |> parsec(:datetime_or_date_or_time)
    ])
    |> tag(:interval)

  defcombinator :datetime_or_date_or_time,
    choice([
      parsec(:datetime_parser),
      parsec(:date_parser),
      parsec(:time_parser)
    ])

  defparsec :datetime_parser,
    choice([
      explicit_date_time(),
      implicit_date_time_x(),
      implicit_date_time()
    ])
    |> tag(:datetime)

  defparsec :date_parser,
    choice([
      explicit_date(),
      implicit_date_x(),
      implicit_date()
    ])
    |> tag(:date)

  defparsec :time_parser,
    choice([
      explicit_time_of_day(),
      implicit_time_of_day_x(),
      implicit_time_of_day()
    ])
    |> tag(:time_of_day)

  defcombinator :group,
    integer(min: 1)
    |> unwrap_and_tag(:nth)
    |> ignore(string("G"))
    |> optional(explicit_date())
    |> optional(explicit_time_of_day())
    |> ignore(string("U"))
    |> tag(:group)

  defcombinator :duration,
    optional(negative() |> replace({:direction, :negative}))
    |> ignore(string("P"))
    |> concat(duration_elements())
    |> tag(:duration)

  defcombinator :integer_or_integer_set,
    choice([
      integer(min: 1),
      integer_set_all(),
      integer_set_one()
    ])
    |> label("integer or integer set")

end
