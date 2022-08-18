defmodule Tempo.Interval do
  alias Tempo.Duration

  defstruct [:from, :to, :duration]

  def new([{_from, time}, {:duration, duration}]) do
    %__MODULE__{from: Tempo.new(time), duration: Duration.new(duration)}
  end

  def new([{_from, time}, {_to, to}]) do
    %__MODULE__{from: Tempo.new(time), to: Tempo.new(to)}
  end

end