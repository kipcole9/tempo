defmodule Tempo.Set do
  @moduledoc """
  A Tempo-valued set — either **all-of** (`{a, b, c}` in ISO
  8601-2, free/busy semantics) or **one-of** (`[a, b, c]`,
  epistemic disjunction — "it was one of these, I don't know
  which").

  `type` carries that distinction. Set operations flatten an
  all-of `%Tempo.Set{}` into an IntervalSet; a one-of set is
  refused because asserting every member happened contradicts
  the user's intent.
  """

  @type t :: %__MODULE__{
          type: :all | :one,
          set: [Tempo.t()]
        }

  defstruct [:type, :set]

  def new(tokens, type, calendar \\ Calendrical.Gregorian) do
    tokens = Enum.map(tokens, &Tempo.new(&1, calendar))
    %__MODULE__{type: type, set: tokens}
  end
end
