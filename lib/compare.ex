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
      true -> :same
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

    month = Keyword.get(time, :month, 1)
    day = Keyword.get(time, :day, 1)
    hour = Keyword.get(time, :hour, 0)
    minute = Keyword.get(time, :minute, 0)
    second = Keyword.get(time, :second, 0)

    wall_seconds =
      :calendar.datetime_to_gregorian_seconds({{year, month, day}, {hour, minute, second}})

    offset_seconds = resolve_offset_seconds(extended, shift, wall_seconds)
    wall_seconds - offset_seconds
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
    hour = Keyword.get(shift, :hour, 0)
    minute = Keyword.get(shift, :minute, 0)
    second = Keyword.get(shift, :second, 0)
    hour * 3600 + minute * 60 + second
  end
end
