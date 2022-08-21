defmodule Tempo.Set do
  defstruct [:type, :set]

  def new(tokens, type) do
    %__MODULE__{type: type, set: tokens}
  end
end