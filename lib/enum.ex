defimpl Enumerable, for: Tempo do
  alias Tempo.Algebra

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
  def reduce(enum, {:cont, acc}, fun) do
    case Algebra.next(enum) do
      nil -> {:done, acc}
      next -> reduce(next, fun.(Algebra.collect(next), acc), fun)
    end
  end

  def reduce(_enum, {:halt, acc}, _fun) do
    {:halted, acc}
  end

  def reduce(enum, {:suspend, acc}, fun) do
    {:suspended, acc, &reduce(enum, &1, fun)}
  end

end