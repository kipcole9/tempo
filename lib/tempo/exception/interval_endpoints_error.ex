defmodule Tempo.IntervalEndpointsError do
  @moduledoc """
  Exception raised when an operation requires an interval whose
  endpoints are both concrete `%Tempo{}` structs, but the
  supplied interval carries recurrence, duration-only, or
  otherwise non-concrete endpoints.

  Materialise the interval with `Tempo.to_interval/1,2` first.

  """

  defexception [:operation, :interval, :reason]

  @type t :: %__MODULE__{
          operation: atom() | String.t() | nil,
          interval: Tempo.Interval.t() | nil,
          reason: atom() | String.t() | nil
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{reason: reason}) when is_binary(reason), do: reason

  def message(%__MODULE__{operation: op}) when not is_nil(op) do
    "#{describe_operation(op)} requires an interval with concrete endpoints. " <>
      "Materialise recurrence / duration-only or open-ended intervals via " <>
      "`Tempo.to_interval/1,2` first."
  end

  def message(%__MODULE__{}) do
    "Operation requires an interval with concrete endpoints (not open-ended)"
  end

  defp describe_operation(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp describe_operation(string) when is_binary(string), do: string
end
