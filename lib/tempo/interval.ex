defmodule Tempo.Interval do
  @moduledoc false

  alias Tempo.Duration
  alias Tempo.Math
  alias Tempo.Iso8601.Unit

  @type t :: %__MODULE__{
          recurrence: pos_integer() | :infinity,
          direction: 1 | -1,
          from: Tempo.t() | Tempo.Duration.t() | :undefined | nil,
          to: Tempo.t() | :undefined | nil,
          duration: Tempo.Duration.t() | nil,
          repeat_rule: Tempo.t() | nil
        }

  defstruct recurrence: 1,
            direction: 1,
            from: nil,
            to: nil,
            duration: nil,
            repeat_rule: nil

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
  coarsest un-masked prefix and use `Tempo.Mask.mask_bounds/1` to
  determine the enclosing span.

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
        {:error,
         "Cannot materialise a Tempo at #{inspect(unit)} resolution into an explicit " <>
           "interval — no finer unit is defined. Got: #{inspect(tempo)}"}

      {next_unit, range} ->
        lower_time = time ++ [{next_unit, range_first(range)}]
        upper_time = Math.add_unit(lower_time, unit, calendar)
        {:ok, build_bounds(tempo, lower_time, upper_time)}
    end
  end

  # A `Range` or integer supplied by `Unit.implicit_enumerator/2`
  # — we take the first value as the unit's start-of-span.
  defp range_first(%Range{first: first}), do: first
  defp range_first(int) when is_integer(int), do: int

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
end
