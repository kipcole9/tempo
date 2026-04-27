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

# §1.1 Resolution — finer wins
{:ok, set} = Tempo.intersection(~o"2022Y", ~o"2022-06-15")
Verify.check("intersection year+day count", Tempo.IntervalSet.count(set), 1)

# §1.3 Calendar
hebrew_day = Tempo.new!(year: 5782, month: 10, day: 16, calendar: Calendrical.Hebrew)
Verify.check("hebrew overlaps gregorian day", Tempo.overlaps?(hebrew_day, ~o"2022-06-15"), true)
Verify.check("hebrew disjoint gregorian month", Tempo.disjoint?(hebrew_day, ~o"2023-01"), true)

# §2 Anchor-class — bound option
case Tempo.intersection(~o"2026-01-04", ~o"T10:30") do
  {:error, _} -> IO.puts("OK  no-bound cross-axis returns error")
  other ->
    IO.puts("FAIL no-bound cross-axis returned: #{inspect(other)}")
    System.halt(1)
end

{:ok, slot} = Tempo.intersection(~o"2026-01-04", ~o"T10:30", bound: ~o"2026-01-04")
Verify.check("bound cross-axis count", Tempo.IntervalSet.count(slot), 1)

# §2 anchor/2
Verify.check("anchor", Tempo.anchor(~o"2026-01-04", ~o"T10:30"), ~o"2026Y1M4DT10H30M")

# §3 Union member-preserving
{:ok, u} = Tempo.union(~o"2022Y", ~o"2023Y")
Verify.check("union count distinct", Tempo.IntervalSet.count(u), 2)
Verify.check("union coalesced count", u |> Tempo.IntervalSet.coalesce() |> Tempo.IntervalSet.count(), 1)

# §3 Intersection trimmed
{:ok, r} = Tempo.intersection(~o"2022Y", ~o"2022-06-15")
[iv] = Tempo.IntervalSet.to_list(r)
Verify.check("intersection trimmed day", Tempo.day(iv), 15)

# §3 members_overlapping
{:ok, r} = Tempo.members_overlapping(~o"2022Y", ~o"2022-06-15")
[iv] = Tempo.IntervalSet.to_list(r)
Verify.check("members_overlapping kept whole — year", Tempo.year(iv), 2022)

# §3 Complement
{:ok, r} = Tempo.complement(~o"2022-06", bound: ~o"2022Y")
Verify.check("complement count", Tempo.IntervalSet.count(r), 2)

# §3 Difference trimmed
{:ok, r} = Tempo.difference(~o"2022Y", ~o"2022-06")
Verify.check("difference trimmed count", Tempo.IntervalSet.count(r), 2)

# §3 members_outside
{:ok, r} = Tempo.members_outside(~o"2022Y", ~o"2022-06")
Verify.check("members_outside drops year", r.intervals, [])

# §3 Symmetric difference trimmed
{:ok, a} = Tempo.from_iso8601("2022-01/2022-07")
{:ok, b} = Tempo.from_iso8601("2022-04/2022-10")
{:ok, r} = Tempo.symmetric_difference(a, b)
Verify.check("symmetric_difference trimmed edges", Tempo.IntervalSet.count(r), 2)

# §3 members_in_exactly_one
{:ok, r} = Tempo.members_in_exactly_one(~o"2020Y", ~o"2022Y")
Verify.check("members_in_exactly_one disjoint", Tempo.IntervalSet.count(r), 2)

# §3 Predicates
Verify.check("disjoint? 2020 vs 2022", Tempo.disjoint?(~o"2020Y", ~o"2022Y"), true)
Verify.check("overlaps? year vs month", Tempo.overlaps?(~o"2022Y", ~o"2022-06"), true)
Verify.check("subset? month within year", Tempo.subset?(~o"2022-06", ~o"2022Y"), true)
Verify.check("contains? year contains month", Tempo.contains?(~o"2022Y", ~o"2022-06"), true)
Verify.check("equal? year vs explicit range",
  Tempo.equal?(~o"2022Y", Tempo.from_iso8601!("2022-01-01/2023-01-01")),
  true)

IO.puts("\nAll set-operations.md examples verified.")
