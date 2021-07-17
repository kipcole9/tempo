defmodule TempoTest do
  use ExUnit.Case
  alias Tempo.Iso8601.Parser
  doctest Tempo

  test "Date Parsing" do
    assert Parser.parse("2018-08-01") == {:ok, [date: [year: 2018, month: 8, day_of_month: 1]]}
    assert Parser.parse("1985") == {:ok, [date: [year: 1985]]}
    assert Parser.parse("12Y") == {:ok, [date: [year: 12]]}
    assert Parser.parse("8M") == {:ok, [date: [month: 8]]}
    assert Parser.parse("25D") == {:ok, [date: [day_of_month: 25]]}
    assert Parser.parse("19850412") == {:ok, [date: [year: 1985, month: 4, day_of_month: 12]]}
    assert Parser.parse("1985-04-12") == {:ok, [date: [year: 1985, month: 4, day_of_month: 12]]}
    assert Parser.parse("1985-04") == {:ok, [date: [year: 1985, month: 4]]}
    assert Parser.parse("1985") == {:ok, [date: [year: 1985]]}
    assert Parser.parse("1985102") == {:ok, [date: [year: 1985, day_of_year: 102]]}
    assert Parser.parse("1985W155") == {:ok, [date: [year: 1985, week: 15, day_of_week: 5]]}
    assert Parser.parse("1985W15") == {:ok, [date: [year: 1985, week: 15]]}
  end

  test "Time Parsing but should be toe :time not :datetime" do
    assert Parser.parse("T23:20:50") == {:ok, [datetime: [hour: 23, minute: 20, second: 50]]}
    assert Parser.parse("T23:20") == {:ok, [datetime: [hour: 23, minute: 20]]}
    assert Parser.parse("T23") == {:ok, [datetime: [hour: 23]]}
    assert Parser.parse("T23.3") == {:ok, [datetime: [hour: 23, fraction: 3]]}
    assert Parser.parse("T00:00:00") == {:ok, [datetime: [hour: 0, minute: 0, second: 0]]}
    assert Parser.parse("T23:20:30Z") ==
      {:ok,
       [
         datetime: [
           hour: 23,
           minute: 20,
           second: 30,
           time_shift: [sign: :postitive, hour: 0]
         ]
       ]}
  end

  test "Date Error parsing" do
    assert Parser.parse("W03")
    assert Parser.parse("10W")
    assert Parser.parse("6H")

    # Should be a decade
    assert Parser.parse("198")

    # Should be a century
    assert Parser.parse("19")

    # Extended format
    assert Parser.parse("+0019850412")

    # Extended Format
    assert Parser.parse("+001985-04-12")

    # Extended Format
    assert Parser.parse("+001985-04")

    # Extended Format
    assert Parser.parse("+001985")

    # Extended Format
    assert Parser.parse("+00198")

    # Extended Format
    assert Parser.parse("+0019")

    # Ordinal day
    assert Parser.parse("1985-102")

    assert Parser.parse("1985-W15-5")

    assert Parser.parse("1985-W15")
  end

  test "Time Error Parsing" do
    assert Parser.parse("T232050")
    assert Parser.parse("T2320")
    assert Parser.parse("23:20")
    assert Parser.parse("T232030,5")
    assert Parser.parse("T232030.5")
    assert Parser.parse("23:20:30.5")
    assert Parser.parse("T2320,8")
    assert Parser.parse("T2320.8")
    assert Parser.parse("2320.8")
    assert Parser.parse("T000000")
    assert Parser.parse("T232030Z")
  end
end
