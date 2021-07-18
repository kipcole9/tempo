defmodule TempoTest do
  use ExUnit.Case
  alias Tempo.Iso8601.Parser
  doctest Tempo

  test "Date Parsing" do
    assert Parser.date("2018-08-01") == {:ok, [date: [year: 2018, month: 8, day_of_month: 1]]}
    assert Parser.date("1985") == {:ok, [date: [year: 1985]]}
    assert Parser.date("12Y") == {:ok, [date: [year: 12]]}
    assert Parser.date("8M") == {:ok, [date: [month: 8]]}
    assert Parser.date("25D") == {:ok, [date: [day_of_month: 25]]}
    assert Parser.date("10W") == {:ok, [date: [week: 10]]}
    assert Parser.date("19850412") == {:ok, [date: [year: 1985, month: 4, day_of_month: 12]]}
    assert Parser.date("1985-04-12") == {:ok, [date: [year: 1985, month: 4, day_of_month: 12]]}
    assert Parser.date("1985-04") == {:ok, [date: [year: 1985, month: 4]]}
    assert Parser.date("1985") == {:ok, [date: [year: 1985]]}
    assert Parser.date("1985102") == {:ok, [date: [year: 1985, day_of_year: 102]]}
    assert Parser.date("1985W155") == {:ok, [date: [year: 1985, week: 15, day_of_week: 5]]}
    assert Parser.date("1985W15") == {:ok, [date: [year: 1985, week: 15]]}
    assert Parser.date("19") == {:ok, [date: [century: 19]]}
    assert Parser.date("198") == {:ok, [date: [decade: 198]]}
    assert Parser.date("1985-W15-1") == {:ok, [date: [year: 1985, week: 15, day_of_week: 1]]}
    assert Parser.date("1985-W15") == {:ok, [date: [year: 1985, week: 15]]}
    assert Parser.date("1985-102") == {:ok, [date: [year: 1985, day_of_year: 102]]}
    assert Parser.date("W03") == {:ok, [date: [week: 3]]}
  end

  test "Time Without Zone Parsing" do
    assert Parser.time("T23:20:50") == {:ok, [time_of_day: [hour: 23, minute: 20, second: 50]]}
    assert Parser.time("T23:20") == {:ok, [time_of_day: [hour: 23, minute: 20]]}
    assert Parser.time("T23") == {:ok, [time_of_day: [hour: 23]]}
    assert Parser.time("T23.3") == {:ok, [time_of_day: [hour: 23, fraction: 3]]}
    assert Parser.time("T00:00:00") == {:ok, [time_of_day: [hour: 0, minute: 0, second: 0]]}
    assert Parser.time("23:20") == {:ok, [time_of_day: [hour: 23, minute: 20]]}
    assert Parser.time("23:20:30.5") == {:ok, [time_of_day: [hour: 23, minute: 20, second: 30, fraction: 5]]}
    assert Parser.time("6H") == {:ok, [time_of_day: [hour: 6]]}
    assert Parser.time("T232050") == {:ok, [time_of_day: [hour: 23, minute: 20, second: 50]]}
    assert Parser.time("T2320") == {:ok, [time_of_day: [hour: 23, minute: 20]]}
    assert Parser.time("T232030,5") == {:ok, [time_of_day: [hour: 23, minute: 20, second: 30, fraction: 5]]}
    assert Parser.time("T232030.5") == {:ok, [time_of_day: [hour: 23, minute: 20, second: 30, fraction: 5]]}
    assert Parser.time("T2320,8") == {:ok, [time_of_day: [hour: 23, minute: 20, fraction: 8]]}
    assert Parser.time("T2320.8") == {:ok, [time_of_day: [hour: 23, minute: 20, fraction: 8]]}
    assert Parser.time("2320.8") == {:ok, [time_of_day: [hour: 23, minute: 20, fraction: 8]]}
    assert Parser.time("T000000") == {:ok, [time_of_day: [hour: 0, minute: 0, second: 0]]}
  end

  test "Time With Zone Parsing" do
    assert Parser.time("T23:20:30Z") ==
      {:ok,
       [
         time_of_day: [
           hour: 23,
           minute: 20,
           second: 30,
           time_shift: [sign: :positive, hour: 0]
         ]
       ]}
    assert Parser.time("T232030Z") ==
      {:ok,
       [
         time_of_day: [
           hour: 23,
           minute: 20,
           second: 30,
           time_shift: [sign: :positive, hour: 0]
         ]
       ]}
  end

  test "Date Error parsing" do
    # Extended format
    assert Parser.date("+0019850412")
    assert Parser.date("+001985-04-12")
    assert Parser.date("+001985-04")
    assert Parser.date("+001985")
    assert Parser.date("+00198")
    assert Parser.date("+0019")
  end

  test "Time Error Parsing" do

  end
end
