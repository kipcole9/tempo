defmodule Tempo.Event.Easter.Test do
  use ExUnit.Case

  alias Tempo.Event.Easter
  alias Tempo.GregorianEasterTest

  for [year, month, day] <- GregorianEasterTest.data() do
    test "Gregorian Easter for the year #{year}" do
      assert Easter.gregorian_easter(unquote(year)) ==
               Date.new!(unquote(year), unquote(month), unquote(day))
    end
  end
end
