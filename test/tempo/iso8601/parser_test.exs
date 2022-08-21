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

  test "Section 6 Sets" do
    # Section 6.1 Example 1
    assert Tempo.from_iso8601("{1960,1961,1962,1963}") ==
      {:ok, %Tempo{time: [year: [1960..1963]]}}

    # Section 6.1 Example 2
    assert Tempo.from_iso8601("{1960,1961-12}")
      {:ok, %Tempo.Set{type: :all, set: [[year: 1960], [year: 1961, month: 12]]}}

    # Section 6.2 Example 1
    assert Tempo.from_iso8601("[1984,1986,1988]")
      {:ok, %Tempo.Set{type: :one, set: [[year: 1984], [year: 1986], [year: 1988]]}}

    # Section 6.2 Example 2
    assert Tempo.from_iso8601("[1667,1760-12]")
      {:ok, %Tempo.Set{type: :one, set: [[year: 1667], [year: 1760, month: 12]]}}

    # Section 6.4 Example 1
    assert Tempo.from_iso8601("{1667,1668,1670..1672}") ==
      {:ok, %Tempo{time: [year: [1667..1668, 1670..1672]]}}

    # Section 6.4 Example 2
    assert Tempo.from_iso8601("[1760-01,1760-02,1760-12..]")
      {:ok,
       %Tempo.Set{
         type: :one,
         set: [
           [year: 1760, month: 1],
           [year: 1760, month: 2],
           [[year: 1760, month: 12], :undefined]
         ]
       }}

    # Section 6.4 Example 3
    assert Tempo.from_iso8601("{1M2S..1M5S}") ==
      {:ok,
       %Tempo.Set{
         type: :all,
         set: [range: [[minute: 1, second: 2], [minute: 1, second: 5]]]
       }}

    # Section 6.4 Example 4
    assert Tempo.from_iso8601("[1M2S,1M3S]") ==
      {:ok,
        %Tempo.Set{type: :one, set: [[minute: 1, second: 2], [minute: 1, second: 3]]}}

    # Section 6.6 Example 3
    assert Tempo.from_iso8601("2018-{1,3,5}G2MU") ==
      {:ok, %Tempo{time: [year: 2018, group: [all_of: [1, 3, 5], month: 2]]}}

  end

  test "Section 7 Dates" do
    # Section 7.2.3 Example 1
    assert Tempo.from_iso8601("1985Y102O") ==
      {:ok, %Tempo{time: [year: 1985, month: 4, day: 12]}}

    # Section 7.2.4 Example 1 with month based calendar
    assert Tempo.from_iso8601("1985Y15W7K") ==
      {:ok, %Tempo{time: [year: 1985, month: 4, day: 14]}}

    # Section 7.2.4 Example 1 with week based calendar
    assert Tempo.from_iso8601("1985Y15W7K", Cldr.Calendar.ISOWeek) ==
      {:ok, %Tempo{time: [year: 1985, week: 15, day: 7]}}
  end

  test "Section 7.3 Time" do
    # Section 7.3.1 Example 1
    assert Tempo.from_iso8601("T23H20M50S") ==
      {:ok, %Tempo{time: [hour: 23, minute: 20, second: 50]}}

    # Section 7.3.1 Example 2
    assert Tempo.from_iso8601("T23H20M") ==
      {:ok, %Tempo{time: [hour: 23, minute: 20]}}
  end
end