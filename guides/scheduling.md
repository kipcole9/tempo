# Scheduling

Scheduling is really three questions, and Tempo answers each with a different part of the library:

1. **"When does this recur?"** — generate the occurrences of a repeating rule, bounded and zone-correct (sections 1–4).

2. **"When are we free to meet?"** — turn busy calendars into open, bookable time with set operations (section 5).

3. **"When can these dependent tasks run?"** — order constrained work to a deadline and find the critical path (section 6).

The first question has the sharpest edges — future dates, wall-clock vs UTC, and time zones that change rules out from under you — so it gets the most space. Sections 1–4 each give the principle, the Tempo idiom, and the pitfall to avoid:

* **You can't materialise an infinite stream.** Bounded scheduling is a design decision.

* **Wall-clock time is authoritative; UTC is a projection.** Tempo stores the user's wall time and derives the UTC instant on demand.

* **"Floating" events vs zoned events** — Tempo distinguishes them through what's on the value, not a flag.

* **Future dates survive zone-rule changes** — because Tempo never caches a UTC value, re-reading a future event automatically uses the current Tzdata.

## Setup — required for every example

Every code example in this guide uses the `~o` sigil from `Tempo.Sigils`. Before running any of them — in `iex`, a script, or a module — you must bring the sigil into scope:

```elixir
import Tempo.Sigils
```

The import adds only `sigil_o/2` and `sigil_TEMPO/2` to the caller's namespace; no helper functions leak in.

## 1. Bounded enumeration

An RRULE like `FREQ=MONTHLY;BYDAY=2MO` ("the second Monday of every month") is **infinite** — occurrences continue forever. You cannot call `Enum.to_list/1` on an infinite sequence.

Tempo splits the two operations: building the recurrence **AST** is cheap and always bounded-free, but **materialising** the AST into a concrete `%Tempo.IntervalSet{}` requires a bound.

```elixir
rule = %Tempo.RRule.Rule{freq: :month, interval: 1, byday: [{2, 1}]}
{:ok, ast} = Tempo.RRule.Expander.to_ast(rule, ~o"2025-01-01")

# `ast` is a %Tempo.Interval{recurrence: :infinity, ...} — not an error.
# Materialising it requires a bound:

{:ok, set} = Tempo.to_interval(ast, bound: ~o"2025-07-01")
Tempo.IntervalSet.count(set)
#=> 7
```

> The **AST** is the recurrence *rule*; the **IntervalSet** is its *occurrences* inside a window. `:bound` is always supplied at materialisation, never at the rule. Tempo's default member-preserving semantics keep each occurrence as a distinct member of the IntervalSet — which is what you want for scheduling. For the covered-instant form (individual occurrences merged into contiguous spans), pipe through `Tempo.IntervalSet.coalesce/1` — useful for free/busy questions but not for "list the events."

For ad-hoc use, `Stream.take/2` and `Enum.take/2` work directly on the AST — it's enumerable, lazily:

```elixir
ast |> Stream.take(10) |> Enum.to_list()
```

### Pitfall

Forgetting the bound and calling `Tempo.to_interval(ast)`:

```elixir
{:error,
 "Cannot materialise an unbounded recurrence (recurrence: :infinity, no UNTIL). Supply a :bound option — any Tempo value whose upper endpoint limits the expansion."}
```

Tempo refuses rather than hanging — forgotten bounds are a design error, not a runtime surprise.

## 2. Wall-clock time is authoritative

When a user schedules "08:00 on 1 March 2030 in Paris", the *real* scheduling intent is the wall-clock reading on that morning — not a specific UTC instant. If Paris changes its DST rules between now and 2030, the UTC instant should shift; the wall-clock event should not.

Tempo stores exactly what the user wrote:

```elixir
t = ~o"2030-03-01T08:00:00[Europe/Paris]"
t.time
#=> [year: 2030, month: 3, day: 1, hour: 8, minute: 0, second: 0]

t.extended.zone_id
#=> "Europe/Paris"
```

No UTC seconds are cached on the struct. When you ask for the UTC projection, Tempo consults Tzdata at the time of the call, and the result reflects whatever zone rules Tzdata currently knows about 2030. Re-run the same call after Tzdata updates and the number may change — that's the correct behaviour for future dates.

### Principle

**Store what the user said. Compute UTC when you need it.** This is the same discipline Apple Calendar and Google Calendar enforce: the canonical form of a future event is wall-clock + zone, not UTC.

### Pitfall

Serialising a Tempo value as "the UTC seconds" and rehydrating from that:

```elixir
# Do NOT do this for future events:
cached_utc = Tempo.Compare.to_utc_seconds(event)
store_in_database(cached_utc)
```

When Tzdata ships a DST rule change for 2030, your cached number is now wrong — but you've lost the wall-clock information needed to recompute. Serialise the Tempo value itself (`Tempo.to_iso8601/1` round-trips faithfully) and project to UTC only at display or comparison time.

## 3. Floating vs zoned events

Apple Calendar's **"floating"** events (they call them "All-day" in the UI, but the concept applies to timed events too in iCal RFC 5545) stay at the same wall-clock reading regardless of the viewer's zone — a "6am workout" on holiday is still 6am local.

Tempo distinguishes floating and zoned through **presence of the zone tag**:

```elixir
floating = ~o"2030-03-01T08:00:00"
floating.extended
#=> nil

paris = ~o"2030-03-01T08:00:00[Europe/Paris]"
paris.extended.zone_id
#=> "Europe/Paris"

utc = ~o"2030-03-01T08:00:00Z"
utc.shift
#=> [hour: 0]

fixed = ~o"2030-03-01T08:00:00+05:30"
fixed.shift
#=> [hour: 5, minute: 30]
```

| Form | Meaning |
|---|---|
| `~o"2030-03-01T08:00:00"` | **Floating** — 8am in whatever zone the reader is in |
| `~o"2030-03-01T08:00:00[Europe/Paris]"` | **Zoned** — 8am Paris wall time, UTC derived on demand |
| `~o"2030-03-01T08:00:00Z"` | **UTC-anchored** — a specific UTC instant, wall times vary by zone |
| `~o"2030-03-01T08:00:00+05:30"` | **Fixed-offset** — UTC+05:30 regardless of zone-rule changes |

The right choice depends on what the user said:

* "Morning workout at 6am" when travelling — floating.

* "Meeting at 2pm Paris" — zoned (`[Europe/Paris]`).

* "Server job at 03:00 UTC" — UTC-anchored (`Z`).

* "Event at UTC+05:30" (fixed-offset calendar system) — fixed-offset.

### Principle

**The interpretation of a wall-clock reading is metadata, not an afterthought.** Tempo forces you to make that choice at parse time and preserves it through every operation.

## 4. Future dates survive zone-rule changes

When Paris last moved its DST rules in 1996, any calendar entry stored as a frozen UTC instant for a post-1996 date had to be rewritten. Modern calendars (Google, Apple, Outlook) avoid this by storing wall-clock + zone and deriving UTC on demand — which is exactly what Tempo does.

Concretely: a Paris event stored today for 2030 will be re-evaluated with whatever Tzdata knows about Paris's rules in 2030 *at the time of the computation*:

```elixir
event = ~o"2030-03-01T08:00:00[Europe/Paris]"

# Today, Tzdata thinks this is UTC+1 (standard time in March).
Tempo.Compare.to_utc_seconds(event)
#=> 64052726400

# If Tzdata 2028a ships saying France abolished DST in 2027,
# the next call to to_utc_seconds returns a different number
# — the event is "still 8am Paris wall time, but the UTC shifts."
```

`Tempo.Interval.duration/2` likewise re-evaluates each endpoint's UTC projection on every call. Comparisons and set operations do the same. Nothing is frozen.

### When to freeze

There are cases where you **want** the UTC instant frozen — a CI build that must run "at exactly 03:00 UTC on 15 March 2030" regardless of how zones shift. Store those as UTC (`~o"2030-03-15T03:00:00Z"`). The `Z` suffix is the explicit promise: "this is a UTC instant, don't recompute."

### Principle

**Don't cache UTC. Don't cache DST. Tempo doesn't, and the reason you trust this library over rolling your own is exactly this discipline.**

## 5. Free-busy and availability

The recurrence sections generate *when things happen*. The opposite question — *when is nobody busy* — is set algebra over those occurrences. **Free time is the workday minus the busy periods; mutual free time is the intersection of each person's free time.**

```elixir
work = ~o"2026-06-15T09:00:00/2026-06-15T17:00:00"

alice_busy =
  Tempo.IntervalSet.new!([
    ~o"2026-06-15T10:00:00/2026-06-15T11:00:00",
    ~o"2026-06-15T14:00:00/2026-06-15T15:00:00"
  ])

bob_busy =
  Tempo.IntervalSet.new!([
    ~o"2026-06-15T09:30:00/2026-06-15T10:30:00",
    ~o"2026-06-15T16:00:00/2026-06-15T17:00:00"
  ])

{:ok, alice_free} = Tempo.difference(work, alice_busy)
{:ok, bob_free}   = Tempo.difference(work, bob_busy)
{:ok, mutual}     = Tempo.intersection(alice_free, bob_free)
#=> 09:00–09:30, 11:00–14:00, 15:00–16:00
```

> *"Alice's free time is the workday **minus** her meetings; Bob's is the same. **Mutual** free time is the **intersection** of theirs."*

Free time gives you the *regions* where a meeting could go. Turn them into the discrete slots a booking page actually offers with `Tempo.IntervalSet.slots/3`:

```elixir
mutual
|> Tempo.IntervalSet.slots(~o"PT1H")    # cut into back-to-back 1-hour slots
|> Tempo.IntervalSet.to_list()
#=> 11:00–12:00, 12:00–13:00, 13:00–14:00, 15:00–16:00
```

> *"The bookable hour-long slots are the mutual windows cut into one-hour pieces."* The 09:00–09:30 opening is too short to hold an hour, so it drops out. Pass `every: ~o"PT30M"` to offer a start on every half-hour instead (overlapping slots), or a larger `:every` to leave gaps between offered times.

This is **instant-level** set algebra — you are asking about *time regions*, not preserving individual calendar events — so `difference`/`intersection` are the right operators rather than their member-preserving companions. The [set operations guide](./set-operations.md) explains that distinction in full; to load real calendars from `.ics` files instead of inline busy sets, see the free-busy recipe in the [cookbook](./cookbook.md).

## 6. Dependency scheduling (the critical path)

The sections above schedule *recurrences* — a rule repeated over a window. A different question is scheduling *a plan of dependent tasks*: "design takes 2 days, then build (3 days) and docs (1 day) can run, then ship (2 days) needs both — when does each run, and what's due by the deadline?" That's the critical path method, and `Tempo.Schedule` solves it directly (it's the same Simple Temporal Problem `Tempo.Network` already solves — tasks are periods, dependencies are boundary relations).

```elixir
{:ok, plan} =
  Tempo.Schedule.new()
  |> Tempo.Schedule.task(:design, duration: ~o"P2D", start: ~o"2026-06-01")
  |> Tempo.Schedule.task(:build, duration: ~o"P3D", after: :design)
  |> Tempo.Schedule.task(:docs, duration: ~o"P1D", after: :design)
  |> Tempo.Schedule.task(:ship, duration: ~o"P2D", after: [:build, :docs], deadline: ~o"2026-06-08")
  |> Tempo.Schedule.solve()

plan[:ship].start                 #=> ~o"2026Y6M6D"
plan[:docs].critical?             #=> false   (docs has slack)
Tempo.Schedule.critical_path(plan) #=> [:design, :build, :ship]
Tempo.Schedule.span(plan)          #=> the project interval, 06-01 .. 06-08
```

> *"Design, then build and docs in parallel, then ship — due the 8th. Ship starts on the 6th; docs has slack and isn't on the critical path; the project runs design → build → ship."*

Each task carries a `:duration` (exact or a `{min, max}` range) and optional `:after` dependencies (finish-to-start — a successor starts no earlier than its predecessors finish). Bounds come from `:start` (a fixed anchor), `:earliest`, `:deadline`, or a `:within` window. `solve/1` returns a `%Tempo.Schedule.Slot{}` per task with its early and late positions; `critical?` is true when a task has zero slack. An over-tight deadline or a dependency cycle returns `{:error, :infeasible}`.

### What this is not

Scheduling *around* a busy calendar — "drop this task into the first free gap" — is a disjunctive problem (before *or* after each existing meeting) that the Simple Temporal Problem can't express. For that, compute the free regions with the set operations (`Tempo.difference/2`) and discretise them with `Tempo.IntervalSet.slots/3` (see [set operations](./set-operations.md) and [the cookbook](./cookbook.md)). `Tempo.Schedule` is for *dependency* scheduling, where constraints compose by conjunction.

## Putting it together

A practical scheduling layer built on Tempo looks like:

```elixir
defmodule Schedule do
  def weekly_meeting(name, %Date{} = date, %Time{} = time, zone) do
    dtstart =
      Tempo.new!(
        year: date.year,
        month: date.month,
        day: date.day,
        hour: time.hour,
        minute: time.minute,
        zone: zone
      )

    rule = %Tempo.RRule.Rule{freq: :week, interval: 1}
    {:ok, ast} = Tempo.RRule.Expander.to_ast(rule, dtstart)
    %{name: name, rule: ast}
  end

  def occurrences_in(%{rule: ast}, from, to) do
    bound = Tempo.Interval.new!(from: from, to: to)
    {:ok, set} = Tempo.to_interval(ast, bound: bound)
    Tempo.IntervalSet.to_list(set)
  end
end

retrospective =
  Schedule.weekly_meeting("Retro", ~D[2025-06-01], ~T[14:00:00], "Europe/London")

# Occurrences for Q3:
Schedule.occurrences_in(retrospective, ~o"2025-07-01", ~o"2025-10-01")
# 18 weekly occurrences, each with wall time 14:00 in Europe/London
```

> **`Tempo.new/1` is the runtime companion to the `~o` sigil.** The sigil is for literal values in source; `new/1` takes keyword components that can come from anywhere — function arguments, database rows, API payloads, form inputs. String interpolation to assemble an ISO 8601 value and then parse it back is always the wrong move: it round-trips through formatting twice and bypasses the type-level validation that component construction gives you.

> **Store** the rule as an AST (with zoned wall time). **Materialise** into an IntervalSet only when you need concrete occurrences, bounded to the query window. **Display** by projecting each endpoint's wall time through the viewer's preferred zone. Nothing about the stored rule changes when Tzdata does.

## Related reading

* [Enumeration semantics](./enumeration-semantics.md) — what iteration means on a Tempo value or IntervalSet.

* [Set operations](./set-operations.md) — free/busy, overlap detection, the sweep-line algorithm.

* [iCalendar integration](./ical-integration.md) — round-trip a real `.ics` file, preserve metadata, expand RRULEs from it.

* [RFC 5545 RRULE conformance](./rfc5545_rrule_conformance.md) — property-by-property coverage of the standard.

* [The cookbook](./cookbook.md) — recipe-format queries for the common scheduling patterns.
