defmodule Tempo.Shift do
  @moduledoc """
  Shift a Tempo struct along the timeline.

  If the resolution of the shift is the same or
  less than the resolution of the Tempo then is
  simply an addition.

  If the resolution of the shift is greater
  then we need to convert the tempo to an interval
  if it is not already.

  """

  def shift(time, shift) do

  end
end