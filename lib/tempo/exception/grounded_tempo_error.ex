defmodule Tempo.GroundedTempoError do
  @moduledoc """
  Exception raised when an operation requires a floating `Tempo`
  value but the supplied value is grounded — it already carries an
  `[IANA/Zone]` tag, a `Z`, or a numeric offset.

  `Tempo.in_zone/2` places a floating value into a zone; a value that
  is already grounded should be moved with `Tempo.shift_zone/2`
  instead, which re-computes the wall clock to preserve the instant.

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
    "Cannot #{describe_operation(op)} on a grounded Tempo (it already carries a " <>
      "zone or offset). Use `Tempo.shift_zone/2` to move it to another zone instead."
  end

  def message(%__MODULE__{}) do
    "Operation requires a floating Tempo (this value already carries a zone or offset)"
  end

  defp describe_operation(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp describe_operation(string) when is_binary(string), do: string
end
