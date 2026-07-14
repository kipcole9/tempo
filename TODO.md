* Qualifications (ISO 8601-2 §8) — **implicit-form parsing is now
  fully §8-conformant.** Complete (§8.2.1, rightmost → whole value),
  group (§8.2.2, right-of-component → that component + all coarser),
  and individual (§8.2.3, left-of-component → that one only) are all
  honoured, with overlapping qualifiers combining (`?` + `~` → `%`).
  The explicit (designator) form and output rendering are also done:

  1. ~~**Explicit-form per-component qualifiers**~~ **Done.**
     `2004~Y6?M11D` (§8.3, qualifier between value and designator)
     parses; an explicit qualifier is always individual (§8.2.3).

  2. ~~**Rendering the `:qualifications` map on output**~~ **Done.**
     `inspect/1` and `to_iso8601/1` emit per-component qualifiers in
     explicit form, so component qualification round-trips — a parsed
     group (`2004-06~-11`) re-encodes as the equivalent explicit
     individual qualifiers (`2004~Y6~M11D`).

  The explicit-form BC year path (`2004~YB`) and §8.2.4 canonical
  output are also done: a qualified explicit BC year parses, and an
  output whose every present component shares one qualifier collapses
  to the compact complete form (`2004%Y6%M11%D` → `2004Y6M11D%`). Group
  collapse is intentionally not attempted — the explicit (designator)
  output form has no group representation, so complete is the only
  available reduction.

* Find a way to express:
  * Astro events (Easter, New Moon, ....)
  * ~~Workdays versus Weekends (different per locale)~~ **Done.**
    `Tempo.weekend?/2` and `Tempo.workday?/2` classify a day against a
    territory's CLDR weekend (via `Localize.Calendar.weekend/1`), using
    `Date.day_of_week/1` for the ISO day number. Complements the
    existing `Tempo.weekend/1` and `Tempo.workdays/1` recurrence
    selectors. Business-day arithmetic is also done:
    `Tempo.add_working_days/3` (forward/backward, skipping the
    territory's weekend, calendar-correct), `next_working_day/2`,
    `previous_working_day/2`, and `working_days_in/2`.

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

  1. ~~**`W` (nearest-weekday) day-of-month** — e.g. `15W` meaning "the nearest
     weekday to the 15th".~~ **Done.** `Rule` has a non-standard
     `:bymonthday_nearest` field (integer days or `:last` for `LW`). The
     parser maps `15W`/`LW` onto it (rejecting `W` in lists or ranges, per
     Quartz), and the selection resolver snaps each target to the nearest
     weekday within the same month — Saturday → Friday, Sunday → Monday,
     never crossing a month boundary (`1W` on a Saturday lands on the 3rd).

  2. ~~**Multi-year lists in 7-field cron** — e.g. `0 0 1 1 * 2025,2027,2029`.~~
     **Done.** `Rule` now has a non-standard `:byyear` field. `Tempo.Cron`
     maps a multi-year list (or a range that expands to one) onto it and
     bounds the cadence with `:until` one past the last listed year; the
     expander materialises that span and keeps only occurrences whose year
     is listed, skipping the gaps.

  3. ~~**POSIX day-of-month OR day-of-week semantics**~~ **Done.** Rather
     than a general disjunction operator, the common case is handled with a
     `:bymonthday_or_byday` union filter on `Rule`: when both `dom` and `dow`
     are plain lists, the parser emits a DAILY cadence whose selection keeps a
     day if its day-of-month OR its weekday matches (`13 * 5` → every 13th and
     every Friday). Month/time fields still AND-compose. A Quartz extension
     (ordinal `5#2`/`5L`, or nearest-weekday `15W`) opts out and keeps the
     AND interpretation. Known limit: a wildcard sub-day time field in the OR
     case is under-served (the daily cadence assumes a fixed time); the common
     fixed-time shape is exact.

  4. ~~**Step LHS semantics on day-of-week** — `MON-FRI/2` works, but `FRI/2`
     ...~~ **Done.** The design call: a day-of-week step expands in *cron*
     numbering (Sunday = 0, week start) to the end of the week — no
     wrap-around — then maps to RFC. `5/2` stays Fri, Sun; `0/3` is now
     Wed, Sat, Sun (previously collapsed to Sunday because Sunday-as-0 was
     converted to RFC-7 before the range was built); `*/2` is Tue, Thu,
     Sat, Sun. This also fixed a Sunday-spanning range LHS (`0-3`) that
     had built a descending range.

* ~~**IXDTF strict mode — flag offset/zone disagreement.**~~ **Done.**
  `Tempo.validate_zone_offset/1` returns `:ok | {:error,
  %Tempo.ZoneOffsetMismatchError{}}`, and `Tempo.from_iso8601/2`
  accepts `strict: true` (composing with `calendar:`) to reject a
  disagreeing value at parse time. A DST fall-back offset is treated as
  disambiguation, not disagreement. The `!` critical flag refinement
  also landed (2026-07-11): a critical zone (`[!America/New_York]`)
  enforces RFC 9557 §4.2 offset consistency unconditionally, with the
  flag retained on `extended.zone_critical` and round-tripping through
  `to_iso8601/1`; `strict: true` remains the superset that also rejects
  elective disagreement. Analysis below.

  When an IXDTF string carries both a numeric offset and a zone identifier
  (e.g. `2022-11-20T10:37:00+05:00[Europe/Paris]`), the two can disagree —
  Paris is UTC+01 in November, not +05. Tempo currently accepts both at
  parse time and stores them separately on the struct (`shift` for the
  offset, `extended.zone_id` for the zone). At conversion time
  (`Tempo.Compare.resolve_offset_seconds/3`), the IANA zone wins and the
  offset is consulted only for DST fall-back disambiguation — so a
  typo'd offset is silently discarded rather than flagged. See
  [lib/compare.ex:238](lib/compare.ex:238) for the current resolution
  precedence.

  RFC 9557 §4.2 identifies this as one of the conditions consumers MAY
  treat as an error (the standard intentionally leaves the strictness
  choice to the consumer). We should offer an opt-in strict mode:

  - Either a parse-time option (e.g. `from_iso8601(str, strict: true)`)
    that errors when the offset and the zone disagree at the given wall
    instant.

  - Or a post-parse validator (e.g. `Tempo.validate_zone_consistency/1`)
    that returns `:ok | {:error, reason}` so callers can choose to enforce
    at schema-validation time without coupling it to parsing.

  The check itself is cheap — compute the zone's offset at the wall instant
  via Tzdata and compare to the stated offset. Details to work out: what
  counts as "critical" (should `[!Europe/Paris]` tighten the check?), and
  how to surface the mismatch (new exception type vs. `ParseError`).

  Related: the critical flag on IXDTF suffixes currently only governs
  unknown-zone handling, not consistency. Strict mode could honour the
  `!` flag to mean "this zone is authoritative — any disagreeing offset
  is an error".

* Define a `Tempo.Intervallic` protocol so user-defined types can
  participate in Allen-algebra comparisons and set operations without
  being copied into `%Tempo.Interval{}`.

  Currently `Tempo.Interval` is the only first-class interval type;
  a user with `%Booking{check_in, check_out}` (or similar) has to
  build `Tempo.Interval.new!(from: ..., to: ...)` and lose their
  struct's identity, or attach metadata via the `:metadata` map.

  Haskell's `interval-algebra` solves this with an `Intervallic`
  typeclass; Rust's `allen-intervals` exposes an `IntervalBounds`
  trait. The Elixir-idiomatic equivalent is a protocol:

  ```elixir
  defprotocol Tempo.Intervallic do
    @spec from(t) :: Tempo.t() | :undefined
    def from(value)

    @spec to(t) :: Tempo.t() | :undefined
    def to(value)
  end
  ```

  Then `Tempo.relation/2`, `overlaps?/2`, set operations etc. would
  accept any value implementing the protocol, dispatching through
  `Tempo.Intervallic.from/1` and `to/1`. The library would ship
  default implementations for `Tempo.Interval`, `Tempo`, and
  `Tempo.IntervalSet` (single-member case).

  Reward: third-party data types participate in set operations
  without copying. Reduces friction for adoption in larger apps.

  Reference: [Tempo vs. other interval-algebra libraries](papers/library-comparisons.md#what-tempo-could-learn).

* Investigate an interval-tree backing store for `IntervalSet` to
  accelerate stabbing and overlap queries on large sets.

  Current `IntervalSet` is a sorted, coalesced list — O(n log n)
  construction, O(n) for some traversal operations. Users with
  multi-year iCalendar feeds (tens of thousands of events) would
  benefit from an interval-tree internal representation.

  Rust's `interavl` crate demonstrates that AVL-backed interval
  trees give millions-to-billions of stabbing queries per second
  with subtree-pruning optimisations. The change is purely internal:
  the `Tempo.IntervalSet` API stays identical; the change is the
  shape of `:intervals` (or an additional cached tree).

  Effort: significant. Worth doing only when a real user reports
  the need — premature without a benchmark target.

  Reference: [Tempo vs. other interval-algebra libraries](papers/library-comparisons.md#what-tempo-could-learn).

* ~~**iCal import of zero-duration events vs. the no-degenerate-intervals
  domain.**~~ **Resolved** — punctual events materialise at DTSTART's
  one-unit implicit span (the "materialise" option below), tagged
  `metadata: %{punctual: true}`. The widening happens at a single
  construction chokepoint (`ensure_non_degenerate/3` in `lib/ical.ex`),
  so it also catches an explicit `DTEND == DTSTART`; no zero-extent
  interval can reach a `%Tempo.Interval{}` or a set operation. The
  analysis below is kept for context.

  The iCal importer now follows RFC 5545 §3.6.1 for events with no
  `DTEND`/`DURATION`: a `DATE-TIME` `DTSTART` becomes a zero-duration
  point (`to == from`), and a `DATE` `DTSTART` spans exactly one day.
  See the `dtend_to_tempo/2` clauses at
  [lib/ical.ex:465](lib/ical.ex:465). The zero-duration case constructs
  a `%Tempo.Interval{}` struct directly, bypassing
  `Tempo.Interval.new/1`'s rejection of empty intervals — so the point
  event currently survives import and (empirically) a `union`.

  This is in direct tension with a *deliberate* ontological commitment,
  not an accident. Reviewing the TIME 2027 paper confirms the intent:
  Tempo follows Grüninger & Li's $T_{bounded\_meeting}$, which **excludes
  degenerate (zero-extent) intervals from the domain** — "intervals are
  the only entities", points are deliberately avoided, and
  "an interval is never returned with zero extent". See
  [papers/time-2027/extended-abstract-body.tex](papers/time-2027/extended-abstract-body.tex)
  §"Set operations on intervals and interval sets" (the
  `T_bounded_meeting` exclusion at lines 242–247) and the
  point-avoidance rationale at lines 276–280. The v0.7.0 changelog entry
  ("`Tempo.Interval.new/1` now rejects empty intervals … the ontology's
  exclusion of degenerate intervals from the domain") is the code-side
  realisation of the same decision.

  So the conflict is real: RFC 5545 wants a *point*; Tempo's domain
  *has no points*. The current fix makes import RFC-faithful at the cost
  of injecting a value the ontology says cannot exist, which set
  operations may legitimately drop or mishandle once empty-interval
  filtering is tightened (the paper says set ops never *return* zero
  extent; they don't yet promise to *tolerate* a zero-extent input).

  Options to decide between:

  * **Skip on import** — treat a DTEND-less timed event as
    non-representable in the interval domain and drop it, the way
    `DTSTART`-less events are already skipped. Honest to the ontology;
    loses the event.

  * **Keep zero-extent (current)** — RFC-faithful, but the value is
    outside the domain and is a latent landmine for set operations.

  * **Materialise at DTSTART's implicit span** — the event becomes the
    one-unit span the DTSTART value denotes. Keeps the event inside the
    domain and reframes RFC 5545 §3.6.1's "zero duration" (an
    instant-model artifact) as the smallest span containing the moment.
    Now that `Tempo.from_elixir/2` infers resolution from the type's
    declared precision rather than component magnitude, this yields a
    clean **one-second** span for `09:00:00` (not the old one-*hour*
    span), so the option that previously looked bad is now the
    natural one. Optionally tag `metadata: %{punctual: true}` to record
    that the source was instantaneous.

  * **Model points outside the interval type** — carry instantaneous
    events as a distinct annotation/marker rather than forcing them into
    `%Tempo.Interval{}`. Largest change; reintroduces a point category
    the ontology deliberately excludes, and explodes Allen's algebra
    into a point-interval algebra. If ever needed, the right seam is the
    proposed `Tempo.Intervallic` protocol (above), not a core type.

  Resolve which of these is correct before relying on imported
  point-events in set-algebra pipelines. Leaning toward "materialise at
  DTSTART's implicit span + metadata tag" now that the `from_elixir`
  precision blocker is fixed.

* ~~**Non-anchored time-of-day groups — error vs. materialise as a
  relative span.**~~ **Done.** A *pure* time-of-day group (no date
  components) now materialises to a **non-anchored** interval — e.g.
  `[hour: 16, minute: {:group, 1..15}]` → `[16:01, 16:16)` — provided
  the upper bound's carry stays within the present time units. A carry
  off the end of the day (`23:45..`, no day to carry into), a date
  group (`5G10DU`), and a partially-dated value still error. The result
  lives on the time-of-day axis until anchored. Analysis below.

  `Tempo.to_interval/1` materialises a group (`{:group, first..last}`)
  to its enclosing span only when the value carries the contiguous
  coarser prefix `add_unit`'s carry needs (see `group_required_units/1`
  in [lib/tempo/interval.ex](lib/tempo/interval.ex)). A *non-anchored*
  time-of-day group — e.g. a bare minute group `[hour: 16, minute:
  {:group, 1..15}]` with no year/month/day — therefore returns
  `{:error, :unanchored_group}` rather than materialising to the
  relative span `[16:01, 16:16)`.

  This was a deliberate call when fixing the `5G10DU` crash. Revisit
  whether non-anchored *time-of-day* groups (as opposed to date groups)
  should instead materialise to a non-anchored interval.

  **Pros of materialising them:**

  * Tempo already supports non-anchored time-of-day values (a bare
    `~T`-derived Tempo, `to_time/1`), so a non-anchored time-of-day
    *interval* is a consistent extension of that axis.

  * It's strictly more capable — relative spans like "minutes 1..15 of
    some hour" become first-class, usable for templating/recurrence
    patterns before anchoring.

  * Before the group fix these produced *wrong* bounds silently;
    materialising them correctly would close that gap rather than
    trading one non-result (wrong) for another (error).

  **Cons / why it currently errors:**

  * A non-anchored interval can't project to UTC (`to_utc_seconds/1`
    raises without `:year`), so `duration/1`, Allen comparison, and all
    set operations would raise on it — a value that materialises but
    can't be used in most pipelines is a footgun.

  * The carry is only well-defined when the group doesn't hit the unit
    max (minute 1..15 is fine; minute 45..59 must carry into an `:hour`
    that may be absent), so "sometimes materialises, sometimes errors"
    is murkier than a clean "anchor it first."

  * Date groups (`:day`/`:month`) genuinely *can't* be materialised
    without anchoring (variable month length); keeping one rule —
    "groups need their anchoring prefix" — is simpler than splitting
    date-group vs. time-group behaviour.

  If we do allow them, the natural shape is: materialise time-of-day
  groups to a non-anchored interval, leave date groups erroring, and
  document that the result lives on the time-of-day axis until anchored
  (see `guides/interop.md` for the anchored/non-anchored distinction).

## Review later — observations from the v0.15.1 round-trip + un-anchored math sprints (2026-07-03)

These surfaced while implementing ISO 8601 round-tripping and un-anchored `shift`/set-operations. None block release; each is a design or maintainability call to make deliberately rather than let stand by accident.

* ~~**Consolidate the two parallel selection builders.**~~ **Done.** Both paths now build the selection through `Tempo.RRule.Rule.to_selection/1` — the single source of truth for the RRULE/cron → selection mapping. `Tempo.RRule.build_repeat_rule/1` builds a `%Rule{}` from its parsed parts (`struct(Rule, parts)`) and delegates; `Tempo.RRule.Expander.repeat_rule/1` delegates directly. The duplicated `push_by`/`push_byday`/`push_wkst`/`push_or_day` helpers were removed from both callers. The original observation: they "independently assembled the `[selection: …]` keyword list" and the v0.15.1 work had to apply the *same* fix to both twice over (byday-before-time ordering, then range consolidation) — that drift trap is now closed.

* **`function_exported?/3` without `Code.ensure_loaded?/1` is a non-determinism class, not a one-off.** `months_in_year_unanchored/1` in [lib/math.ex](lib/math.ex) took the wrong branch when the calendar module was not yet loaded (`function_exported?` answers `false` for a cold module), so un-anchored month arithmetic passed on a warm module and failed on a cold one. Fixed there with `Code.ensure_loaded?`. Sweep the sibling libs (`calendrical`, `localize`) for the same pattern now that calendrical exposes optional callbacks (`months_in_year/0`) that downstreams probe this way — the failure hides behind green tests because the test run warms the module.

* **Decide what a bare un-anchored partial value *means*.** The set-operation anchor model (`:non_anchored`) was designed for time-of-day only — `guides/set-operations.md` literally defined it that way until this sprint. Month/day (`~o"1M31D"`) and bare-day (`~o"15D"`) values fell into the same class with no first-class semantic, which is why cross-axis set operations silently misaligned until guarded (`same_axis?/2` in [lib/operations.ex](lib/operations.ex)). Deeper: `~o"15D"` is treated as one abstract day-span, but a mask like `1985-XX-15` expands to twelve disjoint days — the same intuitive "the 15th," two different models. Ratify whether a bare partial is a single abstract span (current, by implementation) or a recurring set, and make the code express the choice rather than inherit it.

* ~~**Ratify or revert the `V`/`Q` selection designators.**~~ **Ratified.** `V` (BYSETPOS) and `Q` (WKST) are kept as permanent Tempo extensions: they express selections ISO 8601 cannot (`V` ranks the merged per-period candidate set — "last weekday" ≠ "last Friday"; `Q` sets a non-Monday week start, which ISO has no spelling for), and neither the ISO ordinal `I` nor set operations can reproduce them. Documented with worked examples and the (low) interchange risk in conformance guide §5; the RFC 5545 string via `Tempo.to_rrule/1` remains the portable wire format.

* ~~**Write down the un-anchored arithmetic ambiguity boundaries.**~~ **Done.** The governing principle is now stated where the logic lives (the "Un-anchored arithmetic" comment block in [lib/math.ex](lib/math.ex)) and in the user-facing `Tempo.shift/2` doc: *an un-anchored shift is computed when its result is invariant to the missing year, and returns `%Tempo.RequiresAnchorError{}` when it isn't — never raising.* The specific boundaries (year no-op, `2M29D` + `P1Y` erroring, the month-wrap, the day-clamp, the bare-day shortest-month rule) are enumerated as worked applications of that one principle, with a directive that future cases be decided by the principle rather than the clamp's incidental behaviour. The `2M29D` + `P1Y` → error call is confirmed and doctested.

## 1.0 readiness review — deferred items (2026-07-05)

A pre-1.0 readiness review (security/robustness, ISO 8601 + RRULE conformance, documentation, code quality) found the library in strong shape. The input-robustness blockers (an exponential set/group parse, an unbounded input length) and the recurrence-materialisation quadratic (`R10000/…/P1D` was ~6 s; now ~20 ms via absolute-day arithmetic in `Tempo.Math`) were fixed in that round. The following are parked — none block 1.0, each is a deliberate engineering or governance call:

* ~~**Ratify the `V`/`Q` selection designators.**~~ **Ratified** — kept as permanent extensions; see the v0.15.1 review note above and conformance guide §5.

## Conceptual-model review — deferred items (2026-07-11)

* **Decide what `Enum` over a recurring interval yields.** Today `Enum.count(R5/2022-01-01/P1M)` walks the *first occurrence's days* (31) — the recurrence count is ignored, which is wrong on two axes. The candidates: yield the N occurrences (as intervals, matching what `to_interval/1` materialises), or refuse like `relation/2` and `duration/1` now do (both direct the caller to `to_interval/2` + the set-level API). The crisp single-span API refuses recurrences uniformly since 2026-07-11; Enumerable is the remaining surface that silently misreads them.

* **Decide what a bare un-anchored partial value *means*** — carried from the v0.15.1 review above (`~o"15D"` is one abstract day-span while `~o"1985-XX-15"` is twelve disjoint days; same intuitive referent, two models). Revisit deliberately before 1.0.
