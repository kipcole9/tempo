defimpl Enumerable, for: Tempo do
  @moduledoc false

  alias Tempo.Enumeration
  alias Tempo.Enumeration.Zone
  alias Tempo.Validation

  # Implicit enumeration of a resolved `%Tempo{}` walks the same
  # sequence as forward-stepping its materialised interval (see
  # `to_interval/1`), so `count/1`, `member?/2`, and `slice/1` reuse
  # the interval's O(1) `Tempo.Interval.Steps`-backed implementations.
  # Those are DST-aware in the same way as `reduce/3` here — a
  # spring-forward gap hour is not counted/sliced, a fall-back hour is
  # counted twice — so the fast paths agree with the walk.
  #
  # Values that don't materialise to a single interval — groups,
  # selections, ranges, sets, masks — return `{:error, __MODULE__}`,
  # so `Enum` falls back to the reduce-based traversal that handles
  # them.

  @impl Enumerable
  def count(%Tempo{} = tempo) do
    case single_interval(tempo) do
      {:ok, interval} -> Enumerable.count(interval)
      :error -> {:error, __MODULE__}
    end
  end

  @impl Enumerable
  def member?(%Tempo{} = tempo, %Tempo{} = element) do
    case single_interval(tempo) do
      {:ok, interval} -> Enumerable.member?(interval, element)
      :error -> {:error, __MODULE__}
    end
  end

  def member?(_tempo, _element) do
    {:error, __MODULE__}
  end

  @impl Enumerable
  def slice(%Tempo{} = tempo) do
    case single_interval(tempo) do
      {:ok, interval} -> Enumerable.slice(interval)
      :error -> {:error, __MODULE__}
    end
  end

  defp single_interval(%Tempo{time: time} = tempo) do
    # A masked value materialises to a single block interval, but its
    # enumeration walks the mask's *candidates* (e.g. `2020-06-XX` is 30
    # day-candidates, not one month-long span), so the interval fast paths
    # would disagree with `reduce/3`. Force the reduce fallback for masks.
    if Enum.any?(time, &match?({_unit, {:mask, _mask}}, &1)) do
      :error
    else
      case Tempo.to_interval(tempo) do
        {:ok, %Tempo.Interval{} = interval} -> {:ok, interval}
        _ -> :error
      end
    end
  end

  @impl Enumerable
  def reduce(enum, {:cont, acc}, fun) do
    enum = make_enum(enum)

    case Enumeration.next(enum) do
      nil ->
        {:done, acc}

      next ->
        tempo = Enumeration.collect(next)

        case Zone.zone_status(tempo) do
          # Wall clock never shows this moment (DST spring-forward):
          # skip and advance.
          :gap ->
            reduce(next, {:cont, acc}, fun)

          # Wall clock shows this moment twice (DST fall-back): emit
          # both occurrences, distinguished by their `:shift` — first
          # with the pre-transition offset (e.g. AEDT +11), second
          # with the post-transition offset (AEST +10). RFC 9557
          # IXDTF treats the explicit numeric offset as the fold
          # disambiguator, so the two emitted Tempos round-trip as
          # distinct values and compare as distinct UTC instants.
          {:ambiguous, first_shift, second_shift} ->
            emit_values(
              [%{tempo | shift: first_shift}, %{tempo | shift: second_shift}],
              next,
              acc,
              fun
            )

          :ok ->
            reduce(next, fun.(tempo, acc), fun)
        end
    end
  end

  def reduce(_enum, {:halt, acc}, _fun) do
    {:halted, acc}
  end

  def reduce(enum, {:suspend, acc}, fun) do
    {:suspended, acc, &reduce(enum, &1, fun)}
  end

  # Apply `fun` to each pending value (typically the two occurrences
  # of a DST fold), threading the accumulator, then continue normal
  # iteration from `next`.
  defp emit_values([], next, acc, fun), do: reduce(next, {:cont, acc}, fun)

  defp emit_values([value | rest], next, acc, fun) do
    case fun.(value, acc) do
      {:cont, acc2} ->
        emit_values(rest, next, acc2, fun)

      {:halt, acc2} ->
        {:halted, acc2}

      {:suspend, acc2} ->
        {:suspended, acc2, &emit_values_after_suspend(rest, next, fun, &1)}
    end
  end

  defp emit_values_after_suspend(rest, next, fun, {:cont, acc}),
    do: emit_values(rest, next, acc, fun)

  defp emit_values_after_suspend(_rest, _next, _fun, {:halt, acc}),
    do: {:halted, acc}

  defp emit_values_after_suspend(rest, next, fun, {:suspend, acc}),
    do: {:suspended, acc, &emit_values_after_suspend(rest, next, fun, &1)}

  defp make_enum(%Tempo{calendar: calendar} = tempo) do
    # Resolve the implicit `1..-1` enumeration range against the
    # value's *own* calendar. Without the explicit calendar,
    # `Validation.validate/1` defaults to Gregorian, so a Coptic
    # month would enumerate 31 days (January) and a 13-month calendar
    # year only 12 months. `Enumeration.next/1` already threads the
    # calendar; this lines the range resolution up with it.
    {:ok, tempo} =
      tempo
      |> Enumeration.maybe_add_implicit_enumeration()
      |> Validation.validate(calendar)

    tempo
  end
end
