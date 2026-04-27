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

# ===== livebook/tempo_tour.livemd =====

# Set ops on shared a, b
a = ~o"2026-06-01/2026-06-15"
b = ~o"2026-06-10/2026-06-20"

# Union — both kept distinct
{:ok, both} = Tempo.union(a, b)
Verify.check("livebook union both count", Tempo.IntervalSet.count(both), 2)

# Coalesced — single span
coalesced = Tempo.IntervalSet.coalesce(both)
Verify.check("livebook union coalesced count", Tempo.IntervalSet.count(coalesced), 1)

# Intersection — overlap
{:ok, overlap} = Tempo.intersection(a, b)
[span] = Tempo.IntervalSet.to_list(overlap)
{from, to} = Tempo.Interval.endpoints(span)
Verify.check("livebook intersection day endpoints", {Tempo.day(from), Tempo.day(to)}, {10, 15})

# Difference — workday minus lunch
work_day = ~o"2026-06-15T09/2026-06-15T17"
lunch = ~o"2026-06-15T12/2026-06-15T13"
{:ok, free} = Tempo.difference(work_day, lunch)
Verify.check("livebook free count", Tempo.IntervalSet.count(free), 2)

# §"Compose with set operations" — workdays minus vacation
{:ok, june_workdays} = Tempo.select(~o"2026-06", Tempo.workdays(:US))
{:ok, vacation} = Tempo.to_interval_set(~o"2026-06-15/2026-06-20")
{:ok, available} = Tempo.difference(june_workdays, vacation)
Verify.check("livebook june workdays minus vacation",
  Tempo.IntervalSet.count(available), 17)

# Mutual free time scenario
alice = Tempo.IntervalSet.new!([
  Tempo.Interval.new!(from: ~o"2026-06-15T10", to: ~o"2026-06-15T11", metadata: %{who: "Alice"}),
  Tempo.Interval.new!(from: ~o"2026-06-15T14", to: ~o"2026-06-15T15", metadata: %{who: "Alice"})
])
bob = Tempo.IntervalSet.new!([
  Tempo.Interval.new!(from: ~o"2026-06-15T11", to: ~o"2026-06-15T12", metadata: %{who: "Bob"}),
  Tempo.Interval.new!(from: ~o"2026-06-15T15:30", to: ~o"2026-06-15T16", metadata: %{who: "Bob"})
])
work_hours = ~o"2026-06-15T09/2026-06-15T17"
{:ok, alice_free} = Tempo.difference(work_hours, alice)
{:ok, bob_free} = Tempo.difference(work_hours, bob)
{:ok, mutual} = Tempo.intersection(alice_free, bob_free)
bookable = Tempo.IntervalSet.filter(mutual, &Tempo.at_least?(&1, ~o"PT1H"))
# Mutual free fragments: 09-10, 12-14, 16-17 = 3 windows ≥1h
Verify.check("livebook bookable count", Tempo.IntervalSet.count(bookable), 3)

# ===== guides/workdays-and-weekends.md =====
# Workdays that overlap a specific window
{:ok, q2_workdays} = Tempo.members_overlapping(june_workdays, ~o"2026-04/2026-07")
# June is in Q2 (Apr-Jun), so all 22 June workdays survive.
Verify.check("workdays-and-weekends q2 workdays count",
  Tempo.IntervalSet.count(q2_workdays), 22)

# ===== guides/holidays.md =====
# Q3 workdays minus 2 federal holidays scenario — synthetic stand-in
q3 = ~o"2026-07-01/2026-10-01"
{:ok, q3_workdays} = Tempo.select(q3, Tempo.workdays(:US))
# Synthetic holidays: July 3 (in lieu of July 4 which is Saturday), and Sept 7 Labor Day.
holidays = Tempo.IntervalSet.new!([
  %Tempo.Interval{from: ~o"2026-07-03", to: ~o"2026-07-04"},
  %Tempo.Interval{from: ~o"2026-09-07", to: ~o"2026-09-08"}
])
{:ok, net_workdays} = Tempo.members_outside(q3_workdays, holidays)
# 66 Q3 workdays - 2 holidays = 64
Verify.check("holidays.md net Q3 workdays count",
  Tempo.IntervalSet.count(net_workdays), 64)

# Same numeric result with trimmed difference
{:ok, net_via_diff} = Tempo.difference(q3_workdays, holidays)
Verify.check("holidays.md trimmed difference matches members_outside",
  Tempo.IntervalSet.count(net_via_diff), 64)

# Q3 holidays via members_overlapping — both holidays are in Q3
q3_window = ~o"2026-07/2026-10"
{:ok, q3_holidays} = Tempo.members_overlapping(holidays, q3_window)
Verify.check("holidays.md q3_holidays count",
  Tempo.IntervalSet.count(q3_holidays), 2)

IO.puts("\nAll livebook + workdays + holidays examples verified.")
