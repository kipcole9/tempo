defmodule Tempo.Parser.Set.Test do
  use ExUnit.Case, async: true

  alias Tempo.Iso8601.Tokenizer

  test "Set expressions: all of" do
    assert Tokenizer.tokenize("{1960,1961,1962}") ==
             {:ok, [date: [year: {:all_of, [1960, 1961, 1962]}]]}

    assert Tokenizer.tokenize("{1960,1961-12}") ==
             {:ok, [all_of: [date: [year: 1960], date: [year: 1961, month: 12]]]}

    assert Tokenizer.tokenize("{1M2S}")
    {:ok, [all_of: [datetime: [month: 1, second: 2]]]}

    assert Tokenizer.tokenize("{T1M2S,T1M3S}") ==
             {:ok,
              [
                all_of: [
                  time_of_day: [minute: 1, second: 2],
                  time_of_day: [minute: 1, second: 3]
                ]
              ]}

    assert Tokenizer.tokenize("{PT1M2S..PT1M5S}")

    {:ok,
     [
       all_of: [
         [duration: [minute: 1, second: 2], duration: [minute: 1, second: 5]]
       ]
     ]}
  end

  test "Set expressions: one of" do
    assert Tokenizer.tokenize("[1984,1986,1988]") ==
             {:ok, [one_of: [date: [year: 1984], date: [year: 1986], date: [year: 1988]]]}

    assert Tokenizer.tokenize("[1667,1760-12]") ==
             {:ok, [one_of: [date: [year: 1667], date: [year: 1760, month: 12]]]}
  end

  test "Set expressions: range" do
    assert Tokenizer.tokenize("[1900..2000]") ==
             {:ok, [one_of: [{:year, 1900..2000}]]}

    assert Tokenizer.tokenize("[..2000]") ==
             {:ok, [one_of: [{:range, [:undefined, [year: 2000]]}]]}

    assert Tokenizer.tokenize("[..1984-10]") ==
             {:ok, [one_of: [{:range, [:undefined, [year: 1984, month: 10]]}]]}

    assert Tokenizer.tokenize("[..1760-12-03]") ==
             {:ok, [one_of: [{:range, [:undefined, [year: 1760, month: 12, day: 3]]}]]}

    assert Tokenizer.tokenize("[1984..]") ==
             {:ok, [one_of: [{:range, [[year: 1984], :undefined]}]]}

    assert Tokenizer.tokenize("[1760-12..]") ==
             {:ok, [one_of: [{:range, [[year: 1760, month: 12], :undefined]}]]}

    assert Tokenizer.tokenize("[1984-10-10..]") ==
             {:ok, [one_of: [{:range, [[year: 1984, month: 10, day: 10], :undefined]}]]}

    assert Tokenizer.tokenize("[1670..1673]") ==
             {:ok, [one_of: [{:year, 1670..1673}]]}

    assert Tokenizer.tokenize("[1984-10-10..1984-11-01]") ==
             {
               :ok,
               [
                 one_of: [
                   {:range,
                    [
                      date: [year: 1984, month: 10, day: 10],
                      date: [year: 1984, month: 11, day: 1]
                    ]}
                 ]
               ]
             }

    assert Tokenizer.tokenize("{..1983-12-31,1984-10-10..1984-11-01,1984-11-05..}") ==
             {
               :ok,
               [
                 all_of: [
                   {:range, [:undefined, [year: 1983, month: 12, day: 31]]},
                   {:range,
                    [
                      date: [year: 1984, month: 10, day: 10],
                      date: [year: 1984, month: 11, day: 1]
                    ]},
                   {:range, [[year: 1984, month: 11, day: 5], :undefined]}
                 ]
               ]
             }

    assert Tokenizer.tokenize("[1760-01,1760-02,1760-12..]") ==
             {
               :ok,
               [
                 one_of: [
                   {:date, [year: 1760, month: 1]},
                   {:date, [year: 1760, month: 2]},
                   {:range, [[year: 1760, month: 12], :undefined]}
                 ]
               ]
             }

    assert Tokenizer.tokenize("{1M2S..1M5S}") ==
             {:ok,
              [
                all_of: [
                  {:range,
                   [time_of_day: [minute: 1, second: 2], time_of_day: [minute: 1, second: 5]]}
                ]
              ]}
  end

  test "Group sets" do
    assert Tokenizer.tokenize("2018-{1,3,5}G2MU") ==
             {:ok, [date: [year: 2018, group: [all_of: [1, 3, 5], month: 2]]]}

    assert Tokenizer.tokenize("2018-[2,4]G3MU") ==
             {:ok, [date: [year: 2018, group: [one_of: [2, 4], month: 3]]]}
  end
end
