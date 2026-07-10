# A value carrying a construct with no ISO 8601 representation (a cron
# nearest-weekday recurrence) cannot be rendered as a `~o"…"` sigil. The
# encoder raises `Tempo.Iso8601EncodeError`; rendering for humans must
# never crash, so each implementation falls back to a labelled struct
# view. This rescue is confined to that one exception — any other error
# still surfaces.
defmodule Tempo.Inspect.Fallback do
  @moduledoc false

  def safe(value, tag, fun) do
    fun.(value)
  rescue
    Tempo.Iso8601EncodeError -> "#" <> tag <> "<not ISO 8601 expressible>"
  end
end

defimpl Inspect, for: Tempo do
  def inspect(tempo, _opts) do
    Tempo.Inspect.Fallback.safe(tempo, "Tempo", &Tempo.Inspect.inspect/1)
  end
end

defimpl Inspect, for: Tempo.Set do
  def inspect(tempo, _opts) do
    Tempo.Inspect.Fallback.safe(tempo, "Tempo.Set", &Tempo.Inspect.inspect/1)
  end
end

defimpl Inspect, for: Tempo.Interval do
  def inspect(tempo, _opts) do
    Tempo.Inspect.Fallback.safe(tempo, "Tempo.Interval", &Tempo.Inspect.inspect/1)
  end
end

defimpl Inspect, for: Tempo.Duration do
  def inspect(tempo, _opts) do
    Tempo.Inspect.Fallback.safe(tempo, "Tempo.Duration", &Tempo.Inspect.inspect/1)
  end
end

defimpl Inspect, for: Tempo.IntervalSet do
  def inspect(set, opts) do
    Tempo.Inspect.inspect_interval_set(set, opts)
  end
end
