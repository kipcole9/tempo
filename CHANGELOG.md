# Changelog 

## Tempo v0.3.0 - Unreleased

### Changed

* Renamed `Tempo.compare/2` and `Tempo.Interval.compare/2` to `Tempo.relation/2` and `Tempo.Interval.relation/2`. The function returns one of 13 Allen interval-algebra relations (`:precedes`, `:meets`, `:overlaps`, …), not the `:lt | :eq | :gt` shape stdlib's `compare/2` promises. The new name avoids the trap.

* Renamed `Tempo.Sigil` to `Tempo.Sigils` (plural), and moved `calendar_from/1` out to `Tempo.Sigils.Options`. `import Tempo.Sigils` now brings only `sigil_o/2` and `sigil_TEMPO/2` into scope — no helper functions leak. The old `Tempo.Sigil` module remains as a deprecated compatibility shim and will be removed in a future major version.

### Bug Fixes

* `Tempo.to_date/1` now handles ordinal dates (`[year, day]` — produced by the `O` designator, the extended `YYYY-DDD` form, or by enumerating a year-only Tempo as days) and ISO week dates (`[year, week, day_of_week]`). Previously both shapes returned a `Tempo.ConversionError` even though the components unambiguously identify a single calendar day. Examples: `Tempo.to_date(~o"2020-166")` now returns `{:ok, ~D[2020-06-14]}`; `Tempo.to_date(~o"2020-W24-3")` returns `{:ok, ~D[2020-06-10]}`; and `~o"2020Y{1..-1}D" |> Enum.to_list() |> hd() |> Tempo.to_date()` returns `{:ok, ~D[2020-01-01]}`.

## Tempo v0.2.0 - April 23rd, 2026

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

## Tempo v0.1.0

This is the changelog for Tempo v0.1.0 released which was never released.

### Enhancements

* Add support for steps in set ranges. This is not ISO8601 compliant but is a natural expectation for Elixir. For example `~o"2023Y{1..-1//2}W"` says "every second week in 2023".

* Add `Tempo.round/2` to round a Tempo struct to a given resolution.

* Add `Tempo.to_date/1`, `Tempo.to_time/1` and `Tempo.to_naive_date_time/1`

* Add `Tempo.to_calendar/1` that will convert a `Tempo.t` struct to the most appropriate native Elixir date, time or naive date time struct.

### Bug Fixes

* Fix implicit enumeration of standalone months like `~o"3M"`. The requires an updated `ex_cldr_calendars` library that supports returning the number of days in the month without a year (returning an error if the result is ambiguous without a year).

* Many miscellaneous bug fixes.
