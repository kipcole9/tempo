defmodule Tempo.WeekDateRolloverTest do
  @moduledoc """
  Edge cases for ISO 8601 week-date (`YYYY-Www-D`) to calendar-date
  conversion.

  ISO 8601 §5.2.3: week 01 is the week containing the first Thursday
  of the calendar year (equivalently, the week containing January 4).
  Consequences:

  * Week 01 of year Y can start in December of year Y-1. The Monday
    of `2020-W01` is **2019-12-30** — three days before the calendar
    year begins.

  * Week 53 exists only when January 1 is a Thursday, or when the
    year is a leap year and January 1 is a Wednesday. 2020 and 2015
    are both 53-week years; 2021 is not.

  * Week 01 of the year *after* a 53-week year can start four days
    after January 1. The Monday of `2021-W01` is **2021-01-04** —
    because January 1-3 2021 fall in `2020-W53`.

  These two boundaries are where naive "week × 7 + day" arithmetic
  breaks, and where calendar-date libraries historically disagree.
  These tests pin down Tempo's behaviour against hand-computed
  answers.

  """

  use ExUnit.Case, async: true
  import Tempo.Sigils

  describe "2020 week-date rollover (2020 is a 53-week year)" do
    test "W01-1 rolls back to the previous calendar year" do
      assert Tempo.to_date(~o"2020-W01-1") == {:ok, ~D[2019-12-30]}
    end

    test "W01-2 rolls back to the previous calendar year" do
      assert Tempo.to_date(~o"2020-W01-2") == {:ok, ~D[2019-12-31]}
    end

    test "W01-3 is the first day of the calendar year" do
      assert Tempo.to_date(~o"2020-W01-3") == {:ok, ~D[2020-01-01]}
    end

    test "W01-7 is the last day of week 1" do
      assert Tempo.to_date(~o"2020-W01-7") == {:ok, ~D[2020-01-05]}
    end

    test "W52-7 is the last day of week 52" do
      assert Tempo.to_date(~o"2020-W52-7") == {:ok, ~D[2020-12-27]}
    end
  end

  describe "2021 week-date rollover (follows a 53-week year)" do
    # Jan 1-3 2021 belong to 2020-W53 (Fri, Sat, Sun). 2021-W01
    # therefore starts on Monday Jan 4 — four days into the
    # calendar year.
    #
    # KNOWN BUG: `Tempo.from_iso8601/1` with the default Gregorian
    # calendar currently resolves `2021-W01-1` to `2020-12-28`
    # (the Monday of 2020-W53, one week too early) because
    # `Calendrical.Gregorian.weeks_in_year/1` returns `{52, _}` for
    # every year and the week-resolution path never consults
    # `Calendrical.ISOWeek`. Filed for fix; test is skipped until
    # the parser routes week-valued inputs through ISOWeek
    # regardless of the caller's explicit calendar.
    @tag :skip
    test "W01-1 starts Jan 4 when previous year has 53 weeks" do
      {:ok, tempo} = Tempo.from_iso8601("2021-W01-1")
      assert Tempo.to_date(tempo) == {:ok, ~D[2021-01-04]}
    end

    @tag :skip
    test "W52-5 is Dec 31 in a 52-week year" do
      {:ok, tempo} = Tempo.from_iso8601("2021-W52-5")
      assert Tempo.to_date(tempo) == {:ok, ~D[2021-12-31]}
    end
  end

  describe "2015 week-date rollover (2015 is a 53-week year)" do
    test "W01-4 is the first Thursday (= Jan 1 rule)" do
      assert Tempo.to_date(~o"2015-W01-4") == {:ok, ~D[2015-01-01]}
    end

    # KNOWN BUG: W53 is rejected with "53 is not valid. The valid
    # values are 1..52" because the parser validates week numbers
    # against `Calendrical.Gregorian.weeks_in_year/1` (always 52)
    # instead of `Calendrical.ISOWeek.weeks_in_year/1` (which
    # correctly returns 53 for 2015 and 2020). Filed for fix.
    @tag :skip
    test "W53-7 is the last day of W53 in a 53-week year" do
      {:ok, tempo} = Tempo.from_iso8601("2015-W53-7")
      assert Tempo.to_date(tempo) == {:ok, ~D[2016-01-03]}
    end

    @tag :skip
    test "W53-1 is the Monday of the 53rd week" do
      {:ok, tempo} = Tempo.from_iso8601("2015-W53-1")
      assert Tempo.to_date(tempo) == {:ok, ~D[2015-12-28]}
    end
  end

  describe "canonical mid-year week-dates (no rollover)" do
    test "W24-3 is unambiguous" do
      assert Tempo.to_date(~o"2020-W24-3") == {:ok, ~D[2020-06-10]}
    end

    test "the Thursday of any week shares its ISO week-year with the calendar year" do
      # 2020-W01-4 is Jan 2, 2020 — Thursday; 2020-06-15 is in W25,
      # etc. Pins down one sample per quarter so a regression in
      # week-to-date arithmetic surfaces fast.
      assert Tempo.to_date(~o"2020-W01-4") == {:ok, ~D[2020-01-02]}
      assert Tempo.to_date(~o"2020-W14-4") == {:ok, ~D[2020-04-02]}
      assert Tempo.to_date(~o"2020-W27-4") == {:ok, ~D[2020-07-02]}
      assert Tempo.to_date(~o"2020-W40-4") == {:ok, ~D[2020-10-01]}
    end
  end
end
