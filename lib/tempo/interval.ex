defmodule Tempo.Interval do
  alias Tempo.Duration

  defstruct recurrence: 1,
            direction: 1,
            from: nil,
            to: nil,
            duration: nil,
            repeat_rule: nil

  def new([{_from, time}, {:duration, duration}]) do
    %__MODULE__{from: Tempo.new(time), duration: Duration.new(duration)}
  end

  def new([{_from, time}, :undefined]) do
    %__MODULE__{from: Tempo.new(time), to: :undefined}
  end

  def new([:undefined, {_to, time}]) do
    %__MODULE__{from: :undefined, to: Tempo.new(time)}
  end

  def new([{_from, time}, {_to, to}]) do
    %__MODULE__{from: Tempo.new(time), to: Tempo.new(to)}
  end

  def new([{_from, from}, {:duration, duration}, {:repeat_rule, repeat_rule}]) do
     %__MODULE__{from: Tempo.new(from), duration: Tempo.Duration.new(duration), repeat_rule: Tempo.new(repeat_rule)}
  end

  def new([{_from, from}, {:to, to}, {:repeat_rule, repeat_rule}]) do
     %__MODULE__{from: Tempo.new(from), to: Tempo.new(to), repeat_rule: Tempo.new(repeat_rule)}
  end

  def new([{:recurrence, recur} | rest]) do
    new(rest)
    |> Map.put(:recurrence, recur)
  end
end
