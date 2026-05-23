defmodule Tempo.Sigils.Options do
  @moduledoc false

  # Maps the sigil modifier character list to a calendar module.
  # Kept out of `Tempo.Sigils` so `import Tempo.Sigils` does not
  # bring `calendar_from/1` into the caller's scope.

  def calendar_from([?W]), do: Calendrical.ISOWeek
  def calendar_from([]), do: Calendrical.Gregorian
end
