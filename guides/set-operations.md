# Set operations

Tempo implements the core set operations — union, intersection, complement, difference, symmetric difference — and a companion set of predicates (`disjoint?/2`, `overlaps?/2`, `subset?/2`, `contains?/2`, `equal?/2`) on every Tempo value.

Every operation accepts any Tempo shape — an implicit `%Tempo{}`, an `%Tempo.Interval{}`, a `%Tempo.IntervalSet{}`, or an all-of `%Tempo.Set{}` — and returns a `%Tempo.IntervalSet{}` (or a boolean for predicates). The top-level API lives on the `Tempo` module: `Tempo.union/2`, `Tempo.intersection/2`, and so on.

## 1. The three rules

Before any operation runs, both operands are **aligned** by a shared preflight. Three rules govern that alignment.

### 1.1. Resolution — finer wins

Given operands at different resolutions, the coarser one is extended to the finer one before math runs. This is lossless: extending `2022Y` to day resolution yields `[2022-01-01, 2023-01-01)` — the same span, just more explicit.

```
iex> Tempo.intersection(~o"2022Y", ~o"2022-06-15")
{:ok, %Tempo.IntervalSet{intervals: [...]}}
```

The result's endpoints are at day precision — the finer of the two inputs. The alternative (truncate the finer operand to year) would silently destroy information.

### 1.2. Timezone — compare via UTC, inherit first operand's zone

Each operand keeps its wall-clock time and zone as authoritative. When set operations need to compare endpoints across zones, Tempo computes UTC projections on demand — per-operation, never cached. The result's `extended.zone_id` comes from the first operand, so the caller controls the display frame.

A Paris 12:00 CEST interval compares equal to a UTC 10:00 interval because they map to the same UTC instant. Tzdata updates don't invalidate stored values — nothing UTC-shaped is stored — so results stay stable when IANA pushes new zone rules.

### 1.3. Calendar — first operand's calendar wins

If the operands are in different calendars (Gregorian vs Hebrew, say), the second is converted to the first's calendar before math runs. Each endpoint of the second operand is extended to day precision, then year/month/day are converted via `Date.convert!/2`; hour/minute/second pass through unchanged (those units are calendar-independent). The result's calendar is the first operand's.

```elixir
hebrew_day = %Tempo{time: [year: 5782, month: 10, day: 16], calendar: Calendrical.Hebrew}
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
# {:ok, %Tempo.IntervalSet{intervals: [<2026-01-04 10:30-10:31>]}}
```

The `:bound` option is also required on `complement/2` — for the same reason. An unbounded complement is infinite; Tempo refuses to pick a universe.

### The `anchor/2` primitive

When you want to *compose* a date with a time-of-day rather than intersect them, use `Tempo.anchor/2`. This is axis composition, not a set operation, and no algebraic laws apply — it's a constructor.

```elixir
iex> Tempo.anchor(~o"2026-01-04", ~o"T10:30")
~o"2026Y1M4DT10H30M"
```

## 3. The operations

### Union

Every instant in either operand.

```elixir
iex> {:ok, r} = Tempo.union(~o"2022Y", ~o"2023Y")
iex> length(r.intervals)
1                                    # touching years coalesce

iex> {:ok, r} = Tempo.union(~o"2020Y", ~o"2022Y")
iex> length(r.intervals)
2                                    # non-touching stay separate
```

Identities: `∅ ∪ A = A`. Commutative: `A ∪ B = B ∪ A`.

### Intersection

Every instant in both operands.

```elixir
iex> {:ok, r} = Tempo.intersection(~o"2022Y", ~o"2022-06-15")
iex> [span] = r.intervals
iex> span.from.time[:day]
15                                   # the day is contained in the year
```

Identities: `∅ ∩ A = ∅`. Commutative. Half-open: touching intervals (`2022Y ∩ 2023Y`) share no instants; intersection is empty.

### Complement

Every instant in the universe that is NOT in `set`. The `:bound` option is **required**.

```elixir
iex> {:ok, r} = Tempo.complement(~o"2022-06", bound: ~o"2022Y")
iex> length(r.intervals)
2                                    # January–May and July–December
```

An unbounded complement is infinite; Tempo refuses to pick a universe implicitly.

### Difference

`A \ B` — every instant in `A` that is not in `B`.

```elixir
iex> {:ok, r} = Tempo.difference(~o"2022Y", ~o"2022-06")
iex> length(r.intervals)
2                                    # same as complement(2022-06, bound: 2022Y)
```

Identities: `A \ A = ∅`, `A \ ∅ = A`, `∅ \ A = ∅`.

### Symmetric difference

`A △ B` — instants in exactly one of `A` and `B`. Derived from `(A \ B) ∪ (B \ A)`.

```elixir
iex> a = ~o"2022-01/2022-07"
iex> b = ~o"2022-04/2022-10"
iex> {:ok, r} = Tempo.symmetric_difference(a, b)
iex> length(r.intervals)
2                                    # Jan-Mar and Jul-Sep (non-overlap portions)
```

### Predicates

All return booleans; all short-circuit where possible.

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
true                                 # same span, different representations
```

## 4. Algebraic laws

The operations satisfy the standard set-algebra identities, provided both operands are in the same anchor class or a `:bound` is supplied:

- Commutativity: `A ∪ B = B ∪ A`, `A ∩ B = B ∩ A`
- Associativity: `(A ∪ B) ∪ C = A ∪ (B ∪ C)` and similarly for ∩
- Identity: `A ∪ ∅ = A`, `A ∩ U = A` (with `U` = bound)
- De Morgan's laws: `¬(A ∪ B) = ¬A ∩ ¬B` and `¬(A ∩ B) = ¬A ∪ ¬B` (within a common bound)

Tempo's test suite covers all of these.

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

- Union: concat + `IntervalSet.new/1` (which sorts and coalesces). O(n log n) on the combined input.
- Intersection: sweep-line, O(n+m).
- Complement: derived as `difference(bound, set)`.
- Difference: sweep-line over A with a running cursor into B, emitting the uncovered portions.
- Symmetric difference: derived as `(A \ B) ∪ (B \ A)`.

Implementation in `lib/operations.ex`. Shared comparison primitives in `lib/compare.ex`. Tests in `test/tempo/operations_test.exs`.
