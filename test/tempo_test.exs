defmodule TempoTest do
  use ExUnit.Case, async: true
  import Tempo.Sigil

  doctest Tempo

  test "times with groups that can be expanded and resolved" do
    assert Tempo.from_iso8601("2018Y1G6MU") ==
      {:ok, %Tempo{calendar: Cldr.Calendar.Gregorian, time: [year: 2018, month: {:group, 1..6}]}}

    assert Tempo.from_iso8601("2018Y1G2MU30D") ==
      {:ok, %Tempo{calendar: Cldr.Calendar.Gregorian, time: [year: 2018, month: 1, day: 30]}}

    # 5.4.2 Group Example 7
    assert Tempo.from_iso8601("2018Y2G3MU50D") ==
      {:ok, %Tempo{calendar: Cldr.Calendar.Gregorian, time: [year: 2018, month: 5, day: 20]}}
  end

  test "times with invalid groups" do
    assert Tempo.from_iso8601("2018Y1G2MU60D") ==
      {:error, "60 is not valid. The valid values are 1..59"}
  end

  test "time with month and day but no year" do
    assert Tempo.from_iso8601("4M{1..-1}D") == {:ok, ~o"4M{1..30}D"}
    assert Tempo.from_iso8601("1M{1..-1}D") == {:ok, ~o"1M{1..31}D"}
    assert Tempo.from_iso8601("2M{1..-1}D") == {:error, "Cannot resolve days in month 2 without knowing the year"}
  end

  # 5.4.2 Group Example 8
  test "times that are two following groups of the same unit" do
    assert Tempo.from_iso8601("201J2G5YU3DT10H0S") ==
      {:ok, %Tempo{calendar: Cldr.Calendar.Gregorian, time: [year: [2015..2019], day: 3, hour: 10, minute: 0, second: 0]}}

  end

  test "tempo truncation" do
    assert Tempo.trunc(~o"12M31DT1H10M59S", :day) == ~o"12M31D"
    assert Tempo.trunc(~o"12M31DT1H10M59S", :year) == {:error, "Truncation would result in no time resolution"}
    assert Tempo.trunc(~o"12M31DT1H10M59S", :date) == {:error, "Invalid time unit :date"}
  end

  test "tempo merging" do
    assert Tempo.merge(~o"50M", ~o"2022Y") == {:error, "50 is not valid. The valid values are 1..12"}
    assert Tempo.merge(~o"12M", ~o"2022Y") == ~o"2022Y12M"
    assert Tempo.merge(~o"12M", ~o"2022Y1M") == ~o"2022Y1M"
  end
end
