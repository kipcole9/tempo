defmodule Tempo.Iso8601.RoundingTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  alias Tempo.InvalidUnitError
  alias Tempo.RoundingError

  describe "rounding to year" do
    test "a date in the first half of the year rounds down" do
      assert Tempo.round(~o"2022Y3M10D", :year) == ~o"2022Y"
    end

    test "a date in the second half of the year rounds up" do
      assert Tempo.round(~o"2022Y11M21D", :year) == ~o"2023Y"
    end

    test "a year-resolution value is unchanged" do
      assert Tempo.round(~o"2022Y", :year) == ~o"2022Y"
    end
  end

  describe "rounding to month" do
    test "the first half of the month rounds down" do
      assert Tempo.round(~o"2023Y8M1D", :month) == ~o"2023Y8M"
    end

    test "the second half of the month rounds up" do
      assert Tempo.round(~o"2023Y8M20D", :month) == ~o"2023Y9M"
      assert Tempo.round(~o"2022Y11M21D", :month) == ~o"2022Y12M"
    end

    test "a month-resolution value is unchanged" do
      assert Tempo.round(~o"2022Y11M", :month) == ~o"2022Y11M"
    end
  end

  describe "rounding to hour" do
    test "the first half of the hour rounds down" do
      assert Tempo.round(~o"T10H10M", :hour) == ~o"T10H"
      assert Tempo.round(~o"T10H30M", :hour) == ~o"T10H"
    end

    test "the second half of the hour rounds up" do
      assert Tempo.round(~o"T10H50M", :hour) == ~o"T11H"
    end
  end

  describe "rounding to minute" do
    test "the first half of the minute rounds down" do
      assert Tempo.round(~o"T10H10M20S", :minute) == ~o"T10H10M"
    end

    test "the second half of the minute rounds up" do
      assert Tempo.round(~o"T10H10M50S", :minute) == ~o"T10H11M"
    end
  end

  describe "values already at the target resolution are returned unchanged" do
    test "day" do
      assert Tempo.round(~o"2022Y11M21D", :day) == ~o"2022Y11M21D"
    end

    test "hour" do
      assert Tempo.round(~o"T10H", :hour) == ~o"T10H"
    end

    test "minute" do
      assert Tempo.round(~o"T10H10M", :minute) == ~o"T10H10M"
    end

    test "second" do
      assert Tempo.round(~o"T10H10M20S", :second) == ~o"T10H10M20S"
    end
  end

  describe "errors" do
    test "rounding to a resolution finer than the value is a RoundingError" do
      assert {:error, %RoundingError{unit: :second}} = Tempo.round(~o"2022Y", :second)
    end

    test "an unknown unit is an InvalidUnitError" do
      assert {:error, %InvalidUnitError{unit: :fortnight}} =
               Tempo.round(~o"2022Y11M21D", :fortnight)
    end
  end
end
