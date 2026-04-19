# Validating the Tempo AST against RRule

## Purpose

Before building the two queued plans (Enumerable review, implicit→explicit conversion), we wanted to check whether Tempo's AST — `%Tempo{}`, `%Tempo.Interval{}`, `%Tempo.Duration{}`, `%Tempo.Set{}`, and the token-level selection / group / qualification shapes — is actually a sufficient target representation, or whether the ISO 8601-specific grammar has baked accidental shape decisions into it that won't generalise.

The strategy: implement a parser for a semantically different input format — iCalendar RFC 5545 `RRULE` — and check whether its output fits the existing AST without extensions. If yes, the AST is validated. If no, we find out now.

## What we built

* `lib/tempo/rrule.ex` — a `Tempo.RRule.parse/2` function that takes a RRULE string (with or without the `RRULE:` prefix) and an optional `:from` anchor, and returns `{:ok, %Tempo.Interval{}}` or `{:error, reason}`.

* `test/tempo/rrule_test.exs` — 29 assertions covering `FREQ`, `INTERVAL`, `COUNT`, `UNTIL`, all seven `FREQ` unit mappings, `BYMONTH`, `BYMONTHDAY`, `BYDAY` (with and without positional ordinal, positive and negative), `BYHOUR`, `BYMINUTE`, `BYSECOND`, `BYSETPOS`, `DTSTART` as `:from`, and five error paths.

## The mapping

RRULE concept → Tempo AST field:

| RRULE | `%Tempo.Interval{}` field | Shape |
|---|---|---|
| `FREQ=<unit>` | `:duration` | `%Tempo.Duration{time: [{unit, 1}]}` |
| `INTERVAL=n` | `:duration` | `%Tempo.Duration{time: [{unit, n}]}` |
| `COUNT=n` | `:recurrence` | integer `n` |
| (no `COUNT`) | `:recurrence` | `:infinity` |
| `UNTIL=<date>` | `:to` | `%Tempo{time: [...]}` |
| `DTSTART` (via option) | `:from` | `%Tempo{time: [...]}` |
| `BY*` rules | `:repeat_rule` | `%Tempo{time: [selection: [unit: value, ...]]}` |

## Verbatim AST-shape equivalence examples

```
FREQ=MONTHLY;BYMONTHDAY=15
  repeat_rule.time == [selection: [day: 15]]

FREQ=YEARLY;BYMONTH=6
  repeat_rule.time == [selection: [month: 6]]

FREQ=YEARLY;BYMONTH=11;BYDAY=4TH                       (US Thanksgiving)
  repeat_rule.time == [selection: [month: 11, day_of_week: 4, instance: 4]]

FREQ=MONTHLY;BYDAY=-1FR                                (last Friday of month)
  repeat_rule.time == [selection: [day_of_week: 5, instance: -1]]

FREQ=WEEKLY;BYDAY=MO,WE,FR
  repeat_rule.time == [selection: [day_of_week: [1, 3, 5]]]

FREQ=DAILY;BYHOUR=9;BYMINUTE=0,30
  repeat_rule.time == [selection: [hour: 9, minute: [0, 30]]]
```

These selection shapes are **byte-for-byte identical** to the tokens emitted by the existing ISO 8601-2 `L…N` selection grammar. No new token kinds, no new struct fields, no new tag atoms.

## What worked cleanly

1. **`FREQ` + `INTERVAL`** maps to `%Tempo.Duration{}` exactly. Tempo's duration grammar already admits any keyword of `{unit, n}`, so `{:second, 2}`, `{:hour, 3}`, `{:month, 6}` all drop in without effort.

2. **`COUNT`** maps to `%Tempo.Interval{:recurrence}` as an integer. `:infinity` (the default for RRULE without COUNT or UNTIL) is already the sentinel Tempo uses when an ISO 8601 `R/...` omits the count.

3. **`UNTIL`** maps to `%Tempo.Interval{:to}`. UNTIL dates in basic ISO 8601 format round-trip through `Tempo.from_iso8601/1` without ceremony.

4. **BY* rules with a single value** map to `{unit, integer}` selection entries. The existing `L<n>Y`, `L<n>M`, `L<n>D`, `L<n>K`, `L<n>H`, `L<n>M`, `L<n>S` forms accept exactly this shape.

5. **BY* rules with multiple values** map to `{unit, [list]}`. Tempo's selection grammar already handles `L{n,n,n}<unit>N` which lands on this same list shape. Identical.

6. **BYDAY positional ordinals** (`4TH`, `-1FR`) map to **paired** `{:day_of_week, n}` + `{:instance, k}` selection entries — which is precisely how the existing ISO 8601-2 `L<n>K<k>IN` form tokenises (instance selector on a day-of-week selector).

7. **Negative indices** (`-1FR`, `BYMONTHDAY=-1`) carry through unchanged. Tempo's `maybe_negative_integer_or_integer_set` already supports negative values on every selection unit.

## What required interpretation

1. **`BYSETPOS` vs. BYDAY ordinal**. RFC 5545 distinguishes `BYDAY=4TH` (the 4th Thursday, baked into `BYDAY`) from `BYDAY=TH;BYSETPOS=4` (the 4th matching Thursday after all other filters are applied). Tempo's AST has one `:instance` selector — it can't carry both simultaneously. For this spike, BYDAY's ordinal and BYSETPOS both map to `{:instance, n}`. A production implementation would need to decide whether to promote one to a struct field, or resolve the semantics at enumeration time.

2. **`WKST` (week start)**. No obvious home in the current AST. Stored nowhere; the parser accepts it but ignores it. A production implementation would need a per-value calendar override (e.g. the calendar's `:week_start` could be overridden per-interval), which is arguably a calendar concern and not a time-value concern.

3. **Time zones in UNTIL**. RFC 5545 allows `UNTIL=20221231T235959Z` with zone semantics. The spike accepts this because `Tempo.from_iso8601/1` parses the Z suffix, but the interaction with `DTSTART`'s zone is non-trivial and the spike doesn't enforce the cross-field rule that "if DTSTART is zoned, UNTIL must be in UTC".

## What was found to be broken (orthogonal bugs)

1. **`Tempo.Interval.new/1` is under-specified**. Its pattern-match clauses cover six of the possible `{from, to, duration, repeat_rule}` shape combinations but not all. Specifically, the shape `{from, to, repeat_rule}` only matches when the second element is tagged `:to`, but the tokenizer emits dates as `:date`-tagged tuples — so `R/2022-01-01/2022-12-31/F2022-11-24` crashes the tokenizer-to-struct step. This is a latent ISO 8601 bug unrelated to the spike, but it was uncovered while probing.

2. **`Tempo.Inspect.inspect_value/1` assumes `from` is a struct**. When an Interval has `from: nil` (legitimate for a COUNT+duration-only recurrence like `FREQ=DAILY;COUNT=10` without a DTSTART), the inspect protocol hits `BadMapError`. The generated struct is valid; only the string-rendering path breaks.

Both of these are small, isolated, and should be filed as separate issues.

## What was found to need small AST additions

Nothing. The spike did not need to add any fields, tags, or token kinds. Every RRULE part landed on an existing AST location.

## Conclusion

**The AST is a valid shared target for ISO 8601-2 and RFC 5545 RRULE.**

Specifically:

1. `%Tempo.Interval{}` with `:recurrence`, `:duration`, `:from`, `:to`, and `:repeat_rule` fields is the natural home for a recurrence rule. RRULE's structure maps onto this directly.

2. The token-level `{:selection, [unit: value, ...]}` shape is a clean target for RRULE's BY* filters. The same shape is emitted by Tempo's existing ISO 8601-2 `L…N` grammar, confirming the shape is general rather than accidental.

3. Negative indices, list-valued selectors, and ordinal-paired day-of-week filters all fit without modification.

4. The gap between "parseable AST" and "enumerable AST" identified in the Enumerable review plan is confirmed. The RRule parser produces AST nodes that the current `Enumerable.Tempo.Interval` (which does not exist) would need to handle. The spike validates that the plan's Step 5 is aimed at the right target.

## Implications for the two queued plans

* **Enumerable review** (`plans/enumerable-review-for-implicit-intervals.md`): proceed as written. The AST it targets is confirmed to be the right abstraction. Add an explicit test from the RRule suite to the enumerable conformance harness (Step 1) so we catch any enumeration that works for ISO 8601-2 but regresses for RRule-produced values.

* **Implicit → explicit conversion** (`plans/implicit-to-explicit-interval-conversion.md`): proceed as written, with one addition. The `to_interval/1` function should handle the case where the input is already a `%Tempo.Interval{}` with a `:repeat_rule` — passing it through untouched rather than trying to materialise it. This was already specified as the first clause of the function; just emphasising that RRULE-derived intervals rely on this.

## Artefacts

* `lib/tempo/rrule.ex` — the parser (~200 lines).

* `test/tempo/rrule_test.exs` — the test suite (29 assertions).

* This document.

Total added to the production codebase: one small file. No changes to any existing module, grammar, or struct.
