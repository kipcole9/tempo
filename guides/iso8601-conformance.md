# ISO 8601 Conformance Guide

Tempo implements a substantial subset of [ISO 8601:2019](https://www.iso.org/standard/70907.html) Part 1 and [ISO 8601-2:2019](https://www.iso.org/standard/70908.html) Part 2, plus the [IETF IXDTF draft (draft-ietf-sedate-datetime-extended-09)](https://www.ietf.org/archive/id/draft-ietf-sedate-datetime-extended-09.html). This guide catalogues what is supported, what isn't, and where Tempo diverges from the strict standard.

The canonical authority is the PDF of the ISO standard (held locally in `~/Documents/Development/iso_standards/`). When this document and the standard disagree, the standard wins — please file an issue.

## 1. Core principle — bounded intervals

Every Tempo value is a **bounded interval on the time line**, not an instant. `2026-01` is not the single moment "January 2026"; it is the interval `[2026-01-01, 2026-02-01)` — inclusive of the first boundary, exclusive of the last. This is called the **implicit-span semantics**: a partial date specification spans the next-finer unit that isn't given.

A single `Tempo.from_iso8601/1` call therefore always returns a bounded value, never a "partial" or "unresolved" date. This guarantees that set operations (planned: union, intersection, coalesce) can reason about every value uniformly.

## 2. ISO 8601 Part 1 — core representations

### Supported

| Feature | Examples |
|---|---|
| Year | `2022`, `-0001`, `+002022` |
| Year-month | `2022-06`, `202206` |
| Year-month-day | `2022-06-15`, `20220615` |
| Ordinal date | `2022-166`, `2022166` |
| Week date | `2022-W24`, `2022-W24-3`, `2022W243` |
| Month-day | `06-15`, `--0615` |
| Time of day | `T10`, `T10:30`, `T10:30:00`, `T103000` |
| Fractional seconds | `T10:30:00.5`, `T10:30:00,5` |
| Time zone `Z`, `+HH`, `+HH:MM`, `+HHMM` | `10:30:00Z`, `10:30:00+05:30` |
| Combined datetime | `2022-06-15T10:30:00Z` |
| Durations `PnYnMnDTnHnMnS` | `P1Y`, `PT30M`, `P3Y6M4DT12H30M5S` |
| Negative duration | `-P100D` |
| Fixed-endpoint interval | `2022-01/2022-06`, `20220101/20220630` |
| Duration-relative interval | `2022-01-01/P1Y`, `P1Y/2022-12-31` |
| Recurring interval | `R/2022-01/P1M`, `R5/2022-01/P1M` |
| Expanded (large) years | `+002022`, `-0001` |
| Leap second | `23:59:60Z` on 30 June or 31 December UTC |

### Partial or divergent

* **Truncated representations** (`--06-15`, `85-06-15` — 2-digit year) were deprecated in the 2019 edition and are not accepted. Modernise your input.

### Not supported

* Nothing known to be missing from Part 1 as of v0.2.0.

## 3. ISO 8601-2 Part 2 — extensions

### Supported

| Feature | Examples |
|---|---|
| **Unspecified digits** (`X`) | `156X`, `1XXX`, `2022-XX`, `1985-XX-XX`, `-1XXX-XX`, `-XXXX-12-XX` |
| **EDTF Level 1 qualification** (`?`, `~`, `%`) | `2022?`, `2022~`, `2022%` |
| **EDTF Level 2 component qualification** | `2022-?06-15`, `2022-06?-15`, `?2022-06-15`, `%-2011-06-13` |
| **Per-endpoint qualification in intervals** | `1984?/2004~`, `2019-12/2020%`, `2004-06-11%/2004-06~` |
| **Leading prefix qualifier** | `?2022-06-15`, `%2001`, `?-2004-06` |
| **Open-ended intervals** | `1985/..`, `../1985`, `../..`, `1985/`, `/1985`, `/`, `/..`, `../` |
| **Set of dates — all of** | `{1960,1961,1962}`, `{1960..1970}` |
| **Set of dates — one of** | `[1984,1986,1988]`, `[1667..1672]` |
| **Range in set** | `[1900..2000]`, `{-1640-06..-1200-01}` |
| **Groups** | `5G10DU` (5th group of 10 days), `2018Y4G60DU6D` (2018, day 6 of the 4th group of 60 days) |
| **Selections** | `L1MN`, `L2MI3N` (1st month, 3rd instance of the 2nd month) |
| **Meteorological seasons** (codes 21–24) | `2022-21` (spring), `2022-22` (summer), `2022-23` (autumn), `2022-24` (winter) |
| **Astronomical seasons** (codes 25–32) | `2022-25` (N spring), `2022-26` (N summer), `2022-27` (N autumn), `2022-28` (N winter), `2022-29..32` (Southern hemisphere). Boundaries computed via the `Astro` library using March/September equinoxes and June/December solstices (accurate to ≈2 minutes for years 1000–3000 CE). |
| **Quarters** (codes 33–36) | `2022-33` (Q1), `2022-36` (Q4) |
| **Quadrimesters** (codes 37–39) | `2022-37`, `2022-38`, `2022-39` |
| **Semestrals / halves** (codes 40–41) | `2022-40` (H1), `2022-41` (H2) |
| **Negative calendar qualification** | `-2004?`, `-2004-06?`, `-2001-34` (Q1 BCE) |
| **Sets / ranges with negative members** | `[-1667,1668]`, `{-1640-06..-1200-01}` |
| **Margin of error** | numeric literal with `±` (via `form_number`) |
| **Exponents on year** | `2018E3` style — parsed by `numbers.ex` `exponent()` |
| **Significant-digit annotations** (short form) | `1950S2`, `-1859S5`, `Y3388E2S3` |
| **Year-zero** (`0000`, `-0000`) | Parses as year 0. Interpretation per astronomical convention (year 0 = 1 BCE) is the caller's responsibility. |

### Not supported

| Feature | Example | Reason |
|---|---|---|
| Cross-endpoint semantic validation of intervals | `2012-24/2012-21` (winter before spring) | Parses at syntax level; semantic check (via Allen's Interval Algebra) is planned for the set-operations milestone. |

All other EDTF Level 2 features — including wide-range exponent years (`Y17E8`, `Y-170000002`) and long-year significant-digit annotations (`Y171010000S3`) — are supported.

## 4. IXDTF — Internet Extended Date/Time Format

Tempo implements the [IXDTF draft](https://www.ietf.org/archive/id/draft-ietf-sedate-datetime-extended-09.html) suffix syntax. After any ISO 8601 date-time, an optional suffix may carry:

| Suffix | Example | Stored on `%Tempo{}` |
|---|---|---|
| IANA time zone | `[Europe/Paris]` | `extended.zone_id` |
| Numeric offset | `[+08:45]`, `[-03:30]`, `[+0530]` | `extended.zone_offset` (minutes from UTC) |
| Calendar (`u-ca=`) | `[u-ca=hebrew]`, `[u-ca=gregory]` | `extended.calendar` (atom) |
| Generic tag | `[_foo=bar-baz]` | `extended.tags` (`%{"key" => ["value", ...]}`) |

Each bracket may be prefixed with `!` to mark it **critical**. Unrecognised critical tags cause the parse to fail; unrecognised elective tags are retained verbatim in `extended.tags`.

Time zones are validated against `Tzdata.zone_exists?/1`. Calendars are validated against `Localize.validate_calendar/1`, which also handles the `"gregory"` → `:gregorian` alias per BCP 47.

## 5. Project-specific extensions (not in ISO 8601)

These syntaxes are Tempo conveniences, not part of any standard:

* **Step in range** — `{1990..1999//2}Y` or `2023Y{1..-1//2}W` means "every second week in 2023".
* **Explicit suffixes** — `2022Y11M20D` instead of `2022-11-20`. Used by the `~o` sigil as the canonical output form.
* **Repeat rule** — `/F` combinator inside a parsed expression.
* **Selection instance count** — `L…N` with an `I` modifier for the nth instance.

None of these break ISO 8601 compatibility — Tempo accepts the standard forms too.

## 6. Ambiguity resolution

A few ISO 8601 constructs are genuinely ambiguous; Tempo resolves them as follows.

| Construct | Standard says | Tempo does |
|---|---|---|
| Seasons `21-24` | Hemisphere unspecified | Treated as **Northern meteorological** (`21` = spring = March-May). |
| `Z` without offset | "UTC is known, local offset unknown" (per RFC 5322 / IXDTF) | Stored as `shift: [hour: 0]`. No distinction from `+00:00`. |
| `-00:00` | ISO 8601:2000 forbade; ISO 8601:2019 permits | Permitted; equivalent to `Z`. |
| Leading qualifier on whole date | All components qualified | Stored on expression-level `:qualification` field only; individual components are not stamped. |

## 7. Test coverage

Tempo's conformance is exercised by:

* **`test/tempo/iso8601/dates_times_test.exs`** — Part 1 core representations.
* **`test/tempo/iso8601/duration_test.exs`**, **`interval_test.exs`**, **`set_test.exs`** — interval, duration, and set constructs.
* **`test/tempo/iso8601/extended_test.exs`** — IXDTF suffix parsing.
* **`test/tempo/iso8601/qualification_test.exs`** — EDTF L1 and L2 qualification.
* **`test/tempo/iso8601/open_interval_test.exs`** — open-ended intervals.
* **`test/tempo/iso8601/unspecified_digit_test.exs`** — unspecified-digit masks.
* **`test/tempo/iso8601/leap_second_test.exs`** — leap-second validation.
* **`test/tempo/iso8601/edtf_corpus_test.exs`** — the full `unt-libraries/edtf-validate` corpus (BSD-3-Clause), exercised at 100%. See `test/support/edtf_corpus.ex` for the raw strings and attribution.

As of v0.2.0 the suite runs 1592 tests with zero failures. The EDTF corpus is the only publicly-available conformance test set we know of for ISO 8601-2 Part 2; Tempo passes it in full.

## 8. Comparison to other implementations

No other known implementation in any language supports **full** ISO 8601 Parts 1 and 2. The RFC 3339 subset is covered by every mainstream date library (`java.time`, `chrono`, Python `datetime`, etc.). Part 2 — sets, groups, uncertainty, seasons, selections — is covered only by the EDTF family of libraries (`python-edtf`, `edtf.js`, `edtf-validate`, `mbklein/nulib` for Elixir), which themselves target EDTF's subset of the 2019 standard. Tempo's Part 2 coverage is roughly equivalent to EDTF Level 2 plus Tempo-specific extensions (groups, selections, step ranges).

See `docs/iso8601-conformance-research.md` for the detailed prior-art survey.

## 9. Reporting a conformance gap

If you have an ISO 8601 or EDTF string that should parse and doesn't, please open an issue including:

* The input string.
* The expected result (cite the ISO 8601 clause or EDTF level).
* The actual output from `Tempo.from_iso8601/1`.

Pull requests with a failing test case are especially welcome.
