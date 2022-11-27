defmodule Tempo.Iso8601.Parser.Test do
  use ExUnit.Case, async: true
  import Tempo.Sigil

  test "Parsing centuries and decades resolves to a year group" do
    assert Tempo.from_iso8601("20C") ==
             {:ok, Tempo.new(year: {:group, 2000..2099})}

    assert Tempo.from_iso8601("200J") ==
             {:ok, Tempo.new(year: {:group, 2000..2009})}

    assert Tempo.from_iso8601("199J") ==
             {:ok, Tempo.new(year: {:group, 1990..1999})}

    assert Tempo.from_iso8601("{1990..1999}Y") ==
             {:ok, Tempo.new(year: [1990..1999])}
  end

  test "Section 5: groups" do
    # 5.3 Example 1
    assert Tempo.from_iso8601("5G10DU") ==
             {:ok, %Tempo{calendar: Cldr.Calendar.Gregorian, time: [day: {:group, 41..50}]}}

    # 5.3 Example 2
    assert Tempo.from_iso8601("20GT30MU") ==
             {:ok, %Tempo{calendar: Cldr.Calendar.Gregorian, time: [minute: {:group, 571..600}]}}

    # 5.4.1 Example 1
    assert Tempo.from_iso8601("2018Y4G60DU6D") ==
             {:ok,
              %Tempo{calendar: Cldr.Calendar.Gregorian, time: [year: 2018, month: 7, day: 5]}}

    # 5.4.1 Example 3
    assert Tempo.from_iso8601("2018Y9M2DT3GT8HU30M")

    {:ok,
     %Tempo{
       calendar: Cldr.Calendar.Gregorian,
       time: [year: 2018, month: 9, day: 2, hour: 16, minute: 30]
     }}

    # 5.4.1 Example 4
    assert Tempo.from_iso8601("2018Y2M2G14DU") ==
             {:ok,
              %Tempo{
                calendar: Cldr.Calendar.Gregorian,
                time: [year: 2018, month: 2, day: {:group, 15..28}]
              }}

    # 5.4.1 Example 5
    assert Tempo.from_iso8601("T16H1GT15MU") ==
             {:ok,
              %Tempo{calendar: Cldr.Calendar.Gregorian, time: [hour: 16, minute: {:group, 1..15}]}}

    # 5.4.1 Example 6
    assert Tempo.from_iso8601("2018Y1G6MU") ==
             {:ok,
              %Tempo{calendar: Cldr.Calendar.Gregorian, time: [year: 2018, month: {:group, 1..6}]}}

    # 5.4.2 Example 2
    assert Tempo.from_iso8601("10C5G20YU") ==
             {:ok, %Tempo{calendar: Cldr.Calendar.Gregorian, time: [year: [1080..1099]]}}

    # 5.4.2 Example 3
    assert Tempo.from_iso8601("1933Y1G80DU") ==
             {:ok,
              %Tempo{calendar: Cldr.Calendar.Gregorian, time: [year: 1933, day: {:group, 1..80}]}}

    # 5.4.2 Example 4
    assert Tempo.from_iso8601("1543Y1M3G5DU") ==
             {:ok,
              %Tempo{
                calendar: Cldr.Calendar.Gregorian,
                time: [year: 1543, month: 1, day: {:group, 11..15}]
              }}

    # 5.4.2 Example 5
    assert Tempo.from_iso8601("110Y2G3MU") ==
             {:ok,
              %Tempo{calendar: Cldr.Calendar.Gregorian, time: [year: 110, month: {:group, 4..6}]}}

    # 5.4.2 Example 6
    assert Tempo.from_iso8601("6GT2HU") ==
             {:ok, %Tempo{calendar: Cldr.Calendar.Gregorian, time: [hour: {:group, 11..12}]}}

    # 5.4.2 Example 7
    assert Tempo.from_iso8601("2018Y2G3MU50D") ==
             {:ok,
              %Tempo{calendar: Cldr.Calendar.Gregorian, time: [year: 2018, month: 5, day: 20]}}

    # 5.4.2 Example 8
    assert Tempo.from_iso8601("201J2G5YU3DT10H0S") ==
             {:ok,
              %Tempo{
                calendar: Cldr.Calendar.Gregorian,
                time: [year: [2015..2019], day: 3, hour: 10, minute: 0, second: 0]
              }}

    # 5.4.2 Example 9
    assert Tempo.from_iso8601("2018Y3G60DU6D") ==
             {:ok,
              %Tempo{calendar: Cldr.Calendar.Gregorian, time: [year: 2018, month: 5, day: 6]}}

    # 5.4.2 Example 10
    assert Tempo.from_iso8601("2018Y20GT12HU3H") ==
             {:ok,
              %Tempo{
                calendar: Cldr.Calendar.Gregorian,
                time: [year: 2018, month: 1, day: 10, hour: 15]
              }}

    # 5.4.3 Example 1
    assert Tempo.from_iso8601("2018Y1G2MU30D") ==
             {:ok,
              %Tempo{calendar: Cldr.Calendar.Gregorian, time: [year: 2018, month: 1, day: 30]}}

    # 5.4.3 Example 2
    assert Tempo.from_iso8601("2018Y1G2MU60D") ==
             {:error, "60 is not valid. The valid values are 1..59"}

    # 5.4.4 Example 1
    assert Tempo.from_iso8601("2018Y3G60DU6DZ-5H") ==
             {:ok,
              %Tempo{
                calendar: Cldr.Calendar.Gregorian,
                time: [year: 2018, month: 5, day: 6],
                shift: [hour: -5]
              }}

    # 5.4.4 Example 2
    assert Tempo.from_iso8601("2018Y3G60DU6DZ8H") ==
             {:ok,
              %Tempo{
                calendar: Cldr.Calendar.Gregorian,
                time: [year: 2018, month: 5, day: 6],
                shift: [hour: 8]
              }}

    # 5.4.5.2 Example
    assert Tempo.from_iso8601("2018Y9M4G8DU") ==
             {:ok,
              %Tempo{
                calendar: Cldr.Calendar.Gregorian,
                time: [year: 2018, month: 9, day: {:group, 25..30}]
              }}
  end

  test "todo tests" do
    # 5.3 Example 3
    assert Tempo.from_iso8601("2G2DT6HU") ==
             {:error, "Complex groupings not yet supported. Found [nth: 2, day: 2, hour: 6]"}
  end

  test "Section 6 Sets" do
    # Section 6.1 Example 1
    assert Tempo.from_iso8601("{1960,1961,1962,1963}") ==
             {:ok, %Tempo{calendar: Cldr.Calendar.Gregorian, time: [year: [1960..1963]]}}

    # Section 6.1 Example 2
    assert Tempo.from_iso8601("{1960,1961-12}") ==
      {:ok, %Tempo.Set{set: [~o"1960Y", ~o"1961Y12M"], type: :all}}

    # Section 6.2 Example 1
    assert Tempo.from_iso8601("[1984,1986,1988]") ==
      {:ok, %Tempo.Set{set: [~o"1984Y", ~o"1986Y", ~o"1988Y"], type: :one}}

    # Section 6.2 Example 2
    assert Tempo.from_iso8601("[1667,1760-12]") ==
      {:ok, %Tempo.Set{set: [~o"1667Y", ~o"1760Y12M"], type: :one}}

    # Section 6.4 Example 1
    assert Tempo.from_iso8601("{1667,1668,1670..1672}") ==
      {:ok, ~o"{1667..1668,1670..1672}Y"}

    # Section 6.4 Example 2
    assert Tempo.from_iso8601("[1760-01,1760-02,1760-12..]") ==
      {:ok, %Tempo.Set{set: [~o"1760Y1M", ~o"1760Y2M", {:range, ~o"1760Y12M", :undefined}], type: :one}}
      {:ok, ~o"[1760Y1M,1760Y2M,1760Y12M..]"}

    assert Tempo.from_iso8601("[1760-01,1760-02,..1760-12]") ==
      {:ok, ~o"[1760Y1M,1760Y2M,..1760Y12M]"}

    assert Tempo.from_iso8601("[1760-01,1760-02,1760-10..1760-12]") ==
      {:ok, ~o"[1760Y1M,1760Y2M,1760Y10M..1760Y12M]"}

    # Section 6.4 Example 3
    assert Tempo.from_iso8601("{1M2S..1M5S}") ==
      {:ok, %Tempo.Set{set: [{:range, ~o"T1M2S", ~o"T1M5S"}], type: :all}}

    # Section 6.4 Example 4
    assert Tempo.from_iso8601("[1M2S,1M3S]") ==
             {:ok, %Tempo.Set{set: [~o"T1M2S", ~o"T1M3S"], type: :one}}

    # Section 6.6 Example 3
    assert Tempo.from_iso8601("2018-{1,3,5}G2MU") ==
             {
               :ok,
               %Tempo{
                 calendar: Cldr.Calendar.Gregorian,
                 shift: nil,
                 time: [{:year, 2018}, {:month, {:group, {:all, [1, 3, 5]}}, 2}]
               }
             }
  end

  test "Section 7 Dates" do
    # Section 7.2.3 Example 1
    assert Tempo.from_iso8601("1985Y102O") ==
             {:ok,
              %Tempo{calendar: Cldr.Calendar.Gregorian, time: [year: 1985, month: 4, day: 12]}}

    # Section 7.2.4 Example 1 with month based calendar
    assert Tempo.from_iso8601("1985Y15W7K") ==
             {:ok,
              %Tempo{calendar: Cldr.Calendar.Gregorian, time: [year: 1985, month: 4, day: 14]}}

    # Section 7.2.4 Example 1 with week based calendar
    assert Tempo.from_iso8601("1985Y15W7K", Cldr.Calendar.ISOWeek) ==
             {:ok, %Tempo{calendar: Cldr.Calendar.ISOWeek, time: [year: 1985, week: 15, day: 7]}}
  end

  test "Section 7.3 Time" do
    # Section 7.3.1 Example 1
    assert Tempo.from_iso8601("T23H20M50S") ==
             {:ok,
              %Tempo{calendar: Cldr.Calendar.Gregorian, time: [hour: 23, minute: 20, second: 50]}}

    # Section 7.3.1 Example 2
    assert Tempo.from_iso8601("T23H20M") ==
             {:ok, %Tempo{calendar: Cldr.Calendar.Gregorian, time: [hour: 23, minute: 20]}}

    # Section 7.3.2
    assert Tempo.from_iso8601("T0H0M0S") ==
             {:ok,
              %Tempo{calendar: Cldr.Calendar.Gregorian, time: [hour: 0, minute: 0, second: 0]}}

    # Section 7.4 Example 1
    assert Tempo.from_iso8601("Z-5H") ==
             {:ok, %Tempo{calendar: Cldr.Calendar.Gregorian, time: [], shift: [hour: -5]}}

    # Section 7.4 Example 2
    assert Tempo.from_iso8601("Z8H") ==
             {:ok, %Tempo{calendar: Cldr.Calendar.Gregorian, time: [], shift: [hour: 8]}}

    # Section 7.4 Example 3
    assert Tempo.from_iso8601("Z28H") ==
             {:ok, %Tempo{calendar: Cldr.Calendar.Gregorian, time: [], shift: [hour: 28]}}

    # Section 7.4 Example 4
    assert Tempo.from_iso8601("Z6H0M") ==
             {:ok,
              %Tempo{calendar: Cldr.Calendar.Gregorian, time: [], shift: [hour: 6, minute: 0]}}

    # Section 7.4 Example 5
    assert Tempo.from_iso8601("Z7H33M14S") ==
             {:ok,
              %Tempo{
                calendar: Cldr.Calendar.Gregorian,
                time: [],
                shift: [hour: 7, minute: 33, second: 14]
              }}

    # Section 7.4 Example 6
    assert Tempo.from_iso8601("Z") ==
             {:ok, %Tempo{calendar: Cldr.Calendar.Gregorian, time: [], shift: [hour: 0]}}

    # Section 7.4 Example 7
    assert Tempo.from_iso8601("Z0H0M") ==
             {:ok,
              %Tempo{calendar: Cldr.Calendar.Gregorian, time: [], shift: [hour: 0, minute: 0]}}

    # Section 7.4 Example 8
    assert Tempo.from_iso8601("Z0S")
    {:ok, %Tempo{calendar: Cldr.Calendar.Gregorian, time: [], shift: [second: 0]}}
  end

  test "Section 7.5 Date Shift" do
    # Section 7.5 Example 1
    assert Tempo.from_iso8601("1985Y4M12DZ-5H") ==
             {:ok,
              %Tempo{
                calendar: Cldr.Calendar.Gregorian,
                time: [year: 1985, month: 4, day: 12],
                shift: [hour: -5]
              }}

    # Section 7.5 Example 2
    assert Tempo.from_iso8601("2018Y9M12DZ8H") ==
             {:ok,
              %Tempo{
                calendar: Cldr.Calendar.Gregorian,
                time: [year: 2018, month: 9, day: 12],
                shift: [hour: 8]
              }}
  end

  test "Section 7.6 Time with Time Shift" do
    # Section 7.6 Example 1
    assert Tempo.from_iso8601("T23H20M50SZ")

    {:ok,
     %Tempo{
       calendar: Cldr.Calendar.Gregorian,
       time: [hour: 23, minute: 20, second: 50],
       shift: [hour: 0]
     }}

    # Section 7.6 Example 2
    assert Tempo.from_iso8601("T23H20M50SZ-5H0M") ==
             {:ok,
              %Tempo{
                calendar: Cldr.Calendar.Gregorian,
                time: [hour: 23, minute: 20, second: 50],
                shift: [hour: -5, minute: 0]
              }}

    # Section 7.6 Example 3
    assert Tempo.from_iso8601("T23H20M50SZ8H") ==
             {:ok,
              %Tempo{
                calendar: Cldr.Calendar.Gregorian,
                time: [hour: 23, minute: 20, second: 50],
                shift: [hour: 8]
              }}
  end

  test "Section 7.7 Date and Time of Day" do
    # Section 7.7.2 Example 1
    assert Tempo.from_iso8601("1985Y4M12DT23H20M30S")

    {:ok,
     %Tempo{
       calendar: Cldr.Calendar.Gregorian,
       time: [year: 1985, month: 4, day: 12, hour: 23, minute: 20, second: 30]
     }}

    # Section 7.7.3 Example 1
    assert Tempo.from_iso8601("1985Y4M12DT23H20M30SZ8H")

    {:ok,
     %Tempo{
       calendar: Cldr.Calendar.Gregorian,
       time: [
         year: 1985,
         month: 4,
         day: 12,
         hour: 23,
         minute: 20,
         second: 30
       ],
       shift: [hour: 8]
     }}
  end

  test "Section 7.8 Decades" do
    # Section 7.8 Example 1
    assert Tempo.from_iso8601("188J") ==
             {:ok, %Tempo{calendar: Cldr.Calendar.Gregorian, time: [year: {:group, 1880..1889}]}}

    # Section 7.8 Example 2
    assert Tempo.from_iso8601("18J") ==
             {:ok, %Tempo{calendar: Cldr.Calendar.Gregorian, time: [year: {:group, 180..189}]}}
  end

  test "Section 7.9 Centuries" do
    # Section 7.9 Example 1
    assert Tempo.from_iso8601("13C") ==
             {:ok, %Tempo{calendar: Cldr.Calendar.Gregorian, time: [year: {:group, 1300..1399}]}}

    # Section 7.9 Example 2
    assert Tempo.from_iso8601("3C") ==
             {:ok, %Tempo{calendar: Cldr.Calendar.Gregorian, time: [year: {:group, 300..399}]}}
  end

  test "Section 7.12 Fractions for time" do
    # Section 7.12 Example 1
    assert Tempo.from_iso8601("2018Y8M8DT0,5H") ==
             {:ok,
              %Tempo{
                calendar: Cldr.Calendar.Gregorian,
                time: [year: 2018, month: 8, day: 8, hour: 0, minute: 30]
              }}

    # Section 7.12 Example 2
    assert Tempo.from_iso8601("2018Y8M8DT10H30.5M") ==
             {:ok,
              %Tempo{
                calendar: Cldr.Calendar.Gregorian,
                time: [year: 2018, month: 8, day: 8, hour: 10, minute: 30, second: 30]
              }}

    # Section 7.12 Example 3
    assert Tempo.from_iso8601("2018Y8M8DT10H30M15,3S") ==
             {:ok,
              %Tempo{
                calendar: Cldr.Calendar.Gregorian,
                time: [year: 2018, month: 8, day: 8, hour: 10, minute: 30, second: 15.3]
              }}
  end

  test "The universe - big bang to big crunch" do
    assert Tempo.from_iso8601("R/-13.787E9±20E6Y/..") ==
             {:ok,
              %Tempo.Interval{
                recurrence: :infinity,
                from: %Tempo{
                  calendar: Cldr.Calendar.Gregorian,
                  time: [year: {-13_787_000_000, [margin_of_error: 20_000_000]}]
                },
                to: :undefined,
                duration: nil
              }}
  end

  test "Fractional units can only be the last unit" do
    assert Tempo.from_iso8601("1985Y2.5M1D") ==
             {:error,
              "A fractional unit can only be used for the highest resolution unit (smallest time unit)"}

    assert Tempo.from_iso8601("1985Y1M5.5D") ==
             {:ok,
              %Tempo{
                time: [year: 1985, month: 1, day: 5, hour: 12],
                shift: nil,
                calendar: Cldr.Calendar.Gregorian
              }}

    assert Tempo.from_iso8601("1985Y1M5.6D") ==
             {:ok,
              %Tempo{
                time: [year: 1985, month: 1, day: 5, hour: 14, minute: 24],
                shift: nil,
                calendar: Cldr.Calendar.Gregorian
              }}

    assert Tempo.from_iso8601("1985.5Y") ==
             {:ok,
              %Tempo{
                time: [year: 1985, month: 7, day: 1, hour: 12],
                shift: nil,
                calendar: Cldr.Calendar.Gregorian
              }}

    assert Tempo.from_iso8601("1985Y2.5M") ==
             {:ok,
              %Tempo{
                time: [year: 1985, month: 2, day: 14],
                shift: nil,
                calendar: Cldr.Calendar.Gregorian
              }}
  end

  test "Negative seconds, minutes, hours, days and months" do
    import Tempo.Sigil

    assert ~o"1985Y-10M" ==
             %Tempo{
               time: [year: 1985, month: 3],
               shift: nil,
               calendar: Cldr.Calendar.Gregorian
             }

    assert ~o"1985Y-11M-1D" ==
             %Tempo{
               time: [year: 1985, month: 2, day: 28],
               shift: nil,
               calendar: Cldr.Calendar.Gregorian
             }

    assert ~o"2000Y-11M-1D" ==
             %Tempo{
               time: [year: 2000, month: 2, day: 29],
               shift: nil,
               calendar: Cldr.Calendar.Gregorian
             }

    assert Tempo.from_iso8601("T-1H") ==
             {:ok, %Tempo{time: [hour: 23], shift: nil, calendar: Cldr.Calendar.Gregorian}}

    assert Tempo.from_iso8601("T-1M") ==
             {:ok, %Tempo{time: [minute: 59], shift: nil, calendar: Cldr.Calendar.Gregorian}}

    assert Tempo.from_iso8601("T-1S") ==
             {:ok, %Tempo{time: [second: 59], shift: nil, calendar: Cldr.Calendar.Gregorian}}

    assert Tempo.from_iso8601("T-24H") ==
             {:ok, %Tempo{time: [hour: 0], shift: nil, calendar: Cldr.Calendar.Gregorian}}

    assert Tempo.from_iso8601("T-25H") ==
             {:error, "-25 is not valid. The normalized value of -1 is outside the range 0..23"}

    assert Tempo.from_iso8601("2022Y-13M31D") ==
             {:error, "-13 is not valid. The normalized value of 0 is outside the range 1..12"}

    assert Tempo.from_iso8601("2022Y-13M") ==
             {:error, "-13 is not valid. The normalized value of 0 is outside the range 1..12"}
  end

  test "Day of week adheres to calendar limit" do
    assert Tempo.from_iso8601("2022Y1W-7K") ==
             {:ok,
              %Tempo{
                time: [year: 2021, month: 12, day: 27],
                shift: nil,
                calendar: Cldr.Calendar.Gregorian
              }}

    assert Tempo.from_iso8601("2022Y1W7K") ==
             {:ok,
              %Tempo{
                time: [year: 2022, month: 1, day: 2],
                shift: nil,
                calendar: Cldr.Calendar.Gregorian
              }}

    assert Tempo.from_iso8601("2022Y1W7K", Cldr.Calendar.ISOWeek) ==
             {:ok,
              %Tempo{
                time: [year: 2022, week: 1, day: 7],
                shift: nil,
                calendar: Cldr.Calendar.ISOWeek
              }}

    assert Tempo.from_iso8601("2022Y1W8K", Cldr.Calendar.ISOWeek) ==
             {:error, "8 is not valid. The valid values are 1..7"}
  end

  test "Quarters, Quadrimesters and Semestrals" do
    assert Tempo.from_iso8601("2022Y1Q") ==
             {:ok,
              %Tempo{
                time: [year: 2022, month: {:group, 1..3}],
                shift: nil,
                calendar: Cldr.Calendar.Gregorian
              }}

    assert Tempo.from_iso8601("2022Y2Q") ==
             {:ok,
              %Tempo{
                time: [year: 2022, month: {:group, 4..6}],
                shift: nil,
                calendar: Cldr.Calendar.Gregorian
              }}

    assert Tempo.from_iso8601("2022Y3Q") ==
             {:ok,
              %Tempo{
                time: [year: 2022, month: {:group, 7..9}],
                shift: nil,
                calendar: Cldr.Calendar.Gregorian
              }}

    assert Tempo.from_iso8601("2022Y4Q") ==
             {:ok,
              %Tempo{
                time: [year: 2022, month: {:group, 10..12}],
                shift: nil,
                calendar: Cldr.Calendar.Gregorian
              }}

    assert Tempo.from_iso8601("2022Y37M") ==
             {:ok,
              %Tempo{
                time: [year: 2022, month: {:group, 1..4}],
                shift: nil,
                calendar: Cldr.Calendar.Gregorian
              }}

    assert Tempo.from_iso8601("2022Y38M") ==
             {:ok,
              %Tempo{
                time: [year: 2022, month: {:group, 5..8}],
                shift: nil,
                calendar: Cldr.Calendar.Gregorian
              }}

    assert Tempo.from_iso8601("2022Y39M") ==
             {:ok,
              %Tempo{
                time: [year: 2022, month: {:group, 9..12}],
                shift: nil,
                calendar: Cldr.Calendar.Gregorian
              }}

    assert Tempo.from_iso8601("2022Y1H") ==
             {:ok,
              %Tempo{
                time: [year: 2022, month: {:group, 1..6}],
                shift: nil,
                calendar: Cldr.Calendar.Gregorian
              }}

    assert Tempo.from_iso8601("2022Y2H") ==
             {:ok,
              %Tempo{
                time: [year: 2022, month: {:group, 7..12}],
                shift: nil,
                calendar: Cldr.Calendar.Gregorian
              }}
  end

  test "Integer sets with negative bounds" do
    assert Tempo.from_iso8601("T{-4..-1}H") ==
             {:ok, %Tempo{time: [hour: [-4..-1]], shift: nil, calendar: Cldr.Calendar.Gregorian}}
  end
end
