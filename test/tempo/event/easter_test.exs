defmodule Tempo.Event.Easter.Test do
  use ExUnit.Case

  for [year, month, day] <- Tempo.GregorianEasterTest.data() do
    test "Gregorian Easter for the year #{year}" do
      assert Tempo.Event.Easter.gregorian_easter(unquote(year)) ==
        Date.new!(unquote(year), unquote(month), unquote(day))
    end
  end

end