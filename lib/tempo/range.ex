defmodule Tempo.Range do
  defstruct [:first, :last]

  @doc false
  def new(first, last, calendar \\ Cldr.Calendar.Gregorian) do
    first = Tempo.new(first, calendar)
    last = Tempo.new(last, calendar)
    %__MODULE__{first: first, last: last}
  end

  @doc false

  # This is interesting, but not correct.
  # To enumerate a range requires the math operators
  # incrementing on the smallest time unit

  def to_tempo(%__MODULE__{first: first, last: last}) do
    time =
      Enum.zip_with first.time, last.time, fn {key, from}, {key, to} ->
        {key, [from..to]}
      end

    %Tempo{time: time, shift: first.shift, calendar: first.calendar}
  end
end
