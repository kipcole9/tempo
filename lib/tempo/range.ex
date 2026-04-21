defmodule Tempo.Range do
  @moduledoc """
  A pair of Tempo values denoting a range, produced by the ISO
  8601-2 range operator (`2022..2024`). The first and last
  bounds are inclusive — contrast with `%Tempo.Interval{}`
  which uses the half-open `[from, to)` convention.

  Open-ended ranges are represented by `:undefined` on either
  endpoint (`../2024`, `2022/..`, `../..`).
  """

  @type endpoint :: Tempo.t() | :undefined

  @type t :: %__MODULE__{
          first: endpoint(),
          last: endpoint()
        }

  defstruct [:first, :last]

  @doc false
  def new(first, last, calendar \\ Calendrical.Gregorian) do
    first = Tempo.new(first, calendar)
    last = Tempo.new(last, calendar)
    %__MODULE__{first: first, last: last}
  end
end
