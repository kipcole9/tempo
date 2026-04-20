defmodule Tempo.Operations.Test do
  use ExUnit.Case, async: true
  import Tempo.Sigil

  # Tests for `Tempo.Operations` — the set-operations module.
  # Organised by concern:
  #
  #   1. Preflight (align/2,3) — validation, anchor-class, resolution
  #   2. Core set operations — union, intersection, complement,
  #      difference, symmetric_difference
  #   3. Predicates — disjoint?, overlaps?, subset?, contains?, equal?
  #   4. Cross-axis (bound-based materialisation)
  #   5. Algebraic identities — ∅ ∪ A = A, De Morgan's laws, etc.

  setup_all do
    # Needed for zoned DateTime construction in tests.
    Calendar.put_time_zone_database(Tzdata.TimeZoneDatabase)
    :ok
  end

  describe "align/2,3 — operand validation" do
    test "rejects Tempo.Duration" do
      {:ok, d} = Tempo.from_iso8601("P3M")
      assert {:error, message} = Tempo.Operations.align(~o"2022Y", d)
      assert message =~ "Duration"
    end

    test "rejects one-of Tempo.Set" do
      {:ok, s} = Tempo.from_iso8601("[2020Y,2021Y,2022Y]")
      assert {:error, message} = Tempo.Operations.align(~o"2023Y", s)
      assert message =~ "one-of"
    end

    test "accepts Tempo.IntervalSet passthrough" do
      {:ok, set} = Tempo.to_interval_set(~o"2022Y")
      assert {:ok, {a, b}} = Tempo.Operations.align(set, ~o"2023Y")
      assert a.intervals != []
      assert b.intervals != []
    end
  end

  describe "align/2,3 — anchor class compatibility" do
    test "two anchored operands — OK" do
      assert {:ok, _} = Tempo.Operations.align(~o"2022Y", ~o"2023Y")
    end

    test "two non-anchored operands — OK" do
      assert {:ok, _} = Tempo.Operations.align(~o"T10:00", ~o"T14:30")
    end

    test "anchored + non-anchored without bound — error" do
      assert {:error, message} = Tempo.Operations.align(~o"2022Y", ~o"T10:30")
      assert message =~ ":bound"
      assert message =~ "anchor/2"
    end

    test "anchored + non-anchored WITH bound — OK" do
      assert {:ok, _} =
               Tempo.Operations.align(~o"2026-01-04", ~o"T10:30", bound: ~o"2026-01-04")
    end
  end

  describe "align/2,3 — resolution" do
    test "aligns to the finer resolution" do
      {:ok, {a, b}} = Tempo.Operations.align(~o"2022Y", ~o"2022-06-15")
      [a_iv] = a.intervals
      [b_iv] = b.intervals

      # Both aligned to day resolution (the finer of year vs day).
      assert Keyword.has_key?(a_iv.from.time, :day)
      assert Keyword.has_key?(b_iv.from.time, :day)
    end
  end

  describe "union/2" do
    test "disjoint operands — returns both" do
      {:ok, r} = Tempo.union(~o"2020Y", ~o"2022Y")
      assert length(r.intervals) == 2
    end

    test "touching operands coalesce" do
      {:ok, r} = Tempo.union(~o"2022Y", ~o"2023Y")
      assert length(r.intervals) == 1
      [iv] = r.intervals
      assert iv.from.time == [year: 2022, month: 1]
      assert iv.to.time == [year: 2024, month: 1]
    end

    test "overlapping operands coalesce" do
      # Interval [2022-Jan, 2022-Dec) overlaps [2022-Jun, 2023-Jan)
      {:ok, a} = Tempo.from_iso8601("2022-01/2022-12")
      {:ok, b} = Tempo.from_iso8601("2022-06/2023-01")
      {:ok, r} = Tempo.union(a, b)
      assert length(r.intervals) == 1
    end

    test "identity with empty set: ∅ ∪ A = A" do
      {:ok, empty} = Tempo.IntervalSet.new([])
      {:ok, r} = Tempo.union(empty, ~o"2022Y")
      assert length(r.intervals) == 1
    end

    test "commutativity" do
      {:ok, r1} = Tempo.union(~o"2022Y", ~o"2024Y")
      {:ok, r2} = Tempo.union(~o"2024Y", ~o"2022Y")
      assert r1.intervals == r2.intervals
    end
  end

  describe "intersection/2" do
    test "year ∩ day inside → the day span" do
      # Both aligned to day's implicit enumeration (hour). 2022Y
      # extends to [2022-01-01T00, 2023-01-01T00); the day
      # extends to [2022-06-15T00, 2022-06-16T00). Intersection =
      # the day's span.
      {:ok, r} = Tempo.intersection(~o"2022Y", ~o"2022-06-15")
      [iv] = r.intervals
      assert iv.from.time[:year] == 2022
      assert iv.from.time[:month] == 6
      assert iv.from.time[:day] == 15
      assert iv.to.time[:day] == 16
    end

    test "disjoint operands → empty" do
      {:ok, r} = Tempo.intersection(~o"2022Y", ~o"2024Y")
      assert r.intervals == []
    end

    test "touching operands → empty (half-open semantics)" do
      # [2022-Jan, 2023-Jan) and [2023-Jan, 2024-Jan) touch at Jan 1
      # 2023 but share no instant — both half-open.
      {:ok, r} = Tempo.intersection(~o"2022Y", ~o"2023Y")
      assert r.intervals == []
    end

    test "identity with empty set: ∅ ∩ A = ∅" do
      {:ok, empty} = Tempo.IntervalSet.new([])
      {:ok, r} = Tempo.intersection(empty, ~o"2022Y")
      assert r.intervals == []
    end

    test "commutativity" do
      {:ok, r1} = Tempo.intersection(~o"2022Y", ~o"2022-06")
      {:ok, r2} = Tempo.intersection(~o"2022-06", ~o"2022Y")
      assert r1.intervals == r2.intervals
    end

    test "time-of-day axis intersection" do
      {:ok, r} = Tempo.intersection(~o"T10", ~o"T10:30")
      [iv] = r.intervals
      # 10:30 is contained in 10:00-11:00.
      assert iv.from.time[:hour] == 10
      assert iv.from.time[:minute] == 30
    end
  end

  describe "complement/2" do
    test "requires :bound" do
      assert {:error, message} = Tempo.complement(~o"2022-06", [])
      assert message =~ ":bound"
    end

    test "gap in the middle → two intervals" do
      {:ok, r} = Tempo.complement(~o"2022-06", bound: ~o"2022Y")
      assert length(r.intervals) == 2
      [jan_may, jul_dec] = r.intervals
      assert jan_may.from.time == [year: 2022, month: 1, day: 1]
      assert jan_may.to.time == [year: 2022, month: 6, day: 1]
      assert jul_dec.from.time == [year: 2022, month: 7, day: 1]
      assert jul_dec.to.time == [year: 2023, month: 1, day: 1]
    end

    test "complement of ∅ within U = U" do
      {:ok, empty} = Tempo.IntervalSet.new([])
      {:ok, r} = Tempo.complement(empty, bound: ~o"2022Y")
      assert length(r.intervals) == 1
    end

    test "complement of U within U = ∅" do
      {:ok, r} = Tempo.complement(~o"2022Y", bound: ~o"2022Y")
      assert r.intervals == []
    end
  end

  describe "difference/2" do
    test "A ∖ A = ∅" do
      {:ok, r} = Tempo.difference(~o"2022Y", ~o"2022Y")
      assert r.intervals == []
    end

    test "A ∖ ∅ = A" do
      {:ok, empty} = Tempo.IntervalSet.new([])
      {:ok, r} = Tempo.difference(~o"2022Y", empty)
      assert length(r.intervals) == 1
    end

    test "∅ ∖ A = ∅" do
      {:ok, empty} = Tempo.IntervalSet.new([])
      {:ok, r} = Tempo.difference(empty, ~o"2022Y")
      assert r.intervals == []
    end

    test "year ∖ single month → two intervals" do
      {:ok, r} = Tempo.difference(~o"2022Y", ~o"2022-06")
      assert length(r.intervals) == 2
    end

    test "year ∖ two non-adjacent months → three intervals" do
      {:ok, two_months} = Tempo.union(~o"2022-03", ~o"2022-09")
      {:ok, r} = Tempo.difference(~o"2022Y", two_months)
      assert length(r.intervals) == 3
    end

    test "A ∖ B where B is entirely outside A → A unchanged" do
      {:ok, r} = Tempo.difference(~o"2022-06", ~o"2023Y")
      assert length(r.intervals) == 1
    end
  end

  describe "symmetric_difference/2" do
    test "A △ A = ∅" do
      {:ok, r} = Tempo.symmetric_difference(~o"2022Y", ~o"2022Y")
      assert r.intervals == []
    end

    test "disjoint A △ B = A ∪ B" do
      {:ok, sym} = Tempo.symmetric_difference(~o"2020Y", ~o"2022Y")
      {:ok, union} = Tempo.union(~o"2020Y", ~o"2022Y")
      assert sym.intervals == union.intervals
    end

    test "overlapping — emits only the non-shared parts" do
      {:ok, a} = Tempo.from_iso8601("2022-01/2022-07")
      {:ok, b} = Tempo.from_iso8601("2022-04/2022-10")
      {:ok, r} = Tempo.symmetric_difference(a, b)
      # Symmetric difference = Jan-Mar ∪ Jul-Sep (two disjoint pieces).
      assert length(r.intervals) == 2
    end
  end

  describe "predicates" do
    test "disjoint?/2" do
      assert Tempo.disjoint?(~o"2020Y", ~o"2022Y")
      refute Tempo.disjoint?(~o"2022Y", ~o"2022-06")
    end

    test "overlaps?/2" do
      refute Tempo.overlaps?(~o"2020Y", ~o"2022Y")
      assert Tempo.overlaps?(~o"2022Y", ~o"2022-06")
    end

    test "subset?/2" do
      assert Tempo.subset?(~o"2022-06", ~o"2022Y")
      refute Tempo.subset?(~o"2022Y", ~o"2022-06")
    end

    test "contains?/2 — inverse of subset" do
      assert Tempo.contains?(~o"2022Y", ~o"2022-06")
      refute Tempo.contains?(~o"2022-06", ~o"2022Y")
    end

    test "equal?/2" do
      assert Tempo.equal?(~o"2022Y", ~o"2022Y")
      refute Tempo.equal?(~o"2022Y", ~o"2023Y")

      # Different representations, same span.
      {:ok, explicit} = Tempo.from_iso8601("2022-01-01/2023-01-01")
      assert Tempo.equal?(~o"2022Y", explicit)
    end
  end

  describe "cross-axis with bound" do
    test "anchored ∩ non-anchored within a single-day bound → single time slot" do
      {:ok, r} = Tempo.intersection(~o"2026-01-04", ~o"T10:30", bound: ~o"2026-01-04")
      assert length(r.intervals) == 1
      [iv] = r.intervals
      assert iv.from.time[:hour] == 10
      assert iv.from.time[:minute] == 30
    end

    test "anchored ∩ non-anchored within a multi-day bound → single slot on matched day" do
      # Bound covers a 10-day window; the anchored date is within it.
      {:ok, r} =
        Tempo.intersection(~o"2026-01-04", ~o"T10:30", bound: ~o"2026-01-01/2026-01-10")

      # T10:30 is materialised on each of 9 days (Jan 1..9);
      # intersection with 2026-01-04 yields only the slot on that day.
      assert length(r.intervals) == 1
      [iv] = r.intervals
      assert iv.from.time[:day] == 4
    end

    test "non-anchored bound is rejected" do
      assert {:error, message} =
               Tempo.Operations.align(~o"2026-01-04", ~o"T10:30", bound: ~o"T00:00")

      assert message =~ "bound"
      assert message =~ "anchored"
    end
  end

  describe "zone-crossing" do
    test "equal?/2 across zones — same UTC instant compares equal" do
      # Both these intervals represent the same one-hour window,
      # one expressed in UTC and one in Europe/Paris (CEST, +2).
      utc = %Tempo.Interval{
        from: Tempo.from_iso8601!("2022-06-15T10:00:00Z"),
        to: Tempo.from_iso8601!("2022-06-15T11:00:00Z")
      }

      paris_from =
        Tempo.from_date_time(DateTime.new!(~D[2022-06-15], ~T[12:00:00], "Europe/Paris"))

      paris_to =
        Tempo.from_date_time(DateTime.new!(~D[2022-06-15], ~T[13:00:00], "Europe/Paris"))

      paris = %Tempo.Interval{from: paris_from, to: paris_to}

      # The intervals share a UTC instant, so the intersection
      # between them should be non-empty.
      assert Tempo.overlaps?(utc, paris)
    end
  end

  describe "anchor/2" do
    test "combines date + time into datetime" do
      assert Tempo.anchor(~o"2026-01-04", ~o"T10:30") == ~o"2026Y1M4DT10H30M"
    end

    test "rejects a non-anchored first operand" do
      assert_raise ArgumentError, ~r/first argument/, fn ->
        Tempo.anchor(~o"T10:30", ~o"T14:00")
      end
    end

    test "rejects an anchored second operand" do
      assert_raise ArgumentError, ~r/second argument/, fn ->
        Tempo.anchor(~o"2026-01-04", ~o"2026-01-04")
      end
    end
  end

  describe "cross-calendar operations" do
    test "Hebrew ∩ Gregorian converts B to A's calendar" do
      # Gregorian 2022-06-15 corresponds to Hebrew 5782-10-16.
      # The Hebrew month 10 of year 5782 contains that date.
      hebrew_month = %Tempo{
        time: [year: 5782, month: 10],
        calendar: Calendrical.Hebrew
      }

      {:ok, r} = Tempo.intersection(hebrew_month, ~o"2022-06-15")
      assert length(r.intervals) == 1

      # Result inherits first operand's calendar (Hebrew).
      [iv] = r.intervals
      assert iv.from.calendar == Calendrical.Hebrew
      assert iv.from.time[:year] == 5782
      assert iv.from.time[:month] == 10
      assert iv.from.time[:day] == 16
    end

    test "Gregorian ∩ Hebrew converts B to A's calendar" do
      hebrew_day = %Tempo{
        time: [year: 5782, month: 10, day: 16],
        calendar: Calendrical.Hebrew
      }

      {:ok, r} = Tempo.intersection(~o"2022-06", hebrew_day)
      assert length(r.intervals) == 1

      # Result inherits first operand's calendar (Gregorian).
      [iv] = r.intervals
      assert iv.from.calendar == Calendrical.Gregorian
      assert iv.from.time[:year] == 2022
      assert iv.from.time[:month] == 6
      assert iv.from.time[:day] == 15
    end

    test "disjoint dates across calendars are correctly identified" do
      hebrew_day = %Tempo{
        time: [year: 5782, month: 10, day: 16],
        calendar: Calendrical.Hebrew
      }

      # Hebrew 5782-10-16 = Greg 2022-06-15, which is NOT in Greg 2023-01.
      assert Tempo.disjoint?(hebrew_day, ~o"2023-01")
      refute Tempo.overlaps?(hebrew_day, ~o"2023-01")
    end

    test "overlaps? across calendars" do
      hebrew_day = %Tempo{
        time: [year: 5782, month: 10, day: 16],
        calendar: Calendrical.Hebrew
      }

      assert Tempo.overlaps?(hebrew_day, ~o"2022-06-15")
    end
  end

  describe "midnight-crossing non-anchored intervals" do
    test "anchor to a single day — crossing materialises on the correct days" do
      {:ok, na} = Tempo.from_iso8601("T23:30/T01:00")

      # The non-anchored interval crosses midnight, so anchored
      # to Jan 4 it becomes [Jan 4 23:30, Jan 5 01:00). Intersected
      # with the date `2026-01-04` span [Jan 4, Jan 5), the result
      # is [Jan 4 23:30, Jan 5 00:00) — the pre-midnight portion.
      {:ok, r} = Tempo.intersection(~o"2026-01-04", na, bound: ~o"2026-01-04")
      assert length(r.intervals) == 1

      [iv] = r.intervals
      assert iv.from.time[:day] == 4
      assert iv.from.time[:hour] == 23
      assert iv.from.time[:minute] == 30
      # Intersection clamped to the bound's upper edge: midnight
      # of Jan 5 (which equals start-of-Jan-5, not Jan 4 24:00).
      assert iv.to.time[:day] == 5
      assert iv.to.time[:hour] == 0
    end

    test "crossing materialises on each day of a multi-day bound" do
      # 3-day bound (2026-01-01/2026-01-04 is the half-open span
      # covering Jan 1, 2, 3). The non-anchored crossing interval
      # produces 3 anchored intervals (one anchored to each day),
      # but the last one's upper endpoint is clamped by the bound.
      {:ok, na} = Tempo.from_iso8601("T23:00/T01:00")

      {:ok, r} =
        Tempo.intersection(~o"2026-01-01/2026-01-04", na,
          bound: ~o"2026-01-01/2026-01-04"
        )

      assert length(r.intervals) == 3
    end

    test "time-of-day union: crossing ∪ non-crossing" do
      {:ok, crossing} = Tempo.from_iso8601("T23:00/T01:00")
      {:ok, morning} = Tempo.from_iso8601("T00:30/T02:00")

      {:ok, r} = Tempo.union(crossing, morning)

      # Split produces [T00:00, T01:00) from the crossing and
      # [T00:30, T02:00) from morning, which overlap and coalesce
      # to [T00:00, T02:00). Plus [T23:00, T24:00) from the
      # crossing. Total: 2 intervals.
      assert length(r.intervals) == 2
    end

    test "time-of-day intersection: crossing ∩ non-crossing" do
      {:ok, crossing} = Tempo.from_iso8601("T23:00/T01:00")
      {:ok, morning} = Tempo.from_iso8601("T00:30/T02:00")

      {:ok, r} = Tempo.intersection(crossing, morning)

      # Only the post-midnight portion of the crossing
      # ([T00:00, T01:00)) overlaps morning ([T00:30, T02:00)).
      assert length(r.intervals) == 1
      [iv] = r.intervals
      assert iv.from.time[:hour] == 0
      assert iv.from.time[:minute] == 30
      assert iv.to.time[:hour] == 1
    end

    test "time-of-day disjoint: two non-crossing on opposite sides of midnight" do
      {:ok, evening} = Tempo.from_iso8601("T22:00/T23:30")
      {:ok, morning} = Tempo.from_iso8601("T02:00/T04:00")

      assert Tempo.disjoint?(evening, morning)
    end

    test "zero-width non-anchored interval is treated as empty" do
      # `T12:00/T12:00` — from == to. compare_time gives :eq, which
      # is not :gt, so crosses_midnight? returns false and the
      # interval stays as zero-width.
      {:ok, zero} = Tempo.from_iso8601("T12:00/T12:00")
      {:ok, r} = Tempo.intersection(zero, zero)
      # Zero-width intersected with zero-width is empty.
      assert r.intervals == []
    end
  end

  describe "De Morgan's laws" do
    # ¬(A ∪ B) = ¬A ∩ ¬B
    # ¬(A ∩ B) = ¬A ∪ ¬B
    #
    # "Complement within the universe" is our ¬.

    test "¬(A ∪ B) = ¬A ∩ ¬B" do
      a = ~o"2022-03"
      b = ~o"2022-09"
      u = ~o"2022Y"

      {:ok, a_or_b} = Tempo.union(a, b)
      {:ok, not_a_or_b} = Tempo.complement(a_or_b, bound: u)

      {:ok, not_a} = Tempo.complement(a, bound: u)
      {:ok, not_b} = Tempo.complement(b, bound: u)
      {:ok, not_a_and_not_b} = Tempo.intersection(not_a, not_b)

      assert not_a_or_b.intervals == not_a_and_not_b.intervals
    end

    test "¬(A ∩ B) = ¬A ∪ ¬B" do
      a = ~o"2022-01/2022-07"
      b = ~o"2022-04/2022-10"
      u = ~o"2022Y"

      {:ok, a_and_b} = Tempo.intersection(a, b)
      {:ok, not_a_and_b} = Tempo.complement(a_and_b, bound: u)

      {:ok, not_a} = Tempo.complement(a, bound: u)
      {:ok, not_b} = Tempo.complement(b, bound: u)
      {:ok, not_a_or_not_b} = Tempo.union(not_a, not_b)

      assert not_a_and_b.intervals == not_a_or_not_b.intervals
    end
  end
end
