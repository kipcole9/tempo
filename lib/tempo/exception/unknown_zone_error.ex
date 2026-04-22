defmodule Tempo.UnknownZoneError do
  @moduledoc """
  Exception raised when a time-zone identifier is not present in
  the loaded `Tzdata` database.

  """

  defexception [:zone_id]

  @type t :: %__MODULE__{
          zone_id: String.t() | nil
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{zone_id: zone_id}) when is_binary(zone_id) do
    "Unknown IANA time zone: #{inspect(zone_id)}"
  end

  def message(%__MODULE__{}), do: "Unknown IANA time zone"
end
