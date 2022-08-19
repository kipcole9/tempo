defmodule Tempo.Iso8601.ParserTest do
  use ExUnit.Case, async: true
  alias Tempo.Iso8601.Tokenizer

  describe "iso8601/1" do
    test "parsing simple iso dates" do
      assert {:ok,
              [
                datetime: [
                  year: 2020,
                  month: 11,
                  day: 14,
                  hour: 10,
                  minute: 11,
                  second: 12
                ]
              ], "", _, _, _} = Tokenizer.iso8601("2020-11-14T10:11:12")

      assert {:ok, [date: [year: 2020, week: 28]], "", _, _, _} = Tokenizer.iso8601("2020W28")

      assert {:ok, [date: [year: 2020, day: 193]], "", _, _, _} =
               Tokenizer.iso8601("2020193")

      assert {:ok, [date: [year: 2020, month: 11]], "", _, _, _} = Tokenizer.iso8601("2020-11")
    end

    test "parsing simple iso durations" do
      assert {:ok, [duration: [day: 1]], "", _, _, _} = Tokenizer.iso8601("P1D")
      assert {:ok, [duration: [hour: 24]], "", _, _, _} = Tokenizer.iso8601("PT24H")
      assert {:ok, [duration: [day: 1, hour: 3]], "", _, _, _} = Tokenizer.iso8601("P1DT3H")
    end

    test "parsing simple iso intervals" do
      assert {:ok,
              [
                interval: [
                  date: [year: 2020, month: 11, day: 14],
                  date: [year: 2020, month: 11, day: 17]
                ]
              ], "", _, _, _} = Tokenizer.iso8601("2020-11-14/2020-11-17")

      assert {:ok,
              [
                interval: [
                  datetime: [
                    year: 2020,
                    month: 11,
                    day: 14,
                    hour: 10,
                    minute: 11,
                    second: 12
                  ],
                  date: [year: 2020, month: 11, day: 17]
                ]
              ], "", _, _, _} = Tokenizer.iso8601("2020-11-14T10:11:12/2020-11-17")

      assert {:ok,
              [
                interval: [
                  date: [year: 2020, month: 11, day: 14],
                  duration: [day: 1]
                ]
              ], "", _, _, _} = Tokenizer.iso8601("2020-11-14/P1D")

      assert {:ok,
              [
                interval: [
                  duration: [day: 1],
                  date: [year: 2020, month: 11, day: 14]
                ]
              ], "", _, _, _} = Tokenizer.iso8601("P1D/2020-11-14")
    end
  end
end
