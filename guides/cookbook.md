# Tempo Cookbook

Task-oriented recipes for common time-and-calendar problems. Each recipe states the problem, shows the solution, and explains why it works. Copy, adapt, iterate.

Every example uses the `~o` sigil (`import Tempo.Sigil`). In iex, paste the setup once and the rest of the snippets run against it:

```elixir
import Tempo.Sigil
```

---

## Contents

1. [Parsing and construction](#1-parsing-and-construction)
2. [Exploring a value](#2-exploring-a-value)
3. [Iteration](#3-iteration)
4. [Comparison and predicates](#4-comparison-and-predicates)
5. [Set operations](#5-set-operations)
6. [Recurring events (RRULE)](#6-recurring-events-rrule)
7. [iCalendar import](#7-icalendar-import)
8. [Cross-calendar and cross-timezone](#8-cross-calendar-and-cross-timezone)
9. [Archaeological / approximate dates](#9-archaeological--approximate-dates)
10. [Real-world scenarios](#10-real-world-scenarios)

---

## 1. Parsing and construction

### How do I parse an ISO 8601 date?

```elixir
iex> ~o"2026-06-15"
~o"2026Y6M15D"
```

The sigil output uses ISO 8601-2's unit-suffix form (`Y`/`M`/`D`/`H`/…) which disambiguates months from minutes.

### How do I convert an Elixir `Date`, `Time`, `NaiveDateTime`, or `DateTime` to a Tempo?

```elixir
iex> Tempo.from_elixir(~D[2026-06-15])
~o"2026Y6M15D"

iex> Tempo.from_elixir(~U[2026-06-15 10:30:00Z])
# Hour-resolution datetime with zone_id "Etc/UTC"
```

`from_elixir/2` accepts a `:resolution` option when you want to coarsen or extend the inferred one.

### How do I express a duration?

```elixir
iex> ~o"P1Y6M"
~o"P1Y6M"

iex> ~o"P1Y6M".time
[year: 1, month: 6]
```

### How do I express an interval between two dates?

```elixir
iex> ~o"2026-06-01/2026-06-30"
~o"2026Y6M1D/2026Y6M30D"
```

Tempo uses the half-open `[from, to)` convention. Adjacent intervals concatenate cleanly.

### How do I say "approximately 2022" or "uncertain 1984"?

```elixir
iex> ~o"2022~"
# Approximate 2022

iex> ~o"1984?"
# Uncertain 1984

iex> ~o"1984%"
# Both uncertain and approximate (equivalent to ISO 8601-2 `%`)
```

The qualification is stored on the value's `:qualification` field; the span stays the same calendar year.

---

## 2. Exploring a value

### How do I see what a value represents?

```elixir
iex> Tempo.explain(~o"156X")
"""
A masked year spanning the 1560s.
Span: [1560-01-01, 1570-01-01).
Iterates at :month granularity.
Materialise as an interval with `Tempo.to_interval/1`.
"""
```

`Tempo.explain/1` returns a plain string. For structured output (HTML visualiser, terminal colour) call `Tempo.Explain.explain/1` which returns a `%Tempo.Explanation{}` with tagged parts — `Tempo.Explain.to_string/1`, `to_ansi/1`, and `to_iodata/1` format it for different surfaces.

### How do I see the concrete bounds of an implicit interval?

```elixir
iex> {:ok, %Tempo.Interval{from: from, to: to}} = Tempo.to_interval(~o"2026-06")
iex> {from.time, to.time}
{[year: 2026, month: 6, day: 1], [year: 2026, month: 7, day: 1]}
```

Every Tempo value *is* an interval. `to_interval/1` materialises the implicit span into explicit `from`/`to` endpoints.

### How do I check a value's resolution?

```elixir
iex> Tempo.resolution(~o"2026-06-15")
{:day, 1}
```

---

## 3. Iteration

### How do I list every month of a year?

```elixir
iex> Enum.take(~o"2026Y", 12)
[~o"2026Y1M", ~o"2026Y2M", ~o"2026Y3M", ~o"2026Y4M", ~o"2026Y5M",
 ~o"2026Y6M", ~o"2026Y7M", ~o"2026Y8M", ~o"2026Y9M", ~o"2026Y10M",
 ~o"2026Y11M", ~o"2026Y12M"]
```

A year iterates at month granularity — the next-finer unit below what's specified.

### How do I list every day of a month?

```elixir
iex> Enum.take(~o"2026-06", 30) |> length()
30
```

### How do I list every year in the 1560s?

```elixir
iex> Enum.take(~o"156X", 5)
[~o"1560Y", ~o"1561Y", ~o"1562Y", ~o"1563Y", ~o"1564Y"]
```

The `X` mask is interpreted as "any digit." Enumeration walks the concrete years the mask represents.

### How do I step by a non-default unit?

Wrap the value in an explicit interval with the resolution you want:

```elixir
iex> interval = ~o"2026-06-01/2026-07-01"
# Iterates at day resolution (the boundaries' resolution).
iex> Enum.take(interval, 3)
# First three days of June
```

---

## 4. Comparison and predicates

### How do I check if a date is in an interval?

```elixir
iex> Tempo.contains?(~o"2026Y", ~o"2026-06-15")
true
```

### How do I check if two intervals overlap?

```elixir
iex> a = ~o"2026-06-01/2026-06-15"
iex> b = ~o"2026-06-10/2026-06-20"
iex> Tempo.overlaps?(a, b)
true
```

### What's the full set of relationships between two intervals?

Tempo implements Allen's interval algebra. Along with `overlaps?/2` and `contains?/2` you get `precedes?`, `meets?`, `starts?`, `finishes?`, `equal?`, and their inverses.

### How do I compare two values across different calendars?

```elixir
iex> hebrew = %Tempo{time: [year: 5786, month: 10, day: 30], calendar: Calendrical.Hebrew}
iex> Tempo.overlaps?(hebrew, ~o"2026-06-15")
true
```

Cross-calendar comparisons convert operands to a shared reference (UTC days or `Calendrical.Date`) automatically.

---

## 5. Set operations

### How do I merge two overlapping intervals into one?

```elixir
iex> a = ~o"2026-06-01/2026-06-15"
iex> b = ~o"2026-06-10/2026-06-20"
iex> {:ok, set} = Tempo.union(a, b)
iex> length(set.intervals)
1
# The merged span is June 1 .. June 20.
```

### How do I find the overlap between two intervals?

```elixir
iex> {:ok, set} = Tempo.intersection(a, b)
iex> hd(set.intervals).from.time
[year: 2026, month: 6, day: 10]
iex> hd(set.intervals).to.time
[year: 2026, month: 6, day: 15]
```

### How do I subtract a busy period from a free window?

```elixir
iex> work_day = ~o"2026-06-15T09/2026-06-15T17"
iex> lunch = ~o"2026-06-15T12/2026-06-15T13"
iex> {:ok, free} = Tempo.difference(work_day, lunch)
# `free` has two intervals: 09:00-12:00 and 13:00-17:00.
```

### How do I compose free/busy across a real calendar?

```elixir
iex> {:ok, calendar} = Tempo.ICal.from_ical_file("~/work.ics")
iex> {:ok, free} = Tempo.difference(~o"2026-06-15T09/2026-06-15T17", calendar)
```

Result intervals carry the event metadata from the subtracted calendar where relevant, so you can trace each "busy" segment back to the meeting that caused it.

### How do I get the symmetric difference (everything in A or B but not both)?

```elixir
iex> {:ok, set} = Tempo.symmetric_difference(a, b)
```

---

## 6. Recurring events (RRULE)

### How do I express "every Monday for 10 weeks"?

```elixir
iex> rule = %Tempo.RRule.Rule{freq: :week, interval: 1, byday: [{nil, 1}], count: 10}
iex> {:ok, occurrences} = Tempo.RRule.Expander.expand(rule, ~o"2026-06-01")
iex> length(occurrences)
10
```

### How do I parse an RRULE string?

```elixir
iex> {:ok, ast} = Tempo.RRule.parse("FREQ=WEEKLY;BYDAY=MO;COUNT=10", from: ~o"2026-06-01")
iex> {:ok, set} = Tempo.to_interval(ast, coalesce: false)
iex> length(set.intervals)
10
```

### How do I express "the 4th Thursday of November" (Thanksgiving)?

```elixir
iex> rule = %Tempo.RRule.Rule{
...>   freq: :year, interval: 1,
...>   bymonth: [11], byday: [{4, 4}],
...>   count: 5
...> }
iex> {:ok, occurrences} = Tempo.RRule.Expander.expand(rule, ~o"2022-11-24")
iex> Enum.map(occurrences, & &1.from.time[:day])
[24, 23, 28, 27, 26]
```

Positive ordinals count from the start of the period; negatives count from the end (`-1FR` = last Friday).

### How do I express "every Friday the 13th"?

```elixir
iex> rule = %Tempo.RRule.Rule{
...>   freq: :month, interval: 1,
...>   byday: [{nil, 5}], bymonthday: [13],
...>   count: 10
...> }
iex> {:ok, occurrences} = Tempo.RRule.Expander.expand(rule, ~o"1998-02-13")
```

When `BYMONTHDAY` is co-present, `BYDAY` becomes a filter (per RFC Note 1) — `BYMONTHDAY=13` picks day 13 of each month, then `BYDAY=FR` keeps only the Fridays.

### How do I express US Presidential Election Day?

"Every four years, the first Tuesday after a Monday in November":

```elixir
iex> rule = %Tempo.RRule.Rule{
...>   freq: :year, interval: 4,
...>   bymonth: [11], byday: [{nil, 2}],
...>   bymonthday: [2, 3, 4, 5, 6, 7, 8],
...>   count: 3
...> }
iex> {:ok, occurrences} = Tempo.RRule.Expander.expand(rule, ~o"1996-11-05")
iex> Enum.map(occurrences, fn iv -> {iv.from.time[:year], iv.from.time[:day]} end)
[{1996, 5}, {2000, 7}, {2004, 2}]
```

### How do I express "last weekday of every month"?

```elixir
iex> rule = %Tempo.RRule.Rule{
...>   freq: :month, interval: 1,
...>   byday: [{nil, 1}, {nil, 2}, {nil, 3}, {nil, 4}, {nil, 5}],
...>   bysetpos: [-1],
...>   count: 3
...> }
iex> {:ok, occurrences} = Tempo.RRule.Expander.expand(rule, ~o"2026-06-01")
```

`BYDAY=MO..FR` expands each month to all weekdays; `BYSETPOS=-1` picks the last.

### How do I handle an unbounded rule?

Supply `:bound`:

```elixir
iex> rule = %Tempo.RRule.Rule{freq: :day, interval: 1}  # No COUNT, no UNTIL
iex> {:ok, occurrences} = Tempo.RRule.Expander.expand(rule, ~o"2026-06-01", bound: ~o"2026-07-01")
iex> length(occurrences)
30
```

---

## 7. iCalendar import

### How do I import an `.ics` file?

```elixir
iex> {:ok, calendar} = Tempo.ICal.from_ical_file("~/work.ics")
iex> length(calendar.intervals)
# One interval per VEVENT (or per materialised recurrence occurrence).
```

Each event becomes a `%Tempo.Interval{}` with full metadata (summary, location, attendees, …) attached to `:metadata`.

### How do I import an `.ics` that contains recurring events?

Pass a `:bound` so unbounded recurrences terminate:

```elixir
iex> {:ok, calendar} = Tempo.ICal.from_ical(ics, bound: ~o"2026-04-01/2026-07-01")
```

Every RRULE part (including BY-rules, BYSETPOS, WKST, RDATE, EXDATE) materialises correctly — one `%Tempo.Interval{}` per occurrence carrying the event's metadata.

### How do I find when a specific attendee is in a meeting?

```elixir
iex> {:ok, calendar} = Tempo.ICal.from_ical(ics)
iex> ada_meetings = Enum.filter(calendar.intervals, fn iv ->
...>   "ada@example.com" in (iv.metadata[:attendees] || [])
...> end)
```

Metadata rides through any downstream set operation — after `intersection/difference/union`, you can still trace each result fragment to its originating event.

---

## 8. Cross-calendar and cross-timezone

### How do I compare a Hebrew date to a Gregorian one?

```elixir
iex> hebrew = %Tempo{time: [year: 5786, month: 10, day: 30], calendar: Calendrical.Hebrew}
iex> Tempo.overlaps?(hebrew, ~o"2026-06-15")
true
# Hebrew 5786-10-30 is Gregorian 2026-06-15.
```

### How do I compare across timezones?

```elixir
iex> paris = Tempo.from_elixir(DateTime.new!(~D[2026-06-15], ~T[10:00:00], "Europe/Paris"))
iex> utc_window = ~o"2026-06-15T07/2026-06-15T09"
iex> Tempo.overlaps?(paris, utc_window)
true
# Paris 10:00 CEST == UTC 08:00 — inside the window.
```

Tempo projects to UTC via `Tzdata` for cross-zone comparisons. The wall-clock representation on the struct is preserved; the projection happens per-call.

### How do I convert a Tempo to a specific calendar?

```elixir
iex> Tempo.to_calendar(~o"2026-06-15", Calendrical.Hebrew)
# Returns {:ok, %Tempo{...calendar: Calendrical.Hebrew}}
```

---

## 9. Archaeological / approximate dates

### How do I say "sometime in the 1560s"?

```elixir
iex> ~o"156X"
# Decade mask — spans 1560-01-01 .. 1570-01-01.
```

### How do I say "the 15th of every month in 1985"?

```elixir
iex> {:ok, %Tempo.IntervalSet{intervals: days}} = Tempo.to_interval(~o"1985-XX-15")
iex> length(days)
12
```

A non-contiguous mask (masked month, concrete day) expands to one interval per valid month.

### How do I express an open-ended interval?

```elixir
iex> ~o"1985/.."
# From 1985 onward, no end.

iex> ~o"../2024"
# No start, ending 2024.

iex> ~o"../.."
# Fully open.
```

### How do I attach a qualifier to a single endpoint?

```elixir
iex> ~o"1984?/2004~"
# Uncertain lower bound, approximate upper bound.
```

Each endpoint carries its own `:qualification` in addition to any expression-level one.

---

## 10. Real-world scenarios

### Find every Friday the 13th this century

```elixir
iex> rule = %Tempo.RRule.Rule{
...>   freq: :month, interval: 1,
...>   byday: [{nil, 5}], bymonthday: [13]
...> }
iex> {:ok, occurrences} = Tempo.RRule.Expander.expand(
...>   rule,
...>   ~o"2000-01-01",
...>   bound: ~o"2100-01-01"
...> )
iex> length(occurrences)
# Total Friday-the-13ths in the 21st century.
```

### Find when two people are both available

```elixir
iex> {:ok, ada} = Tempo.ICal.from_ical_file("~/ada.ics")
iex> {:ok, grace} = Tempo.ICal.from_ical_file("~/grace.ics")
iex> work_hours = ~o"2026-06-15T09/2026-06-15T17"
iex> {:ok, ada_free} = Tempo.difference(work_hours, ada)
iex> {:ok, both_free} = Tempo.difference(ada_free, grace)
# `both_free` intervals are the slots where neither is busy.
```

### How do I check if a dig layer overlaps a historical period?

```elixir
iex> dig_layer = ~o"1520/1590"
iex> ming_period = ~o"1368/1644"
iex> Tempo.overlaps?(dig_layer, ming_period)
true
```

### How do I find free time across multiple calendars and timezones?

```elixir
iex> work = ~o"2026-06-15T09/2026-06-15T17"
iex> {:ok, cal_ny} = Tempo.ICal.from_ical_file("~/cal_ny.ics")
iex> {:ok, cal_london} = Tempo.ICal.from_ical_file("~/cal_london.ics")
iex> {:ok, step1} = Tempo.difference(work, cal_ny)
iex> {:ok, free} = Tempo.difference(step1, cal_london)
```

Set operations convert to UTC per-call so wall-clock mismatches across zones resolve correctly.

### How do I round a datetime to the nearest hour?

```elixir
iex> Tempo.at_resolution(~o"2026-06-15T10:37:42", :hour)
~o"2026Y6M15DT10H"
```

`at_resolution/2` is the single entry point for normalising to a target unit — coarser uses `trunc/2`, finer uses `extend_resolution/2`.

### How do I generate a list of business days in a month?

```elixir
iex> rule = %Tempo.RRule.Rule{
...>   freq: :day, interval: 1,
...>   byday: [{nil, 1}, {nil, 2}, {nil, 3}, {nil, 4}, {nil, 5}]
...> }
iex> {:ok, days} = Tempo.RRule.Expander.expand(rule, ~o"2026-06-01", bound: ~o"2026-06")
iex> length(days)
22
```

Tip: `bound: ~o"2026-06"` has an upper endpoint of July 1 (exclusive) — it confines the expansion to June. Using `~o"2026-07-01"` would include July 1 too, since day-resolution values span their whole day under the implicit-span rule.

### How do I represent a free/busy period set from iCal and do set algebra on it?

```elixir
iex> {:ok, calendar} = Tempo.ICal.from_ical(ics, bound: ~o"2026-06")
iex> month = ~o"2026-06"
iex> {:ok, free} = Tempo.difference(month, calendar)
iex> # `free` is every free minute of June 2026.
```

---

## Related reading

* [ISO 8601 conformance](./iso8601-conformance.md) — what's supported from the standard.
* [Enumeration semantics](./enumeration-semantics.md) — how iteration works across Tempo values.
* [Set operations](./set-operations.md) — union, intersection, complement, difference.
* [iCalendar integration](./ical-integration.md) — full `.ics` import with RRULE/RDATE/EXDATE.
* [Shared AST for ISO 8601 and RRULE](./shared-ast-iso8601-and-rrule.md) — the internal representation.
