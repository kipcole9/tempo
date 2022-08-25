defmodule Tempo.Algebra do
  alias Tempo.Validation

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
      {:no_cycles, _list} -> nil
      list -> list
    end
  end

  def do_next([], _calendar, _previous) do
    []
  end

  def do_next([{unit, value} | t], calendar, previous) when is_unit(unit, value) do
    [{unit, cycle(value, unit, calendar, previous)} |
      List.wrap(do_next(t, [{unit, value} | previous], calendar))]
  end

  def do_next([{unit, {_acc, fun}}], calendar, previous) when is_continuation(unit, fun) do
    case fun.(calendar, previous) do
      {{:rollover, acc}, fun} ->
        {:rollover, [{unit, {acc, fun}}]}
      {acc, fun} ->
        [{unit, {acc, fun}}]
    end
  end

  def do_next([{unit, {current, fun}} | t], calendar, previous) when is_continuation(unit, fun) do
    case do_next(t, calendar, previous) do
      {state, list} when state in [:rollover, :no_cycles] ->
        case fun.(calendar, previous) do
          {{:rollover, current}, fun} ->
            {:rollover, [{unit, {current, fun}} | list]}

          {current, fun} ->
            [{unit, {current, fun}} | list]
        end

      list ->
        [{unit, {current, fun}} | list]
    end
  end

  def do_next({:no_cycles, h}, _calendar, _previous) do
    {:no_cycles, h}
  end

  def do_next([{:no_cycles, h}], _calendar, _previous) do
    {:no_cycles, List.wrap(h)}
  end

  def do_next([h], _calendar, _previous) do
    {:no_cycles, [h]}
  end

  def do_next([h | t], calendar, previous) do
    case do_next(t, calendar, previous) do
      {:no_cycles, list} ->
        {:no_cycles, [h | list]}

      {:rollover, list} ->
        {:rollover, [h | list]}

      list ->
        [h | list]
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
    cycle([source], [source], unit, calendar, previous)
  end

  def cycle(source, unit, calendar, previous) do
    cycle(source, source, unit, calendar, previous)
  end

  def  cycle(source, list, unit, calendar, previous) do
    case list do
      [] ->
        rollover(source, unit, calendar, previous)

      [%Range{step: step} = range | tail] when step < 1 ->
        %Range{first: first, last: last, step: step} = adjusted_range(range, unit, calendar, previous)
        {first, fn previous -> cycle(source, [(first + step)..last//step | tail], unit, calendar, previous) end}

      [%Range{first: first, last: last, step: step} | rest] when first <= last ->
        {first, fn calendar, previous -> cycle(source, [(first + step)..last//step | rest], unit, calendar, previous) end}

      [%Range{}] ->
        rollover(source, unit, calendar, previous)

      [%Range{}, next | rest] ->
        {next, fn calendar, previous -> cycle(source, rest, unit, calendar, previous) end}

      [next | rest] ->
        {next, fn calendar, previous -> cycle(source, rest, unit, calendar, previous) end}

      other when is_number(other) ->
        other
    end
  end

  defp rollover([h | t] = source, unit, calendar, previous) do
    case h do
      %Range{step: step} = range when step < 1 ->
        %Range{first: first, last: last, step: step} = adjusted_range(range, unit, calendar, previous)
        {{:rollover, first}, fn -> cycle(source, [(first + step)..last//step | t], unit, calendar, previous) end}
      %Range{first: first, last: last, step: step} ->
        {{:rollover, first}, fn calendar, previous -> cycle(source, [(first + step)..last//step | t], unit, calendar, previous) end}
      {unit, value} ->
        {unit, value}
      first ->
        {{:rollover, first}, fn calendar, previous -> cycle(source, t, unit, calendar, previous) end}
    end
  end

  defp adjusted_range(range, unit, calendar, previous) do
    units = [{unit, range} | current_units(previous)] |> Enum.reverse()

    {_unit, range} =
      units
      |> Validation.validate(calendar)
      |> Enum.reverse()
      |> hd

    range
  end

  def current_units(units) do
    Enum.map units, fn
      {unit, list} when is_list(list) -> {unit, extract_first(list)}
      {unit, {current, _fun}} -> {unit, current}
      {:no_cycles, list} -> list
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
end