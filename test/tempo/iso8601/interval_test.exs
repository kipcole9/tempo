defmodule Tempo.Parser.Interval.Test do
  use ExUnit.Case

  alias Tempo.Iso8601.Parser

  test "Intervals" do
    assert Parser.interval("2018-01-15/02-20") ==
      {:ok,
       [
         interval: [
           date: [year: 2018, month: 1, day_of_month: 15],
           date: [month: 2, day_of_month: 20]
         ]
       ]}

    assert Parser.interval("2018-01-15/2018-02-20") ==
      {:ok,
       [
         interval: [
           date: [year: 2018, month: 1, day_of_month: 15],
           date: [year: 2018, month: 2, day_of_month: 20]
         ]
       ]}
  end
end