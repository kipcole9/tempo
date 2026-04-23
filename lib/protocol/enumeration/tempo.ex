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

        case zone_status(tempo) do
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

  defp make_enum(%Tempo{} = tempo) do
    {:ok, tempo} =
      tempo
      |> Enumeration.maybe_add_implicit_enumeration()
      |> Validation.validate()

    tempo
  end

  # Classify a Tempo value against its configured zone:
  #
  #   * `:ok` — no zone, no time-of-day, or the wall time resolves
  #     to a single unambiguous UTC instant.
  #
  #   * `:gap` — wall time falls in a DST spring-forward gap; the
  #     clock never shows it.
  #
  #   * `{:ambiguous, first_shift, second_shift}` — wall time
  #     happens twice (DST fall-back). The shifts are keyword lists
  #     derived from the pre- and post-transition total UTC offset.
  defp zone_status(%Tempo{extended: %{zone_id: zone}} = tempo) when is_binary(zone) do
    with %NaiveDateTime{} = naive <- naive_from_tempo(tempo),
         db when is_atom(db) <- Calendar.get_time_zone_database() do
      case DateTime.from_naive(naive, zone, db) do
        {:gap, _before, _after} ->
          :gap

        {:ambiguous, first, second} ->
          {:ambiguous, shift_from_datetime(first), shift_from_datetime(second)}

        _ ->
          :ok
      end
    else
      _ -> :ok
    end
  end

  defp zone_status(_tempo), do: :ok

  # Extract `year, month, day, hour, minute, second` from a Tempo's
  # time keyword list and build a NaiveDateTime, filling missing
  # minute/second with 0. Returns `nil` if the value doesn't have
  # enough components to form a NaiveDateTime.
  defp naive_from_tempo(%Tempo{time: time}) do
    with year when is_integer(year) <- Keyword.get(time, :year),
         month when is_integer(month) <- Keyword.get(time, :month),
         day when is_integer(day) <- Keyword.get(time, :day),
         hour when is_integer(hour) <- Keyword.get(time, :hour) do
      minute = Keyword.get(time, :minute, 0)
      second = Keyword.get(time, :second, 0)

      case NaiveDateTime.new(year, month, day, hour, minute, second) do
        {:ok, naive} -> naive
        _ -> nil
      end
    else
      _ -> nil
    end
  end

  # Convert a DateTime's total offset (`utc_offset + std_offset`, in
  # seconds) to a Tempo `:shift` keyword list. Drops the `:minute`
  # element when the offset is an exact number of hours — matches
  # the shape parsed from IXDTF `+HH` vs `+HH:MM`.
  defp shift_from_datetime(%DateTime{utc_offset: utc, std_offset: std}) do
    total = utc + std
    sign = if total < 0, do: -1, else: 1
    abs_total = abs(total)
    hours = div(abs_total, 3600)
    minutes = div(rem(abs_total, 3600), 60)

    case minutes do
      0 -> [hour: sign * hours]
      m -> [hour: sign * hours, minute: sign * m]
    end
  end
end
