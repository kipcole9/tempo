defmodule Tempo.Sigil do
  defmacro sigil_o({:<<>>, _meta, [string]}, opts) do
    calendar = Tempo.Sigil.calendar_from(opts)

    case Tempo.from_iso8601(string, calendar) do
      {:ok, tempo} -> Macro.escape(tempo)
      {:error, message} -> raise Tempo.ParseError, message
    end
  end

  defmacro sigil_TEMPO({:<<>>, _meta, [string]}, opts) do
    calendar = Tempo.Sigil.calendar_from(opts)

    case Tempo.from_iso8601(string, calendar) do
      {:ok, tempo} -> Macro.escape(tempo)
      {:error, message} -> raise Tempo.ParseError, message
    end
  end

  def calendar_from([?W]) do
    Cldr.Calendar.ISOWeek
  end

  def calendar_from([]) do
    Cldr.Calendar.Gregorian
  end
end
