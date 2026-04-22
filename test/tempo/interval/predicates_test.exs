defmodule Tempo.Interval.PredicatesTest do
  use ExUnit.Case, async: true
  import Tempo.Sigil

  alias Tempo.Interval

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

  describe "relation predicates — thin wrappers over compare/2" do
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
        Tempo.IntervalSet.new!(
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

      # "Free time" is an instant-level query — the uncovered
      # portions of the workday — so we use `split_difference/2`
      # (trim) rather than `difference/2` (member-filter).
      # Likewise `overlap_trim/2` for the instant-level
      # intersection of the two free-time spans.
      work = ~o"2026-06-15T09/2026-06-15T17"
      {:ok, alice_free} = Tempo.split_difference(work, alice_busy)
      {:ok, bob_free} = Tempo.split_difference(work, bob_busy)
      {:ok, mutual} = Tempo.overlap_trim(alice_free, bob_free)

      one_hour_slots =
        mutual
        |> Tempo.IntervalSet.to_list()
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

      {from, to} = Tempo.Interval.endpoints(iv)
      assert Tempo.day(from) == 15
      assert Tempo.day(to) == 20
    end

    test "preserves :undefined endpoints" do
      assert {:undefined, _} =
               Tempo.Interval.endpoints(%Interval{from: :undefined, to: ~o"2026-06-20"})

      assert {_, :undefined} =
               Tempo.Interval.endpoints(%Interval{from: ~o"2026-06-15", to: :undefined})
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
        Tempo.Interval.duration(iv)
      end
    end

    test "error message points at set operations as the cross-calendar path" do
      {:ok, hebrew} = Tempo.from_iso8601("5786-10-30[u-ca=hebrew]")
      iv = %Interval{from: hebrew, to: ~o"2026-06-15"}

      try do
        Tempo.Interval.duration(iv)
        flunk("expected ArgumentError")
      rescue
        e in ArgumentError ->
          assert Exception.message(e) =~ "Tempo.intersection/2"
          assert Exception.message(e) =~ "Tempo.difference/2"
      end
    end

    test "same-calendar intervals still compute duration normally" do
      iv = %Interval{from: ~o"2026-06-15", to: ~o"2026-06-20"}
      assert %Tempo.Duration{} = Tempo.Interval.duration(iv)
    end
  end

  describe "resolution/1" do
    test "day-spanning interval has :day resolution" do
      iv = %Interval{from: ~o"2026-06-15", to: ~o"2026-06-16"}
      assert Tempo.Interval.resolution(iv) == :day
    end

    test "month-spanning interval has :month resolution" do
      {:ok, iv} = Tempo.to_interval(~o"2026-06")
      assert Tempo.Interval.resolution(iv) == :month
    end

    test "year-spanning interval has :year resolution" do
      {:ok, iv} = Tempo.to_interval(~o"2026")
      assert Tempo.Interval.resolution(iv) == :year
    end

    test "sub-day interval has :hour resolution" do
      iv = %Interval{from: ~o"2026-06-15T10", to: ~o"2026-06-15T11"}
      assert Tempo.Interval.resolution(iv) == :hour
    end

    test "unbounded interval returns :undefined" do
      assert Tempo.Interval.resolution(%Interval{from: :undefined, to: ~o"2026-06-20"}) ==
               :undefined

      assert Tempo.Interval.resolution(%Interval{from: ~o"2026-06-15", to: :undefined}) ==
               :undefined
    end
  end
end
