# Plan: review the `Enumerable` implementation for implicit intervals

## Context

As of v0.2.0 the parser accepts the full ISO 8601-2 / EDTF Level 2 vocabulary (183-string corpus passing). The parser now emits `%Tempo{}` values whose shape is substantially richer than the `Enumerable` implementation was written for:

| New parser construct | New struct field or token shape | Enumerable status |
|---|---|---|
| IXDTF zone / offset / calendar | `:extended` map (`%{zone_id:, zone_offset:, calendar:, tags:}`) | untouched — not read or written by `Enumeration` |
| Expression-level qualification | `:qualification :: :uncertain \| :approximate \| :uncertain_and_approximate \| nil` | untouched |
| Component-level qualification | `:qualifications :: %{unit => qualifier} \| nil` | untouched |
| Astronomical seasons (25–32) | expanded to `%Tempo.Interval{}` before enumeration | transparent — already works |
| Unspecified digits + negative years | `{:mask, [:negative \| rest]}` on year | needs verification (see below) |
| Long years with exponent | `integer` (up to `1_700_000_000`) | should work (integer enum) but range sizing may overflow |
| Long years with significant digits | `{integer, significant_digits: n}` tuple value | never handled — `do_next` doesn't match this shape |
| Open-ended intervals | `%Tempo.Interval{from: :undefined, to: :undefined}` | needs verification — `Enumerable.Tempo.Range` is an empty file |

## Objective

Audit `lib/enumeration.ex`, `lib/protocol/enumeration/tempo.ex`, `lib/protocol/enumeration/set.ex`, and `lib/mask.ex` against every construct the parser can now produce. Produce a gap list, fill the gaps, and verify with tests that cover each new construct.

## Step-by-step

### Step 1 — write a single enumeration conformance harness (1 day)

Create `test/tempo/enumeration_conformance_test.exs` that iterates over a representative sample of every parser construct and asserts that `Enum.take(tempo, N)` returns something plausible (or explicitly raises a documented error). For the initial run, most assertions should be "`Enum.take/2` does not crash" — the harness is a *gap detector*, not a correctness oracle.

Construct categories to exercise, each with 2–3 strings:

* Bare year / month / day (baseline)
* Unspecified digits (`156X`, `1985-XX-XX`, `-1XXX-XX`)
* Long year (`Y12345`, `Y17E8`, `Y171010000S3`)
* Qualification — expression-level (`2022?`, `~2022-06-15`)
* Qualification — component-level (`2022-?06-15`, `2022?-06-?15`)
* IXDTF suffix (`2022-06-15[Europe/Paris]`, `2022-06-15[u-ca=hebrew]`)
* Open-ended interval (`1985/..`, `../1985`, `../..`)
* Per-endpoint qualification interval (`1984?/2004~`)
* Astronomical and meteorological season (`2022-25`, `2022-21`)
* Groups and selections (existing, already tested — include for regression)

Run the harness and collect the failures into `docs/enumeration-gaps.md`. This artefact drives Steps 2–5.

### Step 2 — straightforward propagation (1 day)

The lowest-risk fixes: make sure every enumerated value carries through the new metadata from its source `%Tempo{}`. Specifically in `Enumeration.collect/1`:

```elixir
def collect(%Tempo{time: units, extended: extended, qualification: q, qualifications: qs} = tempo) do
  case collect(units) do
    nil -> nil
    other -> %{tempo | time: other, extended: extended, qualification: q, qualifications: qs}
  end
end
```

The struct-update form already propagates — the `%{tempo | time: other}` keeps every other field — but verify with tests that every yielded value retains its `:extended`, `:qualification`, and `:qualifications` fields. This is expected to pass without changes; the step is a confidence check, not a refactor.

### Step 3 — component-level qualification semantics (2 days)

Decision needed: when enumerating `2022-?06-15`, does each yielded day carry `qualifications: %{month: :uncertain}`? Two defensible positions:

1. **Propagate verbatim**: every enumerated value shares the same `qualifications` map as the source. Simple and honest about what the user wrote.
2. **Strip on resolution**: once a component is concretely enumerated, drop its qualifier (the uncertainty has been "collapsed" by picking a specific value).

Recommend **Option 1** (propagate verbatim). Rationale: the qualification is a statement about the *source expression*, not about the resolved value. An archaeologist enumerating `2022-?06-15` one day at a time still knows "the June part was a guess". Stripping the marker discards that epistemic state.

Implementation: Option 1 is the default struct-update behaviour. Add a test that verifies the map survives enumeration.

### Step 4 — long-year integer / significant-digit shapes (2–3 days)

The `do_next` function assumes year values are integers or keyword lists or masks. Two new shapes now exist:

* `{integer, significant_digits: n}` — emitted by `form_number` for `1950S2`, `Y171010000S3`, etc.
* Integer values in the millions or billions (`Y170000002`, `Y17E8` = 1.7 billion).

Gaps:

* `do_next([{:year, {value, opts}} | _], ...)` has no clause. Will match the final `do_next([h | t], ...)` clause (if one exists — verify) or crash.
* `Tempo.Mask.fill_unspecified/4` calls `[target_range] = fill_unspecified(unit, :any, ...)` which uses `Date.utc_today().year`. That's fine for short years but for `Y170000002` the target range is unbounded — we can't enumerate over 1.7 billion years.

Proposed handling:

* For `{integer, significant_digits: n}`, enumerate at the nth-digit granularity. E.g. `1950S2` = "1950 with the first 2 digits significant" = enumerate as `1900..1999` year-range. Implement by teaching `do_next` to expand the sig-digits tuple into a range before recursing.
* For wide-range exponent years (>9999), refuse to enumerate and return `{:error, :unenumerable_year_range}` or similar — or only enumerate *within* the stated year, not *across* years. Document the limit in the moduledoc.

### Step 5 — open-ended and unbounded intervals (3–5 days)

The existing `Enumerable.Tempo.Range` file is empty (0 lines). The parser now produces `%Tempo.Interval{from: :undefined, to: :undefined}` and half-open variants.

Design questions:

* **`Enum.take(interval_with_open_upper, n)`** — iterate from `:from` forward, stopping after `n`. Infinite iterator. Needs cycle+continuation wiring analogous to `Enumeration.do_next/3`.
* **`Enum.take(interval_with_open_lower, n)`** — iterate from ??? There is no anchor. Either raise `ArgumentError` or iterate *backwards* from some cursor. Recommend raising with a clear message; backward iteration is surprising.
* **`Enum.take(fully_open, n)`** — raise. Nothing to anchor to.
* **`Enum.count/1`** — always `{:error, __MODULE__}` for open intervals.
* **`Enum.member?/2`** — can be answered in O(1) for open intervals by comparing to the open endpoint. Worth implementing.

Implement `Enumerable.Tempo.Interval` with these four callbacks. The `reduce` path delegates to `Enumeration.do_next/3` on the `:from` endpoint for the open-upper case, and short-circuits the other two with a clear error.

### Step 6 — IXDTF extended info & zone-aware enumeration (1 day)

Most iterations (years, months, days) are zone-insensitive. A handful are not:

* Iterating across a DST boundary in a zoned interval — what does "next day" mean? For now, treat enumeration as operating on wall-clock time and pass the `zone_id` through unchanged on each yielded value. Document that DST transitions are NOT compensated.
* Iterating hours in a zoned interval — same principle; document and test.

Add a test that confirms `zone_id` and `calendar` flow through enumeration unchanged.

### Step 7 — qualification × enumeration × coalescing (1 day, documentation only)

No code change yet. Document in the conformance guide what happens when an uncertain date is coalesced into a set. The next milestone (set operations) will need this settled. Short answer proposed: two values are equal for coalescing purposes if and only if their bounded intervals match; qualification does not break equality.

### Step 8 — regression and corpus coverage (1 day)

Add every string from the conformance harness to the main test file so regressions are caught. Re-run the full corpus to confirm parsing hasn't regressed.

## Deliverables

* `test/tempo/enumeration_conformance_test.exs` — the harness from Step 1, re-used as the regression suite.
* `docs/enumeration-gaps.md` — short living document listing any gaps we consciously defer.
* Code changes in `lib/enumeration.ex`, `lib/protocol/enumeration/tempo.ex`, `lib/protocol/enumeration/range.ex` (currently empty), and `lib/mask.ex` per Steps 3–6.
* An `Enumerable.Tempo.Interval` implementation.
* CHANGELOG entry.
* Updates to `guides/iso8601-conformance.md` describing enumeration semantics.

## Estimated effort

Approximately **8–12 working days** of focused work, dominated by Step 5 (open-ended intervals). Steps 1, 2, 6, 7, 8 are each a day or less.

## Non-goals

* Performance optimisation — the current implementation is correctness-first and there is no evidence of a performance problem.
* Lazy enumeration of truly infinite intervals in a streaming-compatible way — addressed with a clear error for now.
* Cross-endpoint semantic validation (e.g. "this interval reverses time") — tracked separately as part of the set-operations milestone.

## Dependencies on other work

* **Blocking**: none. The parser is stable at v0.2.0.
* **Blocks**: the set-operations milestone assumes a working `Enumerable.Tempo.Interval` for coalescing and iteration; Step 5 must land before that milestone starts.
