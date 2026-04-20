# ISO 8601 Conformance & Full-Parser Research

Research brief for Tempo, 2026-04-19. Focus: whether any public conformance test suite covers ISO 8601 (especially Part 2 / 2019 extensions), and which other libraries actually implement the full standard — not just the RFC 3339 subset.

## 1. Conformance test suites

### Findings at a glance

| Candidate | Scope | License | Suitable for Tempo? |
|---|---|---|---|
| Official ISO/IEC test suite for 8601 | — | — | **No evidence found.** ISO does not appear to publish a conformance test suite for 8601-1 or 8601-2. ISO sells conformance test method standards for other IT areas (e.g. ISO/IEC 9646, 19823-*, 13650-1), but a search of iso.org for "8601" + "conformance"/"test methods" returns nothing. The 2019 revision text itself is the only artefact available for purchase. |
| RFC 3339 test vectors (IETF) | RFC 3339 subset | Public | None published. The RFC contains illustrative examples (e.g. `1985-04-12T23:20:50.52Z`, `1996-12-19T16:39:57-08:00`) but no normative vector file. |
| IJMacD `rfc3339-iso8601` comparison table | RFC 3339 vs ISO 8601 Part 1 | MIT | Useful as a human-readable matrix of valid/invalid strings across the two specs. Explicitly disclaims completeness: "There are thousands (if not millions) of possible combinations… not practical to enumerate." Good for spot-checks, not a suite. |
| TC39 `test262` (Temporal) | RFC 3339 + RFC 9557, ECMAScript subset of 8601 | BSD | Thousands of Temporal parse/format tests. Covers Part 1 only. No Part 2 coverage. Licence friendly. |
| CPython `test_datetime` / `Lib/test/datetimetester.py` | `fromisoformat` / `isoformat` of Part 1 | PSF | As of 3.11 `fromisoformat` grew broader ISO 8601 coverage; the test module exercises many edge cases (basic/extended, T/space separator, fractional components, offsets). No Part 2. |
| OpenJDK `jdk/test/java/time/` | java.time ISO formatters | GPL+CPE | Extensive. Covers Part 1 formatters only. License is copyleft — borrowing test strings (facts) is fine, but lifting test code is not. |
| ICU / CLDR | Locale-formatted dates; ISO 8601 is a peripheral concern | Unicode | Not a conformance suite for 8601; CLDR's tests target locale patterns. |
| W3C date/time note (`NOTE-datetime`) | A tiny RFC 3339–like profile | W3C Document | Six illustrative examples, nothing more. |
| `edtf-validate` (UNT Libraries) `tests/test_valid_edtf.py` | Full EDTF = 8601-2 Levels 0/1/2 | BSD-3-Clause | **The most promising source.** ~250–300 classified strings split across L0/L1/L2 valid dates, valid intervals, and a dedicated invalid list. See §3. |
| `python-edtf` test suite | EDTF Levels 0/1/2; every example in the spec feature table | MIT | Also promising. Smaller corpus but README explicitly claims "every example given in the spec table of features" is tested. |
| `edtf.js` test suite | EDTF Levels 0/1/2 (+ experimental L3 seasons) | BSD-2-Clause | Per-feature files (`date.js`, `interval.js`, `season.js`, `set.js`, `year.js`, etc.) plus a `sample.js` fixture. |
| Academic corpora: TimeBank, i2b2 Clinical Temporal Relations Challenge, TE-3 | TIMEX3 / ISO-TimeML normalisations, which subset 8601 | Varies; mostly research-only | Test inputs are natural-language; they normalise to ISO 8601 but aren't designed as parser conformance. Low value for Tempo. |
| HeidelTime resources | Rule patterns, not vectors | GPL | Same as above — tagger, not a parser corpus. |

### Bottom line

The maintainer's search is correct: **no public conformance suite published by ISO, IETF, or W3C exists for ISO 8601**. The closest thing to de facto Part 1 coverage is `test262` (Temporal); the closest thing to Part 2 coverage is the triad of EDTF test suites (`edtf-validate`, `python-edtf`, `edtf.js`).

## 2. Full ISO 8601 implementations (Part 1 + Part 2)

| Library | Language | URL | Part 2 coverage | Licence |
|---|---|---|---|---|
| `edtf.js` | JavaScript | https://github.com/inukshuk/edtf.js | **Full L0/L1/L2** — sets `{}` `[]`, uncertainty `?`/`~`/`%`, unspecified `X`, year expansion `Y`, seasons, qualified intervals | BSD-2-Clause |
| `edtf-ruby` | Ruby | https://github.com/inukshuk/edtf-ruby | Full EDTF (older draft, not yet updated for 2019 revision per the project's own note) | BSD-2 |
| `python-edtf` | Python | https://github.com/ixc/python-edtf | L0/L1/L2 per README; updated for 2019 standard | MIT |
| `edtf2` | Python | https://pypi.org/project/edtf2/ | Fork adding more 2019 features | MIT |
| `go-edtf` (SFO Museum) | Go | https://github.com/sfomuseum/go-edtf | L0 full; most of L1/L2; explicitly incomplete: no >4-digit years, no compound phrases | MIT-style (unverified, LICENSE file present) |
| `ProfessionalWiki/EDTF` | PHP | https://github.com/ProfessionalWiki/EDTF | Full EDTF levels 0/1/2 | GPL-2.0-or-later |
| `edtf` (mbklein / nulib) | Elixir | https://hex.pm/packages/edtf | EDTF parser + English rendering; current 1.3.0 | MIT |
| `iso-8601` crate | Rust | https://crates.io/crates/iso-8601 | Aims for full 8601-1 (calendar/week/ordinal, durations, intervals, recurring); **no Part 2** | MIT/Apache-2.0 |
| `chrono` | Rust | https://docs.rs/chrono | RFC 3339 subset of Part 1 only | MIT/Apache-2.0 |
| `DateTime::Format::ISO8601` | Perl | https://metacpan.org/pod/DateTime::Format::ISO8601 | Broad Part 1 (2000 edition); intervals "in a later release"; no Part 2 | Artistic 2.0 |
| `java.time` | Java | JSR-310 | RFC 3339 subset; no Part 2 | GPL+CPE (OpenJDK) |
| `Temporal` (TC39) | JavaScript | https://tc39.es/proposal-temporal/ | RFC 3339 + RFC 9557; no Part 2 | BSD (test262) |
| PostgreSQL | SQL | https://www.postgresql.org/docs/current/datetime-input-rules.html | Part 1 dates/times plus ISO 8601 intervals (§4.4.3.2 and §4.4.3.3). No Part 2. | PostgreSQL Licence |
| Oracle / SQL Server | SQL | — | RFC 3339-ish subset; no Part 2 evidence found. | proprietary |
| Go `time.Parse` | Go | stdlib | RFC 3339 subset; no Part 2. | BSD |
| `ciso8601` | Python/C | https://github.com/closeio/ciso8601 | Fast RFC 3339 subset; explicitly not full 8601. | MIT |
| HeidelTime | Java | https://github.com/HeidelTime/heideltime | Natural-language tagger that normalises to TIMEX3/ISO 8601 — not a parser. | GPL-3 |

**Summary.** Outside the EDTF family, nothing on the public landscape implements ISO 8601-2 (Part 2). General-purpose date libraries (`java.time`, `chrono`, `datetime`, `date-fns`, `Temporal`) are all RFC 3339 / Part 1 subset implementations. The full-standard space is dominated by EDTF ports, and most of them share `inukshuk`'s design lineage.

## 3. EDTF crossover — can we adapt the tests?

Yes, and this is the single highest-leverage finding.

EDTF was drafted by the Library of Congress and folded wholesale into ISO 8601-2:2019 Part 2. The three levels map directly:

* **EDTF Level 0** — dates, date-times, intervals (8601-1 subset).
* **EDTF Level 1** — uncertain `?`, approximate `~`, both `%`; unspecified digits `X`; open-ended intervals `..` / blank; negative years; seasons; year resolution `198X`.
* **EDTF Level 2** — qualification of individual components (`1984?-06`), set `{}`, one-of `[]`, extended seasons with qualifiers, year scientific `Y170000002`, multi-valued unspecified digits.

Concretely, from `unt-libraries/edtf-validate/tests/test_valid_edtf.py` (BSD-3):

* `L0_Intervals` — 12 strings
* `L1_Intervals` — ~40 strings including negative years, open-ended, uncertainty qualifiers on endpoints
* `L2_Intervals` — ~50 strings including `X`-masks mid-component, per-component `?`/`~`/`%`
* Separate lists for valid dates, valid datetimes, and invalid strings (negative cases)

`python-edtf` and `edtf.js` each add their own per-feature suites — cross-referencing them gives Tempo a corpus of **~600–800 distinct strings** with known L0/L1/L2 classification and valid/invalid labelling.

License compatibility: BSD-2, BSD-3, and MIT are all attribution-only and compatible with Tempo's Apache-2.0 (per `mix.exs` → `LICENSE.md`). Test *data* — lists of valid date strings — is facts, not copyrightable in most jurisdictions, but keeping attribution in the Tempo test fixture headers is the safe path.

Gaps relative to Part 2 that even EDTF doesn't perfectly cover:

* Groups (`2018-05-{12,15,16}`) are in both EDTF L2 and 8601-2; well covered.
* Exponential years (`Y-17E7`) — EDTF L2 covers, but `go-edtf` and some others skip.
* Full calendar duration arithmetic (ISO 8601-2 clause 6) — EDTF does not define; Tempo will need to write these itself.
* Time interval with designators and recurrence (`R5/PT1H`) — in 8601-1, not EDTF. `iso-8601` Rust crate is the best reference here.

## 4. Recommendations for Tempo

1. **Borrow immediately.** Pull the three EDTF test string lists (`edtf-validate`, `python-edtf`, `edtf.js`) into a `test/fixtures/edtf/` directory with a LICENSE/ATTRIBUTION notice. Each string goes into an ExUnit data-driven test keyed by `{level, kind, expect_valid?}`. Dedup across the three sources; keep provenance comments. This gives Tempo several hundred classified Part 2 test cases on day one.

2. **Layer RFC 3339 and Temporal coverage on top.** For Part 1 edge cases (offset formats, fractional seconds, leap seconds, week dates, ordinal dates), cherry-pick inputs from `test262` Temporal parse tests and from CPython's `datetimetester.py`. These are the most adversarial Part 1 corpora in the wild.

3. **Read `edtf.js` parser for corner cases.** It's the most polished full-standard parser; its grammar (`src/grammar.pegjs`) is a good oracle for disambiguating Part 2 productions where the standard text is ambiguous (and it is, in several places around qualification scope).

4. **Read the Rust `iso-8601` crate for Part 1 intervals and recurring intervals.** It's the only library that handles `R[n]/<start>/<end>`, `R/<start>/<duration>`, etc., with serious care. `DateTime::Format::ISO8601` (Perl) is historically the most thorough on week/ordinal/basic-extended permutations — worth skimming for parser shape even though it doesn't do Part 2.

5. **Publish Tempo's corpus back.** There is a real gap here. Nothing in the community presents itself as "the ISO 8601 conformance suite." Tempo could:
   * Release `test/fixtures/iso8601/` as a standalone JSON/YAML file under a permissive licence (CC0 or MIT).
   * Classify each case by `{part: 1|2, clause: "4.1.2.3", kind: date|time|datetime|duration|interval|set|group, level: 0|1|2, expect: :ok | {:error, reason}}`.
   * Mirror it at something like `github.com/kipcole9/iso8601-conformance` so other-language implementers can adopt it. Given the absence of any official suite, this would plausibly become a small de facto standard — the LoC EDTF page at https://www.loc.gov/standards/datetime/implementations.html already links community implementations, so getting a test-vector entry listed there is realistic.

6. **Do not pay ISO for a test suite.** No evidence one exists. The standard itself (ISO 8601-1:2019 CHF 118, ISO 8601-2:2019 CHF 118) is worth buying for canonical text, but there is no companion test artefact to purchase.

## Sources

* https://www.iso.org/standard/70908.html — ISO 8601-2:2019
* https://www.iso.org/iso-8601-date-and-time-format.html — ISO overview page
* https://en.wikipedia.org/wiki/ISO_8601
* https://www.loc.gov/standards/datetime/ — LoC EDTF spec
* https://www.loc.gov/standards/datetime/implementations.html — LoC list of EDTF implementations
* https://lcnetdev.github.io/standards/datetime/edtf.html — current EDTF spec HTML
* https://github.com/inukshuk/edtf.js — JS full implementation (BSD-2)
* https://github.com/inukshuk/edtf-ruby — Ruby (BSD-2)
* https://github.com/ixc/python-edtf — Python (MIT)
* https://pypi.org/project/edtf2/ — Python fork with 2019 additions
* https://github.com/sfomuseum/go-edtf — Go (MIT-style)
* https://github.com/ProfessionalWiki/EDTF — PHP (GPL-2)
* https://hex.pm/packages/edtf — Elixir EDTF (MIT)
* https://github.com/unt-libraries/edtf-validate — Python validator + test corpus (BSD-3)
* https://crates.io/crates/iso-8601 — Rust full Part 1 parser
* https://docs.rs/chrono — Rust chrono (Part 1 subset)
* https://metacpan.org/pod/DateTime::Format::ISO8601 — Perl
* https://github.com/tc39/test262 — ECMAScript conformance (Temporal tests)
* https://tc39.es/proposal-temporal/ — TC39 Temporal
* https://github.com/python/cpython/issues/80010 — CPython expanding `fromisoformat`
* https://github.com/IJMacD/rfc3339-iso8601 — MIT comparison table
* https://datatracker.ietf.org/doc/html/rfc3339 — RFC 3339
* https://www.postgresql.org/docs/current/datetime-input-rules.html — PostgreSQL rules
* https://github.com/HeidelTime/heideltime — HeidelTime tagger (GPL-3)
