defmodule Tempo.Parser.Interval.Test do
  use ExUnit.Case, async: true

  alias Tempo.Iso8601.Tokenizer

  test "Intervals" do
    assert Tokenizer.tokenize("2018-01-15/02-20") ==
             {:ok,
              [
                interval: [
                  date: [year: 2018, month: 1, day: 15],
                  date: [month: 2, day: 20]
                ]
              ]}

    assert Tokenizer.tokenize("2018-01-15/2018-02-20") ==
             {:ok,
              [
                interval: [
                  date: [year: 2018, month: 1, day: 15],
                  date: [year: 2018, month: 2, day: 20]
                ]
              ]}

    assert Tokenizer.tokenize("2018-01-15+05:00/2018-02-20") ==
             {:ok,
              [
                interval: [
                  date: [
                    year: 2018,
                    month: 1,
                    day: 15,
                    time_shift: [hour: 5, minute: 0]
                  ],
                  date: [year: 2018, month: 2, day: 20]
                ]
              ]}

    assert Tokenizer.tokenize("19850412T232050/19850625T103000") ==
             {:ok,
              [
                interval: [
                  datetime: [
                    year: 1985,
                    month: 4,
                    day: 12,
                    hour: 23,
                    minute: 20,
                    second: 50
                  ],
                  datetime: [
                    year: 1985,
                    month: 6,
                    day: 25,
                    hour: 10,
                    minute: 30,
                    second: 0
                  ]
                ]
              ]}

    assert Tokenizer.tokenize("1985-04-12T23:20:50/1985-06-25T10:30:00") ==
             {:ok,
              [
                interval: [
                  datetime: [
                    year: 1985,
                    month: 4,
                    day: 12,
                    hour: 23,
                    minute: 20,
                    second: 50
                  ],
                  datetime: [
                    year: 1985,
                    month: 6,
                    day: 25,
                    hour: 10,
                    minute: 30,
                    second: 0
                  ]
                ]
              ]}

    assert Tokenizer.tokenize("19850412T232050/P1Y2M15DT12H30M0S") ==
             {:ok,
              [
                interval: [
                  datetime: [
                    year: 1985,
                    month: 4,
                    day: 12,
                    hour: 23,
                    minute: 20,
                    second: 50
                  ],
                  duration: [year: 1, month: 2, day: 15, hour: 12, minute: 30, second: 0]
                ]
              ]}

    assert Tokenizer.tokenize("1985-04-12T23:20:50/P1Y2M15DT12H30M0S") ==
             {:ok,
              [
                interval: [
                  datetime: [
                    year: 1985,
                    month: 4,
                    day: 12,
                    hour: 23,
                    minute: 20,
                    second: 50
                  ],
                  duration: [year: 1, month: 2, day: 15, hour: 12, minute: 30, second: 0]
                ]
              ]}

    assert Tokenizer.tokenize("P1Y2M15DT12H30M0S/19850412T232050") ==
             {:ok,
              [
                interval: [
                  duration: [year: 1, month: 2, day: 15, hour: 12, minute: 30, second: 0],
                  datetime: [
                    year: 1985,
                    month: 4,
                    day: 12,
                    hour: 23,
                    minute: 20,
                    second: 50
                  ]
                ]
              ]}

    assert Tokenizer.tokenize("P1Y2M15DT12H30M0S/1985-04-12T23:20:50") ==
             {:ok,
              [
                interval: [
                  duration: [year: 1, month: 2, day: 15, hour: 12, minute: 30, second: 0],
                  datetime: [
                    year: 1985,
                    month: 4,
                    day: 12,
                    hour: 23,
                    minute: 20,
                    second: 50
                  ]
                ]
              ]}
  end

  test "Interval with recurrence" do
    assert Tokenizer.tokenize("R12/19850412T232050/19850625T103000") ==
             {:ok,
              [
                interval: [
                  recurrence: 12,
                  datetime: [
                    year: 1985,
                    month: 4,
                    day: 12,
                    hour: 23,
                    minute: 20,
                    second: 50
                  ],
                  datetime: [
                    year: 1985,
                    month: 6,
                    day: 25,
                    hour: 10,
                    minute: 30,
                    second: 0
                  ]
                ]
              ]}

    assert Tokenizer.tokenize("R/19850412T232050/19850625T103000") ==
             {:ok,
              [
                interval: [
                  recurrence: :infinity,
                  datetime: [
                    year: 1985,
                    month: 4,
                    day: 12,
                    hour: 23,
                    minute: 20,
                    second: 50
                  ],
                  datetime: [
                    year: 1985,
                    month: 6,
                    day: 25,
                    hour: 10,
                    minute: 30,
                    second: 0
                  ]
                ]
              ]}
  end

  test "Intervals with undefined beginning or end" do
    assert Tokenizer.tokenize("-13.787E9S4±20E6Y/..") ==
      {:ok,
       [
         interval: [
           {:date,
            [year: {-13787000000, [significant_digits: 4, margin_of_error: 20000000]}]},
           :undefined
         ]
       ]}

     assert Tokenizer.tokenize("../13.787E9S4±20E6Y") ==
       {:ok,
        [
          interval: [
            :undefined,
            {:date,
             [year: {13787000000, [significant_digits: 4, margin_of_error: 20000000]}]}
          ]
        ]}
  end

  test "Intervals where trailing century should be month" do
    assert Tokenizer.tokenize("2018-01/02") ==
             {:ok, [interval: [date: [year: 2018, month: 1], date: [month: 2]]]}
  end
end
