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
[iv] = clipped.intervals

iv.metadata.summary
# "Design review"  — preserved through the intersection
```

The rule: **result intervals inherit the A-operand's per-interval metadata**. For `intersection/2`, every result fragment stays tagged with the source event's metadata. For `difference/2`, the uncovered portions of A keep A's metadata. Set-level metadata (calendar `PRODID` etc.) follows the first operand through all operations.

## 5. Overlapping events are preserved

Real calendars routinely have overlapping events — a travel event on top of a lunch meeting, an all-day conference covering several one-hour talks. `Tempo.ICal.from_ical/2` returns **an IntervalSet with overlaps preserved**; it doesn't coalesce because that would destroy event identity.

```elixir
{:ok, set} = Tempo.ICal.from_ical(ics)
# set.intervals may contain overlapping intervals — each one a
# distinct VEVENT with its own metadata.
```

When you want free/busy spans (coalesced time), compute them explicitly:

```elixir
# Either: empty-set union coalesces
{:ok, busy} = Tempo.union(set, %Tempo.IntervalSet{})

# Or: pass through Tempo.IntervalSet.new/1 (which defaults to coalesce: true)
{:ok, busy} = Tempo.IntervalSet.new(set.intervals)
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
free.intervals
|> Enum.map(fn iv -> {iv.from, iv.to} end)
```

## 7. Recurrence expansion

Events with an `RRULE` expand via `Tempo.Math.add/2`, stepping forward from `DTSTART` by the rule's cadence. Each occurrence is a distinct `%Tempo.Interval{}` with the event's metadata attached. Three termination paths, any of which works:

- **`COUNT=N`** — stop after N occurrences.
- **`UNTIL=<date-or-datetime>`** — stop when the next occurrence would start past `UNTIL`.
- **No `COUNT` or `UNTIL`** — a `:bound` option is required at the call site. The rule expands within the bound.

```elixir
# COUNT — 3 weekly standups
ics = "...RRULE:FREQ=WEEKLY;COUNT=3..."
{:ok, set} = Tempo.ICal.from_ical(ics)
length(set.intervals)  # => 3

# UNTIL — every Monday in June 2026
ics = "...RRULE:FREQ=WEEKLY;UNTIL=20260701T000000Z..."
{:ok, set} = Tempo.ICal.from_ical(ics)

# Bounded — every day in a chosen window
{:ok, set} = Tempo.ICal.from_ical(ics, bound: ~o"2026-04-01/2026-05-01")
```

The supported RRULE properties for full expansion are `FREQ`, `INTERVAL`, `COUNT`, and `UNTIL`.

## 8. What's not in v1

- **RRULE `BY*` rules** (`BYDAY`, `BYMONTH`, `BYSETPOS`, …) and `RDATE`/`EXDATE`. When any `BY*` rule is present, `Tempo.ICal` returns the first occurrence tagged `metadata.recurrence_note == :first_occurrence_only` and `metadata.recurrence_reason == :by_rules_not_supported`. Full expansion of these is a separate project — the `ical` library already parses them, but computing the correct occurrence set requires logic the iCalendar spec describes over pages.

- **Duration-only events.** `VEVENT`s with `DURATION` but no `DTEND` — the `ical` library exposes the duration in its own record shape that doesn't line up with Tempo's `%Tempo.Duration{}`. Bridging the two is a small follow-up.

- **VTIMEZONE definitions.** `VTIMEZONE` blocks in the input are used by the `ical` library to resolve zoned DTSTART/DTEND values, but Tempo itself relies on Tzdata for zone calculations. Zones not in Tzdata (historical / non-standard zones defined in the `VTIMEZONE`) may not round-trip cleanly.

- **Export.** `Tempo → iCalendar` (going the other way) isn't implemented. Tempo emits RRULE via `to_rrule/1` for individual values; a full `to_ical/1` that produces a VCALENDAR envelope with VEVENTs is a future step.

## 9. Related reading

- [`guides/set-operations.md`](./set-operations.md) for how to combine imported calendars.
- [`guides/enumeration-semantics.md`](./enumeration-semantics.md) for how iteration works over the resulting IntervalSets.
- [RFC 5545](https://www.rfc-editor.org/rfc/rfc5545) for the iCalendar spec itself.
