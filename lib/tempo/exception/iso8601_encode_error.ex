defmodule Tempo.Iso8601EncodeError do
  @moduledoc """
  Exception raised when a `Tempo` value cannot be rendered as an ISO 8601
  string because it contains a construct with no ISO 8601 representation.

  The only such construct at present is a **nearest-weekday** recurrence —
  the cron `W` day-of-month modifier (`15W`, `LW`), parsed by `Tempo.Cron`
  into a `:nearest_weekday` selection token. Like RFC 5545 `BYSETPOS`/`WKST`
  it has no ISO 8601 designator; unlike those, no project-specific
  designator was minted for it (the equivalent day-level operation is
  `Tempo.nearest_working_day/2`). Such a value round-trips only through its
  cron string, not through `Tempo.to_iso8601/1`.

  """

  defexception [:construct, :value]

  @type t :: %__MODULE__{
          construct: atom() | nil,
          value: term() | nil
        }

  @impl true
  def exception(bindings) when is_list(bindings) do
    struct!(__MODULE__, bindings)
  end

  @impl true
  def message(%__MODULE__{construct: :nearest_weekday}) do
    "Cannot encode a nearest-weekday recurrence (cron `W`, e.g. `15W`) as " <>
      "ISO 8601 — it has no ISO 8601 designator. It is expressible only as a " <>
      "cron string; for the day-level operation use `Tempo.nearest_working_day/2`."
  end

  def message(%__MODULE__{construct: construct}) do
    "Cannot encode #{inspect(construct)} as ISO 8601 — it has no ISO 8601 representation."
  end
end
