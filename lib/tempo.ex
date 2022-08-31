defmodule Tempo do
  @moduledoc """
  Documentation for `Tempo`.

  ### Terminology

  The following terms, defined by ISO 8601, are used throughout
  Tempo. For further information consult:

  * [ISO Online browsing platform](https://www.iso.org/obp)
  * [IEC Electropedia](http://www.electropedia.org/)

  #### Date

  A [time](#time) on the the calendar time scale. Common forms of date include calendar date,
  ordinal date or week date.

  #### Time

  A mark attributed to an [instant](#instant) or a [time interval](#time_interval) on a specified
  [time scale](#time_scale).

  The term “time” is often used in common language. However, it should only be used if the
  meaning is clearly visible from the context.

  On a time scale consisting of successive time intervals, such as a clock or calendar,
  distinct instants may be expressed by the same time.

  This definition corresponds with the definition of the term “date” in
  IEC 60050-113:2011, 113-01-12.

  #### Instant

  A point on the [time axis](#time_axis). An instantaneous event occurs at a specific instant.

  #### Time axis

  A mathematical representation of the succession in time according to the space-time model
  of instantaneous events along a unique axis/

  According to the theory of special relativity, the time axis depends on the choice of a
  spatial reference frame.

  In IEC 60050-113:2011, 113-01-03, time according to the space-time model is defined to be
  the one-dimensional subspace of space-time, locally orthogonal to space.

  #### Time scale

  A system of ordered marks which can be attributed to [instants](#instant) on the
  [time axis](#time_axis), one instant being chosen as the origin.

  A time scale may amongst others be chosen as:

  * continuous, e.g. international atomic time (TAI) (see IEC 60050-713:1998, 713-05-18);

  * continuous with discontinuities, e.g. UTC due to leap seconds, standard time due
    to summer time and winter time;

  * successive steps, e.g. [calendars](#calendar), where the [time axis](#time_axis) is split
    up into a succession of consecutive time intervals and the same mark is attributed to all
    instants of each time interval;

  * discrete, e.g. in digital techniques.

  #### Time interval

  A part of the [time axis](#time_axis) limited by two [instants](#instant) *including, unless
  otherwise stated, the limiting instants themselves*.

  #### Time scale unit

  A unit of measurement of a [duration](#duration)

  For example:

  * Calendar year, calendar month and calendar day are time scale units
    of the Gregorian calendar.

  * Clock hour, clock minutes and clock seconds are time scale units of the 24-hour clock.

  In Tempo, time scale units are referred to by the shortened term "unit".  When a "unit" is
  combined with a value, the combination is referred to as a "component".

  #### Duration

  A non-negative quantity of time equal to the difference between the final and initial
  [instants](#instant) of a [time interval](#interval)

  The duration is one of the base quantities in the International System of Quantities (ISQ)
  on which the International System of Units (SI) is based. The term “time” instead of
  “duration” is often used in this context and also for an infinitesimal duration.

  For the term “duration”, expressions such as “time” or “time interval” are often used,
  but the term “time” is not recommended in this sense and the term “time interval” is
  deprecated in this sense to avoid confusion with the concept of “time interval”.

  The exact duration of a [time scale unit](#time_scale_unit) depends on the
  [time scale](#time_scale) used. For example, the durations of a year, month, week,
  day, hour or minute, may depend on when they occur (in a Gregorian calendar, a
  calendar month can have a duration of 28, 29, 30, or 31 days; in a 24-hour clock, a
  clock minute can have a duration of 59, 60, or 61 seconds, etc.). Therefore,
  the exact duration can only be evaluated if the exact duration of each is known.

  """

  alias Tempo.Iso8601.{Tokenizer, Parser, Group, Unit}
  alias Tempo.Validation

  defstruct [:time, :shift, :calendar]

  def new(tokens, calendar \\ Cldr.Calendar.Gregorian) do
    {shift, time} = Keyword.pop(tokens, :time_shift)
    %__MODULE__{time: time, shift: shift, calendar: calendar}
  end

  def from_iso8601(string, calendar \\ Cldr.Calendar.Gregorian) do
    with {:ok, tokens} <- Tokenizer.tokenize(string),
         {:ok, parsed} <- Parser.parse(tokens, calendar),
         {:ok, expanded} <- Group.expand_groups(parsed) do
      Validation.validate(expanded, calendar)
    end
  end

  def from_iso8601!(string, calendar \\ Cldr.Calendar.Gregorian) do
    case from_iso8601(string, calendar) do
      {:ok, tempo} -> tempo
      {:error, reason} -> raise Tempo.ParseError, reason
    end
  end

  def from_date(%{year: year, month: month, day: day, calendar: calendar}) do
    new([year: year, month: month, day: day, calendar: calendar])
  end

  def resolution(%__MODULE__{time: units}) do
    case hd(Enum.reverse(units)) do
      {:group, group} -> group
      {unit, %Range{last: last}} -> {unit, last}
      {unit, {_value, meta}} when is_list(meta) -> {unit, Keyword.get(meta, :margin_of_error, 1)}
      {unit, {_value, continuation}} when is_function(continuation)-> {unit, 1}
      {unit, _value} -> {unit, 1}
    end
  end

  @valid_units Unit.units()

  def validate_unit(unit) when unit in @valid_units do
    {:ok, unit}
  end

  def validate_unit(unit) do
    {:error, "Invalid time unit #{inspect unit}"}
  end

  def anchored?(%__MODULE__{time: [{:year, _year} | _rest]}) do
    true
  end

  def anchored?(%__MODULE__{}) do
    false
  end

  def trunc(%__MODULE__{time: time} = tempo, truncate_to \\ :day) do
    with {:ok, truncate_to} <- validate_unit(truncate_to) do
      case Enum.take_while(time, &Unit.compare(&1, truncate_to) in [:gt, :eq]) do
        [] -> {:error, "Truncation would result in no time resolution"}
        other -> %{tempo | time: other}
      end
    end
  end

  def round(%__MODULE__{time: time} = tempo, round_to \\ :day) do
    with {:ok, truncate_to} <- validate_unit(round_to) do
      case round(time, truncate_to) do
        [] -> {:error, "Rounding would result in no time resolution"}
        other -> %{tempo | time: other}
      end
    end
  end

  def make_enum(%__MODULE__{} = tempo) do
    {:ok, tempo} =
      tempo
      |> Tempo.Algebra.maybe_add_implicit_enumeration()
      |> Tempo.Validation.validate()

    tempo
  end

  def merge(%Tempo{} = base, %Tempo{} = from) do
    units = Tempo.Algebra.merge(base.time, from.time)
    shift = from.shift || base.shift
    %{base | time: units, shift: shift}
  end
end
