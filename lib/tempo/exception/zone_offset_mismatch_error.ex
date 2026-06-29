defmodule Tempo.ZoneOffsetMismatchError do
  @moduledoc """
  Exception raised (or returned) when an IXDTF value's explicit numeric
  offset disagrees with its IANA time zone at the value's wall instant.

  An IXDTF string may carry both a numeric offset and a zone identifier,
  for example `2022-11-20T10:37:00+05:00[Europe/Paris]`. Paris is
  `+01:00` in November, so the stated `+05:00` is inconsistent. RFC 9557
  §4.2 identifies this as a condition a consumer MAY treat as an error;
  Tempo surfaces it through `Tempo.validate_zone_offset/1` and the
  `strict: true` parse option rather than silently letting the zone win.

  """

  defexception [:zone_id, :wall_time, :stated_offset, :zone_offsets]

  @type t :: %__MODULE__{
          zone_id: String.t() | nil,
          wall_time: String.t() | nil,
          stated_offset: integer() | nil,
          zone_offsets: [integer()]
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{
        zone_id: zone_id,
        wall_time: wall_time,
        stated_offset: stated,
        zone_offsets: zone_offsets
      }) do
    actual =
      zone_offsets
      |> Enum.map(&format_offset/1)
      |> Enum.join(" or ")

    "Stated offset #{format_offset(stated)} disagrees with #{inspect(zone_id)} " <>
      "(#{actual}) at #{wall_time}."
  end

  @doc """
  Format an offset in seconds as a signed `±HH:MM` string.

  ### Examples

      iex> Tempo.ZoneOffsetMismatchError.format_offset(3600)
      "+01:00"

      iex> Tempo.ZoneOffsetMismatchError.format_offset(-18000)
      "-05:00"

  """
  @spec format_offset(integer()) :: String.t()
  def format_offset(seconds) when is_integer(seconds) do
    sign = if seconds < 0, do: "-", else: "+"
    total_minutes = div(abs(seconds), 60)
    hours = div(total_minutes, 60)
    minutes = rem(total_minutes, 60)

    "#{sign}#{pad(hours)}:#{pad(minutes)}"
  end

  defp pad(value), do: String.pad_leading(Integer.to_string(value), 2, "0")
end
