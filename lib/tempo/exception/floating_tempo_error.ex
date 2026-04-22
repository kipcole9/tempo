defmodule Tempo.FloatingTempoError do
  @moduledoc """
  Exception raised when an operation requires zone or offset
  information but the supplied `Tempo` value is floating — no
  `[IANA/Zone]` tag, no `Z`, no numeric offset.

  Floating values are deliberate (see the scheduling guide) but
  cannot be projected to UTC, so any operation that needs a
  universal instant rejects them.

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
    "Cannot #{describe_operation(op)} on a floating Tempo (no zone or offset information). " <>
      "Attach a zone via an IXDTF suffix (`[Europe/Paris]`) or an offset " <>
      "(`Z` or `+HH:MM`) first."
  end

  def message(%__MODULE__{}) do
    "Operation requires a zoned Tempo (floating values have no UTC projection)"
  end

  defp describe_operation(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp describe_operation(string) when is_binary(string), do: string
end
