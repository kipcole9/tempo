defimpl Enumerable, for: Tempo.Set do
  @impl Enumerable
  def count(_array) do
    {:error, __MODULE__}
  end

  @impl Enumerable
  def member?(_array, _element) do
    {:error, __MODULE__}
  end

  @impl Enumerable
  def slice(_array) do
    {:error, __MODULE__}
  end

  @impl Enumerable
  def reduce(%Tempo.Set{set: set, type: _type}, {:cont, acc}, fun) do
    reduce(set, {:cont, acc}, fun)
  end

  def reduce([], {:cont, acc}, _fun) do
    {:halted, acc}
  end

  def reduce([next | rest], {:cont, acc}, fun) do
    reduce(rest, fun.(next, acc), fun)
  end

  def reduce(_enum, {:halt, acc}, _fun) do
    {:halted, acc}
  end

  def reduce(enum, {:suspend, acc}, fun) do
    {:suspended, acc, &reduce(enum, &1, fun)}
  end
end
