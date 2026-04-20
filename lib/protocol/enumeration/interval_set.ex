defimpl Enumerable, for: Tempo.IntervalSet do
  @moduledoc false

  # An IntervalSet is a sorted, non-overlapping list of intervals.
  # Enumeration walks each interval in sequence, yielding the
  # forward-stepped values produced by `Enumerable.Tempo.Interval`.
  # The result is a flat sequence of `%Tempo{}` values in time
  # order — the natural input for free/busy scans and calendar
  # renderings.

  @impl Enumerable
  def count(_set) do
    # v1: consistent with Enumerable.Tempo.Interval — precise
    # counts are deferred to the set-operations milestone.
    {:error, __MODULE__}
  end

  @impl Enumerable
  def member?(_set, _element) do
    {:error, __MODULE__}
  end

  @impl Enumerable
  def slice(_set) do
    {:error, __MODULE__}
  end

  @impl Enumerable
  def reduce(%Tempo.IntervalSet{intervals: intervals}, acc, fun) do
    do_reduce(intervals, acc, fun)
  end

  defp do_reduce(_intervals, {:halt, acc}, _fun) do
    {:halted, acc}
  end

  defp do_reduce(intervals, {:suspend, acc}, fun) do
    {:suspended, acc, &do_reduce(intervals, &1, fun)}
  end

  defp do_reduce([], {:cont, acc}, _fun) do
    {:done, acc}
  end

  # Reduce the current interval, capturing its result. On `:done`,
  # advance to the next interval. On `:halted` / `:suspended`,
  # propagate upward and preserve the continuation so the enumeration
  # resumes mid-set.

  defp do_reduce([interval | rest], {:cont, acc}, fun) do
    case Enumerable.reduce(interval, {:cont, acc}, fun) do
      {:done, acc} ->
        do_reduce(rest, {:cont, acc}, fun)

      {:halted, acc} ->
        {:halted, acc}

      {:suspended, acc, continuation} ->
        {:suspended, acc, &resume_current(continuation, rest, &1, fun)}
    end
  end

  # When the current interval's enumeration is suspended, resuming
  # first finishes that interval and only then moves to the next.
  defp resume_current(continuation, rest, acc, fun) do
    case continuation.(acc) do
      {:done, acc} ->
        do_reduce(rest, {:cont, acc}, fun)

      {:halted, acc} ->
        {:halted, acc}

      {:suspended, acc, next_continuation} ->
        {:suspended, acc, &resume_current(next_continuation, rest, &1, fun)}
    end
  end
end
