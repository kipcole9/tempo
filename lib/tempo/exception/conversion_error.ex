defmodule Tempo.ConversionError do
  @moduledoc """
  Exception raised when a `Tempo` value cannot be converted to
  the requested target — typically a standard-library
  `t:Date.t/0`, `t:Time.t/0`, `t:NaiveDateTime.t/0`, or
  `t:DateTime.t/0`, or in the reverse direction an ISO 8601 or
  IXDTF encoding that the target type does not support.

  """

  defexception [:value, :target, :reason]

  @type t :: %__MODULE__{
          value: any() | nil,
          target: atom() | module() | String.t() | nil,
          reason: atom() | String.t() | nil
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{reason: reason}) when is_binary(reason), do: reason

  def message(%__MODULE__{value: value, target: target})
      when not is_nil(value) and not is_nil(target) do
    "Cannot convert #{inspect(value)} to #{describe_target(target)}"
  end

  def message(%__MODULE__{target: target}) when not is_nil(target) do
    "Invalid #{describe_target(target)}"
  end

  def message(%__MODULE__{}), do: "Conversion failed"

  defp describe_target(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp describe_target(other), do: inspect(other)
end
