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
  Returns a function that when called will return
  the next cycle value in a sequence.

  When the sequence cycles back to the start
  it returns `{:rollover, value}` to signal
  the rollover.

  """
  def cycle(list) when is_list(list) do
    cycle(list, list)
  end

  def cycle(%Range{} = range) do
    cycle(range, range)
  end

  defp cycle([h | t] = source, list) do
    case list do
      [] -> {{:rollover, h}, fn -> cycle(source, t) end}
      [head | tail] -> {head, fn -> cycle(source, tail) end}
    end
  end

  defp cycle(source, %Range{first: first, last: last, step: step} = range) do
    if range.first > source.last do
      {{:rollover, source.first}, fn -> cycle(source, (source.first + source.step)..last//step) end}
    else
      {range.first, fn -> cycle(source, (first + step)..last//step) end}
    end
  end

  def next(list) do
    case do_next(list) do
      {:rollover, _list} -> nil
      {:no_cycles, _list} -> nil
      list -> list
    end
  end

  def do_next([]) do
    []
  end

  def do_next([%Range{} = h | t]) do
    [cycle(h) | List.wrap(do_next(t))]
  end

  def do_next([h | t]) when is_list(h) do
    [cycle(h) | List.wrap(do_next(t))]
  end

  def do_next([{_acc, fun}]) when is_function(fun) do
    case fun.() do
      {{:rollover, acc}, fun} ->
        {:rollover, [{acc, fun}]}
      {acc, fun} ->
        [{acc, fun}]
    end
  end

  def do_next([{acc, fun} | t]) when is_function(fun) do
    case do_next(t) do
      {state, list} when state in [:rollover, :no_cycles] ->
        case fun.() do
          {{:rollover, acc}, fun} ->
            {:rollover, [{acc, fun} | list]}
          {acc, fun} ->
            [{acc, fun} | list]
        end

      list ->
        [{acc, fun} | list]
    end
  end

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
  Strips the functions from return tuples to produce
  a clean structure to pass to functions
  """
  def collect([]) do
    []
  end

  def collect([{:no_cycles, list}]) do
    list
  end

  def collect([{value, fun} | t]) when is_function(fun) do
    [value | collect(t)]
  end

  def collect([h | t]) do
    [h | collect(t)]
  end
end