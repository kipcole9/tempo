defmodule Tempo.Duration do
  defstruct [:time]

  def new(tokens) do
    %__MODULE__{time: tokens}
  end
end
