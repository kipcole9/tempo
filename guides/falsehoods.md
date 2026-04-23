# Falsehoods Programmers Believe About Time

Every programmer who has worked seriously with calendars has their own version of this list. The falsehoods below are the ones with the largest bug-surface — the ones that are true for 95% of inputs, accepted by code review, and then silently wrong in production. Each one is followed by the Tempo idiom that makes the correct behaviour automatic.

The final section is honest: three things where Tempo does not yet improve the situation. Those deserve attention too.

---

## 1. "Every day has 24 hours"

Daylight-saving transitions add or remove an hour. A day that starts a DST spring-forward is 23 hours long; a day that ends a DST fall-back is 25 hours. Code that multiplies days by 86 400 seconds and adds the result to a zoned timestamp gets the wrong answer for roughly two days per year per zone.

**Traditional approach — silent wrong answer:**

```elixir
# 86_400 seconds later is NOT necessarily "the same time tomorrow"
DateTime.add(datetime, 86_400, :second)
```

**Tempo — the duration is computed correctly:**

```elixir
iex> iv = Tempo.Interval.new!(
...>   from: Tempo.from_iso8601!("2024-03-09T12:00:00[America/New_York]"),
...>   to:   Tempo.from_iso8601!("2024-03-10T12:00:00[America/New_York]")
...> )
iex> Tempo.Interval.duration(iv)
~o"PT82800S"
```

82 800 seconds is 23 hours. Spring forward in New York removes one hour from that calendar day — Tempo returns the real elapsed time, not 86 400.

---

## 2. "Every wall-clock time exists once and only once"

Two ways this is wrong:

* **Spring-forward gaps**: the clock jumps from 01:59 to 03:00, so 02:30 never appears.
* **Fall-back duplicates**: the clock rolls back from 02:00 to 01:00, so 01:30 appears twice.

Libraries that parse `"02:30 America/New_York"` on a spring-forward date and silently return *something* have hidden a bug behind convenience.

**Tempo — invalid wall times are rejected at parse time:**

```elixir
iex> Tempo.from_iso8601("2024-03-10T02:30:00[America/New_York]")
{:error, "Wall time 2024-03-10T02:30:00 does not exist in \"America/New_York\" (DST gap: clocks spring forward from 02:00 to 03:00). Supply a valid wall time or use a UTC offset to name the instant unambiguously."}
```

The error surfaces at the boundary — parse time — not hours later in a downstream calculation.

---

## 3. "01:30 during a fall-back refers to a single instant"

The fall-back duplicate is the mirror of the gap. When New York sets the clocks back, 01:30 EST occurs twice: once during EDT and once during EST. A bare `01:30` is ambiguous.

**Tempo — the UTC offset names which instant you mean:**

```elixir
iex> pre  = Tempo.from_iso8601!("2024-11-03T01:30:00-04:00[America/New_York]")
iex> post = Tempo.from_iso8601!("2024-11-03T01:30:00-05:00[America/New_York]")
iex> Tempo.Compare.to_utc_seconds(post) - Tempo.Compare.to_utc_seconds(pre)
3600
```

`-04:00` names the EDT instant; `-05:00` names the EST instant. They are 3 600 seconds apart. Tempo stores both the wall time and the offset, so the disambiguation is carried through every subsequent operation. Supplying neither offset makes the parse ambiguous — Tempo surfaces the ambiguity rather than guessing.

---

## 4. "Storing a future event as UTC is safe"

For past events this is fine. For future events it is wrong: DST rules change. When a government changes its zone rules after you stored a UTC instant, the UTC number is now stale — and you've lost the wall-clock information needed to recompute it.

**Tempo — store what the user said; project UTC on demand:**

```elixir
iex> event = Tempo.from_iso8601!("2030-03-01T08:00:00[Europe/Paris]")
iex> event.extended.zone_id
"Europe/Paris"
```

No UTC is stored on the struct. `Tempo.Compare.to_utc_seconds/1` consults Tzdata at call time, so re-evaluating after a Tzdata update automatically reflects any rule change. Serialise with `Tempo.to_iso8601/1`; the round-trip is faithful.

```elixir
iex> Tempo.to_iso8601(event)
"2030-03-01T08:00:00[Europe/Paris]"
```

---

## 5. "A minute has 60 seconds"

Occasionally it has 61. The IERS has inserted 27 positive leap seconds since 1972; the most recent was on 31 December 2016 at 23:59:60 UTC. Code that counts across that boundary and assumes 60-second minutes is off by one.

**Tempo — leap seconds are first-class interval metadata:**

```elixir
iex> iv = ~o"2016-12-31T23:59:00Z/2017-01-01T00:01:00Z"
iex> Tempo.Interval.spans_leap_second?(iv)
true
iex> Tempo.Interval.duration(iv)
~o"PT120S"
iex> Tempo.Interval.duration(iv, leap_seconds: true)
~o"PT121S"
```

`duration/1` returns the POSIX elapsed time (120 s). `duration/2` with `leap_seconds: true` returns the physical elapsed time (121 s). Both are correct for their purpose; Tempo exposes both. The `spans_leap_second?/1` predicate lets downstream code branch explicitly rather than silently dropping the second.

---

## 6. "1582-01-01 means the same thing everywhere"

The Gregorian calendar was adopted at different times in different countries. In England, the Julian calendar was used until 1752. In France, the switch happened in 1582. A date written as `1582-01-01` in a French historical record and the same date in an English record refer to different days on the astronomical time line — they are ten days apart.

**Tempo — the calendar is part of the value:**

```elixir
iex> julian_1582_jan1     = Tempo.from_iso8601!("1582-01-01[u-ca=julian]")
iex> gregorian_1582_jan1  = Tempo.from_iso8601!("1582-01-01")
iex> Tempo.overlaps?(julian_1582_jan1, gregorian_1582_jan1)
false
```

`[u-ca=julian]` is an IXDTF annotation; `Tempo.overlaps?/2` converts both values to the same astronomical reference frame before comparing. The two `1582-01-01` dates do not overlap.

---

## 7. "There is no year 0"

In the proleptic Gregorian calendar used by ISO 8601 and most programming environments, year 0 exists and represents 1 BCE. Year -1 is 2 BCE. Code that converts a signed year to a historical "n BCE" label by negating it is off by one for every negative year.

**Tempo — year 0 is a valid, parseable value:**

```elixir
iex> Tempo.from_iso8601("0000-01-01")
{:ok, ~o"0Y1M1D"}
iex> Tempo.from_iso8601("-0001-01-01")
{:ok, ~o"-1Y1M1D"}
```

`~o"0Y1M1D"` is 1 BCE; `~o"-1Y1M1D"` is 2 BCE. Label conversion requires `year_value + 1` when `year_value <= 0` — Tempo's calendar-aware display helpers do this correctly.

---

## 8. "February always has 28 or 29 days"

In the Hebrew calendar, the month Cheshvan (month 2) has 29 days in a regular year and 30 days in a complete year. So February-30 is invalid in the Gregorian calendar but valid for some Hebrew years. Month-length rules are calendar-specific and cannot be hard-coded.

**Tempo — month lengths are validated per calendar:**

```elixir
iex> Tempo.from_iso8601("2024-02-30")
{:error, "30 is not valid for day in 2024-02 (valid range 1..29)"}

iex> Tempo.from_iso8601("5785-02-30[u-ca=hebrew]")
{:ok, ~o"5785Y2M30D[u-ca=hebrew]"}

iex> Tempo.from_iso8601("5784-02-30[u-ca=hebrew]")
{:error, "30 is not valid for day in 5784-02 (valid range 1..29)"}
```

The calendar module in Tzdata supplies the correct `days_in_month/2` for each calendar system. Tempo delegates to it rather than hard-coding 28/29.

---

## 9. "Every location follows a 24-hour offset from UTC"

Samoa skipped 29 December 2011 entirely when it moved from UTC−11 to UTC+13 to align its calendar with Australia and New Zealand. The entire calendar day never existed for that territory.

**Tempo — the missing day is an error, not a silent correction:**

```elixir
iex> Tempo.from_iso8601("2011-12-29T12:00:00[Pacific/Apia]")
{:error, "Wall time 2011-12-29T12:00:00 does not exist in \"Pacific/Apia\" (DST gap: the calendar date was skipped when Samoa moved from UTC-11 to UTC+13 on 29 December 2011)."}
```

Any timestamp in that zone on that date is rejected. The same mechanism that catches DST gaps (falsehood #2) catches this one — the wall time is invalid in Tzdata and Tempo surfaces the error.

---

## 10. "Two timestamps represent the same instant if they show the same time"

`2026-04-15T10:30+05:30` and `2026-04-15T10:30+09:00` show the same wall-clock reading but are 3.5 hours apart. "Same time, different zone" is not "same instant." The Allen relation makes the structure explicit.

**Tempo — comparing two zoned times gives the correct Allen relation:**

```elixir
iex> a = Tempo.from_iso8601!("2026-04-15T10:30:00+05:30")
iex> b = Tempo.from_iso8601!("2026-04-15T10:30:00+09:00")
iex> Tempo.relation(a, b)
{:ok, :preceded_by}
```

`b` is 3.5 hours earlier in UTC — it precedes `a`. The comparison goes through UTC projection so the Allen relation reflects the real ordering on the time line, not the face value of the clock reading.

---

## Where Tempo won't help (yet)

The guide above shows Tempo making correct behaviour automatic. Here are three areas where it does not (yet) improve the situation, with recommendations.

### Sub-second precision in arithmetic and comparison

Tempo parses fractional seconds and stores them, but comparison and arithmetic at sub-second resolution currently fail:

```elixir
iex> Tempo.relation(~o"2024-06-15T12:00:00.1", ~o"2024-06-15T12:00:00.2")
{:error, "Cannot materialise a Tempo at :second resolution into an explicit interval"}
```

If your domain requires millisecond or microsecond arithmetic, you still need `DateTime` and `DateTime.diff/3` with `:millisecond`. **Recommendation**: extend the resolution ladder to `:millisecond` and `:microsecond` so that sub-second Tempo values materialise and compare correctly. The necessary unit arithmetic already exists in Calendar; the gap is in the resolution normalisation step.

### Monotonic time

Tempo has no abstraction over `System.monotonic_time/0`. Elapsed-duration measurements in benchmarks, timeouts, or retry loops should use `System.monotonic_time(:millisecond)` directly — using wall-clock intervals for that purpose is wrong in any library. **Recommendation**: document this boundary clearly (a `Time.Monotonic` note in the README is enough) so users know when to step outside Tempo. This is not a library gap so much as a boundary that should be named.

### Clock mocking in tests

Tempo has no equivalent of Elixir's `ExUnit.mock_time` or Erlang's `meck`. Tests that depend on "what is today" remain hard to write in a time-independent way. **Recommendation**: add a `Tempo.Clock` behaviour with a default `SystemClock` implementation and a `TestClock` stub that pins the current time. This is a narrow shim — five or six lines — and would make the "today" idioms in the cookbook and scheduling guide fully testable.

---

## Related reading

* [Scheduling](./scheduling.md) — how Tempo handles future dates, DST, floating vs zoned events, and bounded recurrence.
* [Set operations](./set-operations.md) — union, intersection, free/busy queries, and the sweep-line algorithm.
* [The cookbook](./cookbook.md) — recipe-format queries for the common patterns referenced here.
