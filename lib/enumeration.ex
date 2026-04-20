defmodule Tempo.Enumeration do
  @moduledoc false
  alias Tempo.Validation
  alias Tempo.Iso8601.Unit

  defguard is_continuation(unit, fun) when is_atom(unit) and is_function(fun)
  defguard is_unit(unit, value) when (is_atom(unit) and is_list(value)) or is_number(value)

  @doc """
  Get the next "odomoter reading" list of integers and ranges
  or a list of time units

  """
  def next(%Tempo{time: units, calendar: calendar} = tempo) do
    case next(units, calendar) do
      nil -> nil
      other -> %{tempo | time: other}
    end
  end

  def next(list, calendar) when is_list(list) do
    case do_next(list, calendar, []) do
      {:rollover, _list} -> nil
      list -> list
    end
  end

  # A selection `{:selection, [unit: value, …]}` is a constraint
  # on the enclosing enumeration ("the Nth month", "the last
  # Friday"), not a sequence to iterate over. This clause must
  # come before the `is_unit` clause below, otherwise that clause
  # would match (the selection's inner keyword list is a list)
  # and the selection would be destructively iterated.
  #
  # Full selection resolution — actually filtering enumerated
  # values by the selection pattern — is future work.

  def do_next([{:selection, _} = sel | t], calendar, previous) do
    case do_next(t, calendar, [sel | previous]) do
      {:rollover, tail} -> {:rollover, [sel | tail]}
      tail -> [sel | tail]
    end
  end

  def do_next([{unit, value} | t], calendar, previous) when is_unit(unit, value) do
    cycle =
      case cycle(value, unit, calendar, previous) do
        {{:rollover, value}, continuation} when is_number(value) -> {value, continuation}
        other -> other
      end

    [{unit, cycle} | List.wrap(do_next(t, calendar, [{unit, value} | previous]))]
  end

  # When its a mask, fill in the unspecified digits with
  # acceptable candidate values.

  def do_next([{unit, {:mask, mask}} | t], calendar, previous) do
    value = Tempo.Mask.fill_unspecified(unit, mask, calendar, previous)
    do_next([{unit, value} | t], calendar, previous)
  end

  def do_next([{unit, :any = mask} | t], calendar, previous) do
    value = Tempo.Mask.fill_unspecified(unit, mask, calendar, previous)
    do_next([{unit, value} | t], calendar, previous)
  end

  # A group token `{:group, range}` (produced by expanded
  # `nGspanUNITU` constructs) wraps a range of candidate values.
  # Treat it as a single-element list holding the range so the
  # `is_unit` path picks it up via the existing cycle machinery.

  def do_next([{unit, {:group, %Range{} = range}} | t], calendar, previous) do
    do_next([{unit, [range]} | t], calendar, previous)
  end

  # ISO 8601-2 significant-digits annotation. A year value tagged
  # `{int, [significant_digits: n]}` (e.g. `1950S2` → first 2
  # digits are significant) enumerates over the block of values
  # sharing those leading digits: `1950S2` → `1900..1999`,
  # `Y3388E2S3` → `338800..338899`.
  #
  # The candidate-count guard refuses to enumerate blocks larger
  # than `@significant_digits_limit`. The user can still hold the
  # value as a parsed AST; they just can't iterate through it.

  @significant_digits_limit 10_000

  def do_next([{unit, {value, [significant_digits: n]}} | t], calendar, previous)
      when is_integer(value) and is_integer(n) and n > 0 do
    range = significant_digits_range(value, n)

    case Range.size(range) do
      size when size > @significant_digits_limit ->
        raise ArgumentError,
              "Cannot enumerate a significant-digits block of #{size} candidates " <>
                "(limit: #{@significant_digits_limit}). Source: #{inspect(value)}S#{n}"

      _ ->
        do_next([{unit, [range]} | t], calendar, previous)
    end
  end

  # We hit a continuation at the end of a list
  def do_next([{unit, {_current, fun}}], calendar, previous) when is_continuation(unit, fun) do
    case fun.(calendar, previous) do
      {{:rollover, acc}, fun} ->
        {:rollover, [{unit, {acc, fun}}]}

      {acc, fun} ->
        [{unit, {acc, fun}}]
    end
  end

  def do_next([], _calendar, _previous) do
    []
  end

  def do_next([{unit, {current, fun}} | t], calendar, previous) when is_continuation(unit, fun) do
    case do_next(t, calendar, [{unit, {current, fun}} | previous]) do
      {:rollover, list} ->
        case fun.(calendar, previous) do
          {{:rollover, current}, fun} ->
            {:rollover, [{unit, {current, fun}} | list]}

          {current, fun} ->
            [{unit, {current, fun}} | list]
        end

      tail ->
        [{unit, {current, fun}} | tail]
    end
  end

  @doc """
  Returns a function that when called will return
  the next cycle value in a sequence.

  When the sequence cycles back to the start
  it returns `{:rollover, value}` to signal
  the rollover.

  """
  def cycle(source, unit, calendar, previous) when is_number(source) do
    cycle([source], [], unit, calendar, previous)
  end

  def cycle(source, unit, calendar, previous) do
    cycle(List.wrap(source), List.wrap(source), unit, calendar, previous)
  end

  def cycle(source, list, unit, calendar, previous) do
    case list do
      [] ->
        rollover(source, unit, calendar, previous)

      [%Range{first: first, last: last} = range | rest] when first > 0 and last < 0 ->
        reset(source, range, unit, calendar, previous, rest)

      [%Range{first: first, last: last, step: step} = range | rest]
      when first <= last and step > 0 ->
        increment(source, range, unit, rest)

      [%Range{first: first, last: last, step: step} = range | rest]
      when first >= last and step < 0 ->
        increment(source, range, unit, rest)

      [%Range{}] ->
        rollover(source, unit, calendar, previous)

      [%Range{}, %Range{} = range | rest] ->
        cycle(source, [range | rest], unit, calendar, previous)

      [%Range{}, next | rest] ->
        {next, continuation(source, rest, unit)}

      [next | rest] ->
        {next, continuation(source, rest, unit)}

      value ->
        value
    end
  end

  defp increment(source, %Range{first: first, last: last, step: step}, unit, rest) do
    {first, continuation(source, [(first + step)..last//step | rest], unit)}
  end

  def continuation(source, rest, unit) do
    fn calendar, previous -> cycle(source, rest, unit, calendar, previous) end
  end

  def reset(source, range, unit, calendar, previous, rest) do
    range = adjusted_range(range, unit, calendar, backtrack(previous, calendar))
    increment(List.wrap(source), range, unit, rest)
  end

  defp rollover([h | t] = source, unit, calendar, previous) do
    case h do
      %Range{first: first, last: last} = range when first >= 0 and last < 0 ->
        {first, continuation} = reset(h, range, unit, calendar, previous, t)
        {{:rollover, first}, continuation}

      %Range{} = range ->
        %Range{first: first, last: last, step: step} =
          adjusted_range(range, unit, calendar, previous)

        {{:rollover, first}, continuation(source, [(first + step)..last//step | t], unit)}

      first ->
        {{:rollover, first}, continuation(source, t, unit)}
    end
  end

  def backtrack(previous, calendar) do
    previous
    |> reverse()
    |> do_next(calendar, previous)
    |> reverse()
  end

  defp reverse({:rollover, list}), do: Enum.reverse(list)
  defp reverse(list), do: Enum.reverse(list)

  @doc false
  def adjusted_range(%Range{first: first, last: last, step: step}, _unit, _calendar, _previous)
      when first >= 0 and last >= first and step > 0 do
    %Range{first: first, last: last, step: step}
  end

  def adjusted_range(range, unit, calendar, previous) do
    units = [{unit, range} | current_units(previous)] |> Enum.reverse()

    {_unit, range} =
      units
      |> Validation.resolve(calendar)
      |> Enum.reverse()
      |> hd

    range
  end

  def current_units(units) do
    Enum.map(units, fn
      {unit, list} when is_list(list) -> {unit, extract_first(list)}
      {unit, {current, _fun}} -> {unit, current}
      {unit, value} -> {unit, value}
    end)
  end

  def extract_first([%Range{first: first} | _rest]), do: first
  def extract_first([first | _rest]), do: first

  # Returns the range of integers sharing `value`'s first `n`
  # digits. Honours sign: for `value < 0` the range runs from
  # most-negative to least-negative so iteration surfaces
  # "larger magnitude first" (matches the parser's intuition
  # that `-1950S2` covers `-1999..-1900`).
  defp significant_digits_range(value, n) when is_integer(value) and is_integer(n) and n > 0 do
    digit_count = digit_count(value)

    cond do
      n >= digit_count ->
        value..value

      value >= 0 ->
        scale = integer_pow10(digit_count - n)
        prefix = div(value, scale) * scale
        prefix..(prefix + scale - 1)

      true ->
        scale = integer_pow10(digit_count - n)
        prefix = div(-value, scale) * scale
        -(prefix + scale - 1)..-prefix
    end
  end

  defp digit_count(0), do: 1
  defp digit_count(n) when n < 0, do: digit_count(-n)
  defp digit_count(n), do: length(Integer.digits(n))

  defp integer_pow10(0), do: 1
  defp integer_pow10(n) when n > 0, do: 10 * integer_pow10(n - 1)

  @doc """
  Strips the functions from return tuples to produce
  a clean structure to pass to functions

  """
  def collect(%Tempo{time: units} = tempo) do
    case collect(units) do
      nil -> nil
      other -> %{tempo | time: other}
    end
  end

  def collect([]) do
    []
  end

  def collect([{:no_cycles, list}]) do
    list
  end

  def collect([{value, fun} | t]) when is_function(fun) do
    [value | collect(t)]
  end

  def collect([{unit, {acc, fun}} | t]) when is_function(fun) do
    [{unit, acc} | collect(t)]
  end

  def collect([h | t]) do
    [h | collect(t)]
  end

  def explicitly_enumerable?(%Tempo{time: time}) do
    Enum.any?(time, fn
      # A selection is a constraint, not a sequence — it doesn't
      # make the value enumerable on its own. Without this guard
      # the `is_list(value)` rule below would match a selection's
      # inner keyword list and skip implicit enumeration.
      {:selection, _} -> false
      {_unit, value} when is_list(value) -> true
      {_unit, :any} -> true
      {_unit, {:mask, _}} -> true
      {_unit, {:group, _}} -> true
      {_unit, {_value, continuation}} when is_function(continuation) -> true
      {_unit, continuation} when is_function(continuation) -> false
      _other -> false
    end)
  end

  def add_implicit_enumeration(%Tempo{time: time, calendar: calendar} = tempo) do
    {unit, _span} = Tempo.resolution(tempo)

    case Unit.implicit_enumerator(unit, calendar) do
      nil ->
        # No finer unit exists for implicit enumeration. A fully
        # resolved value at `:second` resolution (or any other
        # finest-grained unit) is a bounded one-unit interval with
        # no sub-units to iterate over.
        raise ArgumentError,
              "Cannot enumerate a Tempo at #{inspect(unit)} resolution " <>
                "— no finer unit is defined. Got: #{inspect(tempo)}"

      {enum_unit, range} ->
        %{tempo | time: time ++ [{enum_unit, [range]}]}
    end
  end

  def maybe_add_implicit_enumeration(%Tempo{} = tempo) do
    if explicitly_enumerable?(tempo) do
      tempo
    else
      add_implicit_enumeration(tempo)
    end
  end

  def merge(base, from) do
    Enum.reduce(from, base, fn {unit, value}, acc ->
      Keyword.update(acc, unit, value, fn _existing -> value end)
    end)
    |> Unit.sort(:desc)
  end
end
