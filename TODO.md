* Don't allow group in time shifts

* Note doesn't support qualifications (section 8)

* Note doesn't support expanded year

* Find a way to express:
  * Astro events (Easter, New Moon, ....)
  * Workdays versus Weekends (different per locale)

* Resolve the tension in `Enumerable.Tempo.IntervalSet` semantics. An
  IntervalSet can sensibly be enumerated two ways, and we currently
  expose both behind separate names:

  1. **Sub-point walking** (current `Enumerable` default) — consistent
     with `Enumerable.Tempo` and `Enumerable.Tempo.Interval`: every
     Tempo value is a span; iterating walks the sub-points at the
     next-finer resolution. Good for calendar rendering and free/busy
     scans at minute/hour resolution.
  2. **Member-interval walking** via `Tempo.IntervalSet.to_list/1` —
     returns `[%Tempo.Interval{}]` that can be piped into `Enum` for
     scheduling, filtering, and counting use cases. Mirrors
     `Map.to_list/1` / `MapSet.to_list/1`.

  Works today but feels slightly asymmetric — users writing scheduling
  code have to remember to pipe through `to_list/1`. Options to revisit:

  * Leave as-is (preserves philosophical consistency — a Tempo value is
    always iterated as its span's sub-points; the "give me the members"
    view is a named helper).
  * Flip the default — `Enumerable` yields intervals, a named
    `to_points_stream/1` helper exposes the walk.
  * Protocol split — `Enumerable` stays as is; a separate
    `Tempo.Walkable` protocol explicitly expresses "walk the span."

  The right answer depends on which use case dominates in practice;
  defer until we have more real-world examples.

* **Cron parser — AST gaps identified during implementation of `Tempo.Cron`.**

  The cron parser (`Tempo.Cron.parse/1`) converts cron expressions into the
  `%Tempo.RRule.Rule{}` AST used by the rest of the recurrence pipeline. Four
  cron features do not map cleanly to the current AST. Each will require
  either an AST extension or a new operator to support faithfully.

  1. **`W` (nearest-weekday) day-of-month** — e.g. `15W` meaning "the nearest
     weekday to the 15th". RFC 5545 has no equivalent; `Tempo.RRule.Rule` has
     no field for it. The parser rejects `W` with
     `{:error, %Tempo.CronError{reason: :unsupported_w}}`. Adding this would
     need a new `:bymonthday_nearest_weekday` field on `Rule` and a matching
     clause in the expander.

  2. **Multi-year lists in 7-field cron** — e.g. `0 0 1 1 * 2025,2027,2029`.
     A single concrete year becomes `:until` (Dec 31 of that year). Multi-
     year lists have no direct AST field (`:byyear` does not exist) and the
     constraint is silently dropped; callers currently have to supply a
     `:bound` at materialisation time. Adding a `:byyear` field to `Rule`
     would be the cleanest fix.

  3. **POSIX day-of-month OR day-of-week semantics** — when a cron expression
     has both `dom` and `dow` non-`*`, POSIX specifies the union (either
     condition true). RRule BY rules AND-compose. Currently the parser
     tightens `dom` into a conjunction alongside `dow`, producing fewer
     matches than POSIX would. Exact OR would require a disjunction operator
     in the AST — e.g. `:or_clauses` holding a list of sub-rules whose match
     sets are unioned.

  4. **Step LHS semantics on day-of-week** — `MON-FRI/2` works, but `FRI/2`
     (a step starting from a named day) currently expands to `FRI..SUN` at
     step 2, which is the conservative interpretation. cron dialects
     disagree on whether `N/S` means "every S from N to end of range" or
     "every S starting from N with wrap-around". No AST change needed — a
     design call only.

* **tempo_sql round 2 — metadata-preserving storage variant.**

  The initial `ex_tempo_sql` release (v0.1.0) stores Tempo intervals as
  PostgreSQL `tstzrange` / `tstzmultirange` values. Round-trip is lossy by
  design: `Tempo.Interval.metadata`, `Tempo.IntervalSet.metadata`, Tempo
  `:extended` metadata (zone_id, IXDTF tags), and the implicit-vs-explicit-
  span distinction (`~o"2026Y"` vs `2026-01-01..2027-01-01`) are all
  dropped on write because PostgreSQL range types cannot carry them.

  Round 2 should add a text-based storage variant that preserves the full
  Tempo shape byte-for-byte — likely a composite type `(range tstzrange,
  iso8601 text)` where the range remains queryable via Postgres range
  operators and the text column carries the original ISO 8601 / IXDTF
  string for perfect round-trip. Alternative shapes to consider: a bare
  `text` column (no range queries but full fidelity); a `jsonb` column
  with both the range and the extended metadata; or a Postgres composite
  type.

  The `ideas_for_the_future.md` entry on Ecto integration already names
  this as a `:text` variant option. The implementation decision is mostly
  about whether to sacrifice range-query performance for fidelity.

