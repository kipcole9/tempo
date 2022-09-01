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

  test "Enumeration with negative range and cascading ranges" do
    assert Enum.map(~o"2022Y{1,2}M{1..-28}D", &(&1)) ==
    [
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
        time: [year: 2022, month: 1, day: 3],
        shift: nil,
        calendar: Cldr.Calendar.Gregorian
      },
      %Tempo{
        time: [year: 2022, month: 1, day: 4],
        shift: nil,
        calendar: Cldr.Calendar.Gregorian
      },
      %Tempo{
        time: [year: 2022, month: 2, day: 1],
        shift: nil,
        calendar: Cldr.Calendar.Gregorian
      }
    ]
  end

  test "Implicit Enumeration" do
    assert Enum.map(~o"2022", &(&1)) ==
      [~o"2022Y1M", ~o"2022Y2M", ~o"2022Y3M", ~o"2022Y4M", ~o"2022Y5M", ~o"2022Y6M",
       ~o"2022Y7M", ~o"2022Y8M", ~o"2022Y9M", ~o"2022Y10M", ~o"2022Y11M",
       ~o"2022Y12M"]

    assert Enum.map(~o"2022Y2M", &(&1)) ==
      [~o"2022Y2M1D", ~o"2022Y2M2D", ~o"2022Y2M3D", ~o"2022Y2M4D", ~o"2022Y2M5D",
       ~o"2022Y2M6D", ~o"2022Y2M7D", ~o"2022Y2M8D", ~o"2022Y2M9D", ~o"2022Y2M10D",
       ~o"2022Y2M11D", ~o"2022Y2M12D", ~o"2022Y2M13D", ~o"2022Y2M14D", ~o"2022Y2M15D",
       ~o"2022Y2M16D", ~o"2022Y2M17D", ~o"2022Y2M18D", ~o"2022Y2M19D", ~o"2022Y2M20D",
       ~o"2022Y2M21D", ~o"2022Y2M22D", ~o"2022Y2M23D", ~o"2022Y2M24D", ~o"2022Y2M25D",
       ~o"2022Y2M26D", ~o"2022Y2M27D", ~o"2022Y2M28D"]

    assert Enum.map(~o"2020Y2M", &(&1)) ==
      [~o"2020Y2M1D", ~o"2020Y2M2D", ~o"2020Y2M3D", ~o"2020Y2M4D", ~o"2020Y2M5D",
       ~o"2020Y2M6D", ~o"2020Y2M7D", ~o"2020Y2M8D", ~o"2020Y2M9D", ~o"2020Y2M10D",
       ~o"2020Y2M11D", ~o"2020Y2M12D", ~o"2020Y2M13D", ~o"2020Y2M14D", ~o"2020Y2M15D",
       ~o"2020Y2M16D", ~o"2020Y2M17D", ~o"2020Y2M18D", ~o"2020Y2M19D", ~o"2020Y2M20D",
       ~o"2020Y2M21D", ~o"2020Y2M22D", ~o"2020Y2M23D", ~o"2020Y2M24D", ~o"2020Y2M25D",
       ~o"2020Y2M26D", ~o"2020Y2M27D", ~o"2020Y2M28D", ~o"2020Y2M29D"]
  end

  test "when a set has a range followed by a range" do
    assert Enum.to_list(~o"{1..2,5..6}Y") == [~o"1Y", ~o"2Y", ~o"5Y", ~o"6Y"]
    assert Enum.to_list(~o"{1..2,4,6..7}Y") == [~o"1Y", ~o"2Y", ~o"4Y", ~o"6Y", ~o"7Y"]
  end
end