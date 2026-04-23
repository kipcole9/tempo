# Set operations

Tempo implements the core set operations — union, intersection, complement, difference, symmetric difference — with **member-preserving** semantics by default. Companion predicates (`disjoint?/2`, `overlaps?/2`, `subset?/2`, `contains?/2`, `equal?/2`) operate at the instant-set level.

Every operation accepts any Tempo shape — an implicit `%Tempo{}`, an `%Tempo.Interval{}`, a `%Tempo.IntervalSet{}`, or an all-of `%Tempo.Set{}` — and returns a `%Tempo.IntervalSet{}` (or a boolean for predicates). The top-level API lives on the `Tempo` module: `Tempo.union/2`, `Tempo.intersection/2`, and so on.

## 0. Member-preserving vs instant-level

This is the most important distinction in Tempo's set algebra, and the one that drives every design decision below.

A `%Tempo.IntervalSet{}` represents **a set of distinct member intervals** — typically events, bookings, meetings, holidays, or any domain object with identity and metadata. Set operations respect that identity:

* **`Tempo.union/2`** — concatenates the members of both operands. Two touching year-intervals stay two members, not one merged span.

* **`Tempo.intersection/2`** — returns the members of A that overlap any member of B, kept whole with their original metadata. This is "which of these bookings hit the query window?".

* **`Tempo.difference/2`** — returns the members of A that *don't* overlap any member of B, kept whole. This is "which workdays aren't holidays?".

* **`Tempo.symmetric_difference/2`** — members of either operand that don't overlap any member of the other.

Some questions are about **covered instants** rather than members: "is this point in a busy period?", "what's the total free time?", "are these two schedules equivalent?". For those, Tempo exposes parallel **instant-level** operations that trim and compute at the point level:

* **`Tempo.overlap_trim/2`** — each result interval is the *portion* of an A member trimmed to the overlap with some B member. Members can split into multiple fragments.

* **`Tempo.split_difference/2`** — each A member is trimmed to its non-overlapping portions of B, possibly splitting one member into multiple fragments.

* **`Tempo.complement/2`** — coalesces internally; returns the uncovered portions of a bound.

* **`Tempo.IntervalSet.coalesce/1`**, **`covered?/2`**, **`total_duration/1`** — canonical instant-set queries on an IntervalSet.

The test: **if your question is about events or members, use the default operations; if it's about covered time, use the instant-level variants.** "Which bookings overlap this window?" uses `intersection`. "How much overlapping time is there?" uses `overlap_trim` + `total_duration`.

## 1. The three rules

Before any operation runs, both operands are **aligned** by a shared preflight. Three rules govern that alignment.

### 1.1. Resolution — finer wins

Given operands at different resolutions, the coarser one is extended to the finer one before math runs. This is lossless: extending `2022Y` to day resolution yields `[2022-01-01, 2023-01-01)` — the same span, just more explicit.

```
iex> {:ok, set} = Tempo.intersection(~o"2022Y", ~o"2022-06-15")
iex> Tempo.IntervalSet.count(set)
1
```

The result's endpoints are at day precision — the finer of the two inputs. The alternative (truncate the finer operand to year) would silently destroy information.

### 1.2. Timezone — compare via UTC, inherit first operand's zone

Each operand keeps its wall-clock time and zone as authoritative. When set operations need to compare endpoints across zones, Tempo computes UTC projections on demand — per-operation, never cached. The result's `extended.zone_id` comes from the first operand, so the caller controls the display frame.

A Paris 12:00 CEST interval compares equal to a UTC 10:00 interval because they map to the same UTC instant. Tzdata updates don't invalidate stored values — nothing UTC-shaped is stored — so results stay stable when IANA pushes new zone rules.

### 1.3. Calendar — first operand's calendar wins

If the operands are in different calendars (Gregorian vs Hebrew, say), the second is converted to the first's calendar before math runs. Each endpoint of the second operand is extended to day precision, then year/month/day are converted via `Date.convert!/2`; hour/minute/second pass through unchanged (those units are calendar-independent). The result's calendar is the first operand's.

```elixir
hebrew_day = Tempo.new!(year: 5782, month: 10, day: 16, calendar: Calendrical.Hebrew)
# Hebrew 5782-10-16 corresponds to Gregorian 2022-06-15.

Tempo.overlaps?(hebrew_day, ~o"2022-06-15")
# => true

Tempo.disjoint?(hebrew_day, ~o"2023-01")
# => true
```

## 2. The anchor-class rule

A Tempo value is **anchored** when it has a year-level component — it's a position on the universal time line. A **non-anchored** value is a pure time-of-day (`~o"T10:30"`) — it represents a recurring pattern, 10:30 on every day, with no anchor. A `Tempo.Duration` is neither — it's a length, not a set of instants.

Set operations require **both operands to share an anchor class**:

| A | B | Valid without `:bound`? |
|---|---|---|
| anchored | anchored | ✓ compare on universal time line |
| non-anchored | non-anchored | ✓ compare on time-of-day axis |
| anchored | non-anchored | needs `:bound` |
| duration | anything | always raises — anchor it first |

The cross-axis case *is* mathematically defined — a bare time-of-day is an infinite set of 1-second slots (one per day), and an anchored operand bounds it to finite occurrences. But picking the universe (what year range does "every day" mean?) isn't something Tempo can do without inventing a default. The `:bound` option makes the choice explicit:

```elixir
# No bound — raises
Tempo.intersection(~o"2026-01-04", ~o"T10:30")
# ** (ArgumentError) Set operations between an anchored operand and a 
#    non_anchored operand require a `:bound` option to anchor the 
#    non-anchored side. Alternatively, use `Tempo.anchor/2` to combine 
#    a date-like value with a time-of-day value before the operation.

# With bound — works
Tempo.intersection(~o"2026-01-04", ~o"T10:30", bound: ~o"2026-01-04")
# {:ok, #Tempo.IntervalSet<[~o"2026Y1M4DT10H30M/2026Y1M4DT10H31M"]>}
```

The `:bound` option is also required on `complement/2` — for the same reason. An unbounded complement is infinite; Tempo refuses to pick a universe.

### The `anchor/2` primitive

When you want to *compose* a date with a time-of-day rather than intersect them, use `Tempo.anchor/2`. This is axis composition, not a set operation, and no algebraic laws apply — it's a constructor.

```elixir
iex> Tempo.anchor(~o"2026-01-04", ~o"T10:30")
~o"2026Y1M4DT10H30M"
```

## 3. The operations

### Union — member-preserving

All members of both operands, kept as distinct intervals with their original metadata.

```elixir
iex> {:ok, r} = Tempo.union(~o"2022Y", ~o"2023Y")
iex> Tempo.IntervalSet.count(r)
2                                    # two distinct year members
```

For the canonical instant-set form (touching members merged into one span), coalesce explicitly:

```elixir
iex> {:ok, r} = Tempo.union(~o"2022Y", ~o"2023Y")
iex> r |> Tempo.IntervalSet.coalesce() |> Tempo.IntervalSet.count()
1                                    # [2022-01-01, 2024-01-01)
```

Identities hold at the instant-set level: `∅ ∪ A` has the same covered instants as `A`; `A ∪ B` and `B ∪ A` differ only in sort order, which is normalised.

### Intersection — member-preserving overlap-filter

Members of `a` that overlap any member of `b`, kept whole.

```elixir
iex> {:ok, r} = Tempo.intersection(~o"2022Y", ~o"2022-06-15")
iex> [iv] = Tempo.IntervalSet.to_list(r)
iex> Tempo.year(iv)
2022                                 # the year member is kept whole
```

The surviving A member inherits A's calendar and metadata; the operand's time range is used only to decide *whether* to keep the member, not to trim it.

For the trimmed instant-level form:

```elixir
iex> {:ok, r} = Tempo.overlap_trim(~o"2022Y", ~o"2022-06-15")
iex> [iv] = Tempo.IntervalSet.to_list(r)
iex> Tempo.day(iv)
15                                   # trimmed to the day-shaped overlap
```

### Complement — instant-level

Every instant in the universe that is NOT covered by any member of `set`. The `:bound` option is **required**. Internally coalesces before computing gaps.

```elixir
iex> {:ok, r} = Tempo.complement(~o"2022-06", bound: ~o"2022Y")
iex> Tempo.IntervalSet.count(r)
2                                    # January–May and July–December
```

An unbounded complement is infinite; Tempo refuses to pick a universe implicitly.

### Difference — member-preserving anti-overlap-filter

Members of `a` that do NOT overlap any member of `b`, kept whole.

```elixir
iex> workdays = Tempo.select!(window, Tempo.workdays(:US))
iex> {:ok, net_workdays} = Tempo.difference(workdays, holidays)
# each surviving workday is a distinct day-member, holidays removed
```

A member of `a` is dropped entirely if any member of `b` overlaps it, even partially. For a single `a` member that partially overlaps `b`, that member is dropped — use `split_difference/2` to keep its non-overlapping portions:

```elixir
iex> {:ok, r} = Tempo.split_difference(~o"2022Y", ~o"2022-06")
iex> Tempo.IntervalSet.count(r)
2                                    # Jan–Jun and Jul–Dec
```

### Symmetric difference — member-preserving

`A △ B` — members of either operand that don't overlap any member of the other. Derived from `(A \ B) ∪ (B \ A)`.

```elixir
iex> {:ok, r} = Tempo.symmetric_difference(~o"2020Y", ~o"2022Y")
iex> Tempo.IntervalSet.count(r)
2                                    # disjoint operands → both members survive
```

For the instant-level "only the non-shared portions" form, use `split_difference` on both directions and union:

```elixir
iex> a = ~o"2022-01/2022-07"
iex> b = ~o"2022-04/2022-10"
iex> {:ok, left}  = Tempo.split_difference(a, b)
iex> {:ok, right} = Tempo.split_difference(b, a)
iex> {:ok, trim}  = Tempo.union(left, right)
iex> Tempo.IntervalSet.count(trim)
2                                    # Jan–Mar and Jul–Oct (the trimmed edges)
```

### Predicates — instant-level

All return booleans. Predicates answer "covered instants" questions — they ignore member identity and compare the coalesced forms.

```elixir
iex> Tempo.disjoint?(~o"2020Y", ~o"2022Y")
true

iex> Tempo.overlaps?(~o"2022Y", ~o"2022-06")
true

iex> Tempo.subset?(~o"2022-06", ~o"2022Y")
true                                 # June ⊆ 2022

iex> Tempo.contains?(~o"2022Y", ~o"2022-06")
true                                 # 2022 ⊇ June (alias: subset?(b, a))

iex> Tempo.equal?(~o"2022Y", Tempo.from_iso8601!("2022-01-01/2023-01-01"))
true                                 # same covered instants, different representations
```

## 4. Algebraic laws

Set-algebra identities hold at the **instant-set level** — i.e. after coalescing, or equivalently, when compared via `Tempo.equal?/2`. The member-preserving operations don't satisfy laws like classical commutativity of intersection because they preserve A-side member identity; for that, use the instant-level variants (`overlap_trim`, `split_difference`) which do satisfy them:

- Commutativity: `overlap_trim(A, B) ≡ overlap_trim(B, A)` (same covered instants)
- Associativity: `(A ∪ B) ∪ C ≡ A ∪ (B ∪ C)` under coalescing
- Identity: `A ∪ ∅ ≡ A`, `overlap_trim(A, U) ≡ A` (with `U` = bound)
- De Morgan's laws: `¬(A ∪ B) ≡ ¬A ∩ ¬B` and `¬(overlap_trim(A, B)) ≡ ¬A ∪ ¬B` (within a common bound)

Tempo's test suite covers all of these.

Note that `≡` here is covered-instant equality (via `Tempo.equal?/2`), not member-list equality. Member-preserving `intersection` and `difference` are *not* commutative in the classical sense: `intersection(a, b)` returns A-side members, `intersection(b, a)` returns B-side — same covered instants, different members.

## 5. Edge cases

| Case | Behaviour |
|---|---|
| Empty IntervalSet on either side | Follows algebraic identities |
| Open-ended interval (`1985/..`) as operand | Raises — bound the interval first |
| Unbounded recurrence (`R/.../P1M`) | Raises — same reason |
| `Tempo.Duration` | Raises — durations aren't instant sets |
| One-of `Tempo.Set` (`[a,b,c]`) | Raises — epistemic disjunction, not IntervalSet |
| Cross-calendar operands | Second operand converted to first's calendar via `Date.convert!/2`; result inherits first's calendar |
| Cross-zone operands | Compared via UTC; result inherits first operand's zone |
| Midnight-crossing non-anchored interval (`T23:30/T01:00`) | Anchored to day D materialises as `[D T23:30, D+1 T01:00)`; on the time-of-day axis, split into `[T23:30, T24:00)` ∪ `[T00:00, T01:00)` before sweep-line |

## 6. Not in scope

- **Rule-algebra** — intersecting two infinite recurrences to produce a closed-form rule. Intentionally deferred; see `plans/set-operations.md` for the rationale.
- **UTC caching on IntervalSet** — projections are recomputed per operation. Enables stability across Tzdata updates; revisit if profiling shows the recomputation matters.

## 7. Implementation notes

- **Union**: concat + `IntervalSet.new/1` (which sorts but does *not* coalesce by default). O(n log n) on the combined input.
- **Intersection** (member-preserving): per-A-member overlap check against B. O(n × m) in the worst case; sweep-line optimisation planned for large sets.
- **Difference** (member-preserving): per-A-member anti-overlap check against B. Same complexity as intersection.
- **Symmetric difference**: derived as `(A \ B) ∪ (B \ A)`.
- **`overlap_trim`** (instant-level): sweep-line, O(n+m). Each step emits the trimmed overlap and advances whichever interval ends first.
- **`split_difference`** (instant-level): sweep-line over A with a running cursor into B, emitting A's uncovered portions.
- **`complement`**: internally coalesces the input and then calls `split_difference(bound, coalesced)`.

Implementation in `lib/operations.ex`. Shared comparison primitives in `lib/compare.ex`. Tests in `test/tempo/operations_test.exs`.
