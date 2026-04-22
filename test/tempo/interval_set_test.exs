defmodule Tempo.IntervalSet.Test do
  use ExUnit.Case, async: true
  import Tempo.Sigil

  # `%Tempo.IntervalSet{}` is the multi-interval value. The tests
  # below cover the constructor invariants (sort + coalesce),
  # the Enumerable protocol (walks each interval in time order),
  # and error cases (open-ended inputs).

  describe "new/1 — sort and coalesce" do
    test "separate non-touching intervals remain separate, in sorted order" do
      jan = interval(~o"2022Y1M")
      mar = interval(~o"2022Y3M")
      may = interval(~o"2022Y5M")

      {:ok, set} = Tempo.IntervalSet.new([may, jan, mar])

      assert length(set.intervals) == 3

      assert Enum.map(set.intervals, & &1.from.time) == [
               [year: 2022, month: 1, day: 1],
               [year: 2022, month: 3, day: 1],
               [year: 2022, month: 5, day: 1]
             ]
    end

    test "touching intervals coalesce (half-open semantics)" do
      # `[Jan, Feb) ++ [Feb, Mar)` = `[Jan, Mar)`.
      jan = interval(~o"2022Y1M")
      feb = interval(~o"2022Y2M")

      {:ok, set} = Tempo.IntervalSet.new([jan, feb])

      assert length(set.intervals) == 1
      [interval] = set.intervals
      assert interval.from.time == [year: 2022, month: 1, day: 1]
      assert interval.to.time == [year: 2022, month: 3, day: 1]
    end

    test "overlapping intervals coalesce" do
      jan = interval(~o"2022Y1M")
      q1 = %Tempo.Interval{from: ~o"2022Y1M15D", to: ~o"2022Y3M15D"}

      {:ok, set} = Tempo.IntervalSet.new([jan, q1])

      assert length(set.intervals) == 1
      [interval] = set.intervals
      assert interval.from.time == [year: 2022, month: 1, day: 1]
      assert interval.to.time == [year: 2022, month: 3, day: 15]
    end

    test "three touching intervals coalesce to one" do
      # Known from the integration tests but verified here in
      # isolation against the constructor itself.
      {:ok, tempo} = Tempo.from_iso8601("{2020,2021,2022}Y")
      {:ok, %Tempo.IntervalSet{intervals: intervals}} = Tempo.to_interval(tempo)
      assert length(intervals) == 1
    end

    test "empty list yields an empty set" do
      assert {:ok, %Tempo.IntervalSet{intervals: []}} = Tempo.IntervalSet.new([])
    end

    test "rejects open-ended intervals" do
      {:ok, open} = Tempo.from_iso8601("1985/..")
      assert {:error, message} = Tempo.IntervalSet.new([open])
      assert Exception.message(message) =~ "open-ended"
    end
  end

  describe "new!/1" do
    test "raises on open-ended input" do
      {:ok, open} = Tempo.from_iso8601("../1985")

      assert_raise ArgumentError, fn ->
        Tempo.IntervalSet.new!([open])
      end
    end

    test "returns the set directly on success" do
      assert %Tempo.IntervalSet{} = Tempo.IntervalSet.new!([interval(~o"2022Y1M")])
    end
  end

  describe "Enumerable protocol — walks sub-points" do
    # An IntervalSet's Enumerable is consistent with Tempo and
    # Tempo.Interval: iterating walks the sub-points at the
    # next-finer resolution, not the member intervals
    # themselves. For member-interval iteration use
    # `Tempo.IntervalSet.to_list/1`.

    test "iterates each interval's values in time order" do
      jan = interval(~o"2022Y1M")
      mar = interval(~o"2022Y3M")
      {:ok, set} = Tempo.IntervalSet.new([jan, mar])

      list = Enum.take(set, 35)
      # First 31 days = Jan. Day 32 must be Mar 1 (crossing the
      # non-touching boundary skips Feb entirely).
      assert length(list) == 35
      assert Enum.at(list, 0).time == [year: 2022, month: 1, day: 1]
      assert Enum.at(list, 30).time == [year: 2022, month: 1, day: 31]
      assert Enum.at(list, 31).time == [year: 2022, month: 3, day: 1]
    end

    test "Enum.to_list yields the full sequence" do
      jan = interval(~o"2022Y1M")
      mar = interval(~o"2022Y3M")
      {:ok, set} = Tempo.IntervalSet.new([jan, mar])

      # Jan (31 days) + Mar (31 days) = 62.
      assert length(Enum.to_list(set)) == 62
    end

    test "halt during iteration works" do
      jan = interval(~o"2022Y1M")
      mar = interval(~o"2022Y3M")
      {:ok, set} = Tempo.IntervalSet.new([jan, mar])

      # `Enum.find/2` halts as soon as the predicate matches.
      found = Enum.find(set, fn v -> v.time[:day] == 15 end)
      assert found.time == [year: 2022, month: 1, day: 15]
    end

    test "count/member?/slice return {:error, __MODULE__}" do
      {:ok, set} = Tempo.IntervalSet.new([interval(~o"2022Y1M")])
      assert Enumerable.count(set) == {:error, Enumerable.Tempo.IntervalSet}
      assert Enumerable.member?(set, :anything) == {:error, Enumerable.Tempo.IntervalSet}
      assert Enumerable.slice(set) == {:error, Enumerable.Tempo.IntervalSet}
    end
  end

  describe "to_list/1 — member intervals as a plain list" do
    test "returns the constituent %Tempo.Interval{} values" do
      jan = interval(~o"2022Y1M")
      mar = interval(~o"2022Y3M")
      {:ok, set} = Tempo.IntervalSet.new([jan, mar])

      assert [a, b] = Tempo.IntervalSet.to_list(set)
      assert %Tempo.Interval{} = a
      assert a.from.time == [year: 2022, month: 1, day: 1]
      assert b.from.time == [year: 2022, month: 3, day: 1]
    end

    test "pipes into Enum for member-level filtering" do
      jan = interval(~o"2022Y1M")
      mar = interval(~o"2022Y3M")
      {:ok, set} = Tempo.IntervalSet.new([jan, mar])

      long_enough =
        set
        |> Tempo.IntervalSet.to_list()
        |> Enum.filter(&Tempo.at_least?(&1, ~o"P28D"))

      assert length(long_enough) == 2
    end

    test "empty set → empty list" do
      {:ok, set} = Tempo.IntervalSet.new([])
      assert Tempo.IntervalSet.to_list(set) == []
    end
  end

  describe "count/1" do
    test "returns the number of member intervals" do
      jan = interval(~o"2022Y1M")
      mar = interval(~o"2022Y3M")
      may = interval(~o"2022Y5M")
      {:ok, set} = Tempo.IntervalSet.new([jan, mar, may])

      assert Tempo.IntervalSet.count(set) == 3
    end

    test "returns 0 for an empty set" do
      {:ok, set} = Tempo.IntervalSet.new([])
      assert Tempo.IntervalSet.count(set) == 0
    end
  end

  describe "map/2" do
    test "applies the mapper to each member interval" do
      jan = interval(~o"2022Y1M")
      mar = interval(~o"2022Y3M")
      {:ok, set} = Tempo.IntervalSet.new([jan, mar])

      assert Tempo.IntervalSet.map(set, &Tempo.month/1) == [1, 3]
    end

    test "mappers can return arbitrary values (not just intervals)" do
      jan = interval(~o"2022Y1M")
      feb = interval(~o"2022Y4M")
      {:ok, set} = Tempo.IntervalSet.new([jan, feb])

      result = Tempo.IntervalSet.map(set, fn iv -> {Tempo.year(iv), Tempo.month(iv)} end)
      assert result == [{2022, 1}, {2022, 4}]
    end

    test "empty set maps to empty list" do
      {:ok, set} = Tempo.IntervalSet.new([])
      assert Tempo.IntervalSet.map(set, & &1) == []
    end
  end

  describe "filter/2" do
    test "keeps only members where the predicate returns truthy" do
      jan = interval(~o"2022Y1M")
      mar = interval(~o"2022Y3M")
      {:ok, set} = Tempo.IntervalSet.new([jan, mar])

      only_january = Tempo.IntervalSet.filter(set, &(Tempo.month(&1) == 1))

      assert Tempo.IntervalSet.count(only_january) == 1
      [only] = Tempo.IntervalSet.to_list(only_january)
      assert Tempo.month(only) == 1
    end

    test "returns an IntervalSet, not a plain list" do
      jan = interval(~o"2022Y1M")
      {:ok, set} = Tempo.IntervalSet.new([jan])

      assert %Tempo.IntervalSet{} = Tempo.IntervalSet.filter(set, fn _ -> true end)
    end

    test "filtering to empty still returns an IntervalSet" do
      jan = interval(~o"2022Y1M")
      {:ok, set} = Tempo.IntervalSet.new([jan])

      empty = Tempo.IntervalSet.filter(set, fn _ -> false end)
      assert %Tempo.IntervalSet{} = empty
      assert Tempo.IntervalSet.count(empty) == 0
    end
  end

  describe "to_interval/1 routing — multi-interval shapes" do
    test "range in a time slot → IntervalSet (coalesced if touching)" do
      {:ok, tempo} = Tempo.from_iso8601("2022Y{1..3}M")
      {:ok, %Tempo.IntervalSet{intervals: [q1]}} = Tempo.to_interval(tempo)
      assert q1.from.time == [year: 2022, month: 1, day: 1]
      assert q1.to.time == [year: 2022, month: 4, day: 1]
    end

    test "stepped range → multiple disjoint intervals" do
      {:ok, tempo} = Tempo.from_iso8601("2022Y{1..-1//3}M")
      {:ok, %Tempo.IntervalSet{intervals: intervals}} = Tempo.to_interval(tempo)
      assert length(intervals) == 4
      assert Enum.map(intervals, & &1.from.time[:month]) == [1, 4, 7, 10]
    end

    test "cartesian range expansion with partial coalescing" do
      # `{1..2}M{1..2}D` gives four points: Jan 1, Jan 2, Feb 1,
      # Feb 2. Jan 1 and Jan 2 are touching; Feb 1 and Feb 2 are
      # touching; Jan 2 and Feb 1 don't touch (Jan 3..Feb 1 gap).
      {:ok, tempo} = Tempo.from_iso8601("2022Y{1..2}M{1..2}D")
      {:ok, %Tempo.IntervalSet{intervals: intervals}} = Tempo.to_interval(tempo)
      assert length(intervals) == 2
    end

    test "scalar input still returns a single Interval" do
      {:ok, tempo} = Tempo.from_iso8601("2022Y6M")
      assert {:ok, %Tempo.Interval{}} = Tempo.to_interval(tempo)
    end
  end

  describe "to_interval_set/1" do
    test "wraps a single interval in a 1-element set" do
      {:ok, tempo} = Tempo.from_iso8601("2022Y6M")
      {:ok, %Tempo.IntervalSet{intervals: intervals}} = Tempo.to_interval_set(tempo)
      assert length(intervals) == 1
    end

    test "passes IntervalSet through unchanged" do
      {:ok, tempo} = Tempo.from_iso8601("2022Y{1..-1//3}M")
      {:ok, set} = Tempo.to_interval_set(tempo)
      assert length(set.intervals) == 4

      assert {:ok, ^set} = Tempo.to_interval_set(set)
    end

    test "errors on a bare Duration" do
      {:ok, duration} = Tempo.from_iso8601("P3M")
      assert {:error, _} = Tempo.to_interval_set(duration)
    end

    test "errors on a one-of Tempo.Set (epistemic)" do
      {:ok, set} = Tempo.from_iso8601("[2020Y,2021Y,2022Y]")
      assert {:error, message} = Tempo.to_interval_set(set)
      assert Exception.message(message) =~ "epistemic"
    end
  end

  ## Helpers

  defp interval(tempo) do
    {:ok, interval} = Tempo.to_interval(tempo)
    interval
  end
end
