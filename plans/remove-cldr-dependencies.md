# Plan: remove all CLDR-family dependencies

## Context

Tempo currently pulls in `ex_cldr_calendars` as a direct dep, which transitively brings `ex_cldr`, `cldr_utils`, `ex_cldr_numbers`, and `ex_cldr_currencies`. Code, tests and docs reference `Cldr.*` modules in 14 files.

Policy: **no CLDR-family libraries anywhere in the codebase**. Calendar/calendrical functionality must go through `Calendrical` (a drop-in replacement hex package for `ex_cldr_calendars`). Numeric helpers go through `Localize.Utils.Math` and `Localize.Utils.Digits`.

## Module mapping

Verified against the Calendrical source (`/tmp/calendrical` clone) and the Localize source (`../localize/localize`):

| Before | After |
|---|---|
| `ex_cldr_calendars` dep | `calendrical` dep |
| `Cldr.Calendar.Gregorian` | `Calendrical.Gregorian` |
| `Cldr.Calendar.ISOWeek` | `Calendrical.ISOWeek` |
| `Cldr.Calendar.date_from_day_of_year/3` | `Calendrical.date_from_day_of_year/3` |
| `Cldr.Calendar.date_to_iso_days/1` | `Calendrical.date_to_iso_days/1` |
| `Cldr.Calendar.date_from_iso_days/2` | `Calendrical.date_from_iso_days/2` |
| `Cldr.Calendar.sunday/0` | `Calendrical.sunday/0` |
| `Cldr.Calendar.Kday.kday_after/2` | `Calendrical.Kday.kday_after/2` (verify location) |
| `Cldr.Math.round/2` | `Localize.Utils.Math.round/2` |
| `Cldr.Digits.number_of_integer_digits/1` | `Localize.Utils.Digits.number_of_integer_digits/1` |
| `Cldr.known_calendars/0` | (removed — only used internally, replace with a local list if needed) |
| `Cldr.validate_calendar/1` | Keep using `Localize.validate_calendar/1` in IXDTF parser (already migrated) |

Calendar-module methods (`calendar.days_in_month(year, month)`, `calendar.months_in_year(year)`, `calendar.weeks_in_year(year)`, `calendar.days_in_week/0`, `calendar.calendar_base/0`) are called via the calendar module atom and will work unchanged as long as the calendar module is `Calendrical.Gregorian` rather than `Cldr.Calendar.Gregorian`.

## Scope of changes

**`lib/` — 31 references across 9 files:**

* `lib/tempo.ex` — 7 refs (default `Cldr.Calendar.Gregorian`, moduledoc, `from_date` pattern match)
* `lib/validation.ex` — 9 refs (default calendar, `Cldr.Calendar.date_from_day_of_year`, 6× `Cldr.Math.round`, `Cldr.Calendar.date_to_iso_days`)
* `lib/tempo/range.ex`, `lib/tempo/set.ex` — defaults
* `lib/sigil.ex`, `lib/inspect.ex` — default calendar matching and Gregorian/ISOWeek branches
* `lib/iso8601/tokenizer/numbers.ex` — 2× `Cldr.Digits.number_of_integer_digits`
* `lib/iso8601/group.ex` — 1 default
* `lib/event/easter.ex` — 4 refs (date conversions, Kday, sunday)

**`test/` — 121 references across 5 files:**

* `test/tempo/iso8601/parser_test.exs` — bulk of references (expected `calendar: Cldr.Calendar.Gregorian` in struct assertions)
* `test/tempo/iso8601/selection_test.exs`
* `test/tempo/enumeration_test.exs`
* `test/tempo/inspect_test.exs`
* `test/tempo_test.exs`

**`mix.exs`:**

* Remove `{:ex_cldr_calendars, "~> 1.23"}`
* Add `{:calendrical, "~> 0.2"}` (version to match latest on hex)
* Add `:calendrical` to `extra_applications` if required

## Step-by-step

### Step 1 — update `mix.exs` and fetch deps (10 min)

```elixir
defp deps do
  [
    {:nimble_parsec, "~> 1.0"},
    {:calendrical, "~> 0.2"},
    {:astro, "~> 0.10"},
    {:localize, path: "../localize/localize"},
    {:tzdata, "~> 1.1"},
    {:ex_doc, "~> 0.21", runtime: false},
    {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
  ]
end
```

Remove `ex_cldr_*` from `extra_applications`. Run `mix deps.get`.

Expected: mix.lock updates; `ex_cldr`, `ex_cldr_calendars`, `ex_cldr_numbers`, `ex_cldr_currencies`, `cldr_utils`, `digital_token`, `jason` (if only pulled by CLDR) are removed from the dep tree.

### Step 2 — library code (lib/) replacements (1–2 hours)

Mechanical find-and-replace across the 9 lib files, using the mapping table above. Key patterns:

* **Default calendar argument**: every `calendar \\ Cldr.Calendar.Gregorian` becomes `calendar \\ Calendrical.Gregorian`. One replace per file, 7 files total.

* **Pattern matches**: `calendar: Cldr.Calendar.Gregorian` in `from_date` (tempo.ex) and `from_naive_date_time` becomes `calendar: Calendrical.Gregorian`. Also `%Tempo{calendar: Cldr.Calendar.Gregorian}` and `%Tempo{calendar: Cldr.Calendar.ISOWeek}` pattern-matches in `inspect.ex` and `sigil.ex`.

* **Function calls**: `Cldr.Math.round` → `Localize.Utils.Math.round`, `Cldr.Digits.number_of_integer_digits` → `Localize.Utils.Digits.number_of_integer_digits`, `Cldr.Calendar.date_from_day_of_year` → `Calendrical.date_from_day_of_year`, etc.

* **`Cldr.Calendar.Kday.kday_after/2`**: verify Calendrical location — likely `Calendrical.Kday.kday_after/2` per the source clone. Adjust if the module is instead `Calendrical.Gregorian.Kday` or similar.

* **Moduledocs/@doc text**: mention of `Cldr.Calendar.Gregorian` in prose is updated to `Calendrical.Gregorian`.

### Step 3 — test suite (1–2 hours)

121 references in 5 test files. These are overwhelmingly assertions like:

```elixir
assert Tempo.from_iso8601("2018-08-01") ==
         {:ok, %Tempo{time: [year: 2018, month: 8, day: 1], shift: nil,
                      calendar: Cldr.Calendar.Gregorian}}
```

Replace `Cldr.Calendar.Gregorian` with `Calendrical.Gregorian` and `Cldr.Calendar.ISOWeek` with `Calendrical.ISOWeek` throughout.

Use `Edit` with `replace_all: true` per-file. Run each test file after its rewrite as a quick sanity check.

### Step 4 — compile check and warnings-as-errors (15 min)

```bash
mix clean && mix compile --warnings-as-errors
```

Expected: clean build. Any lingering `Cldr.*` reference will fail compile — fix as it appears.

### Step 5 — full test run (15 min)

```bash
mix test
```

Expected: 1592 tests, 0 failures. Any numeric/rounding discrepancy from `Localize.Utils.Math.round` vs `Cldr.Math.round` will surface here. The two should be functionally identical (both are banker's-rounding wrappers around `:math.pow` and `Float.round`), but verify.

### Step 6 — dialyzer (5 min)

```bash
mix dialyzer
```

Expected: clean. Watch for unused-module or invalid-module warnings if any `Cldr.*` reference was missed.

### Step 7 — update docs (15 min)

* `CHANGELOG.md` — add a v0.2.0 entry: "Removed all CLDR-family dependencies; calendar operations now go through `Calendrical` and numeric helpers through `Localize.Utils`."
* `CLAUDE.md` — no change required (already generic about calendars).
* `README.md` — check for any `Cldr.Calendar.Gregorian` in code examples; replace.
* `guides/iso8601-conformance.md` — the "Unspecified `X` digits" and "Calendar (`u-ca=`) validation" rows mention Localize; update the default-calendar example.

### Step 8 — verify no residual references (5 min)

```bash
grep -rn "Cldr\|ex_cldr" lib/ test/ mix.exs mix.lock README.md CHANGELOG.md guides/ plans/
```

Expected output: **empty**. If any reference remains, fix or document why.

## Risks

1. **Calendrical API gap.** If any `Cldr.*` function used by Tempo has no equivalent in Calendrical, we have to either reimplement it locally or drop the feature. I verified the headline ones (see mapping table) but haven't spot-checked every call site. Risk: small to medium. Mitigation: Step 4 (compile) and Step 5 (tests) will surface any gap immediately.

2. **Numeric rounding semantics drift.** `Cldr.Math.round/2` vs `Localize.Utils.Math.round/2` — both are thin wrappers but if they disagree on half-even vs half-up at the fifth-decimal edge we'll get test failures in the fractional-time resolution tests. Risk: low. Mitigation: fractional-time tests in `test/tempo/iso8601/*.exs` will catch it.

3. **Week-based calendar (`ISOWeek`).** `Calendrical.ISOWeek` exists at `lib/calendrical.ex:651` but I haven't verified it implements the same interface as `Cldr.Calendar.ISOWeek`. Risk: low-medium. Mitigation: the handful of tests that exercise week dates will catch an incompatibility.

4. **Transitive deps.** Removing `ex_cldr_calendars` may also remove `decimal` or `digital_token` if nothing else in the tree needs them. `astro` might pull one of them in. Risk: low. Mitigation: `mix deps.tree` after Step 1.

5. **Test count drift.** Rewrite of 121 test assertions is mechanical but high-volume. Any typo produces a cryptic pattern-match failure. Risk: low. Mitigation: per-file test runs during Step 3.

## Estimated effort

**3–4 hours** total, dominated by the test file sweep. No architectural changes, no new features, no design decisions pending user input beyond confirmation of this plan.

## Non-goals

* **Changing the internal representation of the `:calendar` field.** It remains a module atom (e.g. `Calendrical.Gregorian`).
* **Introducing atom-named calendars** (`:gregorian`). That would be a deeper refactor affecting every pattern match on `calendar:`.
* **Removing `Localize` or `Tzdata`.** Those stay; only CLDR-family libraries are removed.

## Open questions / check before starting

1. **Calendrical version on hex** — latest at time of writing appears to be 0.2.0 per the HexDocs title. Confirm the version constraint before `mix deps.get`.

2. **`Calendrical.Kday` path** — need to verify the exact module path for `kday_after` used in `lib/event/easter.ex`. A grep of Calendrical source suggests it's under a kday module; I'll confirm during Step 2.

3. **Any other CLDR fallthrough?** — the Localize package itself uses CLDR data internally (via the `localize/data` directory), but that's an implementation detail of Localize, not a direct Tempo dependency. Confirm this is acceptable under the "no CLDR-related libraries" policy, or whether we need to treat Localize as suspect too.

Once these three questions are answered, the plan can execute in a single focused session.
