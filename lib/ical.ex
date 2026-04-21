if Code.ensure_loaded?(ICal) do
  defmodule Tempo.ICal do
    @moduledoc """
    Import iCalendar (RFC 5545) data into `%Tempo.IntervalSet{}`.

    This module wraps the [`ical`](https://github.com/expothecary/ical)
    parser and translates each `VEVENT` into a `%Tempo.Interval{}`
    with full event metadata (summary, description, location,
    attendees, status, …) attached to the interval's `:metadata`
    map. The `VCALENDAR` envelope's metadata (product id, version,
    calendar scale, method) attaches to the `IntervalSet`'s
    `:metadata` map.

    Every pipeline step that accepts a Tempo value — set
    operations, `Enum.take/2`, resolution alignment — preserves
    the metadata through to the result. That lets free/busy and
    scheduling queries stay connected to their source events.

    The `ical` dependency is declared `optional: true` in `mix.exs`.
    `Tempo.ICal` is only compiled when `ical` is available in the
    dependency tree; projects that don't import calendar data don't
    pay the compile cost.

    ## Required reading

    * [RFC 5545](https://www.rfc-editor.org/rfc/rfc5545) — the iCalendar spec.
    * `guides/set-operations.md` for how the imported data is used downstream.

    ## RFC 5545 coverage

    | Property  | Status                                            |
    | --------- | ------------------------------------------------- |
    | `RRULE`   | Fully supported — every `BY*` part, `WKST`, and   |
    |           | `BYSETPOS` flow through the interpreter.          |
    | `RDATE`   | Supported — extra occurrences with the event's    |
    |           | own span.                                         |
    | `EXDATE`  | Supported — start-moment match removes the        |
    |           | corresponding occurrence.                         |
    | `EXRULE`  | Not surfaced by the underlying `ical` library, so |
    |           | not implementable at this layer. EXRULE is also   |
    |           | RFC-deprecated (RFC 2445 → 5545).                 |
    | Multiple  | RFC 5545 says SHOULD NOT; some exports do it      |
    | `RRULE`   | anyway. The `ical` library exposes only the       |
    | per       | first `RRULE` on `event.rrule`, so we materialise |
    | `VEVENT`  | that one and silently ignore the rest.            |

    """

    alias Tempo.{Interval, IntervalSet}

    # A hard ceiling on how many occurrences any single RRULE can
    # materialise. Prevents a malformed rule or a very wide bound
    # from consuming unbounded memory; 10 000 is more than a human
    # calendar would ever contain in a recurring series.
    @safety_cap 10_000

    @doc """
    Parse an iCalendar string and return a `%Tempo.IntervalSet{}`.

    Every `VEVENT` becomes one `%Tempo.Interval{}` in the result.
    All-day events (`DTSTART` as a `Date`) use day-resolution
    endpoints; datetime events use the matching datetime
    resolution. The event's `SUMMARY`, `DESCRIPTION`, `LOCATION`,
    `UID`, `STATUS`, `TRANSPARENCY`, `CATEGORIES`, attendees, and
    organizer all flow into the interval's `:metadata` map.

    The calendar-level metadata (`PRODID`, `VERSION`, `CALSCALE`,
    `METHOD`, and the user-visible name from `X-WR-CALNAME` when
    present) attaches to the IntervalSet's `:metadata` map.

    ### Arguments

    * `ics` is an iCalendar string (the contents of an `.ics`
      file).

    ### Options

    * `:bound` — a `t:Tempo.t/0`, `t:Tempo.Interval.t/0`, or
      `t:Tempo.IntervalSet.t/0` within which recurring events
      (those with an `RRULE`) are expanded. Required when any
      event in the input has a recurrence rule; ignored when
      there are none. An unbounded recurrence is infinite and
      refused at set-op time.

    ### Returns

    * `{:ok, interval_set}` — sorted, coalesced IntervalSet of
      the events.
    * `{:error, reason}` when parsing fails or a recurring event
      requires a `:bound` that wasn't supplied.

    ### Examples

        iex> ics = \"\"\"
        ...> BEGIN:VCALENDAR
        ...> VERSION:2.0
        ...> PRODID:-//Test//Test//EN
        ...> BEGIN:VEVENT
        ...> UID:test-1
        ...> DTSTAMP:20220101T000000Z
        ...> DTSTART:20220615T100000Z
        ...> DTEND:20220615T110000Z
        ...> SUMMARY:Test meeting
        ...> LOCATION:Paris
        ...> END:VEVENT
        ...> END:VCALENDAR
        ...> \"\"\"
        iex> {:ok, set} = Tempo.ICal.from_ical(ics)
        iex> length(set.intervals)
        1
        iex> [iv] = set.intervals
        iex> iv.metadata.summary
        "Test meeting"
        iex> iv.metadata.location
        "Paris"

    """
    @spec from_ical(binary(), keyword()) :: {:ok, IntervalSet.t()} | {:error, term()}
    def from_ical(ics, opts \\ []) when is_binary(ics) do
      try do
        calendar = ICal.from_ics(ics)
        build_interval_set(calendar, opts)
      rescue
        e in [ArgumentError, MatchError, FunctionClauseError] ->
          {:error, Exception.message(e)}
      end
    end

    @doc """
    Parse an iCalendar file and return a `%Tempo.IntervalSet{}`.

    Wraps `from_ical/2` with `File.read/1`.

    ### Arguments

    * `path` is a path to an `.ics` file.

    ### Options

    See `from_ical/2`.

    ### Returns

    * `{:ok, interval_set}` or `{:error, reason}`.

    """
    @spec from_ical_file(binary(), keyword()) ::
            {:ok, IntervalSet.t()} | {:error, term()}
    def from_ical_file(path, opts \\ []) do
      with {:ok, ics} <- File.read(path) do
        from_ical(ics, opts)
      end
    end

    ## ------------------------------------------------------------
    ## Calendar → IntervalSet
    ## ------------------------------------------------------------

    defp build_interval_set(%ICal{events: events} = calendar, opts) do
      case convert_events(events, opts) do
        {:ok, intervals} ->
          metadata = calendar_metadata(calendar)
          # Events are preserved as distinct intervals — overlapping
          # events (e.g. an all-day travel event on top of a lunch
          # meeting) are common and each carries its own metadata.
          # Coalescing would collapse these and silently lose
          # event identity. Callers who want coalesced free/busy
          # spans can union the set with itself or call a future
          # explicit coalesce helper.
          IntervalSet.new(intervals, metadata: metadata, coalesce: false)

        {:error, _} = err ->
          err
      end
    end

    defp convert_events(events, opts) do
      Enum.reduce_while(events, {:ok, []}, fn event, {:ok, acc} ->
        case event_to_intervals(event, opts) do
          {:ok, ivs} -> {:cont, {:ok, ivs ++ acc}}
          {:error, _} = err -> {:halt, err}
        end
      end)
    end

    defp calendar_metadata(%ICal{} = cal) do
      custom = Map.get(cal, :custom_properties) || %{}
      name = custom |> Map.get("X-WR-CALNAME") |> unwrap_custom_value()

      %{
        prodid: cal.product_id,
        version: cal.version,
        scale: cal.scale,
        method: cal.method,
        name: name
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()
    end

    # The `ical` library wraps custom property values in a struct
    # like `%{value: "X", params: %{}}`. Unwrap the inner string.
    defp unwrap_custom_value(%{value: value}) when is_binary(value), do: value
    defp unwrap_custom_value(value) when is_binary(value), do: value
    defp unwrap_custom_value(_), do: nil

    ## ------------------------------------------------------------
    ## Event → Interval(s)
    ## ------------------------------------------------------------

    defp event_to_intervals(%ICal.Event{dtstart: nil}, _opts) do
      # iCal technically requires DTSTART, but some exports
      # contain events without one. Skip silently — they can't be
      # placed on a time line.
      {:ok, []}
    end

    defp event_to_intervals(%ICal.Event{rrule: nil} = event, _opts) do
      case single_event_to_interval(event) do
        {:ok, iv} -> {:ok, [iv]}
        {:error, _} = err -> err
      end
    end

    defp event_to_intervals(%ICal.Event{rrule: rrule} = event, opts) do
      case expand_recurrence(event, rrule, opts) do
        {:ok, intervals} -> {:ok, intervals}
        {:error, _} = err -> err
      end
    end

    ## Recurrence expansion.
    ##
    ## Delegates to `Tempo.RRule.Expander.expand/3`, which is the
    ## single source of truth for RRULE materialisation. This
    ## module is only responsible for:
    ##
    ## * shaping the base event (`DTSTART`/`DTEND` → `%Interval{}`),
    ## * mapping `%ICal.Recurrence{}` fields to the Expander's
    ##   options,
    ## * carrying event metadata onto every occurrence,
    ## * deciding the "BY* rules → first-occurrence fallback"
    ##   policy while Phase B of the expander is in flight.
    ##
    ## When BY* rule support lands in the interpreter, the
    ## fallback goes away and this function becomes unconditional
    ## delegation.

    # With Phases A–D landed, every RFC 5545 recurrence primitive
    # flows through the supported path:
    #
    #   RRULE → `Tempo.RRule.Expander.expand/3` →
    #           `Tempo.to_interval/2` → `Tempo.RRule.Selection`
    #
    #   RDATE  — unioned into the RRULE occurrence set as extra
    #            `%Tempo.Interval{}` values, each carrying the
    #            event's span (`DTEND − DTSTART`) and metadata.
    #
    #   EXDATE — subtracted from the combined set by matching on
    #            the occurrence's `from` start moment.
    #
    # Phases B + C cover: BYMONTH, BYMONTHDAY, BYYEARDAY,
    # BYWEEKNO, BYDAY (with and without ordinals), BYHOUR,
    # BYMINUTE, BYSECOND, BYSETPOS.
    #
    # EXRULE is RFC-deprecated and the `ical` library does not
    # surface it, so we don't need to handle it.
    defp expand_recurrence(event, %ICal.Recurrence{} = rule, opts) do
      cond do
        rule.count == nil and rule.until == nil and not Keyword.has_key?(opts, :bound) ->
          {:error,
           "Event #{inspect(event.uid)} has an unbounded recurrence rule " <>
             "(no COUNT, no UNTIL). Provide a `:bound` option — a Tempo " <>
             "value within which the recurrence will be materialised."}

        true ->
          with {:ok, base} <- single_event_to_interval(event) do
            expander_opts =
              []
              |> maybe_put(:bound, Keyword.get(opts, :bound))
              |> Keyword.put(:metadata, base.metadata)
              |> Keyword.put(:base_to, base.to)

            case Tempo.RRule.Expander.expand(rule, base.from, expander_opts) do
              {:ok, rrule_occurrences} ->
                capped = Enum.take(rrule_occurrences, @safety_cap)

                combined =
                  capped
                  |> apply_rdates(event, base)
                  |> apply_exdates(event)
                  |> sort_by_from()

                {:ok, combined}

              {:error, _} = err ->
                err
            end
          end
      end
    end

    defp maybe_put(keyword, _key, nil), do: keyword
    defp maybe_put(keyword, key, value), do: Keyword.put(keyword, key, value)

    ## ----------------------------------------------------------
    ## RDATE / EXDATE
    ##
    ## `final = (RRULE_expansion ∪ RDATES) − EXDATES`
    ##
    ## The `ical` library delivers RDATE / EXDATE entries as
    ## plain `Date`, `DateTime`, or `NaiveDateTime` values. We
    ## normalise to `%Tempo{}` via `Tempo.from_elixir/1` so
    ## matching and set-operations share one vocabulary.
    ##
    ## Union: each RDATE becomes an `%Tempo.Interval{}` with the
    ## event's span (same `base_to - base_from` delta used by
    ## RRULE occurrences). Event metadata rides along so
    ## downstream operations keep the tie back to the source
    ## event.
    ##
    ## Subtract: EXDATE matches an occurrence when the
    ## occurrence's `from` moment equals the EXDATE. We compare
    ## via `Tempo.Compare.compare_endpoints/2` so time-zone
    ## equality and cross-resolution comparison fall out
    ## naturally.
    ## ----------------------------------------------------------

    defp apply_rdates(occurrences, %ICal.Event{rdates: nil}, _base), do: occurrences
    defp apply_rdates(occurrences, %ICal.Event{rdates: []}, _base), do: occurrences

    defp apply_rdates(occurrences, %ICal.Event{rdates: rdates}, %Interval{} = base) do
      extras =
        rdates
        |> Enum.map(&rdate_to_interval(&1, base))
        |> Enum.reject(&is_nil/1)

      occurrences ++ extras
    end

    # Turn one RDATE value into a full `%Tempo.Interval{}`. The
    # event's span (`base.to - base.from`) is preserved — an
    # RDATE adds a matching-duration occurrence at a new start.
    defp rdate_to_interval(%DateTime{} = dt, %Interval{} = base) do
      rdate_tempo(Tempo.from_elixir(dt), base)
    end

    defp rdate_to_interval(%NaiveDateTime{} = ndt, %Interval{} = base) do
      rdate_tempo(Tempo.from_elixir(ndt), base)
    end

    defp rdate_to_interval(%Date{} = d, %Interval{} = base) do
      rdate_tempo(Tempo.from_elixir(d, resolution: :day), base)
    end

    defp rdate_to_interval(_other, _base), do: nil

    # The RDATE's start is its full timestamp (date + time-of-day
    # if present). The end is `start + event_duration`, where the
    # event's duration is derived from the base occurrence in
    # UTC seconds via `Tempo.Compare.to_utc_seconds/1`. That
    # gives us a calendar-neutral delta that `Tempo.Math.add/2`
    # can apply to the RDATE start.
    defp rdate_tempo(%Tempo{} = from_tempo, %Interval{from: base_from, to: base_to, metadata: metadata}) do
      duration = event_duration(base_from, base_to)
      to_tempo = Tempo.Math.add(from_tempo, duration)
      %Interval{from: from_tempo, to: to_tempo, metadata: metadata}
    end

    defp event_duration(%Tempo{} = from, %Tempo{} = to) do
      seconds = Tempo.Compare.to_utc_seconds(to) - Tempo.Compare.to_utc_seconds(from)
      %Tempo.Duration{time: [second: seconds]}
    end

    defp apply_exdates(occurrences, %ICal.Event{exdates: nil}), do: occurrences
    defp apply_exdates(occurrences, %ICal.Event{exdates: []}), do: occurrences

    defp apply_exdates(occurrences, %ICal.Event{exdates: exdates}) do
      excluded =
        exdates
        |> Enum.map(&exdate_to_tempo/1)
        |> Enum.reject(&is_nil/1)

      Enum.reject(occurrences, fn %Interval{from: from} ->
        Enum.any?(excluded, fn ex -> same_moment?(from, ex) end)
      end)
    end

    defp exdate_to_tempo(%DateTime{} = dt), do: Tempo.from_elixir(dt)
    defp exdate_to_tempo(%NaiveDateTime{} = ndt), do: Tempo.from_elixir(ndt)
    defp exdate_to_tempo(%Date{} = d), do: Tempo.from_elixir(d, resolution: :day)
    defp exdate_to_tempo(_other), do: nil

    defp same_moment?(%Tempo{} = a, %Tempo{} = b) do
      Tempo.Compare.compare_endpoints(a, b) == :same
    end

    ## Sort the combined set so consumers see chronological order
    ## regardless of whether an RDATE landed after the RRULE run.
    defp sort_by_from(intervals) do
      Enum.sort_by(intervals, fn %Interval{from: %Tempo{time: time}} -> time_sort_key(time) end)
    end

    # Stable key for chronological sort — year, month, day, hour,
    # minute, second, with missing units defaulting to their unit
    # minimum so partial-resolution values sort alongside fully
    # specified ones.
    defp time_sort_key(time) do
      {
        Keyword.get(time, :year, 0),
        Keyword.get(time, :month, 1),
        Keyword.get(time, :day, 1),
        Keyword.get(time, :hour, 0),
        Keyword.get(time, :minute, 0),
        Keyword.get(time, :second, 0)
      }
    end

    # NOTE: `first_occurrence_only/2` was retired when Phase C
    # landed. Every RFC 5545 BY-rule now materialises through the
    # supported path, so no event emits only its first occurrence
    # with `metadata.recurrence_reason == :by_rules_not_supported`.
    # Restore it (git log) if a future RFC addition needs a
    # "visible but not fully materialised" fallback.

    defp single_event_to_interval(%ICal.Event{} = event) do
      with {:ok, from} <- dtstart_to_tempo(event.dtstart),
           {:ok, to} <- dtend_to_tempo(event, from) do
        metadata = event_metadata(event)
        {:ok, %Interval{from: from, to: to, metadata: metadata}}
      end
    end

    # All-day event: DTSTART is a Date. Convert to a
    # day-resolution Tempo; DTEND is typically the day after
    # (iCal all-day semantics are half-open).
    defp dtstart_to_tempo(%Date{} = date) do
      {:ok, Tempo.from_elixir(date, resolution: :day)}
    end

    defp dtstart_to_tempo(%DateTime{} = dt) do
      {:ok, Tempo.from_elixir(dt)}
    end

    defp dtstart_to_tempo(%NaiveDateTime{} = ndt) do
      {:ok, Tempo.from_elixir(ndt)}
    end

    defp dtstart_to_tempo(other) do
      {:error, "Unsupported DTSTART type: #{inspect(other)}"}
    end

    defp dtend_to_tempo(%ICal.Event{dtend: nil, duration: nil}, from) do
      # No DTEND and no DURATION — treat as a point event with
      # zero-width span, advanced by one unit at the from's
      # resolution so the interval is well-formed and
      # half-open-consistent. This matches iCal semantics for an
      # event with just DTSTART.
      case Tempo.Interval.next_unit_boundary(from) do
        {:ok, {_lower, upper}} -> {:ok, upper}
        {:error, _} = err -> err
      end
    end

    defp dtend_to_tempo(%ICal.Event{dtend: nil, duration: _duration}, _from) do
      # Duration-only events are parseable but require
      # `Tempo.Math.add/2` on a Duration token whose shape the
      # `ical` library surfaces as a `Timex.Duration`-ish record.
      # Not in v1.
      {:error, "Duration-only VEVENT (no DTEND) is not yet supported."}
    end

    defp dtend_to_tempo(%ICal.Event{dtend: %Date{} = date}, _from) do
      {:ok, Tempo.from_elixir(date, resolution: :day)}
    end

    defp dtend_to_tempo(%ICal.Event{dtend: %DateTime{} = dt}, _from) do
      {:ok, Tempo.from_elixir(dt)}
    end

    defp dtend_to_tempo(%ICal.Event{dtend: %NaiveDateTime{} = ndt}, _from) do
      {:ok, Tempo.from_elixir(ndt)}
    end

    defp dtend_to_tempo(%ICal.Event{dtend: other}, _from) do
      {:error, "Unsupported DTEND type: #{inspect(other)}"}
    end

    # Lift the iCalendar properties users most often care about.
    # Everything absent from the event is dropped (kept the
    # metadata map compact). X-* custom properties go into
    # `:custom` for later access.
    defp event_metadata(%ICal.Event{} = event) do
      base = %{
        uid: event.uid,
        summary: event.summary,
        description: event.description,
        location: event.location,
        status: event.status,
        transparency: event.transparency,
        categories: event.categories,
        url: event.url,
        classification: event.class,
        priority: event.priority,
        organizer: stringify_organizer(event.organizer),
        attendees: stringify_attendees(event.attendees),
        custom: event.custom_properties
      }

      base
      |> Enum.reject(fn
        {_k, nil} -> true
        {_k, []} -> true
        {_k, %{} = map} when map_size(map) == 0 -> true
        _ -> false
      end)
      |> Map.new()
    end

    defp stringify_organizer(nil), do: nil

    defp stringify_organizer(%{__struct__: _, cname: cname}) when is_binary(cname),
      do: cname

    defp stringify_organizer(other), do: inspect(other)

    defp stringify_attendees([]), do: []

    defp stringify_attendees(attendees) when is_list(attendees) do
      Enum.map(attendees, fn
        %{cname: cname} when is_binary(cname) -> cname
        other -> inspect(other)
      end)
    end
  end
end
