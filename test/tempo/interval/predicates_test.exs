defmodule Tempo.Interval.PredicatesTest do
  use ExUnit.Case, async: true
  import Tempo.Sigils

  alias Tempo.Interval
  alias Tempo.IntervalSet

  describe "bounded?/1" do
    test "both endpoints concrete" do
      assert Interval.bounded?(%Interval{from: ~o"2026-06-01", to: ~o"2026-06-10"})
    end

    test "unbounded from" do
      refute Interval.bounded?(%Interval{from: :undefined, to: ~o"2026-06-10"})
    end

    test "unbounded to" do
      refute Interval.bounded?(%Interval{from: ~o"2026-06-01", to: :undefined})
    end

    test "fully open" do
      refute Interval.bounded?(%Interval{from: :undefined, to: :undefined})
    end
  end

  describe "empty?/1" do
    test "from == to → empty" do
      assert Interval.empty?(%Interval{from: ~o"2026-06-15", to: ~o"2026-06-15"})
    end

    test "from != to → non-empty" do
      refute Interval.empty?(%Interval{from: ~o"2026-06-01", to: ~o"2026-06-10"})
    end

    test "unbounded → non-empty" do
      refute Interval.empty?(%Interval{from: :undefined, to: ~o"2026-06-10"})
    end
  end

  describe "duration/1" do
    test "1 hour" do
      iv = %Interval{from: ~o"2026-06-15T09", to: ~o"2026-06-15T10"}
      assert Interval.duration(iv) == %Tempo.Duration{time: [second: 3600]}
    end

    test "zero-length → 0 seconds" do
      iv = %Interval{from: ~o"2026-06-15", to: ~o"2026-06-15"}
      assert Interval.duration(iv) == %Tempo.Duration{time: [second: 0]}
    end

    test "unbounded → :infinity" do
      assert Interval.duration(%Interval{from: :undefined, to: ~o"2026"}) == :infinity
      assert Interval.duration(%Interval{from: ~o"2026", to: :undefined}) == :infinity
    end
  end

  describe "duration predicates" do
    @iv %Interval{from: ~o"2026-06-15T09", to: ~o"2026-06-15T10"}

    test "at_least? — equals + longer ok, shorter not" do
      assert Interval.at_least?(@iv, ~o"PT1H")
      assert Interval.at_least?(@iv, ~o"PT30M")
      refute Interval.at_least?(@iv, ~o"PT2H")
    end

    test "at_most? — equals + shorter ok, longer not" do
      assert Interval.at_most?(@iv, ~o"PT1H")
      assert Interval.at_most?(@iv, ~o"PT2H")
      refute Interval.at_most?(@iv, ~o"PT30M")
    end

    test "exactly? — only the same duration" do
      assert Interval.exactly?(@iv, ~o"PT1H")
      refute Interval.exactly?(@iv, ~o"PT30M")
      refute Interval.exactly?(@iv, ~o"PT2H")
    end

    test "longer_than? — strict greater" do
      assert Interval.longer_than?(@iv, ~o"PT30M")
      refute Interval.longer_than?(@iv, ~o"PT1H")
      refute Interval.longer_than?(@iv, ~o"PT2H")
    end

    test "shorter_than? — strict less" do
      assert Interval.shorter_than?(@iv, ~o"PT2H")
      refute Interval.shorter_than?(@iv, ~o"PT1H")
      refute Interval.shorter_than?(@iv, ~o"PT30M")
    end

    test "unbounded satisfies at_least?, longer_than?, but not upper bounds" do
      unbounded_right = %Interval{from: ~o"2026-06-15", to: :undefined}

      assert Interval.at_least?(unbounded_right, ~o"P10Y")
      assert Interval.longer_than?(unbounded_right, ~o"P10Y")
      refute Interval.at_most?(unbounded_right, ~o"P10Y")
      refute Interval.shorter_than?(unbounded_right, ~o"P10Y")
      refute Interval.exactly?(unbounded_right, ~o"P10Y")
    end
  end

  describe "relation predicates — thin wrappers over relation/2" do
    @y %Interval{from: ~o"2026-06-05", to: ~o"2026-06-11"}

    test "before?/2 — strict precedes" do
      x = %Interval{from: ~o"2026-06-01", to: ~o"2026-06-03"}
      assert Interval.before?(x, @y)
    end

    test "before?/2 — meets does NOT count" do
      x = %Interval{from: ~o"2026-06-01", to: ~o"2026-06-05"}
      refute Interval.before?(x, @y)
    end

    test "after?/2 — strict preceded_by" do
      x = %Interval{from: ~o"2026-06-13", to: ~o"2026-06-15"}
      assert Interval.after?(x, @y)
    end

    test "meets?/2 — boundary coincidence" do
      x = %Interval{from: ~o"2026-06-01", to: ~o"2026-06-05"}
      assert Interval.meets?(x, @y)
    end

    test "adjacent?/2 — meets OR met_by" do
      meets_y = %Interval{from: ~o"2026-06-01", to: ~o"2026-06-05"}
      met_by_y = %Interval{from: ~o"2026-06-11", to: ~o"2026-06-15"}

      assert Interval.adjacent?(meets_y, @y)
      assert Interval.adjacent?(met_by_y, @y)
    end

    test "during?/2 — strict interior, no shared endpoints" do
      inside = %Interval{from: ~o"2026-06-07", to: ~o"2026-06-09"}
      shares_start = %Interval{from: ~o"2026-06-05", to: ~o"2026-06-09"}

      assert Interval.during?(inside, @y)
      # `starts` is not `during`
      refute Interval.during?(shares_start, @y)
    end

    test "within?/2 — equals + starts + during + finishes" do
      equals = %Interval{from: ~o"2026-06-05", to: ~o"2026-06-11"}
      starts = %Interval{from: ~o"2026-06-05", to: ~o"2026-06-09"}
      during = %Interval{from: ~o"2026-06-07", to: ~o"2026-06-09"}
      finishes = %Interval{from: ~o"2026-06-07", to: ~o"2026-06-11"}
      outside = %Interval{from: ~o"2026-06-01", to: ~o"2026-06-15"}

      assert Interval.within?(equals, @y)
      assert Interval.within?(starts, @y)
      assert Interval.within?(during, @y)
      assert Interval.within?(finishes, @y)
      refute Interval.within?(outside, @y)
    end

    test "relation predicates return false on error (e.g. multi-member set)" do
      multi =
        IntervalSet.new!(
          [
            %Interval{from: ~o"2026-06-01", to: ~o"2026-06-03"},
            %Interval{from: ~o"2026-06-05", to: ~o"2026-06-07"}
          ],
          coalesce: false
        )

      refute Interval.before?(multi, @y)
      refute Interval.within?(multi, @y)
    end
  end

  describe "top-level Tempo delegates" do
    test "Tempo.at_least?/2" do
      iv = %Interval{from: ~o"2026-06-15T09", to: ~o"2026-06-15T10"}
      assert Tempo.at_least?(iv, ~o"PT1H")
    end

    test "Tempo.within?/2" do
      candidate = %Interval{from: ~o"2026-06-15T10", to: ~o"2026-06-15T11"}
      window = %Interval{from: ~o"2026-06-15T09", to: ~o"2026-06-15T17"}
      assert Tempo.within?(candidate, window)
    end

    test "Tempo.adjacent?/2" do
      assert Tempo.adjacent?(~o"2026-06-15", ~o"2026-06-16")
      refute Tempo.adjacent?(~o"2026-06-15", ~o"2026-06-17")
    end

    test "Tempo.duration/1" do
      iv = %Interval{from: ~o"2026-06-15T09", to: ~o"2026-06-15T10"}
      assert Tempo.duration(iv) == %Tempo.Duration{time: [second: 3600]}
    end

    test "Tempo.bounded?/1 and Tempo.empty?/1" do
      assert Tempo.bounded?(%Interval{from: ~o"2026-06-01", to: ~o"2026-06-10"})
      refute Tempo.bounded?(%Interval{from: ~o"2026-06-01", to: :undefined})
      assert Tempo.empty?(%Interval{from: ~o"2026-06-15", to: ~o"2026-06-15"})
    end
  end

  describe "scenario: at_least?/within? in practice" do
    test "filter mutual-free-slots by minimum duration" do
      alice_busy = %Tempo.IntervalSet{
        intervals: [
          %Interval{from: ~o"2026-06-15T10", to: ~o"2026-06-15T11"},
          %Interval{from: ~o"2026-06-15T14", to: ~o"2026-06-15T15"}
        ]
      }

      bob_busy = %Tempo.IntervalSet{
        intervals: [
          %Interval{from: ~o"2026-06-15T11", to: ~o"2026-06-15T12"},
          %Interval{from: ~o"2026-06-15T15:30", to: ~o"2026-06-15T16"}
        ]
      }

      # "Free time" is the instant-level remainder of the workday
      # after busy periods, so we use `difference/2` (trimmed)
      # and `intersection/2` (trimmed) — both produce the
      # covered-time fragments.
      work = ~o"2026-06-15T09/2026-06-15T17"
      {:ok, alice_free} = Tempo.difference(work, alice_busy)
      {:ok, bob_free} = Tempo.difference(work, bob_busy)
      {:ok, mutual} = Tempo.intersection(alice_free, bob_free)

      one_hour_slots =
        mutual
        |> IntervalSet.to_list()
        |> Enum.filter(&Tempo.at_least?(&1, ~o"PT1H"))

      assert length(one_hour_slots) == 3
    end

    test "candidate scheduling via within?/2" do
      window = %Interval{from: ~o"2026-06-15T09", to: ~o"2026-06-15T17"}

      bookable_candidates =
        [
          %Interval{from: ~o"2026-06-15T09", to: ~o"2026-06-15T10"},
          %Interval{from: ~o"2026-06-15T16", to: ~o"2026-06-15T17"},
          %Interval{from: ~o"2026-06-15T08", to: ~o"2026-06-15T10"}
        ]
        |> Enum.filter(&Tempo.within?(&1, window))

      assert length(bookable_candidates) == 2
    end
  end

  describe "endpoints/1" do
    test "returns {from, to} as a named accessor" do
      iv = %Interval{from: ~o"2026-06-15", to: ~o"2026-06-20"}

      {from, to} = Interval.endpoints(iv)
      assert Tempo.day(from) == 15
      assert Tempo.day(to) == 20
    end

    test "preserves :undefined endpoints" do
      assert {:undefined, _} =
               Interval.endpoints(%Interval{from: :undefined, to: ~o"2026-06-20"})

      assert {_, :undefined} =
               Interval.endpoints(%Interval{from: ~o"2026-06-15", to: :undefined})
    end
  end

  describe "empty?/1 and duration/1 — degenerate and inverted intervals" do
    # Under the half-open `[from, to)` convention, an interval
    # with `from == to` is degenerate (contains no instants) and
    # an interval with `from > to` is inverted (also contains no
    # instants). Both should be treated as empty — not as
    # intervals with "negative" duration.

    test "empty?/1 returns true for from == to" do
      iv = %Interval{from: ~o"2024-06-15", to: ~o"2024-06-15"}
      assert Interval.empty?(iv)
    end

    test "empty?/1 returns true for from > to (inverted)" do
      iv = %Interval{from: ~o"2024-06-20", to: ~o"2024-06-15"}
      assert Interval.empty?(iv)
    end

    test "duration/1 returns zero for degenerate intervals" do
      iv = %Interval{from: ~o"2024-06-15", to: ~o"2024-06-15"}
      assert Interval.duration(iv) == %Tempo.Duration{time: [second: 0]}
    end

    test "duration/1 returns zero for inverted intervals (no negative durations)" do
      iv = %Interval{from: ~o"2024-06-20", to: ~o"2024-06-15"}
      assert Interval.duration(iv) == %Tempo.Duration{time: [second: 0]}
    end

    test "non-empty intervals still compute their span correctly" do
      iv = %Interval{from: ~o"2024-06-15", to: ~o"2024-06-20"}
      refute Interval.empty?(iv)
      assert Interval.duration(iv) == %Tempo.Duration{time: [second: 432_000]}
    end
  end

  describe "duration/1 — cross-calendar rejection" do
    # Tempo.Interval.duration/1 cannot compute a meaningful
    # duration when endpoints are in different calendars because
    # `to_utc_seconds/1` projects each via its own epoch. Refuse
    # explicitly rather than silently compute garbage.

    test "raises when from and to are in different calendars" do
      {:ok, hebrew} = Tempo.from_iso8601("5786-10-30[u-ca=hebrew]")
      gregorian = ~o"2026-06-15"
      iv = %Interval{from: hebrew, to: gregorian}

      assert_raise ArgumentError, ~r/same calendar/, fn ->
        Interval.duration(iv)
      end
    end

    test "error message points at set operations as the cross-calendar path" do
      {:ok, hebrew} = Tempo.from_iso8601("5786-10-30[u-ca=hebrew]")
      iv = %Interval{from: hebrew, to: ~o"2026-06-15"}

      try do
        Interval.duration(iv)
        flunk("expected ArgumentError")
      rescue
        e in ArgumentError ->
          assert Exception.message(e) =~ "Tempo.intersection/2"
          assert Exception.message(e) =~ "Tempo.difference/2"
      end
    end

    test "same-calendar intervals still compute duration normally" do
      iv = %Interval{from: ~o"2026-06-15", to: ~o"2026-06-20"}
      assert %Tempo.Duration{} = Interval.duration(iv)
    end
  end

  describe "resolution/1" do
    test "day-spanning interval has :day resolution" do
      iv = %Interval{from: ~o"2026-06-15", to: ~o"2026-06-16"}
      assert Interval.resolution(iv) == :day
    end

    test "month-spanning interval has :month resolution" do
      {:ok, iv} = Tempo.to_interval(~o"2026-06")
      assert Interval.resolution(iv) == :month
    end

    test "year-spanning interval has :year resolution" do
      {:ok, iv} = Tempo.to_interval(~o"2026")
      assert Interval.resolution(iv) == :year
    end

    test "sub-day interval has :hour resolution" do
      iv = %Interval{from: ~o"2026-06-15T10", to: ~o"2026-06-15T11"}
      assert Interval.resolution(iv) == :hour
    end

    test "unbounded interval returns :undefined" do
      assert Interval.resolution(%Interval{from: :undefined, to: ~o"2026-06-20"}) ==
               :undefined

      assert Interval.resolution(%Interval{from: ~o"2026-06-15", to: :undefined}) ==
               :undefined
    end
  end

  describe "graded relations over ±-bearing intervals" do
    test "overlap_certainty is three-valued (the step-0 oracle)" do
      # Disjoint even at closest drift, overlapping regardless, and the
      # borderline where the margins make overlap possible-but-not-sure.
      assert Interval.overlap_certainty(~o"2000±1Y", ~o"2010±1Y") == :impossible
      assert Interval.overlap_certainty(~o"2000±1Y", ~o"2001±1Y") == :possible

      wide = Interval.new!(from: ~o"1990", to: ~o"2010")
      assert Interval.overlap_certainty(~o"2000±1Y", wide) == :certain
    end

    test "within_certainty is three-valued" do
      assert Interval.within_certainty(~o"2000Y6M", ~o"2000Y") == :certain
      assert Interval.within_certainty(~o"2000±1Y", ~o"2000Y") == :possible
      assert Interval.within_certainty(~o"2000±1Y", ~o"2010Y") == :impossible
    end

    test "relation_certainty accepts an atom or a list of relations" do
      assert Interval.relation_certainty(~o"2000±1Y", ~o"2010±1Y", :precedes) == :certain
      assert Interval.relation_certainty(~o"2000Y", ~o"2000Y", :equals) == :certain
      assert Interval.relation_certainty(~o"2000Y", ~o"2000Y", [:equals, :during]) == :certain
    end

    test "modal predicates read off the certainty" do
      assert Interval.certainly_overlaps?(~o"2000Y", ~o"2000Y")
      refute Interval.certainly_overlaps?(~o"2000±1Y", ~o"2001±1Y")
      assert Interval.possibly_overlaps?(~o"2000±1Y", ~o"2001±1Y")
      refute Interval.possibly_overlaps?(~o"2000±1Y", ~o"2010±1Y")
    end

    test "crisp operands degrade exactly to the boolean predicates" do
      crisp_pairs = [
        {~o"2000Y", ~o"2000Y"},
        {~o"2000Y", ~o"2001Y"},
        {~o"2000Y6M", ~o"2000Y"},
        {~o"2005Y", ~o"2000Y"},
        {~o"2000Y", ~o"2000Y6M"}
      ]

      for {a, b} <- crisp_pairs do
        assert Interval.certainly_overlaps?(a, b) == Tempo.overlaps?(a, b)
        assert Interval.certainly_within?(a, b) == Tempo.within?(a, b)
        # A crisp verdict is never merely :possible.
        assert Interval.overlap_certainty(a, b) in [:certain, :impossible]
      end
    end

    test "open-ended and multi-member operands return an error" do
      open = %Interval{from: ~o"2000", to: :undefined}
      assert {:error, _} = Interval.overlap_certainty(open, ~o"2000Y")
      refute Interval.certainly_overlaps?(open, ~o"2000Y")
    end

    test "before/after modal predicates" do
      assert Interval.certainly_before?(~o"2000±1Y", ~o"2010±1Y")
      refute Interval.certainly_before?(~o"2000±1Y", ~o"2001±1Y")
      assert Interval.possibly_before?(~o"2000±1Y", ~o"2001±1Y")

      assert Interval.certainly_after?(~o"2010±1Y", ~o"2000±1Y")
      assert Interval.possibly_after?(~o"2001±1Y", ~o"2000±1Y")
    end

    test "before/after degrade exactly to the crisp before?/after?" do
      crisp_pairs = [
        {~o"2000Y", ~o"2005Y"},
        {~o"2005Y", ~o"2000Y"},
        {~o"2000Y", ~o"2000Y"},
        {~o"2000Y", ~o"2001Y"}
      ]

      for {a, b} <- crisp_pairs do
        assert Interval.certainly_before?(a, b) == Interval.before?(a, b)
        assert Interval.certainly_after?(a, b) == Interval.after?(a, b)
      end
    end

    test "verdicts use the exact neighbourhood, not the endpoint-range over-approximation" do
      # Two width-1 year values can only stand in the five year-granularity
      # relations. The exact placement enumeration knows this, so the target
      # set is fully covered (`:certain`). An independent-endpoint envelope
      # would spuriously admit overlaps/during/contains and report `:possible`.
      year_relations = [:equals, :meets, :met_by, :precedes, :preceded_by]
      assert Interval.relation_certainty(~o"2000±5Y", ~o"2000±5Y", year_relations) == :certain
    end
  end
end
