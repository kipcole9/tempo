import Tempo.Sigils

defmodule Verify do
  def check(label, actual, expected) do
    if actual == expected do
      IO.puts("OK  #{label}")
    else
      IO.puts("FAIL #{label}")
      IO.puts("     expected: #{inspect(expected)}")
      IO.puts("     actual:   #{inspect(actual)}")
      System.halt(1)
    end
  end
end

# §5 union — merge two overlapping intervals
a = ~o"2026-06-01/2026-06-15"
b = ~o"2026-06-10/2026-06-20"
{:ok, merged} = Tempo.union(a, b)
# The cookbook says count = 1, but union is member-preserving — count is 2.
# After coalesce, count is 1.
Verify.check("union member count", Tempo.IntervalSet.count(merged), 2)
Verify.check("union coalesced count",
  merged |> Tempo.IntervalSet.coalesce() |> Tempo.IntervalSet.count(), 1)

# §5 intersection — find the overlap
{:ok, overlap} = Tempo.intersection(a, b)
[span] = Tempo.IntervalSet.to_list(overlap)
{from, to} = Tempo.Interval.endpoints(span)
Verify.check("intersection day endpoints", {Tempo.day(from), Tempo.day(to)}, {10, 15})

# §5 difference — workday minus lunch
work_day = ~o"2026-06-15T09/2026-06-15T17"
lunch = ~o"2026-06-15T12/2026-06-15T13"
{:ok, free} = Tempo.difference(work_day, lunch)
Verify.check("workday minus lunch count", Tempo.IntervalSet.count(free), 2)

[morning, afternoon] = Tempo.IntervalSet.to_list(free)
{m_from, m_to} = Tempo.Interval.endpoints(morning)
{a_from, a_to} = Tempo.Interval.endpoints(afternoon)
Verify.check("morning hours", {Tempo.hour(m_from), Tempo.hour(m_to)}, {9, 12})
Verify.check("afternoon hours", {Tempo.hour(a_from), Tempo.hour(a_to)}, {13, 17})

# §5 symmetric_difference (with the same a, b from above)
{:ok, set} = Tempo.symmetric_difference(a, b)
# Trimmed edges: June 1–10 and June 15–20 → 2 intervals.
Verify.check("symmetric_difference of overlapping intervals count",
  Tempo.IntervalSet.count(set), 2)

# §6 select workdays of a month
{:ok, workdays} = Tempo.select(~o"2026-06", Tempo.workdays(:US))
Verify.check("June 2026 US workdays count", Tempo.IntervalSet.count(workdays), 22)

# §6 compose select with set ops — workdays minus vacation
{:ok, vacation} = Tempo.to_interval_set(~o"2026-06-15/2026-06-20")
{:ok, available} = Tempo.difference(workdays, vacation)
# 22 workdays - 5 workdays in vacation week = 17 available.
Verify.check("June workdays minus vacation count",
  Tempo.IntervalSet.count(available), 17)

# Also verify members_outside gives same result for this case
{:ok, available_mo} = Tempo.members_outside(workdays, vacation)
Verify.check("members_outside same numeric result",
  Tempo.IntervalSet.count(available_mo), 17)

# §10 Find when two people are both free for at least 1 hour — synthetic data
work = ~o"2026-06-15T09/2026-06-15T17"
ada = Tempo.IntervalSet.new!([
  %Tempo.Interval{from: ~o"2026-06-15T10", to: ~o"2026-06-15T11"},
  %Tempo.Interval{from: ~o"2026-06-15T14", to: ~o"2026-06-15T15"}
])
grace = Tempo.IntervalSet.new!([
  %Tempo.Interval{from: ~o"2026-06-15T11", to: ~o"2026-06-15T12"},
  %Tempo.Interval{from: ~o"2026-06-15T15:30", to: ~o"2026-06-15T16"}
])
{:ok, ada_free} = Tempo.difference(work, ada)
{:ok, grace_free} = Tempo.difference(work, grace)
{:ok, mutual} = Tempo.intersection(ada_free, grace_free)
slots =
  mutual
  |> Tempo.IntervalSet.to_list()
  |> Enum.filter(&Tempo.at_least?(&1, ~o"PT1H"))
# Expect 09-10, 12-14, 16-17 → 3 slots ≥ 1 hour.
Verify.check("mutual free slots ≥ 1h count", length(slots), 3)

IO.puts("\nAll cookbook examples verified.")
