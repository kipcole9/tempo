defmodule Tempo.Enumeration.Test do
  use ExUnit.Case, async: true
  import Tempo.Sigil

  test "Enumeration of basic double" do
    assert Enum.map(~o"2022Y{1,2}M{1..2}D", &(&1)) == [
      %Tempo{
        time: [year: 2022, month: 1, day: 1],
        shift: nil,
        calendar: Cldr.Calendar.Gregorian
      },
      %Tempo{
        time: [year: 2022, month: 1, day: 2],
        shift: nil,
        calendar: Cldr.Calendar.Gregorian
      },
      %Tempo{
        time: [year: 2022, month: 2, day: 1],
        shift: nil,
        calendar: Cldr.Calendar.Gregorian
      },
      %Tempo{
        time: [year: 2022, month: 2, day: 2],
        shift: nil,
        calendar: Cldr.Calendar.Gregorian
      }
    ]
  end

  test "Enumeration of basic triple" do
    assert Enum.map(~o"{2021,2022}Y{1,2}M{1..2}D", &(&1)) == [
      %Tempo{
        time: [year: 2021, month: 1, day: 1],
        shift: nil,
        calendar: Cldr.Calendar.Gregorian
      },
      %Tempo{
        time: [year: 2021, month: 1, day: 2],
        shift: nil,
        calendar: Cldr.Calendar.Gregorian
      },
      %Tempo{
        time: [year: 2021, month: 2, day: 1],
        shift: nil,
        calendar: Cldr.Calendar.Gregorian
      },
      %Tempo{
        time: [year: 2021, month: 2, day: 2],
        shift: nil,
        calendar: Cldr.Calendar.Gregorian
      },
      %Tempo{
        time: [year: 2022, month: 1, day: 1],
        shift: nil,
        calendar: Cldr.Calendar.Gregorian
      },
      %Tempo{
        time: [year: 2022, month: 1, day: 2],
        shift: nil,
        calendar: Cldr.Calendar.Gregorian
      },
      %Tempo{
        time: [year: 2022, month: 2, day: 1],
        shift: nil,
        calendar: Cldr.Calendar.Gregorian
      },
      %Tempo{
        time: [year: 2022, month: 2, day: 2],
        shift: nil,
        calendar: Cldr.Calendar.Gregorian
      }
    ]
  end

  test "Enumeration with a constant after a range" do
    assert Enum.map(~o"{1,2}M23D", &(&1)) == [
      %Tempo{
        time: [month: 1, day: 23],
        shift: nil,
        calendar: Cldr.Calendar.Gregorian
      },
      %Tempo{
        time: [month: 2, day: 23],
        shift: nil,
        calendar: Cldr.Calendar.Gregorian
      }
    ]
  end

  test "Enumeration with a range, then constant, then range" do
    assert Enum.map(~o"{1,2}M23DT{3,4}H", &(&1)) ==
    [
      %Tempo{
        time: [month: 1, day: 23, hour: 3],
        shift: nil,
        calendar: Cldr.Calendar.Gregorian
      },
      %Tempo{
        time: [month: 1, day: 23, hour: 4],
        shift: nil,
        calendar: Cldr.Calendar.Gregorian
      },
      %Tempo{
        time: [month: 2, day: 23, hour: 3],
        shift: nil,
        calendar: Cldr.Calendar.Gregorian
      },
      %Tempo{
        time: [month: 2, day: 23, hour: 4],
        shift: nil,
        calendar: Cldr.Calendar.Gregorian
      }
    ]
  end
end