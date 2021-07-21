defmodule Tempo do
  @moduledoc """
  Documentation for `Tempo`.
  """

  alias Tempo.Iso8601.Parser

  def from_iso8601(string) do
    case Parser.iso8601(string) do
      {:ok, parsed, "", %{}, _line, _char} -> {:ok, parsed}
      {:ok, _parsed, _rest, %{}, _line, _char} -> {:error, :invalid_format}
      {:error, _message, _rest, %{}, _line, _char} -> {:error, :invalid_format}
    end
  end
end
