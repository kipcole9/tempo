defmodule Tempo.Parser.Group.Test do
  use ExUnit.Case, async: true

  alias Tempo.Iso8601.Parser

  test "Group formation section 5" do
    assert Parser.date("2018-2G3MU") ==
      {:ok, [date: [year: 2018, month: {:group, [nth: 2, month: 3]}]]}

    # Note that in secrion 5.4 Example 2 is shows
    # 2018Y9M2DT3GT8HU0H30M (Note the added 0H). The example
    # notes that the 0H *may* be omitted.  In this implementation
    # it *must* be omitted since the group occupies the `hour`
    # slot

    assert Parser.parse("2018Y9M2DT3GT8HU30M") ==
      {:ok,
       [
         datetime: [
           year: 2018,
           month: 9,
           day_of_month: 2,
           hour: {:group, [nth: 3, hour: 8]},
           minute: 30
         ]
       ]}

    assert Parser.parse("2018-02-2G14DU") ==
      {:ok, [date: [year: 2018, month: 2, day_of_month: {:group, [nth: 2, day: 14]}]]}

    assert Parser.parse("2018-03-3G10DU") ==
      {:ok, [date: [year: 2018, month: 3, day_of_month: {:group, [nth: 3, day: 10]}]]}

    assert Parser.time("16:1GT15MU") ==
      {:ok, [time_of_day: [hour: 16, minute: {:group, [nth: 1, minute: 15]}]]}

    assert Parser.parse("2018-1G6MU") ==
      {:ok, [date: [year: 2018, month: {:group, [nth: 1, month: 6]}]]}

    assert Parser.parse("2018Y1G6MU") ==
      {:ok, [date: [year: 2018, month: {:group, [nth: 1, month: 6]}]]}

    assert Parser.parse("1933Y1G80DU") ==
      {:ok, [date: [year: 1933, month: {:group, [nth: 1, day: 80]}]]}

    assert Parser.parse("1543Y1M3G5DU") ==
      {:ok, [date: [year: 1543, month: 1, day_of_month: {:group, [nth: 3, day: 5]}]]}

    assert Parser.time("6GT2HU") ==
      {:ok, [time_of_day: [hour: {:group, [nth: 6, hour: 2]}]]}

    assert Parser.parse("110Y2G3MU") ==
      {:ok, [date: [year: 110, month: {:group, [nth: 2, month: 3]}]]}

    assert Parser.parse("2018Y3G60DU6D") ==
      {:ok, [date: [year: 2018, month: {:group, [nth: 3, day: 60]}, day_of_month: 6]]}

    assert Parser.parse("2018Y20GT12HU3H") ==
      {:ok, [datetime: [year: 2018, month: {:group, [nth: 20, hour: 12]}, hour: 3]]}

    assert Parser.parse("2018Y1G2MU30D") ==
      {:ok,
       [date: [year: 2018, month: {:group, [nth: 1, month: 2]}, day_of_month: 30]]}

    assert Parser.parse("2018Y1G2MU60D") ==
      {:ok,
       [date: [year: 2018, month: {:group, [nth: 1, month: 2]}, day_of_month: 60]]}

    assert Parser.parse("2018Y9M4G8DU") ==
      {:ok, [date: [year: 2018, month: 9, day_of_month: {:group, [nth: 4, day: 8]}]]}

    assert Parser.parse("2018Y9M4G8DU") ==
      {:ok, [date: [year: 2018, month: 9, day_of_month: {:group, [nth: 4, day: 8]}]]}
  end

  test "Group formation special tests" do
    assert Parser.date("5G10DU") ==
      {:ok, [date: [year: {:group, [nth: 5, day: 10]}]]}

    assert Parser.date("1G2DT6HU") ==
      {:ok, [date: [year: {:group, [nth: 1, day: 2, hour: 6]}]]}

    assert Parser.parse("2018Y4G60DU6D") ==
      {:ok, [date: [year: 2018, month: {:group, [nth: 4, day: 60]}, day_of_month: 6]]}
  end
end