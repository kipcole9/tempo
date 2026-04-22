defmodule Tempo.Select do
  @moduledoc """
  Narrow a Tempo span by a selector — the composition primitive
  for "workdays of June", "the 15th of every month", "every
  Dec 25 in the next decade", and user-supplied holidays.

  ```elixir
  Tempo.select(~o"2026-06", Tempo.workdays(:US))  # workdays of June — locale-aware
  Tempo.select(~o"2026-06", Tempo.weekend(:US))   # weekend days of June
  Tempo.select(~o"2026", [1, 15])
  Tempo.select(~o"2026", ~o"12-25")
  Tempo.select(~o"2026", ~o"10O")     # ISO 8601-2 ordinal day — the 10th day of 2026
  Tempo.select(~o"2026-06", ~o"5K")   # ISO 8601-2 day-of-week — every Friday in June 2026
  Tempo.select(~o"2026", &my_holidays/1)
  ```

  Every call returns `{:ok, %Tempo.IntervalSet{}}` (or
  `{:error, reason}`), consistent with the other set-algebra
  operations — the result composes directly into
  `Tempo.union/2`, `Tempo.intersection/2`, `Tempo.difference/2`.

  `Tempo.select/2` is a **pure function**. It has no `opts`, no
  ambient locale read, no implicit territory resolution. Every
  input that can affect the result is a value on the selector.
  Locale-dependent constraints like "workdays" or "weekend" are
  constructed by `Tempo.workdays/1` and `Tempo.weekend/1` (which
  read the locale once at construction time) and composed in:

      interval
      |> Tempo.select(Tempo.workdays(:US))

  That means the `workdays(:US)` call is where territory
  resolution happens — **not** inside `select/2` — and the
  resulting value is safe to capture anywhere, including
  module attributes.

  ## Selector shapes

  | Shape | Example | Meaning |
  | ----- | ------- | ------- |
  | `[integer]` / `Range` | `Tempo.select(m, [1, 15])` | Integer indices applied at base's next-finer unit |
  | `%Tempo{}` or list | `Tempo.select(y, ~o"12-25")` | Project the constraint's specified units onto the base |
  | `%Tempo{day_of_week: …}` | `Tempo.select(m, ~o"5K")` | Day-of-week pattern — every matching weekday in the base (ISO 8601-2 `K` suffix) |
  | `%Tempo{day_of_week: [...]}` | `Tempo.select(m, Tempo.workdays(:US))` | Day-of-week list — every matching weekday in the base |
  | `%Tempo{day: N}` (ordinal) | `Tempo.select(y, ~o"10O")` | Ordinal day in the year — the Nth day (ISO 8601-2 `O` suffix) |
  | `%Tempo.Interval{}` or list | `Tempo.select(y, vacation)` | Same, for explicit intervals |
  | Function | `Tempo.select(y, &fn/1)` | The function returns any of the above; evaluated against the base |

  Base can be a `t:Tempo.t/0`, `t:Tempo.Interval.t/0`, or
  `t:Tempo.IntervalSet.t/0`. IntervalSet bases flat-map the
  selector across each member and collect the results.

  """

  alias Tempo.Interval
  alias Tempo.IntervalSet

  @type selector ::
          [integer()]
          | Range.t()
          | Tempo.t()
          | Interval.t()
          | [Tempo.t() | Interval.t()]
          | (base() -> selector())

  @type base :: Tempo.t() | Interval.t() | IntervalSet.t()

  @doc """
  Narrow `base` by `selector`, returning the selected intervals
  as a `t:Tempo.IntervalSet.t/0`.

  See the module doc for the selector vocabulary and runtime-
  resolution caveats.

  ### Supported base shapes

  `base` can be any Tempo value that materialises to an Interval
  or IntervalSet. Grouped and masked forms have their endpoints
  resolved to concrete values before the selector runs, so every
  ISO 8601-2 shape composes with every selector:

  | Base shape | Example | Materialises to |
  | ---------- | ------- | --------------- |
  | Scalar `%Tempo{}` | `~o"2026-06"` | single Interval |
  | Explicit Interval | `~o"2026-07/2026-10"` | single Interval |
  | IntervalSet | output of `Tempo.union/2` etc. | IntervalSet (flat-mapped) |
  | Quarter (`NQ`) | `~o"2026Y3Q"` | single Interval (group resolved) |
  | Season (codes 25–32) | `~o"2026Y26M"` | Interval bounded by equinox/solstice |
  | Month/day range in a slot | `~o"2026Y{6..8}M"` | IntervalSet of three members |
  | Stepped range | `~o"2026Y{1..-1//3}M"` | IntervalSet of disjoint members |
  | Archaeological mask | `~o"156X"` | decade-long Interval |

  Example with a quarter base:

      Tempo.select(~o"2026Y3Q", Tempo.workdays(:US))
      #=> {:ok, IntervalSet with 66 members — workdays of Q3 2026}

  ### Examples

      iex> {:ok, set} = Tempo.Select.select(~o"2026-02", [1, 15])
      iex> Enum.map(Tempo.IntervalSet.to_list(set), & &1.from.time[:day])
      [1, 15]

      iex> {:ok, set} = Tempo.Select.select(~o"2026", ~o"12-25")
      iex> [xmas] = Tempo.IntervalSet.to_list(set)
      iex> xmas.from.time
      [year: 2026, month: 12, day: 25]

      iex> {:ok, set} = Tempo.Select.select(~o"2026", ~o"10O")
      iex> [day10] = Tempo.IntervalSet.to_list(set)
      iex> {day10.from.time[:month], day10.from.time[:day]}
      {1, 10}

      iex> {:ok, set} = Tempo.Select.select(~o"2026-06", ~o"5K")
      iex> set |> Tempo.IntervalSet.to_list() |> Enum.map(& &1.from.time[:day])
      [5, 12, 19, 26]

      iex> {:ok, set} = Tempo.Select.select(~o"2026-02", Tempo.workdays(:US))
      iex> Tempo.IntervalSet.count(set)
      20

  """
  @spec select(base(), selector()) ::
          {:ok, IntervalSet.t()} | {:error, term()}

  # ---- IntervalSet base: flat-map then reassemble ----

  def select(%IntervalSet{} = set, selector) do
    set
    |> IntervalSet.to_list()
    |> Enum.reduce_while({:ok, []}, fn member, {:ok, acc} ->
      case select(member, selector) do
        {:ok, %IntervalSet{intervals: ivs}} -> {:cont, {:ok, acc ++ ivs}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, all} -> IntervalSet.new(all, coalesce: false)
      err -> err
    end
  end

  # ---- Tempo base: materialise to interval, recurse ----
  #
  # For integer-index selectors we need the ORIGINAL resolution
  # (before `to_interval` fills lower-bound units), so route
  # integer / range selectors through a dedicated path.

  def select(%Tempo{} = tempo, %Range{} = range) do
    select(tempo, Enum.to_list(range))
  end

  def select(%Tempo{} = tempo, [head | _] = indices) when is_integer(head) do
    select_indices_on_tempo(tempo, indices)
  end

  def select(%Tempo{} = tempo, selector) do
    case Tempo.to_interval(tempo) do
      {:ok, %Interval{} = iv} -> select(resolve_grouped_endpoints(iv), selector)
      {:ok, %IntervalSet{} = set} -> select(set, selector)
      {:error, _} = err -> err
    end
  end

  # ---- Empty selector list — explicit short-circuit ----

  def select(%Interval{} = _base, []) do
    IntervalSet.new([], coalesce: false)
  end

  # ---- Range: expand to integer list ----

  def select(%Interval{} = base, %Range{} = range) do
    select(base, Enum.to_list(range))
  end

  # ---- Integer list: indices at next-finer unit ----

  def select(%Interval{} = base, [head | _] = indices) when is_integer(head) do
    select_indices(base, indices)
  end

  # ---- Tempo / Interval projection (single or list) ----

  def select(%Interval{} = base, %Tempo{} = tempo) do
    select(base, [tempo])
  end

  def select(%Interval{} = base, %Interval{} = iv) do
    select(base, [iv])
  end

  def select(%Interval{} = base, [%Tempo{} | _] = tempos) do
    select_projections(base, tempos)
  end

  def select(%Interval{} = base, [%Interval{} | _] = intervals) do
    select_projections(base, intervals)
  end

  # ---- Function: evaluate, recurse on the result ----

  def select(%Interval{} = base, fun) when is_function(fun, 1) do
    select(base, fun.(base))
  end

  # ---- Catch-all: clearer error ----

  def select(base, selector) do
    {:error,
     ArgumentError.exception(
       "Tempo.Select.select/2 does not recognise selector #{inspect(selector)} " <>
         "for base #{inspect(base)}. See `Tempo.Select` moduledoc for the " <>
         "selector vocabulary."
     )}
  end

  ## -----------------------------------------------------------
  ## Weekday filter — consumed by the day-of-week-only projection
  ## path (see `project_onto_base/2` below)
  ## -----------------------------------------------------------

  # Walk `base` day-by-day, keeping dates whose ISO day-of-week
  # (Monday=1) is in the requested set. Returns an IntervalSet of
  # day-resolution intervals.
  defp filter_by_weekdays(%Interval{from: %Tempo{} = from, to: %Tempo{} = to}, weekdays) do
    calendar = from.calendar

    intervals =
      stream_days(from, to, calendar)
      |> Stream.filter(fn {y, m, d} ->
        dow_of(calendar, y, m, d) in weekdays
      end)
      |> Enum.map(fn {y, m, d} -> day_interval(calendar, y, m, d, from) end)

    IntervalSet.new(intervals, coalesce: false)
  end

  defp filter_by_weekdays(%Interval{} = interval, _weekdays) do
    {:error,
     Tempo.IntervalEndpointsError.exception(
       interval: interval,
       operation: :select_weekdays,
       reason: "Cannot select weekdays across an open-ended interval."
     )}
  end

  defp stream_days(from, to, calendar) do
    with {:ok, start_date} <- tempo_to_date(from, calendar),
         {:ok, end_date} <- tempo_to_date(to, calendar) do
      total = Date.diff(end_date, start_date)

      Stream.unfold(0, fn i ->
        if i < total do
          d = Date.add(start_date, i)
          {{d.year, d.month, d.day}, i + 1}
        else
          nil
        end
      end)
    else
      _ -> []
    end
  end

  defp tempo_to_date(%Tempo{time: time, calendar: calendar}, calendar) do
    with year when is_integer(year) <- Keyword.get(time, :year),
         month when is_integer(month) <- Keyword.get(time, :month, 1),
         day when is_integer(day) <- Keyword.get(time, :day, 1) do
      Date.new(year, month, day, calendar)
    else
      _ -> :error
    end
  end

  defp dow_of(calendar, y, m, d) do
    case calendar.day_of_week(y, m, d, :monday) do
      {dow, _first, _last} when is_integer(dow) -> dow
      dow when is_integer(dow) -> dow
      _ -> nil
    end
  end

  defp day_interval(calendar, y, m, d, source_from) do
    from_tempo = build_day_tempo(source_from, y, m, d, calendar)

    next = day_after(y, m, d, calendar)
    to_tempo = build_day_tempo(source_from, next.year, next.month, next.day, calendar)

    %Interval{from: from_tempo, to: to_tempo}
  end

  defp day_after(y, m, d, calendar) do
    {:ok, date} = Date.new(y, m, d, calendar)
    Date.add(date, 1)
  end

  defp build_day_tempo(%Tempo{} = source, y, m, d, calendar) do
    %Tempo{source | time: [year: y, month: m, day: d], calendar: calendar}
  end

  ## -----------------------------------------------------------
  ## Integer-index selector — apply indices at next-finer unit
  ## -----------------------------------------------------------
  ##
  ## The base_unit must be the declared resolution of the SPAN,
  ## not the resolution of the from-endpoint. `Tempo.to_interval/1`
  ## fills a from-endpoint like `[year: 2026, month: 2]` down to
  ## `[year: 2026, month: 2, day: 1]`, so asking `Tempo.resolution/1`
  ## of that endpoint would wrongly say `:day`. The span itself
  ## `[2026-02-01, 2026-03-01)` ticks forward at the month — that
  ## is the authoritative resolution for the "next finer unit"
  ## derivation.

  defp select_indices(%Interval{from: %Tempo{} = from} = base, indices) do
    base_unit = Interval.resolution(base)
    truncated_time = truncate_to_unit(from.time, base_unit)
    select_indices_at(from, truncated_time, base_unit, indices)
  end

  defp select_indices_on_tempo(%Tempo{} = tempo, indices) do
    {base_unit, _} = Tempo.resolution(tempo)
    select_indices_at(tempo, tempo.time, base_unit, indices)
  end

  defp select_indices_at(%Tempo{calendar: calendar} = source, base_time, base_unit, indices) do
    case Tempo.Iso8601.Unit.implicit_enumerator(base_unit, calendar) do
      nil ->
        {:error,
         "Cannot select indices under #{inspect(base_unit)} — no finer unit is " <>
           "defined for that resolution."}

      {next_unit, _range} ->
        intervals =
          indices
          |> Enum.map(fn idx -> project_index(source, base_time, next_unit, idx) end)
          |> Enum.reject(&is_nil/1)

        IntervalSet.new(intervals, coalesce: false)
    end
  end

  defp project_index(%Tempo{} = source, base_time, unit, idx) do
    new_time = base_time ++ [{unit, idx}]
    new_tempo = %Tempo{source | time: new_time}

    case Tempo.to_interval(new_tempo) do
      {:ok, %Interval{} = iv} -> iv
      {:ok, %IntervalSet{intervals: [iv | _]}} -> iv
      _ -> nil
    end
  end

  # Keep entries from head until (and including) `unit`. Anything
  # finer-grained is dropped — we're about to replace it with the
  # selected index at the next unit down.
  defp truncate_to_unit(time, unit) do
    {coarser, rest} = Enum.split_while(time, fn {u, _} -> u != unit end)

    case rest do
      [{^unit, _} = entry | _] -> coarser ++ [entry]
      [] -> coarser
    end
  end

  ## -----------------------------------------------------------
  ## Projection selector — merge constraint's units onto base
  ## -----------------------------------------------------------

  defp select_projections(%Interval{} = base, constraints) do
    constraints
    |> Enum.reduce_while({:ok, []}, fn c, {:ok, acc} ->
      case project_onto_base(base, c) do
        {:error, _} = err -> {:halt, err}
        list when is_list(list) -> {:cont, {:ok, acc ++ Enum.reject(list, &is_nil/1)}}
        nil -> {:cont, {:ok, acc}}
        other -> {:cont, {:ok, acc ++ List.wrap(other)}}
      end
    end)
    |> case do
      {:ok, intervals} -> IntervalSet.new(intervals, coalesce: false)
      {:error, _} = err -> err
    end
  end

  # Merge a constraint Tempo's time units onto base's from-endpoint
  # — units specified on the constraint take precedence; others
  # inherit from base. Then materialise and intersect with base.
  #
  # A day-of-week-only constraint (`~o"5K"` for "Friday", or
  # `Tempo.workdays(:US)` — `day_of_week: [1, 2, 3, 4, 5]`) is
  # a recurring pattern rather than a specific date, so it routes
  # to the weekday filter instead of the merge-and-materialise
  # path.
  defp project_onto_base(%Interval{} = base, %Tempo{time: c_time}) do
    case day_of_week_only(c_time) do
      {:ok, weekdays} ->
        case filter_by_weekdays(base, weekdays) do
          {:ok, %IntervalSet{intervals: ivs}} -> ivs
          {:error, _} = err -> err
        end

      :no ->
        project_merge(base, c_time)
    end
  end

  defp project_onto_base(%Interval{} = base, %Interval{from: %Tempo{} = c_from}) do
    # For an Interval constraint, project using its from-endpoint.
    # Extending to preserve the constraint's own span is a v2 concern.
    project_onto_base(base, c_from)
  end

  defp project_merge(%Interval{from: %Tempo{} = base_from} = base, c_time) do
    base_time = base_from.time

    merged_time =
      base_time
      |> Enum.map(fn {unit, value} -> {unit, Keyword.get(c_time, unit, value)} end)
      |> Kernel.++(Enum.reject(c_time, fn {unit, _} -> Keyword.has_key?(base_time, unit) end))
      |> trim_finer_than_constraint(c_time)

    merged = %Tempo{base_from | time: merged_time}

    case Tempo.to_interval(merged) do
      {:ok, %Interval{} = iv} ->
        intersect_with_base(trim_iv_to_constraint(iv, c_time), base)

      {:ok, %IntervalSet{intervals: ivs}} ->
        Enum.map(ivs, &intersect_with_base(trim_iv_to_constraint(&1, c_time), base))

      _ ->
        nil
    end
  end

  # After materialisation, `Tempo.to_interval/1` may pad the
  # endpoints with `hour: 0` (the natural start-of-day representation
  # of a day-resolution span). For selector results we want the
  # endpoint time to match the constraint's resolution exactly —
  # a `~o"12-25"` projection should read as day-shaped, not
  # hour-shaped. Trim both endpoints to the constraint's finest
  # unit.
  defp trim_iv_to_constraint(%Interval{from: %Tempo{} = from, to: %Tempo{} = to} = iv, c_time) do
    %{
      iv
      | from: %{from | time: trim_finer_than_constraint(from.time, c_time)},
        to: %{to | time: trim_finer_than_constraint(to.time, c_time)}
    }
  end

  defp trim_iv_to_constraint(iv, _c_time), do: iv

  # The projection's natural resolution is the finest unit the
  # CONSTRAINT specifies — `~o"12-25"` means "a day" (finest unit
  # :day), `~o"12-25T14:30"` means "a minute". Anything finer
  # carried through from the base's materialisation is dropped
  # so the result is shaped at the constraint's resolution.
  defp trim_finer_than_constraint(time, c_time) do
    case finest_unit(c_time) do
      nil -> time
      finest -> Enum.take_while(time, fn {unit, _} -> not finer_than?(unit, finest) end)
    end
  end

  @unit_order_coarse_to_fine [
    :year,
    :month,
    :week,
    :day,
    :day_of_year,
    :day_of_week,
    :hour,
    :minute,
    :second
  ]

  defp finest_unit(time) do
    time
    |> Keyword.keys()
    |> Enum.reverse()
    |> Enum.find(&(&1 in @unit_order_coarse_to_fine))
  end

  defp finer_than?(a, b) do
    i_a = Enum.find_index(@unit_order_coarse_to_fine, &(&1 == a))
    i_b = Enum.find_index(@unit_order_coarse_to_fine, &(&1 == b))
    not is_nil(i_a) and not is_nil(i_b) and i_a > i_b
  end

  # A constraint is "day-of-week-only" when its :time keyword list
  # has a `:day_of_week` entry (scalar integer or list) and no
  # date-axis key (`:year`, `:month`, `:day`, `:week`).
  defp day_of_week_only(c_time) do
    case Keyword.get(c_time, :day_of_week) do
      nil ->
        :no

      dow ->
        if Enum.any?([:year, :month, :day, :week], &Keyword.has_key?(c_time, &1)) do
          :no
        else
          {:ok, List.wrap(dow)}
        end
    end
  end

  defp intersect_with_base(%Interval{from: %Tempo{} = from} = iv, %Interval{
         from: %Tempo{} = bf,
         to: %Tempo{} = bt
       }) do
    case Tempo.Compare.compare_endpoints(from, bf) do
      :earlier ->
        nil

      _ ->
        case Tempo.Compare.compare_endpoints(from, bt) do
          r when r in [:earlier, :same] -> iv
          _ -> nil
        end
    end
  end

  defp intersect_with_base(_, _), do: nil

  ## ---------------------------------------------------------
  ## Grouped-endpoint resolution
  ## ---------------------------------------------------------

  # Some AST shapes — notably the ISO 8601-2 quarter designator
  # (`~o"2026Y3Q"`) — materialise into an Interval whose `:from`
  # endpoint still carries a `{:group, range}` value for one of
  # its time units. Downstream selectors (`filter_by_weekdays`,
  # integer-index selection) expect concrete integer units.
  #
  # When we find a group on `from`, resolve both endpoints from
  # the group's range:
  #
  #   * `from`  gets the group's FIRST element (the concrete start).
  #   * `to`    is rebuilt from `from`'s time with the grouped unit
  #             replaced by `group.last + 1` — the exclusive
  #             upper bound under the half-open convention.
  #
  # This replaces whatever `to` value `to_interval/1` previously
  # produced for the quarter case, which advances past the span
  # (a known quirk for the quarter designator). For other AST
  # shapes — seasons, range-in-slot, masks — `to_interval/1`
  # already produces concrete endpoints and `from` has no group,
  # so this helper is a no-op.
  defp resolve_grouped_endpoints(%Interval{from: %Tempo{time: from_time} = from, to: to} = iv) do
    case find_group(from_time) do
      {unit, %Range{first: first, last: last}} ->
        resolved_from = %{from | time: Keyword.replace(from_time, unit, first)}
        resolved_to_time = Keyword.replace(from_time, unit, last + 1)
        resolved_to = %{from | time: resolved_to_time}
        %{iv | from: resolved_from, to: merge_to_calendar(resolved_to, to)}

      nil ->
        iv
    end
  end

  defp resolve_grouped_endpoints(other), do: other

  defp find_group(time) do
    Enum.find_value(time, fn
      {unit, {:group, range}} -> {unit, range}
      _ -> nil
    end)
  end

  # Preserve calendar/extended/shift from the original `to`
  # endpoint where available; only the :time list is rebuilt.
  defp merge_to_calendar(%Tempo{} = new_to, %Tempo{} = old_to) do
    %{new_to | calendar: old_to.calendar, extended: old_to.extended, shift: old_to.shift}
  end

  defp merge_to_calendar(new_to, _), do: new_to
end
