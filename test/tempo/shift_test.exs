defmodule Tempo.ShiftTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  describe "Tempo.shift/2" do
    test "mixed units apply largest-to-smallest" do
      assert Tempo.shift(~o"2026-06-15", month: 1, day: -5) == ~o"2026Y7M10D"
    end

    test "negative values move the Tempo backwards" do
      assert Tempo.shift(~o"2026-06-15", day: -10) == ~o"2026Y6M5D"
    end

    test "rolls a year boundary backwards" do
      assert Tempo.shift(~o"2026-01-05", day: -10) == ~o"2025Y12M26D"
    end

    test "clamps the day-of-month after month arithmetic" do
      # Jan 31 + 1 month in a non-leap year is Feb 28, not Feb 31.
      assert Tempo.shift(~o"2026-01-31", month: 1) == ~o"2026Y2M28D"
      # Leap year gives Feb 29.
      assert Tempo.shift(~o"2024-01-31", month: 1) == ~o"2024Y2M29D"
    end

    test "time-of-day shifts work" do
      assert Tempo.shift(~o"2026-06-15T10:00:00", hour: -3) ==
               ~o"2026Y6M15DT7H0M0S"

      assert Tempo.shift(~o"2026-06-15T10:00:00", minute: 45, second: 30) ==
               ~o"2026Y6M15DT10H45M30S"
    end

    test "week is normalised to days" do
      assert Tempo.shift(~o"2026-06-15", week: 2) == ~o"2026Y6M29D"
    end

    test "empty keyword list is a no-op" do
      assert Tempo.shift(~o"2026-06-15", []) == ~o"2026Y6M15D"
    end
  end
end
