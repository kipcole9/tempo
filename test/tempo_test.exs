defmodule TempoTest do
  use ExUnit.Case, async: true

  doctest Tempo

  test "times with groups that can be expanded and resolved" do
    assert Tempo.from_iso8601("2018Y9M4G8DU") ==
      {:ok, %Tempo{time: [year: 2018, month: 9, day: 25..30]}}

    assert Tempo.from_iso8601("2018Y1G6MU") ==
      {:ok, %Tempo{time: [year: 2018, month: 1..6]}}

    assert Tempo.from_iso8601("2018Y1G2MU30D") ==
      {:ok, %Tempo{time: [year: 2018, month: 1, day: 30]}}

    # 5.4.2 Group Example 7
    assert Tempo.from_iso8601("2018Y2G3MU50D") ==
      {:ok, %Tempo{time: [year: 2018, month: 5, day: 20]}}
  end

  test "times with invalid groups" do
    assert Tempo.from_iso8601("2018Y1G2MU60D") ==
      {:error,
        "60 is greater than 59 which is the number of days in the group of months 1..2 for " <>
        "the calendar Cldr.Calendar.Gregorian"}
  end

  # 5.4.2 Group Example 8
  test "times that are two following groups of the same unit" do
    assert Tempo.from_iso8601("201J2G5YU3DT10H0S") ==
      {:ok, %Tempo{time: [year: [2015..2019], day: 3, hour: 10, minute: 0, second: 0]}}

  end
end
