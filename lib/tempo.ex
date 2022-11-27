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
  alias Tempo.Algebra
  alias Tempo.Validation

  defstruct [:time, :shift, :calendar]

  # TODO refine this to be more specific
  @type token :: integer() | list() | tuple()

  @type time_unit :: [
          :year | :month | :week | :day | :hour | :minute | :second
        ]

  @type token_list :: [
          {:year, token}
          | {:month, token}
          | {:week, token}
          | {:day, token}
          | {:hour, token}
          | {:minute, token}
          | {:second, token}
        ]

  @type time_shift :: number()

  @type t :: %{time: token_list(), shift: time_shift(), calendar: Calendar.t()}
  @type error_reason :: atom() | binary()

  @doc false
  def new(tokens, calendar \\ Cldr.Calendar.Gregorian)

  def new({:range, [first, last]}, calendar) do
    Tempo.Range.new(first, last, calendar)
  end

  def new(:undefined, _calendar) do
    :undefined
  end

  def new(tokens, calendar) when is_list(tokens) do
    {shift, time} = Keyword.pop(tokens, :time_shift)
    %__MODULE__{time: time, shift: shift, calendar: calendar}
  end

  @doc """
  Creates a `t:Tempo.t/0` struct from an ISO8601
  string.

  The parser supports the vast majority of [ISO8601](https://www.iso.org/iso-8601-date-and-time-format.html)
  parts 1 and 2.

  ### Arguments

  * `string` is any ISO8601 formatted string

  * `calendar` is any `t:Calendar.t/0`. The default is
    `Cldr.Calendar.Gregorian`.

  ### Returns

  * `{:ok, t}` or

  * `{:error, reason}`

  ## Examples

      iex> Tempo.from_iso8601("2022-11-20")
      {:ok, ~o"2022Y11M20D"}

      iex> Tempo.from_iso8601("2022Y")
      {:ok, ~o"2022Y"}

      iex> Tempo.from_iso8601("invalid")
      {:error, "Expected time of day. Error detected at \\"invalid\\""}

  """
  @spec from_iso8601(string :: String.t(), calendar :: Calendat.t()) ::
          {:ok, t} | {:error, error_reason()}
  def from_iso8601(string, calendar \\ Cldr.Calendar.Gregorian) do
    with {:ok, tokens} <- Tokenizer.tokenize(string),
         {:ok, parsed} <- Parser.parse(tokens, calendar),
         {:ok, expanded} <- Group.expand_groups(parsed) do
      Validation.validate(expanded, calendar)
    end
  end

  @doc """
  Creates a `t:Tempo.t/0` struct from an ISO8601
  string.

  The parser supports the vast majority of [ISO8601](https://www.iso.org/iso-8601-date-and-time-format.html)
  parts 1 and 2.

  ### Arguments

  * `string` is any ISO8601 formatted string

  * `calendar` is any `t:Calendar.t/0`. The default is
    `Cldr.Calendar.Gregorian`.

  ### Returns

  * `t:t/0` or

  * raises an exception

  ## Examples

      iex> Tempo.from_iso8601!("2022-11-20")
      ~o"2022Y11M20D"

      iex> Tempo.from_iso8601!("2022Y")
      ~o"2022Y"

  """
  @spec from_iso8601!(string :: String.t(), calendar :: Calendat.t()) :: t | no_return()
  def from_iso8601!(string, calendar \\ Cldr.Calendar.Gregorian) do
    case from_iso8601(string, calendar) do
      {:ok, tempo} -> tempo
      {:error, reason} -> raise Tempo.ParseError, reason
    end
  end

  @doc """
  Creates a `t:Tempo.t/0` struct from a `t:Date.t/0`.

  ### Arguments

  * `date` is any `t:Date.t/0`.

  ### Returns

  * `t:t/0` or

  * `{:error, reason}`

  ### Examples

      iex> Tempo.from_date ~D[2022-11-20]
      ~o"2022Y11M20D"

  """
  @spec from_date(date :: Date.t()) :: t | {:error, error_reason}
  def from_date(%{year: year, month: month, day: day, calendar: Calendar.ISO}) do
    new(year: year, month: month, day: day)
  end

  def from_date(%{year: year, month: month, day: day, calendar: Cldr.Calendar.Gregorian}) do
    new(year: year, month: month, day: day)
  end

  def from_date(%{year: year, month: month, day: day, calendar: calendar}) do
    new([year: year, month: month, day: day], calendar)
  end

  @doc """
  Creates a `t:Tempo.t/0` struct from a `t:Time.t/0`.

  ### Arguments

  * `time` is any `t:Time.t/0`.

  ### Returns

  * `t:t/0` or

  * `{:error, reason}`

  ### Examples

      iex> Tempo.from_time ~T[10:09:00]
      ~o"T10H9M0S"

  """
  @spec from_time(time :: Time.t()) :: t | {:error, error_reason}
  def from_time(%{hour: hour, minute: minute, second: second}) do
    new(hour: hour, minute: minute, second: second)
  end

  @doc """
  Creates a `t:Tempo.t/0` struct from a `t:NaiveDateTime.t/0`.

  ### Arguments

  * `naive_date_time` is any `t:NaiveDateTime.t/0`.

  ### Returns

  * `t:t/0` or

  * `{:error, reason}`

  ### Examples

      iex> Tempo.from_naive_date_time ~N[2022-11-20 10:37:00]
      ~o"2022Y11M20DT10H37M0S"

  """
  @spec from_naive_date_time(naive_date_time :: NaiveDateTime.t()) :: t | {:error, error_reason}
  def from_naive_date_time(%{
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute,
        second: second,
        calendar: Calendar.ISO
      }) do
    new(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
  end

  def from_naive_date_time(%{
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute,
        second: second,
        calendar: Cldr.Calendar.Gregorian
      }) do
    new(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
  end

  def from_naive_date_time(%{
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute,
        second: second,
        calendar: calendar
      }) do
    new(
      [year: year, month: month, day: day, hour: hour, minute: minute, second: second],
      calendar
    )
  end

  @doc """
  Returns the resolution of a `t:Tempo.t/0` struct.

  The resolution is the smallest time unit of the
  struct and an appropriate scale.

  ### Arguments

  * `tempo` is any `t:#{__MODULE__}.t/0`.

  ### Returns

  * `{time_unit, scale}`

  ### Examples

      iex> Tempo.resolution ~o"2022"
      {:year, 1}

      iex> Tempo.resolution ~o"2022-11"
      {:month, 1}

      iex> Tempo.resolution ~o"2022-11-20"
      {:day, 1}

      iex> Tempo.resolution ~o"2022Y1M2G3DU"
      {:day, 3}

  """
  @spec resolution(tempo :: t) :: {time_unit(), non_neg_integer()}
  def resolution(%__MODULE__{time: units}) do
    case hd(Enum.reverse(units)) do
      {unit, {:group, first..last}} -> {unit, last - first + 1}
      {unit, %Range{last: last}} -> {unit, last}
      {unit, {_value, meta}} when is_list(meta) -> {unit, Keyword.get(meta, :margin_of_error, 1)}
      {unit, {_value, continuation}} when is_function(continuation) -> {unit, 1}
      {unit, _value} -> {unit, 1}
    end
  end

  @doc """
  Returns a boolean indicating if a `t:Tempo.t/0` struct
  is anchored to the timeline.

  Anchored means that the time representation contains
  enough information for it to be located in a single
  location on the timeline.  In practise this means the
  if the tempo struct has a `:year` value then
  it is anchored.

  ### Arguments

  * `tempo` is any `t:#{__MODULE__}.t/0`.

  ### Returns

  * `true` or `false`

  ### Examples

      iex> Tempo.anchored? ~o"2022"
      true

      iex> Tempo.anchored? ~o"2M"
      false

  """
  @spec anchored?(tempo :: t) :: boolean()
  def anchored?(%__MODULE__{time: [{:year, _year} | _rest]}) do
    true
  end

  def anchored?(%__MODULE__{}) do
    false
  end

  @doc """
  Truncates a tempo struct to the specified resolution.

  Truncation removes the time units that have a
  higher resolution than the specified `truncate_to`
  option.

  ### Arguments

  * `tempo` is any `t:#{__MODULE__}.t/0`.

  * `truncate_to` is any time unit. The default
    is `:day`.

  ### Returns

  * `truncated` is a tempo struct that is truncated or

  * `{:error, reason}`

  ### Examples

      iex> Tempo.trunc ~o"2022-11-21T09:30:00"
      ~o"2022Y11M21D"

      iex> Tempo.trunc ~o"2022-11-21T09:30:00", :minute
      ~o"2022Y11M21DT9H30M"

      iex> Tempo.trunc ~o"2022-11-21T09:30:00", :year
      ~o"2022Y"

  """
  @spec trunc(tempo :: t, truncate_to :: time_unit()) :: t
  def trunc(%__MODULE__{time: time} = tempo, truncate_to \\ :day) do
    with {:ok, truncate_to} <- validate_unit(truncate_to) do
      case Enum.take_while(time, &(Unit.compare(&1, truncate_to) in [:gt, :eq])) do
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

  def merge(%Tempo{} = base, %Tempo{} = from) do
    units = Algebra.merge(base.time, from.time)
    shift = from.shift || base.shift

    case Validation.validate(%{base | time: units, shift: shift}) do
      {:ok, tempo} -> tempo
      other -> other
    end
  end

  def explode(tempo, unit \\ nil)

  def explode(%Tempo{} = tempo, nil) do
    tempo
    |> Tempo.Algebra.add_implicit_enumeration()
    |> Tempo.Validation.validate()
  end

  def explode!(%Tempo{} = tempo, unit \\ nil) do
    case explode(tempo, unit) do
      {:ok, zoomed} -> zoomed
      {:error, reason} -> raise Tempo.ParseError, reason
    end
  end

  def to_date(%Tempo{time: [year: year, month: month, day: day]}) do
    Date.new(year, month, day)
  end

  def to_date(%Tempo{}) do
    {:error, :invalid_date}
  end

  def to_time(%Tempo{time: [hour: hour, minute: minute, second: second], shift: nil}) do
    Time.new(hour, minute, second, 0)
  end

  def to_time(%Tempo{}) do
    {:error, :invalid_time}
  end

  def to_naive_date_time(%Tempo{
        time: [year: year, month: month, day: day, hour: hour, minute: minute, second: second],
        shift: nil
      }) do
    NaiveDateTime.new(year, month, day, hour, minute, second, 0)
  end

  def to_naive_date_time(%Tempo{}) do
    {:error, :invalid_date_time}
  end

  def to_calendar(%Tempo{shift: nil} = tempo) do
    with {:error, :invalid_date} <- to_date(tempo),
         {:error, :invalid_time} <- to_time(tempo) do
      to_naive_date_time(tempo)
    end
  end

  def to_calendar(%Tempo{}) do
    {:error, :invalid_date_time}
  end

  @valid_units Unit.units()

  @doc false
  def validate_unit(unit) when unit in @valid_units do
    {:ok, unit}
  end

  def validate_unit(unit) do
    {:error, "Invalid time unit #{inspect(unit)}"}
  end

  @doc false
  def make_enum(%__MODULE__{} = tempo) do
    {:ok, tempo} =
      tempo
      |> Tempo.Algebra.maybe_add_implicit_enumeration()
      |> Tempo.Validation.validate()

    tempo
  end
end
