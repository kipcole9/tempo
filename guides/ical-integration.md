# iCalendar integration

Tempo imports iCalendar (RFC 5545) data — the interchange format used by Google Calendar, Apple Calendar, Outlook, CalDAV servers, and every `.ics` file on disk — via `Tempo.ICal.from_ical/2`. Events convert to `%Tempo.Interval{}` values with their full metadata (summary, location, attendees, status, …) preserved and carried through every downstream operation, including set operations and enumeration.

This unlocks free/busy scheduling, calendar overlap analysis, and event-aware time queries as direct expressions over the same API you use for any other Tempo value.

## 1. A complete round-trip

```elixir
ics = File.read!("~/my-calendar.ics")

{:ok, calendar} = Tempo.ICal.from_ical(ics)
# %Tempo.IntervalSet{
#   intervals: [%Tempo.Interval{metadata: %{summary: ..., location: ...}}, ...],
#   metadata: %{prodid: "-//Apple Inc...", name: "Work", ...}
# }

# What's on the calendar today?
today = ~o"2026-04-21"
{:ok, today_events} = Tempo.intersection(calendar, today)

# What time am I actually busy?
{:ok, busy} = Tempo.union(calendar, %Tempo.IntervalSet{})
# Unioning with an empty set coalesces overlapping events into
# busy-time spans.

# When am I free during work hours?
work_hours = ~o"2026-04-21T09/2026-04-21T17"
{:ok, free} = Tempo.difference(work_hours, calendar)
```

Every result is a standard `%Tempo.IntervalSet{}`. Event metadata from the source calendar is preserved on whichever intervals came from those events.

## 2. Setup

`Tempo.ICal` depends on the [`ical`](https://github.com/expothecary/ical) library, declared `optional: true` on Tempo's side. Pull it into your own project:

```elixir
def deps do
  [
    {:tempo, "~> 0.2"},
    {:ical, github: "expothecary/ical"}
  ]
end
```

The GitHub version is used rather than the hex release because Tempo targets `gettext ~> 1.0`, while the hex release of `ical` transitively requires an older `gettext`. The GitHub main branch has dropped that dependency.

## 3. What each event produces

A `VEVENT` becomes a `%Tempo.Interval{}`:

| iCalendar property | Tempo placement |
|---|---|
| `DTSTART` (date) | `interval.from` at day resolution |
| `DTSTART` (datetime) | `interval.from` at datetime resolution |
| `DTEND` | `interval.to` at matching resolution |
| `TZID` (on DTSTART/DTEND) | `interval.from.extended.zone_id` via `Tempo.from_elixir/2` |
| `UID` | `metadata.uid` |
| `SUMMARY` | `metadata.summary` |
| `DESCRIPTION` | `metadata.description` |
| `LOCATION` | `metadata.location` |
| `STATUS` | `metadata.status` (atom like `:tentative`) |
| `TRANSPARENCY` | `metadata.transparency` |
| `CATEGORIES` | `metadata.categories` (list) |
| `URL` | `metadata.url` |
| `CLASS` | `metadata.classification` |
| `PRIORITY` | `metadata.priority` |
| `ORGANIZER` | `metadata.organizer` (name or inspected struct) |
| `ATTENDEE`s | `metadata.attendees` (list of names or inspected structs) |
| `X-*` custom | `metadata.custom` (map) |

The `VCALENDAR` envelope produces set-level metadata on the `IntervalSet`:

| Envelope property | Set-level metadata |
|---|---|
| `PRODID` | `metadata.prodid` |
| `VERSION` | `metadata.version` |
| `CALSCALE` | `metadata.scale` |
| `METHOD` | `metadata.method` |
| `X-WR-CALNAME` | `metadata.name` |

## 4. Metadata flows through set operations

The key promise: once an event is in Tempo, its metadata travels with any portion of it that survives set operations.

```elixir
# A design review meeting
event = %Tempo.Interval{
  from: ~o"2026-04-21T10:30",
  to: ~o"2026-04-21T11:30",
  metadata: %{summary: "Design review", location: "Room 101"}
}

# Clip to work hours
{:ok, clipped} = Tempo.intersection(event, ~o"2026-04-21T09/2026-04-21T17")
[iv] = Tempo.IntervalSet.to_list(clipped)

iv.metadata.summary
# "Design review"  — preserved through the intersection
```

The rule: **result intervals inherit the A-operand's per-interval metadata**. For `intersection/2`, every result fragment stays tagged with the source event's metadata. For `difference/2`, the uncovered portions of A keep A's metadata. Set-level metadata (calendar `PRODID` etc.) follows the first operand through all operations.

## 5. Overlapping events are preserved

Real calendars routinely have overlapping events — a travel event on top of a lunch meeting, an all-day conference covering several one-hour talks. `Tempo.ICal.from_ical/2` returns **an IntervalSet with overlaps preserved**; it doesn't coalesce because that would destroy event identity.

```elixir
{:ok, set} = Tempo.ICal.from_ical(ics)
# The set may contain overlapping intervals — each one a
# distinct VEVENT with its own metadata.
```

When you want free/busy spans (coalesced time), compute them explicitly:

```elixir
# Either: empty-set union coalesces
{:ok, busy} = Tempo.union(set, %Tempo.IntervalSet{})

# Or: pass through Tempo.IntervalSet.new/1 (which defaults to coalesce: true)
{:ok, busy} = Tempo.IntervalSet.new(Tempo.IntervalSet.to_list(set))
```

## 6. Free/busy patterns

The most common iCal workflow:

```elixir
# 1. Import calendars
{:ok, work} = Tempo.ICal.from_ical_file("work.ics")
{:ok, personal} = Tempo.ICal.from_ical_file("personal.ics")

# 2. Merge into one busy-set
{:ok, all_busy} = Tempo.union(work, personal)

# 3. Find free time within a window
work_hours = ~o"2026-04-21T09/2026-04-21T17"
{:ok, free} = Tempo.difference(work_hours, all_busy)

# 4. Enumerate free slots
Tempo.IntervalSet.map(free, &Tempo.Interval.endpoints/1)
```

## 7. Recurrence expansion

Events with an `RRULE` materialise through a single pipeline:

```
%ICal.Recurrence{}  ─┐
                     ├──► Tempo.RRule.Expander.to_ast/3 ──► %Tempo.Interval{}
RRULE string ────────┘                                         │
                                                               ▼
                                                     Tempo.to_interval/2
                                                               │
                                                               ▼
                                                    Tempo.RRule.Selection
                                                               │
                                                               ▼
                                                     [%Tempo.Interval{}]
```

Every RFC 5545 BY-rule flows through one interpreter — there is no "simple core" and no "full expander" split. Each occurrence is a distinct `%Tempo.Interval{}` with the event's metadata attached.

### Supported rule parts

| Part         | Support                                                     |
| ------------ | ----------------------------------------------------------- |
| `FREQ`       | `SECONDLY`, `MINUTELY`, `HOURLY`, `DAILY`, `WEEKLY`, `MONTHLY`, `YEARLY` |
| `INTERVAL`   | Positive integer; applied as `DTSTART + i × INTERVAL`       |
| `COUNT`      | Terminates after N materialised occurrences (post-filter)   |
| `UNTIL`      | Date or UTC datetime; inclusive                             |
| `BYMONTH`    | LIMIT generally; EXPAND for `FREQ=YEARLY`                   |
| `BYMONTHDAY` | LIMIT generally; EXPAND for `FREQ=MONTHLY` / `YEARLY`. Signed indexing (`-1` = last day of the month) |
| `BYYEARDAY`  | LIMIT generally; EXPAND for `FREQ=YEARLY`. Signed           |
| `BYWEEKNO`   | EXPAND for `FREQ=YEARLY` (ISO week, Monday-first). Signed   |
| `BYDAY`      | LIMIT for `DAILY` and finer. EXPAND within the enclosing week / month / year for `WEEKLY` / `MONTHLY` / `YEARLY`. Ordinal prefixes (`1MO`, `-1FR`, `4TH`) select the Nth weekday of the enclosing period via `Calendrical.Kday.nth_kday/3`. RFC Notes 1/2 downgrade to LIMIT when BYMONTHDAY / BYYEARDAY is co-present |
| `BYHOUR`     | EXPAND when `FREQ` is coarser than hour; LIMIT otherwise    |
| `BYMINUTE`   | Same pattern at the minute unit                             |
| `BYSECOND`   | Same pattern at the second unit                             |
| `BYSETPOS`   | Applied last, across the per-period candidate set. Signed   |
| `WKST`       | Week-start day (default Monday). Affects `FREQ=WEEKLY + BYDAY` week boundaries |
| `RDATE`      | Extra occurrences; carry the event's span                   |
| `EXDATE`     | Subtracted from the combined set by start-moment match      |

### Termination paths

- **`COUNT=N`** — stop after N materialised occurrences (after BY-rule filtering / expansion).
- **`UNTIL=<date-or-datetime>`** — stop when the next occurrence would start past `UNTIL`.
- **No `COUNT` or `UNTIL`** — a `:bound` option is required at the call site. The rule expands within the bound.

### Worked examples

```elixir
# "Every Friday the 13th, 5 occurrences"
ics = "...RRULE:FREQ=MONTHLY;BYDAY=FR;BYMONTHDAY=13;COUNT=5..."
{:ok, set} = Tempo.ICal.from_ical(ics)
# => 1998-02-13, 1998-03-13, 1998-11-13, 1999-08-13, 2000-10-13

# "The 4th Thursday of November" (US Thanksgiving)
ics = "...RRULE:FREQ=YEARLY;BYMONTH=11;BYDAY=4TH;COUNT=3..."
{:ok, set} = Tempo.ICal.from_ical(ics)
# => 2022-11-24, 2023-11-23, 2024-11-28

# "Last weekday of every month"
ics = "...RRULE:FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1;COUNT=3..."
{:ok, set} = Tempo.ICal.from_ical(ics)

# With RDATE + EXDATE
ics = """
...
RRULE:FREQ=WEEKLY;COUNT=3
RDATE:20220618T140000Z
EXDATE:20220608T090000Z
...
"""
{:ok, set} = Tempo.ICal.from_ical(ics)
# Weekly series has Jun 8 removed and Jun 18 14:00 added
```

### DTSTART is always the first occurrence

Per RFC 5545, `DTSTART` is the first instance in the recurrence. When `BY*` rules EXPAND, they can legitimately produce candidates earlier than `DTSTART` in the same period — the resolver drops these automatically so the emitted list starts at (or after) `DTSTART`.

### Calendar-aware throughout

Every arithmetic operation goes through the candidate's own calendar (`calendar.day_of_week/4`, `calendar.days_in_month/2`, `calendar.iso_week_of_year/3`, `Date.add/2` with the calendar arg, `Calendrical.Kday.nth_kday/3`). A Hebrew-calendar VEVENT with `FREQ=YEARLY;BYMONTHDAY=-1` expands correctly against Hebrew month lengths.

## 8. What's not in v1

- **`EXRULE`** — RFC-deprecated (RFC 2445 → 5545) and not surfaced by the underlying `ical` library. If you need subtractive rules, use `EXDATE` for specific dates.

- **Multiple `RRULE` per `VEVENT`** — RFC 5545 says SHOULD NOT. Some exports do it anyway; the `ical` library exposes only the first `RRULE` on `event.rrule`, so we materialise that one and silently ignore the rest.

- **Duration-only events.** `VEVENT`s with `DURATION` but no `DTEND` — the `ical` library exposes the duration in its own record shape that doesn't line up with Tempo's `%Tempo.Duration{}`. Bridging the two is a small follow-up.

- **VTIMEZONE definitions.** `VTIMEZONE` blocks in the input are used by the `ical` library to resolve zoned DTSTART/DTEND values, but Tempo itself relies on Tzdata for zone calculations. Zones not in Tzdata (historical / non-standard zones defined in the `VTIMEZONE`) may not round-trip cleanly.

- **Export.** `Tempo → iCalendar` (going the other way) isn't implemented. Tempo emits RRULE via `to_rrule/1` for individual values; a full `to_ical/1` that produces a VCALENDAR envelope with VEVENTs is a future step.

## 9. Related reading

- [`guides/set-operations.md`](./set-operations.md) for how to combine imported calendars.
- [`guides/enumeration-semantics.md`](./enumeration-semantics.md) for how iteration works over the resulting IntervalSets.
- [RFC 5545](https://www.rfc-editor.org/rfc/rfc5545) for the iCalendar spec itself.
