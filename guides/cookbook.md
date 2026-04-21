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
6. [Selecting sub-spans with `Tempo.select/3`](#6-selecting-sub-spans-with-temposelect3)
7. [Recurring events (RRULE)](#7-recurring-events-rrule)
8. [iCalendar import](#8-icalendar-import)
9. [Cross-calendar and cross-timezone](#9-cross-calendar-and-cross-timezone)
10. [Archaeological / approximate dates](#10-archaeological--approximate-dates)
11. [Real-world scenarios](#11-real-world-scenarios)

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

Tempo implements Allen's interval algebra — every pair of bounded intervals stands in exactly one of 13 relations. `Tempo.compare/2` returns the atom:

```elixir
iex> a = %Tempo.Interval{from: ~o"2026-06-01", to: ~o"2026-06-10"}
iex> b = %Tempo.Interval{from: ~o"2026-06-05", to: ~o"2026-06-15"}
iex> Tempo.compare(a, b)
:overlaps

iex> Tempo.compare(~o"2026-06-15", ~o"2026-06-16")
:meets
```

Named predicates cover the common one-shot checks:

| Predicate | Maps to |
|---|---|
| `Tempo.before?(a, b)` | `:precedes` — ends with a gap before b |
| `Tempo.after?(a, b)` | `:preceded_by` |
| `Tempo.meets?(a, b)` | `:meets` — ends exactly at b's start |
| `Tempo.adjacent?(a, b)` | `:meets \| :met_by` — touches, no gap |
| `Tempo.during?(a, b)` | `:during` — strictly inside |
| `Tempo.within?(a, b)` | `:equals \| :starts \| :during \| :finishes` — fits inside, inclusive |

`Tempo.within?/2` is the canonical "does this fit inside that window?" predicate:

```elixir
iex> candidate = %Tempo.Interval{from: ~o"2026-06-15T10", to: ~o"2026-06-15T11"}
iex> window = %Tempo.Interval{from: ~o"2026-06-15T09", to: ~o"2026-06-15T17"}
iex> Tempo.within?(candidate, window)
true
```

For set-level questions across two multi-member `IntervalSet`s, use `Tempo.IntervalSet.relation_matrix/2` which returns every pairwise relation.

### How long is an interval?

```elixir
iex> iv = %Tempo.Interval{from: ~o"2026-06-15T09", to: ~o"2026-06-15T11"}
iex> Tempo.duration(iv)
~o"PT7200S"
```

Returns `:infinity` when one or both endpoints are `:undefined`.

### How do I check an interval's length against a duration?

Five predicates cover the comparison lattice:

```elixir
iv = %Tempo.Interval{from: ~o"2026-06-15T09", to: ~o"2026-06-15T10"}

Tempo.at_least?(iv, ~o"PT1H")      # true — length ≥ 1h
Tempo.exactly?(iv, ~o"PT1H")       # true — length == 1h
Tempo.at_most?(iv, ~o"PT1H")       # true — length ≤ 1h
Tempo.longer_than?(iv, ~o"PT30M")  # true — strict >
Tempo.shorter_than?(iv, ~o"PT2H")  # true — strict <
```

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
work_day = ~o"2026-06-15T09/2026-06-15T17"
lunch    = ~o"2026-06-15T12/2026-06-15T13"

{:ok, free} = Tempo.difference(work_day, lunch)
```

> The **workday minus lunch** is my **free** time — two intervals, 09:00-12:00 and 13:00-17:00.

### How do I compose free/busy across a real calendar?

```elixir
{:ok, calendar} = Tempo.ICal.from_ical_file("~/work.ics")

work = ~o"2026-06-15T09/2026-06-15T17"
{:ok, free} = Tempo.difference(work, calendar)
```

> **Work** minus **my calendar** gives me **free** time that day.

Result intervals carry the event metadata from the subtracted calendar where relevant, so you can trace each "busy" segment back to the meeting that caused it.

### How do I get the symmetric difference (everything in A or B but not both)?

```elixir
iex> {:ok, set} = Tempo.symmetric_difference(a, b)
```

---

## 6. Selecting sub-spans with `Tempo.select/3`

`Tempo.select/3` narrows a base span (a Tempo, an Interval, or an IntervalSet) by a **selector** and returns the matched spans as a `{:ok, %Tempo.IntervalSet{}}` tuple. The same vocabulary covers locale-dependent queries (workdays, weekends), integer indices at the next-finer unit, and projection of a Tempo or Interval onto a larger base.

> **Locale-dependent selectors (`:workdays`, `:weekend`) resolve at call time.** Do not capture such calls in module attributes or at compile time — the result would bake in whichever locale the build machine happened to have. Always call them from a function body at runtime. Explicit selectors (integer lists, Tempo projections, functions) are safe to capture.

### How do I select the workdays of a month?

```elixir
iex> {:ok, workdays} = Tempo.select(~o"2026-06", :workdays)
iex> workdays |> Tempo.IntervalSet.to_list() |> length()
22
```

> **Workdays** of **June 2026** in the default locale (US) are Monday through Friday — 22 day-resolution intervals.

### How do I pick specific days inside a month?

```elixir
iex> {:ok, set} = Tempo.select(~o"2026-06", [1, 15])
iex> set |> Tempo.IntervalSet.to_list() |> Enum.map(& &1.from.time[:day])
[1, 15]
```

> **Integer selectors** apply at the **next-finer unit** below the base's resolution — on a month base that's day, on a year base it's month. A `Range` works too: `Tempo.select(~o"2026-06", 10..15)`.

### How do I project a date pattern onto a larger base?

```elixir
iex> {:ok, set} = Tempo.select(~o"2026", ~o"12-25")
iex> [xmas] = Tempo.IntervalSet.to_list(set)
iex> {xmas.from.time[:year], xmas.from.time[:month], xmas.from.time[:day]}
{2026, 12, 25}
```

> **Project** the constraint `12-25` onto the base year — Dec 25 of 2026. A list of constraints works the same: `Tempo.select(~o"2026", [~o"07-04", ~o"12-25"])` yields both US holidays.

### How do I override the territory for a locale-dependent selector?

```elixir
iex> {:ok, sa_weekend} = Tempo.select(~o"2026-02", :weekend, region: :SA)
iex> sa_weekend |> Tempo.IntervalSet.to_list() |> Enum.map(& &1.from.time[:day])
[6, 7, 13, 14, 20, 21, 27, 28]
```

> Saudi Arabia's **weekend** is **Friday + Saturday**. The territory resolution chain is: explicit `region:` option → IXDTF `u-rg=XX` tag on the base → `Application.get_env(:ex_tempo, :default_region)` → `Localize.get_locale() |> Localize.Territory.territory_from_locale()`.

### How do I compose select with the set operations?

```elixir
{:ok, june_workdays} = Tempo.select(~o"2026-06", :workdays)
{:ok, vacation} = Tempo.to_interval_set(~o"2026-06-15/2026-06-20")
{:ok, available} = Tempo.difference(june_workdays, vacation)
```

> **Workdays** of June **minus** my **vacation** yields the workdays I'm **available**. Because `select/3` returns an IntervalSet, it drops straight into `union/2`, `intersection/2`, `difference/2`, and `symmetric_difference/2`.

### How do I use a function as a selector?

```elixir
holidays = fn _base -> [~o"01-01", ~o"07-04", ~o"12-25"] end
{:ok, set} = Tempo.select(~o"2026", holidays)
```

> **Function selectors** receive the base and return any selector shape (list of Tempos here). This is the extension point for user-defined holiday calendars, business rules, or anything else you want to compute from the base.

See `Tempo.Select` for the full selector vocabulary.

---

## 7. Recurring events (RRULE)

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

## 8. iCalendar import

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
{:ok, calendar} = Tempo.ICal.from_ical(ics)

ada_meetings =
  calendar
  |> Tempo.IntervalSet.to_list()
  |> Enum.filter(fn meeting ->
    "ada@example.com" in (meeting.metadata[:attendees] || [])
  end)
```

> **Ada's meetings** are every event in the **calendar** whose **attendees** include her.

Metadata rides through any downstream set operation — after `intersection/difference/union`, you can still trace each result fragment to its originating event.

---

## 9. Cross-calendar and cross-timezone

### How do I compare a Hebrew date to a Gregorian one?

```elixir
hebrew    = %Tempo{time: [year: 5786, month: 10, day: 30], calendar: Calendrical.Hebrew}
gregorian = ~o"2026-06-15"

Tempo.overlaps?(hebrew, gregorian)
#=> true
```

> The **Hebrew date** 5786-10-30 **overlaps** the **Gregorian date** 2026-06-15 — they're the same day.

### How do I compare across timezones?

```elixir
paris      = Tempo.from_elixir(DateTime.new!(~D[2026-06-15], ~T[10:00:00], "Europe/Paris"))
utc_window = ~o"2026-06-15T07/2026-06-15T09"

Tempo.overlaps?(paris, utc_window)
#=> true
```

> **Paris 10:00 CEST** **overlaps** the **UTC 07:00-09:00 window** — it projects to UTC 08:00, which is inside.

Tempo projects to UTC via `Tzdata` for cross-zone comparisons. The wall-clock representation on the struct is preserved; the projection happens per-call.

### How do I convert a Tempo to a specific calendar?

```elixir
iex> Tempo.to_calendar(~o"2026-06-15", Calendrical.Hebrew)
# Returns {:ok, %Tempo{...calendar: Calendrical.Hebrew}}
```

---

## 10. Archaeological / approximate dates

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

## 11. Real-world scenarios

### Find every Friday the 13th this century

```elixir
friday_the_13th = %Tempo.RRule.Rule{
  freq: :month,
  interval: 1,
  byday: [{nil, 5}],
  bymonthday: [13]
}

century = ~o"2000-01-01/2100-01-01"

{:ok, occurrences} =
  Tempo.RRule.Expander.expand(friday_the_13th, ~o"2000-01-01", bound: century)
```

> **Friday the 13th** is a monthly rule — Fridays whose day-of-month is 13. **Expanding** the rule across the **century** gives every occurrence.

### Find when two people are both free for at least 1 hour

```elixir
{:ok, ada}   = Tempo.ICal.from_ical_file("~/ada.ics")
{:ok, grace} = Tempo.ICal.from_ical_file("~/grace.ics")

work = ~o"2026-06-15T09/2026-06-15T17"

{:ok, ada_free}   = Tempo.difference(work, ada)
{:ok, grace_free} = Tempo.difference(work, grace)
{:ok, mutual}     = Tempo.intersection(ada_free, grace_free)

slots =
  mutual
  |> Tempo.IntervalSet.to_list()
  |> Enum.filter(&Tempo.at_least?(&1, ~o"PT1H"))
```

> Ada's free time is the workday **minus** her busy periods. Grace's is the same. **Mutual** free time is the **intersection** of theirs. **Slots** are the mutual windows **at least an hour** long.

### Which of these candidate meeting times can I book?

```elixir
candidates = [
  ~o"2026-06-15T09/2026-06-15T10",
  ~o"2026-06-15T11/2026-06-15T12",
  ~o"2026-06-15T16/2026-06-15T17"
]

bookable =
  Enum.filter(candidates, fn candidate ->
    Enum.any?(Tempo.IntervalSet.to_list(mutual), &Tempo.within?(candidate, &1))
  end)
```

> A **candidate** is **bookable** if **any** mutual free window **contains** it.

### How do I check if a dig layer overlaps a historical period?

```elixir
dig_layer    = ~o"1520/1590"
ming_period  = ~o"1368/1644"

Tempo.overlaps?(dig_layer, ming_period)
#=> true
```

> The **dig layer overlaps** the **Ming period** — the site was in use during the dynasty.

### How do I find free time across multiple calendars and timezones?

```elixir
{:ok, ny}     = Tempo.ICal.from_ical_file("~/cal_ny.ics")
{:ok, london} = Tempo.ICal.from_ical_file("~/cal_london.ics")

work = ~o"2026-06-15T09/2026-06-15T17"

{:ok, ny_free}   = Tempo.difference(work, ny)
{:ok, free}      = Tempo.difference(ny_free, london)
```

> **Work** minus **New York's busy times** gives one person's free window; that **minus London's busy times** gives the cross-timezone **free** slots. Each `difference/2` call projects to UTC internally, so wall-clock mismatches across zones resolve correctly.

### How do I round a datetime to the nearest hour?

```elixir
iex> Tempo.at_resolution(~o"2026-06-15T10:37:42", :hour)
~o"2026Y6M15DT10H"
```

`at_resolution/2` is the single entry point for normalising to a target unit — coarser uses `trunc/2`, finer uses `extend_resolution/2`.

### How do I generate a list of business days in a month?

```elixir
iex> {:ok, workdays} = Tempo.select(~o"2026-06", :workdays)
iex> workdays |> Tempo.IntervalSet.to_list() |> length()
22
```

> **Workdays** of **June 2026** are Monday through Friday — 22 day-resolution intervals, locale-aware via `Localize.Calendar`. See [§6](#6-selecting-sub-spans-with-temposelect3) for the full selector vocabulary and territory-resolution chain.

An RRULE equivalent is available when you need the full rule machinery (byday counts, bymonth filters, intervals greater than 1):

```elixir
weekdays = %Tempo.RRule.Rule{
  freq: :day,
  interval: 1,
  byday: [{nil, 1}, {nil, 2}, {nil, 3}, {nil, 4}, {nil, 5}]
}

{:ok, days} = Tempo.RRule.Expander.expand(weekdays, ~o"2026-06-01", bound: ~o"2026-06")
```

### Every free minute in a month

```elixir
{:ok, calendar} = Tempo.ICal.from_ical(ics, bound: ~o"2026-06")

month = ~o"2026-06"
{:ok, free} = Tempo.difference(month, calendar)
```

> The **month** of June **minus** my **calendar** is my **free** time that month.

---

## Related reading

* [ISO 8601 conformance](./iso8601-conformance.md) — what's supported from the standard.
* [Enumeration semantics](./enumeration-semantics.md) — how iteration works across Tempo values.
* [Set operations](./set-operations.md) — union, intersection, complement, difference.
* [iCalendar integration](./ical-integration.md) — full `.ics` import with RRULE/RDATE/EXDATE.
* [Shared AST for ISO 8601 and RRULE](./shared-ast-iso8601-and-rrule.md) — the internal representation.
