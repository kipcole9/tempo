defmodule Tempo.Algebra do
  alias Tempo.Validation
  alias Tempo.Iso8601.Unit

  defguard is_continuation(unit, fun) when is_atom(unit) and is_function(fun)
  defguard is_unit(unit, value) when is_atom(unit) and is_list(value) or is_number(value)

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

  def do_next([{unit, value} | t], calendar, previous) when is_unit(unit, value) do
    cycle =
      case cycle(value, unit, calendar, previous) do
        {{:rollover, value}, continuation} when is_number(value) -> {value, continuation}
        other -> other
      end

    [{unit, cycle} | List.wrap(do_next(t, calendar, [{unit, value} | previous]))]
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

      [%Range{first: first, last: last} = range | rest] when first <= last ->
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
    previous =
      previous
      |> Enum.reverse()
      |> do_next(calendar, previous)

    case previous do
      {:rollover, list} -> Enum.reverse(list)
      other -> Enum.reverse(other)
    end
  end

  defp adjusted_range(%Range{first: first, last: last, step: step}, _unit, _calendar, _previous)
      when first >= 0 and last >= first and step > 0 do
    %Range{first: first, last: last, step: step}
  end

  defp adjusted_range(range, unit, calendar, previous) do
    units = [{unit, range} | current_units(previous)] |> Enum.reverse()

    {_unit, range} =
      units
      |> Validation.resolve(calendar)
      |> Enum.reverse()
      |> hd

    range
  end

  def current_units(units) do
    Enum.map units, fn
      {unit, list} when is_list(list) -> {unit, extract_first(list)}
      {unit, {current, _fun}} -> {unit, current}
      {unit, value} -> {unit, value}
    end
  end

  def extract_first([%Range{first: first} | _rest]), do: first
  def extract_first([first | _rest]), do: first

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
      {_unit, value} when is_list(value) -> true
      {_unit, {_value, continuation}} when is_function(continuation) -> true
      {_unit, continuation} when is_function(continuation) -> false
      _other -> false
    end)
  end

  def add_implicit_enumeration(%Tempo{time: time, calendar: calendar} = tempo) do
    {unit, _span} = Tempo.resolution(tempo)
    {unit, range} = Unit.implicit_enumerator(unit, calendar)
    %{tempo| time: time ++ [{unit, [range]}]}
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