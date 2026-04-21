# Enumeration semantics

Tempo implements the `Enumerable` protocol for `%Tempo{}`, `%Tempo.Set{}`, and `%Tempo.Interval{}`. This document explains what each value can and cannot be iterated over, and why.

## 1. The two kinds of iteration

Tempo values are **bounded intervals on the time line**, not instants. That informs two distinct iteration modes, each produced by a different shape of value:

* **Implicit enumeration — "drill into this span."** A single `%Tempo{}` at some resolution yields its sub-units. `Enum.take(~o"2022Y", 3)` yields `[2022Y1M, 2022Y2M, 2022Y3M]` — the year span is walked one month at a time. Implicit enumeration is the default when the value is a single resolved point at a coarser-than-finest resolution.

* **Forward-stepping — "walk across this interval."** A `%Tempo.Interval{}` yields each resolution-unit along the span. `Enum.take(%Tempo.Interval{from: ~o"1985Y", to: :undefined}, 3)` yields `[1985Y, 1986Y, 1987Y]` — successive years at the endpoint's own resolution.

Iteration always honours the **half-open `[from, to)` convention**: the lower bound is inclusive, the upper bound is exclusive. This makes adjacent intervals concatenate cleanly without overlap or gap.

`Tempo.to_interval/1` converts between the two forms: it takes any implicit-span `%Tempo{}` and returns the equivalent `%Tempo.Interval{}` with concrete `from` and `to` endpoints. Iteration on the explicit form is guaranteed to yield the same sequence as iteration on the implicit source (for every shape where both are defined — see §5.6 for the edge cases). `to_interval/1` is idempotent on values that are already intervals.

## 2. Enumerable — what you can iterate

### 2.1. Single `%Tempo{}` values

Every resolved Tempo at coarser-than-finest resolution is enumerable via implicit enumeration. The iteration unit is the next-finer unit that isn't already specified.

| Construct | Example | Yields |
|---|---|---|
| Year | `2022Y` | 12 months |
| Year-month | `2022-06` | days of June |
| Year-month-day | `2022-06-15` | 24 hours |
| Hour | `2022-06-15T10` | 60 minutes |
| Minute | `2022-06-15T10:30` | 60 seconds |
| Week | `2022-W24` | 7 days |
| Ordinal date | `2022-166` | 24 hours |

### 2.2. Explicit ranges and sets

Any component may carry a range, a range with step, a set of values, or a cartesian product of the above.

| Construct | Example | Iterates over |
|---|---|---|
| Inclusive range | `{1..3}M` | months 1, 2, 3 |
| Stepped range | `{1..-1//2}W` | every second week of the year |
| All-of set | `{2021,2022}Y` | 2021, then 2022 |
| One-of set | `[1984,1986,1988]` | exactly those three years |
| Cartesian product | `2022Y{1..2}M{1..2}D` | Jan 1, Jan 2, Feb 1, Feb 2 |

### 2.3. Missing / unknown digits (EDTF masks)

A digit marked `X` means "any value in this position." Tempo expands the mask to the range of candidate values and iterates it — the value is just as enumerable as an explicit range written with the same bounds.

| Construct | Example | Expanded range |
|---|---|---|
| Last digit unknown (year) | `156X` | `1560..1569` |
| Positive century masked | `1XXX` | `1000..1999` |
| Negative century masked | `-1XXX` | `-1999..-1000` (most-negative first) |
| Fully unspecified year | `XXXX` | `1000..9999` |
| Month-day masked | `1985-XX-XX` | year fixed, month/day iterate |
| Month only masked | `1985-XX-15` | year and day fixed, month iterates |

### 2.4. EDTF long-year shapes

| Construct | Example | Notes |
|---|---|---|
| `Y`-prefix short year | `Y2022` | same as `2022`; 12 months |
| `Y`-prefix long year | `Y12345` | single anchored year; 12 months |
| Exponent long year | `Y17E8` | 1 700 000 000; single anchored year |
| Significant-digits year | `1950S2` | block `1900..1999`; 100 × 12 months |
| Significant-digits long | `Y171010000S8` | block of 10 candidates |

Significant-digits blocks are capped at **10 000 candidates**. Larger blocks (e.g. `Y171010000S3`, which would be 10⁶ candidates) raise a clear `ArgumentError` — the parsed value is still usable as a data value, you just cannot iterate it.

### 2.5. Groups and selections

| Construct | Example | Behaviour |
|---|---|---|
| Group | `2022Y5G2MU` | "5th group of 2 months" = months 9–10; then iterates days |
| Selection | `2022YL1MN` | "the 1st month of 2022" — selection tuple preserved on every yielded value |

### 2.6. Qualifications (EDTF Level 1 and Level 2)

Qualifications describe epistemic state (`?` uncertain, `~` approximate, `%` both) and never affect whether a value is enumerable. They propagate verbatim to every yielded value.

| Construct | Example | Each yielded value carries |
|---|---|---|
| Expression-level | `2022Y?` | `qualification: :uncertain` |
| Leading | `?2022-06-15` | `qualification: :uncertain` |
| Approximate | `~2022` | `qualification: :approximate` |
| Component-level | `2022-?06-15` | `qualifications: %{month: :uncertain}` |
| Mixed components | `2022?-?06-%15` | per-component map |

### 2.7. IXDTF metadata

Time zone, calendar, and tagged suffixes attach to the `:extended` field and flow through enumeration unchanged.

| Construct | Example |
|---|---|
| Zone only | `2022-06-15T10:30[Europe/Paris]` |
| Calendar only | `2022-06-15T10:30[u-ca=hebrew]` |
| Zone + offset + calendar | `2022-06-15T10:30[+05:30][u-ca=hebrew]` |
| Per-endpoint on interval | `10:00[Europe/Paris]/12:00[Europe/London]` |

The endpoint that anchors iteration (`from`) provides the metadata carried on each yielded value.

### 2.8. Intervals — closed and forward-open

| Shape | Example | Iteration |
|---|---|---|
| Closed day | `1985-01-01/1985-01-04` | Jan 1, 2, 3 (half-open) |
| Closed month | `1985-12/1986-02` | Dec 1985, Jan 1986 |
| Closed week | `2022-W05/2022-W08` | W5, W6, W7 |
| Mismatched resolutions | `1985/1986-06` | 1985, 1986 (both start before Jun 1 1986) |
| Open upper | `1985/..` | 1985, 1986, 1987, … (use `Enum.take/2`) |
| Open upper, hour | `1985-01-01T10/..` | 10:00, 11:00, 12:00, … |
| Per-endpoint qualifier | `1984?/2004~` | 1984 through 2003, each carrying its endpoint's qualifier where applicable |

Mismatched-resolution endpoints are compared as their concrete start-moments: missing trailing units fill with their unit minimum (`:month` / `:day` / `:week` from 1, everything else from 0).

### 2.9. Implicit-to-explicit conversion (`Tempo.to_interval/1`)

Every enumerable `%Tempo{}` has an explicit equivalent — either a single `%Tempo.Interval{}` (contiguous span) or a `%Tempo.IntervalSet{}` (sorted, coalesced list of disjoint spans). `Tempo.to_interval/1` materialises the appropriate form under the half-open `[from, to)` convention. The conversion preserves every piece of source metadata (`:qualification`, `:qualifications`, `:extended`, `:shift`, `:calendar`) on both endpoints.

Call `Tempo.to_interval_set/1` if you always want the IntervalSet form (a single interval is wrapped in a one-element set).

| Input | `from.time` | `to.time` |
|---|---|---|
| `2026` | `[year: 2026, month: 1]` | `[year: 2027, month: 1]` |
| `2026-01` | `[year: 2026, month: 1, day: 1]` | `[year: 2026, month: 2, day: 1]` |
| `2026-01-15` | `[year: 2026, month: 1, day: 15, hour: 0]` | `[year: 2026, month: 1, day: 16, hour: 0]` |
| `2026-01-15T10` | `[…, hour: 10, minute: 0]` | `[…, hour: 11, minute: 0]` |
| `156X` | `[year: 1560]` | `[year: 1570]` |
| `-1XXX` | `[year: -1999]` | `[year: -999]` |
| `1985-XX-XX` | `[year: 1985]` | `[year: 1986]` |
| `1985-06-XX` | `[year: 1985, month: 6]` | `[year: 1985, month: 7]` |

Mask rules:

* A **year mask** (`156X`, `-1XXX`) translates directly to a year range via `Tempo.Mask.mask_bounds/1`. The signed half-open upper bound is computed as `-magnitude_min + 1` for negative masks.

* A **finer-unit mask** (`1985-XX-XX`, `1985-06-XX`, `1985-XX-15`) widens to the coarsest un-masked prefix and increments there. `1985-XX-XX` becomes year-resolution bounds because the mask at month-level can't map cleanly to a valid-month range; `1985-06-XX` keeps month resolution because only the day is masked.

* `1985-XX-15` (day specified, month masked) is semantically non-contiguous — the covered moments are "the 15th of any 1985 month" which isn't a single interval. `to_interval/1` accepts the looser bound (`[year: 1985]..[year: 1986]`) rather than returning a set.

`to_interval/1` is idempotent on existing intervals and interval sets. Multi-valued AST shapes (ranges, stepped ranges, iterated groups, all-of sets) materialise to `%Tempo.IntervalSet{}` with touching intervals coalesced under the half-open `[from, to)` rule. One-of sets (`[a,b,c]`) are *epistemic* (the value is one of these, we don't know which) and return an error from `to_interval/1` — flattening them would assert all members happened, which is semantically wrong. Bare `%Tempo.Duration{}` values also return an error (no anchor on the time line).

| Input shape | Result |
|---|---|
| Scalar `~o"2022Y"` | `%Tempo.Interval{}` |
| Contiguous range `~o"2022Y{1..3}M"` | `%Tempo.IntervalSet{}` with 1 coalesced member |
| Stepped range `~o"2022Y{1..-1//3}M"` | `%Tempo.IntervalSet{}` with N disjoint members |
| All-of set `~o"{2020,2021,2022}Y"` | `%Tempo.IntervalSet{}` (coalesced to 1 if touching) |
| One-of set `~o"[2020Y,2021Y,2022Y]"` | `{:error, "... epistemic disjunction ..."}` |
| Bare Duration `~o"P3M"` | `{:error, "... no anchor ..."}` |

### 2.10. `%Tempo.IntervalSet{}` — multi-interval values

`%Tempo.IntervalSet{intervals: [%Tempo.Interval{}, ...]}` holds a sorted, non-overlapping, coalesced list. The constructor `Tempo.IntervalSet.new/1` sorts by `from` endpoint and coalesces adjacent or overlapping intervals in a single sweep-line pass.

```
iex> {:ok, tempo} = Tempo.from_iso8601("2022Y{1..-1//3}M")
iex> {:ok, set} = Tempo.to_interval(tempo)
iex> Tempo.IntervalSet.count(set)
4
```

Enumeration walks each interval in time order, crossing interval boundaries seamlessly: `Enum.to_list(set)` on four month-sized intervals yields every day in each month, one interval at a time.

IntervalSet is the form used by set operations — `Tempo.union/2`, `Tempo.intersection/2`, `Tempo.complement/2`, `Tempo.difference/2`, and predicates. See `guides/set-operations.md` for the full treatment. Any call that needs a uniform-shape input can use `Tempo.to_interval_set/1`.

### 2.10. Seasons

The parser expands season codes into intervals before enumeration sees them.

| Code | Example | Expands to |
|---|---|---|
| Astronomical (25–32) | `2022-25` | March equinox to June solstice (computed via `Astro`) |
| Meteorological (21–24) | `2022-21` | March 1 to May 31 (calendar approximation) |

## 3. Not enumerable by design

These constructs *cannot* be enumerated, and no amount of future implementation will change that. They raise `ArgumentError` with a clear message, or the protocol falls back to `{:error, Enumerable.<Module>}` for calls like `Enum.count/1`.

### 3.1. Bare `%Tempo.Duration{}` values

A duration is a **length**, not a sequence. `P3M` means "three months" with no anchor on the time line. Iterating it would be nonsensical — three months starting *when*?

| Construct | Example |
|---|---|
| Pure duration | `P3M`, `P1Y2M3D`, `PT30M` |

A duration that *participates* in an interval (`1985-01/P3M`) is not a bare duration — see §4.1 for that case.

No `Enumerable` instance is defined for `Tempo.Duration`. Calls like `Enum.take(~o"P3M", 3)` raise `Protocol.UndefinedError`.

### 3.2. Fully open intervals

`../..` has no anchor at all. There is nowhere to start and nowhere to stop.

```
iex> {:ok, interval} = Tempo.from_iso8601("../..")
iex> Enum.take(interval, 3)
** (ArgumentError) Cannot enumerate a fully open interval `../..` — no anchor from which to start iteration.
```

### 3.3. Open-lower intervals

`../1985` has an upper anchor but no lower anchor. `Enumerable` iterates forward by protocol convention, which requires a lower bound. Iterating backwards from the upper bound would be surprising and would invert the half-open semantics.

```
iex> {:ok, interval} = Tempo.from_iso8601("../1985-12-31")
iex> Enum.take(interval, 3)
** (ArgumentError) Cannot enumerate an interval with an open lower bound `../to` — Enumerable iterates forward from the lower bound, which is not defined.
```

### 3.4. Values at the finest available resolution

A fully-specified second-resolution datetime has no finer unit to drill into. Tempo deliberately does not invent a sub-second "tick" unit — the value is a single indivisible moment at its declared resolution.

```
iex> {:ok, value} = Tempo.from_iso8601("2022-06-15T10:30:00Z")
iex> Enum.take(value, 1)
** (ArgumentError) Cannot enumerate a Tempo at :second resolution — no finer unit is defined. …
```

### 3.5. Significant-digits blocks larger than 10 000

`Y171010000S3` would expand to `171010000..171019999` — a million candidate years. Tempo refuses to iterate a block that large rather than hang or consume unbounded memory.

```
iex> {:ok, value} = Tempo.from_iso8601("Y171010000S3")
iex> Enum.take(value, 3)
** (ArgumentError) Cannot enumerate a significant-digits block of 1000000 candidates (limit: 10000). …
```

The parsed value itself is usable for comparison, equality, and round-trip serialisation; only iteration is refused.

## 4. Not enumerable — not yet implemented

These *will* be enumerable in future versions, but are not today. Each is pinned by a test that will force a conscious update when the implementation lands.

### 4.1. `count/1`, `member?/2`, `slice/1` on `Tempo.Interval`

All three currently return `{:error, Enumerable.Tempo.Interval}`, which tells Elixir's `Enum` module to fall back to iterating via `reduce/3`.

Precise implementations need:

* For `count/1` on closed intervals — Tempo-to-Tempo distance in resolution-units (calendar-aware).

* For `member?/2` — a full Tempo comparison (`lib/comparison.ex` is currently a template).

* For `slice/1` — addressing the Nth element directly.

Tracked with the set-operations milestone, which also depends on `Tempo.compare/2`.

### 4.2. `count/1` and `member?/2` on `%Tempo{}` and `%Tempo.Set{}`

Both return `{:error, Enumerable.Tempo}` / `{:error, Enumerable.Tempo.Set}` today. Will be filled in alongside the same comparison primitives as §4.2.

## 5. Semantic edge cases

### 5.1. "Missing" versus "unknown" versus "qualified"

Three similar-sounding situations have distinct enumeration meanings:

* **Missing (not specified).** `2022Y` simply omits finer units. The value is the *interval* of all of 2022 (§2.1) and implicit enumeration walks its months. **Fully enumerable.**

* **Unknown digit (`X` mask).** `156X` declares "this position is any valid digit." The mask expands to a **range** of candidate values (§2.3). **Fully enumerable.**

* **Qualified (`?`, `~`, `%`).** `2022Y?` is a concrete, fully-specified value — the year 2022 — annotated with uncertainty about the source. The qualification attaches to metadata; it does not change what is iterated (§2.6). **Fully enumerable.**

These three are semantically distinct and should not be conflated:

| Description | Syntax | What's iterated |
|---|---|---|
| "Some year in the 1560s" | `156X` | each year 1560..1569 |
| "All of the year 1560" | `1560` | each month of 1560 |
| "The year 1560, uncertainly" | `1560?` | each month of 1560, every yielded value flagged uncertain |

### 5.2. Qualification propagation on intervals

Per-endpoint qualifiers attach to that endpoint's `%Tempo{}` struct, not to the interior values.

```
iex> {:ok, interval} = Tempo.from_iso8601("1984?/2004~")
iex> interval.from.qualification
:uncertain
iex> interval.to.qualification
:approximate
```

When the interval is enumerated forward from `:from`, each yielded value inherits `:from`'s qualification. The `:to` endpoint's qualifier is a property of the boundary, not the interior.

### 5.3. IXDTF metadata propagation on intervals

Per-endpoint IXDTF suffixes (`[Europe/Paris]`) attach to that endpoint. A top-level IXDTF suffix on an interval propagates to each endpoint that does not already carry its own. Iteration walks forward from `:from`, so yielded values carry `:from`'s zone, offset, and calendar.

### 5.4. Calendar-aware increment

Forward-stepping through an interval uses `calendar.months_in_year/1`, `calendar.days_in_month/2`, `calendar.weeks_in_year/1`, and `calendar.days_in_week/0` for carry. Iterating an interval whose endpoint's calendar is Hebrew, Islamic, or any other supported calendar Just Works — the carry boundaries change to match.

### 5.5. DST transitions

Zone-aware iteration currently treats enumeration as operating on **wall-clock time** and passes the `zone_id` through unchanged on each yielded value. DST transitions are **not** compensated. Iterating hours across a DST boundary yields each wall-clock hour in turn, which may skip or repeat an instant-clock hour. This is a deliberate simplification and is documented so callers can choose to correct for it downstream.

### 5.6. Parity between implicit and explicit iteration

For every `%Tempo{}` where both implicit and explicit iteration are defined, the two produce identical sequences:

```
iex> {:ok, tempo} = Tempo.from_iso8601("2026-01")
iex> implicit = Enum.to_list(tempo)
iex> {:ok, interval} = Tempo.to_interval(tempo)
iex> explicit = Enum.to_list(interval)
iex> implicit == explicit
true
```

Known divergences:

* **Second-resolution values.** `~o"2026-01-15T10:30:00"` has no finer unit to drill into. Implicit iteration raises `ArgumentError`; `to_interval/1` raises a matching error. Neither form yields a value.

* **Masked values iterated implicitly.** The current implicit enumeration of masked values (`1985-XX-XX`) has known quirks — it does not always walk the full cartesian product of valid month/day pairs. `to_interval/1` widens to the coarsest un-masked prefix and produces a clean span; iterating that interval yields the straightforward forward-stepped sequence. Prefer the explicit form for set operations on masked values.

## 6. Summary table

| Category | Examples |
|---|---|
| **Enumerable** | every standard ISO 8601 / EDTF value with a concrete anchor — single values, ranges, sets, masks, long years, qualified values, IXDTF-tagged values, closed intervals, open-upper intervals, seasons, mixed-resolution intervals |
| **Not enumerable by design** | bare `%Tempo.Duration{}`, fully open intervals `../..`, open-lower intervals `../to`, values at finest resolution, significant-digits blocks > 10 000 candidates |
| **Not enumerable (deferred)** | exact `count/1` / `member?/2` / `slice/1` on intervals, `count/1` / `member?/2` on `%Tempo{}` and `%Tempo.Set{}` |
