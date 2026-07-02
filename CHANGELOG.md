# Changelog

## [v0.15.0] — 2026-07-02

### Added

* A Claude Code **skill** — shipped as a GitHub plugin — that maps a natural-language date/time problem to validated, runnable Tempo (`~o"…"` syntax, the right layer, checked with `Tempo.explain/1`), plus a *Using Tempo with an AI assistant* guide. Install with `/plugin marketplace add kipcole9/tempo` then `/plugin install tempo@tempo-plugins`.

### Changed

* `Tempo.Cron.parse/2` and `parse!/2` now return a recurring `%Tempo.Interval{}` — the same first-class value `Tempo.RRule.parse/2` produces — instead of an internal `%Tempo.RRule.Rule{}`. A parsed cron schedule now materialises directly with `Tempo.to_interval/2` (no `Expander` step) and accepts a `:from` anchor; the raw field mapping stays available internally.

### Fixed

* Recurrence occurrences now span their selection's own resolution — "the 15th of every month" (`FREQ=MONTHLY;BYMONTHDAY=15`, `~o"R/2025-01-15/P1M/FL15DN"`, or cron `0 0 15 * *`) materialises as the *day* the 15th, not the month-long cadence it sits in. Native ISO 8601-2, RRULE, and cron now agree on occurrence spans, while a plain repeating interval still spans its cadence.

## [v0.14.0] — 2026-07-02

### Added

* Graded before/after predicates — `Tempo.certainly_before?/2`, `possibly_before?/2`, `certainly_after?/2`, and `possibly_after?/2` answer the disjoint-order question three-valued (`:certain | :possible | :impossible`) over `±` margin-of-error intervals, alongside the existing overlap/within certainty functions.

### Changed

* The graded relations now compute the *exact* set of possible Allen relations — enumerating each operand's discrete `±` placements rather than treating endpoints independently — so verdicts are tighter (e.g. `relation_certainty(~o"2000±5Y", ~o"2000±5Y", [...year relations])` is now `:certain`). Margins beyond ±128 units per operand fall back to the previous sound O(1) endpoint-range method.

* Enumerating a masked value now yields its candidates in ascending order — `~o"2020-06-XX"` gives the 1st … 30th, consistent with year masks and materialisation (month/day masks previously enumerated descending). Mask candidate generation is now shared between the enumeration and materialisation paths through a single resolver, so they can no longer diverge.

### Removed

* The web visualizer — `Tempo.Visualizer` and its `Standalone` Bandit server — is removed, along with the optional `:plug` and `:bandit` dependencies. Interactive exploration is moving to an LLM-based approach that better fits Tempo's scope.

## [v0.13.0] — 2026-07-02

### Fixed

* `Tempo.shift/2`, `Tempo.Math.add/2` and `subtract/2` now support unspecified-digit masks instead of crashing, including masks spanning several components (`195X`, `2020-XX`, `19XX-XX`, `199X-06-XX`). A shift moves the value's block: a block-aligned single-year shift stays a mask (`195X` + `P10Y` → `196X`), a contiguous shift returns a one-of set (`195X` + `P1Y` → `~o"[1951Y..1960Y]"`), and a mask with a concrete component after it — which denotes *disjoint* spans — returns a coalesced IntervalSet (`199X-06-XX` + `P1Y` → the ten Junes of 1991–2000).

* Fixed several long-standing mask bugs surfaced by the above: enumerating a month/day mask dropped single-digit values (`2020-06-XX` skipped days 1–9), `Enum.count/1` on a masked value returned the block count rather than the candidate count, and materialising a non-contiguous mask (`199X-06-XX`) raised instead of expanding to its disjoint intervals.

## [v0.12.0] — 2026-07-02

### Added

* Graded relations over `±` margin-of-error intervals: `Tempo.overlap_certainty/2`, `within_certainty/2`, and modal predicate pairs (`certainly_overlaps?/2`, `possibly_overlaps?/2`, …) answer Allen-relation queries three-valued (`:certain | :possible | :impossible`). Crisp intervals degrade exactly to the existing boolean predicates.

### Fixed

* `Tempo.shift/2` and `Tempo.Math.add/2` / `subtract/2` no longer crash on margin-of-error (`±`) or significant-digits (`S`) values; the annotation now rides along with the shifted component (`Tempo.shift(~o"2018±2Y", ~o"P1Y") == ~o"2019±2Y"`), completing the crisp-inert treatment begun in 0.11.1.

## [v0.11.1] — 2026-07-01

### Fixed

* A margin-of-error value (`~o"2018±2Y"`) crashed `Tempo.relation/2`, `Tempo.to_interval/2`, and endpoint comparison with an `ArithmeticError`. The `±` annotation is now crisp-inert — dropped for materialisation and comparison, preserved on the value — so a `±`-bearing value behaves identically to its crisp core (margin-aware graded relations are a future step).

* A significant-digits value (`~o"1950S3"`) crashed `Tempo.to_interval/2` and `Tempo.relation/2` with an `ArithmeticError`. It now materialises to the block of values sharing its leading digits — `1950S3` spans `~o"1950Y/1960Y"`, identical to the equivalent mask `195X` — and the `S` annotation is preserved on the value.

## [v0.11.0] — 2026-07-01

### Changed

* Recurrences are now constructed and documented as first-class interval values rather than the internal RRULE AST builder. A simple periodic recurrence is `Tempo.Interval.new!(from: dtstart, duration: ~o"P1W", recurrence: :infinity)` (or the `~o"R/…/P1W"` literal), and a calendar rule is `Tempo.RRule.parse!("FREQ=MONTHLY;BYDAY=2MO", from: …)`, which returns a recurring `%Tempo.Interval{}`; both materialise with `Tempo.to_interval(value, bound: …)`.

### Fixed

* `Tempo.Interval.new/1` returned an un-inspectable, non-canonical `to: :undefined` for any interval built from a `:duration`. It now derives the endpoint as `to: nil`, so duration and recurring intervals inspect and round-trip as `~o"2020Y/P1D"` and `~o"R/…/P1W"`; open-ended intervals (no `:duration`) are unchanged.

* Inspecting a recurring interval whose `BYDAY` filter carries an ordinal (`FREQ=MONTHLY;BYDAY=2MO`, `-1FR`, `1MO,3MO`) raised a `FunctionClauseError`. The `:byday` selection now renders in the instance/day-of-week notation (`~o"R/2025Y1M1D/P1M/FL2I1KN"`).

## [v0.10.2] — 2026-06-30

### Added

* Component-level "one of a set" (ISO 8601-2 / EDTF): `~o"[1,2,3]M"` is the one-of counterpart of the all-of `~o"{1,2,3}M"`, distributing across the value to a one-of `Tempo.Set` (`2020Y[1,2]M` → one of `2020Y1M`, `2020Y2M`); ranges expand and multiple one-of components form the cartesian product.

* One-of sets work in interval endpoints too: `2020Y[1,2]M/2021Y` distributes to a one-of set of intervals, and an explicit one-of set of intervals (`~o"[2020Y/2021Y,2022Y/2023Y]"`) now builds its interval members correctly.

### Fixed

* Rounding a time of day to the hour or minute always rounded up — `Tempo.round(~o"T10H10M", :hour)` returned `~o"T11H"` instead of `~o"T10H"`. It now rounds to nearest (≤ half down, > half up).

## [v0.10.1] — 2026-06-30

### Fixes

* Links to guides in README.md

## [v0.10.0] — 2026-06-30

### Added

* `Tempo.Network` — a chronological-network constraint layer implementing the ChronoLog scheme (Levy et al. 2020) over Tempo's intervals: time-periods with independent start/end/duration bounds, sequences, and the ChronoLog relation vocabulary, normalised to a Simple Temporal Problem and solved by Floyd–Warshall (`consistent?/1`, `tighten/1`, and explanatory `trace/3`). Reproduces the paper's ChronoLand and 26th-dynasty results exactly.

* `Tempo.Network.Relation` covers ChronoLog's full boundary lattice: the precise Allen relations (`:starts`, `:started_by`, `:finishes`, `:finished_by`), `:strictly_contemporary`, and a parameterised `{:boundary, edge, comparison, edge}` for the start/end before/after/at relations. Validated by decoding and re-solving ChronoLog's published case studies (Egyptian 26th dynasty, RDC-2022 Near-Eastern models, Mediterranean LBA).

* `Tempo.shift/2` now accepts a `Tempo.Duration` directly (`Tempo.shift(~o"2026", ~o"P2Y")`), in addition to the keyword-list form; both delegate to `Tempo.Math.add/2`.

* `Tempo.weekend?/2` and `Tempo.workday?/2` classify a day against a territory's weekend (`weekend?(~o"2026-06-12", :SA)` is `true`, `:US` is `false`). Weekend days come from CLDR via `Localize.Calendar.weekend/1`; the day of week from `Date.day_of_week/1`, computed in the value's own calendar so non-Gregorian values are correct.

* Business-day arithmetic: `Tempo.add_working_days/3` (forward or backward, skipping the territory's weekend), `Tempo.next_working_day/2`, `Tempo.previous_working_day/2`, and `Tempo.working_days_in/2`.

* IXDTF offset/zone consistency (RFC 9557 §4.2): `Tempo.validate_zone_offset/1` flags a numeric offset that disagrees with its IANA zone, and `Tempo.from_iso8601/2` accepts `strict: true` to reject such a value at parse time. A DST fall-back offset is treated as disambiguation, not disagreement.

* `Tempo.IntervalSet.slots/3` cuts a free-time region into discrete fixed-length bookable slots (`slots(mutual_free, ~o"PT1H")`), with an `:every` spacing option. Complements the set operations: where `difference`/`intersection` give the free regions, `slots/3` discretises them into bookable windows.

* `Tempo.Schedule` — constraint-based project scheduling (critical path method) over `Tempo.Network`: declare tasks with durations and finish-to-start dependencies, anchors and deadlines, then `solve/1` for each task's early/late position and `critical?` flag, plus `critical_path/1` and `span/1`. An over-tight deadline or dependency cycle is reported infeasible.

### Changed

* A pure time-of-day group now materialises to a non-anchored interval (`[hour: 16, minute: {:group, 1..15}]` → `[16:01, 16:16)`) instead of erroring, when its upper bound stays within the day. Date groups and end-of-day carries still require anchoring.

* `Tempo.Network` now derives its axis unit from duration bounds as well as dates, so a purely relative network of day-length periods measures in days rather than collapsing onto the default year axis.

### Fixed

* iCal import no longer produces zero-extent intervals. A punctual event (RFC 5545 §3.6.1 zero-duration, or an explicit `DTEND == DTSTART`) now materialises as the one-unit implicit span of its start, tagged `metadata: %{punctual: true}`, upholding the domain's no-degenerate-interval invariant through set operations.

## [v0.9.0] — 2026-06-29

### Added

* `Tempo.to_date_time/1` — convert a zoned Tempo back into a `DateTime`, preserving the named time zone and re-deriving the UTC offset from the time-zone database (the lossless inverse of `from_elixir/2` on a `DateTime`). DST fall-back ambiguity is resolved using the value's stored offset, and a spring-forward gap returns an error.

* `Enumerable` `count/1`, `member?/2`, and `slice/1` are now implemented for `%Tempo{}`, delegating to the materialised interval's O(1) `Tempo.Interval.Steps` paths instead of an O(n) walk. They are DST-aware (a spring-forward day counts 23 hours, a fall-back day 25); group, range, and selection values fall back to the reduce walk.

* ISO 8601-2 expanded years — a sign-prefixed year of five or more digits (`+12022`, `-12022`, `+002022`, `+12022-06-15`). The mandatory sign distinguishes the expanded form from a basic-format date, and a signed four-digit value (`+2006`) is rejected as it is neither basic nor expanded.

* Multi-year cron fields — a 7-field cron carrying a year list or range (`0 0 0 1 1 * 2025,2027,2029`) now expands to occurrences in exactly those years, via a new non-standard `:byyear` field on `Tempo.RRule.Rule`. Previously only a single concrete year was honoured and multi-year lists were silently dropped.

* Cron `W` (nearest-weekday) day-of-month — `15W` and `LW` now resolve to the nearest weekday within the month (Saturday → Friday, Sunday → Monday, never crossing a month boundary), via a new non-standard `:bymonthday_nearest` field on `Tempo.RRule.Rule`. Previously `W` returned an `:unsupported_w` error.

* Cron POSIX day-of-month OR day-of-week — when both fields are restricted (`13 * 5` — "the 13th or any Friday"), occurrences are now the union of the two, via a new non-standard `:bymonthday_or_byday` field on `Tempo.RRule.Rule`. A Quartz extension (ordinal `5#2`, or nearest-weekday `15W`) opts out and keeps the AND-composing interpretation.

* ISO 8601-2 §8 component qualification is now spec-conformant and round-trips. On parse, a qualifier at the rightmost end is *complete* (`2004-06-11%` → the whole value), to the right of a component is *group* (`2004-06~-11` → the month and the year), to the left is *individual* (`2004-?06-11` → the month only), and the explicit designator form (`2004~Y6?M11D`, including a qualified BC year `2004~YB`) parses too. `inspect/1` and `to_iso8601/1` render the per-component qualifications back in explicit form — a parsed group re-encodes as the equivalent `2004~Y6~M11D` — and, per §8.2.4, collapse a uniformly-qualified value to the compact complete form (`2004%Y6%M11%D` → `2004Y6M11D%`).

### Changed

* `Tempo.from_elixir/2` now infers resolution for `Time`, `NaiveDateTime`, and `DateTime` from the type's declared precision (`:second`, or `:microsecond`) rather than the magnitude of the components, so `~U[2022-07-04 09:00:00Z]` is a fully specified second (not an hour) and round-trips losslessly through `to_naive_date_time/1`. Pass an explicit `:resolution` to force a coarser span (e.g. `resolution: :day` for a midnight value).

### Bug Fixes

* Cron day-of-week steps now expand in cron numbering (Sunday = 0) before mapping to RFC, so `0/3` yields Wed, Sat, Sun (previously collapsed to Sunday alone) and `*/2` yields Tue, Thu, Sat, Sun. A Sunday-spanning range step LHS such as `0-3` no longer builds a descending range.

* `Enumerable.Tempo.Interval.reduce/3` is now DST-aware, so an interval's `Enum.to_list/1` agrees with its `Enum.count/1`: a spring-forward day walks 23 hours and a fall-back day 25 (the folded hour emitted twice with its two offsets), matching the `Tempo.Interval.Steps` fast paths and the implicit `%Tempo{}` walk. The classification now lives in a shared `Tempo.Enumeration.Zone`.

* `Tempo.Interval.Steps.nth_step/4` now disambiguates a DST fall-back's duplicated hour, assigning each occurrence its own offset. This makes the O(1) `slice/1` fast path exact across a DST transition, so `Enum.at/2` and `Enum.slice/2` agree with the walk for zoned values too (they previously deferred to the O(n) reduce walk).

* Implicit enumeration of a `%Tempo{}` now resolves its range against the value's own calendar instead of defaulting to Gregorian, for both the `Enum` walk and the `count`/`member?`/`slice` fast paths. A Coptic/Ethiopic year (or a Hebrew leap year) now enumerates 13 months, and a 30-day Coptic month enumerates 30 days rather than a non-existent Gregorian-style 31.

* `Tempo.from_iso8601/1` now rejects genuinely inverted intervals such as `2026/2025` with a `Tempo.IntervalEndpointsError`. The check is narrow — it compares against the end's exclusive upper bound, so EDTF reduced-precision (`1111-01-01/1111`), masked, and non-anchored midnight-crossing (`T22/T02`) intervals stay valid.

* The ISO 8601-2 parser no longer raises `KeyError` when a selection is adjacent to a group; such pairs now validate resolution ordering from each wrapper's units, yielding a clean parse or a clean `Tempo.ParseError`. A copy-paste bug that disabled cross-group ordering validation is also fixed.

* `Tempo.Compare.to_utc_seconds/1` now resolves ISO week dates (`2022-W24`) and ordinal dates (`2022-166`) to their real calendar date before projecting. Previously they collapsed to January 1, so every week interval reported a zero-second duration and adjacent weeks compared `:equals` instead of `:meets`.

* `Tempo.to_interval/1` now materialises group values — centuries (`20C`), decades (`201J`), and unit groups (`2018Y1G6MU`) — to the single contiguous span they denote (`20C` → `[2000, 2100)`). Year groups previously raised an `ArithmeticError`, other unit groups widened to the wrong bounds, and a non-anchored group (`5G10DU`) now returns a clean `:unanchored_group` error instead of crashing.

* `Tempo.to_interval/1` now materialises second-resolution values to a one-second span `[t, t+1s)` instead of returning `{:error, :finest_resolution}`. Since sub-second resolution landed, a second is no longer the finest unit, so the common case of a plain `DateTime`/`NaiveDateTime` (which infers to second resolution) can now become an interval and participate in set operations.

* `Tempo.to_naive_date_time/1` and `Tempo.to_time/1` no longer error on zoned values; they drop the offset and return the wall-clock reading (matching `to_date/1` and the stdlib `DateTime.to_naive/1`), not shifted to UTC. Use `to_date_time/1` to keep the zone, or `shift_zone(tempo, "Etc/UTC")` to normalise to UTC wall time first.

## [v0.8.0] — 2026-06-27

### Bug Fixes

* `Tempo.ICal.from_ical/2` now follows RFC 5545 §3.6.1 for events with no `DTEND`/`DURATION`: a `DATE`-valued `DTSTART` spans exactly one day and a `DATE-TIME` `DTSTART` becomes a zero-duration point (`to == from`) rather than being widened by one resolution unit. The all-day end boundary also stays at day resolution instead of drifting to an hour-resolution midnight.

## [v0.7.0] — 2026-05-28

### Added

* Sub-second (fractional-second) resolution via a `:microsecond {value, precision}` component matching Elixir's `Time`/`DateTime` shape (precision capped at 6 digits). Parsing, materialisation (`[v, v+1ulp)`), Allen comparison, durations (`PT0.5S`) and arithmetic, ISO 8601 / inspect round-trip, `from_elixir`/`to_naive_date_time`, and explicit-interval enumeration are all sub-second aware. Trailing zeros are significant — `.120` (millisecond) and `.12` (centisecond) are distinct resolutions.

* `Tempo.Interval.equivalent?/2` — temporal-extent equality that ignores metadata, calendar, and zone-display labels by projecting endpoints to UTC and comparing only the temporal positions. Matches the equivalence notion of Grüninger and Li's `T_bounded_meeting` ontology (TIME 2017).

* Property tests verifying Allen's interval-algebra axioms and the Sum Axiom of `T_bounded_meeting`. Checks joint exhaustiveness, self-equality, inverse consistency, `meets` asymmetry, and predicate-relation consistency across 1000+ randomly generated interval pairs per property.

### Changed

* Fractional-second input is now preserved rather than truncated. `~o"...45.123"`, `PT1.250S`, and `Tempo.from_elixir(datetime_with_microseconds)` previously dropped the sub-second part; they now retain it as a `:microsecond` component. `Tempo.utc_now/0` and `now/1` remain second-resolution by contract (use `from_elixir(DateTime.utc_now())` for a sub-second reading).

* `Tempo.Interval.new/1` now rejects empty intervals (`from == to`) with `Tempo.IntervalEndpointsError`. Internal set operations already filtered these out; this change closes the public-API hole and matches the ontology's exclusion of degenerate intervals from the domain.

* `Tempo.Operations` set-producing functions (`union/3`, `intersection/3`, `difference/3`, `complement/2`, `symmetric_difference/3`, `members_overlapping/3`, `members_outside/3`, `members_in_exactly_one/3`) now have proper `@spec` operand types (`Tempo.t() | Tempo.Interval.t() | Tempo.IntervalSet.t() | Tempo.Set.t()`) instead of `any()`. Brings them into line with the predicate functions and the `align/3` contract.

* `Tempo.Interval` `@moduledoc` documents the discrete-style interval boundary semantics (exclusive upper bound, `meets` at the seam) against the continuous underlying time line. Clarifies that Tempo's half-open convention matches Rust's `allen-intervals` discrete-domain choice and Hayes' open-interval model cited by Grüninger and Li.

## [v0.6.0] — 2026-05-23

### Added

* `Tempo.parse/2` and `Tempo.parse!/2`. Parse a locale-formatted date, time, datetime, or interval string into a `Tempo` (or `Tempo.Interval` for ranges) by delegating to `Calendrical.parse/2`. Forwards `:locale`, `:calendar`, and `:reference_date` to Calendrical and normalises the resulting field map for `Tempo.new/1`.

* `Tempo.new/1` and `Tempo.new!/1` now also accept a map. `Calendar.ISO` is silently normalised to `Calendrical.Gregorian`, so an Elixir `Date`, `Time`, or `NaiveDateTime` can be passed via `Map.from_struct/1` directly.

## [v0.5.0] — 2026-04-28

### Breaking — set operations now match textbook semantics

The named set operations now behave the way the symbols in `A ∩ B`, `A ∖ B`, and `A △ B` read in a textbook: each returns the *trimmed instant-level result* (covered time). Member-preserving filters — the "give me the whole events that survive" form — moved to explicitly named `members_*` companions. `union/2` is unchanged (the only member-preserving default — coalesce explicitly with `IntervalSet.coalesce/1` for the merged-span form).

* `Tempo.intersection/2` now returns the trimmed overlap. Previous member-preserving form is `Tempo.members_overlapping/2`. Previous `Tempo.overlap_trim/2` is removed — `intersection/2` does its job.

* `Tempo.difference/2` now returns the trimmed remainder (`A` with `B`-shaped holes punched out — possibly splitting an `A` member into multiple fragments). Previous member-preserving form is `Tempo.members_outside/2`. Previous `Tempo.split_difference/2` is removed — `difference/2` does its job.

* `Tempo.symmetric_difference/2` now returns the trimmed non-shared edges of both operands. Previous member-preserving form is `Tempo.members_in_exactly_one/2`.

Migration:

* "What's the overlap?" / "What time is in both?" → `intersection/2` (no change in name; behaviour now trimmed).
* "Which of these meetings hit the query window?" → `members_overlapping/2` (was `intersection/2`).
* "Workday minus lunch as free-time blocks" / "Free time around busy" → `difference/2` (no change in name; behaviour now trimmed). This fixes the previously broken `Tempo.difference(workday, lunch)` pattern, which used to drop the whole workday.
* "Which workdays aren't holidays?" → `members_outside/2` (was `difference/2`). The numeric result is the same when each `A` member is either fully covered or fully outside any `B` member (workdays/holidays case), but `members_outside` is the right name for an event-list question.
* Callers of `Tempo.overlap_trim/2` → `Tempo.intersection/2`.
* Callers of `Tempo.split_difference/2` → `Tempo.difference/2`.

The motivation: when a user reads `Tempo.intersection(japan_trip, enrolled)` or `Tempo.difference(workday, lunch)` aloud, they're describing a covered-time question. The library should return that, not surprise them by collapsing whole members. The member-preserving forms remain available — and clearly named — for the event-list questions where they're the right shape.

### Bug Fixes

* `Tempo.difference/2` (formerly `split_difference/2`) no longer emits a zero-width residue interval when an `A` member is fully consumed by a `B` member and additional `B` members remain. Surfaced when applying the new instant-level `difference` to multi-day workday/holiday set operations; previously masked because the trimmed form was rarely composed against multi-member B sets.

### Changes

* Removed `Tempo.Sigil` shim (was renamed to `Tempo.Sigils`)

## [v4.1.0] — 2026-04-25

### Bug Fixes

* Update `ex_doc` dependency config to remove possible conflict with calendrical's configuration.

## [v0.4.0] — 2026-04-25

### Added

* `~o` in match context. On the left-hand side of `match?/2`, `case` clauses, `=`, or a function head, the sigil now expands to a structural pattern — prefix-matching the value's `:time` keyword list while leaving `:calendar`, `:shift`, `:extended`, and `:qualification` unconstrained. Thanks to @am-kantox for the PR.

## [v0.3.0] — 2026-04-23

### Added

* `Tempo.Interval.metadata/1`. Named accessor for the `:metadata` map on an interval. Mirrors `from/1`, `to/1`, `endpoints/1`, and `resolution/1` added in v0.2.0, so user-facing code never has to reach into struct fields to read iCal `SUMMARY`, `LOCATION`, event UIDs, or any other per-interval data attached by the caller.

### Changed

* Renamed `Tempo.compare/2` and `Tempo.Interval.compare/2` to `Tempo.relation/2` and `Tempo.Interval.relation/2`. The function returns one of 13 Allen interval-algebra relations (`:precedes`, `:meets`, `:overlaps`, …), not the `:lt | :eq | :gt` shape stdlib's `compare/2` promises. The new name avoids the trap.

* Renamed `Tempo.Sigil` to `Tempo.Sigils` (plural), and moved `calendar_from/1` out to `Tempo.Sigils.Options`. `import Tempo.Sigils` now brings only `sigil_o/2` and `sigil_TEMPO/2` into scope — no helper functions leak. The old `Tempo.Sigil` module remains as a deprecated compatibility shim and will be removed in a future major version.

* `Tempo.Visualizer` and `Tempo.Visualizer.Standalone` now compile only when **both** `:plug` and `:bandit` are available. Previously Plug alone was enough to trigger compilation of `Tempo.Visualizer`, and `Standalone` referenced `Bandit` unguarded — so a downstream application that depended on Tempo without pulling in either library saw "undefined module" warnings during compilation. Both modules still expose stub `init/call/start/child_spec/stop` functions that raise a single actionable error when called without the deps in place.

### Bug Fixes

* ISO week-date resolution now uses `Calendrical.ISOWeek` semantics throughout the validation path, regardless of the caller's declared calendar. There is room to be more selective than this (there can be multiple ways to construct a week-based calendar). However there isn't yet a clear way to influence that decision other than through a `-u-ca` qualifier and that only allows ISO Week calendars.

* `Tempo.to_date/1` now handles ordinal dates (`[year, day]` — produced by the `O` designator, the extended `YYYY-DDD` form, or by enumerating a year-only Tempo as days) and ISO week dates (`[year, week, day_of_week]`). Previously both shapes returned a `Tempo.ConversionError` even though the components unambiguously identify a single calendar day. Examples: `Tempo.to_date(~o"2020-166")` now returns `{:ok, ~D[2020-06-14]}`; `Tempo.to_date(~o"2020-W24-3")` returns `{:ok, ~D[2020-06-10]}`; and `~o"2020Y{1..-1}D" |> Enum.to_list() |> hd() |> Tempo.to_date()` returns `{:ok, ~D[2020-01-01]}`.

## [v0.2.0] — 2026-04-23

### Adds

* `Tempo.new/1`, `Tempo.new!/1`, `Tempo.Interval.new/1`, `Tempo.Interval.new!/1`, `Tempo.Duration.new/1`, `Tempo.Duration.new!/1`.

* `Tempo.Interval.spans_leap_second?/1`, `leap_seconds_spanned/1`, and `Tempo.Interval.duration(iv, leap_seconds: true)`. Interval-level leap-second detection and an opt-in duration that counts them. Lets scientific pipelines account for exact elapsed time without Tempo accepting `23:59:60` as a value.

* `Tempo.LeapSeconds.removals/0`. Extension point for future negative leap seconds (CGPM agreed in 2022 that they may become necessary from ~2035). Empty today; interval-level helpers already treat insertions and removals uniformly.

* `Tempo.LeapSeconds`. The 27 IERS-announced positive leap-second dates from 1972-06-30 through 2016-12-31, exposed as `dates/0`, `on_date?/3`, and `latest/0`. Drives historical validation of `:60` seconds.

* Historical leap-second validation. `23:59:60` is now accepted only on the 27 IERS-announced dates. The previous structural check (hour/minute/month-day/offset) remains; a new check rejects `:60` on any other June 30 or December 31. Error messages point callers at `Tempo.LeapSeconds.dates/0`.

* Zone-gap parse rejection. A zoned wall time that falls inside a daylight-saving or zone-transition gap (e.g. `2024-03-10T02:30:00[America/New_York]`) is now rejected at parse time via `Tzdata.periods_for_time/3`. DST fall-back ambiguity is accepted; coarser-than-minute values and unzoned values skip the check.

* `Tempo.year/1`, `month/1`, `day/1`, `hour/1`, `minute/1`, `second/1`. Commodity component accessors for `%Tempo{}` and `%Tempo.Interval{}` values. Return `nil` when the component isn't specified; raise `ArgumentError` when called on an interval whose span covers multiple values of that unit.

* `Tempo.Interval.from/1`, `to/1`, `endpoints/1`, `resolution/1`. Named endpoint and span-resolution accessors so user-facing code never has to reach into struct fields.

* `Tempo.IntervalSet.count/1`, `map/2`, `filter/2`. Named helpers that treat the set as a sequence of member intervals — the complement to the `Enumerable` protocol, which walks sub-points.

* `Tempo.select/2`. Polymorphic composition primitive: narrows a base span (`%Tempo{}`, `%Interval{}`, or `%IntervalSet{}`) by a selector (integer lists, ranges, `%Tempo{}` / `%Interval{}` projection, or a function). Pure function — no ambient reads. Always returns `{:ok, %IntervalSet{}}`, composing with the other set ops.

* `Tempo.workdays/1` and `Tempo.weekend/1`. Territory-aware day-of-week constructors that return `%Tempo{}` selector values — composable with `Tempo.select/2`. Accept a territory atom (`:US`), territory string, locale string (`"ar-SA"`), or `%Localize.LanguageTag{}`; default chain is `Application.get_env(:ex_tempo, :default_territory)` then ambient locale. `workdays(t) ++ weekend(t)` partitions the seven days of the week.

* `Tempo.Territory.resolve/1`. Normalises a territory, territory string, locale, or language-tag value to a canonical uppercase territory atom. The single resolution chain used by `Tempo.workdays/1` and `Tempo.weekend/1`.

* `Tempo.explain/1`. Returns a structured, prose explanation of any Tempo value. `Tempo.Explain` provides `to_string/1`, `to_ansi/1`, and `to_iodata/1` formatters so renderers (the visualizer, terminals, HTML surfaces) can style each tagged part independently.

* Inspect polish. Zoned Tempos round-trip via the sigil with the `[zone_id]` IXDTF trailer. `%Tempo.IntervalSet{}` inspects as `#Tempo.IntervalSet<…>` with a preview and metadata summary. `%Tempo.Interval{}` with non-empty `:metadata` shows the event summary inline.

* iCalendar import. `Tempo.ICal.from_ical/2` and `from_ical_file/2` parse RFC 5545 `.ics` data (via the optional `ical` dependency) into `%Tempo.IntervalSet{}` with per-event metadata on each interval. Overlapping events are preserved.

* Full RFC 5545 `RRULE` expansion. Every `BY*` rule (`BYMONTH`, `BYMONTHDAY`, `BYYEARDAY`, `BYWEEKNO`, `BYDAY` with and without ordinals, `BYHOUR`, `BYMINUTE`, `BYSECOND`), `BYSETPOS`, `WKST`, and the `RDATE`/`EXDATE` extras flow through one tagged AST into `Tempo.to_interval/2` and `Tempo.RRule.Selection`. All 30 RFC 5545 §3.8.5.3 worked examples pass — Thanksgiving, Election Day, Friday-the-13th, first-Saturday-after-first-Sunday, last-weekday-of-month, and the rest. Calendar-aware throughout. Unbounded rules still require `:bound`.

* `Tempo.RRule.parse/2` + `Tempo.to_rrule/1`. Parse an RFC 5545 RRULE string to the shared AST; round-trip through the encoder preserves every supported field (including `WKST` and BYDAY-with-ordinal as pairs).

* `Tempo.RRule.Expander.expand/3`. Thin adapter from `%Tempo.RRule.Rule{}` or `%ICal.Recurrence{}` to `%Tempo.Interval{}` AST, delegating materialisation to `Tempo.to_interval/2`. One interpreter path for every recurrence source.

* `Tempo.to_interval/2`. Accepts `:bound` (for unbounded recurrences). New stream pipeline `iterate_recurrence/7` is the single expansion loop — bounded `n`, unbounded `UNTIL`, and `:bound`-capped all share it.

* `RDATE` additive and `EXDATE` subtractive in `Tempo.ICal.from_ical/2`. `final = (expand(rrule) ∪ rdates) − exdates`. RDATEs carry the event's span (`DTEND − DTSTART`); EXDATEs match on the occurrence's start moment via `Tempo.Compare.compare_endpoints/2`.

* Metadata on `%Tempo.Interval{}` and `%Tempo.IntervalSet{}`. Free-form `:metadata` maps travel through set operations — intersection and difference tag result fragments with the A-operand's metadata; set-level metadata follows the first operand.

* Set operations. `Tempo.union/2`, `intersection/2`, `complement/2`, `difference/2`, `symmetric_difference/2`, and predicates (`disjoint?`, `overlaps?`, `subset?`, `contains?`, `equal?`) on any Tempo value. Results are always `%Tempo.IntervalSet{}`.

* Cross-calendar set operations. Operands in different calendars (e.g. Hebrew vs Gregorian) are converted via `Date.convert!/2`; the result inherits the first operand's calendar.

* Midnight-crossing non-anchored intervals. `T23:30/T01:00` anchored to day D materialises as `[D T23:30, D+1 T01:00)`; on the pure time-of-day axis, such intervals are split before set-op sweep-line runs.

* `Tempo.anchor/2`. Axis composition primitive — combines a date-like value with a time-of-day into a datetime. Not a set operation; used to prepare cross-axis values for set algebra.

* `Tempo.Compare`. New shared module with `compare_time/2` (start-moment keyword-list comparison, padding missing trailing units with their unit minimum) and `to_utc_seconds/1` (zone-aware projection via `Tzdata`, per-call, no cache).

* `Tempo.Math.add/2` and `subtract/2`. Calendar-aware Tempo-plus-Duration arithmetic with end-of-month day clamping (`Jan 31 + P1M = Feb 28`, `Feb 29 + P1Y = Feb 28`). Weeks expand to days; negative components subtract.

* Non-contiguous mask expansion. `1985-XX-15` now materialises to an IntervalSet of 12 day-intervals (the 15th of each month) instead of widening to year. Partial masks (`1985-X5-15`) narrow to valid candidates.

* Bounded recurrence and duration-bounded intervals. `R3/1985-01/P1M` expands to N occurrences; `1985-01/P3M` and `P1M/1985-06` materialise to closed intervals via `Tempo.Math` arithmetic. `Enum.to_list/1` on a duration-bounded interval now respects the bound instead of running unbounded.

* `%Tempo.IntervalSet{}` — multi-interval values. Sorted, list of intervals. `to_interval/1` now returns `Interval | IntervalSet` depending on expansion; use `to_interval_set/1` when a uniform shape is wanted.

* Multi-interval materialisation. Range-in-slot (`{1..3}M`), stepped ranges, cartesian ranges, and all-of sets expand to an IntervalSet. One-of sets (`[a,b,c]`) return an error — they're epistemic disjunctions, not free/busy lists.

* Unified conversion from Elixir date/time types. `Tempo.from_elixir/2` accepts `Date.t`, `Time.t`, `NaiveDateTime.t`, or `DateTime.t` and returns a `%Tempo{}` at an inferred or explicit resolution.

* `Tempo.from_date_time/1`. Previously missing for `DateTime.t` — the existing `from_date/1`, `from_time/1`, `from_naive_date_time/1` family now has its fourth member. UTC offset (including DST) populates `:shift`; the IANA zone name and numeric offset in minutes populate `:extended`.

* `Tempo.extend_resolution/2`* fills finer units with their start-of-unit minimum values up to a target resolution.

* `Tempo.at_resolution/2`* dispatches to `trunc/2` or `extend_resolution/2` based on whether the target is coarser or finer than the current resolution. Idempotent when the target matches. The single entry point for normalising a Tempo to a known resolution.

* Implicit-to-explicit interval conversion. `Tempo.to_interval/1` and `Tempo.to_interval!/1` materialise any implicit-span `%Tempo{}` into the equivalent `%Tempo.Interval{}`.

* Support the Internet Extended Date/Time Format (IXDTF) as defined in [draft-ietf-sedate-datetime-extended-09](https://www.ietf.org/archive/id/draft-ietf-sedate-datetime-extended-09.html). An optional suffix such as `[Europe/Paris][u-ca=hebrew]` may follow an ISO 8601 datetime.

* Add an `:extended` field to `%Tempo{}` holding `%{calendar:, zone_id:, zone_offset:, tags:}` parsed from the IXDTF suffix (or `nil` when no suffix is present).

* `Tempo.Iso8601.Tokenizer.tokenize/1` now returns `{:ok, {tokens, extended_info}}` where `extended_info` is either `nil` or the parsed IXDTF map.

* Astronomical seasons. ISO 8601-2 season codes 25–28 (Northern) and 29–32 (Southern) now expand to intervals bounded by the relevant March/September equinox and June/December solstice as computed by the `Astro` library. Codes 21–24 remain meteorological calendar approximations.

* Leap-second validation. ISO 8601 permits `second = 60` as a positive leap second. Tempo now accepts it only when the minute is 59, the hour is 23, the calendar date (if present) is 30 June or 31 December, and any time-zone offset is zero. All other uses of `second = 60` are rejected.

* ISO 8601-2 / EDTF qualification operators. Expression-level `?` (uncertain), `~` (approximate) and `%` (both) are now parsed. The parsed qualification is carried on the new `:qualification` field of `%Tempo{}`; the bounded interval semantics of the value are unchanged.

* EDTF conformance corpus. 200+ valid and invalid strings from the `unt-libraries/edtf-validate` corpus (BSD-3-Clause) are now exercised as ExUnit tests. The known-failure list is tracked in `test/tempo/iso8601/edtf_corpus_test.exs`.

* EDTF Level 2 component-level qualification. `?`, `~` and `%` qualifiers can now appear adjacent to individual date components (`2022-?06-15`, `2022-06?-15`, `?2022-06-15`, `%-2011-06-13`). The qualification is stored per-component on the new `:qualifications` field of `%Tempo{}` (a `%{unit => qualifier}` map). Expression-level qualifiers continue to populate the single `:qualification` field.

* Per-endpoint qualification in intervals. Each endpoint of an interval may now carry its own qualifier (`1984?/2004~`, `2019-12/2020%`). The qualifier attaches to that endpoint's `%Tempo{}` struct rather than the interval as a whole.

* Open-ended intervals. `1985/..`, `../1985`, and `../..` now parse, along with the equivalent trailing-/leading-slash forms `1985/`, `/1985`, `/`, `/..`, `../`. Open endpoints are represented as `:undefined` on the `%Tempo.Interval{}` struct.

* Unspecified digits in negative years. Strings like `-1XXX-XX`, `-XXXX-12-XX`, and `-1X32-X1-X2` now parse. The negative sign was previously discarded by `form_number`, causing a crash in `parse_date/1`; it is now carried on the mask as a `:negative` sentinel.

* EDTF long-year notation. `Y`-prefix years with exponent notation (`Y17E8`, `Y-17E7`) or significant-digit annotations (`Y171010000S3`, `Y-171010000S2`) now parse. Combined with existing support for 4-digit `Y`-prefix years (`Y2022`) and plain 5+ digit years (`Y170000002`), this completes Tempo's coverage of the geological-scale year syntax.

* 100% EDTF corpus coverage. The `unt-libraries/edtf-validate` corpus — the only publicly-available conformance test suite we could find for ISO 8601-2 Part 2 — now passes in full. 183 strings exercised, 0 known failures.

* Web visualizer. `Tempo.Visualizer` is a `Plug.Router` that shows a parsed ISO 8601 / ISO 8601-2 / IXDTF string as a large-font echo followed by a component-by-component breakdown.

### Changed

* `tz` added as a `dev/test` dependency and installed as the default `Calendar.TimeZoneDatabase` in `config/dev.exs` and `config/test.exs`. Required for `ical` 2.0 to parse `DTSTART;TZID=…` properties — without a zone database installed, those events come through with `dtstart: nil` and are silently dropped. Runtime consumers configure their own database (see the README).

* Internal builder `Tempo.Iso8601.AST` now owns the token-to-struct conversion path formerly done by a `@doc false` `Tempo.new/2`. The old internal `new/2` is removed. External callers should have been unaffected (the old function was never public); internal callers in the parser / range / set / interval paths have been rewired.

* `Tempo.Clock.clock/0` checks `Process.get({Tempo.Clock, :clock})` before falling back to the application env. Lets the `NowTest` / `ToRelativeStringTest` suites install `Tempo.Clock.Test` process-locally so the swap doesn't leak into concurrent doctests. Fixes an intermittent CI failure in the `utc_now/0` / `now/1` / `utc_today/0` / `today/1` doctests when those suites ran interleaved.

* Leap-second handling is now ecosystem-aligned. `:second = 60` is **rejected at parse** regardless of date (matches `Calendar.ISO`, `Time`, and `DateTime` in Elixir/OTP). Leap-second information is preserved at the interval level via `spans_leap_second?/1`, `leap_seconds_spanned/1`, and `duration(iv, leap_seconds: true)`.

* Cross-calendar `Tempo.Interval.duration/1` now raises `ArgumentError` when endpoints are in different calendars instead of silently computing a garbage value. Error message points at set operations (which handle cross-calendar inputs automatically).

* Numeric zone offsets now bounded to ±24h. Nonsensical values like `+25:00` and `Z28H` are rejected at validation; the ISO 8601 grammar still accepts them but the semantic check refuses anything outside a plausible UTC offset.

* IXDTF `[u-ca=NAME]` suffix now swaps the Tempo struct's calendar. Parse routes the atom (e.g. `:hebrew`, `:islamic-umalqura`, `:ethioaa`) through `Calendrical.calendar_from_cldr_calendar_type/1` to the corresponding `Calendrical.*` module. Explicit `calendar` argument to `Tempo.from_iso8601/2` still wins over IXDTF.

* `mix.exs` docs structure follows the Localize layout — `name:`, `source_url:`, `package()`, `links()`, `groups_for_modules`, `groups_for_extras`, `source_ref`. Hex.pm landing page now anchors to the README rather than the `Tempo` module.

* Dialyzer build now enforces `:underspecs`, `:extra_return`, and `:missing_return` on top of the existing `:error_handling` and `:unknown` flags. All spec mismatches in `lib/` have been resolved.

* Removed all CLDR-family dependencies. `ex_cldr_calendars` has been replaced by [Calendrical](https://hex.pm/packages/calendrical) for calendar functionality and by `Localize.Utils.Math` / `Localize.Utils.Digits` for numeric helpers.

* Reduce parser compile time by ~85% (from ~190s to ~28s) and generated BEAM size by ~61% by converting high-fanout NimbleParsec combinators to `defparsecp` function boundaries. No runtime performance regression.

### Bug Fixes

* Enumeration of zoned values now honours DST transitions. On the day a zone enters DST, the iterator skips the "missing" wall-clock hour (e.g. `Enum.take(~o"2026-10-04[Australia/Sydney]", 5)` yields hours `[0, 1, 3, 4, 5]` — 02:00 never appears on a Sydney clock face that day). On the day a zone exits DST, the duplicated hour is emitted twice, distinguished by the `:shift` field: the first occurrence with the pre-transition offset, the second with the post-transition offset (per RFC 9557 IXDTF's explicit-offset fold disambiguator). The two emitted Tempos round-trip through the parser and project to distinct UTC instants 3600 seconds apart. Unzoned values and values outside DST transitions are unaffected.

* Fix parser interpretation of bare `~o"-1M"`. The `M` designator was resolving to `:minute` inside a time-zone shift (`[minute: -1]`) instead of `:month` (`time: [month: -1]`). Tightened `explicit_time_shift` to require `Z` alone or `Z`-prefixed explicit components; the ambiguous sign-plus-single-unit form now parses as a signed calendar component per ISO 8601-2 §4.4.1.

* Fix `Tempo.select` with negative components and week-of-month context. `~o"-1M"` on a year base now correctly resolves to December; `~o"-1D"` on a year base to Dec 31 (leap-aware); `~o"-1W"` on a year base to the last ISO week; `~o"1W"` on a month base to week-of-month. Week-of-year and week-of-month axes are now kept coherent through the `project_merge` pipeline.

* Fix `Tempo.Inspect` for values with a `:day_of_year` component. `~o"166O"` (day-of-year 166) and its negative-count companion `~o"-1O"` now render through the ISO 8601-2 `O` designator instead of raising a FunctionClauseError inside inspect.

* Removed `Tempo.Shift` (no-op stub that silently dropped shifts) and `Tempo.Comparison` (self-described as "badly wrong" template code with no callers). The one rounding branch that depended on `Tempo.Shift` — `round(time_of_day, :day)` — now returns a clear `Tempo.RoundingError` instead of crashing.

* `Tempo.Interval.spans_leap_second?/1` boundary bug fixed. An interval like `[23:59:59Z, next 00:00:00Z)` now correctly reports `true` — the leap second 23:59:60Z is within this span under the half-open `[from, to)` convention. Previously an off-by-one in the containment test missed the boundary case.

* `Tempo.Interval.empty?/1` now returns `true` for inverted intervals (`from > to`), and `duration/1` returns `PT0S` for any empty interval. Inverted intervals used to silently produce a negative duration.

* Explicit numeric offsets now disambiguate DST fall-back correctly. `01:30:00-04:00[America/New_York]` and `01:30:00-05:00[America/New_York]` now resolve to different UTC instants as RFC 9557 §4.5 describes; previously the zone_id won unconditionally and the explicit offset was silently ignored.

* `Tempo.from_iso8601!/1` no longer silently overrides IXDTF `[u-ca=NAME]` with `Calendrical.Gregorian`. Previously the bang form always passed Gregorian explicitly, which (per the explicit-wins-over-IXDTF rule) nullified the calendar tag; now matches the behaviour of `Tempo.from_iso8601/1`.

* `%Tempo.Interval{}` inspect now preserves each endpoint's IXDTF extended trailer (zone, calendar, tags). Previously the sigil output dropped `[zone]` and `[u-ca=cal]` from interval endpoints even though the data was stored on the underlying Tempo values.

* Spec tightening across the public API to satisfy dialyzer's strict flags. Refined `@spec`s on `Tempo.Compare.to_utc_seconds/1`, `Operations` predicates (`disjoint?/overlaps?/subset?/contains?/equal?`), `RRule.Expander.to_ast/2`, and `Tempo.Interval.resolution/1`.

* Recurrence cadence applies as `DTSTART + i × INTERVAL` (scalar multiplication) rather than `i` successive `+ INTERVAL` steps. The old iterative approach clamped Feb 29 → Feb 28 at step 1 and never recovered; `YEARLY` rules anchored on Feb 29 now correctly produce Feb 29 on every leap year.

* BY-rule EXPAND semantics per RFC 5545 §3.3.10 table. `BYMONTH`/`BYMONTHDAY`/`BYYEARDAY`/`BYWEEKNO` expand when `FREQ` is coarser than the rule's unit (previously they only filtered). Notes 1 and 2 are honoured — `BYDAY` downgrades from EXPAND to LIMIT when `BYMONTHDAY`/`BYYEARDAY` is co-present.

* DTSTART is always the first materialised occurrence. BY-rule EXPAND can legitimately produce candidates earlier than DTSTART (e.g. `BYMONTHDAY=1` with `DTSTART=Sep 30` also yields Sep 1); those are now dropped by the `iterate_recurrence` loop to match the RFC.

* `matches_mask?/2` checks digit equality position-by-position. The previous implementation always returned `true` for concrete digit positions, which silently let non-contiguous year masks like `1_6_` accept any 4-digit candidate. The dialyzer silencer attached to this function has been removed.

* Fix compiler warnings around `%NaiveDateTime{}` struct updates and unreachable clauses in the set enumerable protocol.

* Fix `Enum.take/2` and related Enumerable operations on values with unspecified-digit year masks.

* Fix `Enum.take/2` on year-month-day masks where the day is unspecified (e.g. `1985-XX-XX`, `1985-12-XX`).

* `Tempo.Enumeration.add_implicit_enumeration/1` now raises a clear `ArgumentError` when `Tempo.Iso8601.Unit.implicit_enumerator/2` returns `nil` (e.g. trying to enumerate a fully-specified second-resolution datetime — no finer unit exists).

* Fix group enumeration (`2022Y5G2MU`). The `{:group, %Range{}}` token shape produced by expanded `nGspanUNITU` constructs now has a matching clause in `Tempo.Enumeration.do_next/3` that unwraps the range into the standard range-iteration path. Previously crashed with `no function clause matching in Tempo.Enumeration.do_next/3`.

* Fix selection enumeration (`2022YL1MN`). The `{:selection, _}` clause in `do_next/3` is now ordered before the generic `is_unit` clause, which would otherwise match the selection's inner keyword list and destructively iterate it. `explicitly_enumerable?/1` no longer treats a bare selection as an enumerable shape on its own. The selection tuple is preserved verbatim on every yielded Tempo.

* Enumerate long-year significant-digit shapes (`1950S2`, `Y12345S3`). Year values tagged `{integer, [significant_digits: n]}` now iterate over the block of candidate years sharing the leading n digits (`1950S2` → `1900..1999`, `Y12345S3` → `12300..12399`). Blocks larger than 10,000 candidates raise a clear `ArgumentError` rather than hanging — callers who want to refer to a significant-digits year without iterating can still hold the parsed AST. Negative values enumerate in most-negative-first order.

* Extend `Tempo.Validation.resolve/2`'s `{:year, year}, {:month, months}` clause guard to accept `%Range{}` months. Previously only `is_list(months) or is_integer(months)` was accepted, which meant the implicit month enumerator (`1..-1//-1`) never conformed against `months_in_year` when the year was a range value. Enables correct `1950S2`-style significant-digits enumeration.

* Implement `Enumerable.Tempo.Interval`. Closed intervals and open-upper intervals (`1985/..`) now iterate forward one resolution-unit at a time from the `:from` endpoint; fully-open (`../..`) and open-lower (`../1985`) intervals raise `ArgumentError` with a clear message (no anchor from which to iterate). Iteration honours the half-open `[from, to)` convention — the upper bound is exclusive, so adjacent intervals concatenate without overlap or gap.

* Enumeration of `from/duration` intervals (`1985-01/P3M`) and `R…/from/duration` recurrence intervals no longer crashes. The upper bound is currently treated as open — iteration proceeds forward from the `from` endpoint and `Enum.take/2` / `Stream.take/2` are the idiomatic way to halt it. Computing a concrete upper bound from `from + duration` is tracked separately; until that lands, `Enum.to_list/1` on such an interval is an infinite sequence (don't do it). `duration/to` intervals (`P1M/1985-06`) raise a clear `ArgumentError` explaining that Tempo-Duration subtraction is required to compute the lower bound.

* Enumeration of closed intervals with mismatched-resolution endpoints (`1985/1986-06`, `1985-06/1987`) now compares endpoints as their concrete start-instants rather than bailing on unit-list length mismatch. Missing trailing units are filled with their unit minimum (`:month`/`:day`/`:week` from 1, everything else from 0), so `1985` (start = 1985-01-01) correctly sorts before `1986-06` (start = 1986-06-01) and the interval yields both 1985 and 1986.

* Extend `Enumerable.Tempo.Interval` increment rules to cover `:week`, `:day_of_year`, and `:day_of_week` resolutions. Week-resolution intervals (`2022-W05/2022-W08`) now advance week-by-week, carrying into the next year at `calendar.weeks_in_year/1`.

## [v0.1.0]

This is the changelog for Tempo v0.1.0 released which was never released.

### Enhancements

* Add support for steps in set ranges. This is not ISO8601 compliant but is a natural expectation for Elixir. For example `~o"2023Y{1..-1//2}W"` says "every second week in 2023".

* Add `Tempo.round/2` to round a Tempo struct to a given resolution.

* Add `Tempo.to_date/1`, `Tempo.to_time/1` and `Tempo.to_naive_date_time/1`

* Add `Tempo.to_calendar/1` that will convert a `Tempo.t` struct to the most appropriate native Elixir date, time or naive date time struct.

### Bug Fixes

* Fix implicit enumeration of standalone months like `~o"3M"`. The requires an updated `ex_cldr_calendars` library that supports returning the number of days in the month without a year (returning an error if the result is ambiguous without a year).

* Many miscellaneous bug fixes.
