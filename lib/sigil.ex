defmodule Tempo.Sigil do
  def sigil_o(string, opts) do
    calendar = calendar_from(opts)

    case Tempo.from_iso8601(string, calendar) do
      {:ok, tokens} -> tokens
      {:error, message} -> raise Tempo.ParseError, message
    end
  end

  defp calendar_from([?W]) do
    Cldr.Calendar.ISOWeek
  end

  defp calendar_from([]) do
    Cldr.Calendar.Gregorian
  end
end