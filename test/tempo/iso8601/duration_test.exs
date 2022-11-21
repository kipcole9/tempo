defmodule Tempo.Parser.Duration.Test do
  use ExUnit.Case, async: true

  alias Tempo.Iso8601.Tokenizer

  test "Alternate duration format section 5.5.2.4" do
    assert Tokenizer.tokenize("P00020110T223355") ==
             {:ok,
              [
                duration: [
                  datetime: [
                    year: 2,
                    month: 1,
                    day: 10,
                    hour: 22,
                    minute: 33,
                    second: 55
                  ]
                ]
              ]}

    assert Tokenizer.tokenize("P0002-01-10T22:33:55") ==
             {:ok,
              [
                duration: [
                  datetime: [
                    year: 2,
                    month: 1,
                    day: 10,
                    hour: 22,
                    minute: 33,
                    second: 55
                  ]
                ]
              ]}
  end

  test "Negative durations section 4.4.1.9" do
    assert Tokenizer.tokenize("-P100D") == {:ok, [duration: [direction: :negative, day: 100]]}

    assert Tokenizer.tokenize("-P1Y3D") ==
             {:ok, [duration: [direction: :negative, year: 1, day: 3]]}
  end
end
