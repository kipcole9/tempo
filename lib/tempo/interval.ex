defmodule Tempo.Interval do
  @moduledoc false

  alias Tempo.Duration

  @type t :: %__MODULE__{
          recurrence: pos_integer() | :infinity,
          direction: 1 | -1,
          from: Tempo.t() | Tempo.Duration.t() | :undefined | nil,
          to: Tempo.t() | :undefined | nil,
          duration: Tempo.Duration.t() | nil,
          repeat_rule: Tempo.t() | nil
        }

  defstruct recurrence: 1,
            direction: 1,
            from: nil,
            to: nil,
            duration: nil,
            repeat_rule: nil

  # Clause ordering matters. The `:recurrence` peeler is the first
  # defence — it strips a leading recurrence token and recurses so
  # every other clause can ignore recurrence entirely.
  #
  # After that, clauses that reference the literal `:duration` tag
  # must come *before* any clause using a wildcard in the same
  # position, otherwise the wildcard clause will swallow duration
  # tokens and mis-classify them as dates.
  #
  # The tokenizer emits dates as one of `:date`, `:datetime`, or
  # `:time_of_day`; durations as `:duration`; undefined endpoints
  # as the atom `:undefined`. All of the following clauses
  # collectively cover every combination the tokenizer can produce.

  ## Recurrence peeler

  def new([{:recurrence, recur} | rest]) do
    rest
    |> new()
    |> Map.put(:recurrence, recur)
  end

  ## Two-element forms: undefined endpoints

  def new([:undefined, :undefined]) do
    %__MODULE__{from: :undefined, to: :undefined}
  end

  def new([{_from_tag, time}, :undefined]) do
    %__MODULE__{from: Tempo.new(time), to: :undefined}
  end

  def new([:undefined, {_to_tag, time}]) do
    %__MODULE__{from: :undefined, to: Tempo.new(time)}
  end

  ## Two-element forms with a duration (must precede the
  ## wildcard date/date clause below).

  def new([{:duration, duration}, {_to_tag, time}]) do
    %__MODULE__{from: :undefined, duration: Duration.new(duration), to: Tempo.new(time)}
  end

  def new([{_from_tag, time}, {:duration, duration}]) do
    %__MODULE__{from: Tempo.new(time), duration: Duration.new(duration)}
  end

  ## Two-element date/date form (wildcard; must be last among
  ## two-element clauses).

  def new([{_from_tag, from}, {_to_tag, to}]) do
    %__MODULE__{from: Tempo.new(from), to: Tempo.new(to)}
  end

  ## Three-element forms with a repeat_rule.

  def new([{:duration, duration}, {_to_tag, to}, {:repeat_rule, repeat_rule}]) do
    %__MODULE__{
      from: :undefined,
      to: Tempo.new(to),
      duration: Duration.new(duration),
      repeat_rule: Tempo.new(repeat_rule)
    }
  end

  def new([{_from_tag, from}, {:duration, duration}, {:repeat_rule, repeat_rule}]) do
    %__MODULE__{
      from: Tempo.new(from),
      duration: Duration.new(duration),
      repeat_rule: Tempo.new(repeat_rule)
    }
  end

  def new([{_from_tag, from}, {_to_tag, to}, {:repeat_rule, repeat_rule}]) do
    %__MODULE__{
      from: Tempo.new(from),
      to: Tempo.new(to),
      repeat_rule: Tempo.new(repeat_rule)
    }
  end
end
