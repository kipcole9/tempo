defmodule Tempo.Algebra do

  @doc """
  Expand a Tempo expression that might have
  ranges in it (one or more than one)

  """
  def expand([]) do
    []
  end

  def expand([%Range{} = range | t]) do
    accum(range, expand(t))
  end

  def expand([h | t]) do
    accum(h, expand(t))
  end

  def accum({type, %Range{} = range}, [h | _t] = list) when is_list(h) do
    Enum.flat_map(range, fn i ->
      Enum.map(list, fn elem ->
        accum({type, i}, elem)
      end)
    end)
  end

  def accum({type, %Range{} = range}, list) do
    Enum.map(range, fn i -> accum({type, i}, list) end)
  end

  def accum(elem, [h | _t] = list) when is_list(h) do
    Enum.map(list, fn e -> accum(elem, e) end)
  end

  def accum(elem, list) do
    [elem | list]
  end

  @doc """
  Get the next "odomoter reading" list of integers and ranges
  or a list of time units

  """
  def next(%Tempo{time: units} = tempo) do
    case next(units) do
      nil -> nil
      other -> %{tempo | time: other}
    end
  end

  def next(list) when is_list(list) do
    case do_next(list) do
      {:rollover, _list} -> nil
      {:no_cycles, _list} -> nil
      list -> list
    end
  end

  def do_next([]) do
    []
  end

  # def do_next([%Range{} = h | t]) do
  #   [cycle(h) | List.wrap(do_next(t))]
  # end

  def do_next([{unit, h} | t]) when is_atom(unit) and is_list(h) do
    [{unit, cycle(h)} | List.wrap(do_next(t))]
  end

  # def do_next([h | t]) when is_list(h) do
  #   [cycle(h) | List.wrap(do_next(t))]
  # end

  def do_next([{unit, {_acc, fun}}]) when is_atom(unit) and is_function(fun) do
    case fun.() do
      {{:rollover, acc}, fun} ->
        {:rollover, [{unit, {acc, fun}}]}
      {acc, fun} ->
        [{unit, {acc, fun}}]
    end
  end

  # def do_next([{_acc, fun}]) when is_function(fun) do
  #   case fun.() do
  #     {{:rollover, acc}, fun} ->
  #       {:rollover, [{acc, fun}]}
  #     {acc, fun} ->
  #       [{acc, fun}]
  #   end
  # end

  def do_next([{unit, {acc, fun}} | t]) when is_atom(unit) and is_function(fun) do
    case do_next(t) do
      {state, list} when state in [:rollover, :no_cycles] ->
        case fun.() do
          {{:rollover, acc}, fun} ->
            {:rollover, [{unit, {acc, fun}} | list]}
          {acc, fun} ->
            [{unit, {acc, fun}} | list]
        end

      list ->
        [{unit, {acc, fun}} | list]
    end
  end

  # def do_next([{acc, fun} | t]) when is_function(fun) do
  #   case do_next(t) do
  #     {state, list} when state in [:rollover, :no_cycles] ->
  #       case fun.() do
  #         {{:rollover, acc}, fun} ->
  #           {:rollover, [{acc, fun} | list]}
  #         {acc, fun} ->
  #           [{acc, fun} | list]
  #       end
  #
  #     list ->
  #       [{acc, fun} | list]
  #   end
  # end

  def do_next({:no_cycles, h}) do
    {:no_cycles, h}
  end

  def do_next([h]) do
    {:no_cycles, [h]}
  end

  def do_next([h | t]) do
    case do_next(t) do
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
  def cycle(source) when is_list(source) do
    cycle(source, source)
  end

  def cycle(%Range{} = range) do
    cycle(range, range)
  end

  defp cycle(source, list) when is_list(list)do
    case list do
      [] ->
        rollover(source)

      [%Range{first: first, last: last, step: step} | tail] when first <= last ->
        {first, fn -> cycle(source, [(first + step)..last//step | tail]) end}

      [%Range{}] ->
        rollover(source)

      [%Range{}, next | tail] ->
        {next, fn -> cycle(source, tail) end}

      [head | tail] ->
        {head, fn -> cycle(source, tail) end}
    end
  end

  defp cycle(source, %Range{first: first, last: last, step: step} = range) do
    if range.first > source.last do
      {{:rollover, source.first}, fn -> cycle(source, (source.first + source.step)..last//step) end}
    else
      {range.first, fn -> cycle(source, (first + step)..last//step) end}
    end
  end

  defp rollover([h | t] = source) do
    case h do
      %Range{first: first, step: step} = range ->
        {{:rollover, first}, fn -> cycle(source, [%{range | first: first + step} | t]) end}
      first ->
        {{:rollover, first}, fn -> cycle(source, t) end}
    end
  end

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