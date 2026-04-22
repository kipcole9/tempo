defmodule Tempo.ToInterval.Test do
  use ExUnit.Case, async: true

  # Tests for `Tempo.to_interval/1` — implicit-to-explicit interval
  # materialisation. Covers the table of input-resolution rules from
  # `plans/implicit-to-explicit-interval-conversion.md` plus mask
  # widening, metadata propagation, and iteration parity.

  describe "concrete date resolutions" do
    test "year only → year-month endpoints" do
      {:ok, tempo} = Tempo.from_iso8601("2026")
      {:ok, interval} = Tempo.to_interval(tempo)
      assert interval.from.time == [year: 2026, month: 1]
      assert interval.to.time == [year: 2027, month: 1]
    end

    test "year-month → year-month-day endpoints" do
      {:ok, tempo} = Tempo.from_iso8601("2026-01")
      {:ok, interval} = Tempo.to_interval(tempo)
      assert interval.from.time == [year: 2026, month: 1, day: 1]
      assert interval.to.time == [year: 2026, month: 2, day: 1]
    end

    test "year-month-day → year-month-day-hour endpoints" do
      {:ok, tempo} = Tempo.from_iso8601("2026-01-15")
      {:ok, interval} = Tempo.to_interval(tempo)
      assert interval.from.time == [year: 2026, month: 1, day: 15, hour: 0]
      assert interval.to.time == [year: 2026, month: 1, day: 16, hour: 0]
    end

    test "month carry to next year" do
      {:ok, tempo} = Tempo.from_iso8601("2026-12")
      {:ok, interval} = Tempo.to_interval(tempo)
      assert interval.to.time == [year: 2027, month: 1, day: 1]
    end

    test "day carry across leap year Feb → Mar" do
      {:ok, tempo} = Tempo.from_iso8601("2024-02-29")
      {:ok, interval} = Tempo.to_interval(tempo)
      assert interval.from.time == [year: 2024, month: 2, day: 29, hour: 0]
      assert interval.to.time == [year: 2024, month: 3, day: 1, hour: 0]
    end
  end

  describe "concrete datetime resolutions" do
    test "hour → hour-minute endpoints" do
      {:ok, tempo} = Tempo.from_iso8601("2026-01-15T10")
      {:ok, interval} = Tempo.to_interval(tempo)
      assert interval.from.time == [year: 2026, month: 1, day: 15, hour: 10, minute: 0]
      assert interval.to.time == [year: 2026, month: 1, day: 15, hour: 11, minute: 0]
    end

    test "minute → minute-second endpoints" do
      {:ok, tempo} = Tempo.from_iso8601("2026-01-15T10:30")
      {:ok, interval} = Tempo.to_interval(tempo)

      assert interval.from.time == [
               year: 2026,
               month: 1,
               day: 15,
               hour: 10,
               minute: 30,
               second: 0
             ]

      assert interval.to.time == [
               year: 2026,
               month: 1,
               day: 15,
               hour: 10,
               minute: 31,
               second: 0
             ]
    end

    test "second — no finer unit, refuses with a clear error" do
      {:ok, tempo} = Tempo.from_iso8601("2026-01-15T10:30:00")

      assert {:error, %Tempo.MaterialisationError{reason: :finest_resolution} = e} =
               Tempo.to_interval(tempo)

      assert Exception.message(e) =~ "finest resolution"
    end
  end

  describe "mask values (widest enclosing bound)" do
    test "positive year mask `156X` → decade span" do
      {:ok, tempo} = Tempo.from_iso8601("156X")
      {:ok, interval} = Tempo.to_interval(tempo)
      assert interval.from.time == [year: 1560]
      assert interval.to.time == [year: 1570]
    end

    test "millennium mask `1XXX` → millennium span" do
      {:ok, tempo} = Tempo.from_iso8601("1XXX")
      {:ok, interval} = Tempo.to_interval(tempo)
      assert interval.from.time == [year: 1000]
      assert interval.to.time == [year: 2000]
    end

    test "fully-unspecified year `XXXX` → 0..10000 span" do
      {:ok, tempo} = Tempo.from_iso8601("XXXX")
      {:ok, interval} = Tempo.to_interval(tempo)
      assert interval.from.time == [year: 0]
      assert interval.to.time == [year: 10000]
    end

    test "negative year mask `-1XXX` → signed span (most-negative first)" do
      {:ok, tempo} = Tempo.from_iso8601("-1XXX")
      {:ok, interval} = Tempo.to_interval(tempo)
      # Magnitude range 1000..1999 → signed values -1999..-1000.
      # Half-open upper = -1000 + 1 = -999.
      assert interval.from.time == [year: -1999]
      assert interval.to.time == [year: -999]
    end

    test "month-day masked widens to year resolution" do
      {:ok, tempo} = Tempo.from_iso8601("1985-XX-XX")
      {:ok, interval} = Tempo.to_interval(tempo)
      # First masked unit is month; widen to year prefix.
      assert interval.from.time == [year: 1985]
      assert interval.to.time == [year: 1986]
    end

    test "day-only masked widens to month resolution" do
      {:ok, tempo} = Tempo.from_iso8601("1985-06-XX")
      {:ok, interval} = Tempo.to_interval(tempo)
      assert interval.from.time == [year: 1985, month: 6]
      assert interval.to.time == [year: 1985, month: 7]
    end

    test "non-contiguous `1985-XX-15` expands to 12 day-intervals" do
      # Day is specified but month is masked — the covered moments
      # are 12 disjoint days (the 15th of each month). `to_interval/1`
      # substitutes the mask with the valid month values and
      # materialises each as a day-resolution interval.
      {:ok, tempo} = Tempo.from_iso8601("1985-XX-15")
      {:ok, %Tempo.IntervalSet{intervals: intervals}} = Tempo.to_interval(tempo)
      assert length(intervals) == 12

      assert Enum.map(intervals, & &1.from.time[:month]) ==
               [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]

      assert Enum.all?(intervals, fn i ->
               i.from.time[:year] == 1985 and i.from.time[:day] == 15
             end)
    end
  end

  describe "passthroughs and errors" do
    test "existing %Tempo.Interval{} is idempotent" do
      {:ok, interval} = Tempo.from_iso8601("1985/1986")
      {:ok, result} = Tempo.to_interval(interval)
      assert result == interval
    end

    test "open-ended interval passes through" do
      {:ok, interval} = Tempo.from_iso8601("1985/..")
      {:ok, result} = Tempo.to_interval(interval)
      assert result == interval
    end

    test "bare Tempo.Duration returns an error" do
      {:ok, duration} = Tempo.from_iso8601("P3M")

      assert {:error, %Tempo.MaterialisationError{reason: :bare_duration} = e} =
               Tempo.to_interval(duration)

      assert Exception.message(e) =~ "Duration"
      assert Exception.message(e) =~ "no anchor"
    end

    test "to_interval!/1 raises on duration" do
      {:ok, duration} = Tempo.from_iso8601("P3M")

      assert_raise Tempo.MaterialisationError, ~r/no anchor/, fn ->
        Tempo.to_interval!(duration)
      end
    end

    test "to_interval!/1 raises on second-resolution Tempo" do
      {:ok, tempo} = Tempo.from_iso8601("2026-01-15T10:30:00")

      assert_raise Tempo.MaterialisationError, ~r/finest resolution/, fn ->
        Tempo.to_interval!(tempo)
      end
    end
  end

  describe "Tempo.Set mapping" do
    test "one-of set (`[a,b,c]`) is epistemic disjunction — returns an error" do
      # `[…]` is one-of set syntax: "it was one of these, I don't
      # know which." Flattening to an IntervalSet would lie about
      # certainty.
      {:ok, set} = Tempo.from_iso8601("[2020Y,2021Y,2022Y]")

      assert {:error, %Tempo.MaterialisationError{reason: :one_of_set} = e} =
               Tempo.to_interval(set)

      assert Exception.message(e) =~ "one-of"
      assert Exception.message(e) =~ "epistemic"
    end

    test "all-of range (`{a..c}Y`) materialises to a coalesced IntervalSet" do
      # `{…}Y` is the range-in-a-slot form. Three touching years
      # coalesce to a single 3-year span.
      {:ok, tempo} = Tempo.from_iso8601("{2020,2021,2022}Y")
      {:ok, %Tempo.IntervalSet{intervals: intervals}} = Tempo.to_interval(tempo)
      assert length(intervals) == 1
      [interval] = intervals
      assert interval.from.time == [year: 2020, month: 1]
      assert interval.to.time == [year: 2023, month: 1]
    end
  end

  describe "metadata propagation" do
    test "expression-level qualification propagates to both endpoints" do
      {:ok, tempo} = Tempo.from_iso8601("2022Y?")
      {:ok, interval} = Tempo.to_interval(tempo)
      assert interval.from.qualification == :uncertain
      assert interval.to.qualification == :uncertain
    end

    test "component-level qualifications propagate" do
      {:ok, tempo} = Tempo.from_iso8601("2022-?06-15")
      {:ok, interval} = Tempo.to_interval(tempo)
      assert interval.from.qualifications == %{month: :uncertain}
      assert interval.to.qualifications == %{month: :uncertain}
    end

    test "IXDTF extended info (zone + calendar) propagates" do
      {:ok, tempo} = Tempo.from_iso8601("2022-06-15T10:30[Europe/Paris][u-ca=hebrew]")
      {:ok, interval} = Tempo.to_interval(tempo)
      assert interval.from.extended.zone_id == "Europe/Paris"
      assert interval.from.extended.calendar == :hebrew
      assert interval.to.extended.zone_id == "Europe/Paris"
      assert interval.to.extended.calendar == :hebrew
    end

    test "calendar propagates" do
      {:ok, tempo} = Tempo.from_iso8601("2022")
      {:ok, interval} = Tempo.to_interval(tempo)
      assert interval.from.calendar == Calendrical.Gregorian
      assert interval.to.calendar == Calendrical.Gregorian
    end
  end

  describe "iteration parity (implicit vs explicit)" do
    # The central promise of `to_interval/1`: implicit iteration and
    # explicit iteration produce identical results for every shape
    # that supports both. If this test fails, either the implicit
    # enumeration or the explicit materialisation is wrong.

    for input <- ["2026Y", "2026-06", "2026-06-15", "2026-06-15T10", "2026-06-15T10:30"] do
      test "implicit vs explicit iteration match for #{inspect(input)}" do
        {:ok, tempo} = Tempo.from_iso8601(unquote(input))
        {:ok, interval} = Tempo.to_interval(tempo)

        implicit_times = tempo |> Enum.to_list() |> Enum.map(& &1.time)
        explicit_times = interval |> Enum.to_list() |> Enum.map(& &1.time)

        assert implicit_times == explicit_times,
               "implicit and explicit iteration diverge for #{unquote(input)}\n" <>
                 "implicit: #{inspect(implicit_times, limit: 3)}\n" <>
                 "explicit: #{inspect(explicit_times, limit: 3)}"
      end
    end
  end
end
