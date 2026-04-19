# Changelog 

## Tempo v0.2.0 (unreleased)

### Enhancements

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

### Changed

* **Removed all CLDR-family dependencies.** `ex_cldr_calendars` (and its transitive closure `ex_cldr`, `ex_cldr_numbers`, `ex_cldr_currencies`, `cldr_utils`, `digital_token`) has been replaced by [Calendrical](https://hex.pm/packages/calendrical) for calendar functionality and by `Localize.Utils.Math` / `Localize.Utils.Digits` for numeric helpers. The default calendar is now `Calendrical.Gregorian` instead of `Cldr.Calendar.Gregorian`. Calendrical bundles all 17 CLDR-aligned calendars directly and has broader calendar coverage than the previous setup.

* Reduce parser compile time by ~85% (from ~190s to ~28s) and generated BEAM size by ~61% by converting high-fanout NimbleParsec combinators to `defparsecp` function boundaries. No runtime performance regression.

### Bug Fixes

* Fix compiler warnings around `%NaiveDateTime{}` struct updates and unreachable clauses in the set enumerable protocol.

* Fix a range of Dialyzer warnings, including incorrect `@type time_unit` (was a list type, now a union of atoms), missing `nil` in struct field types, a `Calendat.t()` typo, and specs that did not include `{:error, _}` returns for `Tempo.trunc/2` and `Tempo.round/2`.

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
