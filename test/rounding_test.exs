defmodule Tempo.Iso8601.RoundingTest do
  use ExUnit.Case, async: true
  import Tempo.Sigil

  test "Round to mounth" do
    assert Tempo.round(~o"2023Y8M01D", :month) == ~o"2023Y8M"
    assert Tempo.round(~o"2023Y8M20D", :month) == ~o"2023Y9M"
  end
end