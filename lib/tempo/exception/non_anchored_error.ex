defmodule Tempo.NonAnchoredError do
  @moduledoc """
  Exception raised when an operation requires a `Tempo` value
  anchored to the time line (that is, carrying at least a
  year component) but the caller supplied a non-anchored value.

  Non-anchored values express a time-of-day axis ("every morning
  at 06:00") without a specific location on the time line. Use
  `Tempo.anchor/2` to compose such a value with a date before
  attempting operations that require a UTC projection.

  """

  defexception [:operation, :value]

  @type t :: %__MODULE__{
          operation: atom() | String.t() | nil,
          value: Tempo.t() | nil
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{operation: op}) when not is_nil(op) do
    "Cannot #{describe_operation(op)} on a non-anchored Tempo (no :year component). " <>
      "Non-anchored values live on the time-of-day axis; anchor them first " <>
      "via `Tempo.anchor/2`."
  end

  def message(%__MODULE__{}) do
    "Operation requires an anchored Tempo (a year component)"
  end

  defp describe_operation(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp describe_operation(string) when is_binary(string), do: string
end
