defmodule Tempo.Sigils do
  @moduledoc """
  Sigils for constructing `%Tempo{}` values at compile time.

  Provides `~o` (and its verbose alias `~TEMPO`) to turn an ISO 8601
  / ISO 8601-2 / IXDTF / EDTF string into a `%Tempo{}`, `%Tempo.Interval{}`,
  `%Tempo.Duration{}`, or `%Tempo.Set{}` struct.

  ```elixir
  import Tempo.Sigils

  ~o"2026-06-15"            #=> %Tempo{…}
  ~o"2026-06-15T10:30:00Z"  #=> zoned datetime
  ~o"1984?/2004~"           #=> qualified interval
  ~o"2026Y"w                #=> ISO week calendar (w modifier)
  ```

  ### Why a module just for sigils

  The module exposes **only** the sigil macros so `import Tempo.Sigils`
  in application code adds exactly `sigil_o/2` and `sigil_TEMPO/2` to
  the caller's scope — no helper functions leak into the caller's
  namespace. Any expansion-time helpers live in a private sibling
  module that isn't part of the public API.

  ### Modifiers

  * No modifier — Gregorian calendar (the common case).

  * `w` — ISO Week calendar (`Calendrical.ISOWeek`). Use when the
    input is in a week-based form you want parsed under ISO week
    semantics explicitly.

  """

  alias Tempo.Sigils.Options

  @doc """
  Parse an ISO 8601 / EDTF / IXDTF string at compile time.

  The value is fully resolved to its `%Tempo{}` / `%Tempo.Interval{}` /
  `%Tempo.Duration{}` / `%Tempo.Set{}` form by the parser and escaped
  as a compile-time literal, so there is no runtime parse cost at the
  call site.

  """
  defmacro sigil_o({:<<>>, _meta, [_string]} = sigil, opts) do
    do_sigil(__CALLER__.context, sigil, opts)
  end

  @doc """
  Verbose alias for `sigil_o`. Use when `~o` might be confused with
  another sigil in scope, or when you want the three-letter form
  for readability in dense code.
  """
  defmacro sigil_TEMPO({:<<>>, _meta, [_string]} = sigil, opts) do
    do_sigil(__CALLER__.context, sigil, opts)
  end

  defp do_sigil(nil, {:<<>>, _meta, [string]}, opts) do
    calendar = Options.calendar_from(opts)

    case Tempo.from_iso8601(string, calendar) do
      {:ok, tempo} -> Macro.escape(tempo)
      {:error, exception} -> raise exception
    end
  end

  # Modifier letters accepted in match context and the unit they
  # bind. `M` is deliberately absent — ISO 8601 overloads it for
  # both month and minute, so match-context modifiers use `O` for
  # month and `N` for minute to keep the binding unambiguous.
  @modifier_to_unit %{
    ?Y => :year,
    ?O => :month,
    ?W => :week,
    ?D => :day,
    ?I => :day_of_year,
    ?K => :day_of_week,
    ?H => :hour,
    ?N => :minute,
    ?S => :second
  }

  # Canonical unit sequences per calendar axis. A `~o[…]`-bound
  # pattern picks the axis that covers every unit named (sigil or
  # modifier) and lays elements out in that axis's order, with
  # wildcards filling positions not explicitly requested.
  @gregorian_axis [:year, :month, :day, :hour, :minute, :second]
  @iso_week_axis [:year, :week, :day_of_week, :hour, :minute, :second]
  @ordinal_axis [:year, :day_of_year, :hour, :minute, :second]

  defp do_sigil(:match, {:<<>>, _meta, [string]}, opts) do
    # Match-context modifiers are always binding letters — a
    # departure from value context, where `W` selects the ISO
    # week calendar. The sigil string is therefore always parsed
    # with `Calendrical.Gregorian`; the generated pattern does
    # not constrain the target's `:calendar` field either, so a
    # Gregorian-looking sigil still matches e.g. a Hebrew value
    # at the same `time` prefix.
    bindings = bindings_from_modifiers(opts)

    case Tempo.from_iso8601(string, Calendrical.Gregorian) do
      {:ok, parsed} -> build_match_pattern(parsed, bindings)
      {:error, exception} -> raise exception
    end
  end

  defp do_sigil(:guard, {:<<>>, _meta, [_string]}, _opts) do
    raise ArgumentError, "invalid expression in guard"
  end

  # Resolve the modifier char list to a list of unit atoms to
  # bind. Order in the sigil is irrelevant — the pattern builder
  # re-sorts by axis position.
  defp bindings_from_modifiers([]), do: []

  defp bindings_from_modifiers(letters) when is_list(letters) do
    Enum.map(letters, fn letter ->
      case Map.fetch(@modifier_to_unit, letter) do
        {:ok, unit} ->
          unit

        :error ->
          raise ArgumentError,
                "~o sigil in a match context does not recognise modifier " <>
                  "#{inspect(<<letter::utf8>>)}; valid modifiers are " <>
                  "Y (year), O (month), W (week), D (day), I (day-of-year), " <>
                  "K (day-of-week), H (hour), N (minute), S (second)"
      end
    end)
  end

  # Dispatch on the struct that the parser produced. `%Tempo{}`
  # and `%Tempo.Duration{}` share a keyword-list `time` field, so
  # modifier bindings work for both; containers (intervals,
  # ranges, sets) match structurally and refuse modifiers.
  defp build_match_pattern(%Tempo{time: time}, bindings) do
    time_pattern = build_time_match_pattern(time, bindings)

    quote do
      %Tempo{time: unquote(time_pattern)}
    end
  end

  defp build_match_pattern(%Tempo.Duration{time: time}, bindings) do
    time_pattern = build_time_match_pattern(time, bindings)

    quote do
      %Tempo.Duration{time: unquote(time_pattern)}
    end
  end

  defp build_match_pattern(%Tempo.Interval{} = interval, bindings) do
    reject_container_bindings!(bindings, Tempo.Interval)
    interval_pattern(interval)
  end

  defp build_match_pattern(%Tempo.Range{} = range, bindings) do
    reject_container_bindings!(bindings, Tempo.Range)
    range_pattern(range)
  end

  defp build_match_pattern(%Tempo.Set{} = set, bindings) do
    reject_container_bindings!(bindings, Tempo.Set)
    set_pattern(set)
  end

  # `%Tempo.IntervalSet{}` is produced by `Tempo.to_interval/1`,
  # not by `Tempo.from_iso8601/2` — so a sigil string can't
  # materialise to one in practice. Kept here for exhaustiveness
  # in case future grammar extensions produce one.
  defp build_match_pattern(%Tempo.IntervalSet{} = interval_set, bindings) do
    reject_container_bindings!(bindings, Tempo.IntervalSet)
    interval_set_pattern(interval_set)
  end

  defp build_match_pattern(other, _bindings) do
    raise ArgumentError,
          "~o sigil in a match context does not support matching on " <>
            "#{inspect(other.__struct__)} values"
  end

  defp reject_container_bindings!([], _module), do: :ok

  defp reject_container_bindings!(bindings, module) do
    raise ArgumentError,
          "~o sigil modifier bindings #{inspect(bindings)} are only " <>
            "supported on %Tempo{} and %Tempo.Duration{} values; " <>
            "#{inspect(module)} values match structurally only"
  end

  # Build a cons-pattern AST ending in `| _` for the `time` field
  # of the generated `%Tempo{}` pattern. The pattern lays out the
  # canonical axis slice between the earliest and latest unit
  # requested (whether via the sigil literal or a binding
  # modifier), filling each position with either the literal
  # value, the binding variable, or a wildcard.
  #
  # Only simple integer-valued components from the parsed sigil
  # are supported. Complex AST shapes (groups, selections,
  # ranges, margin-of-error tuples, continuations) raise at
  # macro-expansion time.
  defp build_time_match_pattern([], []) do
    quote do: _
  end

  defp build_time_match_pattern(time, bindings) do
    sigil_units = Keyword.keys(time)
    assert_no_modifier_duplicates!(sigil_units, bindings)

    all_units = sigil_units ++ bindings
    axis = axis_for(all_units)

    indexes = Enum.map(all_units, &index_in_axis!(&1, axis))
    first_index = Enum.min(indexes)
    last_index = Enum.max(indexes)

    axis
    |> Enum.slice(first_index..last_index)
    |> Enum.map(&element_for_unit(&1, time, bindings))
    |> build_cons_pattern()
  end

  # Pick the appropriate element shape for a canonical-axis
  # position: the sigil's literal value wins, a modifier binding
  # comes next, and unrequested positions become `_` wildcards.
  defp element_for_unit(unit, time, bindings) do
    cond do
      Keyword.has_key?(time, unit) ->
        value = Keyword.fetch!(time, unit)
        assert_matchable!(unit, value)
        {:fixed, unit, value}

      unit in bindings ->
        {:bind, unit}

      true ->
        :wildcard
    end
  end

  defp build_cons_pattern([]) do
    quote do: _
  end

  defp build_cons_pattern([elem | rest]) do
    head = element_to_ast(elem)
    tail = build_cons_pattern(rest)

    quote do
      [unquote(head) | unquote(tail)]
    end
  end

  defp element_to_ast({:fixed, unit, value}) do
    quote do: {unquote(unit), unquote(value)}
  end

  # Bind the unit's value to a same-named variable in the
  # caller's context — `D` binds `day`, `N` binds `minute`, etc.
  # `Macro.var(unit, nil)` uses hygienic context `nil`, matching
  # how the standard library's pattern-producing sigils (e.g.
  # `~D`) expose bindings.
  defp element_to_ast({:bind, unit}) do
    var = Macro.var(unit, nil)
    quote do: {unquote(unit), unquote(var)}
  end

  defp element_to_ast(:wildcard) do
    quote do: _
  end

  # Integers (including negatives) are valid literal patterns.
  # Anything else indicates a non-simple Tempo component that we
  # don't yet know how to express as a static Elixir pattern.
  defp assert_matchable!(_unit, value) when is_integer(value), do: :ok

  defp assert_matchable!(unit, value) do
    raise ArgumentError,
          "~o sigil in a match context only supports simple integer components; " <>
            "got #{inspect(unit)}: #{inspect(value)}"
  end

  defp assert_no_modifier_duplicates!(sigil_units, bindings) do
    dupes = for u <- bindings, u in sigil_units, do: u

    if dupes != [] do
      raise ArgumentError,
            "~o sigil modifier binds a unit already present in the sigil literal: " <>
              "#{inspect(dupes)}"
    end
  end

  # Derive the calendar axis (Gregorian / ISO week / ordinal)
  # that every requested unit has to belong to. Axis mixing is
  # an expansion-time error — a user can't meaningfully match
  # `:month` and `:week` on the same value.
  defp axis_for(units) do
    week? = Enum.any?(units, &(&1 in [:week, :day_of_week]))
    ordinal? = Enum.any?(units, &(&1 == :day_of_year))
    gregorian? = Enum.any?(units, &(&1 in [:month, :day]))

    if Enum.count([week?, ordinal?, gregorian?], & &1) > 1 do
      raise ArgumentError,
            "~o sigil in a match context cannot mix calendar axes: " <>
              "#{inspect(units)}"
    end

    cond do
      week? -> @iso_week_axis
      ordinal? -> @ordinal_axis
      true -> @gregorian_axis
    end
  end

  defp index_in_axis!(unit, axis) do
    case Enum.find_index(axis, &(&1 == unit)) do
      nil ->
        raise ArgumentError,
              "~o sigil in a match context cannot place unit #{inspect(unit)} " <>
                "on the inferred calendar axis #{inspect(axis)}"

      idx ->
        idx
    end
  end

  # ---- Container patterns -----------------------------------

  # Pattern for a value that appears as an endpoint on an
  # `Interval`, `Range`, or `Set`. `:undefined` is used by the
  # parser for open endpoints; `nil` can appear on intervals
  # constructed without a `from` or `to` (e.g. a bare RRULE).
  # Concrete `%Tempo{}` / `%Tempo.Duration{}` endpoints reuse the
  # prefix-match semantics of phase ①/② so that an endpoint like
  # `~o"2022Y"` matches any Tempo whose `time` starts with year
  # 2022.
  defp endpoint_pattern(:undefined), do: :undefined
  defp endpoint_pattern(nil), do: nil

  defp endpoint_pattern(%Tempo{time: time}) do
    time_pattern = build_time_match_pattern(time, [])

    quote do
      %Tempo{time: unquote(time_pattern)}
    end
  end

  defp endpoint_pattern(%Tempo.Duration{time: time}) do
    time_pattern = build_time_match_pattern(time, [])

    quote do
      %Tempo.Duration{time: unquote(time_pattern)}
    end
  end

  # Intervals carry 7 fields but most are optional metadata. The
  # pattern only constrains fields that differ from their struct
  # defaults (so an interval built from `1984/2004` doesn't
  # accidentally require `metadata: %{}`, `direction: 1`, etc.).
  defp interval_pattern(%Tempo.Interval{
         from: from,
         to: to,
         duration: duration,
         recurrence: recurrence,
         direction: direction,
         repeat_rule: repeat_rule
       }) do
    fields =
      [from: endpoint_pattern(from), to: endpoint_pattern(to)]
      |> maybe_put_field(:duration, duration, &endpoint_pattern/1, &is_nil/1)
      |> maybe_put_field(:recurrence, recurrence, & &1, &(&1 == 1))
      |> maybe_put_field(:direction, direction, & &1, &(&1 == 1))
      |> maybe_put_field(:repeat_rule, repeat_rule, &endpoint_pattern/1, &is_nil/1)

    {:%, [],
     [
       {:__aliases__, [alias: false], [:Tempo, :Interval]},
       {:%{}, [], fields}
     ]}
  end

  defp range_pattern(%Tempo.Range{first: first, last: last}) do
    first_ast = endpoint_pattern(first)
    last_ast = endpoint_pattern(last)

    quote do
      %Tempo.Range{first: unquote(first_ast), last: unquote(last_ast)}
    end
  end

  # Sets either enumerate explicit members (`%Tempo.Set{}` with
  # `:all`/`:one`) or hold ranges. Member order and length are
  # constrained by the pattern — a sigil set only matches a Set
  # whose `:set` list has the same members in the same order.
  defp set_pattern(%Tempo.Set{type: type, set: members}) do
    member_asts = Enum.map(members, &set_member_pattern/1)

    quote do
      %Tempo.Set{type: unquote(type), set: unquote(member_asts)}
    end
  end

  defp set_member_pattern(%Tempo.Range{} = range), do: range_pattern(range)
  defp set_member_pattern(%Tempo{} = tempo), do: endpoint_pattern(tempo)
  defp set_member_pattern(%Tempo.Duration{} = duration), do: endpoint_pattern(duration)

  defp set_member_pattern(other) do
    raise ArgumentError,
          "~o sigil in a match context does not support set members of type " <>
            "#{inspect(other.__struct__)}"
  end

  defp interval_set_pattern(%Tempo.IntervalSet{intervals: intervals}) do
    interval_asts = Enum.map(intervals, &interval_pattern/1)

    quote do
      %Tempo.IntervalSet{intervals: unquote(interval_asts)}
    end
  end

  # Append `{field, transform.(value)}` to `fields` when `value`
  # differs from its default (as reported by `default?`). Keeps
  # container patterns free of spurious constraints on fields the
  # sigil string didn't actually mention.
  defp maybe_put_field(fields, field, value, transform, default?) do
    if default?.(value) do
      fields
    else
      fields ++ [{field, transform.(value)}]
    end
  end
end

defmodule Tempo.Sigil do
  @moduledoc """
  Deprecated — use `Tempo.Sigils` (plural).

  The pluralised module exposes only the sigil macros, so
  `import Tempo.Sigils` leaves the caller's namespace free of helper
  functions. Old `Tempo.Sigil` is kept as a thin compatibility shim
  that re-exports the macros. It will be removed in a future major
  version.

  """

  alias Tempo.Sigils.Options

  # Re-implement the macros directly rather than delegating to
  # `Tempo.Sigils.sigil_o/2`. Macro-to-macro forwarding would require
  # every legacy call site to `require Tempo.Sigils` for the inner
  # macro to be expanded, which defeats the point of a compatibility
  # shim. Keeping the logic inline means existing `import Tempo.Sigil`
  # call sites continue to work unchanged during the deprecation
  # window.
  defmacro sigil_o({:<<>>, _meta, [string]}, opts) do
    calendar = Options.calendar_from(opts)

    case Tempo.from_iso8601(string, calendar) do
      {:ok, tempo} -> Macro.escape(tempo)
      {:error, exception} -> raise exception
    end
  end

  defmacro sigil_TEMPO({:<<>>, _meta, [string]}, opts) do
    calendar = Options.calendar_from(opts)

    case Tempo.from_iso8601(string, calendar) do
      {:ok, tempo} -> Macro.escape(tempo)
      {:error, exception} -> raise exception
    end
  end
end

defmodule Tempo.Sigils.Options do
  @moduledoc false

  # Maps the sigil modifier character list to a calendar module.
  # Kept out of `Tempo.Sigils` so `import Tempo.Sigils` does not
  # bring `calendar_from/1` into the caller's scope.

  def calendar_from([?W]), do: Calendrical.ISOWeek
  def calendar_from([]), do: Calendrical.Gregorian
end
