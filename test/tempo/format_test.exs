defmodule Tempo.FormatTest do
  use ExUnit.Case, async: true

  import Tempo.Sigils

  doctest Tempo, only: [to_string: 2]

  # The CLDR range separator is a thin-space + en-dash + thin-space.
  @en_dash_sep "\u2009\u2013\u2009"

  describe "Tempo.to_string/1 — Rule B expansion" do
    test "year resolution expands to Jan–Dec (closed interval)" do
      assert Tempo.to_string(~o"2026") == "Jan#{@en_dash_sep}Dec 2026"
    end

    test "year :long uses full month names" do
      assert Tempo.to_string(~o"2026", format: :long) ==
               "January#{@en_dash_sep}December 2026"
    end

    test "month resolution expands to day 1–N" do
      assert Tempo.to_string(~o"2026-06") == "Jun 1#{@en_dash_sep}30, 2026"
    end

    test "month length follows the calendar (29 in a leap Feb)" do
      assert Tempo.to_string(~o"2024-02") == "Feb 1#{@en_dash_sep}29, 2024"
    end

    test "month length in a common-year Feb is 28" do
      assert Tempo.to_string(~o"2025-02") == "Feb 1#{@en_dash_sep}28, 2025"
    end

    test "day resolution collapses to a single value" do
      assert Tempo.to_string(~o"2026-06-15") == "Jun 15, 2026"
    end

    test "day :long uses full month name" do
      assert Tempo.to_string(~o"2026-06-15", format: :long) == "June 15, 2026"
    end

    test "second resolution collapses to a single datetime" do
      string = Tempo.to_string(~o"2026-06-15T14:30:00")
      assert string =~ "Jun 15, 2026"
      assert string =~ "2:30"
    end
  end

  describe "Tempo.to_string/2 — locale" do
    test "en-GB switches to DMY ordering on day values" do
      assert Tempo.to_string(~o"2026-06-15", format: :long, locale: "en-GB") ==
               "15 June 2026"
    end

    test "de renders German month names" do
      assert Tempo.to_string(~o"2026-06-15", format: :long, locale: "de") ==
               "15. Juni 2026"
    end

    test "year expansion honours the locale" do
      assert Tempo.to_string(~o"2026", locale: "de", format: :long) ==
               "Januar\u2013Dezember 2026"
    end

    test "fr month expansion" do
      assert Tempo.to_string(~o"2026-06", locale: "fr") =~ "juin"
    end
  end

  describe "Tempo.to_string/2 on Tempo.Interval — same rule" do
    test "day-resolution interval collapses to a single day when from == to − 1 day" do
      {:ok, iv} = Tempo.to_interval(~o"2026-06-15")
      assert Tempo.to_string(iv) == "Jun 15, 2026"
    end

    test "month-resolution interval renders the day range of the month" do
      {:ok, iv} = Tempo.to_interval(~o"2026-06")
      assert Tempo.to_string(iv) == "Jun 1#{@en_dash_sep}30, 2026"
    end

    test "year-resolution interval renders Jan–Dec" do
      {:ok, iv} = Tempo.to_interval(~o"2026")
      assert Tempo.to_string(iv) == "Jan#{@en_dash_sep}Dec 2026"
    end

    test "multi-year range — union preserves members; coalesce for a single span" do
      # Member-preserving union keeps both years distinct; the
      # IntervalSet renders them as two comma-separated spans. For
      # the "Jan 2022 – Dec 2023" single-span rendering, coalesce
      # explicitly first.
      {:ok, yr_iv} = Tempo.union(~o"2022", ~o"2023")
      coalesced = Tempo.IntervalSet.coalesce(yr_iv)

      assert Tempo.to_string(coalesced) == "Jan 2022#{@en_dash_sep}Dec 2023"
    end

    test "Tempo.to_string(tempo) matches Tempo.to_string(to_interval(tempo)) — year" do
      tempo = ~o"2026"
      {:ok, iv} = Tempo.to_interval(tempo)
      assert Tempo.to_string(tempo) == Tempo.to_string(iv)
    end

    test "Tempo.to_string(tempo) matches Tempo.to_string(to_interval(tempo)) — month" do
      tempo = ~o"2026-06"
      {:ok, iv} = Tempo.to_interval(tempo)
      assert Tempo.to_string(tempo) == Tempo.to_string(iv)
    end

    test "Tempo.to_string(tempo) matches Tempo.to_string(to_interval(tempo)) — day" do
      # The materialised interval has T00H endpoints; the
      # midnight-to-midnight trunc in Tempo.Format ensures the
      # display resolution matches the source Tempo's.
      tempo = ~o"2026-06-15"
      {:ok, iv} = Tempo.to_interval(tempo)
      assert Tempo.to_string(tempo) == Tempo.to_string(iv)
    end

    test "explicit hour-level interval preserves hour display" do
      iv = %Tempo.Interval{from: ~o"2026-06-15T10", to: ~o"2026-06-15T18"}
      string = Tempo.to_string(iv)
      assert string =~ "Jun 15, 2026"
      assert string =~ "10"
      assert string =~ "5"
    end

    test "month :long uses the day-of-week-and-month format" do
      {:ok, iv} = Tempo.to_interval(~o"2026-06")
      string = Tempo.to_string(iv, format: :long)
      # CLDR :long for date-style intervals includes the abbreviated
      # weekday + abbreviated month, e.g. "Mon, Jun 1 – Tue, Jun 30, 2026".
      assert string =~ "Mon"
      assert string =~ "Tue"
      assert string =~ "Jun"
      assert string =~ "30, 2026"
    end
  end

  describe "Tempo.to_string/2 on Tempo.IntervalSet" do
    test "joins members with ', '" do
      {:ok, set} = Tempo.union(~o"2022", ~o"2024")

      assert Tempo.to_string(set) ==
               "Jan#{@en_dash_sep}Dec 2022, Jan#{@en_dash_sep}Dec 2024"
    end
  end

  describe "String.Chars protocol" do
    test "Tempo interpolates into a string" do
      assert "Date: #{~o"2026-06-15"}" == "Date: Jun 15, 2026"
    end

    test "Year interpolation expands to Jan–Dec" do
      assert "#{~o"2026"}" == "Jan#{@en_dash_sep}Dec 2026"
    end

    test "Tempo.Interval interpolates" do
      {:ok, iv} = Tempo.to_interval(~o"2026-06")
      assert "#{iv}" == "Jun 1#{@en_dash_sep}30, 2026"
    end

    test "Tempo.IntervalSet interpolates" do
      {:ok, set} = Tempo.union(~o"2022", ~o"2024")
      assert "#{set}" =~ "2022"
      assert "#{set}" =~ "2024"
    end

    test "to_string/1 on Tempo equals Tempo.to_string/1" do
      tempo = ~o"2026-06-15"
      assert to_string(tempo) == Tempo.to_string(tempo)
    end
  end

  describe "Tempo.to_string/2 on Tempo.Duration — Localize-backed" do
    test "year + month duration" do
      assert Tempo.to_string(~o"P1Y6M") == "1 year and 6 months"
    end

    test "day + hour duration" do
      assert Tempo.to_string(~o"P3DT2H") == "3 days and 2 hours"
    end

    test "weeks normalise to days" do
      assert Tempo.to_string(~o"P2W3D") == "17 days"
    end

    test "zero duration renders as `0 seconds`" do
      assert Tempo.to_string(~o"P0D") == "0 seconds"
    end

    test ":style short abbreviates" do
      assert Tempo.to_string(~o"P3DT2H", style: :short) == "3 days and 2 hr"
    end

    test "locale honoured" do
      assert Tempo.to_string(~o"P1Y6M", locale: :de) == "1 Jahr und 6 Monate"
    end

    test "String.Chars interpolates duration" do
      assert "Elapsed: #{~o"P1Y6M"}" == "Elapsed: 1 year and 6 months"
    end
  end

  describe "Inspect remains unchanged" do
    test "inspect returns the sigil form, not the localized form" do
      assert inspect(~o"2026-06-15") == ~s|~o"2026Y6M15D"|
      assert inspect(~o"2026") == ~s|~o"2026Y"|
    end
  end
end
