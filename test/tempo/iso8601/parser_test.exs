defmodule Tempo.Iso8601.Parser.Test do
  use ExUnit.Case, async: true

  test "Parsing centuries and decades resolves to a year range" do
    assert Tempo.from_iso8601("20C") ==
      {:ok, Tempo.new([year: [2000..2099]])}
    assert Tempo.from_iso8601("200J") ==
      {:ok, Tempo.new([year: [2000..2009]])}
    assert Tempo.from_iso8601("199J") ==
      {:ok, Tempo.new([year: [1990..1999]])}
    assert Tempo.from_iso8601("{1990..1999}Y") ==
      {:ok, Tempo.new([year: [1990..1999]])}
  end

end