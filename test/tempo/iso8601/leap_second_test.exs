defmodule Tempo.Iso8601.LeapSecond.Test do
  use ExUnit.Case, async: true

  # ISO 8601 permits `second = 60` as a positive leap second. Validation
  # constrains the leap second to 23:59 UTC at the end of 30 June or
  # 31 December — AND to a specific historical date on which IERS
  # actually announced a leap second insertion.

  describe "valid leap seconds" do
    test "end of December UTC — 2016 (most recent)" do
      assert {:ok, tempo} = Tempo.from_iso8601("2016-12-31T23:59:60Z")
      assert Keyword.get(tempo.time, :second) == 60
    end

    test "end of June UTC — 2015 (real insertion)" do
      assert {:ok, _} = Tempo.from_iso8601("2015-06-30T23:59:60Z")
    end

    test "first-ever leap second — 1972-06-30" do
      assert {:ok, _} = Tempo.from_iso8601("1972-06-30T23:59:60Z")
    end

    test "end of day without offset (local time)" do
      assert {:ok, _} = Tempo.from_iso8601("2016-12-31T23:59:60")
    end

    test "time-only value (no calendar date) at 23:59" do
      # No year/month/day means no historical check applies.
      assert {:ok, _} = Tempo.from_iso8601("T23:59:60")
    end
  end

  describe "invalid leap seconds — historical check" do
    # Since IERS has only announced 27 leap seconds, ISO 8601 `:60`
    # on any other June 30 or December 31 is semantically invalid.

    test "rejected on a June 30 with no announced leap second" do
      assert {:error, msg} = Tempo.from_iso8601("2017-06-30T23:59:60Z")
      assert msg =~ "No leap second has been inserted on 2017-06-30"
    end

    test "rejected on a December 31 with no announced leap second" do
      assert {:error, msg} = Tempo.from_iso8601("2026-12-31T23:59:60Z")
      assert msg =~ "No leap second has been inserted on 2026-12-31"
    end

    test "rejected on 2016-06-30 — only 2016-12-31 had a leap second" do
      assert {:error, msg} = Tempo.from_iso8601("2016-06-30T23:59:60Z")
      assert msg =~ "No leap second has been inserted on 2016-06-30"
    end

    test "the error message points to Tempo.LeapSeconds.dates/0" do
      {:error, msg} = Tempo.from_iso8601("2020-12-31T23:59:60Z")
      assert msg =~ "Tempo.LeapSeconds.dates/0"
    end
  end

  describe "invalid leap seconds — structural" do
    test "rejected mid-day" do
      assert {:error, msg} = Tempo.from_iso8601("2022-05-15T10:30:60")
      assert msg =~ "leap second"
    end

    test "rejected when minute is not 59" do
      assert {:error, msg} = Tempo.from_iso8601("2016-12-31T23:58:60Z")
      assert msg =~ "leap second"
    end

    test "rejected on dates other than 30 June or 31 December" do
      assert {:error, msg} = Tempo.from_iso8601("2016-05-31T23:59:60Z")
      assert msg =~ "leap second"
    end

    test "rejected with a non-zero time-zone offset" do
      assert {:error, msg} = Tempo.from_iso8601("2016-12-31T23:59:60+05:30")
      assert msg =~ "leap second"
    end
  end

  describe "non-leap-second seconds" do
    test "0..59 all accepted" do
      for s <- [0, 1, 29, 30, 58, 59] do
        assert {:ok, _} = Tempo.from_iso8601("2022-05-15T10:30:#{pad(s)}")
      end
    end

    test "61 rejected" do
      assert {:error, _} = Tempo.from_iso8601("2016-12-31T23:59:61Z")
    end

    test "negative -1 wraps to 59 (not 60)" do
      assert {:ok, tempo} = Tempo.from_iso8601("T-1S")
      assert Keyword.get(tempo.time, :second) == 59
    end
  end

  defp pad(n) when n < 10, do: "0#{n}"
  defp pad(n), do: "#{n}"
end
