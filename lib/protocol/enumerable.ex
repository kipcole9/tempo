defimpl Enumerable, for: Tempo do
  alias Tempo.Algebra
  alias Tempo.Validation

  # Count can be calculated from ranges/sets in all
  # cases except where there is groupgin involved and therefore
  # we would need to evaluate each date/time

  @impl Enumerable
  def count(_array) do
    {:error, __MODULE__}
  end

  # Similar to the above, we can check inclusion by checking against
  # the bounds of each range/set

  @impl Enumerable
  def member?(_array, _element) do
    {:error, __MODULE__}
  end

  # As for the above, we could calculate the bounds
  # of each range/set and calculate their values
  # based upon the catesian product of the bounds

  @impl Enumerable
  def slice(_array) do
    {:error, __MODULE__}
  end

  @impl Enumerable
  def reduce(enum, {:cont, acc}, fun) do
    enum = Tempo.Algebra.maybe_add_implicit_enumeration(enum)
    case Algebra.next(enum) do
      nil ->
        {:done, acc}

      next ->
        {:ok, tempo} =
          next
          |> Algebra.collect()
          |> Validation.validate(next.calendar)

        reduce(next, fun.(tempo, acc), fun)
    end
  end

  def reduce(_enum, {:halt, acc}, _fun) do
    {:halted, acc}
  end

  def reduce(enum, {:suspend, acc}, fun) do
    {:suspended, acc, &reduce(enum, &1, fun)}
  end

end