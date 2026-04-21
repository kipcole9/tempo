defmodule Tempo.Duration do
  @moduledoc """
  A calendar-relative duration — a list of `{unit, amount}`
  pairs such as `[year: 1, month: 6]`. Produced by the ISO 8601
  parser (`P1Y6M`), the RRULE encoder (as the `FREQ + INTERVAL`
  cadence), and arithmetic helpers in `Tempo.Math`.
  """

  @type unit ::
          :year
          | :month
          | :week
          | :day
          | :hour
          | :minute
          | :second
          | :day_of_year
          | :day_of_week

  @type t :: %__MODULE__{
          time: [{unit(), integer()}]
        }

  defstruct [:time]

  def new(tokens) do
    %__MODULE__{time: tokens}
  end
end
