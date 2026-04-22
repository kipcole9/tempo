defmodule Tempo.Interval do
  @moduledoc """
  An explicit bounded span on the time line.

  Every Tempo value *is* an interval at some resolution; a bare
  `%Tempo{}` materialises to an `%Tempo.Interval{}` via
  `Tempo.to_interval/1`. `%Tempo.Interval{}` carries explicit
  `from` and `to` endpoints plus optional recurrence metadata
  (`recurrence`, `duration`, `repeat_rule`) for RRULE-style
  values.

  Tempo uses the half-open `[from, to)` convention: `from` is
  inclusive, `to` is exclusive. Adjacent intervals concatenate
  cleanly — `[a, b) ++ [b, c) == [a, c)`.

  ## Comparing intervals

  `compare/2` classifies two intervals by Allen's interval
  algebra, returning one of 13 mutually-exclusive relations.
  See the function docs for the full table.

  """

  alias Tempo.Compare
  alias Tempo.Duration
  alias Tempo.IntervalSet
  alias Tempo.Math
  alias Tempo.Iso8601.Unit

  @type t :: %__MODULE__{
          recurrence: pos_integer() | :infinity,
          direction: 1 | -1,
          from: Tempo.t() | Tempo.Duration.t() | :undefined | nil,
          to: Tempo.t() | :undefined | nil,
          duration: Tempo.Duration.t() | nil,
          repeat_rule: Tempo.t() | nil,
          metadata: map()
        }

  @typedoc """
  One of Allen's 13 interval relations — jointly exhaustive and
  pairwise disjoint under the half-open `[from, to)` convention.
  """
  @type relation ::
          :precedes
          | :meets
          | :overlaps
          | :finished_by
          | :contains
          | :starts
          | :equals
          | :started_by
          | :during
          | :finishes
          | :overlapped_by
          | :met_by
          | :preceded_by

  @typedoc """
  Anything `compare/2` can reduce to a single bounded interval.
  """
  @type interval_like :: Tempo.t() | t() | IntervalSet.t()

  defstruct recurrence: 1,
            direction: 1,
            from: nil,
            to: nil,
            duration: nil,
            repeat_rule: nil,
            metadata: %{}

  # Clause ordering matters. The `:recurrence` peeler is the first
  # defence — it strips a leading recurrence token and recurses so
  # every other clause can ignore recurrence entirely.
  #
  # After that, clauses that reference the literal `:duration` tag
  # must come *before* any clause using a wildcard in the same
  # position, otherwise the wildcard clause will swallow duration
  # tokens and mis-classify them as dates.
  #
  # The tokenizer emits dates as one of `:date`, `:datetime`, or
  # `:time_of_day`; durations as `:duration`; undefined endpoints
  # as the atom `:undefined`. All of the following clauses
  # collectively cover every combination the tokenizer can produce.

  ## Recurrence peeler

  def new([{:recurrence, recur} | rest]) do
    rest
    |> new()
    |> Map.put(:recurrence, recur)
  end

  ## Two-element forms: undefined endpoints

  def new([:undefined, :undefined]) do
    %__MODULE__{from: :undefined, to: :undefined}
  end

  def new([{_from_tag, time}, :undefined]) do
    %__MODULE__{from: Tempo.new(time), to: :undefined}
  end

  def new([:undefined, {_to_tag, time}]) do
    %__MODULE__{from: :undefined, to: Tempo.new(time)}
  end

  ## Two-element forms with a duration (must precede the
  ## wildcard date/date clause below).

  def new([{:duration, duration}, {_to_tag, time}]) do
    %__MODULE__{from: :undefined, duration: Duration.new(duration), to: Tempo.new(time)}
  end

  def new([{_from_tag, time}, {:duration, duration}]) do
    %__MODULE__{from: Tempo.new(time), duration: Duration.new(duration)}
  end

  ## Two-element date/date form (wildcard; must be last among
  ## two-element clauses).

  def new([{_from_tag, from}, {_to_tag, to}]) do
    %__MODULE__{from: Tempo.new(from), to: Tempo.new(to)}
  end

  ## Three-element forms with a repeat_rule.

  def new([{:duration, duration}, {_to_tag, to}, {:repeat_rule, repeat_rule}]) do
    %__MODULE__{
      from: :undefined,
      to: Tempo.new(to),
      duration: Duration.new(duration),
      repeat_rule: Tempo.new(repeat_rule)
    }
  end

  def new([{_from_tag, from}, {:duration, duration}, {:repeat_rule, repeat_rule}]) do
    %__MODULE__{
      from: Tempo.new(from),
      duration: Duration.new(duration),
      repeat_rule: Tempo.new(repeat_rule)
    }
  end

  def new([{_from_tag, from}, {_to_tag, to}, {:repeat_rule, repeat_rule}]) do
    %__MODULE__{
      from: Tempo.new(from),
      to: Tempo.new(to),
      repeat_rule: Tempo.new(repeat_rule)
    }
  end

  ## Implicit → explicit materialisation
  ##
  ## `Tempo.to_interval/1` is the public entry point; the heavy
  ## lifting lives here so the logic is testable in isolation and
  ## stays close to the struct it produces.

  @doc """
  Given a fully-resolved `%Tempo{}`, compute the two endpoints of
  its implicit span under the half-open `[from, to)` convention.

  Returns `{:ok, {lower, upper}}` where both are `%Tempo{}` values,
  or `{:error, reason}` when the input has no finer unit that could
  produce a bounded span (e.g. a fully-specified second-resolution
  datetime).

  The lower bound is the input's time extended with the minimum of
  the next-finer unit (so `[year: 2022]` becomes `[year: 2022,
  month: 1]` on a month-based calendar). The upper bound is the
  lower bound incremented by one unit at the input's own resolution,
  carrying via the calendar module. Masked values widen to the
  coarsest un-masked prefix and use the internal mask-bounds
  helper to determine the enclosing span.

  """
  def next_unit_boundary(%Tempo{time: time, calendar: calendar} = tempo) do
    case masked_widening(time) do
      {:ok, {lower_time, upper_time}} ->
        {:ok, build_bounds(tempo, lower_time, upper_time)}

      {:widen, prefix, unit} ->
        upper_time = Math.add_unit(prefix, unit, calendar)
        {:ok, build_bounds(tempo, prefix, upper_time)}

      {:error, _} = err ->
        err

      :no_mask ->
        concrete_boundary(tempo, calendar)
    end
  end

  # Concrete (non-masked) path: drill to the implicit-enumerator unit
  # for the lower bound, then add one unit at the input's resolution
  # for the upper bound.

  defp concrete_boundary(%Tempo{time: time, calendar: calendar} = tempo, calendar) do
    {unit, _span} = Tempo.resolution(tempo)

    case Unit.implicit_enumerator(unit, calendar) do
      nil ->
        {:error, Tempo.MaterialisationError.exception(value: tempo, reason: :finest_resolution)}

      {next_unit, range} ->
        lower_time = time ++ [{next_unit, range_first(range)}]
        upper_time = Math.add_unit(lower_time, unit, calendar)
        {:ok, build_bounds(tempo, lower_time, upper_time)}
    end
  end

  # A `Range` supplied by `Unit.implicit_enumerator/2` — we take
  # its first value as the unit's start-of-span.
  defp range_first(%Range{first: first}), do: first

  # Mask path: scan the time list for the first masked unit.
  # The rule:
  #
  # * If the first masked unit is `:year` (the only unit whose
  #   mask-bounds translate directly to an integer range — every
  #   digit position contributes a power of ten), use the mask
  #   bounds. Honour `[:negative | …]` by flipping sign.
  #
  # * If the first masked unit is ANY OTHER unit (`:month`,
  #   `:day`, `:week`, etc.), the mask doesn't map cleanly to the
  #   unit's valid range (a two-digit `XX` month mask nominally
  #   spans `00..99`, but only `01..12` are valid). In that case we
  #   widen to the PARENT — take the un-masked prefix as the lower
  #   bound and increment it at the coarsest stated unit. This
  #   matches the plan's "widest enclosing bound" rule:
  #   `1985-XX-XX` → `[1985, 1986)`.

  defp masked_widening(time) do
    case find_first_mask(time, []) do
      nil -> :no_mask
      {prefix, :year, mask} -> year_mask_bounds(prefix, mask)
      {prefix, _unit, _mask} -> parent_widen(prefix)
    end
  end

  defp find_first_mask([], _acc), do: nil

  defp find_first_mask([{unit, {:mask, mask}} | _rest], acc) do
    {Enum.reverse(acc), unit, mask}
  end

  defp find_first_mask([entry | rest], acc) do
    find_first_mask(rest, [entry | acc])
  end

  # Year mask — both positive and negative.
  # Positive: `[1, 5, 6, :X]` → magnitude range `(1560, 1569)` → interval `[1560, 1570)`.
  # Negative: `[:negative, 1, :X, :X, :X]` → magnitude `(1000, 1999)` →
  #           signed values range from -1999 (most negative) to -1000
  #           (least negative), half-open upper = -999.
  defp year_mask_bounds([], [:negative | digits]) do
    {mag_min, mag_max} = Tempo.Mask.mask_bounds(digits)
    {:ok, {[year: -mag_max], [year: -mag_min + 1]}}
  end

  defp year_mask_bounds([], digits) do
    {min, max} = Tempo.Mask.mask_bounds(digits)
    {:ok, {[year: min], [year: max + 1]}}
  end

  # A year mask appearing after some prefix doesn't make sense in
  # ISO 8601 — year is the coarsest unit. We leave it as a noop
  # rather than crash; callers will see the original time unchanged.
  defp year_mask_bounds(_prefix, _mask), do: :no_mask

  # Widen to the parent: use the un-masked prefix as the lower
  # bound, increment the coarsest stated unit for the upper bound.
  # `1985-XX-XX` → prefix `[year: 1985]` → `[[year: 1985], [year: 1986]]`.
  defp parent_widen([]) do
    # No un-masked prefix — nothing to anchor against. Shouldn't
    # happen in practice (the parser always resolves a year before
    # finer units can appear), but raise a clear error if it does.
    {:error,
     "Cannot materialise a masked Tempo with no un-masked coarser unit — " <>
       "nothing to anchor the span against."}
  end

  defp parent_widen(prefix) do
    # Use the LAST (finest) un-masked unit as the span's unit.
    {unit, _value} = List.last(prefix)
    # Resolve any inner ranges/masks we might not have caught — not
    # expected here, but if the prefix contains non-scalar values
    # we can't increment cleanly. Pull out just the scalar case.
    if Enum.all?(prefix, fn {_u, v} -> is_integer(v) end) do
      # We need a calendar to call add_unit. Embed the increment
      # inside the outer next_unit_boundary flow — signal via a
      # shape that the caller then materialises with the source
      # tempo's calendar.
      {:widen, prefix, unit}
    else
      {:error,
       "Cannot materialise a masked Tempo whose un-masked prefix contains ranges, " <>
         "selections, or other non-scalar values."}
    end
  end

  defp build_bounds(%Tempo{} = source, lower_time, upper_time) do
    lower = %{source | time: lower_time}
    upper = %{source | time: upper_time}
    {lower, upper}
  end

  ## ----------------------------------------------------------
  ## Allen's interval algebra
  ## ----------------------------------------------------------

  @doc """
  Classify the Allen relation between two interval-like values.

  For intervals `X = [x₁, x₂)` and `Y = [y₁, y₂)` under Tempo's
  half-open convention:

  | Relation          | Shape (X relative to Y)          | Condition                      |
  | ----------------- | -------------------------------- | ------------------------------ |
  | `:precedes`       | X ends strictly before Y starts  | `x₂ < y₁`                      |
  | `:meets`          | X ends exactly at Y's start      | `x₂ = y₁`                      |
  | `:overlaps`       | X starts before Y, ends inside   | `x₁ < y₁ < x₂ < y₂`            |
  | `:finished_by`    | X contains Y, shared end         | `x₁ < y₁ ∧ x₂ = y₂`            |
  | `:contains`       | X strictly contains Y            | `x₁ < y₁ ∧ x₂ > y₂`            |
  | `:starts`         | Shared start, X ends earlier     | `x₁ = y₁ ∧ x₂ < y₂`            |
  | `:equals`         | Identical endpoints              | `x₁ = y₁ ∧ x₂ = y₂`            |
  | `:started_by`     | Shared start, X ends later       | `x₁ = y₁ ∧ x₂ > y₂`            |
  | `:during`         | X strictly inside Y              | `x₁ > y₁ ∧ x₂ < y₂`            |
  | `:finishes`       | X starts after Y, shared end     | `x₁ > y₁ ∧ x₂ = y₂`            |
  | `:overlapped_by`  | Y starts before X, ends inside X | `y₁ < x₁ < y₂ < x₂`            |
  | `:met_by`         | X starts exactly at Y's end      | `x₁ = y₂`                      |
  | `:preceded_by`    | X starts strictly after Y's end  | `x₁ > y₂`                      |

  Every pair of non-empty bounded intervals stands in exactly
  one of these relations.

  ### Arguments

  * `a` and `b` are each one of:

    * a `t:Tempo.t/0` point (materialised via its implicit span).

    * a `t:Tempo.Interval.t/0`.

    * a `t:Tempo.IntervalSet.t/0` with exactly one member.

  ### Returns

  * One of the 13 relation atoms.

  * `{:error, reason}` when either operand is a multi-member
    IntervalSet, an open-ended interval, or otherwise can't be
    reduced to a single bounded interval. For multi-member
    sets use `Tempo.IntervalSet.relation_matrix/2`.

  ### Examples

      iex> a = %Tempo.Interval{from: ~o"2026-06-01", to: ~o"2026-06-10"}
      iex> b = %Tempo.Interval{from: ~o"2026-06-05", to: ~o"2026-06-15"}
      iex> Tempo.Interval.compare(a, b)
      :overlaps

      iex> Tempo.Interval.compare(~o"2026Y", ~o"2026-06-15")
      :contains

  """
  @spec compare(interval_like(), interval_like()) :: relation() | {:error, term()}
  def compare(a, b) do
    with {:ok, iv_a} <- to_single_interval(a, :a),
         {:ok, iv_b} <- to_single_interval(b, :b) do
      classify(iv_a, iv_b)
    end
  end

  @doc """
  The inverse Allen relation.

  If `compare(a, b)` returns `r`, then `compare(b, a)` returns
  `inverse_relation(r)`.

  ### Examples

      iex> Tempo.Interval.inverse_relation(:contains)
      :during

      iex> Tempo.Interval.inverse_relation(:precedes)
      :preceded_by

      iex> Tempo.Interval.inverse_relation(:equals)
      :equals

  """
  @spec inverse_relation(relation()) :: relation()
  def inverse_relation(:precedes), do: :preceded_by
  def inverse_relation(:preceded_by), do: :precedes
  def inverse_relation(:meets), do: :met_by
  def inverse_relation(:met_by), do: :meets
  def inverse_relation(:overlaps), do: :overlapped_by
  def inverse_relation(:overlapped_by), do: :overlaps
  def inverse_relation(:starts), do: :started_by
  def inverse_relation(:started_by), do: :starts
  def inverse_relation(:finishes), do: :finished_by
  def inverse_relation(:finished_by), do: :finishes
  def inverse_relation(:during), do: :contains
  def inverse_relation(:contains), do: :during
  def inverse_relation(:equals), do: :equals

  # Three endpoint comparisons drive the 13-way branch:
  # `a.from vs b.from`, `a.to vs b.to`, and the "seam" checks
  # `a.to vs b.from` / `a.from vs b.to` which disambiguate
  # disjoint (meets/precedes and their inverses) from
  # overlapping cases.
  defp classify(%__MODULE__{from: a_from, to: a_to}, %__MODULE__{from: b_from, to: b_to}) do
    s = Compare.compare_endpoints(a_from, b_from)
    e = Compare.compare_endpoints(a_to, b_to)
    e_vs_bs = Compare.compare_endpoints(a_to, b_from)
    s_vs_be = Compare.compare_endpoints(a_from, b_to)

    cond do
      e_vs_bs == :earlier -> :precedes
      e_vs_bs == :same -> :meets
      s_vs_be == :later -> :preceded_by
      s_vs_be == :same -> :met_by
      s == :earlier and e == :earlier -> :overlaps
      s == :earlier and e == :same -> :finished_by
      s == :earlier and e == :later -> :contains
      s == :same and e == :earlier -> :starts
      s == :same and e == :same -> :equals
      s == :same and e == :later -> :started_by
      s == :later and e == :earlier -> :during
      s == :later and e == :same -> :finishes
      s == :later and e == :later -> :overlapped_by
    end
  end

  defp to_single_interval(%__MODULE__{from: %Tempo{}, to: %Tempo{}} = iv, _label), do: {:ok, iv}

  defp to_single_interval(%IntervalSet{intervals: [iv]}, _label), do: {:ok, iv}

  defp to_single_interval(%IntervalSet{intervals: ivs}, label) do
    {:error,
     "Tempo.Interval.compare/2 requires a single bounded interval on each side. " <>
       "Operand #{inspect(label)} is an IntervalSet with #{length(ivs)} members. " <>
       "For set-level questions use `Tempo.overlaps?/2`, `Tempo.disjoint?/2`, " <>
       "`Tempo.intersection/2`, or `Tempo.IntervalSet.relation_matrix/2`."}
  end

  defp to_single_interval(%Tempo{} = point, label) do
    case Tempo.to_interval(point) do
      {:ok, %__MODULE__{} = iv} -> to_single_interval(iv, label)
      {:ok, %IntervalSet{} = set} -> to_single_interval(set, label)
      {:error, _} = err -> err
    end
  end

  defp to_single_interval(%__MODULE__{}, label) do
    {:error,
     "Tempo.Interval.compare/2 needs bounded intervals on both sides. " <>
       "Operand #{inspect(label)} has an open-ended endpoint (`:undefined`)."}
  end

  defp to_single_interval(other, label) do
    {:error,
     "Tempo.Interval.compare/2 cannot classify operand #{inspect(label)}: " <>
       "#{inspect(other)}"}
  end

  ## ----------------------------------------------------------
  ## Shape predicates
  ## ----------------------------------------------------------

  @doc """
  `true` when both endpoints are concrete `%Tempo{}` values —
  neither `:undefined` nor `nil`. Useful as a guard before set
  operations or duration checks.

  ### Examples

      iex> Tempo.Interval.bounded?(%Tempo.Interval{from: ~o"2026-06-01", to: ~o"2026-06-10"})
      true

      iex> Tempo.Interval.bounded?(%Tempo.Interval{from: ~o"2026-06-01", to: :undefined})
      false

  """
  @spec bounded?(t()) :: boolean()
  def bounded?(%__MODULE__{from: %Tempo{}, to: %Tempo{}}), do: true
  def bounded?(%__MODULE__{}), do: false

  @doc """
  `true` when the interval has zero or negative length —
  `from == to` (degenerate instant) or `from > to` (inverted
  span).

  Under the half-open `[from, to)` convention, an interval with
  `from >= to` contains no real instants. Empty intervals pass
  `bounded?/1` but have no span; inverted intervals are treated
  as empty rather than as a span with "negative" duration.

  ### Examples

      iex> Tempo.Interval.empty?(%Tempo.Interval{from: ~o"2026-06-15", to: ~o"2026-06-15"})
      true

      iex> Tempo.Interval.empty?(%Tempo.Interval{from: ~o"2026-06-20", to: ~o"2026-06-15"})
      true

      iex> Tempo.Interval.empty?(%Tempo.Interval{from: ~o"2026-06-01", to: ~o"2026-06-10"})
      false

  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{from: %Tempo{} = from, to: %Tempo{} = to}) do
    Compare.compare_endpoints(from, to) in [:same, :later]
  end

  def empty?(%__MODULE__{}), do: false

  ## ----------------------------------------------------------
  ## Duration query + duration predicates
  ## ----------------------------------------------------------

  @doc """
  Return the interval's `from` endpoint.

  A named helper so callers never have to reach into the struct
  fields in user-facing code. Compose with `Tempo.day/1`, `Tempo.year/1`,
  etc. to extract components of the starting point.

  ### Arguments

  * `interval` is a `t:t/0`.

  ### Returns

  * The `from` endpoint as a `t:Tempo.t/0` or `:undefined` for
    open-ended intervals.

  ### Examples

      iex> iv = %Tempo.Interval{from: ~o"2026-06-15", to: ~o"2026-06-20"}
      iex> Tempo.Interval.from(iv) |> Tempo.day()
      15

  """
  @spec from(t()) :: Tempo.t() | :undefined
  def from(%__MODULE__{from: from}), do: from

  @doc """
  Return the interval's `to` endpoint.

  Under half-open `[from, to)` semantics, this is the exclusive
  upper bound — the first instant **outside** the span.

  ### Arguments

  * `interval` is a `t:t/0`.

  ### Returns

  * The `to` endpoint as a `t:Tempo.t/0` or `:undefined` for
    open-ended intervals.

  ### Examples

      iex> iv = %Tempo.Interval{from: ~o"2026-06-15", to: ~o"2026-06-20"}
      iex> Tempo.Interval.to(iv) |> Tempo.day()
      20

  """
  @spec to(t()) :: Tempo.t() | :undefined
  def to(%__MODULE__{to: to}), do: to

  @doc """
  Return the interval's endpoints as a `{from, to}` tuple.

  A named helper so callers never have to reach into the struct
  fields in user-facing code.

  ### Arguments

  * `interval` is a `t:t/0`.

  ### Returns

  * `{from, to}` where each endpoint is a `t:Tempo.t/0` or
    `:undefined` for open-ended intervals.

  ### Examples

      iex> iv = %Tempo.Interval{from: ~o"2026-06-15", to: ~o"2026-06-20"}
      iex> {from, to} = Tempo.Interval.endpoints(iv)
      iex> {Tempo.day(from), Tempo.day(to)}
      {15, 20}

  """
  @spec endpoints(t()) :: {Tempo.t() | :undefined, Tempo.t() | :undefined}
  def endpoints(%__MODULE__{from: from, to: to}), do: {from, to}

  @doc """
  Return the interval's span resolution — the coarsest unit at
  which `from` and `to` differ.

  Under the half-open `[from, to)` convention, this is the unit
  that "ticks forward" across the span. `[2026-06-15, 2026-06-16)`
  ticks at the day; `[2026-06-01, 2026-07-01)` ticks at the month;
  `[2026, 2027)` ticks at the year.

  Unlike `Tempo.resolution/1` on a filled endpoint (which would
  report the finest unit present on the time keyword list after
  `Tempo.to_interval/1` has padded missing units with their
  minimums), this function reports the **span's** resolution —
  the authoritative scale of the interval itself.

  ### Arguments

  * `interval` is a `t:t/0`. Must be bounded (both endpoints
    present) — `:undefined` endpoints return `:undefined`.

  ### Returns

  * A unit atom (`:year`, `:month`, `:day`, `:hour`, `:minute`,
    `:second`, …), or `:undefined` for open-ended intervals.

  ### Examples

      iex> iv = %Tempo.Interval{from: ~o"2026-06-15", to: ~o"2026-06-16"}
      iex> Tempo.Interval.resolution(iv)
      :day

      iex> iv = %Tempo.Interval{from: ~o"2026-06", to: ~o"2026-07"}
      iex> Tempo.Interval.resolution(iv)
      :month

  """
  @spec resolution(t()) :: Tempo.time_unit() | :undefined
  def resolution(%__MODULE__{from: :undefined}), do: :undefined
  def resolution(%__MODULE__{to: :undefined}), do: :undefined

  def resolution(%__MODULE__{from: %Tempo{time: from_time}, to: %Tempo{time: to_time}}) do
    span_resolution(from_time, to_time)
  end

  # The coarsest unit at which from and to differ is the span's
  # declared resolution. Walk left-to-right through from.time — the
  # first unit where from and to disagree is the answer. If they
  # agree at every unit present on `from`, fall through to the
  # finest present unit as the resolution.
  defp span_resolution(from_time, to_time) do
    Enum.reduce_while(from_time, finest_unit(from_time), fn {unit, fv}, acc ->
      case Keyword.get(to_time, unit) do
        nil -> {:halt, acc}
        ^fv -> {:cont, acc}
        _other -> {:halt, unit}
      end
    end)
  end

  defp finest_unit(time) do
    case List.last(time) do
      nil -> :day
      {unit, _} -> unit
    end
  end

  @doc """
  Return the interval's length as a `%Tempo.Duration{}` in
  seconds. Returns `:infinity` for unbounded intervals (one or
  both endpoints `:undefined`).

  The result is calendar- and zone-aware — it goes through
  `Tempo.Compare.to_utc_seconds/1` so cross-zone intervals
  compute a correct wall-clock delta.

  ### Options

  * `:leap_seconds` — when `true`, adds one second to the
    returned duration for each IERS leap-second insertion that
    falls inside `[from, to)`. Defaults to `false` so behaviour
    matches `DateTime`, `Time`, and `:calendar` from Elixir/OTP
    (none of which count leap seconds). See
    `Tempo.Interval.spans_leap_second?/1` and
    `leap_seconds_spanned/1` for detection without arithmetic.

  ### Examples

      iex> Tempo.Interval.duration(%Tempo.Interval{from: ~o"2026-06-15T09", to: ~o"2026-06-15T10"})
      ~o"PT3600S"

      iex> Tempo.Interval.duration(%Tempo.Interval{from: ~o"2026-06-15", to: :undefined})
      :infinity

      iex> iv = %Tempo.Interval{from: ~o"2016-12-31T23:59:00Z", to: ~o"2017-01-01T00:01:00Z"}
      iex> Tempo.Interval.duration(iv)
      ~o"PT120S"
      iex> Tempo.Interval.duration(iv, leap_seconds: true)
      ~o"PT121S"

  """
  @spec duration(t(), keyword()) :: Duration.t() | :infinity
  def duration(interval, opts \\ [])
  def duration(%__MODULE__{from: :undefined}, _opts), do: :infinity
  def duration(%__MODULE__{to: :undefined}, _opts), do: :infinity
  def duration(%__MODULE__{from: nil}, _opts), do: :infinity
  def duration(%__MODULE__{to: nil}, _opts), do: :infinity

  def duration(%__MODULE__{from: %Tempo{} = from, to: %Tempo{} = to} = iv, opts) do
    :ok = require_same_calendar(from, to, "Tempo.Interval.duration/1")

    if empty?(iv) do
      # Degenerate (from == to) and inverted (from > to) intervals
      # contain no real instants under `[from, to)`. Duration is
      # zero rather than a negative count of wall-clock seconds.
      %Duration{time: [second: 0]}
    else
      base = Compare.to_utc_seconds(to) - Compare.to_utc_seconds(from)

      seconds =
        if Keyword.get(opts, :leap_seconds, false) do
          # Positive insertions add a second; negative removals
          # (reserved, none yet used) would subtract one.
          base + length(leap_second_insertions_spanned(iv)) -
            length(leap_second_removals_spanned(iv))
        else
          base
        end

      %Duration{time: [second: seconds]}
    end
  end

  @doc """
  Return `true` when the interval `[from, to)` contains at least
  one IERS-announced positive leap second.

  A historical predicate: it doesn't affect any other Tempo
  operation. Use it when you want to know if an elapsed-time
  calculation needs leap-second correction, or to flag intervals
  for a scientific/astronomy pipeline.

  ### Arguments

  * `interval` is a `t:t/0` with both endpoints present. Unbounded
    intervals always return `false` (open-ended to `:undefined`)
    and pre-Unix-era intervals pre-1972 return `false` (IERS leap
    seconds started in 1972).

  ### Returns

  * `true` when at least one entry from `Tempo.LeapSeconds.dates/0`
    falls inside `[from, to)`.

  * `false` otherwise.

  ### Examples

      iex> iv = %Tempo.Interval{from: ~o"2016-12-31T23:00:00Z", to: ~o"2017-01-01T01:00:00Z"}
      iex> Tempo.Interval.spans_leap_second?(iv)
      true

      iex> iv = %Tempo.Interval{from: ~o"2026-06-15", to: ~o"2026-06-16"}
      iex> Tempo.Interval.spans_leap_second?(iv)
      false

  """
  @spec spans_leap_second?(t()) :: boolean()
  def spans_leap_second?(%__MODULE__{from: %Tempo{}, to: %Tempo{}} = iv) do
    leap_second_insertions_spanned(iv) != [] or
      leap_second_removals_spanned(iv) != []
  end

  def spans_leap_second?(%__MODULE__{}), do: false

  @doc """
  Return the list of IERS leap-second dates that fall inside
  `[from, to)`.

  ### Arguments

  * `interval` is a `t:t/0` with both endpoints present.

  ### Returns

  * A list of `{year, month, day}` tuples, each entry drawn from
    `Tempo.LeapSeconds.dates/0`. Empty list when no leap second
    falls inside the span, or when either endpoint is
    `:undefined`.

  ### Examples

      iex> iv = %Tempo.Interval{from: ~o"2015-01-01", to: ~o"2017-12-31"}
      iex> Tempo.Interval.leap_seconds_spanned(iv)
      [{2015, 6, 30}, {2016, 12, 31}]

  """
  @spec leap_seconds_spanned(t()) :: [{integer(), 1..12, 1..31}]
  def leap_seconds_spanned(%__MODULE__{from: %Tempo{}, to: %Tempo{}} = iv) do
    # Union of positive insertions and (reserved) negative
    # removals, in chronological order.
    (leap_second_insertions_spanned(iv) ++ leap_second_removals_spanned(iv))
    |> Enum.sort()
  end

  def leap_seconds_spanned(%__MODULE__{}), do: []

  defp leap_second_insertions_spanned(%__MODULE__{from: %Tempo{} = from, to: %Tempo{} = to}) do
    :ok = require_same_calendar(from, to, "Tempo.Interval.leap_seconds_spanned/1")
    from_s = Compare.to_utc_seconds(from)
    to_s = Compare.to_utc_seconds(to)

    for {y, m, d} <- Tempo.LeapSeconds.dates(),
        leap_second_in_interval?(y, m, d, from_s, to_s),
        do: {y, m, d}
  end

  defp leap_second_removals_spanned(%__MODULE__{from: %Tempo{} = from, to: %Tempo{} = to}) do
    :ok = require_same_calendar(from, to, "Tempo.Interval.leap_seconds_spanned/1")
    from_s = Compare.to_utc_seconds(from)
    to_s = Compare.to_utc_seconds(to)

    for {y, m, d} <- Tempo.LeapSeconds.removals(),
        leap_second_in_interval?(y, m, d, from_s, to_s),
        do: {y, m, d}
  end

  # A leap second is inserted at 23:59:60 UTC on day (y,m,d) —
  # conceptually *between* 23:59:59 and 00:00:00 of the following
  # day. In leap-second-naive gregorian seconds those two endpoints
  # collide at N+1 (where N = gregorian(y,m,d,23,59,59)).
  #
  # For a half-open interval `[from_s, to_s)`, the leap second is
  # included iff `from_s ≤ N AND to_s > N`. That is: the interval
  # starts at or before the final second of day (y,m,d) and extends
  # past that final-second boundary. This places the leap second
  # infinitesimally after N in naive time — any interval that
  # contains N and extends beyond it contains the leap second.
  defp leap_second_in_interval?(year, month, day, from_s, to_s) do
    n = :calendar.datetime_to_gregorian_seconds({{year, month, day}, {23, 59, 59}})
    from_s <= n and to_s > n
  end

  # Cross-calendar endpoints produce nonsense arithmetic — the
  # Gregorian seconds of Hebrew 5786 and Gregorian 2026 measure
  # from different epochs and subtracting them yields a garbage
  # duration. Refuse explicitly and tell the caller how to fix it.
  defp require_same_calendar(
         %Tempo{calendar: cal, time: from_time},
         %Tempo{calendar: cal, time: to_time},
         _context
       ) do
    # Non-anchored endpoints (no year) share the time-of-day axis
    # across any calendar — no conversion needed.
    _ = from_time
    _ = to_time
    :ok
  end

  defp require_same_calendar(%Tempo{} = from, %Tempo{} = to, context) do
    cond do
      not Tempo.anchored?(from) or not Tempo.anchored?(to) ->
        :ok

      true ->
        raise ArgumentError,
              "#{context} requires both endpoints in the same calendar. " <>
                "Got #{inspect(from.calendar)} and #{inspect(to.calendar)}. " <>
                "Convert one endpoint first — set operations such as " <>
                "`Tempo.intersection/2` and `Tempo.difference/2` handle " <>
                "cross-calendar inputs automatically via `Date.convert!/2`."
    end
  end

  @doc """
  `true` when the interval is at least as long as the given
  duration.

  Unbounded intervals (`:undefined` endpoint) satisfy any finite
  minimum — an infinite span is trivially "at least" any
  duration.

  ### Examples

      iex> iv = %Tempo.Interval{from: ~o"2026-06-15T09", to: ~o"2026-06-15T11"}
      iex> Tempo.Interval.at_least?(iv, ~o"PT1H")
      true

      iex> Tempo.Interval.at_least?(iv, ~o"PT3H")
      false

  """
  @spec at_least?(t(), Duration.t()) :: boolean()
  def at_least?(%__MODULE__{from: :undefined}, _), do: true
  def at_least?(%__MODULE__{to: :undefined}, _), do: true

  def at_least?(%__MODULE__{from: %Tempo{} = from, to: %Tempo{} = to}, %Duration{} = d) do
    Compare.compare_endpoints(Math.add(from, d), to) in [:earlier, :same]
  end

  @doc """
  `true` when the interval is at most as long as the given
  duration.

  Unbounded intervals return `false` — an infinite span exceeds
  any finite maximum.

  ### Examples

      iex> iv = %Tempo.Interval{from: ~o"2026-06-15T09", to: ~o"2026-06-15T10"}
      iex> Tempo.Interval.at_most?(iv, ~o"PT1H")
      true

      iex> Tempo.Interval.at_most?(iv, ~o"PT30M")
      false

  """
  @spec at_most?(t(), Duration.t()) :: boolean()
  def at_most?(%__MODULE__{from: :undefined}, _), do: false
  def at_most?(%__MODULE__{to: :undefined}, _), do: false

  def at_most?(%__MODULE__{from: %Tempo{} = from, to: %Tempo{} = to}, %Duration{} = d) do
    Compare.compare_endpoints(Math.add(from, d), to) in [:later, :same]
  end

  @doc """
  `true` when the interval's length equals the given duration
  exactly.

  Unbounded intervals always return `false`.

  ### Examples

      iex> iv = %Tempo.Interval{from: ~o"2026-06-15T09", to: ~o"2026-06-15T10"}
      iex> Tempo.Interval.exactly?(iv, ~o"PT1H")
      true

      iex> Tempo.Interval.exactly?(iv, ~o"PT2H")
      false

  """
  @spec exactly?(t(), Duration.t()) :: boolean()
  def exactly?(%__MODULE__{from: :undefined}, _), do: false
  def exactly?(%__MODULE__{to: :undefined}, _), do: false

  def exactly?(%__MODULE__{from: %Tempo{} = from, to: %Tempo{} = to}, %Duration{} = d) do
    Compare.compare_endpoints(Math.add(from, d), to) == :same
  end

  @doc """
  `true` when the interval's length is strictly greater than
  the given duration.

  ### Examples

      iex> iv = %Tempo.Interval{from: ~o"2026-06-15T09", to: ~o"2026-06-15T11"}
      iex> Tempo.Interval.longer_than?(iv, ~o"PT1H")
      true

      iex> Tempo.Interval.longer_than?(iv, ~o"PT2H")
      false

  """
  @spec longer_than?(t(), Duration.t()) :: boolean()
  def longer_than?(%__MODULE__{from: :undefined}, _), do: true
  def longer_than?(%__MODULE__{to: :undefined}, _), do: true

  def longer_than?(%__MODULE__{from: %Tempo{} = from, to: %Tempo{} = to}, %Duration{} = d) do
    Compare.compare_endpoints(Math.add(from, d), to) == :earlier
  end

  @doc """
  `true` when the interval's length is strictly less than the
  given duration.

  ### Examples

      iex> iv = %Tempo.Interval{from: ~o"2026-06-15T09", to: ~o"2026-06-15T10"}
      iex> Tempo.Interval.shorter_than?(iv, ~o"PT2H")
      true

      iex> Tempo.Interval.shorter_than?(iv, ~o"PT1H")
      false

  """
  @spec shorter_than?(t(), Duration.t()) :: boolean()
  def shorter_than?(%__MODULE__{from: :undefined}, _), do: false
  def shorter_than?(%__MODULE__{to: :undefined}, _), do: false

  def shorter_than?(%__MODULE__{from: %Tempo{} = from, to: %Tempo{} = to}, %Duration{} = d) do
    Compare.compare_endpoints(Math.add(from, d), to) == :later
  end

  ## ----------------------------------------------------------
  ## Relation predicates — thin shortcuts over compare/2
  ## ----------------------------------------------------------

  @doc """
  `true` when `a` ends strictly before `b` starts, with a gap
  (Allen's `:precedes`). Use `adjacent?/2` to include the
  no-gap case.

  Returns `false` on any error or non-matching relation.
  """
  @spec before?(interval_like(), interval_like()) :: boolean()
  def before?(a, b), do: match_relation(a, b, [:precedes])

  @doc """
  `true` when `a` starts strictly after `b` ends, with a gap
  (Allen's `:preceded_by`).
  """
  @spec after?(interval_like(), interval_like()) :: boolean()
  def after?(a, b), do: match_relation(a, b, [:preceded_by])

  @doc """
  `true` when `a`'s end coincides exactly with `b`'s start
  (Allen's `:meets`). Under the half-open convention this means
  the intervals share no point but have no gap.
  """
  @spec meets?(interval_like(), interval_like()) :: boolean()
  def meets?(a, b), do: match_relation(a, b, [:meets])

  @doc """
  `true` when the two intervals touch at a single boundary —
  either `a` meets `b` or `b` meets `a` (Allen's
  `:meets | :met_by`).

  ### Examples

      iex> Tempo.Interval.adjacent?(~o"2026-06-15", ~o"2026-06-16")
      true

      iex> Tempo.Interval.adjacent?(~o"2026-06-15", ~o"2026-06-17")
      false

  """
  @spec adjacent?(interval_like(), interval_like()) :: boolean()
  def adjacent?(a, b), do: match_relation(a, b, [:meets, :met_by])

  @doc """
  `true` when `a` is strictly inside `b` — both endpoints of
  `a` lie strictly within `b` (Allen's `:during`). Shared-
  endpoint cases (`:starts`, `:finishes`) return `false`; use
  `within?/2` for the inclusive version.
  """
  @spec during?(interval_like(), interval_like()) :: boolean()
  def during?(a, b), do: match_relation(a, b, [:during])

  @doc """
  `true` when `a` lies inside `b` inclusive of shared
  endpoints (Allen's `:equals | :starts | :during | :finishes`).
  The canonical "does this fit inside that window?" predicate.

  ### Examples

      iex> a = %Tempo.Interval{from: ~o"2026-06-15T10", to: ~o"2026-06-15T11"}
      iex> window = %Tempo.Interval{from: ~o"2026-06-15T09", to: ~o"2026-06-15T17"}
      iex> Tempo.Interval.within?(a, window)
      true

      iex> # Candidate shares the window's start — still inside
      iex> a2 = %Tempo.Interval{from: ~o"2026-06-15T09", to: ~o"2026-06-15T10"}
      iex> Tempo.Interval.within?(a2, window)
      true

  """
  @spec within?(interval_like(), interval_like()) :: boolean()
  def within?(a, b), do: match_relation(a, b, [:equals, :starts, :during, :finishes])

  defp match_relation(a, b, allowed_relations) do
    case compare(a, b) do
      r when is_atom(r) -> r in allowed_relations
      _ -> false
    end
  end
end
