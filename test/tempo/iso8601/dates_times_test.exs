defmodule Tempo.Parser.DatesTimes.Test do
  use ExUnit.Case, async: true

  alias Tempo.Iso8601.Tokenizer

  test "Date Parsing" do
    assert Tokenizer.tokenize("2018-08-01") == {:ok, [date: [year: 2018, month: 8, day_of_month: 1]]}
    assert Tokenizer.tokenize("1985") == {:ok, [date: [year: 1985]]}
    assert Tokenizer.tokenize("12Y") == {:ok, [date: [year: 12]]}
    assert Tokenizer.tokenize("8M") == {:ok, [date: [month: 8]]}
    assert Tokenizer.tokenize("25D") == {:ok, [date: [day_of_month: 25]]}
    assert Tokenizer.tokenize("10W") == {:ok, [date: [week: 10]]}
    assert Tokenizer.tokenize("19850412") == {:ok, [date: [year: 1985, month: 4, day_of_month: 12]]}
    assert Tokenizer.tokenize("1985-04-12") == {:ok, [date: [year: 1985, month: 4, day_of_month: 12]]}
    assert Tokenizer.tokenize("1985-04") == {:ok, [date: [year: 1985, month: 4]]}
    assert Tokenizer.tokenize("1985") == {:ok, [date: [year: 1985]]}
    assert Tokenizer.tokenize("1985102") == {:ok, [date: [year: 1985, day_of_year: 102]]}
    assert Tokenizer.tokenize("1985W155") == {:ok, [date: [year: 1985, week: 15, day_of_week: 5]]}
    assert Tokenizer.tokenize("1985W15") == {:ok, [date: [year: 1985, week: 15]]}
    assert Tokenizer.tokenize("19") == {:ok, [date: [century: 19]]}
    assert Tokenizer.tokenize("198") == {:ok, [date: [decade: 198]]}
    assert Tokenizer.tokenize("1985-W15-1") == {:ok, [date: [year: 1985, week: 15, day_of_week: 1]]}
    assert Tokenizer.tokenize("1985-W15") == {:ok, [date: [year: 1985, week: 15]]}
    assert Tokenizer.tokenize("1985-102") == {:ok, [date: [year: 1985, day_of_year: 102]]}
    assert Tokenizer.tokenize("W03") == {:ok, [date: [week: 3]]}
  end

  test "Additional Explicit Forms section 4.3" do
    assert Tokenizer.tokenize("01M") == {:ok, [date: [month: 1]]}
    assert Tokenizer.tokenize("0001M") == {:ok, [date: [month: 1]]}
    assert Tokenizer.tokenize("1K") == {:ok, [date: [day_of_week: 1]]}
    assert Tokenizer.tokenize("350O") == {:ok, [date: [day_of_year: 350]]}
    assert Tokenizer.tokenize("16C") == {:ok, [date: [century: 16]]}
    assert Tokenizer.tokenize("-1985Y") == {:ok, [date: [year: -1985]]}
    assert Tokenizer.tokenize("1YB") == {:ok, [date: [year: 0]]}
    assert Tokenizer.tokenize("12YB") == {:ok, [date: [year: -11]]}
    assert Tokenizer.tokenize("-5D") == {:ok, [date: [day_of_month: -5]]}
    assert Tokenizer.tokenize("-3W") == {:ok, [date: [week: -3]]}
    assert Tokenizer.tokenize("-7O") == {:ok, [date: [day_of_year: -7]]}
    assert Tokenizer.tokenize("-306O") == {:ok, [date: [day_of_year: -306]]}
    assert Tokenizer.tokenize("-019") == {:ok, [date: [decade: -19]]}
    assert Tokenizer.tokenize("-1985") == {:ok, [date: [year: -1985]]}
    assert Tokenizer.tokenize("-12J") == {:ok, [date: [decade: -12]]}
    assert Tokenizer.tokenize("-19") == {:ok, [date: [century: -19]]}
    assert Tokenizer.tokenize("-12C") == {:ok, [date: [century: -12]]}
    assert Tokenizer.tokenize("-00") == {:ok, [date: [century: 0]]}
  end

  test "Exponential values section 4.4.2" do
    assert Tokenizer.tokenize("1230S2") == {:ok, [date: [year: {1230, 2}]]}
    assert Tokenizer.tokenize("3E3Y") == {:ok, [date: [year: 3000]]}
  end

  test "Unspecified digits section 4.6.2" do
    assert Tokenizer.tokenize("1390YXXM") == {:ok, [date: [year: 1390, month: 'XX']]}
  end

  test "Time Without Zone Parsing" do
    assert Tokenizer.tokenize("T23:20:50") == {:ok, [time_of_day: [hour: 23, minute: 20, second: 50]]}
    assert Tokenizer.tokenize("T23:20") == {:ok, [time_of_day: [hour: 23, minute: 20]]}
    assert Tokenizer.tokenize("T23") == {:ok, [time_of_day: [hour: 23]]}
    assert Tokenizer.tokenize("T23.3") == {:ok, [time_of_day: [hour: 23, fraction: 3]]}
    assert Tokenizer.tokenize("T00:00:00") == {:ok, [time_of_day: [hour: 0, minute: 0, second: 0]]}
    assert Tokenizer.tokenize("23:20") == {:ok, [time_of_day: [hour: 23, minute: 20]]}

    assert Tokenizer.tokenize("23:20:30.5") ==
             {:ok, [time_of_day: [hour: 23, minute: 20, second: 30, fraction: 5]]}

    assert Tokenizer.tokenize("6H") == {:ok, [time_of_day: [hour: 6]]}
    assert Tokenizer.tokenize("T232050") == {:ok, [time_of_day: [hour: 23, minute: 20, second: 50]]}
    assert Tokenizer.tokenize("T2320") == {:ok, [time_of_day: [hour: 23, minute: 20]]}

    assert Tokenizer.tokenize("T232030,5") ==
             {:ok, [time_of_day: [hour: 23, minute: 20, second: 30, fraction: 5]]}

    assert Tokenizer.tokenize("T232030.5") ==
             {:ok, [time_of_day: [hour: 23, minute: 20, second: 30, fraction: 5]]}

    assert Tokenizer.tokenize("T2320,8") == {:ok, [time_of_day: [hour: 23, minute: 20, fraction: 8]]}
    assert Tokenizer.tokenize("T2320.8") == {:ok, [time_of_day: [hour: 23, minute: 20, fraction: 8]]}
    assert Tokenizer.tokenize("T000000") == {:ok, [time_of_day: [hour: 0, minute: 0, second: 0]]}
  end

  test "Time With Zone Parsing" do
    assert Tokenizer.tokenize("T23:20:30Z") ==
             {:ok,
              [
                time_of_day: [
                  hour: 23,
                  minute: 20,
                  second: 30,
                  time_shift: [sign: :positive, hour: 0]
                ]
              ]}

    assert Tokenizer.tokenize("T232030Z") ==
             {:ok,
              [
                time_of_day: [
                  hour: 23,
                  minute: 20,
                  second: 30,
                  time_shift: [sign: :positive, hour: 0]
                ]
              ]}

    assert Tokenizer.tokenize("T152746+0100") ==
             {:ok,
              [
                time_of_day: [
                  hour: 15,
                  minute: 27,
                  second: 46,
                  time_shift: [sign: :positive, hour: 1, minute: 0]
                ]
              ]}

    assert Tokenizer.tokenize("T152746-0500") ==
             {:ok,
              [
                time_of_day: [
                  hour: 15,
                  minute: 27,
                  second: 46,
                  time_shift: [sign: :negative, hour: 5, minute: 0]
                ]
              ]}

    assert Tokenizer.tokenize("T152746-05") ==
             {:ok,
              [
                time_of_day: [
                  hour: 15,
                  minute: 27,
                  second: 46,
                  time_shift: [sign: :negative, hour: 5]
                ]
              ]}

    assert Tokenizer.tokenize("15:27:46+01:00") ==
             {:ok,
              [
                time_of_day: [
                  hour: 15,
                  minute: 27,
                  second: 46,
                  time_shift: [sign: :positive, hour: 1, minute: 0]
                ]
              ]}

    assert Tokenizer.tokenize("15:27:46+01") ==
             {:ok,
              [
                time_of_day: [
                  hour: 15,
                  minute: 27,
                  second: 46,
                  time_shift: [sign: :positive, hour: 1]
                ]
              ]}

    assert Tokenizer.tokenize("15:27:46-05") ==
             {:ok,
              [
                time_of_day: [
                  hour: 15,
                  minute: 27,
                  second: 46,
                  time_shift: [sign: :negative, hour: 5]
                ]
              ]}
  end

  test "Date Time parsing" do
    assert Tokenizer.tokenize("19850412T232030") ==
             {:ok,
              [
                datetime: [
                  year: 1985,
                  month: 4,
                  day_of_month: 12,
                  hour: 23,
                  minute: 20,
                  second: 30
                ]
              ]}

    assert Tokenizer.tokenize("19850412T232030Z") ==
             {:ok,
              [
                datetime: [
                  year: 1985,
                  month: 4,
                  day_of_month: 12,
                  hour: 23,
                  minute: 20,
                  second: 30,
                  time_shift: [sign: :positive, hour: 0]
                ]
              ]}

    assert Tokenizer.tokenize("19850412T232030+0400")

    {:ok,
     [
       datetime: [
         year: 1985,
         month: 4,
         day_of_month: 12,
         hour: 23,
         minute: 20,
         second: 30,
         time_shift: [sign: :positive, hour: 4, minute: 0]
       ]
     ]}

    assert Tokenizer.tokenize("1985-04-12T23:20:30")

    {:ok,
     [
       datetime: [
         year: 1985,
         month: 4,
         day_of_month: 12,
         hour: 23,
         minute: 20,
         second: 30
       ]
     ]}

    assert Tokenizer.tokenize("1985-04-12T23:20:30Z")

    {:ok,
     [
       datetime: [
         year: 1985,
         month: 4,
         day_of_month: 12,
         hour: 23,
         minute: 20,
         second: 30,
         time_shift: [sign: :positive, hour: 0]
       ]
     ]}

    assert Tokenizer.tokenize("1985-04-12T23:20:30+04:00")

    {:ok,
     [
       datetime: [
         year: 1985,
         month: 4,
         day_of_month: 12,
         hour: 23,
         minute: 20,
         second: 30,
         time_shift: [sign: :positive, hour: 4, minute: 0]
       ]
     ]}

    assert Tokenizer.tokenize("1985-04-12T23:20:30+04")

    {:ok,
     [
       datetime: [
         year: 1985,
         month: 4,
         day_of_month: 12,
         hour: 23,
         minute: 20,
         second: 30,
         time_shift: [sign: :positive, hour: 4]
       ]
     ]}

    assert Tokenizer.tokenize("1985102T232030") ==
             {:ok, [datetime: [year: 1985, day_of_year: 102, hour: 23, minute: 20, second: 30]]}

    assert Tokenizer.tokenize("1985102T232030Z") ==
             {:ok,
              [
                datetime: [
                  year: 1985,
                  day_of_year: 102,
                  hour: 23,
                  minute: 20,
                  second: 30,
                  time_shift: [sign: :positive, hour: 0]
                ]
              ]}

    assert Tokenizer.tokenize("1985-102T23:20:30+04:00") ==
             {:ok,
              [
                datetime: [
                  year: 1985,
                  day_of_year: 102,
                  hour: 23,
                  minute: 20,
                  second: 30,
                  time_shift: [sign: :positive, hour: 4, minute: 0]
                ]
              ]}

    assert Tokenizer.tokenize("1985-102T23:20:30+04") ==
             {:ok,
              [
                datetime: [
                  year: 1985,
                  day_of_year: 102,
                  hour: 23,
                  minute: 20,
                  second: 30,
                  time_shift: [sign: :positive, hour: 4]
                ]
              ]}

    assert Tokenizer.tokenize("1985W155T232030") ==
             {:ok,
              [
                datetime: [
                  year: 1985,
                  week: 15,
                  day_of_week: 5,
                  hour: 23,
                  minute: 20,
                  second: 30
                ]
              ]}

    assert Tokenizer.tokenize("1985W155T232030Z") ==
             {:ok,
              [
                datetime: [
                  year: 1985,
                  week: 15,
                  day_of_week: 5,
                  hour: 23,
                  minute: 20,
                  second: 30,
                  time_shift: [sign: :positive, hour: 0]
                ]
              ]}

    assert Tokenizer.tokenize("1985W155T232030+0400") ==
             {:ok,
              [
                datetime: [
                  year: 1985,
                  week: 15,
                  day_of_week: 5,
                  hour: 23,
                  minute: 20,
                  second: 30,
                  time_shift: [sign: :positive, hour: 4, minute: 0]
                ]
              ]}

    assert Tokenizer.tokenize("1985-W15-5T23:20:30") ==
             {:ok,
              [
                datetime: [
                  year: 1985,
                  week: 15,
                  day_of_week: 5,
                  hour: 23,
                  minute: 20,
                  second: 30
                ]
              ]}

    assert Tokenizer.tokenize("1985-W15-5T23:20:30Z") ==
             {:ok,
              [
                datetime: [
                  year: 1985,
                  week: 15,
                  day_of_week: 5,
                  hour: 23,
                  minute: 20,
                  second: 30,
                  time_shift: [sign: :positive, hour: 0]
                ]
              ]}

    assert Tokenizer.tokenize("1985-W15-5T23:20:30+04:00") ==
             {:ok,
              [
                datetime: [
                  year: 1985,
                  week: 15,
                  day_of_week: 5,
                  hour: 23,
                  minute: 20,
                  second: 30,
                  time_shift: [sign: :positive, hour: 4, minute: 0]
                ]
              ]}

    assert Tokenizer.tokenize("1985-W15-5T23:20:30+04") ==
             {:ok,
              [
                datetime: [
                  year: 1985,
                  week: 15,
                  day_of_week: 5,
                  hour: 23,
                  minute: 20,
                  second: 30,
                  time_shift: [sign: :positive, hour: 4]
                ]
              ]}

    assert Tokenizer.tokenize("19850412T1015") ==
             {:ok, [datetime: [year: 1985, month: 4, day_of_month: 12, hour: 10, minute: 15]]}

    assert Tokenizer.tokenize("1985-04-12T10:15") ==
             {:ok, [datetime: [year: 1985, month: 4, day_of_month: 12, hour: 10, minute: 15]]}

    assert Tokenizer.tokenize("1985102T1015Z") ==
             {:ok,
              [
                datetime: [
                  year: 1985,
                  day_of_year: 102,
                  hour: 10,
                  minute: 15,
                  time_shift: [sign: :positive, hour: 0]
                ]
              ]}

    assert Tokenizer.tokenize("1985-102T10:15Z")

    {:ok,
     [
       datetime: [
         year: 1985,
         day_of_year: 102,
         hour: 10,
         minute: 15,
         time_shift: [sign: :positive, hour: 0]
       ]
     ]}

    assert Tokenizer.tokenize("1985W155T1015+0400") ==
             {:ok,
              [
                datetime: [
                  year: 1985,
                  week: 15,
                  day_of_week: 5,
                  hour: 10,
                  minute: 15,
                  time_shift: [sign: :positive, hour: 4, minute: 0]
                ]
              ]}

    assert Tokenizer.tokenize("1985-W15-5T10:15+04") ==
             {:ok,
              [
                datetime: [
                  year: 1985,
                  week: 15,
                  day_of_week: 5,
                  hour: 10,
                  minute: 15,
                  time_shift: [sign: :positive, hour: 4]
                ]
              ]}
  end

  test "Date Error parsing" do
    # Extended format
    assert Tokenizer.tokenize("+0019850412")
    assert Tokenizer.tokenize("+001985-04-12")
    assert Tokenizer.tokenize("+001985-04")
    assert Tokenizer.tokenize("+001985")
    assert Tokenizer.tokenize("+00198")
    assert Tokenizer.tokenize("+0019")
  end

  test "Time Error Parsing" do
  end
end
