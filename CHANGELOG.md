# Changelog 

## Tempo v0.2.0 (unreleased)

### Enhancements

* **Unified conversion from Elixir date/time types.** `Tempo.from_elixir/2` accepts `Date.t`, `Time.t`, `NaiveDateTime.t`, or `DateTime.t` and returns a `%Tempo{}` at an inferred or explicit resolution.

* **`Tempo.from_date_time/1`.** Previously missing for `DateTime.t` — the existing `from_date/1`, `from_time/1`, `from_naive_date_time/1` family now has its fourth member. UTC offset (including DST) populates `:shift`; the IANA zone name and numeric offset in minutes populate `:extended`.

* **`Tempo.extend_resolution/2`** fills finer units with their start-of-unit minimum values up to a target resolution.

* **`Tempo.at_resolution/2`** dispatches to `trunc/2` or `extend_resolution/2` based on whether the target is coarser or finer than the current resolution. Idempotent when the target matches. The single entry point for normalising a Tempo to a known resolution.

* **Implicit-to-explicit interval conversion.** `Tempo.to_interval/1` and `Tempo.to_interval!/1` materialise any implicit-span `%Tempo{}` into the equivalent `%Tempo.Interval{}` with concrete `from` and `to` endpoints under the half-open `[from, to)` convention. `~o"2026-01"` becomes `from: ~o"2026Y1M1D"`, `to: ~o"2026Y2M1D"`; `~o"156X"` becomes `from: ~o"1560Y"`, `to: ~o"1570Y"`. Masked values widen to the coarsest un-masked prefix (`~o"1985-XX-XX"` → year-resolution bounds). Idempotent on existing intervals, maps over `%Tempo.Set{}` members, returns an error for bare `%Tempo.Duration{}` (no anchor). All source metadata (`:qualification`, `:qualifications`, `:extended`, `:shift`, `:calendar`) propagates to both endpoints. This is the canonical representation used by the upcoming set-operations API.

* **`Tempo.Math` module.** New public primitives for time-unit arithmetic: `add_unit/3` (advance a Tempo or time-keyword-list by one unit at a given resolution, carrying into coarser units via calendar callbacks) and `unit_minimum/1` (the start-of-unit value — 1 for `:month` / `:day` / `:week` / `:day_of_year` / `:day_of_week`, 0 for everything else). Extracted from the private helpers in `Enumerable.Tempo.Interval` so both enumeration and interval materialisation share the same calendar-aware carry logic. `Tempo.Mask.mask_bounds/1` is also now public for computing the `{min, max}` numeric range of a digit-mask list.

* Support the Internet Extended Date/Time Format (IXDTF) as defined in [draft-ietf-sedate-datetime-extended-09](https://www.ietf.org/archive/id/draft-ietf-sedate-datetime-extended-09.html). An optional suffix such as `[Europe/Paris][u-ca=hebrew]` may follow an ISO 8601 datetime. Time zones are validated against `Tzdata` and calendars are validated against `Localize.validate_calendar/1`. The critical flag (`!`) is honoured — unknown critical segments cause the parse to fail while unknown elective segments are retained on the struct's new `:extended` field.

* Add an `:extended` field to `%Tempo{}` holding `%{calendar:, zone_id:, zone_offset:, tags:}` parsed from the IXDTF suffix (or `nil` when no suffix is present).

* `Tempo.Iso8601.Tokenizer.tokenize/1` now returns `{:ok, {tokens, extended_info}}` where `extended_info` is either `nil` or the parsed IXDTF map.

* **Astronomical seasons.** ISO 8601-2 season codes 25–28 (Northern) and 29–32 (Southern) now expand to intervals bounded by the relevant March/September equinox and June/December solstice as computed by the `Astro` library. Codes 21–24 remain meteorological calendar approximations.

* **Leap-second validation.** ISO 8601 permits `second = 60` as a positive leap second. Tempo now accepts it only when the minute is 59, the hour is 23, the calendar date (if present) is 30 June or 31 December, and any time-zone offset is zero. All other uses of `second = 60` are rejected.

* **ISO 8601-2 / EDTF qualification operators.** Expression-level `?` (uncertain), `~` (approximate) and `%` (both) are now parsed. The parsed qualification is carried on the new `:qualification` field of `%Tempo{}`; the bounded interval semantics of the value are unchanged.

* **EDTF conformance corpus.** 200+ valid and invalid strings from the `unt-libraries/edtf-validate` corpus (BSD-3-Clause) are now exercised as ExUnit tests. The known-failure list is tracked in `test/tempo/iso8601/edtf_corpus_test.exs`.

* **EDTF Level 2 component-level qualification.** `?`, `~` and `%` qualifiers can now appear adjacent to individual date components (`2022-?06-15`, `2022-06?-15`, `?2022-06-15`, `%-2011-06-13`). The qualification is stored per-component on the new `:qualifications` field of `%Tempo{}` (a `%{unit => qualifier}` map). Expression-level qualifiers continue to populate the single `:qualification` field.

* **Per-endpoint qualification in intervals.** Each endpoint of an interval may now carry its own qualifier (`1984?/2004~`, `2019-12/2020%`). The qualifier attaches to that endpoint's `%Tempo{}` struct rather than the interval as a whole.

* **Open-ended intervals.** `1985/..`, `../1985`, and `../..` now parse, along with the equivalent trailing-/leading-slash forms `1985/`, `/1985`, `/`, `/..`, `../`. Open endpoints are represented as `:undefined` on the `%Tempo.Interval{}` struct.

* **Unspecified digits in negative years.** Strings like `-1XXX-XX`, `-XXXX-12-XX`, and `-1X32-X1-X2` now parse. The negative sign was previously discarded by `form_number`, causing a crash in `parse_date/1`; it is now carried on the mask as a `:negative` sentinel.

* **EDTF long-year notation.** `Y`-prefix years with exponent notation (`Y17E8`, `Y-17E7`) or significant-digit annotations (`Y171010000S3`, `Y-171010000S2`) now parse. Combined with existing support for 4-digit `Y`-prefix years (`Y2022`) and plain 5+ digit years (`Y170000002`), this completes Tempo's coverage of the geological-scale year syntax.

* **100% EDTF corpus coverage.** The `unt-libraries/edtf-validate` corpus — the only publicly-available conformance test suite we could find for ISO 8601-2 Part 2 — now passes in full. 183 strings exercised, 0 known failures.

* **Web visualizer.** `Tempo.Visualizer` is a `Plug.Router` that shows a parsed ISO 8601 / ISO 8601-2 / IXDTF string as a large-font echo followed by a component-by-component breakdown.

### Changed

* **Removed all CLDR-family dependencies.** `ex_cldr_calendars` has been replaced by [Calendrical](https://hex.pm/packages/calendrical) for calendar functionality and by `Localize.Utils.Math` / `Localize.Utils.Digits` for numeric helpers.

* Reduce parser compile time by ~85% (from ~190s to ~28s) and generated BEAM size by ~61% by converting high-fanout NimbleParsec combinators to `defparsecp` function boundaries. No runtime performance regression.

### Bug Fixes

* Fix compiler warnings around `%NaiveDateTime{}` struct updates and unreachable clauses in the set enumerable protocol.

* Fix a range of Dialyzer warnings.

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

This is the changelog for Tempo v0.1.0 released on _____ 2023.  For older changelogs please consult the release tag on [GitHub](https://github.com/elixir-cldr/cldr/tags)

### Enhancements

* Add support for steps in set ranges. This is not ISO8601 compliant but is a natural expectation for Elixir. For example `~o"2023Y{1..-1//2}W"` says "every second week in 2023".

* Add `Tempo.round/2` to round a Tempo struct to a given resolution.

* Add `Tempo.to_date/1`, `Tempo.to_time/1` and `Tempo.to_naive_date_time/1`

* Add `Tempo.to_calendar/1` that will convert a `Tempo.t` struct to the most appropriate native Elixir date, time or naive date time struct.

### Bug Fixes

* Fix implicit enumeration of standalone months like `~o"3M"`. The requires an updated `ex_cldr_calendars` library that supports returning the number of days in the month without a year (returning an error if the result is ambiguous without a year).

* Many miscellaneous bug fixes.
