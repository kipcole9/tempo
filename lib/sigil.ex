defmodule Tempo.Sigil do
  def sigil_o(string, []) do
    case Tempo.from_iso8601(string) do
      {:ok, tokens} -> tokens
      {:error, message} -> raise Tempo.ParseError, message
    end
  end
end