defmodule Tempo.Format do
  @moduledoc """
  Locale-aware formatting for `Tempo` values, dispatching to the
  Localize library.

  `Tempo.to_string/1,2` and the `String.Chars` implementation for
  `Tempo`, `Tempo.Interval`, and `Tempo.IntervalSet` route through
  this module. Callers don't need to use it directly.

  ### Rendering rule — Tempo values are intervals

  A `%Tempo{}` at year or month resolution is a bounded span, and
  its user-visible rendering reflects that span. Rule:

  * `~o"2026"` (year resolution) → `"Jan\u2009\u2013\u2009Dec 2026"`.
    Iteration over a year yields months; the first and last months
    are shown.

  * `~o"2026-06"` (month resolution) → `"Jun 1\u2009\u2013\u200930, 2026"`.
    Iteration over a month yields days; first and last day.

  * `~o"2026-06-15"` (day resolution) → `"Jun 15, 2026"`. A day is
    atomic at human display granularity; collapse to a single
    value.

  * `~o"2026-06-15T14:30"` (minute or finer) → `"Jun 15, 2026, 2:30\u202FPM"`.
    Same collapse rationale.

  The cutoff between "expand as closed interval" and "collapse as
  single value" lives at **day granularity** by design — matching
  how people talk: "2026" is January-through-December; "June 2026"
  is June 1 to 30; "June 15" is just June 15.

  ### Closed vs half-open at the display boundary

  The underlying interval is always half-open `[from, to)`. For
  display we compute the **closed** last member — `to - 1
  iteration_unit` — so users see `"Jan\u2009\u2013\u2009Dec 2026"`, not
  `"Jan\u2009\u2013\u2009Jan 2026/2027"`. The closure happens purely at
  the display layer; the internal representation is unchanged.

  ### Calendar awareness

  The map passed to Localize carries the Tempo's `:calendar`
  field, so Localize selects the appropriate CLDR data when
  available for that calendar. Coverage of non-Gregorian calendars
  depends on Localize's CLDR data and may fall back to
  Gregorian-equivalent formatting where calendar-specific data is
  absent.

  """

  @doc """
  Format a Tempo, Interval, or IntervalSet as a locale-aware
  string.

  Delegated from `Tempo.to_string/1,2`.

  """
  @spec to_string(Tempo.t() | Tempo.Interval.t() | Tempo.IntervalSet.t(), keyword()) ::
          String.t()
  def to_string(value, options \\ [])

  def to_string(%Tempo{} = tempo, options) do
    {unit, _} = Tempo.resolution(tempo)

    if expand_as_closed_interval?(unit, tempo) do
      render_tempo_as_closed_interval(tempo, unit, options)
    else
      render_single_value(tempo, options)
    end
  end

  def to_string(%Tempo.Interval{} = interval, options) do
    {from, to} = interval_endpoints_for_format(interval)
    {from, to} = collapse_midnight_endpoints(from, to)
    closed_last = closed_last_for_interval(from, to)
    options = with_default_interval_options(options, from, closed_last)

    case format_interval(from, closed_last, options) do
      {:ok, string} -> string
      {:error, exception} -> raise exception
    end
  end

  def to_string(%Tempo.IntervalSet{} = set, options) do
    # CLDR "list separator" formatting could replace the simple
    # ", " join; deferred until Localize exposes a listPattern API.
    set
    |> Tempo.IntervalSet.to_list()
    |> Enum.map_join(", ", &to_string(&1, options))
  end

  ## ---------------------------------------------------------
  ## Closed-interval expansion for year/month Tempo values
  ## ---------------------------------------------------------

  # Rule B: year and month expand; day, hour, minute, second, and
  # non-anchored values collapse. A non-anchored Tempo has no
  # enumeration start in interval terms — we fall through to the
  # single-value path which routes to Localize.Time.
  defp expand_as_closed_interval?(:year, %Tempo{time: time}) do
    Keyword.has_key?(time, :year)
  end

  defp expand_as_closed_interval?(:month, %Tempo{time: time}) do
    Keyword.has_key?(time, :year)
  end

  defp expand_as_closed_interval?(_unit, _tempo), do: false

  # Materialise the Tempo, compute first and closed-last at the
  # iteration unit (one level finer than the Tempo's resolution),
  # then hand off to Localize.Interval.
  defp render_tempo_as_closed_interval(%Tempo{} = tempo, unit, options) do
    iter_unit = next_finer_unit(unit)

    case Tempo.to_interval(tempo) do
      {:ok, %Tempo.Interval{from: from, to: to}} ->
        first = Tempo.trunc(from, iter_unit)

        closed_last =
          to
          |> Tempo.Math.subtract(Tempo.Duration.new([{iter_unit, 1}]))
          |> Tempo.trunc(iter_unit)

        options = with_default_interval_options(options, first, closed_last)

        case format_interval(first, closed_last, options) do
          {:ok, string} -> string
          {:error, exception} -> raise exception
        end

      _other ->
        # Fall back to single-value render if materialisation
        # returned something unexpected (e.g. IntervalSet from a
        # masked value).
        render_single_value(tempo, options)
    end
  end

  defp next_finer_unit(:year), do: :month
  defp next_finer_unit(:month), do: :day
  defp next_finer_unit(:day), do: :hour
  defp next_finer_unit(:hour), do: :minute
  defp next_finer_unit(:minute), do: :second
  defp next_finer_unit(:second), do: :second

  ## ---------------------------------------------------------
  ## Single-value rendering (day, hour, minute, second, time-only)
  ## ---------------------------------------------------------

  defp render_single_value(%Tempo{} = tempo, options) do
    options = with_default_format(options, tempo)

    case dispatch(tempo, options) do
      {:ok, string} -> string
      {:error, exception} -> raise exception
    end
  end

  # Route a plain Tempo to the right Localize function based on
  # whether it's date-like, time-like, or both.
  defp dispatch(%Tempo{} = tempo, options) do
    cond do
      date_only?(tempo) ->
        Localize.Date.to_string(to_locale_map(tempo), options)

      time_only?(tempo) ->
        Localize.Time.to_string(to_locale_map(tempo), options)

      true ->
        Localize.DateTime.to_string(to_locale_map(tempo), options)
    end
  end

  # A Tempo is date-only when its time kv list contains none of
  # :hour, :minute, :second. It is time-only when it contains
  # none of :year, :month, :day (i.e. non-anchored). Otherwise
  # it's a datetime.
  defp date_only?(%Tempo{time: time}) do
    Keyword.has_key?(time, :year) and
      not (Keyword.has_key?(time, :hour) or Keyword.has_key?(time, :minute) or
             Keyword.has_key?(time, :second))
  end

  defp time_only?(%Tempo{time: time}) do
    not Keyword.has_key?(time, :year) and
      not Keyword.has_key?(time, :month) and
      not Keyword.has_key?(time, :day)
  end

  # Convert a Tempo to the map shape Localize accepts: flatten the
  # time keyword list into map keys and append the :calendar field.
  defp to_locale_map(%Tempo{time: time, calendar: calendar}) do
    time
    |> Enum.reduce(%{}, fn
      {k, v}, acc when is_integer(v) -> Map.put(acc, k, v)
      _other, acc -> acc
    end)
    |> Map.put(:calendar, calendar || Calendrical.Gregorian)
  end

  # Pick a default skeleton for single-value rendering.
  defp with_default_format(options, %Tempo{} = tempo) do
    case Keyword.has_key?(options, :format) do
      true ->
        options

      false ->
        {unit, _span} = Tempo.resolution(tempo)
        Keyword.put(options, :format, default_format_for_unit(unit, tempo))
    end
  end

  defp default_format_for_unit(:year, _tempo), do: :y
  defp default_format_for_unit(:month, _tempo), do: :yMMM
  defp default_format_for_unit(:day, _tempo), do: :medium
  defp default_format_for_unit(:hour, _tempo), do: :h
  defp default_format_for_unit(:minute, _tempo), do: :hm
  defp default_format_for_unit(:second, _tempo), do: :medium
  defp default_format_for_unit(_other, _tempo), do: :medium

  ## ---------------------------------------------------------
  ## Interval formatting helpers (shared by %Tempo{} expansion
  ## and %Tempo.Interval{})
  ## ---------------------------------------------------------

  # For a raw Interval, the closed last is `to - 1 iteration_unit`
  # where the iteration unit is the resolution of `from` (explicit
  # spans iterate at their own resolution per the architecture
  # note in CLAUDE.md).
  defp closed_last_for_interval(%Tempo{} = from, %Tempo{} = to) do
    {iter_unit, _} = Tempo.resolution(from)
    Tempo.Math.subtract(to, Tempo.Duration.new([{iter_unit, 1}]))
  end

  # When an interval's endpoints carry time-of-day components that
  # are all zero — i.e. the interval is midnight-to-midnight — the
  # time parts are materialisation artifacts rather than
  # user-chosen resolution. Trunc both endpoints to the coarsest
  # unit common to both so the rendering matches what the user
  # would see for the equivalent `%Tempo{}`. Explicit intervals
  # with non-zero time components are preserved.
  defp collapse_midnight_endpoints(%Tempo{} = from, %Tempo{} = to) do
    if midnight_endpoints?(from) and midnight_endpoints?(to) do
      target_unit = display_unit_for_midnight_pair(from, to)
      {Tempo.trunc(from, target_unit), Tempo.trunc(to, target_unit)}
    else
      {from, to}
    end
  end

  defp midnight_endpoints?(%Tempo{time: time}) do
    Keyword.get(time, :hour, 0) == 0 and
      Keyword.get(time, :minute, 0) == 0 and
      Keyword.get(time, :second, 0) == 0
  end

  # The natural display unit for a midnight-to-midnight pair is
  # the coarsest date unit both endpoints carry. If both have day,
  # use :day. If both have at least month, use :month. Otherwise
  # :year.
  defp display_unit_for_midnight_pair(%Tempo{time: from_time}, %Tempo{time: to_time}) do
    cond do
      Keyword.has_key?(from_time, :day) and Keyword.has_key?(to_time, :day) -> :day
      Keyword.has_key?(from_time, :month) and Keyword.has_key?(to_time, :month) -> :month
      true -> :year
    end
  end

  # Intervals take {:format, :style} options; the style tells
  # Localize which components to render. We pick the style from
  # the coarsest resolution among the two endpoints so a year-month
  # interval doesn't try to render an absent day.
  defp with_default_interval_options(options, %Tempo{} = from, %Tempo{} = to) do
    options
    |> Keyword.put_new(:format, :medium)
    |> Keyword.put_new(:style, interval_style_for(from, to))
  end

  defp interval_style_for(%Tempo{} = from, %Tempo{} = to) do
    {from_unit, _} = Tempo.resolution(from)
    {to_unit, _} = Tempo.resolution(to)
    coarsest = coarsest_unit(from_unit, to_unit)

    case coarsest do
      :year -> :year_and_month
      :month -> :year_and_month
      :day -> :date
      _time_component -> :date
    end
  end

  @unit_order_ctf [:year, :month, :day, :hour, :minute, :second]

  defp coarsest_unit(a, b) do
    i_a = Enum.find_index(@unit_order_ctf, &(&1 == a)) || 0
    i_b = Enum.find_index(@unit_order_ctf, &(&1 == b)) || 0
    Enum.at(@unit_order_ctf, min(i_a, i_b))
  end

  # Year-resolution intervals don't render well through
  # Localize.Interval (the patterns assume at least month). Format
  # each endpoint with the `:y` skeleton and join with the
  # thin-space en-dash CLDR uses for interval ranges.
  #
  # For all other resolutions, delegate to Localize.Interval which
  # handles date-, hour-, minute-, and second-level endpoints and
  # collapses the degenerate (from == to) case natively.
  defp format_interval(%Tempo{} = from, %Tempo{} = to, options) do
    {from_unit, _} = Tempo.resolution(from)
    {to_unit, _} = Tempo.resolution(to)

    if from_unit == :year and to_unit == :year do
      format_year_only_interval(from, to, options)
    else
      Localize.Interval.to_string(to_locale_map(from), to_locale_map(to), options)
    end
  end

  defp format_year_only_interval(%Tempo{} = from, %Tempo{} = to, options) do
    year_opts =
      options
      |> Keyword.put(:format, :y)
      |> Keyword.drop([:style])

    with {:ok, from_str} <- Localize.Date.to_string(to_locale_map(from), year_opts),
         {:ok, to_str} <- Localize.Date.to_string(to_locale_map(to), year_opts) do
      if from_str == to_str do
        {:ok, from_str}
      else
        {:ok, from_str <> "\u2009\u2013\u2009" <> to_str}
      end
    end
  end

  # Extract {from, to} from an interval for formatting. A plain
  # pair of endpoints is enough for Localize.Interval; recurrence
  # / duration-only intervals would need materialisation first and
  # are out of scope for this dispatcher.
  defp interval_endpoints_for_format(%Tempo.Interval{from: %Tempo{} = from, to: %Tempo{} = to}) do
    {from, to}
  end

  defp interval_endpoints_for_format(%Tempo.Interval{} = interval) do
    case Tempo.Interval.endpoints(interval) do
      {%Tempo{} = from, %Tempo{} = to} ->
        {from, to}

      _other ->
        raise ArgumentError,
              "Tempo.Format.to_string/2 requires an interval with concrete " <>
                "endpoints. Materialise recurrence/duration-only intervals via " <>
                "`Tempo.to_interval/1,2` first."
    end
  end
end
