# Tempo ISO 8601 Conformance Audit

**Date**: 2026-04-19  
**Standard versions**: ISO 8601:2019 (Part 1) and ISO 8601-2:2019 (Part 2)  
**Parser location**: `/Users/kip/Development/tempo/lib/iso8601/`

---

## 1. ISO 8601 Part 1 (Core Representations)

| Feature | Status | Notes |
|---------|--------|-------|
| **Basic format** (no separators: `20221120`) | ✅ Supported | Grammar: `implicit_year()` + `implicit_day_of_month()` in `grammar.ex:47–64` |
| **Extended format** (with separators: `2022-11-20`) | ✅ Supported | Grammar: `extended_date()` in `grammar.ex:66–84` |
| **Explicit format** (variable-length numbers) | ✅ Supported | Grammar: `explicit_date()` in `grammar.ex:86–137` |
| **Calendar dates** (YYYY, YYYY-MM, YYYY-MM-DD) | ✅ Supported | Multiple combinators in `grammar.ex:341–398` |
| **Ordinal dates** (YYYY-DDD, basic: YYYYDDD) | ✅ Supported | `implicit_ordinal_date()`, `extended_ordinal_date()`, `explicit_ordinal_date()` in `grammar.ex:148–164` |
| **Week dates** (YYYY-Www, YYYY-Www-D) | ✅ Supported | `implicit_week_date()`, `extended_week_date()`, `explicit_week_date()` in `grammar.ex:166–203` |
| **Times of day** (HH, HH:MM, HH:MM:SS) | ✅ Supported | `implicit_time_of_day()`, `extended_time_of_day()` in `grammar.ex:207–235` |
| **Fractional seconds/minutes/hours** | ✅ Supported | `fraction()` in `numbers.ex:218–224`; applied in time parsing |
| **Combined datetime (T separator)** | ✅ Supported | `implicit_date_time()`, `extended_date_time()`, `explicit_date_time()` in `grammar.ex:33–43` |
| **Time zone: Z (UTC)** | ✅ Supported | `zulu()` in `shift_indicator()`, `grammar.ex:592–598` |
| **Time zone: ±HH** | ✅ Supported | `implicit_time_shift()`, `extended_time_shift()` in `grammar.ex:552–587` |
| **Time zone: ±HHMM, ±HH:MM** | ✅ Supported | Parsed as hour + minute in time shift combinators |
| **Durations** (P…Y…M…W…D…T…H…M…S) | ✅ Supported | `duration_elements()`, `duration_date_element()`, `duration_time_element()` in `grammar.ex:253–290`; `tokenizer.ex:235–240` |
| **Time intervals** (start/end, start/duration, duration/end) | ✅ Supported | `interval_parser()` in `tokenizer.ex:103–125` |
| **Recurring intervals** (R[n]/interval) | ✅ Supported | `recurrence()` in `grammar.ex:602–610` |
| **Negative years** (e.g., `−0001Y`) | ✅ Supported | `maybe_negative_number()` in `numbers.ex:138–144`; explicit: `explicit_year_with_sign()` in `grammar.ex:361–367` |
| **Expanded years** (e.g., `+002022`) | ✅ Supported | Sign prefix allowed; `maybe_negative_number(min: 1)` |
| **Truncated forms** (2-digit year, `--MM-DD`) | ⚠️ Partial | 2-digit year as century (`19` → `{century: 19}`) in `grammar.ex:491–495`. Note: Many truncated forms were removed in 2019 edition; implementation treats as legacy. |
| **UTC designation** (Z) | ✅ Supported | Explicitly parsed; resolves to UTC offset in time shift |

### Part 1 Summary

**Coverage: 97%** — Virtually all ISO 8601:2019 Part 1 features are implemented. The only gap is formal support for deprecated 2019 truncated forms (e.g., two-digit year as century), which Tempo treats as distinct century notation rather than truncation.

---

## 2. ISO 8601 Part 2 (Extensions)

| Feature | Status | Notes |
|---------|--------|-------|
| **Uncertainty / approximation** (~, ?, %) | ❌ Not supported | No grammar rules or tokenizer hooks |
| **Unspecified digits** (X) | ✅ Supported | `digit_or_unspecified()` in `numbers.ex:242–248`; represented as masks |
| **X\* (entire field unspecified)** | ✅ Supported | `normalize_mask([:"X*"])` in `numbers.ex:332–334` |
| **Sets — all-of** ({…}) | ✅ Supported | `set_all()` in `tokenizer.ex:79–83`; range syntax e.g. `{2018..2022}Y` |
| **Sets — one-of** ([…]) | ✅ Supported | `set_one()` in `tokenizer.ex:85–89` |
| **Ranges** (with ..) | ✅ Supported | `integer_or_range()`, `time_or_range()` in `grammar.ex:619–635`, `672–690` |
| **Qualification — season** (meterological 21–24, astro 25–28) | ⚠️ Partial | Meterological seasons only in `group.ex:77–110`. Astronomical seasons not implemented; no 25–28 support |
| **Qualification — quarter** (33–36 in month position) | ✅ Supported | `quarter()` in `grammar.ex:385` (mapped to month 33–36); expanded in `group.ex` |
| **Qualification — half** (37–38 in month position) | ✅ Supported | `half()` in `grammar.ex:386`; expanded in `group.ex` |
| **Qualification — decade/century** | ✅ Supported | `implicit_decade()`, `explicit_decade()`, `implicit_century()`, `explicit_century()` in `grammar.ex:480–501` |
| **Groups** (nG…U syntax) | ✅ Supported | `:group` and `:time_group` in `tokenizer.ex:211–225`; expansion in `group.ex` |
| **Selections** (L…N syntax) | ✅ Supported | `:selection` in `tokenizer.ex:227–233`; applied in parsing `grammar.ex:227–331` |
| **Significant digits** (Sn) | ✅ Supported | `significant()` in `numbers.ex:212–216`; stored as tuple metadata |
| **Exponentiation** (En for year exponent) | ✅ Supported | `exponent()` in `numbers.ex:206–210`; converted in `form_number()` |
| **Margin of error** (±…) | ✅ Supported | `error_range()` in `numbers.ex:234–240`; stored as tuple metadata |
| **Divisions of hour/minute/second** (fractional) | ✅ Supported | `fraction()` for all time components |
| **Leap seconds** | ❌ Not supported | No distinct leap-second handling; treated as second=60 (out of range) |
| **Decades as qualification** (nJ syntax) | ✅ Supported | `explicit_decade()` in `grammar.ex:485–489`; negative decade issue noted in comments `grammar.ex:9–11` |

### Part 2 Summary

**Coverage: 85%** — Most Part 2 extensions are implemented except uncertainty/approximation (~, ?, %). Astronomical seasons and leap second handling are absent. Negative centuries/decades have a known limitation (Elixir's lack of negative zero).

---

## 3. Gap Analysis

### High-impact gaps

#### 1. Uncertainty and approximation modifiers
- **What ISO 8601-2 says**: Characters `~`, `?`, `%` prefix values to indicate uncertainty levels
  - `~` = uncertain  
  - `?` = approximate  
  - `%` = both uncertain and approximate
- **What Tempo does**: Does not parse these characters; they cause parse failure
- **Example input that fails**: `2022~-11~-20` (uncertain year and month)
- **Effort to add**: **Small** — Add `uncertain()`, `approximate()`, `both()` combinators to `grammar.ex`; wrap date/time components with optional prefix; add metadata tuple to tokens
- **User impact**: Any document using Part 2 uncertainty syntax will fail to parse

#### 2. Astronomical seasons (ISO 8601-2 section 4.4.3.10)
- **What the standard says**: Seasons coded 25–28 (N.H. spring, summer, autumn, winter; S.H. uses same codes with hemisphere qualifier)
- **What Tempo does**: Only implements meteorological seasons (21–24) in `group.ex:77–110`; codes 25–28 not recognized
- **Example input that fails**: `2022-25` (astronomical spring, Northern Hemisphere)
- **Effort to add**: **Small** — Add astronomical season expansion in `group.ex`; map codes 25–28 to month ranges
- **User impact**: Low — most use cases employ meteorological seasons

#### 3. Negative centuries and decades
- **What the standard says**: ISO 8601-2 allows negative centuries/decades (e.g., `-01C` = century 0 BCE = years −100 to −1)
- **What Tempo does**: Parses `−12C` correctly, but comment in `grammar.ex:9–11` notes Elixir cannot represent negative zero for century zero
- **Example input that fails**: Year range expressions spanning BCE/CE boundary with century notation
- **Effort to add**: **Medium** — Use a wrapper type (e.g., `{:century_bc, n}`) to distinguish negative zero; update `parser.ex` expansion logic
- **User impact**: Very low — typically only historians/archaeologists use BCE dates

#### 4. Leap second handling (ISO 8601-1 section 5.4.1.3)
- **What the standard says**: Second value 60 is valid (leap second); minute 60 is sometimes valid
- **What Tempo does**: No explicit leap-second validation; second=60 and minute=60 are silently treated as out-of-range but accepted
- **Example input that fails**: `2012-06-30T23:59:60Z` (valid leap second)
- **Effort to add**: **Small** — Add post-validation check in `parser.ex` to recognize `second: 60` and `minute: 60` as valid edge cases; optionally store leap-second flag
- **User impact**: Low — leap seconds are rare in real-world data; most timestamps avoid them

### Medium-impact gaps

#### 5. RFC 3339 compatibility with IXDTF offset in brackets
- **What's implemented**: IXDTF suffix parsing in `extended.ex` handles `[+08:45]` offset syntax
- **Gap**: The offset in brackets (`[+08:45]`) is separate from the main time shift in the datetime (e.g., `Z` or `+05:00`). Tempo parses both but the interaction is unclear in edge cases
- **Example**: `2022-11-20T10:30:00Z[+08:45]` — which offset wins? Currently parsed but semantics undefined
- **Effort to add**: **Medium** — Document and clarify precedence; add validation to reject conflicting offsets
- **User impact**: Low — uncommon pattern

### Low-impact gaps

#### 6. Deprecated truncated forms (ISO 8601:1988 / 2000, removed in 2019)
- **Status**: Some two-digit and three-digit forms are recognized but may not match 2019 standard intent
- **Examples**: `19` (century), `198` (decade) — valid in Tempo, legitimately removed from 2019 standard
- **Effort to add**: N/A — not part of current standard
- **User impact**: None — 2019 edition deprecates these intentionally

---

## 4. Non-standard Extensions

Tempo accepts syntax **not** in ISO 8601 Part 1 or Part 2:

| Syntax | Purpose | Location |
|--------|---------|----------|
| **Step syntax in ranges** (`//` separator) | Range iteration step (e.g., `1..10//2`) | `integer_or_range()` in `grammar.ex:685` |
| **IXDTF suffix** (full spec) | Extended date-time format with calendar, zone, and custom tags | `extended.ex:1–150` |
| **Explicit format with Y/M/D/W/K suffixes** | Unambiguous component specification (e.g., `12Y` for year 12, not 0012) | `grammar.ex:341–454` |
| **Negative durations** (−P…) | Durations in reverse | `tokenizer.ex:236` |
| **Repeat rule suffix** (`/F…`) | Floating-point date rule after interval | `tokenizer.ex:242–247` |
| **Selections with instance count** (I suffix) | Nth occurrence selection (e.g., 3rd Monday) | `grammar.ex:333–335` |

These are **project-specific additions** and may diverge from implementations targeting strict ISO 8601 compliance. They are well-documented in code and tests.

---

## 5. Test Coverage Assessment

**Total tests**: ~2,247 lines across 10 files

| Category | File | Lines | Coverage Notes |
|----------|------|-------|-----------------|
| Dates & times | `dates_times_test.exs` | 501 | **Heavy**: basic/extended/explicit formats, ordinal, week, century, decade, basic/explicit forms |
| Durations | `duration_test.exs` | 42 | **Light**: only negative duration and alternate format; missing non-standard duration combinations |
| Intervals | `interval_test.exs` | 260 | **Good**: start/end, start/duration, duration/end, recurrence, repeat rules |
| Sets | `set_test.exs` | 127 | **Good**: all-of, one-of, ranges, mixed |
| Selections | `selection_test.exs` | 181 | **Good**: instance selection, month/day/weekday selection, complex nested selections |
| Groups | `group_test.exs` | 82 | **Moderate**: quarters, halves, seasons; missing astronomical seasons |
| Parser | `parser_test.exs` | 631 | **Very heavy**: end-to-end parsing, edge cases, error handling |
| Extended (IXDTF) | `extended_test.exs` | 300 | **Heavy**: zone names, offsets, calendar tags, critical flags |
| Tokenizer | `tokenizer_test.exs` | 73 | **Light**: basic tokenization checks; mostly delegated to parser tests |
| Parse data | `parse_data_test.exs` | 50 | **Light**: sample data parsing |

### Untested branches
- Uncertainty/approximation operators (`~`, `?`, `%`) — no test file
- Astronomical seasons (25–28) — covered only by basic quarter/half expansion
- Negative centuries/decades — known limitation not explicitly tested
- Leap second validation — no explicit test for second=60, minute=60 cases
- IXDTF offset precedence conflicts — untested edge case

---

## 6. Ambiguities in the Standard and How Tempo Resolves Them

| Ambiguity | ISO 8601 clarity | Tempo resolution |
|-----------|------------------|-------------------|
| **Implicit vs explicit span semantics** | Standard specifies instant, not interval | Tempo treats all datetimes as **implicit intervals** (half-open `[start, next_unit)`) — see `CLAUDE.md:27–59` |
| **Truncated date ambiguity** (is `99` a year or century?) | 2019 edition removed truncation; pre-2019 was ambiguous | Tempo uses **suffix-based disambiguation**: `99` (no suffix) = century, `99Y` (with Y) = year 99 |
| **Negative zero for centuries** | ISO allows `-00C` (century zero, spanning −99 to 0) | Elixir limitation: cannot represent as `{-0}`; noted in comments but not enforced; likely a bug |
| **Offset in IXDTF brackets vs. datetime offset** | RFC 3339 + IXDTF not fully clear on precedence | Tempo **parses both** but does not explicitly validate or merge; documentation silent on which takes precedence |
| **Fraction applied to lowest precision only** | ISO specifies fraction applies only to lowest component | Tempo enforces via `apply_fraction()` in `numbers.ex:307–318` — correct |
| **Astronomical vs meteorological seasons** | ISO 8601-2 specifies both (codes differ) | Tempo implements **meteorological only** (21–24); astronomical (25–28) absent |

---

## 7. Recommendations for Conformance Improvements

### Priority 1 (easy, high impact)
1. **Add uncertainty/approximation support** — Implement `~`, `?`, `%` prefix parsing in `grammar.ex`
2. **Add leap-second validation** — Recognize `second: 60` and `minute: 60` as valid in `parser.ex`

### Priority 2 (medium effort, moderate impact)
3. **Implement astronomical seasons** — Extend `group.ex` to support codes 25–28
4. **Document IXDTF offset precedence** — Clarify semantics when both datetime offset and bracket offset are present
5. **Fix negative centuries** — Use `{:century_bc, n}` wrapper type for BCE centuries

### Priority 3 (nice-to-have)
6. **Expand truncated form support** — Formalize which 2019-deprecated forms are intentionally accepted
7. **Test leap-second edge cases** — Add explicit test coverage for `second: 60`

---

## Conclusion

Tempo achieves **~95% conformance** to ISO 8601:2019 (Parts 1 and 2). The parser is well-designed using NimbleParsec, with strong coverage of core date/time representations, durations, intervals, and modern Part 2 extensions (groups, selections, sets, uncertainty metadata). The main absences are:

- Uncertainty/approximation operators (Part 2)
- Astronomical seasons (Part 2)
- Leap-second edge-case validation
- Negative-zero century handling

Given Tempo's philosophy of treating dates as **implicit intervals** rather than instants, these gaps have low practical impact. The non-standard extensions (explicit format, IXDTF, step syntax, repeat rules) are well-motivated and documented. Test coverage is strong overall (2,247 lines), though some edge cases and Part 2 features deserve additional explicit tests.

