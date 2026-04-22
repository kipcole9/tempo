defmodule Tempo.CalendarAccessorsTest do
  use ExUnit.Case, async: true

  import Tempo.Sigil

  describe "Tempo.day_of_week/1,2" do
    test "2026-06-15 is a Monday (default ordering)" do
      assert Tempo.day_of_week(~o"2026-06-15") == 1
    end

    test "2026-06-14 is a Sunday (default ordering returns 7)" do
      assert Tempo.day_of_week(~o"2026-06-14") == 7
    end

    test ":sunday starting_on renumbers" do
      # Monday under :sunday starting becomes 2.
      assert Tempo.day_of_week(~o"2026-06-15", :sunday) == 2
      # Sunday under :sunday starting becomes 1.
      assert Tempo.day_of_week(~o"2026-06-14", :sunday) == 1
    end

    test "raises when the Tempo has no year" do
      assert_raise ArgumentError, ~r/requires a year component/, fn ->
        Tempo.day_of_week(~o"6M15D")
      end
    end
  end

  describe "Tempo.day_of_year/1" do
    test "first day of year is 1" do
      assert Tempo.day_of_year(~o"2026-01-01") == 1
    end

    test "last day of a non-leap year is 365" do
      assert Tempo.day_of_year(~o"2025-12-31") == 365
    end

    test "last day of a leap year is 366" do
      assert Tempo.day_of_year(~o"2024-12-31") == 366
    end
  end

  describe "Tempo.quarter_of_year/1" do
    test "January is Q1" do
      assert Tempo.quarter_of_year(~o"2026-01-15") == 1
    end

    test "April is Q2" do
      assert Tempo.quarter_of_year(~o"2026-04-01") == 2
    end

    test "July is Q3" do
      assert Tempo.quarter_of_year(~o"2026-07-31") == 3
    end

    test "December is Q4" do
      assert Tempo.quarter_of_year(~o"2026-12-31") == 4
    end

    test "works on month-resolution Tempo (defaults day to 1)" do
      assert Tempo.quarter_of_year(~o"2026-11") == 4
    end
  end

  describe "Tempo.leap_year?/1" do
    test "2024 is a Gregorian leap year" do
      assert Tempo.leap_year?(~o"2024") == true
    end

    test "2025 is not" do
      assert Tempo.leap_year?(~o"2025") == false
    end

    test "2000 is a leap year (divisible by 400)" do
      assert Tempo.leap_year?(~o"2000") == true
    end

    test "1900 is not (divisible by 100 but not 400)" do
      assert Tempo.leap_year?(~o"1900") == false
    end

    test "raises when the Tempo has no year" do
      assert_raise ArgumentError, ~r/requires a year component/, fn ->
        Tempo.leap_year?(%Tempo{time: [month: 2]})
      end
    end
  end

  describe "Tempo.days_in_month/1" do
    test "Feb in a leap year has 29 days" do
      assert Tempo.days_in_month(~o"2024-02") == 29
    end

    test "Feb in a non-leap year has 28 days" do
      assert Tempo.days_in_month(~o"2025-02") == 28
    end

    test "April has 30 days" do
      assert Tempo.days_in_month(~o"2026-04") == 30
    end

    test "July has 31 days" do
      assert Tempo.days_in_month(~o"2026-07") == 31
    end

    test "accepts a day-resolution Tempo" do
      assert Tempo.days_in_month(~o"2026-04-15") == 30
    end

    test "raises when there's no month" do
      assert_raise ArgumentError, ~r/requires a month component/, fn ->
        Tempo.days_in_month(~o"2026")
      end
    end
  end
end
