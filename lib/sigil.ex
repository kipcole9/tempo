defmodule Tempo.Sigil do
  defmacro sigil_o({:<<>>, _meta, [string]}, opts) do
    calendar = Tempo.Sigil.calendar_from(opts)

    case Tempo.from_iso8601(string, calendar) do
      {:ok, tempo} -> Macro.escape(tempo)
      {:error, exception} -> raise exception
    end
  end

  defmacro sigil_TEMPO({:<<>>, _meta, [string]}, opts) do
    calendar = Tempo.Sigil.calendar_from(opts)

    case Tempo.from_iso8601(string, calendar) do
      {:ok, tempo} -> Macro.escape(tempo)
      {:error, exception} -> raise exception
    end
  end

  def calendar_from([?W]) do
    Calendrical.ISOWeek
  end

  def calendar_from([]) do
    Calendrical.Gregorian
  end
end
