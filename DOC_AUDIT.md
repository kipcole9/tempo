# Documentation Struct-Access Audit

User-facing code (guides, README, livebook, module docs, cookbook) should never construct or pattern-match on Tempo struct fields directly. This audit inventories every violation found and proposes a remediation for each — either a pure prose/API rewrite, or a new public function where one is missing.

## Summary of fixes needed

| Surface | Count | Kind |
|---|---|---|
| Construction (`%Tempo.Interval{from:, to:}`) | 18 sites | Replace with `Tempo.Interval.new!/1` or an `~o"from/to"` sigil |
| Construction (`%Tempo{time: [...]}`) | 3 sites | Replace with `Tempo.new!/1` + keyword components |
| Construction (`%Tempo.IntervalSet{intervals: [...]}`) | 2 sites | Replace with `Tempo.IntervalSet.new!/1` |
| Pattern match on Interval | 2 sites | Replace with `Tempo.Interval.endpoints/1`, `from/1`, `to/1` |
| Field access `iv.from.time[:month]` | 1 site | Use `Tempo.month/1`, `Tempo.day/1`, … (already exist) |
| Field access `iv.metadata.summary` | 1 site | **Needs new API** — `Tempo.Interval.metadata/1` |

Net new public API required: **one function** (`Tempo.Interval.metadata/1`). Everything else is already reachable through existing `Tempo.new!/1`, `Tempo.Interval.new!/1`, `Tempo.IntervalSet.new!/1`, `endpoints/1`, `from/1`, `to/1`, and the component accessors added in v0.2.0.

## 1. Construction sites — `%Tempo.Interval{from:, to:}`

### guides/holidays.md

| Line | Current | Remediation |
|---|---|---|
| 58 | `q3 = %Tempo.Interval{from: ~o"2026-07-01", to: ~o"2026-10-01"}` | `q3 = ~o"2026-07-01/2026-10-01"` (the guide itself shows this as an alternative on line 77) |
| 73 | Prose: "The `%Tempo.Interval{from:, to:}` form above is the most explicit." | Rewrite prose: "The `Tempo.Interval.new!/1` form above is the most explicit." |
| 118 | `window = %Tempo.Interval{from: today, to: Tempo.shift(today, week: 3)}` | `window = Tempo.Interval.new!(from: today, to: Tempo.shift(today, week: 3))` |

### guides/workdays-and-weekends.md

| Line | Current | Remediation |
|---|---|---|
| 11 | Prose: "`%Tempo.Interval{from:, to:}` construct a bounded span" | Rewrite prose to mention `Tempo.Interval.new!/1` |
| 27 | `window = %Tempo.Interval{from: today, to: window_end}` | `window = Tempo.Interval.new!(from: today, to: window_end)` |
| 71 | `window = %Tempo.Interval{from: tomorrow, to: Tempo.shift(today, week: 2)}` | `window = Tempo.Interval.new!(from: tomorrow, to: Tempo.shift(today, week: 2))` |
| 87 | `window = %Tempo.Interval{from: ~o"2026-06-15", to: ~o"2026-06-29"}` | `window = ~o"2026-06-15/2026-06-29"` |
| 187 | `window = %Tempo.Interval{from: from, to: window_end}` | `window = Tempo.Interval.new!(from: from, to: window_end)` |
| 209 | `window = %Tempo.Interval{from: from, to: to}` | `window = Tempo.Interval.new!(from: from, to: to)` |

### guides/cookbook.md

| Line | Current | Remediation |
|---|---|---|
| 189 | `a = %Tempo.Interval{from: ~o"2026-06-01", to: ~o"2026-06-10"}` | `a = ~o"2026-06-01/2026-06-10"` |
| 190 | `b = %Tempo.Interval{from: ~o"2026-06-05", to: ~o"2026-06-15"}` | `b = ~o"2026-06-05/2026-06-15"` |
| 212 | `candidate = %Tempo.Interval{from: ~o"2026-06-15T10", to: ~o"2026-06-15T11"}` | `candidate = ~o"2026-06-15T10/2026-06-15T11"` |
| 213 | `window = %Tempo.Interval{from: ~o"2026-06-15T09", to: ~o"2026-06-15T17"}` | `window = ~o"2026-06-15T09/2026-06-15T17"` |
| 223 | `iv = %Tempo.Interval{from: ~o"2026-06-15T09", to: ~o"2026-06-15T11"}` | `iv = ~o"2026-06-15T09/2026-06-15T11"` |
| 235 | `iv = %Tempo.Interval{from: ~o"2026-06-15T09", to: ~o"2026-06-15T10"}` | `iv = ~o"2026-06-15T09/2026-06-15T10"` |
| 799 | `iv = %Tempo.Interval{from: ~o"2016-12-31T23:59:00Z", to: ~o"2017-01-01T00:01:00Z"}` | `iv = ~o"2016-12-31T23:59:00Z/2017-01-01T00:01:00Z"` |

### guides/scheduling.md

| Line | Current | Remediation |
|---|---|---|
| 181 | `bound = %Tempo.Interval{from: from, to: to}` | `bound = Tempo.Interval.new!(from: from, to: to)` |

### guides/enumeration-semantics.md

| Line | Current | Remediation |
|---|---|---|
| 11 | `Enum.take(%Tempo.Interval{from: ~o"1985Y", to: :undefined}, 3)` | `Enum.take(Tempo.Interval.new!(from: ~o"1985Y", to: :undefined), 3)` |

### guides/falsehoods.md

| Line | Current | Remediation |
|---|---|---|
| 23 | `iv = %Tempo.Interval{from: Tempo.from_iso8601!(...), to: Tempo.from_iso8601!(...)}` | `iv = Tempo.Interval.new!(from: Tempo.from_iso8601!(...), to: Tempo.from_iso8601!(...))` |
| 100 | `iv = %Tempo.Interval{from: ~o"2016-12-31T23:59:00Z", to: ~o"2017-01-01T00:01:00Z"}` | `iv = ~o"2016-12-31T23:59:00Z/2017-01-01T00:01:00Z"` |

### livebook/tempo_tour.livemd

| Line | Current | Remediation |
|---|---|---|
| 374 | `a = %Tempo.Interval{from: ~o"2026-06-01", to: ~o"2026-06-10"}` | `a = ~o"2026-06-01/2026-06-10"` |
| 375 | `b = %Tempo.Interval{from: ~o"2026-06-05", to: ~o"2026-06-15"}` | `b = ~o"2026-06-05/2026-06-15"` |
| 387 | `window = %Tempo.Interval{from: ~o"2026-06-15T09", to: ~o"2026-06-15T17"}` | `window = ~o"2026-06-15T09/2026-06-15T17"` |
| 388 | `candidate = %Tempo.Interval{from: ~o"2026-06-15T10", to: ~o"2026-06-15T11"}` | `candidate = ~o"2026-06-15T10/2026-06-15T11"` |
| 398 | `iv = %Tempo.Interval{from: ~o"2026-06-15T09", to: ~o"2026-06-15T10"}` | `iv = ~o"2026-06-15T09/2026-06-15T10"` |

## 2. Construction sites — `%Tempo{time: [...]}`

### guides/workdays-and-weekends.md

| Line | Current | Remediation |
|---|---|---|
| 136 | `Tempo.select(window, %Tempo{time: [day_of_week: [1, 2, 3, 4, 5]]})` | `Tempo.select(window, Tempo.new!(day_of_week: [1, 2, 3, 4, 5]))` — **needs verification**: `Tempo.new/1` currently expects integer components, not lists. This may require a small API extension to accept a list-of-integers per axis to round-trip the selector form, OR rewrite the example as `Tempo.select(window, Tempo.workdays(territory))` and drop the manual-selector demo entirely. |

### guides/cookbook.md

| Line | Current | Remediation |
|---|---|---|
| 570 | `hebrew = %Tempo{time: [year: 5786, month: 10, day: 30], calendar: Calendrical.Hebrew}` | `hebrew = Tempo.new!(year: 5786, month: 10, day: 30, calendar: Calendrical.Hebrew)` |

### guides/set-operations.md

| Line | Current | Remediation |
|---|---|---|
| 60 | `hebrew_day = %Tempo{time: [year: 5782, month: 10, day: 16], calendar: Calendrical.Hebrew}` | `hebrew_day = Tempo.new!(year: 5782, month: 10, day: 16, calendar: Calendrical.Hebrew)` |

## 3. Construction sites — `%Tempo.IntervalSet{intervals: [...]}`

### livebook/tempo_tour.livemd

| Line | Current | Remediation |
|---|---|---|
| 415-420 | `alice = %Tempo.IntervalSet{intervals: [%Tempo.Interval{…metadata: %{who: "Alice"}}, …]}` | Build each interval with `Tempo.Interval.new!(from: …, to: …, metadata: %{who: "Alice"})`, then `Tempo.IntervalSet.new!([a1, a2])` |
| 422-427 | Same shape for Bob | Same remediation |

## 4. Pattern-match sites

### guides/cookbook.md

| Line | Current | Remediation |
|---|---|---|
| 108 | `{:ok, %Tempo.Interval{from: from, to: to}} = Tempo.to_interval(~o"2026-06")` | `{:ok, iv} = Tempo.to_interval(~o"2026-06")`<br>`{from, to} = Tempo.Interval.endpoints(iv)` |

### README.md

| Line | Current | Remediation |
|---|---|---|
| 43 | `{:ok, %Tempo.Interval{from: from, to: to}} = Tempo.to_interval(~o"2026-06-15")` | Same as above — use `Tempo.Interval.endpoints/1` |

## 5. Field-access sites

### guides/holidays.md

| Line | Current | Remediation |
|---|---|---|
| 101 | `IO.puts "#{iv.from.time[:month]}/#{iv.from.time[:day]}: #{iv.metadata.summary}"` | `IO.puts "#{Tempo.month(iv)}/#{Tempo.day(iv)}: #{Tempo.Interval.metadata(iv).summary}"` — **needs new `Tempo.Interval.metadata/1`** accessor (trivial) |

### guides/enumeration-semantics.md

| Line | Current | Remediation |
|---|---|---|
| 156 | Prose: "`%Tempo.IntervalSet{intervals: [%Tempo.Interval{}, ...]}` holds a sorted list of member intervals." | Leave as-is — this is describing the internal shape in a reference document, not user code. Classification: **referential, no change needed**. |

## 6. Referential-only mentions (no remediation)

All other occurrences of `%Tempo.X{}` in the audit sweep are prose/table references describing the type, not user code that constructs or matches. These do not need remediation:

* All `Stored on %Tempo{}` table headers in ISO 8601 conformance docs.
* All `%Tempo.Interval{}` mentions in shared-ast-iso8601-and-rrule.md (architecture reference).
* All `%Tempo.Duration{}` and `%Tempo.Set{}` type-shape mentions in reference tables.
* The `#=> %Tempo.Interval{from: ~o"…", ...}` style comment-showing-inspect-output lines. These render the default `Inspect` output; they're illustrative of what the REPL prints, not code the reader writes.

## 7. Proposed API addition

**`Tempo.Interval.metadata/1`** — return the `:metadata` map of an interval. Mirrors `from/1`, `to/1`, `endpoints/1`, `resolution/1` added in v0.2.0. One-liner:

```elixir
@doc """
Return the metadata map attached to an interval.

### Arguments

* `interval` — a `t:Tempo.Interval.t/0`.

### Returns

* The `:metadata` map. Empty `%{}` when no metadata was attached.

### Examples

    iex> iv = Tempo.Interval.new!(
    ...>   from: ~o"2026-06-15T09",
    ...>   to:   ~o"2026-06-15T10",
    ...>   metadata: %{summary: "Stand-up"}
    ...> )
    iex> Tempo.Interval.metadata(iv)
    %{summary: "Stand-up"}

"""
@spec metadata(t()) :: map()
def metadata(%__MODULE__{metadata: m}), do: m
```

This is the only net-new public function the audit uncovers.

## 8. Execution plan

1. Land `Tempo.Interval.metadata/1`.
2. Sweep and rewrite the 18 Interval-construction sites — prefer the `~o"from/to"` sigil where both endpoints are literal ISO strings; use `Tempo.Interval.new!/1` when either endpoint is a binding.
3. Rewrite the 3 `%Tempo{time: ...}` construction sites to `Tempo.new!/1` (with a short digression on the `day_of_week: [1,...,5]` selector shape — may need a separate decision about whether `Tempo.new/1` should accept list-valued axes, or whether the example should pivot to `Tempo.workdays/1`).
4. Rewrite the 2 livebook IntervalSet constructions to `Tempo.IntervalSet.new!/1`.
5. Rewrite the 2 pattern-match sites in cookbook and README to use `Tempo.Interval.endpoints/1`.
6. Rewrite the 1 field-access site in holidays.md to use the component accessors and the new `metadata/1`.
7. Regenerate `mix docs` and skim for any remaining struct-literal patterns the grep missed.
