defmodule Tempo.Operations.Test do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  alias Tempo.Compare
  alias Tempo.Interval
  alias Tempo.IntervalSet
  alias Tempo.Operations

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

      assert {:error, %Tempo.MaterialisationError{reason: :bare_duration} = e} =
               Operations.align(~o"2022Y", d)

      assert Exception.message(e) =~ "Duration"
    end

    test "rejects one-of Tempo.Set" do
      {:ok, s} = Tempo.from_iso8601("[2020Y,2021Y,2022Y]")

      assert {:error, %Tempo.MaterialisationError{reason: :one_of_set} = e} =
               Operations.align(~o"2023Y", s)

      assert Exception.message(e) =~ "one-of"
    end

    test "accepts Tempo.IntervalSet passthrough" do
      {:ok, set} = Tempo.to_interval_set(~o"2022Y")
      assert {:ok, {a, b}} = Operations.align(set, ~o"2023Y")
      assert a.intervals != []
      assert b.intervals != []
    end
  end

  describe "align/2,3 — anchor class compatibility" do
    test "two anchored operands — OK" do
      assert {:ok, _} = Operations.align(~o"2022Y", ~o"2023Y")
    end

    test "two non-anchored operands — OK" do
      assert {:ok, _} = Operations.align(~o"T10:00", ~o"T14:30")
    end

    test "anchored + non-anchored without bound — error" do
      assert {:error, %Tempo.NonAnchoredError{} = e} =
               Operations.align(~o"2022Y", ~o"T10:30")

      assert Exception.message(e) =~ ":bound"
      assert Exception.message(e) =~ "anchor/2"
    end

    test "anchored + non-anchored WITH bound — OK" do
      assert {:ok, _} =
               Operations.align(~o"2026-01-04", ~o"T10:30", bound: ~o"2026-01-04")
    end
  end

  describe "align/2,3 — resolution" do
    test "aligns to the finer resolution" do
      {:ok, {a, b}} = Operations.align(~o"2022Y", ~o"2022-06-15")
      [a_iv] = a.intervals
      [b_iv] = b.intervals

      # Both aligned to day resolution (the finer of year vs day).
      assert Keyword.has_key?(a_iv.from.time, :day)
      assert Keyword.has_key?(b_iv.from.time, :day)
    end
  end

  describe "union/2 — member-preserving" do
    test "disjoint operands — returns both as separate members" do
      {:ok, r} = Tempo.union(~o"2020Y", ~o"2022Y")
      assert length(r.intervals) == 2
    end

    test "touching operands keep both members distinct" do
      # Member-preserving union: two touching intervals remain two
      # members. Call `Tempo.IntervalSet.coalesce/1` for the
      # canonical instant-set form (one merged span).
      {:ok, r} = Tempo.union(~o"2022Y", ~o"2023Y")
      assert length(r.intervals) == 2

      coalesced = IntervalSet.coalesce(r)
      assert length(coalesced.intervals) == 1
      [iv] = coalesced.intervals
      assert iv.from.time == [year: 2022, month: 1]
      assert iv.to.time == [year: 2024, month: 1]
    end

    test "overlapping operands keep both members distinct" do
      {:ok, a} = Tempo.from_iso8601("2022-01/2022-12")
      {:ok, b} = Tempo.from_iso8601("2022-06/2023-01")
      {:ok, r} = Tempo.union(a, b)
      assert length(r.intervals) == 2

      coalesced = IntervalSet.coalesce(r)
      assert length(coalesced.intervals) == 1
    end

    test "identity with empty set: ∅ ∪ A = A" do
      {:ok, empty} = IntervalSet.new([])
      {:ok, r} = Tempo.union(empty, ~o"2022Y")
      assert length(r.intervals) == 1
    end

    test "commutativity (member-set equality after coalescing)" do
      {:ok, r1} = Tempo.union(~o"2022Y", ~o"2024Y")
      {:ok, r2} = Tempo.union(~o"2024Y", ~o"2022Y")
      # Member-preserving union sorts by `from`, so the two
      # constructions produce the same ordered member list.
      assert r1.intervals == r2.intervals
    end
  end

  describe "intersection/2 — instant-level trimmed intersection" do
    test "year ∩ day → the day-shaped span (trimmed)" do
      {:ok, r} = Tempo.intersection(~o"2022Y", ~o"2022-06-15")
      [iv] = r.intervals
      assert iv.from.time[:month] == 6
      assert iv.from.time[:day] == 15
      assert iv.to.time[:day] == 16
    end

    test "time-of-day axis trim" do
      {:ok, r} = Tempo.intersection(~o"T10", ~o"T10:30")
      [iv] = r.intervals
      assert iv.from.time[:hour] == 10
      assert iv.from.time[:minute] == 30
    end

    test "disjoint operands → empty" do
      {:ok, r} = Tempo.intersection(~o"2022Y", ~o"2024Y")
      assert r.intervals == []
    end

    test "touching operands → empty (half-open semantics, no shared instant)" do
      {:ok, r} = Tempo.intersection(~o"2022Y", ~o"2023Y")
      assert r.intervals == []
    end

    test "identity with empty set: ∅ ∩ A = ∅" do
      {:ok, empty} = IntervalSet.new([])
      {:ok, r} = Tempo.intersection(empty, ~o"2022Y")
      assert r.intervals == []
    end

    test "commutativity — instant-level intersection IS symmetric" do
      # The trimmed/instant-level intersection covers the same
      # instants regardless of operand order.
      {:ok, r1} = Tempo.intersection(~o"2022Y", ~o"2022-06")
      {:ok, r2} = Tempo.intersection(~o"2022-06", ~o"2022Y")
      assert Tempo.equal?(r1, r2)
    end
  end

  describe "members_overlapping/2 — member-preserving overlap filter" do
    test "year ∩ day inside → the year member (A side is kept whole)" do
      # Member-preserving: the year member of A overlaps the day
      # member of B, so the year member survives. For the trimmed
      # overlap span use `Tempo.intersection/2`.
      {:ok, r} = Tempo.members_overlapping(~o"2022Y", ~o"2022-06-15")
      [iv] = r.intervals
      assert iv.from.time[:year] == 2022
      assert iv.from.time[:month] == 1
      assert iv.to.time[:year] == 2023
    end

    test "disjoint operands → empty" do
      {:ok, r} = Tempo.members_overlapping(~o"2022Y", ~o"2024Y")
      assert r.intervals == []
    end

    test "touching operands → empty (half-open semantics, no shared instant)" do
      {:ok, r} = Tempo.members_overlapping(~o"2022Y", ~o"2023Y")
      assert r.intervals == []
    end

    test "identity with empty set" do
      {:ok, empty} = IntervalSet.new([])
      {:ok, r} = Tempo.members_overlapping(empty, ~o"2022Y")
      assert r.intervals == []
    end

    test "member-preserving filter is NOT symmetric" do
      # Member-preserving keeps the A-side member in its entirety.
      # With different-resolution operands the two orderings
      # produce different result shapes:
      #   year ∩ month → [year] (the year, whole)
      #   month ∩ year → [month] (the month, whole)
      # For the instant-level symmetric form, use `intersection/2`.
      {:ok, r1} = Tempo.members_overlapping(~o"2022Y", ~o"2022-06")
      {:ok, r2} = Tempo.members_overlapping(~o"2022-06", ~o"2022Y")

      refute r1.intervals == r2.intervals

      # intersection IS commutative at the instant-set level.
      {:ok, trim1} = Tempo.intersection(~o"2022Y", ~o"2022-06")
      {:ok, trim2} = Tempo.intersection(~o"2022-06", ~o"2022Y")
      assert Tempo.equal?(trim1, trim2)
    end

    test "multi-member A — filters to members overlapping any B member" do
      # A: two-member set; B: one member overlapping only the second.
      a =
        IntervalSet.new!([
          %Tempo.Interval{from: ~o"2022-01", to: ~o"2022-03"},
          %Tempo.Interval{from: ~o"2022-06", to: ~o"2022-09"}
        ])

      {:ok, r} = Tempo.members_overlapping(a, ~o"2022-07")

      # Only the second member of A overlaps July.
      assert length(r.intervals) == 1
      [iv] = r.intervals
      assert iv.from.time[:month] == 6
    end
  end

  describe "complement/2" do
    test "requires :bound" do
      assert {:error, %Tempo.UnboundedRecurrenceError{} = e} =
               Tempo.complement(~o"2022-06", [])

      assert Exception.message(e) =~ ":bound"
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
      {:ok, empty} = IntervalSet.new([])
      {:ok, r} = Tempo.complement(empty, bound: ~o"2022Y")
      assert length(r.intervals) == 1
    end

    test "complement of U within U = ∅" do
      {:ok, r} = Tempo.complement(~o"2022Y", bound: ~o"2022Y")
      assert r.intervals == []
    end
  end

  describe "difference/2 — instant-level trimmed difference" do
    test "A ∖ A = ∅" do
      {:ok, r} = Tempo.difference(~o"2022Y", ~o"2022Y")
      assert r.intervals == []
    end

    test "A ∖ ∅ = A" do
      {:ok, empty} = IntervalSet.new([])
      {:ok, r} = Tempo.difference(~o"2022Y", empty)
      assert length(r.intervals) == 1
    end

    test "∅ ∖ A = ∅" do
      {:ok, empty} = IntervalSet.new([])
      {:ok, r} = Tempo.difference(empty, ~o"2022Y")
      assert r.intervals == []
    end

    test "year ∖ single month → two trimmed spans (Jan–Jun and Jul–Dec)" do
      {:ok, r} = Tempo.difference(~o"2022Y", ~o"2022-06")
      assert length(r.intervals) == 2
    end

    test "year ∖ two non-adjacent months → three trimmed spans" do
      {:ok, two_months} = Tempo.union(~o"2022-03", ~o"2022-09")
      {:ok, r} = Tempo.difference(~o"2022Y", two_months)
      assert length(r.intervals) == 3
    end

    test "A ∖ B where B is entirely outside A → A unchanged" do
      {:ok, r} = Tempo.difference(~o"2022-06", ~o"2023Y")
      assert length(r.intervals) == 1
    end

    test "fully-covered A member followed by a later B member emits no zero-width residue" do
      # Regression: a workday fully covered by a holiday, with
      # later holidays still in B, used to emit a zero-width
      # interval at the trailing endpoint of the consumed A.
      a =
        IntervalSet.new!([
          %Tempo.Interval{from: ~o"2026-07-03", to: ~o"2026-07-04"},
          %Tempo.Interval{from: ~o"2026-09-08", to: ~o"2026-09-09"}
        ])

      b =
        IntervalSet.new!([
          %Tempo.Interval{from: ~o"2026-07-03", to: ~o"2026-07-04"},
          %Tempo.Interval{from: ~o"2026-09-07", to: ~o"2026-09-08"}
        ])

      {:ok, r} = Tempo.difference(a, b)
      # July 3 fully consumed; Sept 8 has no overlap with Sept 7 holiday.
      assert length(r.intervals) == 1

      [iv] = r.intervals
      assert Interval.from(iv) == ~o"2026-09-08"

      refute Enum.any?(r.intervals, fn iv ->
               Tempo.equal?(iv.from, iv.to)
             end)
    end
  end

  describe "members_outside/2 — member-preserving anti-overlap filter" do
    test "year ∖ single month — the year member is dropped (it overlaps)" do
      # Member-preserving: the single A member (year) overlaps B,
      # so it's removed entirely. Use `difference/2` for the
      # instant-level trim that produces the "year minus June"
      # two remaining months.
      {:ok, r} = Tempo.members_outside(~o"2022Y", ~o"2022-06")
      assert r.intervals == []
    end

    test "multi-member A — drops only members that overlap B" do
      # Three month-members; B overlaps only the middle one.
      a =
        IntervalSet.new!([
          %Tempo.Interval{from: ~o"2022-01", to: ~o"2022-02"},
          %Tempo.Interval{from: ~o"2022-06", to: ~o"2022-07"},
          %Tempo.Interval{from: ~o"2022-12", to: ~o"2023-01"}
        ])

      {:ok, r} = Tempo.members_outside(a, ~o"2022-06")

      assert length(r.intervals) == 2
      [first, last] = r.intervals
      assert first.from.time[:month] == 1
      assert last.from.time[:month] == 12
    end

    test "A members entirely outside B → all kept whole" do
      {:ok, r} = Tempo.members_outside(~o"2022-06", ~o"2023Y")
      assert length(r.intervals) == 1
    end
  end

  describe "symmetric_difference/2 — instant-level" do
    test "A △ A = ∅" do
      {:ok, r} = Tempo.symmetric_difference(~o"2022Y", ~o"2022Y")
      assert r.intervals == []
    end

    test "disjoint A △ B covers the same instants as A ∪ B" do
      {:ok, sym} = Tempo.symmetric_difference(~o"2020Y", ~o"2022Y")
      {:ok, union} = Tempo.union(~o"2020Y", ~o"2022Y")
      assert Tempo.equal?(sym, union)
    end

    test "overlapping single-member operands → only the non-shared edges" do
      # Instant-level symmetric difference: the trimmed edges
      # of each operand that don't fall in the other.
      {:ok, a} = Tempo.from_iso8601("2022-01/2022-07")
      {:ok, b} = Tempo.from_iso8601("2022-04/2022-10")
      {:ok, r} = Tempo.symmetric_difference(a, b)

      # Two trimmed edges: Jan–Mar (a-only) and Jul–Oct (b-only).
      assert length(r.intervals) == 2
    end
  end

  describe "members_in_exactly_one/2 — member-preserving symmetric-difference filter" do
    test "A △ A = ∅" do
      {:ok, r} = Tempo.members_in_exactly_one(~o"2022Y", ~o"2022Y")
      assert r.intervals == []
    end

    test "disjoint A and B → both members survive whole" do
      {:ok, r} = Tempo.members_in_exactly_one(~o"2020Y", ~o"2022Y")
      assert length(r.intervals) == 2
    end

    test "overlapping single-member operands → both members dropped" do
      # Both single members overlap the other, so both are dropped.
      # Use `symmetric_difference/2` if you want the trimmed edges.
      {:ok, a} = Tempo.from_iso8601("2022-01/2022-07")
      {:ok, b} = Tempo.from_iso8601("2022-04/2022-10")
      {:ok, r} = Tempo.members_in_exactly_one(a, b)

      assert r.intervals == []
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
    test "anchored ∩ non-anchored within a single-day bound → trimmed time slot" do
      # Trimmed intersection gives the minute slot inside the day
      # span. The member-preserving filter returns the day itself.
      {:ok, r} = Tempo.intersection(~o"2026-01-04", ~o"T10:30", bound: ~o"2026-01-04")
      assert length(r.intervals) == 1
      [iv] = r.intervals
      assert iv.from.time[:hour] == 10
      assert iv.from.time[:minute] == 30
    end

    test "anchored ∩ non-anchored within a multi-day bound → trimmed slot on matched day" do
      {:ok, r} =
        Tempo.intersection(~o"2026-01-04", ~o"T10:30", bound: ~o"2026-01-01/2026-01-10")

      assert length(r.intervals) == 1
      [iv] = r.intervals
      assert iv.from.time[:day] == 4
    end

    test "non-anchored bound is rejected" do
      assert {:error, %Tempo.NonAnchoredError{} = e} =
               Operations.align(~o"2026-01-04", ~o"T10:30", bound: ~o"T00:00")

      assert Exception.message(e) =~ "bound"
      assert Exception.message(e) =~ "anchored"
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
    test "Hebrew ∩ Gregorian (members_overlapping) — A's calendar is preserved on the surviving A member" do
      # Gregorian 2022-06-15 corresponds to Hebrew 5782-10-16.
      # The Hebrew month 10 of year 5782 contains that date, so
      # the Hebrew-month member of A survives the overlap filter.
      hebrew_month = %Tempo{
        time: [year: 5782, month: 10],
        calendar: Calendrical.Hebrew
      }

      {:ok, r} = Tempo.members_overlapping(hebrew_month, ~o"2022-06-15")
      assert length(r.intervals) == 1

      [iv] = r.intervals
      assert iv.from.calendar == Calendrical.Hebrew
      assert iv.from.time[:year] == 5782
      assert iv.from.time[:month] == 10
    end

    test "intersection preserves A's calendar on the trimmed span" do
      hebrew_month = %Tempo{
        time: [year: 5782, month: 10],
        calendar: Calendrical.Hebrew
      }

      {:ok, r} = Tempo.intersection(hebrew_month, ~o"2022-06-15")
      [iv] = r.intervals
      assert iv.from.calendar == Calendrical.Hebrew
      assert iv.from.time[:day] == 16
    end

    test "Gregorian ∩ Hebrew (members_overlapping) — A's calendar is preserved on the surviving A member" do
      hebrew_day = %Tempo{
        time: [year: 5782, month: 10, day: 16],
        calendar: Calendrical.Hebrew
      }

      {:ok, r} = Tempo.members_overlapping(~o"2022-06", hebrew_day)
      assert length(r.intervals) == 1

      [iv] = r.intervals
      assert iv.from.calendar == Calendrical.Gregorian
      assert iv.from.time[:year] == 2022
      assert iv.from.time[:month] == 6
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
    test "intersection with single-day anchor — crossing materialises the pre-midnight portion" do
      {:ok, na} = Tempo.from_iso8601("T23:30/T01:00")

      # Trimmed form: the overlap span inside the anchored day.
      {:ok, r} = Tempo.intersection(~o"2026-01-04", na, bound: ~o"2026-01-04")
      assert length(r.intervals) == 1

      [iv] = r.intervals
      assert iv.from.time[:hour] == 23
      assert iv.from.time[:minute] == 30
    end

    test "intersection on multi-day bound — crossing materialises three trimmed slots" do
      {:ok, na} = Tempo.from_iso8601("T23:00/T01:00")

      {:ok, r} =
        Tempo.intersection(~o"2026-01-01/2026-01-04", na, bound: ~o"2026-01-01/2026-01-04")

      assert length(r.intervals) == 3
    end

    test "time-of-day union: crossing ∪ non-crossing (member-preserving)" do
      # After midnight-split: crossing becomes two members
      # (pre-midnight + post-midnight); morning stays one. Union
      # is all three members.
      {:ok, crossing} = Tempo.from_iso8601("T23:00/T01:00")
      {:ok, morning} = Tempo.from_iso8601("T00:30/T02:00")

      {:ok, r} = Tempo.union(crossing, morning)
      assert length(r.intervals) == 3
    end

    test "time-of-day intersection: crossing ∩ non-crossing" do
      {:ok, crossing} = Tempo.from_iso8601("T23:00/T01:00")
      {:ok, morning} = Tempo.from_iso8601("T00:30/T02:00")

      {:ok, r} = Tempo.intersection(crossing, morning)

      # Only the post-midnight portion of the crossing overlaps.
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

  describe "De Morgan's laws (instant-set level)" do
    # De Morgan's laws hold at the instant-set level — two sets
    # are "equal" when they cover the same instants. Under Tempo's
    # member-preserving defaults this means: coalesce both sides
    # before comparing members, or just use `Tempo.equal?/2` which
    # does it for you.

    test "¬(A ∪ B) = ¬A ∩ ¬B" do
      a = ~o"2022-03"
      b = ~o"2022-09"
      u = ~o"2022Y"

      {:ok, a_or_b} = Tempo.union(a, b)
      {:ok, not_a_or_b} = Tempo.complement(a_or_b, bound: u)

      {:ok, not_a} = Tempo.complement(a, bound: u)
      {:ok, not_b} = Tempo.complement(b, bound: u)
      # Instant-level intersection — the sides are both
      # "covered-instants" sets, so the trimmed form is the
      # faithful one for the identity.
      {:ok, not_a_and_not_b} = Tempo.intersection(not_a, not_b)

      assert Tempo.equal?(not_a_or_b, not_a_and_not_b)
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

      assert Tempo.equal?(not_a_and_b, not_a_or_not_b)
    end
  end

  # Every operation must give the same answer whether its operands are
  # `%Tempo.Interval{}`, `%Tempo.IntervalSet{}`, a bare `%Tempo{}`, or a
  # mix — `align/3` coerces both operands to an IntervalSet before any
  # logic runs, so representation must never change the result.
  describe "cross-type invariance — Interval, IntervalSet, and mixed operands" do
    setup do
      a_i = Interval.new!(from: ~o"2026-06-15T09:00:00", to: ~o"2026-06-15T12:00:00")
      b_i = Interval.new!(from: ~o"2026-06-15T10:00:00", to: ~o"2026-06-15T14:00:00")

      %{
        a_i: a_i,
        b_i: b_i,
        a_s: IntervalSet.new!([a_i]),
        b_s: IntervalSet.new!([b_i])
      }
    end

    test "binary ops agree across II, IS, SI, SS representations", ctx do
      for op <- [:union, :intersection, :difference, :symmetric_difference] do
        ii = canon(apply(Tempo, op, [ctx.a_i, ctx.b_i]))
        assert ii == canon(apply(Tempo, op, [ctx.a_i, ctx.b_s])), "#{op}: Interval×Set"
        assert ii == canon(apply(Tempo, op, [ctx.a_s, ctx.b_i])), "#{op}: Set×Interval"
        assert ii == canon(apply(Tempo, op, [ctx.a_s, ctx.b_s])), "#{op}: Set×Set"
      end
    end

    test "predicates agree across II, IS, SI, SS representations", ctx do
      for op <- [:disjoint?, :overlaps?, :subset?, :contains?, :equal?] do
        ii = apply(Tempo, op, [ctx.a_i, ctx.b_i])
        assert ii == apply(Tempo, op, [ctx.a_i, ctx.b_s]), "#{op}: Interval×Set"
        assert ii == apply(Tempo, op, [ctx.a_s, ctx.b_i]), "#{op}: Set×Interval"
        assert ii == apply(Tempo, op, [ctx.a_s, ctx.b_s]), "#{op}: Set×Set"
      end
    end

    test "multi-member set vs single-interval operand agree (incl. member-preserving ops)" do
      a =
        IntervalSet.new!([
          Interval.new!(from: ~o"2026-06-15T09:00:00", to: ~o"2026-06-15T11:00:00"),
          Interval.new!(from: ~o"2026-06-15T13:00:00", to: ~o"2026-06-15T16:00:00")
        ])

      b_i = Interval.new!(from: ~o"2026-06-15T10:00:00", to: ~o"2026-06-15T14:00:00")
      b_s = IntervalSet.new!([b_i])

      ops = [
        :union,
        :intersection,
        :difference,
        :symmetric_difference,
        :members_overlapping,
        :members_outside,
        :members_in_exactly_one
      ]

      for op <- ops do
        assert canon(apply(Tempo, op, [a, b_i])) == canon(apply(Tempo, op, [a, b_s])), "#{op}"
      end
    end

    test "a bare Tempo operand mixes with Interval and IntervalSet", ctx do
      day = ~o"2026-06-15"
      assert canon(Tempo.intersection(day, ctx.b_i)) == canon(Tempo.intersection(day, ctx.b_s))
      assert canon(Tempo.union(ctx.b_i, day)) == canon(Tempo.union(ctx.b_s, day))
    end
  end

  # Normalise any set-op result (an Interval or an IntervalSet) to a
  # sorted list of `{from, to}` UTC-second pairs for representation-
  # independent comparison.
  defp canon({:ok, result}) do
    {:ok, set} = Tempo.to_interval_set(result)

    set
    |> IntervalSet.to_list()
    |> Enum.map(&{Compare.to_utc_seconds(&1.from), Compare.to_utc_seconds(&1.to)})
    |> Enum.sort()
  end
end
