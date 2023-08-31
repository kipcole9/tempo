defimpl Enumerable, for: Tempo do
  @moduledoc false

  alias Tempo.Enumeration
  alias Tempo.Validation

  # TODO Implement Enumerable.count
  # Count can be calculated from ranges/sets in all
  # cases except where there is group or selection involved
  # and therefore we would need to evaluate each date/time

  @impl Enumerable
  def count(_array) do
    {:error, __MODULE__}
  end

  # TODO Implement Enumerable.member?
  # Similar to the above, we can check inclusion by checking against
  # the bounds of each range/set

  @impl Enumerable
  def member?(_array, _element) do
    {:error, __MODULE__}
  end

  # TODO Implement Enumerable.slice
  # As for the above, we could calculate the bounds
  # of each range/set and calculate their values
  # based upon the catesian product of the bounds

  @impl Enumerable
  def slice(_enum) do
    {:error, __MODULE__}
  end

  @impl Enumerable
  def reduce(enum, {:cont, acc}, fun) do
    enum = make_enum(enum)

    case Enumeration.next(enum) do
      nil ->
        {:done, acc}

      next ->
        tempo = Enumeration.collect(next)
        reduce(next, fun.(tempo, acc), fun)
    end
  end

  def reduce(_enum, {:halt, acc}, _fun) do
    {:halted, acc}
  end

  def reduce(enum, {:suspend, acc}, fun) do
    {:suspended, acc, &reduce(enum, &1, fun)}
  end

  defp make_enum(%Tempo{} = tempo) do
    {:ok, tempo} =
      tempo
      |> Enumeration.maybe_add_implicit_enumeration()
      |> Validation.validate()

    tempo
  end
end
