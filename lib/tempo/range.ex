defmodule Tempo.Range do
  defstruct [:first, :last]

  @doc false
  def new(first, last, calendar \\ Cldr.Calendar.Gregorian) do
    first = Tempo.new(first, calendar)
    last = Tempo.new(last, calendar)
    %__MODULE__{first: first, last: last}
  end
end
