# Plan: convert implicit intervals to explicit intervals

## Context

Tempo's architecture (see `CLAUDE.md`) distinguishes two forms of bounded interval:

* **Implicit span**: a single datetime value whose stated resolution defines the span. `2026-01` *is* the interval `[2026-01-01, 2026-02-01)` — the span runs to the next unit at the given resolution.

* **Explicit span**: a pair of datetimes written with a range operator, such as `%Tempo.Interval{from: ..., to: ...}` or the EDTF form `2026-01-01/2026-02-01`.

Map and reduce on the implicit form is already implemented and iterates at the **next-higher resolution below what is stated** — iterating `2026-01` yields days; iterating `2026` yields months. Map and reduce on the explicit form iterates at the **resolution of its boundaries**.

The two forms are semantically equivalent for single values but diverge in iteration and set operations. The set-operations milestone (union / intersection / coalesce on lists of intervals) is dramatically simpler if every input is first materialised into the explicit form. This plan defines the conversion.

## Objective

Add a single public function, `Tempo.to_interval/1`, that takes any `%Tempo{}` value and returns the equivalent `%Tempo.Interval{}` with concrete `from` and `to` endpoints (half-open: `from` inclusive, `to` exclusive). After this lands, every construct in the Tempo vocabulary has a single canonical "bounded-pair" representation — the foundation for coalescing and set operations.

## Half-open convention

`%Tempo.Interval{from: start, to: end}` already represents `[start, end)` in this codebase. Every conversion below honours that:

* `2026-01` → `%Tempo.Interval{from: ~o"2026Y1M1D", to: ~o"2026Y2M1D"}` — **not** `2026-01-31`.
* `2026` → `from: 2026-01-01, to: 2027-01-01`.
* `2026-01-15T10` → `from: 2026-01-15T10:00, to: 2026-01-15T11:00`.

The upper bound is always the next-unit boundary, never "the last instant". This lets adjacent intervals concatenate cleanly (`[a, b) ++ [b, c) == [a, c)`).

## Design revision: multi-interval values and `%Tempo.IntervalSet{}`

The original plan assumed every `%Tempo{}` would materialise to a single `%Tempo.Interval{}`. In practice, several AST shapes expand to a sorted list of disjoint intervals, not one contiguous span. This revision introduces `%Tempo.IntervalSet{}` as the multi-interval representation and records the reasoning so we don't have to re-derive it later.

### Shapes that expand to multiple intervals

| AST shape | Example | Expansion |
|---|---|---|
| All-of set (range form) | `{2020,2021,2022}Y` | 3 year-intervals |
| All-of set (explicit members) | `%Tempo.Set{type: :all, …}` | N intervals |
| **One-of set** | `[2020Y,2021Y,2022Y]` = `%Tempo.Set{type: :one, …}` | **stays as epistemic disjunction — NOT an IntervalSet** |
| Non-contiguous mask | `1985-XX-15` | 12 day-intervals (the 15th of each month) |
| Stepped range | `{1..-1//7}D` in 2022 | ~52 day-intervals |
| Group iterated over a range | `{1..6}G1MU` | 6 intervals |
| Recurrence | `R3/1985-01/P1M` | 3 disjoint month-intervals |
| Repeat rule | `.../F...` | list driven by the rule |

The **one-of set is the important asymmetry**. `{a,b,c}` means "each of these values" (all-of, free/busy semantics) → expand to IntervalSet. `[a,b,c]` means "it was one of these, I don't know which" (epistemic disjunction) → stay as `Tempo.Set{type: :one}`. Flattening the epistemic form to an IntervalSet would lie about certainty.

### Why list-of-intervals is the right operational form

We considered two alternatives: (a) a **rule form** that keeps the AST unexpanded and evaluates lazily (RFC 5545 RRULE style — Tempo already emits this via `to_rrule/1`), and (b) the **materialised list** form.

| | Compact | Handles unbounded | Set ops |
|---|---|---|---|
| Rule form | yes | yes | very hard |
| Materialised list | no (O(n)) | no | easy (sweep-line) |

Rule-based set operations fall into three bands of difficulty:

1. **Tractable.** Rule ∩ bounded interval. Materialise within the window, run interval math. This is what every production calendar system does (Google Calendar, Outlook, Apple Calendar, `dateutil.rrule`, `rrule.js`). Membership testing is well-defined and O(1) for most RRULE shapes.

2. **Very hard.** General rule ∩ rule in closed form. RRULE isn't closed under intersection — "every Monday" ∩ "every 3rd day" isn't an RRULE. A richer AST ("AND of rules") and closure proofs would be needed. The iCalendar workaround (RRULE + EXRULE + EXDATE + RDATE per VEVENT) is a compound ad-hoc representation, not an algebra. No production system ships rule-on-rule set operations as a first-class feature.

3. **Very hard plus non-stationary, once timezones are in play.** `Tzdata` (the IANA database) updates several times a year — countries change DST rules, skip days (Samoa 2011), drop DST permanently (Turkey 2016). Rule expansions are re-derived every time they're evaluated and change silently when the zone database updates. IntervalSet endpoints, by contrast, are pinned wall-clock + zone at construction and remain stable; only the UTC projection is re-derived per op, and that re-derivation is automatic.

Additionally, two rules in different zones share no common reference frame until you materialise both. DST gaps and overlaps force policy decisions (RRULE is silent on whether "01:30 every day" fires once or twice on fall-back day). Every path through rule-on-rule set operations touches those policies.

The conclusion: **IntervalSet is the operational form**. Rule form stays as a compact AST for enumeration, membership tests, and round-trip to RRULE / ISO-8601. Any set operation that encounters a rule requires a bounding context — the rule is materialised within the bound, then IntervalSet math runs.

### Timezone handling

The same-as-industry pattern:

* **Wall-clock + zone is the source of truth.** `%Tempo{}.time` holds the wall-clock; `%Tempo{}.extended.zone_id` holds the IANA zone name; `%Tempo{}.shift` holds the current UTC offset (derived, but stored for fast access).

* **UTC projection is computed on demand, per set operation.** `to_utc_instant(tempo, Tzdata.current)` runs when set ops need a common reference frame across zones. The result is not cached on the struct.

* **No caching in v1.** Future profiling may justify a `%Tempo.IntervalSet{tzdata_version: _, utc_endpoints: _}` cache with invalidation, but v1 recomputes per operation. Correctness first, speed later. Users with hot workloads can cache externally.

* **Zoned interval construction resolves DST ambiguity at build time.** A `policy:` argument on the constructor picks `:earlier | :later | :error` for spring-forward gaps and `:first | :last | :error` for fall-back overlaps. Defaults match RFC 5545.

This mirrors iCalendar's design (wall-clock + `TZID` is authoritative; UTC is derivation) and matches what Google / Microsoft / Apple actually do — they cache UTC projections, invalidate on Tzdata update, and occasionally notify users when events shift. Not caching in v1 sidesteps the invalidation layer entirely.

### Forms that stay as rules

The following stay as their AST form — `to_interval/1` either refuses with a "bounding context required" error or passes through unchanged:

* Unbounded recurrence (`R/2022-01/P1M` without a count or end).
* Unbounded repeat rules.
* Future: selections with open-ended instance counts.

A future `Tempo.intersection/3`, `Tempo.union/3`, etc. accept a `bound:` option that materialises unbounded inputs within the given window before running set math.

### Forms that never produce IntervalSets

* **`%Tempo.Duration{}`** — no anchor, returns an error (unchanged from the single-interval plan).
* **`%Tempo.Set{type: :one}`** — epistemic disjunction, stays a Set. Renaming to `Tempo.Disjunction` is considered but deferred to avoid a naming churn before v1.

## Step-by-step

### Step 1 — canonicalisation helper (1 day)

Add a private helper `Tempo.canonicalise/1` that guarantees every `%Tempo{}` input has:

* All implicit-span components filled in (the `:year` is set, etc.). The existing `Group.expand_groups/2` and `Validation.validate/2` already do most of this; the helper is a thin composition.
* Group / selection / set constructs expanded to concrete values where possible. Already done by `Group.expand_groups/2`.
* No lingering fractional values or margin-of-error tuples — those become explicit endpoints via `resolve` in `Validation`.

This helper is the pre-flight check for Step 2. If canonicalisation fails (e.g. ambiguous date, unresolvable selection), `to_interval/1` fails with the same error shape.

### Step 2 — resolve the "next unit" upper bound (2 days)

Write `Tempo.Interval.next_unit_boundary/1`: given a `%Tempo{}` whose smallest stated resolution is `unit`, return the datetime that's one unit larger. Concretely:

| Input resolution | Upper-bound rule |
|---|---|
| year only | same year + 1 |
| year-month | same year, month + 1 (carry to next year if 12) |
| year-month-day | same year-month, day + 1 (carry via calendar) |
| year-month-day-hour | hour + 1 (carry to next day) |
| year-month-day-hour-minute | minute + 1 (carry) |
| year-month-day-hour-minute-second | second + 1 (carry) |
| year-week | year, week + 1 (carry) |
| year-week-day | year-week, day + 1 (carry) |
| year-ordinal-day | year, ordinal + 1 (carry) |

Carry is calendar-sensitive; delegate to `Calendrical.add/3` (or the calendar module's own `add/2` callback) on the already-loaded calendar. Week dates need special handling (last ISO week of the year can be W52 or W53).

Edge cases:

* Season (e.g. `2022-25`) — already materialised to an interval by `Group.expand_groups/2` before we see it here. No-op.
* Group / selection / set — materialised by Step 1.
* Unspecified digits (`156X`, `1985-XX-XX`) — the bounded interval is `1560-01-01/1570-01-01` and `1985-01-01/1986-01-01` respectively. Mask values map to a range, and `to_interval/1` picks the widest enclosing bound.
* Qualification / IXDTF extended info — unchanged; propagated to both endpoints (see Step 4).

### Step 3 — the `to_interval/1` function (1 day)

```elixir
@spec to_interval(Tempo.t() | Tempo.Interval.t()) ::
        {:ok, Tempo.Interval.t()} | {:error, reason}
def to_interval(%Tempo.Interval{} = interval), do: {:ok, interval}

def to_interval(%Tempo{} = tempo) do
  with {:ok, canonical} <- canonicalise(tempo),
       {:ok, upper} <- Tempo.Interval.next_unit_boundary(canonical) do
    {:ok, %Tempo.Interval{from: canonical, to: upper}}
  end
end
```

Plus a bang variant `to_interval!/1` that raises on error.

Also add clauses for:

* `%Tempo.Set{}` — map `to_interval/1` over each member, returning a list of intervals in source order.
* `%Tempo.Duration{}` — error (a duration has no anchor; it is a length, not a bounded span).

### Step 4 — propagate metadata to both endpoints (0.5 days)

When materialising `%Tempo{qualification: :uncertain, extended: %{zone_id: "Europe/Paris"}}` into an interval, both endpoints should carry the same `:qualification`, `:qualifications`, `:extended` and `:shift` values. This matches the intuition that the interval "inherits" the epistemic state of its source.

Exception: endpoint-level qualification read from the *parser* (e.g. `1984?/2004~` — where the parser already produces distinct qualifications on each endpoint) must not be overridden. Detect by checking whether the input is already an `%Tempo.Interval{}`; if so, return untouched (the first clause of `to_interval/1` above handles this).

### Step 5 — iteration parity (1 day)

Once a value is explicit, iteration must match the implicit iteration exactly. That is:

```elixir
Enum.to_list(~o"2026-01")            # implicit: iterates days
Enum.to_list(Tempo.to_interval!(~o"2026-01"))  # explicit: must yield identical list
```

Write a parity test comparing the two lists across:

* Year, year-month, year-month-day
* Year-week, year-week-day
* Ordinal dates
* Time resolutions (hour, minute, second)
* Masked dates (unspecified digits)
* Seasonal codes (21–32)

If the parity test fails, either the implicit enumeration (see the Enumerable review plan) or the explicit materialisation is wrong. Fix whichever is non-conformant.

### Step 6 — integration with future set operations (0 days; documentation)

No code change here. Document in `guides/iso8601-conformance.md` (and a future `guides/set-operations.md`) that:

1. `union/2`, `intersection/2` and `coalesce/1` are defined on `%Tempo.Interval{}` pairs/lists.
2. Consumers who hand in a `%Tempo{}` (implicit form) will have it converted via `to_interval/1` transparently.
3. The half-open convention is preserved across all operations.

### Step 7 — tests and docs (1 day)

* Test file `test/tempo/to_interval_test.exs` covering every construct table row in Step 2.
* Doctest on `Tempo.to_interval/1` with 2–3 archaeological examples (e.g. `~o"156X"` → `~o"1560Y1M1D/1570Y1M1D"`).
* Update `guides/iso8601-conformance.md` with a new "Implicit vs explicit intervals" subsection.
* CHANGELOG entry.

### Step 8 — `%Tempo.IntervalSet{}` struct (1 day)

Define the multi-interval type:

```elixir
defmodule Tempo.IntervalSet do
  @type t :: %__MODULE__{
          intervals: [Tempo.Interval.t()]
        }

  defstruct intervals: []

  def new(intervals) when is_list(intervals) do
    intervals
    |> Enum.sort_by(&from_key/1)
    |> coalesce()
    |> wrap()
  end
end
```

The constructor sorts by `from` endpoint and coalesces adjacent or overlapping intervals (sweep-line pass). The invariant on a `%Tempo.IntervalSet{}` is: *sorted ascending by `from`, with no overlaps and no adjacencies that could be merged.* Construction takes O(n log n).

### Step 9 — `Enumerable.Tempo.IntervalSet` (0.5 days)

Iterate each interval in time order, yielding each interval's forward-stepping sequence via `Enumerable.Tempo.Interval`. Essentially a `Stream.flat_map` over `intervals`, but implemented directly on the protocol for consistency with how the other Tempo enumerables work.

`count/1`, `member?/2`, `slice/1` return `{:error, __MODULE__}` for v1 — same deferral as `Enumerable.Tempo.Interval`.

### Step 10 — extend `Tempo.to_interval/1` to return `Interval | IntervalSet` (2 days)

Re-route the existing routing logic so multi-interval AST shapes materialise to `%Tempo.IntervalSet{}`:

| Input | Output |
|---|---|
| Single concrete `%Tempo{}` at a resolution | `%Tempo.Interval{}` |
| Masked `%Tempo{}` (contiguous widening) | `%Tempo.Interval{}` |
| Non-contiguous mask (`1985-XX-15`) | `%Tempo.IntervalSet{}` of 12 day-intervals |
| Range value inside `%Tempo{}.time` | `%Tempo.IntervalSet{}` |
| Stepped range | `%Tempo.IntervalSet{}` |
| Group iterated over a range | `%Tempo.IntervalSet{}` |
| `%Tempo.Set{type: :all}` | `%Tempo.IntervalSet{}` |
| `%Tempo.Set{type: :one}` | `%Tempo.Set{}` (unchanged — epistemic) |
| Bounded recurrence `%Tempo.Interval{recurrence: n, …}` | `%Tempo.IntervalSet{}` of n occurrences |
| Unbounded recurrence | `{:error, "provide a bounding context"}` |
| `%Tempo.Duration{}` | `{:error, "no anchor"}` |

Return shape changes from `{:ok, interval}` to `{:ok, interval_or_set}`. The existing Step 3 test suite extends accordingly.

Also add `Tempo.to_interval_set/1` — a convenience wrapper that always returns `%Tempo.IntervalSet{}` (wrapping a single interval in a 1-element set). Callers that want uniform handling use this; callers that want to distinguish single vs multi use `to_interval/1`.

### Step 11 — timezone projection helper (1 day)

Add a private `Tempo.Interval.to_utc_endpoints/1` that returns `{utc_from, utc_to}` for a zoned `%Tempo.Interval{}`. This is the primitive future set operations will use to align intervals across zones. Wall-clock + zone stays on the struct; the UTC projection is computed per call, not cached. See the "Timezone handling" design discussion for the rationale.

A failing `to_utc_endpoints/1` (ambiguous DST boundary on an already-constructed interval — shouldn't happen if the constructor resolved ambiguity, but we surface a clear error if it does) returns `{:error, reason}`.

### Step 12 — tests and docs for IntervalSet (1 day)

* `test/tempo/interval_set_test.exs` — constructor (sort + coalesce), enumerable protocol, round-trip to_interval_set / to_interval.
* Extend `test/tempo/to_interval_test.exs` with the multi-interval shapes from the Step 10 table.
* Update `guides/enumeration-semantics.md` with a new subsection on `IntervalSet`.
* CHANGELOG entry.

## Proposed API summary

```elixir
Tempo.to_interval(tempo)
# {:ok, %Tempo.Interval{} | %Tempo.IntervalSet{}} | {:error, reason}

Tempo.to_interval!(tempo)
# %Tempo.Interval{} | %Tempo.IntervalSet{} | raises

Tempo.to_interval_set(tempo)
# {:ok, %Tempo.IntervalSet{}} | {:error, reason}
# Convenience wrapper that always returns an IntervalSet.

# Convenience for the common case:
Tempo.from_iso8601("2026-01") |> elem(1) |> Tempo.to_interval!()
# => %Tempo.Interval{from: ~o"2026Y1M1D", to: ~o"2026Y2M1D"}

Tempo.from_iso8601("1985-XX-15") |> elem(1) |> Tempo.to_interval!()
# => %Tempo.IntervalSet{intervals: [%Tempo.Interval{...}, ...]}  # 12 intervals
```

Existing `%Tempo.Interval{}` values (parsed from `a/b` syntax) pass through unchanged — the function is idempotent on the explicit form. `%Tempo.IntervalSet{}` inputs also pass through unchanged.

## Estimated effort

**Steps 1–7 (single-interval path):** landed. Approximately 5–7 days as originally estimated.

**Steps 8–12 (multi-interval path):** approximately 5–6 working days. Step 10 (routing all AST shapes) and Step 8 (coalesce correctness) are where bugs are likely to surface.

## Dependencies

* **Depends on**: the `Enumerable` review plan, specifically Step 5 (open-ended intervals need a well-defined enumeration story before we can call them equivalent to their explicit form).
* **Blocks**: the set-operations milestone. Coalescing `[%Tempo{...}, %Tempo{...}]` into a canonical sorted list of non-overlapping intervals is much cleaner if every input has already been materialised via `to_interval/1`.

## Non-goals

* Storing the explicit form by default on `%Tempo{}`. The implicit form remains the primary representation; `to_interval/1` is an on-demand conversion.
* Converting durations into intervals. A duration needs an anchor; add an `anchor_duration/2` helper later if needed.
* Lossy conversion. Every piece of source metadata (qualification, extended info, calendar) is preserved on the explicit interval's endpoints.
