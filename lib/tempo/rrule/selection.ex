defmodule Tempo.RRule.Selection do
  @moduledoc """
  Resolve RRULE `BY*` selection tokens during recurrence expansion.

  Called from `Tempo.to_interval/2`'s recurrence loop. Given a
  candidate occurrence and a `repeat_rule` whose `:time` carries
  a `[{:selection, [...]}]` keyword list (the shared AST produced
  by `Tempo.RRule.parse/2` and `Tempo.RRule.Expander.to_ast/3`),
  decide whether the candidate is kept, dropped, or expanded into
  multiple occurrences.

  ## Implemented rules

  Per RFC 5545 §3.3.10's EXPAND/LIMIT table:

  | Part         | Role and when                                     |
  | ------------ | ------------------------------------------------- |
  | `BYMONTH`    | LIMIT — always.                                   |
  | `BYMONTHDAY` | LIMIT — any FREQ except WEEKLY (forbidden).       |
  | `BYYEARDAY`  | LIMIT — any FREQ coarser than DAILY.              |
  | `BYWEEKNO`   | LIMIT — `YEARLY` only.                            |
  | `BYDAY` (no ordinal) | LIMIT for DAILY/HOURLY/MINUTELY/SECONDLY; |
  |              | EXPAND within the enclosing week/month/year for   |
  |              | WEEKLY, MONTHLY, YEARLY.                          |
  | `BYDAY` (with ordinal) | EXPAND — pairs `(ordinal, weekday)` like  |
  |              | `1MO` and `-1FR` pick the Nth / Nth-from-last     |
  |              | matching weekday within the enclosing period      |
  |              | (month for MONTHLY, year for YEARLY). Backed by   |
  |              | `Calendrical.Kday.nth_kday/3`.                    |
  | `BYHOUR`     | EXPAND when FREQ is coarser than hour; LIMIT      |
  |              | when FREQ is hour-or-finer.                       |
  | `BYMINUTE`   | Same pattern at the minute unit.                  |
  | `BYSECOND`   | Same pattern at the second unit.                  |
  | `BYSETPOS`   | LIMIT — applied last, across the post-filter      |
  |              | per-period candidate set. Negative values count   |
  |              | from the end (`-1` = last).                       |

  Tokens this module doesn't interpret pass through unchanged
  so partial support is correct for the partial inputs.

  """

  alias Tempo.Interval

  @doc """
  Apply a `repeat_rule` to one candidate occurrence and return the
  resulting list of occurrences.

  ### Arguments

  * `candidate` is a `t:Tempo.Interval.t/0` — the current
    occurrence under consideration.

  * `repeat_rule` is either `nil` (no rule — passthrough) or a
    `%Tempo{}` whose `:time` holds `[selection: [...]]`.

  * `freq` is the enclosing `FREQ` atom (`:second`, `:minute`,
    `:hour`, `:day`, `:week`, `:month`, `:year`). Drives the
    EXPAND-vs-LIMIT dispatch for rules whose role depends on
    the enclosing frequency.

  ### Returns

  * A list of `t:Tempo.Interval.t/0` occurrences — `[]` on LIMIT
    rejection, `[candidate]` on passthrough or LIMIT accept,
    `[c1, c2, …]` on EXPAND.

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
  ## Selection dispatch
  ## ------------------------------------------------------------

  # RFC 5545 §3.3.10 prescribes a strict application order for
  # BY-rules: BYMONTH → BYWEEKNO → BYYEARDAY → BYMONTHDAY →
  # BYDAY → BYHOUR → BYMINUTE → BYSECOND → BYSETPOS. BYSETPOS
  # is *always* last, regardless of where it sits in the input
  # AST. We sort the selection at apply time so the resolver is
  # robust to whatever order the parser/adapter emitted.
  #
  # Context fields computed once per-selection:
  #
  # * `byday_scope` — for BYDAY with ordinals. Depends on FREQ
  #   and the presence of BYMONTH elsewhere in the selection.
  #   RFC 5545 §3.3.10: "if a BYDAY rule with an ordinal is
  #   used in a YEARLY recurrence that includes a BYMONTH rule
  #   part, then BYDAY is treated as a monthly-scoped filter
  #   within each month specified by BYMONTH."
  #
  # * `wkst` — week-start day (1..7, Monday=1). Affects BYDAY
  #   expansion under FREQ=WEEKLY (which week the candidate
  #   belongs to) and is the source of truth for downstream
  #   week-boundary calculations. Default Monday (1).
  defp apply_selection(candidate, selection, freq) do
    scope = byday_scope(freq, selection)
    wkst = Keyword.get(selection, :wkst, 1)

    selection
    |> Enum.sort_by(&application_order_key/1)
    |> Enum.reduce([candidate], fn entry, candidates ->
      apply_entry(entry, candidates, freq, scope, wkst)
    end)
  end

  @application_order [
    :wkst,
    :month,
    :week,
    :day_of_year,
    :day,
    :day_of_week,
    :byday,
    :hour,
    :minute,
    :second,
    :set_position
  ]

  defp application_order_key({token, _value}) do
    Enum.find_index(@application_order, &(&1 == token)) || length(@application_order)
  end

  # BYDAY-with-ordinal's period scope:
  #
  # * FREQ=MONTHLY → `:month`.
  # * FREQ=YEARLY with BYMONTH present → `:month` (per RFC).
  # * FREQ=YEARLY without BYMONTH → `:year`.
  # * Otherwise BYDAY ordinals are not meaningful per RFC, so we
  #   default to the widest (`:year`) — the `:byday` handler
  #   tolerates this since nth_kday simply operates relative to
  #   the period's endpoint.
  defp byday_scope(:month, _selection), do: :month

  defp byday_scope(:year, selection) do
    if Keyword.has_key?(selection, :month), do: :month, else: :year
  end

  defp byday_scope(_, _), do: :year

  # WKST — context-only token consumed by `apply_selection`.
  # Already extracted before the reduce fires, so by the time it
  # shows up here it's a no-op.
  defp apply_entry({:wkst, _}, candidates, _freq, _scope, _wkst), do: candidates

  # BYMONTH — always LIMIT.
  defp apply_entry({:month, months}, candidates, _freq, _scope, _wkst) do
    limit(candidates, months, &month_of/1)
  end

  # BYMONTHDAY — LIMIT. RFC forbids it with FREQ=WEEKLY; we don't
  # reject such rules here (malformed rules are a parser concern),
  # we just filter by matching day-of-month using positive and/or
  # negative values. `-1` is the last day of the enclosing month.
  defp apply_entry({:day, days}, candidates, _freq, _scope, _wkst) do
    Enum.filter(candidates, fn candidate ->
      in_month_day_list?(candidate, List.wrap(days))
    end)
  end

  # BYYEARDAY — LIMIT. Day-of-year, 1..366, supports negatives
  # (`-1` = last day of year). Forbidden by RFC with FREQ=DAILY,
  # WEEKLY, or MONTHLY; we don't reject, we just filter.
  defp apply_entry({:day_of_year, days}, candidates, _freq, _scope, _wkst) do
    Enum.filter(candidates, fn candidate ->
      in_year_day_list?(candidate, List.wrap(days))
    end)
  end

  # BYWEEKNO — LIMIT. Only valid with FREQ=YEARLY per RFC.
  # Week numbers are ISO weeks (Monday-first, week 1 has ≥4
  # days in the year) as RFC 5545 §3.3.10 mandates. WKST and
  # BYWEEKNO are orthogonal — WKST affects BYDAY week
  # boundaries, not ISO week numbering.
  defp apply_entry({:week, weeks}, candidates, _freq, _scope, _wkst) do
    Enum.filter(candidates, fn candidate ->
      in_week_no_list?(candidate, List.wrap(weeks))
    end)
  end

  # BYDAY without ordinal — pure day-of-week filter/expander
  # driven by FREQ. LIMIT for DAILY/finer, EXPAND for
  # WEEKLY/MONTHLY/YEARLY into all matching weekdays in the
  # period. `WEEKLY` expansion uses `wkst` to decide where the
  # enclosing 7-day window begins.
  defp apply_entry({:day_of_week, days}, candidates, freq, _scope, wkst) do
    case byday_role(freq) do
      :limit ->
        Enum.filter(candidates, fn candidate ->
          weekday_of(candidate) in List.wrap(days)
        end)

      {:expand, :week} ->
        Enum.flat_map(candidates, &expand_weekdays_in_week(&1, List.wrap(days), wkst))

      {:expand, :month} ->
        Enum.flat_map(candidates, &expand_weekdays_in_month(&1, List.wrap(days)))

      {:expand, :year} ->
        Enum.flat_map(candidates, &expand_weekdays_in_year(&1, List.wrap(days)))
    end
  end

  # BYDAY with ordinals — EXPAND. Each `{ordinal, weekday}` pair
  # picks one (or more) specific date within the enclosing
  # period (month or year, as determined by `scope`). Backed by
  # `Calendrical.Kday.nth_kday/3` which handles both positive
  # and negative ordinals.
  #
  # Entries with `nil` ordinal behave like a no-ordinal BYDAY
  # entry at the same scope (all matching weekdays in the
  # period).
  defp apply_entry({:byday, pairs}, candidates, _freq, scope, wkst) do
    Enum.flat_map(candidates, fn candidate ->
      expand_byday_pairs(candidate, pairs, scope, wkst)
    end)
  end

  # BYHOUR / BYMINUTE / BYSECOND — EXPAND when FREQ is coarser
  # than the unit, LIMIT when FREQ is the same unit or finer.
  defp apply_entry({:hour, values}, candidates, freq, _scope, _wkst) do
    expand_or_limit_time(candidates, :hour, List.wrap(values), freq)
  end

  defp apply_entry({:minute, values}, candidates, freq, _scope, _wkst) do
    expand_or_limit_time(candidates, :minute, List.wrap(values), freq)
  end

  defp apply_entry({:second, values}, candidates, freq, _scope, _wkst) do
    expand_or_limit_time(candidates, :second, List.wrap(values), freq)
  end

  # BYSETPOS — applied LAST (per RFC 5545). Treats the
  # accumulated `candidates` list as the per-period set and
  # picks the Nth element. Positive ordinals count from the
  # start (1-based), negative from the end (`-1` = last).
  # Out-of-range ordinals are silently dropped, matching the
  # RFC's "no occurrence" semantic.
  defp apply_entry({:set_position, positions}, candidates, _freq, _scope, _wkst) do
    pick_set_positions(candidates, List.wrap(positions))
  end

  # Unknown tokens pass through unchanged.
  defp apply_entry(_entry, candidates, _freq, _scope, _wkst), do: candidates

  ## ------------------------------------------------------------
  ## Generic LIMIT helper
  ## ------------------------------------------------------------

  # `extractor` pulls an integer (or nil) from a candidate. Keeps
  # candidates whose extracted value is in `targets` (a single
  # integer or a list). `nil` extractions drop the candidate.
  defp limit(candidates, targets, extractor) do
    values = List.wrap(targets)

    Enum.filter(candidates, fn candidate ->
      case extractor.(candidate) do
        nil -> false
        value when is_integer(value) -> value in values
      end
    end)
  end

  defp month_of(%Interval{from: %Tempo{time: time}}), do: Keyword.get(time, :month)

  ## ------------------------------------------------------------
  ## BYMONTHDAY
  ## ------------------------------------------------------------

  defp in_month_day_list?(%Interval{} = candidate, days) do
    case {day_of(candidate), days_in_enclosing_month(candidate)} do
      {nil, _} -> false
      {_, nil} -> false
      {day, dim} -> Enum.any?(days, &matches_signed_index?(&1, day, dim))
    end
  end

  defp day_of(%Interval{from: %Tempo{time: time}}), do: Keyword.get(time, :day)

  defp days_in_enclosing_month(%Interval{from: %Tempo{time: time, calendar: calendar}}) do
    year = Keyword.get(time, :year)
    month = Keyword.get(time, :month)

    if is_integer(year) and is_integer(month) do
      calendar.days_in_month(year, month)
    end
  end

  ## ------------------------------------------------------------
  ## BYYEARDAY
  ## ------------------------------------------------------------

  defp in_year_day_list?(%Interval{} = candidate, target_days) do
    case {day_of_year_of(candidate), days_in_enclosing_year(candidate)} do
      {nil, _} -> false
      {_, nil} -> false
      {doy, diy} -> Enum.any?(target_days, &matches_signed_index?(&1, doy, diy))
    end
  end

  defp day_of_year_of(%Interval{from: %Tempo{time: time, calendar: calendar}}) do
    with year when is_integer(year) <- Keyword.get(time, :year),
         month when is_integer(month) <- Keyword.get(time, :month),
         day when is_integer(day) <- Keyword.get(time, :day) do
      calendar.day_of_year(year, month, day)
    else
      _ -> nil
    end
  end

  defp days_in_enclosing_year(%Interval{from: %Tempo{time: time, calendar: calendar}}) do
    case Keyword.get(time, :year) do
      year when is_integer(year) -> calendar.days_in_year(year)
      _ -> nil
    end
  end

  ## ------------------------------------------------------------
  ## BYWEEKNO
  ## ------------------------------------------------------------

  defp in_week_no_list?(%Interval{} = candidate, weeks) do
    case {iso_week_of(candidate), weeks_in_enclosing_year(candidate)} do
      {nil, _} -> false
      {_, nil} -> false
      {wk, wiy} -> Enum.any?(weeks, &matches_signed_index?(&1, wk, wiy))
    end
  end

  # Dispatch to the candidate's calendar for its ISO-week number.
  # ISO weeks are Monday-first by definition and are what RFC
  # 5545 §3.3.10 specifies for BYWEEKNO ("Week numbers refer to
  # ISO week"). WKST does not shift ISO week numbering — the
  # two are orthogonal.
  defp iso_week_of(%Interval{from: %Tempo{time: time, calendar: calendar}}) do
    with year when is_integer(year) <- Keyword.get(time, :year),
         month when is_integer(month) <- Keyword.get(time, :month),
         day when is_integer(day) <- Keyword.get(time, :day) do
      {_year, week} = calendar.iso_week_of_year(year, month, day)
      week
    else
      _ -> nil
    end
  end

  defp weeks_in_enclosing_year(%Interval{from: %Tempo{time: time, calendar: calendar}}) do
    case Keyword.get(time, :year) do
      year when is_integer(year) ->
        # Some Calendar implementations (e.g. `Calendrical.Gregorian`)
        # return `{weeks, days_in_last_week}` from `weeks_in_year/1`;
        # others return just the integer. Accept either.
        case calendar.weeks_in_year(year) do
          {weeks, _days_in_last_week} when is_integer(weeks) -> weeks
          weeks when is_integer(weeks) -> weeks
          _ -> nil
        end

      _ ->
        nil
    end
  end

  ## ------------------------------------------------------------
  ## BYDAY (weekday filter / expander)
  ## ------------------------------------------------------------

  # Per RFC 5545 §3.3.10, BYDAY is a LIMIT for FREQ finer than a
  # week and an EXPAND for FREQ=WEEKLY, MONTHLY, YEARLY. The
  # period that the expansion walks is the enclosing week, month,
  # or year respectively.
  defp byday_role(:year), do: {:expand, :year}
  defp byday_role(:month), do: {:expand, :month}
  defp byday_role(:week), do: {:expand, :week}
  defp byday_role(_), do: :limit

  defp weekday_of(%Interval{from: %Tempo{time: time, calendar: calendar}}) do
    with year when is_integer(year) <- Keyword.get(time, :year),
         month when is_integer(month) <- Keyword.get(time, :month),
         day when is_integer(day) <- Keyword.get(time, :day) do
      calendar.day_of_week(year, month, day, :monday)
      |> normalise_day_of_week()
    else
      _ -> nil
    end
  end

  # `Calendar.day_of_week/4` can return `:undefined` or a tuple
  # depending on the calendar implementation; coerce to a 1..7
  # integer (ISO, Monday=1) or `nil` when the calendar refuses.
  defp normalise_day_of_week(dow) when is_integer(dow) and dow in 1..7, do: dow
  defp normalise_day_of_week({dow, _first, _last}) when is_integer(dow), do: dow
  defp normalise_day_of_week(_), do: nil

  # Walk every date in the candidate's enclosing week/month/year
  # and emit one new candidate per matching weekday. We preserve
  # the candidate's time-of-day and metadata; only the date
  # component changes. Every calendar op goes through the
  # candidate's own calendar.
  defp expand_weekdays_in_month(%Interval{from: %Tempo{calendar: calendar}} = candidate, weekdays) do
    case enclosing_month(candidate) do
      nil ->
        [candidate]

      {year, month} ->
        emit_matching_days(
          candidate,
          year,
          month,
          1..calendar.days_in_month(year, month),
          weekdays
        )
    end
  end

  defp expand_weekdays_in_year(%Interval{from: %Tempo{calendar: calendar}} = candidate, weekdays) do
    case enclosing_year(candidate) do
      nil ->
        [candidate]

      year ->
        1..calendar.months_in_year(year)
        |> Enum.flat_map(fn month ->
          emit_matching_days(
            candidate,
            year,
            month,
            1..calendar.days_in_month(year, month),
            weekdays
          )
        end)
    end
  end

  defp expand_weekdays_in_week(%Interval{} = candidate, weekdays, wkst) do
    case week_date_range(candidate, wkst) do
      nil ->
        [candidate]

      dates ->
        dates
        |> Enum.filter(fn {_year, _month, _day, dow} -> dow in weekdays end)
        |> Enum.map(fn {year, month, day, _dow} ->
          swap_date(candidate, year, month, day)
        end)
    end
  end

  defp enclosing_month(%Interval{from: %Tempo{time: time}}) do
    with year when is_integer(year) <- Keyword.get(time, :year),
         month when is_integer(month) <- Keyword.get(time, :month) do
      {year, month}
    else
      _ -> nil
    end
  end

  defp enclosing_year(%Interval{from: %Tempo{time: time}}) do
    case Keyword.get(time, :year) do
      year when is_integer(year) -> year
      _ -> nil
    end
  end

  defp emit_matching_days(
         %Interval{from: %Tempo{calendar: calendar}} = candidate,
         year,
         month,
         days,
         weekdays
       ) do
    days
    |> Enum.filter(fn day ->
      dow = calendar.day_of_week(year, month, day, :monday) |> normalise_day_of_week()
      dow in weekdays
    end)
    |> Enum.map(fn day -> swap_date(candidate, year, month, day) end)
  end

  # Build the week around the candidate's date as seven
  # `{year, month, day, weekday}` tuples in chronological order,
  # with the week anchored on `wkst` (1..7, Monday=1, default 1).
  # For `wkst = k` the week starts on the `k`-th weekday
  # preceding-or-equal-to the candidate, computed via
  # `Integer.mod(candidate_dow - wkst, 7)`.
  defp week_date_range(%Interval{from: %Tempo{time: time, calendar: calendar}}, wkst) do
    with year when is_integer(year) <- Keyword.get(time, :year),
         month when is_integer(month) <- Keyword.get(time, :month),
         day when is_integer(day) <- Keyword.get(time, :day),
         dow when is_integer(dow) <-
           calendar.day_of_week(year, month, day, :monday) |> normalise_day_of_week(),
         {:ok, date} <- Date.new(year, month, day, calendar) do
      offset_back = Integer.mod(dow - wkst, 7)
      week_start = Date.add(date, -offset_back)

      for i <- 0..6 do
        d = Date.add(week_start, i)

        d_dow =
          calendar.day_of_week(d.year, d.month, d.day, :monday) |> normalise_day_of_week()

        {d.year, d.month, d.day, d_dow}
      end
    else
      _ -> nil
    end
  end

  # Rebuild a candidate with a new date, preserving the existing
  # time-of-day fields (hour/minute/second) and all other AST.
  # Calendar-aware — every `Date` operation is threaded through
  # the candidate's own calendar, so non-Gregorian recurrences
  # (Hebrew, Islamic, Coptic, …) expand correctly.
  #
  # NOTE: `Keyword.put/3` deletes-then-prepends, which reorders
  # the time list and breaks `Tempo.IntervalSet`'s positional
  # sort. We use `replace_unit_values/2` to preserve the original
  # [year, month, day, hour, …] ordering.
  defp swap_date(
         %Interval{from: %Tempo{time: time, calendar: calendar} = tempo, to: to} = candidate,
         year,
         month,
         day
       ) do
    new_from_time = replace_unit_values(time, year: year, month: month, day: day)
    new_from = %{tempo | time: new_from_time}
    new_to = shift_to_endpoint(to, time, new_from_time, calendar)
    %{candidate | from: new_from, to: new_to}
  end

  # Order-preserving replacement for keyword-list `time` values.
  # For each `{unit, value}` in `replacements`, if `unit` is
  # present in `time`, swap its value in place; otherwise leave
  # `time` alone (callers that need to ADD a unit use
  # `upsert_unit/3`).
  defp replace_unit_values(time, replacements) do
    Enum.map(time, fn {key, value} ->
      case Keyword.fetch(replacements, key) do
        {:ok, new_value} -> {key, new_value}
        :error -> {key, value}
      end
    end)
  end

  defp shift_to_endpoint(nil, _old, _new, _calendar), do: nil
  defp shift_to_endpoint(:undefined, _old, _new, _calendar), do: :undefined

  defp shift_to_endpoint(%Tempo{time: to_time} = to_tempo, old_from_time, new_from_time, calendar) do
    # Shift `to`'s date component by the same calendar-aware
    # day-delta that took `from` to its new position. Preserves
    # hour/minute/second on `to` so a 10:00–11:00 event stays
    # 10:00–11:00 on its new date.
    case delta_days(old_from_time, new_from_time, calendar) do
      nil ->
        to_tempo

      delta ->
        case shift_date_fields(to_time, delta, calendar) do
          nil -> to_tempo
          shifted_time -> %{to_tempo | time: shifted_time}
        end
    end
  end

  defp delta_days(from_time, to_time, calendar) do
    with {:ok, a} <- date_of(from_time, calendar),
         {:ok, b} <- date_of(to_time, calendar) do
      Date.diff(b, a)
    else
      _ -> nil
    end
  end

  defp shift_date_fields(time, delta, calendar) do
    case date_of(time, calendar) do
      {:ok, date} ->
        new_date = Date.add(date, delta)
        replace_unit_values(time, year: new_date.year, month: new_date.month, day: new_date.day)

      _ ->
        nil
    end
  end

  defp date_of(time, calendar) do
    with year when is_integer(year) <- Keyword.get(time, :year),
         month when is_integer(month) <- Keyword.get(time, :month),
         day when is_integer(day) <- Keyword.get(time, :day) do
      Date.new(year, month, day, calendar)
    else
      _ -> :error
    end
  end

  ## ------------------------------------------------------------
  ## BYDAY with ordinals — "nth Kday" of the enclosing period
  ## ------------------------------------------------------------

  # For each `{ordinal, weekday}` pair, emit the matching date(s)
  # within the candidate's enclosing period. `scope` determines
  # whether "the period" is the candidate's month or year.
  # `wkst` is forwarded to the nil-ordinal fallback which
  # delegates to the weekly expander.
  defp expand_byday_pairs(%Interval{} = candidate, pairs, scope, wkst) do
    case period_bounds(candidate, scope) do
      nil ->
        # No clear period — pass through so the pipeline keeps
        # flowing. This shouldn't happen in well-formed rules.
        [candidate]

      {start_date, end_date} ->
        pairs
        |> Enum.flat_map(fn pair ->
          resolve_byday_pair(candidate, pair, start_date, end_date, scope, wkst)
        end)
        |> Enum.reject(&is_nil/1)
    end
  end

  # Compute the enclosing period's start and end `Date` values in
  # the candidate's own calendar. Month scope: 1st..last of the
  # candidate's month. Year scope: Jan 1..(Dec or last month) of
  # the candidate's year.
  defp period_bounds(%Interval{from: %Tempo{time: time, calendar: calendar}}, :month) do
    with year when is_integer(year) <- Keyword.get(time, :year),
         month when is_integer(month) <- Keyword.get(time, :month),
         last_day when is_integer(last_day) <- calendar.days_in_month(year, month),
         {:ok, start_date} <- Date.new(year, month, 1, calendar),
         {:ok, end_date} <- Date.new(year, month, last_day, calendar) do
      {start_date, end_date}
    else
      _ -> nil
    end
  end

  defp period_bounds(%Interval{from: %Tempo{time: time, calendar: calendar}}, :year) do
    with year when is_integer(year) <- Keyword.get(time, :year),
         last_month when is_integer(last_month) <- calendar.months_in_year(year),
         last_day when is_integer(last_day) <- calendar.days_in_month(year, last_month),
         {:ok, start_date} <- Date.new(year, 1, 1, calendar),
         {:ok, end_date} <- Date.new(year, last_month, last_day, calendar) do
      {start_date, end_date}
    else
      _ -> nil
    end
  end

  # A single pair: with an ordinal, call `nth_kday` relative to
  # period start (positive) or end (negative). Without an
  # ordinal, expand to every matching weekday in the period (same
  # semantic as no-ordinal BYDAY at this scope) — matches the
  # RFC behaviour for mixed `BYDAY=MO,2TU` where `MO` is "every
  # Monday" and `2TU` is "2nd Tuesday".
  defp resolve_byday_pair(%Interval{} = candidate, {nil, weekday}, _start, _end, scope, wkst) do
    case scope do
      :month -> expand_weekdays_in_month(candidate, [weekday])
      :year -> expand_weekdays_in_year(candidate, [weekday])
      :week -> expand_weekdays_in_week(candidate, [weekday], wkst)
    end
  end

  defp resolve_byday_pair(
         %Interval{} = candidate,
         {ordinal, weekday},
         start_date,
         end_date,
         _scope,
         _wkst
       )
       when is_integer(ordinal) do
    anchor = if ordinal >= 0, do: start_date, else: end_date

    case Calendrical.Kday.nth_kday(anchor, ordinal, weekday) do
      %Date{year: y, month: m, day: d} = d_struct ->
        if date_in_period?(d_struct, start_date, end_date),
          do: [swap_date(candidate, y, m, d)],
          else: []

      _ ->
        []
    end
  end

  # `nth_kday` may return a date outside the intended period
  # when the ordinal exceeds the number of matching weekdays
  # (e.g. `5MO` in a month with only 4 Mondays). Clamp by
  # checking the period boundaries.
  defp date_in_period?(%Date{} = date, %Date{} = start_date, %Date{} = end_date) do
    Date.compare(date, start_date) != :lt and Date.compare(date, end_date) != :gt
  end

  ## ------------------------------------------------------------
  ## BYSETPOS — applied last, per-period
  ## ------------------------------------------------------------

  # Candidates arrive here in chronological order (the earlier
  # BY-rule expanders walk periods in order). Positive positions
  # are 1-based from the start; negative from the end. We
  # preserve the caller's ordering of the positions list but
  # drop out-of-range picks.
  defp pick_set_positions([], _positions), do: []

  defp pick_set_positions(candidates, positions) do
    total = length(candidates)
    indexed = Enum.with_index(candidates, 1)

    positions
    |> Enum.map(fn pos ->
      target = if pos > 0, do: pos, else: total + pos + 1

      case Enum.find(indexed, fn {_c, i} -> i == target end) do
        {candidate, _i} -> candidate
        nil -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  ## ------------------------------------------------------------
  ## BYHOUR / BYMINUTE / BYSECOND
  ## ------------------------------------------------------------

  # Unit weight for the EXPAND-vs-LIMIT decision: rules whose
  # unit is FINER than FREQ (bigger weight) act as EXPAND; rules
  # whose unit is EQUAL or COARSER act as LIMIT. The weights only
  # need an ordering, not specific values.
  @unit_weight %{
    year: 1,
    month: 2,
    week: 3,
    day: 4,
    hour: 5,
    minute: 6,
    second: 7
  }

  defp expand_or_limit_time(candidates, unit, values, freq) do
    cond do
      Map.get(@unit_weight, freq, 0) < Map.get(@unit_weight, unit, 0) ->
        Enum.flat_map(candidates, fn candidate ->
          Enum.map(values, fn value -> set_time_unit(candidate, unit, value) end)
        end)

      true ->
        Enum.filter(candidates, fn candidate ->
          current = get_time_unit(candidate, unit)
          is_integer(current) and current in values
        end)
    end
  end

  defp get_time_unit(%Interval{from: %Tempo{time: time}}, unit), do: Keyword.get(time, unit)

  defp set_time_unit(%Interval{from: %Tempo{time: time} = tempo} = candidate, unit, value) do
    new_time = upsert_unit(time, unit, value)
    %{candidate | from: %{tempo | time: new_time}}
  end

  # Update a unit in an ordered `time` list. If the unit is
  # already present, replace its value in place. Otherwise
  # insert it in canonical position (year → month → week → day
  # → hour → minute → second) so `Tempo.IntervalSet`'s
  # position-dependent sort stays correct.
  defp upsert_unit(time, unit, value) do
    if Keyword.has_key?(time, unit) do
      Enum.map(time, fn
        {^unit, _} -> {unit, value}
        pair -> pair
      end)
    else
      insert_unit_in_order(time, unit, value)
    end
  end

  @unit_canonical_order [:year, :month, :week, :day, :hour, :minute, :second]

  defp insert_unit_in_order(time, unit, value) do
    target_idx =
      Enum.find_index(@unit_canonical_order, &(&1 == unit)) || length(@unit_canonical_order)

    {before, rest} =
      Enum.split_while(time, fn {k, _} ->
        idx = Enum.find_index(@unit_canonical_order, &(&1 == k))
        idx != nil and idx < target_idx
      end)

    before ++ [{unit, value}] ++ rest
  end

  ## ------------------------------------------------------------
  ## Signed-index match helper
  ##
  ## RFC 5545 expresses "last day of month", "second to last week
  ## of year", etc. as negative integers. `matches_signed_index?`
  ## accepts both positive and negative targets against a value
  ## whose maximum-in-period is `max` (e.g. 31 for Jan, 366 for a
  ## leap year, 53 for ISO weeks).
  ## ------------------------------------------------------------

  defp matches_signed_index?(target, value, max)
       when is_integer(target) and is_integer(value) and is_integer(max) do
    cond do
      target > 0 -> target == value
      target < 0 -> max + target + 1 == value
      true -> false
    end
  end

  defp matches_signed_index?(_target, _value, _max), do: false
end
