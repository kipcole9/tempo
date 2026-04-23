defmodule Tempo.BoundaryHelpersTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  describe "Tempo.beginning_of_day/1" do
    test "pulls a datetime back to 00:00:00 on the same day" do
      assert Tempo.beginning_of_day(~o"2026-06-15T14:30:45") ==
               ~o"2026Y6M15DT0H0M0S"
    end

    test "accepts a day-resolution Tempo" do
      assert Tempo.beginning_of_day(~o"2026-06-15") == ~o"2026Y6M15DT0H0M0S"
    end
  end

  describe "Tempo.end_of_day/1" do
    test "returns the exclusive endpoint (00:00:00 the following day)" do
      assert Tempo.end_of_day(~o"2026-06-15T14:30:00") == ~o"2026Y6M16DT0H0M0S"
    end

    test "rolls a month boundary" do
      assert Tempo.end_of_day(~o"2026-06-30") == ~o"2026Y7M1DT0H0M0S"
    end

    test "rolls a year boundary" do
      assert Tempo.end_of_day(~o"2026-12-31") == ~o"2027Y1M1DT0H0M0S"
    end

    test "beginning_of_day and end_of_day frame a 24-hour window on typical days" do
      start = Tempo.beginning_of_day(~o"2026-06-15")
      stop = Tempo.end_of_day(~o"2026-06-15")

      # beginning .. end is exactly one day (86_400 seconds) when no DST
      # transition intervenes on a floating value.
      iv = %Tempo.Interval{from: start, to: stop}
      assert Tempo.Interval.duration(iv) == ~o"PT86400S"
    end
  end

  describe "Tempo.beginning_of_month/1" do
    test "pulls any day in the month back to the 1st at 00:00:00" do
      assert Tempo.beginning_of_month(~o"2026-06-15T14:30:00") ==
               ~o"2026Y6M1DT0H0M0S"
    end

    test "accepts a month-resolution Tempo" do
      assert Tempo.beginning_of_month(~o"2026-06") == ~o"2026Y6M1DT0H0M0S"
    end
  end

  describe "Tempo.end_of_month/1" do
    test "returns the first of the following month at 00:00:00" do
      assert Tempo.end_of_month(~o"2026-06-15") == ~o"2026Y7M1DT0H0M0S"
    end

    test "rolls a year boundary" do
      assert Tempo.end_of_month(~o"2026-12") == ~o"2027Y1M1DT0H0M0S"
    end

    test "handles February in leap and non-leap years the same way" do
      assert Tempo.end_of_month(~o"2024-02-10") == ~o"2024Y3M1DT0H0M0S"
      assert Tempo.end_of_month(~o"2025-02-10") == ~o"2025Y3M1DT0H0M0S"
    end
  end
end
