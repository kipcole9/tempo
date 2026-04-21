# Tempo — Project Guidance

## Project objective

Tempo treats **date and time as intervals, not as instants**. Every value represents a bounded span on the time line, which means:

* We can **reduce and map** across intervals as first-class structures.

* We can **compare** intervals using [Allen's Interval Algebra](https://ics.uci.edu/~alspaugh/cls/shr/allen.html).

* We **never run the risk of invalid dates** because every value is a bounded interval — partial specifications like `2022Y` or `2022Y-11M` are intervals spanning the whole year or month, not uncertain instants.

### Next major milestone

Define **set operations on intervals**:

1. `union/2` and `intersection/2` on a pair of intervals (first).

2. Extend those operations to **lists of intervals**, including coalescing overlapping intervals into a canonical, non-overlapping form.

All subsequent work (difference, symmetric difference, containment queries, etc.) builds on these primitives.

## Architecture — implicit vs explicit spans

Every Tempo value is a span on the time line. Spans come in two forms and the distinction matters for iteration, comparison, and set operations.

### Implicit span

A single ISO 8601 datetime **is** an interval. Its span runs from the stated datetime to the same datetime incremented by one unit **at the next-higher-resolution-that-is-not-defined**. For example:

* `2026` → `2026-01-01 .. 2027-01-01` (year resolution, span of one year)

* `2026-01` → `2026-01-01 .. 2026-02-01` (month resolution, span of one month)

* `2026-01-15` → `2026-01-15 .. 2026-01-16` (day resolution, span of one day)

* `2026-01-15T10` → `2026-01-15T10:00 .. 2026-01-15T11:00` (hour resolution, span of one hour)

Map and reduce on implicit spans is already implemented. The iteration unit is the **next-higher-resolution below what is stated** — e.g., iterating over `2026-01` yields days, iterating over `2026` yields months (or weeks, depending on calendar).

### Explicit span

An explicit span is a pair of datetimes written with a range operator, such as `2026-01-01..2026-02-01`. It is always iterated at **its own highest resolution** — the resolution of the boundaries. Iterating `2026-01-01..2026-02-01` yields days, not months.

### Half-open convention

**Every span is inclusive of the first boundary and exclusive of the last boundary** — `[first, last)`. This is deliberate, not incidental. It:

* Makes map/reduce work uniformly regardless of the iteration resolution.

* Makes adjacent spans concatenate cleanly: `[a, b)` followed by `[b, c)` is exactly `[a, c)` with no overlap or gap.

* Matches the implicit-span semantics above (`2026-01` ends just before `2026-02-01`, not on it).

Any new span, interval, comparison, or set-operation code **must honour this convention**. Code that treats the upper bound as inclusive is a bug.

### Planned: explicit-span conversion

A near-term todo is to materialise an implicit span into its explicit form — i.e., convert `2026-01` into `2026-01-01..2026-02-01`. This normalisation is the bridge that will let set operations (union/intersection, coalescing) work uniformly whether the caller supplied implicit or explicit spans.

## Documentation and example style

**Every example in Tempo docs, guides, cookbook recipes, livebooks, and module docs should read aloud as English prose a product manager would say.** This is the test of whether the abstractions are doing their job — if a snippet can't be translated to a sentence a non-programmer would understand, there's a missing predicate or operation, and it should be added before the example is written.

### The pipeline-prose shape

Examples follow a consistent three-part structure:

1. **Setup in a few named bindings** (the nouns):

   ```elixir
   work        = ~o"2026-06-15T09/2026-06-15T17"
   alice_busy  = ...
   bob_busy    = ...
   ```

2. **Pipeline in set-algebra + predicate verbs** (the sentence):

   ```elixir
   {:ok, alice_free} = Tempo.difference(work, alice_busy)
   {:ok, bob_free}   = Tempo.difference(work, bob_busy)
   {:ok, mutual}     = Tempo.intersection(alice_free, bob_free)

   slots =
     mutual
     |> Tempo.IntervalSet.to_list()
     |> Enum.filter(&Tempo.at_least?(&1, ~o"PT1H"))
   ```

3. **Prose translation in a callout** (the human reading):

   > *"Alice's free time is the workday **minus** her busy periods. Bob's is the same. **Mutual** free time is the **intersection** of theirs. **Bookable slots** are the mutual windows **at least an hour** long."*

The three parts reinforce each other — nouns, verbs, prose.

### What this excludes from examples

If any of these appear in user-facing examples, it's a signal that an abstraction is missing:

* **`to_utc_seconds/1`** or other raw second counting — add a duration predicate instead (`at_least?`, `exactly?`, `shorter_than?`, …).
* **Struct field accessors** like `set.intervals`, `iv.from.time[:hour]` — add a named helper (`IntervalSet.to_list/1`, a predicate, or a query function).
* **Magic numbers** for durations (`3600`, `86_400`) — use an ISO 8601 duration literal (`~o"PT1H"`, `~o"P1D"`).
* **Hand-rolled geometric checks** like `compare_endpoints(a + d, b) in [:earlier, :same]` — add a predicate that names the concept.
* **Pattern-matching on Allen relation lists inline** like `Tempo.compare(a, b) in [:equals, :starts, :during, :finishes]` — name that set (`Tempo.within?/2` does exactly this).

When writing a new example and one of these patterns appears, stop and add the missing abstraction first. The codebase already models this — `within?/2`, `at_least?/2`, `adjacent?/2` all exist because geometric checks and inline-relation-lists were recurring in examples.

### Applies to

* Module docs and `@doc` examples.
* Guides in `guides/`.
* The cookbook.
* Livebooks.
* README code blocks.
* Release notes and CHANGELOG entries (where examples appear).

### Does NOT apply to

* Internal implementation code and helpers.
* Tests asserting specific AST shapes or low-level behaviour.
* Error messages (which need to reference specific field names and types).

These are about correctness and mechanics; they legitimately work at the plumbing level.

## Naming conventions

### Territory, not region

**Tempo standardises on "territory" everywhere — never "region".** A territory is a CLDR/BCP 47 territory code (`:US`, `:AU`, `:SA`, `:GB`, …) — the two- or three-letter country/region code that locale data is keyed by. The word "region" means something different in everyday speech (a vague geographic area), and the Localize library already names its API `Localize.Territory.territory_from_locale/1`, so Tempo follows suit.

This applies to every user-facing surface:

* **Option keys**: `territory: :SA`, never `region: :SA`.

* **Application config keys**: `:default_territory`, never `:default_region`.

* **Type names and variable names**: `territory`, `normalize_territory`, `resolve_territory`, `ixdtf_territory`.

* **Prose in docs, cookbook, livebook, changelog**: "territory resolution chain", "territory override", "the territory `:SA`".

The single exception is when referring to an **external standard's own terminology**. BCP 47 calls its `u-rg-XX` subtag a "region override" — that's the standard's name, we quote it verbatim with the "region" word in scare quotes or parentheses. IXDTF inherits that name via the `u-rg` key. Those specific references are fine; everywhere else it is "territory".

When reviewing new code or docs, grep for `region` / `:region` / `default_region` and rename them unless they're quoting BCP 47 directly.

## Reference documents

The following documents are **critical** when working on this project. Consult them whenever behaviour, syntax, or semantics need to be verified — do not guess.

* **ISO 8601 standards** — the canonical PDFs live in `~/Documents/Development/iso_standards/`. These are the source of truth for ISO 8601 Part 1 (date/time representations) and Part 2 (extensions), which Tempo implements.

* **IETF draft-ietf-sedate-datetime-extended-09 (IXDTF)** — <https://www.ietf.org/archive/id/draft-ietf-sedate-datetime-extended-09.html#name-format-of-extended-informat>. Defines the extended information suffix syntax (`[zone]`, `[u-ca=calendar]`, `[key=value]`, critical `!` flag) parsed by `Tempo.Iso8601.Tokenizer.Extended`.

* **Allen's Interval Algebra** — <https://ics.uci.edu/~alspaugh/cls/shr/allen.html>. The 13 base relations (`precedes`, `meets`, `overlaps`, `finished_by`, `contains`, `starts`, `equals`, and their inverses, plus `preceded_by`) used by `Tempo.Comparison` when comparing intervals.
