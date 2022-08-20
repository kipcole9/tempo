defmodule Tempo.Iso8601.Parser.Test do
  use ExUnit.Case, async: true

  test "Parsing centuries and decades resolves to a year group" do
    assert Tempo.from_iso8601("20C") ==
      {:ok, Tempo.new([year: 2000..2099])}
    assert Tempo.from_iso8601("200J") ==
      {:ok, Tempo.new([year: 2000..2009])}
    assert Tempo.from_iso8601("199J") ==
      {:ok, Tempo.new([year: 1990..1999])}
    assert Tempo.from_iso8601("{1990..1999}Y") ==
      {:ok, Tempo.new([year: [1990..1999]])}
  end

  test "Section 5: groups" do
    # 5.3 Example 1
    assert Tempo.from_iso8601("5G10DU") ==
      {:ok, %Tempo{time: [day: 41..50]}}

    # 5.3 Example 2
    assert Tempo.from_iso8601("20GT30MU") ==
      {:ok, %Tempo{time: [minute: 571..600]}}

    # 5.4.1 Example 1
    assert Tempo.from_iso8601("2018Y4G60DU6D") ==
      {:ok, %Tempo{time: [year: 2018, month: 7, day: 5]}}

    # 5.4.1 Example 3
    assert Tempo.from_iso8601("2018Y9M2DT3GT8HU30M")
      {:ok, %Tempo{time: [year: 2018, month: 9, day: 2, hour: 16, minute: 30]}}

    # 5.4.1 Example 4
    assert Tempo.from_iso8601("2018Y2M2G14DU") ==
      {:ok, %Tempo{time: [year: 2018, month: 2, day: 15..28]}}

    # 5.4.1 Example 5
    assert Tempo.from_iso8601("T16H1GT15MU") ==
      {:ok, %Tempo{time: [hour: 16, minute: 1..15]}}

    # 5.4.1 Example 6
    assert Tempo.from_iso8601("2018Y1G6MU") ==
      {:ok, %Tempo{time: [year: 2018, month: 1..6]}}

    # 5.4.2 Example 2
    assert Tempo.from_iso8601("10C5G20YU") ==
      {:ok, %Tempo{time: [year: [1080..1099]]}}

    # 5.4.2 Example 3
    assert Tempo.from_iso8601("1933Y1G80DU") ==
      {:ok, %Tempo{time: [year: 1933, day: 1..80]}}

    # 5.4.2 Example 4
    assert Tempo.from_iso8601("1543Y1M3G5DU") ==
      {:ok, %Tempo{time: [year: 1543, month: 1, day: 11..15]}}

    # 5.4.2 Example 5
    assert Tempo.from_iso8601("110Y2G3MU") ==
      {:ok, %Tempo{time: [year: 110, month: 4..6]}}

    # 5.4.2 Example 6
    assert Tempo.from_iso8601("6GT2HU") ==
      {:ok, %Tempo{time: [hour: 11..12]}}

    # 5.4.2 Example 7
    assert Tempo.from_iso8601("2018Y2G3MU50D") ==
      {:ok, %Tempo{time: [year: 2018, month: 5, day: 20]}}

    # 5.4.2 Example 8
    assert Tempo.from_iso8601("201J2G5YU3DT10H0S") ==
      {:ok, %Tempo{time: [year: [2015..2019], day: 3, hour: 10, second: 0]}}

    # 5.4.2 Example 9
    assert Tempo.from_iso8601("2018Y3G60DU6D") ==
      {:ok, %Tempo{time: [year: 2018, month: 5, day: 6]}}

    # 5.4.2 Example 10
    assert Tempo.from_iso8601("2018Y20GT12HU3H") ==
      {:ok, %Tempo{time: [year: 2018, month: 1, day: 10, hour: 15]}}

    # 5.4.3 Example 1
    assert Tempo.from_iso8601("2018Y1G2MU30D") ==
      {:ok, %Tempo{time: [year: 2018, month: 1, day: 30]}}

    # 5.4.3 Example 2
    assert Tempo.from_iso8601("2018Y1G2MU60D") ==
      {:error,
        "60 is greater than 59 which is the number of days in the group of months 1..2 " <>
        "for the calendar Cldr.Calendar.Gregorian"}

    # 5.4.4 Example 1
    assert Tempo.from_iso8601("2018Y3G60DU6DZ-5H") ==
      {:ok, %Tempo{time: [year: 2018, month: 5, day: 6, time_shift: [hour: -5]]}}

    # 5.4.4 Example 2
    assert Tempo.from_iso8601("2018Y3G60DU6DZ8H") ==
      {:ok, %Tempo{time: [year: 2018, month: 5, day: 6, time_shift: [hour: 8]]}}

    # 5.4.5.2 Example
    assert Tempo.from_iso8601("2018Y9M4G8DU") ==
      {:ok, %Tempo{time: [year: 2018, month: 9, day: 25..30]}}
  end

  test "todo tests" do
    # 5.3 Example 3
    assert Tempo.from_iso8601("2G2DT6HU") ==
      {:error, "Complex groupings not yet supported. Found [nth: 2, day: 2, hour: 6]"}
  end
end