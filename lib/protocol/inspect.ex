defimpl Inspect, for: Tempo do
  def inspect(tempo, _opts) do
    Tempo.Inspect.inspect(tempo)
  end
end

defimpl Inspect, for: Tempo.Set do
  def inspect(tempo, _opts) do
    Tempo.Inspect.inspect(tempo)
  end
end

defimpl Inspect, for: Tempo.Interval do
  def inspect(tempo, _opts) do
    Tempo.Inspect.inspect(tempo)
  end
end

defimpl Inspect, for: Tempo.Duration do
  def inspect(tempo, _opts) do
    Tempo.Inspect.inspect(tempo)
  end
end
