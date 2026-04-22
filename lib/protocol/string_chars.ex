defimpl String.Chars, for: Tempo do
  def to_string(tempo), do: Tempo.to_string(tempo)
end

defimpl String.Chars, for: Tempo.Interval do
  def to_string(interval), do: Tempo.to_string(interval)
end

defimpl String.Chars, for: Tempo.IntervalSet do
  def to_string(set), do: Tempo.to_string(set)
end
