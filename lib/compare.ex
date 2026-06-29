defmodule Tempo.Compare do
  @moduledoc """
  Shared comparison primitives for Tempo values.

  Set operations, enumeration, and IntervalSet construction all
  need to compare two time keyword lists as start-moments on the
  time line. This module is the single place that definition
  lives. The comparison treats missing trailing units as their
  unit minimum — so `[year: 2022]` (which means "start of 2022")
  compares correctly against `[year: 2022, month: 6]` (which
  means "start of June 2022") without ambiguity.

  For set operations that span timezones, `to_utc_seconds/1`
  projects a zoned `%Tempo{}` into gregorian-seconds-since-UTC
  epoch so operands in different zones can share a total order.
  The projection is computed on demand and never cached — that
  policy decision was made in the implicit-to-explicit plan and
  revisited in the set-operations plan.

  """

  @doc """
  Compare two time keyword lists as start-moments on the time
  line.

  Missing trailing units are filled with their unit minimum
  (`:month` / `:day` / `:week` / `:day_of_year` / `:day_of_week`
  count from 1; everything else counts from 0). Both lists must
  be sorted descending-by-unit — the invariant the tokenizer and
  `Unit.sort/2` maintain.

  Mismatched units at the same position (e.g. `:week` vs
  `:month`) fall through to `:eq` as a conservative bailout. A
  well-formed comparison has operands using the same unit
  vocabulary.

  ### Arguments

  * `a` and `b` are keyword lists like `[year: 2022, month: 6]`.

  ### Returns

  * `:lt` when `a` is earlier than `b`.

  * `:gt` when `a` is later than `b`.

  * `:eq` when they are the same start-moment, or when mismatched
    unit vocabularies prevent a meaningful order.

  ### Examples

      iex> Tempo.Compare.compare_time([year: 2022], [year: 2022, month: 6])
      :lt

      iex> Tempo.Compare.compare_time([year: 2022, month: 6, day: 15], [year: 2022, month: 6, day: 15])
      :eq

      iex> Tempo.Compare.compare_time([year: 2023], [year: 2022, month: 12])
      :gt

  """
  @spec compare_time(keyword(), keyword()) :: :lt | :eq | :gt
  def compare_time([], []), do: :eq

  # Microseconds compare by VALUE only. Precision (digit count) sets
  # the interval width, not the instant ordering: `{120000, 2}` (.12)
  # and `{120000, 3}` (.120) denote the same start moment, so they
  # compare equal here. Generic tuple comparison would (wrongly) order
  # them by precision, so these clauses precede the generic ones.
  def compare_time([{:microsecond, {v1, _p1}} | t1], [{:microsecond, {v2, _p2}} | t2]) do
    cond do
      v1 < v2 -> :lt
      v1 > v2 -> :gt
      true -> compare_time(t1, t2)
    end
  end

  def compare_time([{:microsecond, {v, _p}} | rest], []) do
    if v > 0, do: :gt, else: compare_time(rest, [])
  end

  def compare_time([], [{:microsecond, {v, _p}} | rest]) do
    if v > 0, do: :lt, else: compare_time([], rest)
  end

  def compare_time([{unit, v} | rest], []) do
    min = unit_minimum(unit)

    cond do
      v < min -> :lt
      v > min -> :gt
      true -> compare_time(rest, [])
    end
  end

  def compare_time([], [{unit, v} | rest]) do
    min = unit_minimum(unit)

    cond do
      min < v -> :lt
      min > v -> :gt
      true -> compare_time([], rest)
    end
  end

  def compare_time([{unit, v1} | t1], [{unit, v2} | t2]) do
    cond do
      v1 < v2 -> :lt
      v1 > v2 -> :gt
      true -> compare_time(t1, t2)
    end
  end

  def compare_time(_, _), do: :eq

  @doc """
  The start-of-unit minimum — 1 for `:month`, `:day`, `:week`,
  `:day_of_year`, `:day_of_week`; 0 for everything else.

  Exposed on `Tempo.Compare` and `Tempo.Math` as the same
  definition (both modules re-export via delegation).

  """
  @spec unit_minimum(atom()) :: integer()
  def unit_minimum(:month), do: 1
  def unit_minimum(:day), do: 1
  def unit_minimum(:week), do: 1
  def unit_minimum(:day_of_year), do: 1
  def unit_minimum(:day_of_week), do: 1
  def unit_minimum(_), do: 0

  @doc """
  Return `:earlier`, `:later`, or `:same` for two `%Tempo{}`
  endpoints comparing by their UTC-projected start-moments.

  When both Tempos share a zone (or both have `nil` zone info),
  this reduces to `compare_time/2` on their `:time` lists with a
  renamed return. When zones differ, both sides are projected to
  UTC via `to_utc_seconds/1` for a common reference frame.

  ### Arguments

  * `a` and `b` are `%Tempo{}` structs, typically interval
    endpoints.

  ### Returns

  * `:earlier`, `:later`, or `:same`.

  """
  @spec compare_endpoints(Tempo.t(), Tempo.t()) :: :earlier | :later | :same
  def compare_endpoints(%Tempo{} = a, %Tempo{} = b) do
    if zones_compatible?(a, b) do
      case compare_time(a.time, b.time) do
        :lt -> :earlier
        :gt -> :later
        :eq -> :same
      end
    else
      compare_via_utc(a, b)
    end
  end

  # Two Tempos are zone-compatible when they carry the same
  # zone_id (or both have no zone info). Same-zone comparison
  # doesn't need UTC projection — the wall-clock values are
  # directly comparable.
  defp zones_compatible?(%Tempo{extended: nil}, %Tempo{extended: nil}), do: true

  defp zones_compatible?(%Tempo{extended: %{zone_id: z}}, %Tempo{extended: %{zone_id: z}}),
    do: true

  defp zones_compatible?(%Tempo{extended: nil}, %Tempo{extended: %{zone_id: nil}}), do: true
  defp zones_compatible?(%Tempo{extended: %{zone_id: nil}}, %Tempo{extended: nil}), do: true

  defp zones_compatible?(%Tempo{extended: %{zone_id: nil}}, %Tempo{extended: %{zone_id: nil}}),
    do: true

  defp zones_compatible?(_, _), do: false

  defp compare_via_utc(a, b) do
    a_secs = to_utc_seconds(a)
    b_secs = to_utc_seconds(b)

    cond do
      a_secs < b_secs -> :earlier
      a_secs > b_secs -> :later
      # Whole UTC seconds tie — break on the sub-second value. Zone
      # offsets are whole-minute, so the microsecond value is the same
      # in wall-clock and UTC frames; comparing the raw values is exact.
      true -> compare_microsecond_values(a, b)
    end
  end

  defp compare_microsecond_values(a, b) do
    case {microsecond_value(a), microsecond_value(b)} do
      {x, y} when x < y -> :earlier
      {x, y} when x > y -> :later
      _ -> :same
    end
  end

  defp microsecond_value(%Tempo{time: time}) do
    case Keyword.get(time, :microsecond) do
      {value, _precision} -> value
      nil -> 0
    end
  end

  @doc """
  Project a zoned `%Tempo{}` to UTC gregorian seconds since
  year 0 (matching Erlang's `:calendar.datetime_to_gregorian_seconds/1`
  epoch).

  The projection is per-call, never cached. When `Tzdata` is
  updated with new zone rules, the next call automatically uses
  them. Stored IntervalSet endpoints carry wall-clock + zone as
  authoritative — see `plans/set-operations.md` for the full
  rationale on why no UTC cache exists.

  ### Arguments

  * `tempo` is a `%Tempo{}` with at minimum year/month/day/hour/
    minute/second components. Missing components are padded with
    their unit minimum.

  ### Returns

  * `integer` — gregorian seconds since year 0 in UTC.

  ### Raises

  * `ArgumentError` when the Tempo has no `:year` component
    (non-anchored values can't be projected to a universal
    instant).

  """
  @spec to_utc_seconds(Tempo.t()) :: integer() | float()
  def to_utc_seconds(%Tempo{time: time, extended: extended, shift: shift}) do
    year = Keyword.get(time, :year)

    if year == nil do
      raise ArgumentError,
            "Cannot project a non-anchored Tempo (no :year component) to a UTC " <>
              "instant. Non-anchored values live on the time-of-day axis; anchor " <>
              "them first via `Tempo.anchor/2` or supply a `bound:` option to the " <>
              "calling operation."
    end

    wall = wall_seconds(time, year)
    wall - resolve_offset_seconds(extended, shift, wall)
  end

  # The wall-clock instant as gregorian seconds (before any offset is
  # applied). Shared by `to_utc_seconds/1` and `validate_zone_offset/1`.
  defp wall_seconds(time, year) do
    {year, month, day} = resolve_ymd(time, year)
    hour = Keyword.get(time, :hour, 0)
    minute = Keyword.get(time, :minute, 0)
    second = Keyword.get(time, :second, 0)
    :calendar.datetime_to_gregorian_seconds({{year, month, day}, {hour, minute, second}})
  end

  @doc """
  Check that an IXDTF value's explicit numeric offset agrees with its
  IANA time zone at the value's wall instant.

  When a value carries both a numeric offset and a zone identifier (e.g.
  `2022-11-20T10:37:00+05:00[Europe/Paris]`), the offset is normally
  consulted only to disambiguate a DST fall-back — the zone otherwise
  wins. This check (RFC 9557 §4.2) flags the case where the stated
  offset matches no offset the zone actually uses at that instant.

  ### Arguments

  * `tempo` is a `t:Tempo.t/0`.

  ### Returns

  * `:ok` when the offset agrees with the zone, when there is nothing to
    check (no zone, or no explicit offset), or when the value is not
    anchored (no wall instant to evaluate against).

  * `{:error, t:Tempo.ZoneOffsetMismatchError.t/0}` when the stated
    offset disagrees with the zone.

  See `Tempo.validate_zone_offset/1`, which delegates here, for worked
  examples.

  """
  @spec validate_zone_offset(Tempo.t()) ::
          :ok | {:error, Tempo.ZoneOffsetMismatchError.t()}
  def validate_zone_offset(%Tempo{time: time, extended: extended, shift: shift} = tempo) do
    zone_id = extended && Map.get(extended, :zone_id)
    stated = explicit_offset_seconds(extended, shift)

    cond do
      is_nil(zone_id) or zone_id == "" -> :ok
      is_nil(stated) -> :ok
      not Tempo.anchored?(tempo) -> :ok
      true -> check_zone_offset(time, zone_id, stated)
    end
  end

  defp check_zone_offset(time, zone_id, stated) do
    wall = wall_seconds(time, Keyword.get(time, :year))

    offsets =
      case Tzdata.periods_for_time(zone_id, wall, :wall) do
        [] -> []
        periods -> Enum.map(periods, &(&1.utc_off + &1.std_off))
      end

    if stated in offsets do
      :ok
    else
      {:error,
       Tempo.ZoneOffsetMismatchError.exception(
         zone_id: zone_id,
         stated_offset: stated,
         zone_offsets: offsets,
         wall_time: wall_seconds_to_iso(wall)
       )}
    end
  end

  defp wall_seconds_to_iso(wall) do
    {{y, mo, d}, {h, mi, s}} = :calendar.gregorian_seconds_to_datetime(wall)

    [y, mo, d, h, mi, s]
    |> then(&:io_lib.format("~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0B", &1))
    |> IO.iodata_to_binary()
  end

  # Resolve the calendar `{year, month, day}` from the time list,
  # handling the three date representations Tempo stores:
  #
  #   * ISO week date — `[year, week, day_of_week]`. Week 01 is the
  #     week containing Jan 4 (ISO 8601-1 §5.2.3).
  #   * Ordinal date — `[year, day]` with `:day` holding the
  #     day-of-year and no `:month` (the absence of `:month` is the
  #     disambiguator, matching `Tempo.to_date/1`).
  #   * Standard date — `[year, month, day]` (month/day default to 1).
  #
  # Without this, week and ordinal dates projected via the
  # month/day defaults (1, 1) and collapsed to Jan 1 — making every
  # week interval report a zero-second duration.
  defp resolve_ymd(time, year) do
    cond do
      Keyword.has_key?(time, :week) ->
        week = Keyword.get(time, :week)
        dow = Keyword.get(time, :day_of_week, 1)
        {:ok, jan_4} = Date.new(year, 1, 4)
        jan_4_dow = Date.day_of_week(jan_4)
        week_1_monday = Date.add(jan_4, -(jan_4_dow - 1))
        date = Date.add(week_1_monday, (week - 1) * 7 + (dow - 1))
        {date.year, date.month, date.day}

      not Keyword.has_key?(time, :month) and Keyword.has_key?(time, :day) ->
        {:ok, jan_1} = Date.new(year, 1, 1)
        date = Date.add(jan_1, Keyword.get(time, :day) - 1)
        {date.year, date.month, date.day}

      true ->
        {year, Keyword.get(time, :month, 1), Keyword.get(time, :day, 1)}
    end
  end

  # The offset to subtract from wall-clock to get UTC. Priority:
  #
  # 1. An IANA zone on `extended.zone_id` — look up via Tzdata at
  #    the given wall instant (DST-era-correct). When Tzdata
  #    returns multiple periods (DST fall-back ambiguity), an
  #    explicit numeric offset from `extended.zone_offset` or
  #    from the ISO 8601 `shift` disambiguates — we pick the
  #    period whose total offset matches. This is the mechanism
  #    RFC 9557 §4.5 describes for resolving fall-back ambiguity
  #    in IXDTF strings like `01:30:00-04:00[America/New_York]`.
  # 2. A numeric offset on `extended.zone_offset` (minutes) — use
  #    directly.
  # 3. A `shift` keyword list (legacy-style) — convert to seconds.
  # 4. No info → 0 (treat as UTC).
  defp resolve_offset_seconds(%{zone_id: zone_id} = extended, shift, wall_seconds)
       when is_binary(zone_id) and zone_id != "" do
    case Tzdata.periods_for_time(zone_id, wall_seconds, :wall) do
      [only] ->
        only.utc_off + only.std_off

      [_, _ | _] = periods ->
        # Ambiguous wall time (DST fall-back). Prefer the period
        # whose offset matches the explicit disambiguator, if any.
        preferred = explicit_offset_seconds(extended, shift)

        case Enum.find(periods, fn p -> p.utc_off + p.std_off == preferred end) do
          nil -> hd(periods).utc_off + hd(periods).std_off
          p -> p.utc_off + p.std_off
        end

      [] ->
        # Gap (spring-forward) or missing period. Fall back to
        # UTC; zone-existence validation at parse time rejects
        # these, so this branch is unreachable in practice.
        0
    end
  end

  defp resolve_offset_seconds(%{zone_offset: minutes}, _shift, _wall)
       when is_integer(minutes) do
    minutes * 60
  end

  defp resolve_offset_seconds(_extended, shift, _wall) when is_list(shift) do
    shift_to_seconds(shift)
  end

  defp resolve_offset_seconds(_extended, _shift, _wall), do: 0

  # Extract an explicit offset in seconds from either the extended
  # `zone_offset` (minutes) or the ISO 8601 `shift` (keyword list).
  # Returns `nil` when no explicit offset is supplied — the caller
  # then falls back to Tzdata's first period.
  defp explicit_offset_seconds(%{zone_offset: minutes}, _shift) when is_integer(minutes) do
    minutes * 60
  end

  defp explicit_offset_seconds(_extended, shift) when is_list(shift) do
    shift_to_seconds(shift)
  end

  defp explicit_offset_seconds(_extended, _shift), do: nil

  defp shift_to_seconds(shift) do
    hour = shift_component(shift, :hour)
    minute = shift_component(shift, :minute)
    second = shift_component(shift, :second)
    hour * 3600 + minute * 60 + second
  end

  # `Keyword.get/3` returns `any()`, so any arithmetic on its result
  # widens to `number()` and propagates a stray `float()` into the
  # spec of `to_utc_seconds/1`. Narrowing through a guarded helper
  # pins the result to `integer()` for Dialyzer. No `@spec` — the
  # success typing inferred from call sites (`:hour | :minute |
  # :second`) is tighter than any spec we'd write, and a broader
  # spec triggers a supertype-contract warning.
  defp shift_component(shift, key) do
    case Keyword.get(shift, key, 0) do
      value when is_integer(value) -> value
    end
  end
end
