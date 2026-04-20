# Plan: set operations on Tempo values

## Context

Every Tempo value is a bounded interval on the time line — or, after `to_interval/1`, an `IntervalSet` of sorted, coalesced disjoint intervals. The natural next step is **set operations**: union, intersection, complement, difference.

These operations answer real-world queries:

* Free/busy scheduling — "when am I free between these booked slots?" (complement)
* Calendar overlap — "do our trips to Paris overlap?" (intersection, overlaps?)
* Scheduling constraints — "all the days I'm in town AND the restaurant is open" (intersection)
* Difference queries — "when was I home but not at work?" (difference)

The prior-art research (`docs/prior-art.md`) identified PostgreSQL multirange as the conceptual model, with `%Tempo.IntervalSet{}` as Tempo's equivalent. This plan defines the operations that make IntervalSet a practically useful set-algebra type.

## Objective

Add a new module `Tempo.Operations` with the four core set operations plus predicates. Every operation accepts any Tempo value (implicit `%Tempo{}`, `%Tempo.Interval{}`, `%Tempo.IntervalSet{}`, all-of `%Tempo.Set{}`), routes through a single `align/2,3` preflight, and returns a `%Tempo.IntervalSet{}` (or boolean for predicates).

Top-level user API lives on `Tempo` for discoverability (`Tempo.union/2`, `Tempo.intersection/2`, …); implementation in `Tempo.Operations`.

## Half-open convention — unchanged

`%Tempo.Interval{from: a, to: b}` is `[a, b)`. Set operations honour this throughout:

* `[a, b) ∪ [b, c) = [a, c)` — touching intervals merge. (Already in `IntervalSet.new/1`.)
* `[a, c) ∩ [b, d) = [max(a, b), min(c, d))` — intersection uses half-open bounds.
* `complement([a, b), bound: [u, v)) = [u, a) ∪ [b, v)` — gaps are half-open.

## Design decisions

These were worked out in the set-operations design discussion (captured here for future reference).

### 1. Resolution alignment: use the **finer** of the two operands

Given operands at different resolutions, extend the coarser to match the finer via `Tempo.at_resolution/2`. This is information-preserving:

```
A = ~o"2022Y"        — coarser (year)
B = ~o"2022-06-15"   — finer (day)

Both compared at day precision:
A extended to day → [2022-01-01, 2023-01-01)
B unchanged      → [2022-06-15, 2022-06-16)

A ∩ B = [2022-06-15, 2022-06-16)   ✓ B is contained in A
```

The alternative (use the coarser / use the first operand's resolution) would round one operand and silently destroy information. Not acceptable for a library that prides itself on "no invalid dates, ever."

### 2. Timezone: compare via UTC, inherit first operand's zone on the result

Each operand keeps its wall-clock + `extended.zone_id` as authoritative. When set operations need to compare endpoints across zones, compute UTC projections on demand — per operation, not cached. The result's `extended.zone_id` comes from the first operand, so the caller controls the output's display frame.

Matches production calendar systems (Google, Microsoft, Apple all follow this pattern: wall-clock + zone is truth; UTC is derived). Tzdata updates don't invalidate stored IntervalSets because nothing UTC-shaped is stored.

### 3. Calendar: use the first operand's calendar; convert the second

If operands are in different calendars (Gregorian vs Hebrew vs Persian), the second is converted to the first's calendar before math runs. `Calendrical.convert/2` handles this. The result inherits the first's calendar.

### 4. Anchor-class compatibility (the big rule)

A Tempo is **anchored** if it has a year-level component — it has a position on the universal time line. Pure times-of-day (`~o"T10:30"`) are **non-anchored** — they're patterns that recur every day. Durations are **neither** — lengths without position.

Set operations require **both operands in the same anchor class**:

| A | B | Valid? |
|---|---|---|
| anchored | anchored | ✓ compare on universal time line |
| non-anchored | non-anchored | ✓ compare on time-of-day axis |
| anchored | non-anchored | needs `bound:` option |
| `Tempo.Duration` | anything | always raises — durations aren't instant sets |

The anchored/non-anchored mixed case is *mathematically* defined — `~o"T10:30"` represents "10:30 every day," an infinite set of minute-slots that an anchored interval can bound to a finite result. But the implicit universe choice (what year range does "every day" mean?) is something Tempo can't pick without lying. Require an explicit `bound:` when mixing; refuse otherwise.

This mirrors the `complement/2` rule: complement without a universe is infinite; require the universe to be stated explicitly.

### 5. Rule-based operations are deferred (unchanged from earlier decisions)

Set operations on rule-shaped values (RRULE-style patterns, unbounded recurrences) are genuinely hard and have no standard production implementation. IntervalSet is the operational form; rules are for enumeration and storage only. Any set op that encounters an unbounded recurrence requires `bound:` (same discipline as the other cases).

### 6. Always return `IntervalSet`

Composability beats terseness. Every operation returns `%Tempo.IntervalSet{}` — empty set for empty results, 1-element set for single-interval results. Predicates return booleans.

Callers that want a single interval can pattern-match `[one]` from `interval_set.intervals`.

## Step-by-step

### Step 1 — preflight `Tempo.Operations.align/2,3` (1 day)

The single entry point that normalises operands. Every public operation calls this first.

```elixir
@spec align(operand_a, operand_b, opts :: keyword) ::
        {:ok, {Tempo.IntervalSet.t(), Tempo.IntervalSet.t()}}
        | {:error, reason}
```

Options:

* `:bound` — a Tempo value that bounds non-anchored or unbounded operands. Required when anchor classes differ, when either operand contains unbounded open intervals, or when complement is called.

Pipeline:

1. Reject `%Tempo.Duration{}` and `%Tempo.Set{type: :one}` early with clear errors.
2. Classify each operand: `:anchored` / `:non_anchored` / `:interval_or_set`.
3. If classes differ, require `:bound` — if absent, raise with a message pointing at `bound:` or `Tempo.anchor/2`.
4. Convert both operands to `%Tempo.IntervalSet{}` via `Tempo.to_interval_set/1`.
5. Resolution alignment: find `max_res = finer_of(res_a, res_b)` and extend both to `max_res` (per-interval, via `at_resolution/2`).
6. Calendar: if they differ, convert second to first's calendar via `Calendrical.convert/2`.
7. Return the aligned pair.

Timezone conversion is deferred to per-operation UTC projection (below), not applied here.

### Step 2 — `union/2` (0.5 days)

Trivial given `IntervalSet.new/1`:

```elixir
def union(a, b) do
  with {:ok, {a, b}} <- align(a, b) do
    Tempo.IntervalSet.new(a.intervals ++ b.intervals)
    # `new/1` already sorts and coalesces.
  end
end
```

Cost: O((n+m) log (n+m)) for the sort. Could be O(n+m) with a merge-step, but we start with the cleaner implementation and optimise if profiling justifies.

### Step 3 — `intersection/2` (1 day)

Sweep-line over the two sorted IntervalSets:

```
i, j = 0, 0
result = []
while i < len(a) and j < len(b):
    overlap = max(a[i].from, b[j].from) ... min(a[i].to, b[j].to)
    if overlap is non-empty: result.append(overlap)
    # Advance the pointer whose interval ends first
    if a[i].to ≤ b[j].to: i += 1 else: j += 1
return IntervalSet.new(result)   # already sorted; coalesce is a no-op but cheap
```

Cost: O(n+m). Needs a `compare_endpoints/2` that handles zone-crossing comparisons via UTC projection. Compare helper lives in `Tempo.Operations.Compare` (extracted from `Enumerable.Tempo.Interval`'s existing `compare_time/2`).

### Step 4 — `complement/2` (1 day)

Requires explicit `bound:`. Walks the gaps between intervals, plus the margins of the bound:

```elixir
def complement(set, bound: u_bound) do
  u = to_interval_set!(u_bound)
  # For each interval in the bound, subtract the set's intervals
  # via walk-the-gaps. Easiest: compute `u \ set` via Step 5's
  # difference.
  difference(u, set)
end
```

Documented as "complement within the bound" — users who want unbounded complement don't exist in practice; everyone operates within a window.

### Step 5 — `difference/2` (1 day)

`A \ B = A ∩ complement(B, bound: span_of(A))`, but we implement it directly for efficiency:

```
Sweep-line similar to intersection, but when current A-interval
overlaps with B-intervals, subtract the overlaps and emit the gaps.
```

`symmetric_difference/2` derived: `(a \ b) ∪ (b \ a)`.

### Step 6 — predicates (0.5 days)

Short-circuit implementations — don't build the full result set:

```elixir
def disjoint?(a, b)      # early-exit on first overlap → false
def overlaps?(a, b)      # early-exit on first overlap → true (negation of disjoint?)
def subset?(a, b)        # a ⊆ b iff every interval in a is covered by b
def contains?(a, b)      # b ⊆ a (alias for subset?(b, a))
def equal?(a, b)         # aligned IntervalSets have identical interval lists
```

All share the `align/2,3` preflight. Predicates returning booleans never allocate an IntervalSet result.

### Step 7 — top-level `Tempo` API (0.5 days)

Delegate from `Tempo` to `Tempo.Operations`:

```elixir
defdelegate union(a, b), to: Tempo.Operations
defdelegate intersection(a, b, opts \\ []), to: Tempo.Operations
defdelegate complement(set, opts), to: Tempo.Operations
defdelegate difference(a, b, opts \\ []), to: Tempo.Operations
defdelegate symmetric_difference(a, b, opts \\ []), to: Tempo.Operations
defdelegate disjoint?(a, b, opts \\ []), to: Tempo.Operations
defdelegate overlaps?(a, b, opts \\ []), to: Tempo.Operations
defdelegate subset?(a, b, opts \\ []), to: Tempo.Operations
defdelegate contains?(a, b, opts \\ []), to: Tempo.Operations
defdelegate equal?(a, b, opts \\ []), to: Tempo.Operations
```

Discoverability: `Tempo.union/2` is the first thing users reach for.

### Step 8 — `Tempo.anchor/2` as a cross-axis primitive (0.5 days)

Separate from set operations. Combines a date-like value with a time-like value into a datetime.

```elixir
Tempo.anchor(~o"2026-01-04", ~o"T10:30:00")
# → ~o"2026-01-04T10:30:00"
```

This is *not* a set operation — it's axis composition. Documented as such; set-algebra laws don't apply. Callers who want "the time-of-day on this date" use `anchor/2`, then set ops run on the datetime result.

Uses `Tempo.merge/2` under the hood (already exists) but validated for cross-axis use only.

### Step 9 — UTC projection helper (1 day)

For zone-crossing comparisons: `Tempo.Operations.Compare.to_utc_instant/1`. Computes `{year, month, day, hour, minute, second}` in UTC given a zoned Tempo. Per-op, not cached (v1 decision).

Uses `Tzdata.zone_period_for_time/2` to find the DST era, applies the offset. Stable under Tzdata updates because nothing is persisted — next call re-derives.

### Step 10 — tests (2 days)

`test/tempo/operations_test.exs` covering:

* **Alignment** — each preflight step exercised in isolation.
* **Union** — commutativity, associativity, identity with empty set, touching/overlapping/disjoint cases.
* **Intersection** — commutativity, associativity, identity with bound set, touching/overlapping/disjoint, empty-result cases.
* **Complement** — De Morgan's laws across union/intersection.
* **Difference** — `A \ A = ∅`, `A \ ∅ = A`, `∅ \ A = ∅`, partial overlaps.
* **Predicates** — every pair of operand classes, symmetry checks.
* **Cross-axis refusal** — anchored ∩ non-anchored without `bound:` raises.
* **Cross-axis with bound** — same operation works, producing expected IntervalSet.
* **Timezone** — intersection across zones respects UTC-equivalence.
* **Calendars** — intersection across calendars uses first operand's calendar.
* **Duration rejection** — all operations raise on Duration operands.
* **One-of set rejection** — all operations raise on epistemic disjunctions.

### Step 11 — guide and CHANGELOG (0.5 days)

* New `guides/set-operations.md` with the three-question framing (anchored vs non-anchored, resolution alignment, zone/calendar) and worked examples for each operation.
* `CHANGELOG.md` entries (≤2 lines each per the project rule).
* Cross-reference from `guides/enumeration-semantics.md`.

## API summary

```elixir
## Core operations — all return %Tempo.IntervalSet{}
Tempo.union(a, b, opts \\ [])
Tempo.intersection(a, b, opts \\ [])
Tempo.complement(set, opts)                  # opts must include :bound
Tempo.difference(a, b, opts \\ [])
Tempo.symmetric_difference(a, b, opts \\ [])

## Predicates — return booleans
Tempo.disjoint?(a, b, opts \\ [])
Tempo.overlaps?(a, b, opts \\ [])
Tempo.subset?(a, b, opts \\ [])
Tempo.contains?(a, b, opts \\ [])
Tempo.equal?(a, b, opts \\ [])

## Cross-axis composition — not a set operation
Tempo.anchor(date_like, time_like)           # → %Tempo{} (datetime)

## Shared options across set operations
#   :bound       Bounding interval for non-anchored/anchored mixes
#                and complement. Accepts any Tempo value.
```

## Worked examples

```elixir
# Same-axis anchored operations
Tempo.union(~o"2022Y", ~o"2023Y")
# → %Tempo.IntervalSet{intervals: [[2022-01-01, 2024-01-01)]}   (coalesced)

Tempo.intersection(~o"2022Y", ~o"2022-06-15")
# → %Tempo.IntervalSet{intervals: [[2022-06-15, 2022-06-16)]}
# Resolution finer: day. 2022 extended to day bounds; intersect.

# Non-anchored operations (time-of-day axis)
Tempo.intersection(~o"T10", ~o"T10:30")
# → %Tempo.IntervalSet on the time-of-day axis:
#   intervals: [[T10:30, T10:31)]

# Complement requires a bound
Tempo.complement(~o"2022-06-15", bound: ~o"2022Y")
# → %Tempo.IntervalSet{intervals: [[2022-01-01, 2022-06-15), [2022-06-16, 2023-01-01)]}

# Anchored × non-anchored requires a bound
Tempo.intersection(~o"2020Y/2030Y", ~o"T10:30", bound: ~o"2020Y/2030Y")
# → IntervalSet of ~3650 daily 10:30 slots within the bound

# Without a bound, same call raises
Tempo.intersection(~o"2020Y", ~o"T10:30")
# ** (ArgumentError) Set operations between anchored and non-anchored
#    operands require an explicit `:bound` option. Alternatively, anchor
#    the non-anchored operand first using `Tempo.anchor/2`.

# Anchor is the explicit cross-axis combiner
Tempo.anchor(~o"2026-01-04", ~o"T10:30")
# → ~o"2026-01-04T10:30"

# Duration is never set-operable
Tempo.union(~o"2022Y", ~o"P3M")
# ** (ArgumentError) Cannot apply set operations to a Tempo.Duration — 
#    a duration is a length, not a set of instants.

# One-of sets are epistemic disjunctions, not IntervalSets
Tempo.union(~o"2022Y", ~o"[2020Y,2021Y,2022Y]")
# ** (ArgumentError) Cannot apply set operations to a one-of Tempo.Set 
#    (epistemic disjunction). Pick a specific member first.
```

## Edge cases called out explicitly

* **Empty IntervalSets** — algebraic identities:
  * `∅ ∪ A = A`
  * `∅ ∩ A = ∅`
  * `complement(∅, bound: U) = U`
  * `A \ ∅ = A`, `∅ \ A = ∅`
* **Open-ended intervals** as operands — raise. Same rule as enumeration: "provide a bound." Covers `1985/..`, `../1985`, `../..`.
* **Unbounded recurrence** (`R/2022-01/P1M` — no count) — raise. Require `bound:` at the call site.
* **DST-ambiguous endpoints** — resolved at interval construction time (per `Tempo.Interval` construction policy), not at set-op time. If a caller constructed ambiguous intervals, the UTC projection surfaces the error.
* **Calendar conversion errors** — a date that exists in one calendar but not another (rare, but possible with historical calendars) raises at preflight.

## Estimated effort

**8–10 working days.** Split:

* 1d — `align/2,3` preflight
* 0.5d — union
* 1d — intersection with sweep-line
* 1d — complement
* 1d — difference + symmetric_difference
* 0.5d — predicates
* 0.5d — top-level `Tempo` API delegation
* 0.5d — `Tempo.anchor/2`
* 1d — UTC projection helper
* 2d — tests (the big time sink)
* 0.5d — guide and CHANGELOG

Step 3 (intersection sweep-line with zone-crossing comparisons) and Step 10 (tests) are where bugs land.

## Dependencies

* **Depends on**: implicit-to-explicit interval conversion (`Tempo.to_interval_set/1`, `%Tempo.IntervalSet{}` — both landed). `Tempo.Math.add/2` / `subtract/2` (landed). `Tempo.at_resolution/2` (landed).

* **Blocks**: nothing in the current roadmap. Set operations are the current frontier.

## Non-goals

* **Rule-algebra.** Intersection of two unbounded recurrences producing a closed-form rule. Deferred indefinitely (see the rule-vs-IntervalSet discussion in `plans/implicit-to-explicit-interval-conversion.md`).
* **UTC-cache on IntervalSet.** Re-derive per op in v1. Profile before adding.
* **Custom universe inference for complement.** The user passes a bound explicitly. No magic default.
* **Allen's 13 relations as public API.** Used internally for case dispatch; the public predicates (`overlaps?/2`, `subset?/2`, etc.) cover the common needs.
* **Performance optimisation.** Clean, correct first. The sweep-line is already O(n+m); we can add B-tree indices for very large IntervalSets if profiling demands.
