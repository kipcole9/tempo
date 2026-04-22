defmodule Tempo.MaterialisationError do
  @moduledoc """
  Exception raised when a value cannot be materialised into an
  explicit `Tempo.Interval` or `Tempo.IntervalSet`.

  Reasons include a bare `Tempo.Duration` (no time-line anchor),
  a one-of `Tempo.Set` (epistemic disjunction, not an interval
  list), and a `Tempo` already at its finest resolution (no
  finer unit to bound the implicit span).

  """

  defexception [:value, :reason]

  @type reason ::
          :bare_duration
          | :one_of_set
          | :finest_resolution
          | atom()
          | String.t()

  @type t :: %__MODULE__{
          value: any() | nil,
          reason: reason() | nil
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{reason: :bare_duration}) do
    "Cannot materialise a Tempo.Duration into an interval — a duration has no " <>
      "anchor on the time line."
  end

  def message(%__MODULE__{reason: :one_of_set}) do
    "Cannot materialise a one-of Tempo.Set into an interval — epistemic " <>
      "disjunction is not an interval list. Pick one member or handle the " <>
      "disjunction explicitly."
  end

  def message(%__MODULE__{reason: :finest_resolution, value: value}) when not is_nil(value) do
    "Cannot materialise #{inspect(value)} at its finest resolution into an " <>
      "explicit interval — no finer unit exists to bound the span."
  end

  def message(%__MODULE__{reason: :finest_resolution}) do
    "Cannot materialise a Tempo at its finest resolution into an explicit interval"
  end

  def message(%__MODULE__{reason: reason}) when is_binary(reason), do: reason

  def message(%__MODULE__{}), do: "Cannot materialise value into an interval"
end
