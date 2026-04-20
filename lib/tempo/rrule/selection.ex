defmodule Tempo.RRule.Selection do
  @moduledoc """
  Resolve RRULE `BY*` selection tokens during recurrence expansion.

  Called from `Tempo.to_interval/2`'s recurrence loop. Given a
  candidate occurrence and a `repeat_rule` whose `:time` carries
  a `[{:selection, [...]}]` keyword list (the shared AST produced
  by `Tempo.RRule.parse/2` and `Tempo.RRule.Expander.to_ast/3`),
  decide whether the candidate is kept, dropped, or expanded into
  multiple occurrences.

  ## Phase B — scope

  The full RFC 5545 §3.3.10 `BY*` table pairs each rule with its
  `FREQ` to decide whether it acts as a **LIMIT** (filter) or an
  **EXPAND** (grow the candidate set). This module lands the table
  one sub-rule at a time:

  * `BYMONTH` — always a LIMIT (implemented).

  * `BYMONTHDAY`, `BYYEARDAY`, `BYWEEKNO` — LIMIT (not yet).

  * `BYDAY` — LIMIT when `FREQ` is day-or-finer; EXPAND when
    `FREQ` is `:month` or `:year` (not yet).

  * `BYHOUR` / `BYMINUTE` / `BYSECOND` — EXPAND when `FREQ` is
    coarser than the unit; LIMIT otherwise (not yet).

  * `BYSETPOS` — applied **after** all other `BY*` rules, so it
    lives in its own pass (not yet).

  Each unimplemented sub-rule currently passes through unchanged
  — the candidate is emitted as-is. That keeps Phase A's simple
  `FREQ/INTERVAL/COUNT/UNTIL` pipeline intact while we add
  sub-rules incrementally.

  """

  alias Tempo.Interval

  @doc """
  Apply a `repeat_rule` to one candidate occurrence and return the
  resulting list of occurrences (zero for a LIMIT rejection, one
  for passthrough, more once EXPAND rules land).

  ### Arguments

  * `candidate` is a `t:Tempo.Interval.t/0` — the current
    occurrence under consideration.

  * `repeat_rule` is either `nil` (no rule — passthrough) or a
    `%Tempo{}` whose `:time` holds `[selection: [...]]`.

  * `freq` is the enclosing `FREQ` atom (`:second`, `:minute`,
    `:hour`, `:day`, `:week`, `:month`, `:year`). Drives the
    EXPAND-vs-LIMIT dispatch for sub-rules that care.

  ### Returns

  * A list of `t:Tempo.Interval.t/0` occurrences — `[]` (LIMIT
    rejected), `[candidate]` (passthrough or LIMIT accepted),
    or `[c1, c2, …]` (EXPAND, future phases).

  ### Examples

      iex> candidate = %Tempo.Interval{from: ~o"2022-06-15", to: ~o"2022-06-16"}
      iex> rule = %Tempo{time: [selection: [month: 6]], calendar: Calendrical.Gregorian}
      iex> Tempo.RRule.Selection.apply(candidate, rule, :month)
      [candidate]

      iex> candidate = %Tempo.Interval{from: ~o"2022-07-15", to: ~o"2022-07-16"}
      iex> rule = %Tempo{time: [selection: [month: 6]], calendar: Calendrical.Gregorian}
      iex> Tempo.RRule.Selection.apply(candidate, rule, :month)
      []

  """
  @spec apply(Interval.t(), Tempo.t() | nil, atom()) :: [Interval.t()]
  def apply(candidate, repeat_rule, freq)

  def apply(%Interval{} = candidate, nil, _freq), do: [candidate]

  def apply(%Interval{} = candidate, %Tempo{time: [selection: selection]}, freq) do
    apply_selection(candidate, selection, freq)
  end

  # No selection shape we recognise — pass through rather than
  # crash. Future phases replace this catch-all with a specific
  # error once every shape is accounted for.
  def apply(%Interval{} = candidate, _, _freq), do: [candidate]

  ## ------------------------------------------------------------
  ## Selection dispatch — one sub-rule at a time
  ## ------------------------------------------------------------

  # Walk the selection keyword list, applying each sub-rule in
  # RFC 5545 order: BYMONTH → BYWEEKNO → BYYEARDAY → BYMONTHDAY →
  # BYDAY → BYHOUR → BYMINUTE → BYSECOND, then BYSETPOS. Each
  # sub-rule reduces or grows the working set of candidates.
  # `freq` is reserved for the dispatch logic landing in later
  # B-phases (BYDAY's EXPAND/LIMIT switch, BYHOUR/MINUTE/SECOND).
  defp apply_selection(candidate, selection, _freq) do
    Enum.reduce(selection, [candidate], fn
      {:month, months}, candidates ->
        limit_by_month(candidates, months)

      # Every other selection token is currently a passthrough.
      # Phase B.3+ replace each clause with a real filter/expand.
      _entry, candidates ->
        candidates
    end)
  end

  ## ------------------------------------------------------------
  ## BYMONTH — always a LIMIT, regardless of FREQ
  ## ------------------------------------------------------------

  # Keep every candidate whose `from`'s month is in the requested
  # list. Per RFC 5545, the single-integer form (`BYMONTH=6`) is a
  # degenerate list of length 1.
  defp limit_by_month(candidates, month) when is_integer(month) do
    limit_by_month(candidates, [month])
  end

  defp limit_by_month(candidates, months) when is_list(months) do
    Enum.filter(candidates, fn %Interval{from: %Tempo{time: time}} ->
      case Keyword.get(time, :month) do
        nil -> false
        m when is_integer(m) -> m in months
      end
    end)
  end
end
