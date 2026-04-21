defmodule Tempo.ParseError do
  defexception message: nil
end

defmodule Tempo.RoundingError do
  defexception message: nil
end

defmodule Tempo.ConversionError do
  @moduledoc """
  Raised when a Tempo value cannot be expressed in a target
  format.

  ISO 8601 and RFC 5545 RRULE are not fully interchangeable —
  each format can express things the other cannot. When a
  conversion is impossible, `Tempo.to_rrule/1` and related
  encoders return `{:error, %Tempo.ConversionError{}}` rather
  than a bare tuple, so the error carries a human-readable
  message and can be re-raised with `raise/1`.

  ### Fields

  * `:message` — a short, human-readable explanation.

  * `:value` — the source value that could not be converted
    (may be `nil`).

  * `:target` — the target format as an atom (`:rrule`,
    `:iso8601`).

  """
  @type t :: %__MODULE__{
          message: String.t() | nil,
          value: term() | nil,
          target: atom() | nil
        }

  defexception message: nil, value: nil, target: nil

  def exception(opts) when is_list(opts) do
    %__MODULE__{
      message: Keyword.get(opts, :message, "Cannot convert value to target format"),
      value: Keyword.get(opts, :value),
      target: Keyword.get(opts, :target)
    }
  end
end
