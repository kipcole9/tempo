defmodule Tempo.Set do
  defstruct [:type, :set]

  def new(tokens, type, calendar \\ Cldr.Calendar.Gregorian) do
    tokens = Enum.map(tokens, &Tempo.new(&1, calendar))
    %__MODULE__{type: type, set: tokens}
  end
end
