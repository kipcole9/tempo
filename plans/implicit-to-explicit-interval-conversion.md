# Plan: convert implicit intervals to explicit intervals

## Context

Tempo's architecture (see `CLAUDE.md`) distinguishes two forms of bounded interval:

* **Implicit span**: a single datetime value whose stated precision defines the span. `2026-01` *is* the interval `[2026-01-01, 2026-02-01)` — the span runs to the next unit at the given precision.

* **Explicit span**: a pair of datetimes written with a range operator, such as `%Tempo.Interval{from: ..., to: ...}` or the EDTF form `2026-01-01/2026-02-01`.

Map and reduce on the implicit form is already implemented and iterates at the **next-higher precision below what is stated** — iterating `2026-01` yields days; iterating `2026` yields months. Map and reduce on the explicit form iterates at the **precision of its boundaries**.

The two forms are semantically equivalent for single values but diverge in iteration and set operations. The set-operations milestone (union / intersection / coalesce on lists of intervals) is dramatically simpler if every input is first materialised into the explicit form. This plan defines the conversion.

## Objective

Add a single public function, `Tempo.to_interval/1`, that takes any `%Tempo{}` value and returns the equivalent `%Tempo.Interval{}` with concrete `from` and `to` endpoints (half-open: `from` inclusive, `to` exclusive). After this lands, every construct in the Tempo vocabulary has a single canonical "bounded-pair" representation — the foundation for coalescing and set operations.

## Half-open convention

`%Tempo.Interval{from: start, to: end}` already represents `[start, end)` in this codebase. Every conversion below honours that:

* `2026-01` → `%Tempo.Interval{from: ~o"2026Y1M1D", to: ~o"2026Y2M1D"}` — **not** `2026-01-31`.
* `2026` → `from: 2026-01-01, to: 2027-01-01`.
* `2026-01-15T10` → `from: 2026-01-15T10:00, to: 2026-01-15T11:00`.

The upper bound is always the next-unit boundary, never "the last moment". This lets adjacent intervals concatenate cleanly (`[a, b) ++ [b, c) == [a, c)`).

## Step-by-step

### Step 1 — canonicalisation helper (1 day)

Add a private helper `Tempo.canonicalise/1` that guarantees every `%Tempo{}` input has:

* All implicit-span components filled in (the `:year` is set, etc.). The existing `Group.expand_groups/2` and `Validation.validate/2` already do most of this; the helper is a thin composition.
* Group / selection / set constructs expanded to concrete values where possible. Already done by `Group.expand_groups/2`.
* No lingering fractional values or margin-of-error tuples — those become explicit endpoints via `resolve` in `Validation`.

This helper is the pre-flight check for Step 2. If canonicalisation fails (e.g. ambiguous date, unresolvable selection), `to_interval/1` fails with the same error shape.

### Step 2 — resolve the "next unit" upper bound (2 days)

Write `Tempo.Interval.next_unit_boundary/1`: given a `%Tempo{}` whose smallest stated precision is `unit`, return the datetime that's one unit larger. Concretely:

| Input precision | Upper-bound rule |
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

## Proposed API summary

```elixir
Tempo.to_interval(tempo)         # {:ok, %Tempo.Interval{}} | {:error, reason}
Tempo.to_interval!(tempo)        # %Tempo.Interval{} | raises

# Convenience for the common case:
Tempo.from_iso8601("2026-01") |> elem(1) |> Tempo.to_interval!()
# => %Tempo.Interval{from: ~o"2026Y1M1D", to: ~o"2026Y2M1D"}
```

Existing `%Tempo.Interval{}` values (parsed from `a/b` syntax) pass through unchanged — the function is idempotent on the explicit form.

## Estimated effort

Approximately **5–7 working days**. Step 2 (next-unit boundary across all calendar constructs) is the most work; Step 5 (iteration parity) is where bugs are likely to surface.

## Dependencies

* **Depends on**: the `Enumerable` review plan, specifically Step 5 (open-ended intervals need a well-defined enumeration story before we can call them equivalent to their explicit form).
* **Blocks**: the set-operations milestone. Coalescing `[%Tempo{...}, %Tempo{...}]` into a canonical sorted list of non-overlapping intervals is much cleaner if every input has already been materialised via `to_interval/1`.

## Non-goals

* Storing the explicit form by default on `%Tempo{}`. The implicit form remains the primary representation; `to_interval/1` is an on-demand conversion.
* Converting durations into intervals. A duration needs an anchor; add an `anchor_duration/2` helper later if needed.
* Lossy conversion. Every piece of source metadata (qualification, extended info, calendar) is preserved on the explicit interval's endpoints.
