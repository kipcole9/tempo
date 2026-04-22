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
  alias Tempo.Enumeration
  alias Tempo.Validation
  alias Tempo.Rounding

  defstruct [:time, :shift, :calendar, :extended, :qualification, :qualifications]

  # TODO refine this to be more specific
  @type token :: integer() | list() | tuple()

  @type time_unit ::
          :year | :month | :week | :day | :hour | :minute | :second

  @type token_list :: [
          {:year, token}
          | {:month, token}
          | {:week, token}
          | {:day, token}
          | {:hour, token}
          | {:minute, token}
          | {:second, token}
        ]

  @type time_shift :: [{:hour, integer()} | {:minute, integer()}] | nil

  @typedoc """
  Extended information parsed from an IXDTF suffix.

  * `:calendar` — calendar identifier atom derived from `u-ca=`.

  * `:zone_id` — IANA time zone name such as `"Europe/Paris"`.

  * `:zone_offset` — numeric offset in minutes from `[+HH:MM]`.

  * `:tags` — map of non-`u-ca` elective tagged suffixes.

  """
  @type extended_info :: %{
          calendar: atom() | nil,
          zone_id: String.t() | nil,
          zone_offset: integer() | nil,
          tags: %{optional(String.t()) => [String.t()]}
        }

  @typedoc """
  ISO 8601-2 / EDTF date qualification.

  * `:uncertain` — the value is uncertain (`?`).

  * `:approximate` — the value is approximate (`~`), e.g. "circa".

  * `:uncertain_and_approximate` — both (`%`).

  * `nil` when no qualification was supplied.

  """
  @type qualification ::
          :uncertain | :approximate | :uncertain_and_approximate | nil

  @typedoc """
  Per-component qualifications parsed from an EDTF Level 2 date.

  A map from the component unit (`:year`, `:month`, `:day`) to its
  qualification atom. `nil` when no component-level qualification
  was present in the parsed string.

  """
  @type qualifications :: %{optional(atom()) => qualification()} | nil

  @type t :: %__MODULE__{
          time: token_list(),
          shift: time_shift(),
          calendar: Calendar.calendar() | nil,
          extended: extended_info() | nil,
          qualification: qualification(),
          qualifications: qualifications()
        }
  @type error_reason :: atom() | binary()

  @doc false
  def new(tokens, calendar \\ Calendrical.Gregorian)

  def new({:range, [first, last]}, calendar) do
    Tempo.Range.new(first, last, calendar)
  end

  def new(:undefined, _calendar) do
    :undefined
  end

  def new(tokens, calendar) when is_list(tokens) do
    {shift, tokens} = Keyword.pop(tokens, :time_shift)
    {qualification, tokens} = Keyword.pop(tokens, :qualification)
    {extended, tokens} = Keyword.pop(tokens, :extended)
    {component_qualifications, time} = pop_component_qualifications(tokens)

    %__MODULE__{
      time: time,
      shift: shift,
      calendar: calendar,
      extended: extended,
      qualification: qualification,
      qualifications: component_qualifications
    }
  end

  # Removes any `{<unit>_qualification, value}` entries from `tokens`
  # and returns them as a plain `%{unit => value}` map. Returns `nil`
  # for the map when no component-level qualifications were present
  # so that the `%Tempo{}` struct stays compact when the feature
  # isn't used.
  defp pop_component_qualifications(tokens) do
    {remaining, acc} =
      Enum.reduce(tokens, {[], %{}}, fn
        {key, value}, {rest, acc} when is_atom(key) ->
          case unit_from_qualification_key(key) do
            nil -> {[{key, value} | rest], acc}
            unit -> {rest, Map.put(acc, unit, value)}
          end

        other, {rest, acc} ->
          {[other | rest], acc}
      end)

    result = if map_size(acc) == 0, do: nil, else: acc
    {result, Enum.reverse(remaining)}
  end

  @qualification_suffix "_qualification"
  @qualification_suffix_size byte_size(@qualification_suffix)

  defp unit_from_qualification_key(key) do
    key_string = Atom.to_string(key)
    size = byte_size(key_string)

    if size > @qualification_suffix_size and
         binary_part(key_string, size - @qualification_suffix_size, @qualification_suffix_size) ==
           @qualification_suffix do
      key_string
      |> binary_part(0, size - @qualification_suffix_size)
      |> String.to_existing_atom()
    else
      nil
    end
  end

  @doc """
  Creates a `t:Tempo.t/0` struct from an ISO 8601 or IXDTF
  string.

  The parser supports the vast majority of [ISO 8601](https://www.iso.org/iso-8601-date-and-time-format.html)
  parts 1 and 2 as well as the Internet Extended Date/Time Format
  (IXDTF) defined in
  [draft-ietf-sedate-datetime-extended-09](https://www.ietf.org/archive/id/draft-ietf-sedate-datetime-extended-09.html).

  An IXDTF suffix follows the ISO 8601 production and consists of
  an optional time zone (`[Europe/Paris]` or `[+08:45]`) followed
  by zero or more tagged suffixes (`[u-ca=hebrew]`, `[_key=value]`).
  Any bracket may be prefixed with `!` to mark it critical —
  unrecognised critical suffixes cause the parse to fail; elective
  suffixes are retained verbatim under `extended.tags`.

  ### Arguments

  * `string` is any ISO 8601 formatted string, optionally
    followed by an IXDTF suffix.

  * `calendar` (optional) is any `t:Calendar.calendar/0`. When
    passed, the explicit calendar always wins over any
    `[u-ca=NAME]` tag in the IXDTF suffix. When omitted, the
    `[u-ca=NAME]` tag is resolved to a `Calendrical.*` module via
    `Calendrical.calendar_from_cldr_calendar_type/1`; if no tag is present,
    `Calendrical.Gregorian` is used.

  ### Returns

  * `{:ok, t}` where the returned struct's `:extended` field
    is populated when an IXDTF suffix was parsed, or `nil`
    otherwise.

  * `{:error, reason}` when the string cannot be parsed or a
    critical IXDTF suffix is unrecognised.

  ## Examples

      iex> Tempo.from_iso8601("2022-11-20")
      {:ok, ~o"2022Y11M20D"}

      iex> Tempo.from_iso8601("2022Y")
      {:ok, ~o"2022Y"}

      iex> Tempo.from_iso8601("invalid")
      {:error, "Expected time of day. Error detected at \\"invalid\\""}

      iex> {:ok, tempo} = Tempo.from_iso8601("5786-10-30[u-ca=hebrew]")
      iex> tempo.calendar
      Calendrical.Hebrew

      iex> {:ok, tempo} = Tempo.from_iso8601("2022-11-20T10:30:00Z[Europe/Paris][u-ca=hebrew]")
      iex> {tempo.extended.zone_id, tempo.extended.calendar, tempo.calendar}
      {"Europe/Paris", :hebrew, Calendrical.Hebrew}

      iex> Tempo.from_iso8601("2022-11-20T10:30:00Z[!Continent/Imaginary]")
      {:error, "Unknown IANA time zone: \\"Continent/Imaginary\\""}

  """
  @spec from_iso8601(string :: String.t()) ::
          {:ok,
           t()
           | Tempo.Interval.t()
           | Tempo.Duration.t()
           | Tempo.Set.t()
           | Tempo.Range.t()}
          | {:error, error_reason()}
  @spec from_iso8601(string :: String.t(), calendar :: Calendar.calendar()) ::
          {:ok,
           t()
           | Tempo.Interval.t()
           | Tempo.Duration.t()
           | Tempo.Set.t()
           | Tempo.Range.t()}
          | {:error, error_reason()}
  def from_iso8601(string) when is_binary(string) do
    # No explicit calendar — the IXDTF `[u-ca=NAME]` suffix wins
    # when present, otherwise fall back to Gregorian.
    do_from_iso8601(string, :from_ixdtf_or_default)
  end

  def from_iso8601(string, calendar) when is_binary(string) do
    # Explicit user calendar always wins — IXDTF `[u-ca=NAME]` is
    # recorded on `extended.calendar` for metadata but does not
    # override the user's choice. This keeps the existing
    # `Tempo.from_iso8601(string, Calendrical.Hebrew)` idiom
    # working unchanged.
    do_from_iso8601(string, calendar)
  end

  defp do_from_iso8601(string, requested_calendar) do
    with {:ok, {tokens, extended}} <- Tokenizer.tokenize(string),
         {:ok, effective_calendar} <- resolve_calendar(requested_calendar, extended),
         {:ok, parsed} <- Parser.parse(tokens, effective_calendar),
         {:ok, expanded} <- Group.expand_groups(parsed),
         {:ok, validated} <- Validation.validate(expanded, effective_calendar),
         attached = attach_extended(validated, extended),
         :ok <- Validation.validate_zone_existence(attached) do
      {:ok, attached}
    end
  end

  # Resolve the effective calendar for a parse.
  #
  # * Explicit user calendar always wins.
  # * Otherwise, if the IXDTF `[u-ca=NAME]` suffix is present, its
  #   atom is resolved to a `Calendrical.*` module via
  #   `Calendrical.calendar_from_cldr_calendar_type/1`.
  # * Otherwise, fall back to `Calendrical.Gregorian`.
  defp resolve_calendar(:from_ixdtf_or_default, nil),
    do: {:ok, Calendrical.Gregorian}

  defp resolve_calendar(:from_ixdtf_or_default, %{calendar: nil}),
    do: {:ok, Calendrical.Gregorian}

  defp resolve_calendar(:from_ixdtf_or_default, %{calendar: name}) when is_atom(name),
    do: Calendrical.calendar_from_cldr_calendar_type(name)

  defp resolve_calendar(:from_ixdtf_or_default, _extended),
    do: {:ok, Calendrical.Gregorian}

  defp resolve_calendar(calendar, _extended),
    do: {:ok, calendar}

  @doc false
  def attach_extended(result, nil), do: result

  def attach_extended(%__MODULE__{extended: existing} = tempo, extended) do
    # An endpoint-local `:extended` parsed from a per-endpoint IXDTF
    # suffix (`2022-06-15T10:00[Europe/Paris]/…`) takes precedence
    # over a top-level suffix. The top-level suffix is only used as
    # a default when the endpoint carries none of its own.
    case existing do
      nil -> %{tempo | extended: extended}
      _map -> tempo
    end
  end

  def attach_extended(%Tempo.Range{} = range, extended) do
    %{range | first: attach_extended(range.first, extended)}
  end

  def attach_extended(%Tempo.Interval{} = interval, extended) do
    # A top-level suffix on an interval propagates to each endpoint
    # unless that endpoint carries its own IXDTF info (which the
    # parser has already attached to `endpoint.extended`).
    %{
      interval
      | from: attach_extended(interval.from, extended),
        to: attach_extended(interval.to, extended)
    }
  end

  def attach_extended(other, _extended), do: other

  @doc """
  Creates a `t:Tempo.t/0` struct from an ISO8601
  string.

  The parser supports the vast majority of [ISO8601](https://www.iso.org/iso-8601-date-and-time-format.html)
  parts 1 and 2.

  ### Arguments

  * `string` is any ISO8601 formatted string

  * `calendar` is any `t:Calendar.calendar/0`. The default is
    `Calendrical.Gregorian`.

  ### Returns

  * `t:t/0` or

  * raises an exception

  ## Examples

      iex> Tempo.from_iso8601!("2022-11-20")
      ~o"2022Y11M20D"

      iex> Tempo.from_iso8601!("2022Y")
      ~o"2022Y"

  """
  @spec from_iso8601!(string :: String.t()) :: t | no_return()
  def from_iso8601!(string) when is_binary(string) do
    # Mirror `from_iso8601/1` — no explicit calendar, so IXDTF
    # `[u-ca=NAME]` wins when present.
    case from_iso8601(string) do
      {:ok, tempo} -> tempo
      {:error, reason} -> raise Tempo.ParseError, reason
    end
  end

  @spec from_iso8601!(string :: String.t(), calendar :: Calendar.calendar()) :: t | no_return()
  def from_iso8601!(string, calendar) when is_binary(string) do
    case from_iso8601(string, calendar) do
      {:ok, tempo} -> tempo
      {:error, reason} -> raise Tempo.ParseError, reason
    end
  end

  @doc """
  Encode a Tempo value back into an ISO 8601-2 string.

  The output uses the explicit-suffix form (`2022Y11M20D`), which
  is a valid ISO 8601-2 / EDTF representation that round-trips
  cleanly through `from_iso8601/1`. Constructs that exist only
  in ISO 8601-2 Part 2 (seasons, groups, selections,
  uncertainty qualifiers, unspecified digits) are preserved in
  their explicit form.

  IXDTF suffixes (`[Europe/Paris]`, `[u-ca=hebrew]`) are **not**
  emitted by this function — the `:extended` field is currently
  ignored. Round-trip of IXDTF-enriched values is a future
  extension.

  ### Arguments

  * `value` is a `t:Tempo.t/0`, `t:Tempo.Interval.t/0`,
    `t:Tempo.Duration.t/0`, or `t:Tempo.Set.t/0`.

  ### Returns

  * An ISO 8601-2 binary that parses back to the same AST.

  ### Examples

      iex> Tempo.from_iso8601!("2022-11-20") |> Tempo.to_iso8601()
      "2022Y11M20D"

      iex> Tempo.from_iso8601!("R5/2022-01-01/P1M") |> Tempo.to_iso8601()
      "R5/2022Y1M1D/P1M"

      iex> {:ok, i} = Tempo.from_iso8601("1984?/2004~")
      iex> Tempo.to_iso8601(i)
      "1984Y?/2004Y~"

  """
  @spec to_iso8601(Tempo.t() | Tempo.Interval.t() | Tempo.Duration.t() | Tempo.Set.t()) ::
          String.t()
  def to_iso8601(value) do
    value
    |> Tempo.Inspect.to_iodata()
    |> IO.iodata_to_binary()
  end

  @doc """
  Encode a `t:Tempo.Interval.t/0` into an RFC 5545 RRULE string.

  The output does **not** include the leading `RRULE:` prefix,
  nor a `DTSTART` property — RRULE is a recurrence pattern, not
  a full iCalendar record. Callers wanting the full record
  prepend `DTSTART` themselves using the interval's `:from`
  field.

  ### Supported inputs

  * A `%Tempo.Interval{}` with a single-unit `%Tempo.Duration{}`
    cadence. Supported units: `:second`, `:minute`, `:hour`,
    `:day`, `:week`, `:month`, `:year`.

  * `:recurrence` of `:infinity` (no COUNT), a positive integer
    (COUNT), or `1` combined with `:to` (UNTIL).

  * `:repeat_rule` of `nil`, or a `%Tempo{}` whose `:time` holds a
    single `{:selection, [...]}` entry. Selection entries for
    `:month`, `:day` (→ BYMONTHDAY), `:day_of_year`, `:week`,
    `:hour`, `:minute`, `:second`, and the paired
    `:day_of_week`/`:instance` (→ BYDAY with optional ordinals)
    are encoded directly.

  ### Returns

  * `{:ok, rrule_string}` on success.

  * `{:error, reason}` when the interval cannot be expressed as
    an RRULE (e.g. multi-unit duration, unsupported selection
    entry).

  ### Examples

      iex> {:ok, i} = Tempo.RRule.parse("FREQ=DAILY;COUNT=10")
      iex> Tempo.to_rrule(i)
      {:ok, "COUNT=10;FREQ=DAILY"}

      iex> {:ok, i} = Tempo.RRule.parse("FREQ=YEARLY;BYMONTH=11;BYDAY=4TH")
      iex> Tempo.to_rrule(i)
      {:ok, "FREQ=YEARLY;BYMONTH=11;BYDAY=4TH"}

      iex> {:error, %Tempo.ConversionError{}} =
      ...>   Tempo.to_rrule(Tempo.from_iso8601!("2022-06-15"))

  """
  @spec to_rrule(Tempo.Interval.t() | term()) ::
          {:ok, String.t()} | {:error, Tempo.ConversionError.t()}
  def to_rrule(%Tempo.Interval{} = interval) do
    Tempo.RRule.Encoder.encode(interval)
  end

  def to_rrule(other) do
    {:error,
     Tempo.ConversionError.exception(
       message:
         "Only a %Tempo.Interval{} can be converted to an RRULE. " <>
           "RRULE is a recurrence rule; got: #{inspect(other)}",
       value: other,
       target: :rrule
     )}
  end

  @doc """
  Bang variant of `to_rrule/1`.

  ### Returns

  * The RRULE string on success.

  * Raises `Tempo.ConversionError` otherwise.

  """
  @spec to_rrule!(Tempo.Interval.t()) :: String.t() | no_return()
  def to_rrule!(value) do
    case to_rrule(value) do
      {:ok, rrule} -> rrule
      {:error, %Tempo.ConversionError{} = error} -> raise error
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
  # `new/2` is multi-clause internally; dialyzer unions all return
  # types across clauses even though `from_date/1` always hits the
  # keyword-list clause. Suppress the resulting wide-return warning
  # rather than widen the spec, which would mislead human readers.
  @dialyzer {:nowarn_function, from_date: 1, from_time: 1, from_naive_date_time: 1}

  @spec from_date(date :: Date.t()) :: t()
  def from_date(%{year: year, month: month, day: day, calendar: Calendar.ISO}) do
    new(year: year, month: month, day: day)
  end

  def from_date(%{year: year, month: month, day: day, calendar: Calendrical.Gregorian}) do
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
  @spec from_time(time :: Time.t()) :: t()
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
  @spec from_naive_date_time(naive_date_time :: NaiveDateTime.t()) :: t()
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
        calendar: Calendrical.Gregorian
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
  Creates a `t:Tempo.t/0` struct from a `t:DateTime.t/0`.

  The DateTime's time zone information is preserved on the Tempo:
  the total offset (`utc_offset + std_offset`) populates the
  `:shift` field, and the IANA zone identifier is stored on the
  `:extended` map under `:zone_id`. Iteration on the returned
  Tempo carries both pieces of metadata through.

  ### Arguments

  * `date_time` is any `t:DateTime.t/0`.

  ### Returns

  * `t:t/0`.

  ### Examples

      iex> Tempo.from_date_time(~U[2022-11-20 10:37:00Z]).time
      [year: 2022, month: 11, day: 20, hour: 10, minute: 37, second: 0]

      iex> Tempo.from_date_time(~U[2022-11-20 10:37:00Z]).shift
      [hour: 0]

      iex> Tempo.from_date_time(~U[2022-11-20 10:37:00Z]).extended.zone_id
      "Etc/UTC"

  """
  @spec from_date_time(DateTime.t()) :: t()
  def from_date_time(%DateTime{
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute,
        second: second,
        time_zone: time_zone,
        utc_offset: utc_offset,
        std_offset: std_offset,
        calendar: calendar
      }) do
    tempo_calendar =
      case calendar do
        Calendar.ISO -> Calendrical.Gregorian
        other -> other
      end

    time = [year: year, month: month, day: day, hour: hour, minute: minute, second: second]
    total_offset = utc_offset + std_offset

    %__MODULE__{
      time: time,
      shift: offset_to_shift(total_offset),
      calendar: tempo_calendar,
      extended: %{
        zone_id: time_zone,
        zone_offset: div(total_offset, 60),
        calendar: nil,
        tags: %{}
      }
    }
  end

  # Convert a UTC offset in seconds to the `[hour: h, minute: m]`
  # keyword list used by `%Tempo{}.shift`. Sign is carried on the
  # hour component (matching the `resolve_shift/1` tokenizer output
  # for negative offsets).
  defp offset_to_shift(0), do: [hour: 0]

  defp offset_to_shift(seconds) do
    sign = if seconds < 0, do: -1, else: 1
    magnitude = abs(seconds)
    hours = div(magnitude, 3600)
    minutes = div(rem(magnitude, 3600), 60)

    case {hours, minutes} do
      {h, 0} -> [hour: sign * h]
      {h, m} -> [hour: sign * h, minute: sign * m]
    end
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
  @spec resolution(tempo :: t()) :: {time_unit(), time_unit() | non_neg_integer()}
  def resolution(%__MODULE__{time: units}) do
    units
    |> Enum.reverse()
    |> hd
    |> unit_resolution()
  end

  @doc """
  Returns the maximum and minimum time units as a
  2-tuple.

  ### Arguments

  * `tempo` is any `t:#{__MODULE__}.t/0`.

  ### Returns

  * `{max_unit, min_unit}`

  ### Examples

        iex> Tempo.unit_min_max ~o"2022Y1M2G3DU"
        {:day, :year}

        iex> Tempo.unit_min_max ~o"2022"
        {:year, :year}

  """
  @spec unit_min_max(tempo :: t | token_list()) :: {time_unit(), time_unit()}
  def unit_min_max(%__MODULE__{time: units}) do
    unit_min_max(units)
  end

  def unit_min_max(units) when is_list(units) do
    {max, _} = unit_resolution(hd(units))
    {min, _} = unit_resolution(hd(Enum.reverse(units)))
    {min, max}
  end

  defp unit_resolution(time_unit) do
    case time_unit do
      {:selection, selection} -> unit_min_max(selection)
      {unit, {:group, first..last//_}} -> {unit, last - first + 1}
      {unit, %Range{last: last}} -> {unit, last}
      {unit, {_value, meta}} when is_list(meta) -> {unit, Keyword.get(meta, :margin_of_error, 1)}
      {unit, {_value, continuation}} when is_function(continuation) -> {unit, 1}
      {unit, _value} -> {unit, 1}
    end
  end

  # Order of units from coarsest to finest. Used by the component
  # accessors (`year/1`, `month/1`, `day/1`, `hour/1`, `minute/1`,
  # `second/1`) to decide whether a unit is unambiguous for a given
  # interval span — a unit U is unambiguous iff the interval's span
  # resolution is equal to or finer than U.
  @unit_order [:year, :month, :day, :hour, :minute, :second]

  for {unit, _idx} <- Enum.with_index(@unit_order) do
    @doc """
    Return the `#{unit}` component of a Tempo value, or `nil` if
    the value doesn't specify one.

    The accessors (`year/1`, `month/1`, `day/1`, `hour/1`,
    `minute/1`, `second/1`) are commodity component extractors so
    callers never have to reach into struct fields in user-facing
    code.

    ### Arguments

    * `value` is a `t:t/0` or `t:Tempo.Interval.t/0`.

    ### Returns

    * The component value as an integer when unambiguous.

    * `nil` when the value doesn't specify that unit (e.g.
      `Tempo.day(~o"2026")` returns `nil` — the year value has no
      day).

    * Raises `ArgumentError` when called on an interval whose span
      covers multiple values of that unit (e.g. `Tempo.day/1` on a
      month-spanning interval is ambiguous).

    ### Examples

        iex> Tempo.#{unit}(~o"2026-06-15T10:30:45")
        #{case unit do
      :year -> 2026
      :month -> 6
      :day -> 15
      :hour -> 10
      :minute -> 30
      :second -> 45
    end}

        iex> Tempo.#{unit}(~o"2026")
        #{if unit == :year, do: 2026, else: "nil"}

    """
    @spec unquote(unit)(t() | Tempo.Interval.t()) :: integer() | nil
    def unquote(unit)(value), do: component(value, unquote(unit))
  end

  # Polymorphic component extraction. A Tempo value reads straight
  # from its time keyword list — nil if absent. An Interval checks
  # unambiguity via the span resolution and raises otherwise.
  defp component(%__MODULE__{time: time}, unit) do
    case Keyword.get(time, unit) do
      value when is_integer(value) -> value
      nil -> nil
      _other -> nil
    end
  end

  defp component(%Tempo.Interval{from: %__MODULE__{time: from_time}} = interval, unit) do
    span_res = Tempo.Interval.resolution(interval)

    cond do
      span_res == :undefined ->
        component(%__MODULE__{time: from_time, calendar: nil}, unit)

      unit_finer_or_equal?(span_res, unit) ->
        component(%__MODULE__{time: from_time, calendar: nil}, unit)

      true ->
        raise ArgumentError,
              "Tempo.#{unit}/1 is ambiguous for an interval spanning at #{inspect(span_res)} resolution. " <>
                "Use `Tempo.Interval.endpoints/1` and extract the component from each endpoint explicitly."
    end
  end

  # `u_res` is finer-or-equal to `u_target` iff u_res's index in
  # @unit_order is >= u_target's index. (:year is coarsest at 0;
  # :second is finest at 5.)
  defp unit_finer_or_equal?(u_res, u_target) do
    Enum.find_index(@unit_order, &(&1 == u_res)) >=
      Enum.find_index(@unit_order, &(&1 == u_target))
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
  @spec trunc(tempo :: t, truncate_to :: time_unit()) :: t | {:error, error_reason()}
  def trunc(%__MODULE__{time: time} = tempo, truncate_to \\ :day) do
    with {:ok, truncate_to} <- validate_unit(truncate_to) do
      case Enum.take_while(time, &(Unit.compare(&1, truncate_to) in [:gt, :eq])) do
        [] -> {:error, "Truncation would result in no time resolution"}
        other -> %{tempo | time: other}
      end
    end
  end

  @doc """
  Truncates a tempo struct to the specified resolution.

  Rounding rounds to the specified time unit resolution.

  ### Arguments

  * `tempo` is any `t:#{__MODULE__}.t/0`.

  * `round_to` is any time unit. The default
    is `:day`.

  ### Returns

  * `rounded` is a tempo struct that is rounded or

  * `{:error, reason}`

  ### Examples

      iex> Tempo.round ~o"2022-11-21", :day
      ~o"2022Y11M21D"

      iex> Tempo.round ~o"2022-11-21", :month
      ~o"2022Y12M"

      iex> Tempo.round ~o"2022-11-21", :year
      ~o"2023Y"

  """
  @spec round(tempo :: t, round_to :: time_unit()) :: t | {:error, error_reason()}
  def round(%__MODULE__{} = tempo, round_to \\ :day) do
    with {:ok, round_to} <- validate_unit(round_to) do
      case Rounding.round(tempo, round_to) do
        {:error, reason} -> {:error, reason}
        other -> %{tempo | time: other}
      end
    end
  end

  @doc """
  Split a tempo struct into a date
  and time.

  """
  def split(%__MODULE__{time: time, calendar: calendar}) do
    case Tempo.Split.split(time) do
      {date, []} ->
        {%Tempo{time: date, calendar: calendar}, nil}

      {[], time} ->
        {nil, %Tempo{time: time, calendar: calendar}}

      {date, time} ->
        {%Tempo{time: date, calendar: calendar}, %Tempo{time: time, calendar: calendar}}
    end
  end

  def merge(%__MODULE__{} = base, %Tempo{} = from) do
    units = Enumeration.merge(base.time, from.time)
    shift = from.shift || base.shift

    case Validation.validate(%{base | time: units, shift: shift}) do
      {:ok, tempo} -> tempo
      other -> other
    end
  end

  @doc """
  Combine a date-like value with a time-of-day value into a
  datetime.

  This is **axis composition**, not a set operation. Set
  operations require both operands to share an anchor class;
  `anchor/2` is how the user explicitly composes cross-axis
  values before set operations run. No set-algebra laws apply
  to `anchor/2` — it's a constructor, not an operator.

  ### Arguments

  * `anchored` is an anchored `t:#{__MODULE__}.t/0` (has a year
    component) — typically a date like `~o"2026-01-04"`.

  * `non_anchored` is a non-anchored `t:#{__MODULE__}.t/0` (pure
    time-of-day) — typically a time like `~o"T10:30"`.

  ### Returns

  * A new `t:t/0` combining the two. The date components come
    from `anchored`; the time components come from `non_anchored`.

  ### Raises

  * `ArgumentError` when either argument has the wrong anchor
    class — if `anchored` is non-anchored or `non_anchored` is
    already anchored.

  ### Examples

      iex> Tempo.anchor(~o"2026-01-04", ~o"T10:30")
      ~o"2026Y1M4DT10H30M"

  """
  # Same pattern as `from_date/1` — `merge/2` passes through any
  # non-`{:ok, _}` return from `Validation.validate/2`, which
  # dialyzer widens to include `nil | :undefined`. The spec
  # reflects what the function is actually contracted to return;
  # suppress the underspecs warning rather than widening.
  @dialyzer {:nowarn_function, anchor: 2}

  @spec anchor(t(), t()) :: t() | {:error, error_reason()}
  def anchor(%__MODULE__{} = anchored, %__MODULE__{} = non_anchored) do
    cond do
      not anchored?(anchored) ->
        raise ArgumentError,
              "anchor/2: first argument must be anchored (have a year component). " <>
                "Got: #{inspect(anchored)}"

      anchored?(non_anchored) ->
        raise ArgumentError,
              "anchor/2: second argument must be non-anchored (time-of-day only). " <>
                "Got: #{inspect(non_anchored)}"

      true ->
        merge(anchored, non_anchored)
    end
  end

  @doc """
  Adds an extended enumeration to a Tempo.

  This has the effect of increasing the
  resolution of the the Tempo struct but
  still covering the same interval.

  ### Example

      iex> Tempo.extend(~o"2020")
      {:ok, ~o"2020Y{1..12}M"}

  """

  def extend(tempo, unit \\ nil)

  def extend(%Tempo{} = tempo, nil) do
    tempo
    |> Enumeration.add_implicit_enumeration()
    |> Validation.validate()
  end

  def extend!(%Tempo{} = tempo, unit \\ nil) do
    case extend(tempo, unit) do
      {:ok, zoomed} -> zoomed
      {:error, reason} -> raise Tempo.ParseError, reason
    end
  end

  @doc """
  Create a `t:Tempo.t/0` from any Elixir date/time type.

  Unifies `Date.t`, `Time.t`, `NaiveDateTime.t`, and `DateTime.t`
  into the single `Tempo.t` representation under the principle
  that every date/time value is a bounded interval on the time
  line at some resolution.

  The intended resolution is either given explicitly via the
  `:resolution` option or inferred from the input:

  * `Date.t` → `:day` (Date has no time components).

  * `Time.t`, `NaiveDateTime.t`, `DateTime.t` → the finest
    Tempo-supported component that is non-zero. If all time
    components are zero (e.g. midnight on a date), the resolution
    falls back to `:day` for datetime types or `:hour` for a bare
    `Time.t`. Microsecond is discarded (Tempo does not yet model
    sub-second resolution).

  When an explicit `:resolution` is given, the resulting Tempo is
  passed through `at_resolution/2` to either truncate or pad to
  that resolution.

  ### Arguments

  * `value` is any `t:Date.t/0`, `t:Time.t/0`,
    `t:NaiveDateTime.t/0`, or `t:DateTime.t/0`.

  ### Options

  * `:resolution` is a time unit atom (`:year`, `:month`, `:day`,
    `:hour`, `:minute`, `:second`) overriding the inferred
    resolution.

  ### Returns

  * The `t:t/0` at the chosen resolution, or

  * `{:error, reason}` if `:resolution` is incompatible with the
    input.

  ### Examples

      iex> Tempo.from_elixir(~D[2022-06-15])
      ~o"2022Y6M15D"

      iex> Tempo.from_elixir(~T[10:30:00])
      ~o"T10H30M"

      iex> Tempo.from_elixir(~N[2022-06-15 10:30:00])
      ~o"2022Y6M15DT10H30M"

      iex> Tempo.from_elixir(~N[2022-06-15 00:00:00])
      ~o"2022Y6M15D"

      iex> Tempo.from_elixir(~D[2022-06-15], resolution: :hour)
      ~o"2022Y6M15DT0H"

      iex> Tempo.from_elixir(~N[2022-06-15 10:30:00], resolution: :day)
      ~o"2022Y6M15D"

  """
  @spec from_elixir(
          value :: Date.t() | Time.t() | NaiveDateTime.t() | DateTime.t(),
          options :: Keyword.t()
        ) :: t() | {:error, error_reason()}
  def from_elixir(value, options \\ [])

  def from_elixir(%Date{} = date, options) do
    resolution = Keyword.get(options, :resolution, :day)

    date
    |> from_date()
    |> at_resolution(resolution)
  end

  def from_elixir(%Time{} = time, options) do
    resolution = Keyword.get(options, :resolution) || infer_time_resolution(time)

    time
    |> from_time()
    |> at_resolution(resolution)
  end

  def from_elixir(%NaiveDateTime{} = naive, options) do
    resolution = Keyword.get(options, :resolution) || infer_datetime_resolution(naive)

    naive
    |> from_naive_date_time()
    |> at_resolution(resolution)
  end

  def from_elixir(%DateTime{} = dt, options) do
    resolution = Keyword.get(options, :resolution) || infer_datetime_resolution(dt)

    dt
    |> from_date_time()
    |> at_resolution(resolution)
  end

  # Infer the intended resolution of a `Time.t` by finding the
  # finest Tempo-supported component that is non-zero. Microsecond
  # is discarded (Tempo has no sub-second unit). All-zero falls
  # back to `:hour`.
  defp infer_time_resolution(%Time{hour: _h, minute: m, second: s}) do
    cond do
      s != 0 -> :second
      m != 0 -> :minute
      true -> :hour
    end
  end

  # Datetime types have date components always non-zero, so the
  # fallback when all time components are zero is `:day` (not
  # `:hour` as for a bare Time).
  defp infer_datetime_resolution(%{hour: h, minute: m, second: s}) do
    cond do
      s != 0 -> :second
      m != 0 -> :minute
      h != 0 -> :hour
      true -> :day
    end
  end

  @doc """
  Extend a Tempo's resolution by padding finer units with their
  start-of-unit minimum values.

  `extend_resolution/2` is the scalar counterpart to `extend/2`:
  where `extend/2` adds an implicit enumeration (turning `~o"2020Y"`
  into `~o"2020Y{1..12}M"` — a range), `extend_resolution/2` fills
  in concrete minimums (turning `~o"2020Y"` into `~o"2020Y1M1D"`
  when extended to `:day`). This is the operation needed to align
  resolutions before interval comparison.

  ### Arguments

  * `tempo` is any `t:#{__MODULE__}.t/0`.

  * `target_unit` is the finer resolution to pad to. Must be
    finer than or equal to `tempo`'s current resolution.

  ### Returns

  * The padded `t:t/0`, or

  * `{:error, reason}` when `target_unit` is coarser than the
    current resolution (use `trunc/2` for that direction) or when
    no path exists from the current unit to `target_unit` under
    the tempo's calendar.

  ### Examples

      iex> Tempo.extend_resolution(~o"2020Y", :day)
      ~o"2020Y1M1D"

      iex> Tempo.extend_resolution(~o"2020Y6M", :hour)
      ~o"2020Y6M1DT0H"

  """
  @spec extend_resolution(tempo :: t, target_unit :: time_unit()) ::
          t | {:error, error_reason()}
  def extend_resolution(%Tempo{time: time, calendar: calendar} = tempo, target_unit) do
    with {:ok, target_unit} <- validate_unit(target_unit) do
      {current_unit, _span} = resolution(tempo)

      case Unit.compare(target_unit, current_unit) do
        :eq ->
          tempo

        :gt ->
          {:error,
           "Target resolution #{inspect(target_unit)} is coarser than the current " <>
             "resolution #{inspect(current_unit)}. Use `Tempo.trunc/2` to reduce " <>
             "resolution."}

        :lt ->
          case fill_to_resolution(time, current_unit, target_unit, calendar) do
            {:ok, new_time} -> %{tempo | time: new_time}
            {:error, _} = err -> err
          end
      end
    end
  end

  # Walk the standard unit-successor chain, appending one
  # `{next_unit, unit_minimum}` at each step until `target_unit` is
  # reached. If the chain runs out before `target_unit` (no
  # `implicit_enumerator` for the current unit), return an error.
  defp fill_to_resolution(time, current_unit, target_unit, _calendar)
       when current_unit == target_unit do
    {:ok, time}
  end

  defp fill_to_resolution(time, current_unit, target_unit, calendar) do
    case Unit.implicit_enumerator(current_unit, calendar) do
      nil ->
        {:error,
         "No path from #{inspect(current_unit)} to #{inspect(target_unit)} under " <>
           "calendar #{inspect(calendar)} — no finer unit is defined."}

      {next_unit, range} ->
        min_value = range_first(range)
        new_time = time ++ [{next_unit, min_value}]
        fill_to_resolution(new_time, next_unit, target_unit, calendar)
    end
  end

  defp range_first(%Range{first: first}), do: first

  @doc """
  Return a Tempo at the specified resolution, dispatching to
  `trunc/2` or `extend_resolution/2` based on whether `target_unit`
  is coarser or finer than the current resolution.

  This is the unified entry point for normalising resolution. It
  is idempotent when `target_unit` matches the current resolution.

  ### Arguments

  * `tempo` is any `t:#{__MODULE__}.t/0`.

  * `target_unit` is any time unit atom (`:year`, `:month`,
    `:day`, `:hour`, `:minute`, `:second`, …).

  ### Returns

  * The Tempo at the requested resolution, or

  * `{:error, reason}`.

  ### Examples

      iex> Tempo.at_resolution(~o"2020Y", :day)
      ~o"2020Y1M1D"

      iex> Tempo.at_resolution(~o"2020Y6M15DT10H", :day)
      ~o"2020Y6M15D"

      iex> Tempo.at_resolution(~o"2020Y6M15D", :day)
      ~o"2020Y6M15D"

  """
  @spec at_resolution(tempo :: t, target_unit :: time_unit()) ::
          t | {:error, error_reason()}
  def at_resolution(%Tempo{} = tempo, target_unit) do
    with {:ok, target_unit} <- validate_unit(target_unit) do
      {current_unit, _span} = resolution(tempo)

      case Unit.compare(target_unit, current_unit) do
        :eq -> tempo
        :gt -> trunc(tempo, target_unit)
        :lt -> extend_resolution(tempo, target_unit)
      end
    end
  end

  @doc """
  Convert a Tempo struct into a Date.

  """
  def to_date(%Tempo{time: [year: year, month: month, day: day]}) do
    Date.new(year, month, day)
  end

  def to_date(%Tempo{}) do
    {:error, :invalid_date}
  end

  @doc """
  Convert a Tempo struct into a Time.

  """
  def to_time(%Tempo{time: [hour: hour, minute: minute, second: second], shift: nil}) do
    Time.new(hour, minute, second, 0)
  end

  def to_time(%Tempo{}) do
    {:error, :invalid_time}
  end

  @doc """
  Convert a Tempo struct into a NaiveDateTime.

  """
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

  ## ---------------------------------------------------------
  ## Current time — clock-backed "now" entry points
  ## ---------------------------------------------------------

  @doc """
  Return the current UTC time as a second-resolution `t:t/0`
  anchored in `Etc/UTC`.

  Reads from the clock configured under `:ex_tempo, :clock`,
  defaulting to `Tempo.Clock.System`. Tests that need determinism
  should configure `Tempo.Clock.Test` — see its module doc.

  ### Returns

  * A `t:t/0` at second resolution with `shift: [hour: 0]` and
    `extended.zone_id: "Etc/UTC"`.

  ### Examples

      iex> tempo = Tempo.utc_now()
      iex> tempo.extended.zone_id
      "Etc/UTC"

      iex> Tempo.utc_now() |> Tempo.resolution()
      {:second, 1}

  """
  @spec utc_now() :: t()
  def utc_now do
    Tempo.Clock.utc_now() |> from_date_time()
  end

  @doc """
  Return the current time in the given IANA time zone as a
  second-resolution `t:t/0`.

  Reads from the configured clock (as `utc_now/0` does) and shifts
  the result into `zone`. The returned Tempo's wall-clock time is
  the zone-local reading of the current UTC instant.

  ### Arguments

  * `zone` is an IANA time zone name (e.g. `"Europe/Paris"`,
    `"America/New_York"`). Defaults to `"Etc/UTC"`, in which case
    `now/1` is equivalent to `utc_now/0`.

  ### Returns

  * A `t:t/0` at second resolution with `extended.zone_id: zone`.

  ### Examples

      iex> tempo = Tempo.now("Europe/London")
      iex> tempo.extended.zone_id
      "Europe/London"

      iex> Tempo.now("Etc/UTC").extended.zone_id
      "Etc/UTC"

  """
  @spec now(String.t()) :: t()
  def now(zone \\ "Etc/UTC") when is_binary(zone) do
    utc = Tempo.Clock.utc_now()

    case zone do
      "Etc/UTC" ->
        from_date_time(utc)

      _other ->
        utc
        |> DateTime.shift_zone!(zone, Tzdata.TimeZoneDatabase)
        |> from_date_time()
    end
  end

  @doc """
  Return today's date in UTC as a day-resolution `t:t/0`.

  ### Returns

  * A `t:t/0` at day resolution anchored in `Etc/UTC`.

  ### Examples

      iex> Tempo.utc_today() |> Tempo.resolution()
      {:day, 1}

  """
  @spec utc_today() :: t() | {:error, error_reason()}
  def utc_today do
    utc_now() |> trunc(:day)
  end

  @doc """
  Return today's date in the given IANA time zone as a
  day-resolution `t:t/0`.

  "Today" is zone-relative: at 11pm New York on the 14th it is
  already the 15th in Paris. This function answers the zone-local
  question.

  ### Arguments

  * `zone` is an IANA time zone name. Defaults to `"Etc/UTC"`.

  ### Returns

  * A `t:t/0` at day resolution whose wall date is the date in
    `zone` at the current UTC instant.

  ### Examples

      iex> Tempo.today("Etc/UTC") |> Tempo.resolution()
      {:day, 1}

  """
  @spec today(String.t()) :: t() | {:error, error_reason()}
  def today(zone \\ "Etc/UTC") when is_binary(zone) do
    now(zone) |> trunc(:day)
  end

  ## ---------------------------------------------------------
  ## Zone shifting — project a zoned Tempo into another zone
  ## ---------------------------------------------------------

  @doc """
  Project a zoned or UTC-anchored Tempo into another IANA time
  zone, preserving the UTC instant.

  The returned Tempo names the same point on the time line, but the
  wall-clock reading is the one an observer in `target_zone` would
  see. This is the stdlib analogue of `DateTime.shift_zone/2`: in
  Tempo it routes through `Tempo.Compare.to_utc_seconds/1` so zone
  rules are re-evaluated from Tzdata at call time.

  ### Arguments

  * `tempo` is a `t:t/0` that carries zone information — either an
    IANA zone on `extended.zone_id`, a numeric `zone_offset`, or a
    `shift` keyword list. A floating Tempo (no zone info) cannot be
    projected because its UTC instant is undefined.

  * `target_zone` is an IANA zone name (`"Europe/Paris"`,
    `"America/New_York"`, `"Etc/UTC"`, …).

  ### Returns

  * `{:ok, tempo}` at second resolution in `target_zone`, or

  * `{:error, reason}` when `tempo` is not zoned or `target_zone`
    is unknown to Tzdata.

  ### Examples

      iex> paris = Tempo.from_iso8601!("2026-06-15T14:00:00[Europe/Paris]")
      iex> {:ok, new_york} = Tempo.shift_zone(paris, "America/New_York")
      iex> new_york.extended.zone_id
      "America/New_York"
      iex> Keyword.take(new_york.time, [:hour, :minute])
      [hour: 8, minute: 0]

  """
  @spec shift_zone(t(), String.t()) :: {:ok, t()} | {:error, error_reason()}
  def shift_zone(%Tempo{} = tempo, target_zone) when is_binary(target_zone) do
    cond do
      not anchored?(tempo) ->
        {:error,
         "Cannot shift_zone/2 a non-anchored Tempo (no :year component). Only " <>
           "anchored values have a UTC projection."}

      floating?(tempo) ->
        {:error,
         "Cannot shift_zone/2 a floating Tempo (no zone or offset information). " <>
           "Attach a zone via parse (`~o\"...[#{target_zone}]\"`) or an offset " <>
           "(`~o\"...Z\"` or `~o\"...+HH:MM\"`) first."}

      true ->
        do_shift_zone(tempo, target_zone)
    end
  end

  defp floating?(%Tempo{shift: nil, extended: nil}), do: true
  defp floating?(%Tempo{shift: nil, extended: %{zone_id: nil, zone_offset: nil}}), do: true
  defp floating?(%Tempo{}), do: false

  defp do_shift_zone(%Tempo{calendar: calendar} = tempo, "Etc/UTC") do
    utc_seconds = Tempo.Compare.to_utc_seconds(tempo)

    {{year, month, day}, {hour, minute, second}} =
      :calendar.gregorian_seconds_to_datetime(utc_seconds)

    {:ok,
     %__MODULE__{
       time: [
         year: year,
         month: month,
         day: day,
         hour: hour,
         minute: minute,
         second: second
       ],
       shift: [hour: 0],
       calendar: calendar || Calendrical.Gregorian,
       extended: %{zone_id: "Etc/UTC", zone_offset: 0, calendar: nil, tags: %{}}
     }}
  end

  defp do_shift_zone(%Tempo{calendar: calendar} = tempo, target_zone) do
    utc_seconds = Tempo.Compare.to_utc_seconds(tempo)

    case Tzdata.periods_for_time(target_zone, utc_seconds, :utc) do
      [period | _] ->
        offset_seconds = period.utc_off + period.std_off
        wall_seconds = utc_seconds + offset_seconds

        {{year, month, day}, {hour, minute, second}} =
          :calendar.gregorian_seconds_to_datetime(wall_seconds)

        {:ok,
         %__MODULE__{
           time: [
             year: year,
             month: month,
             day: day,
             hour: hour,
             minute: minute,
             second: second
           ],
           shift: offset_to_shift(offset_seconds),
           calendar: calendar || Calendrical.Gregorian,
           extended: %{
             zone_id: target_zone,
             zone_offset: div(offset_seconds, 60),
             calendar: nil,
             tags: %{}
           }
         }}

      [] ->
        {:error,
         "Tzdata has no period for #{inspect(target_zone)} at the given UTC " <>
           "instant. Check the zone name."}
    end
  end

  ## ---------------------------------------------------------
  ## Calendar accessors — day_of_week, day_of_year, …
  ## ---------------------------------------------------------

  @doc """
  Return the day of the week as an integer (`1..7`) using the
  Tempo value's calendar.

  For the Gregorian calendar with `:default` ordering, `1` is
  Monday and `7` is Sunday — matching `Date.day_of_week/1`.

  ### Arguments

  * `tempo` is a `t:t/0` anchored with at least year/month/day
    components.

  * `starting_on` is a day-of-week atom controlling which day is
    numbered `1`. Accepts `:default` (calendar's default),
    `:monday`, `:tuesday`, `:wednesday`, `:thursday`, `:friday`,
    `:saturday`, or `:sunday`. Defaults to `:default`.

  ### Returns

  * Integer `1..7`.

  ### Raises

  * `ArgumentError` when `tempo` has no date components.

  ### Examples

      iex> Tempo.day_of_week(~o"2026-06-15")
      1

      iex> Tempo.day_of_week(~o"2026-06-15", :sunday)
      2

  """
  @spec day_of_week(t(), atom()) :: 1..7
  def day_of_week(%Tempo{} = tempo, starting_on \\ :default) do
    {year, month, day} = require_ymd!(tempo, :day_of_week)
    {dow, _first, _last} = calendar_of(tempo).day_of_week(year, month, day, starting_on)
    dow
  end

  @doc """
  Return the 1-based ordinal day of the year (`1..365` or `1..366`
  in a leap year) using the Tempo value's calendar.

  ### Arguments

  * `tempo` is a `t:t/0` anchored with at least year/month/day
    components.

  ### Returns

  * A positive integer.

  ### Raises

  * `ArgumentError` when `tempo` has no date components.

  ### Examples

      iex> Tempo.day_of_year(~o"2026-01-01")
      1

      iex> Tempo.day_of_year(~o"2024-12-31")
      366

  """
  @spec day_of_year(t()) :: pos_integer()
  def day_of_year(%Tempo{} = tempo) do
    {year, month, day} = require_ymd!(tempo, :day_of_year)
    calendar_of(tempo).day_of_year(year, month, day)
  end

  @doc """
  Return the 1-based quarter of the year (`1..4`) for Gregorian-like
  calendars.

  ### Arguments

  * `tempo` is a `t:t/0` anchored with at least year/month
    components.

  ### Returns

  * An integer `1..4`.

  ### Raises

  * `ArgumentError` when `tempo` has no year/month components.

  ### Examples

      iex> Tempo.quarter_of_year(~o"2026-01-15")
      1

      iex> Tempo.quarter_of_year(~o"2026-11-30")
      4

  """
  @spec quarter_of_year(t()) :: 1..4
  def quarter_of_year(%Tempo{} = tempo) do
    {year, month, day} = require_ymd!(tempo, :quarter_of_year, default_day: 1)
    calendar_of(tempo).quarter_of_year(year, month, day)
  end

  @doc """
  Return `true` when the Tempo's year is a leap year under its
  calendar.

  ### Arguments

  * `tempo` is a `t:t/0` with at least a year component.

  ### Returns

  * `true` or `false`.

  ### Raises

  * `ArgumentError` when `tempo` has no year component.

  ### Examples

      iex> Tempo.leap_year?(~o"2024")
      true

      iex> Tempo.leap_year?(~o"2025")
      false

  """
  @spec leap_year?(t()) :: boolean()
  def leap_year?(%Tempo{time: time} = tempo) do
    year =
      Keyword.get(time, :year) ||
        raise ArgumentError,
              "Tempo.leap_year?/1 requires a year component. Got: #{inspect(tempo)}"

    calendar_of(tempo).leap_year?(year)
  end

  @doc """
  Return the number of days in the Tempo's month under its
  calendar.

  ### Arguments

  * `tempo` is a `t:t/0` with year and month components.

  ### Returns

  * A positive integer.

  ### Raises

  * `ArgumentError` when `tempo` has no year or no month
    component.

  ### Examples

      iex> Tempo.days_in_month(~o"2024-02-15")
      29

      iex> Tempo.days_in_month(~o"2025-02")
      28

      iex> Tempo.days_in_month(~o"2026-04")
      30

  """
  @spec days_in_month(t()) :: pos_integer()
  def days_in_month(%Tempo{time: time} = tempo) do
    year =
      Keyword.get(time, :year) ||
        raise ArgumentError,
              "Tempo.days_in_month/1 requires a year component. Got: #{inspect(tempo)}"

    month =
      Keyword.get(time, :month) ||
        raise ArgumentError,
              "Tempo.days_in_month/1 requires a month component. Got: #{inspect(tempo)}"

    calendar_of(tempo).days_in_month(year, month)
  end

  # Return the calendar module for a Tempo, defaulting to
  # Calendrical.Gregorian when nil. Centralises the fallback so
  # every accessor uses the same rule.
  defp calendar_of(%Tempo{calendar: nil}), do: Calendrical.Gregorian
  defp calendar_of(%Tempo{calendar: calendar}), do: calendar

  # Extract {year, month, day} from a Tempo or raise a uniform
  # error. Missing month or day default to 1 (start-of-unit) so
  # quarter-of-year on a year-resolution value still works.
  defp require_ymd!(%Tempo{time: time} = tempo, function, opts \\ []) do
    default_day = Keyword.get(opts, :default_day, 1)

    year =
      Keyword.get(time, :year) ||
        raise ArgumentError,
              "Tempo.#{function}/1 requires a year component. Got: #{inspect(tempo)}"

    month = Keyword.get(time, :month, 1)
    day = Keyword.get(time, :day, default_day)
    {year, month, day}
  end

  ## ---------------------------------------------------------
  ## Day and month boundary helpers
  ## ---------------------------------------------------------

  @doc """
  Return a second-resolution `t:t/0` at the start (`00:00:00`) of
  the day that contains `tempo`.

  Preserves the input's calendar, shift, and zone metadata so that
  beginning-of-day in `[Europe/Paris]` still names midnight Paris
  time, not midnight UTC.

  ### Arguments

  * `tempo` is a `t:t/0` with at least year/month/day components.

  ### Returns

  * A second-resolution `t:t/0`.

  ### Examples

      iex> Tempo.beginning_of_day(~o"2026-06-15T14:30:00")
      ~o"2026Y6M15DT0H0M0S"

      iex> Tempo.beginning_of_day(~o"2026-06-15")
      ~o"2026Y6M15DT0H0M0S"

  """
  @spec beginning_of_day(t()) :: t() | {:error, error_reason()}
  def beginning_of_day(%Tempo{} = tempo) do
    tempo
    |> trunc(:day)
    |> extend_to_second()
  end

  @doc """
  Return a second-resolution `t:t/0` at the **exclusive** end of
  the day that contains `tempo` — i.e. `00:00:00` of the following
  day.

  Tempo follows the half-open `[from, to)` convention everywhere,
  so `end_of_day/1` returns the upper bound at which the day ends
  and the next day begins. This is the right argument for
  interval construction — pairing `beginning_of_day/1` and
  `end_of_day/1` gives you the 24-hour (or DST-adjusted) window.

  ### Arguments

  * `tempo` is a `t:t/0` with at least year/month/day components.

  ### Returns

  * A second-resolution `t:t/0`.

  ### Examples

      iex> Tempo.end_of_day(~o"2026-06-15T14:30:00")
      ~o"2026Y6M16DT0H0M0S"

      iex> Tempo.end_of_day(~o"2026-12-31")
      ~o"2027Y1M1DT0H0M0S"

  """
  @spec end_of_day(t()) :: t() | {:error, error_reason()}
  def end_of_day(%Tempo{} = tempo) do
    case beginning_of_day(tempo) do
      {:error, _} = err -> err
      %Tempo{} = start -> Tempo.Math.add(start, Tempo.Duration.new(day: 1))
    end
  end

  @doc """
  Return a second-resolution `t:t/0` at the start of the month
  (`YYYY-MM-01T00:00:00`) that contains `tempo`.

  ### Arguments

  * `tempo` is a `t:t/0` with at least year/month components.

  ### Returns

  * A second-resolution `t:t/0`.

  ### Examples

      iex> Tempo.beginning_of_month(~o"2026-06-15T14:30:00")
      ~o"2026Y6M1DT0H0M0S"

      iex> Tempo.beginning_of_month(~o"2026-06")
      ~o"2026Y6M1DT0H0M0S"

  """
  @spec beginning_of_month(t()) :: t() | {:error, error_reason()}
  def beginning_of_month(%Tempo{} = tempo) do
    tempo
    |> trunc(:month)
    |> extend_to_second()
  end

  @doc """
  Return a second-resolution `t:t/0` at the **exclusive** end of
  the month that contains `tempo` — i.e. the first day of the
  following month at `00:00:00`.

  Half-open by design; see `end_of_day/1` for the rationale.

  ### Arguments

  * `tempo` is a `t:t/0` with at least year/month components.

  ### Returns

  * A second-resolution `t:t/0`.

  ### Examples

      iex> Tempo.end_of_month(~o"2026-06-15")
      ~o"2026Y7M1DT0H0M0S"

      iex> Tempo.end_of_month(~o"2026-12")
      ~o"2027Y1M1DT0H0M0S"

  """
  @spec end_of_month(t()) :: t() | {:error, error_reason()}
  def end_of_month(%Tempo{} = tempo) do
    case beginning_of_month(tempo) do
      {:error, _} = err -> err
      %Tempo{} = start -> Tempo.Math.add(start, Tempo.Duration.new(month: 1))
    end
  end

  # Pad to second resolution. `extend_resolution/2` handles the
  # general case; this helper just threads the {:error, _} case
  # through so the boundary helpers degrade gracefully.
  defp extend_to_second(%Tempo{} = tempo) do
    extend_resolution(tempo, :second)
  end

  defp extend_to_second({:error, _} = err), do: err

  ## ---------------------------------------------------------
  ## shift/2 — ergonomic keyword-list arithmetic
  ## ---------------------------------------------------------

  @doc """
  Shift a `t:t/0` by a keyword list of signed unit amounts,
  returning a new `t:t/0`.

  This is the ergonomic companion to `Tempo.Math.add/2` — the
  Duration-based API remains the principled path (durations carry
  their own calendar and leap-second semantics), but for ad-hoc
  shifts a keyword list reads more naturally.

  Units are applied largest-to-smallest with the standard
  month-end clamping rule (e.g. `~o"2024-01-31" + 1 month` is
  `2024-02-29`, not `2024-03-02`).

  ### Arguments

  * `tempo` is any `t:t/0`.

  * `units` is a keyword list of `{unit, amount}` pairs such as
    `[month: 1, day: -5]` or `[year: 2]`. Valid units: `:year`,
    `:month`, `:week`, `:day`, `:hour`, `:minute`, `:second`.
    Amounts may be negative.

  ### Returns

  * The shifted `t:t/0`.

  ### Examples

      iex> Tempo.shift(~o"2026-06-15", month: 1, day: -5)
      ~o"2026Y7M10D"

      iex> Tempo.shift(~o"2026-01-31", month: 1)
      ~o"2026Y2M28D"

      iex> Tempo.shift(~o"2026-06-15T10:00:00", hour: -3)
      ~o"2026Y6M15DT7H0M0S"

  """
  @spec shift(t(), keyword()) :: t()
  def shift(%Tempo{} = tempo, units) when is_list(units) do
    Tempo.Math.add(tempo, Tempo.Duration.new(units))
  end

  ## ---------------------------------------------------------
  ## Locale-aware formatting — to_string/1,2
  ## ---------------------------------------------------------

  @doc """
  Format a Tempo value as a locale-aware string.

  Routes through Localize so format patterns, month and weekday
  names, day periods, and punctuation all follow CLDR data for
  the chosen locale. The default format is keyed off the Tempo's
  resolution — a year-only value renders as `"2026"`, a month
  value as `"Jun 2026"`, a day value as `"Jun 15, 2026"`, and so
  on.

  `Tempo.to_string/1,2` is the end-user display function.
  `inspect/1` remains the programmer-facing form and returns the
  `~o"…"` sigil representation unchanged.

  ### Arguments

  * `value` is a `t:t/0`, `t:Tempo.Interval.t/0`, or
    `t:Tempo.IntervalSet.t/0`.

  ### Options

  * `:format` is a CLDR format atom (`:short | :medium | :long |
    :full`), a skeleton atom (`:yMMM`, `:yMMMd`, `:hm`, …), or a
    pattern string. Defaults to a resolution-appropriate choice
    (see the module doc of `Tempo.Format` for the table).

  * `:locale` is a CLDR locale identifier such as `"en"`,
    `"en-GB"`, or `"de"`. Defaults to Localize's configured
    default locale.

  * Any other option accepted by `Localize.Date.to_string/2`,
    `Localize.Time.to_string/2`, `Localize.DateTime.to_string/2`,
    or `Localize.Interval.to_string/3` is forwarded verbatim.

  ### Returns

  * A `t:String.t/0`.

  ### Raises

  * Any exception Localize raises for invalid locales, missing
    CLDR data, or unresolvable format skeletons.

  ### Examples

      iex> Tempo.to_string(~o"2026")
      "Jan\u2009\u2013\u2009Dec 2026"

      iex> Tempo.to_string(~o"2026-06")
      "Jun 1\u2009\u2013\u200930, 2026"

      iex> Tempo.to_string(~o"2026-06-15")
      "Jun 15, 2026"

      iex> Tempo.to_string(~o"2026-06-15", format: :long)
      "June 15, 2026"

      iex> Tempo.to_string(~o"2026", format: :long)
      "January\u2009\u2013\u2009December 2026"

  """
  @spec to_string(t() | Tempo.Interval.t() | Tempo.IntervalSet.t(), keyword()) ::
          String.t()
  defdelegate to_string(value, options \\ []), to: Tempo.Format

  @doc """
  Convert an implicit-span `t:#{__MODULE__}.t/0` into the
  equivalent explicit `t:Tempo.Interval.t/0` or
  `t:Tempo.IntervalSet.t/0`.

  Every Tempo value represents a bounded interval on the time
  line. `~o"2026-01"` *is* the interval `[2026-01-01, 2026-02-01)`
  — `to_interval/1` materialises that implicit span as a pair of
  concrete endpoints under the half-open `[from, to)` convention
  (`from` inclusive, `to` exclusive). This is the canonical
  representation used by the upcoming set-operations API
  (`union/2`, `intersection/2`, `coalesce/1`).

  When the input expands to multiple disjoint spans — a set of
  explicit values, a range over a time unit, a stepped range —
  the result is a `%Tempo.IntervalSet{}` with intervals sorted
  and coalesced. The conversion is idempotent on values that are
  already explicit.

  ### Arguments

  * `value` is a `t:#{__MODULE__}.t/0`, `t:Tempo.Interval.t/0`,
    `t:Tempo.IntervalSet.t/0`, or `t:Tempo.Set.t/0`.

  ### Options

  * `:bound` is a Tempo value whose upper endpoint limits
    expansion of an unbounded recurrence (`recurrence: :infinity`
    with no `UNTIL`). Required to materialise such rules;
    ignored otherwise.

  * `:coalesce` controls whether the resulting IntervalSet
    merges adjacent or overlapping intervals (`true`, the
    default) or preserves each expanded occurrence as a
    distinct interval (`false`). Expansion consumers that care
    about event identity — `Tempo.ICal`, the RRULE expander —
    pass `false`; ordinary implicit-span materialisation uses
    the default.

  ### Returns

  * `{:ok, interval}` when the value materialises to a single
    contiguous span.

  * `{:ok, interval_set}` when the value expands to multiple
    disjoint spans.

  * `{:error, reason}` when the input cannot be materialised — a
    bare `Tempo.Duration` (no anchor), a `Tempo` already at its
    finest resolution (no finer unit to bound the span), a
    one-of `Tempo.Set` (epistemic disjunction is not an interval
    list; the user must pick one or handle the disjunction
    themselves), or an unbounded recurrence with no `:bound`.

  ### Examples

      iex> {:ok, tempo} = Tempo.from_iso8601("2026-01")
      iex> {:ok, interval} = Tempo.to_interval(tempo)
      iex> interval.from.time
      [year: 2026, month: 1, day: 1]
      iex> interval.to.time
      [year: 2026, month: 2, day: 1]

      iex> {:ok, tempo} = Tempo.from_iso8601("156X")
      iex> {:ok, interval} = Tempo.to_interval(tempo)
      iex> {interval.from.time, interval.to.time}
      {[year: 1560], [year: 1570]}

      iex> {:ok, duration} = Tempo.from_iso8601("P3M")
      iex> Tempo.to_interval(duration)
      {:error, "Cannot materialise a Tempo.Duration into an interval — a duration has no anchor on the time line."}

  """
  @spec to_interval(
          Tempo.t()
          | Tempo.Interval.t()
          | Tempo.IntervalSet.t()
          | Tempo.Set.t()
          | Tempo.Duration.t(),
          keyword()
        ) ::
          {:ok, Tempo.Interval.t() | Tempo.IntervalSet.t()} | {:error, error_reason()}
  def to_interval(value, opts \\ [])

  # A bounded recurrence (`R3/1985-01/P1M`) expands to N disjoint
  # intervals. Each occurrence starts at `from + i*duration` and
  # runs for one duration. Requires `Tempo.Math.add/2`.
  #
  # When `repeat_rule` is present, BY-rule selections apply
  # before the COUNT cap: N = "the first N occurrences that
  # survived the BY-rule filter," per RFC 5545.
  def to_interval(
        %Tempo.Interval{
          recurrence: n,
          direction: direction,
          from: %Tempo{} = from,
          duration: %Tempo.Duration{} = duration
        } = interval,
        opts
      )
      when is_integer(n) and n > 1 do
    step = if direction == -1, do: negate_duration(duration), else: duration

    intervals =
      iterate_recurrence(
        from,
        step,
        occurrence_end_fn(from, duration, interval),
        fn _start -> true end,
        selection_fn(interval, duration),
        interval.metadata,
        n
      )

    Tempo.IntervalSet.new(intervals, coalesce: coalesce_opt(opts))
  end

  # An unbounded recurrence with UNTIL: `recurrence: :infinity`
  # plus `to: %Tempo{}`. Iterate by one cadence at a time and stop
  # the step before the first occurrence whose start is at or past
  # the UNTIL endpoint. `from + i*duration` while `from(i) ≤ to`.
  def to_interval(
        %Tempo.Interval{
          recurrence: :infinity,
          from: %Tempo{} = from,
          duration: %Tempo.Duration{} = duration,
          to: %Tempo{} = until
        } = interval,
        opts
      ) do
    intervals =
      iterate_recurrence(
        from,
        duration,
        occurrence_end_fn(from, duration, interval),
        &under_until?(&1, until),
        selection_fn(interval, duration),
        interval.metadata
      )

    Tempo.IntervalSet.new(intervals, coalesce: coalesce_opt(opts))
  end

  # An unbounded recurrence with `:bound` option: `recurrence:
  # :infinity`, `to` is nil/:undefined, and the caller has
  # supplied a `:bound` Tempo value. Iterate while every new
  # occurrence's start falls strictly before the bound's upper
  # endpoint.
  def to_interval(
        %Tempo.Interval{
          recurrence: :infinity,
          from: %Tempo{} = from,
          duration: %Tempo.Duration{} = duration,
          to: to
        } = interval,
        opts
      )
      when to in [nil, :undefined] do
    case Keyword.get(opts, :bound) do
      nil ->
        {:error,
         "Cannot materialise an unbounded recurrence (recurrence: :infinity, no UNTIL). " <>
           "Supply a :bound option — any Tempo value whose upper endpoint limits the " <>
           "expansion."}

      bound ->
        case bound_upper(bound) do
          {:ok, bound_to} ->
            intervals =
              iterate_recurrence(
                from,
                duration,
                occurrence_end_fn(from, duration, interval),
                &under_bound?(&1, bound_to),
                selection_fn(interval, duration),
                interval.metadata
              )

            Tempo.IntervalSet.new(intervals, coalesce: coalesce_opt(opts))

          {:error, _} = err ->
            err
        end
    end
  end

  # A `from + duration` interval (`1985-01/P3M`). Materialise to
  # a closed `[from, from + duration)` interval. Preserves the
  # source interval's metadata — callers like `Tempo.ICal` need
  # event-level metadata (summary, location, …) to ride along
  # onto every materialised occurrence.
  def to_interval(
        %Tempo.Interval{
          from: %Tempo{} = from,
          duration: %Tempo.Duration{} = duration,
          to: to,
          recurrence: 1,
          metadata: metadata
        },
        _opts
      )
      when to in [nil, :undefined] do
    to_tempo = Tempo.Math.add(from, duration)
    {:ok, %Tempo.Interval{from: from, to: to_tempo, metadata: metadata}}
  end

  # A `duration + to` interval (`P1M/1985-06`). Materialise to a
  # closed `[to - duration, to)` interval.
  def to_interval(
        %Tempo.Interval{
          from: :undefined,
          duration: %Tempo.Duration{} = duration,
          to: %Tempo{} = to,
          recurrence: 1,
          metadata: metadata
        },
        _opts
      ) do
    from_tempo = Tempo.Math.subtract(to, duration)
    {:ok, %Tempo.Interval{from: from_tempo, to: to, metadata: metadata}}
  end

  def to_interval(%Tempo.Interval{} = interval, _opts) do
    {:ok, interval}
  end

  def to_interval(%Tempo.IntervalSet{} = set, _opts) do
    {:ok, set}
  end

  def to_interval(%Tempo{} = tempo, _opts) do
    # Step 1: if the Tempo has a non-contiguous mask (a mask
    # followed by concrete units — e.g. `1985-XX-15`), rewrite the
    # time list to substitute the mask with the list of valid
    # values. This turns a previously-widened case into a proper
    # multi-interval expansion.
    tempo = expand_non_contiguous_mask(tempo)

    # Step 2: detect whether the resulting Tempo expands to
    # multiple intervals. A "multi" shape is any time slot whose
    # value is a list containing more than one candidate (ranges,
    # multi-element lists). Masks, scalars, and single-element
    # lists use the existing single-interval path in
    # `next_unit_boundary/1`.
    if multi_tempo?(tempo) do
      materialise_multi(tempo)
    else
      case Tempo.Interval.next_unit_boundary(tempo) do
        {:ok, {lower, upper}} -> {:ok, %Tempo.Interval{from: lower, to: upper}}
        {:error, _} = err -> err
      end
    end
  end

  # An all-of `%Tempo.Set{}` (`{a,b,c}` syntax at the expression
  # level) is free/busy semantics — every member is materialised
  # and coalesced into an `IntervalSet`. A one-of set
  # (`[a,b,c]`) is an epistemic disjunction ("it was one of
  # these, I don't know which") and stays as a set; flattening it
  # to an IntervalSet would assert all members happened, which is
  # the opposite of what the user wrote.
  def to_interval(%Tempo.Set{type: :all, set: members}, _opts) do
    members_to_interval_set(members)
  end

  def to_interval(%Tempo.Set{type: :one}, _opts) do
    {:error,
     "Cannot materialise a one-of Tempo.Set (epistemic disjunction) " <>
       "into an interval list. Pick a specific member or handle the " <>
       "disjunction in calling code."}
  end

  def to_interval(%Tempo.Duration{}, _opts) do
    {:error,
     "Cannot materialise a Tempo.Duration into an interval — " <>
       "a duration has no anchor on the time line."}
  end

  # Apply a duration N times as a single scalar-multiplied step:
  # `tempo + (n × duration)` in one call, not `n` successive
  # `+ duration` calls.
  #
  # Scalar vs iterative matters when the anchor hits a
  # calendar-clamped day. DTSTART = 2020-02-29 with cadence
  # `year: 1`:
  #
  # * Iterative (+1y then +1y then +1y then +1y): the first step
  #   clamps Feb 29 → Feb 28. Every subsequent step starts from
  #   Feb 28, so day 29 is lost forever.
  #
  # * Scalar (+4y in one shot): 2020-02-29 → 2024-02-29 (a leap
  #   year, valid).
  #
  # Matches the RFC intent: "DTSTART + i × INTERVAL" addresses a
  # specific point relative to DTSTART, not a walk.
  defp add_n_durations(tempo, _duration, 0), do: tempo

  defp add_n_durations(tempo, %Tempo.Duration{time: time}, n) when n > 0 do
    scaled = Enum.map(time, fn {unit, amount} -> {unit, amount * n} end)
    Tempo.Math.add(tempo, %Tempo.Duration{time: scaled})
  end

  defp negate_duration(%Tempo.Duration{time: time}) do
    negated = Enum.map(time, fn {unit, amount} -> {unit, -amount} end)
    %Tempo.Duration{time: negated}
  end

  ## ---------------------------------------------------------
  ## Recurrence-expansion helpers
  ##
  ## `iterate_recurrence/5` is the single stepwise expander used
  ## by both the UNTIL and :bound clauses above. The only
  ## difference between the two is the termination predicate;
  ## factoring it out keeps the interpreter's loop authoritative
  ## and eliminates parallel engines in calling modules.
  ## ---------------------------------------------------------

  # Hard safety ceiling on how many occurrences any single
  # recurrence can materialise. Matches `Tempo.ICal.@safety_cap`.
  @recurrence_safety_cap 10_000

  # Coalescing is the default for back-compat with `to_interval/1`
  # semantics: an `R3/1985-01/P1M` interval is a single 3-month
  # span post-coalesce, which matches the documented contract.
  # Expansion consumers that care about event identity
  # (Tempo.ICal, the RRULE expander) pass `coalesce: false`.
  defp coalesce_opt(opts) do
    case Keyword.get(opts, :coalesce) do
      false -> false
      _ -> true
    end
  end

  # The stepwise expander. Shared by all three recurrence shapes:
  #
  # * `start_predicate` drives upstream termination — returns
  #   `true` while the candidate's start is still in-bounds
  #   (pre-filter), `false` once we're past UNTIL / the `:bound`.
  #
  # * `selection_fn` is the BY-rule resolver. It takes one
  #   candidate `%Interval{}` and returns a list (0 for LIMIT
  #   rejection, 1 for passthrough, N for EXPAND). Delegates to
  #   `Tempo.RRule.Selection.apply/3`.
  #
  # * `output_limit` is the downstream cap — `n` for a bounded
  #   recurrence, `@recurrence_safety_cap` otherwise. BY-rule
  #   filtering happens before this cap, so a COUNT of 3 with
  #   `BYMONTH=6` really means "first 3 June occurrences."
  #
  # The upstream `@recurrence_safety_cap` on the candidate stream
  # is a belt-and-braces guard against impossible BY-rule
  # combinations (e.g. `BYMONTHDAY=31` for months that never have
  # 31 days — the filter would reject every candidate forever).
  defp iterate_recurrence(
         %Tempo{} = from,
         %Tempo.Duration{} = cadence,
         occurrence_end_fn,
         start_predicate,
         selection_fn,
         metadata,
         output_limit \\ @recurrence_safety_cap
       )
       when is_function(occurrence_end_fn, 2) and is_function(start_predicate, 1) and
              is_function(selection_fn, 1) do
    0
    |> Stream.iterate(&(&1 + 1))
    |> Stream.map(fn i ->
      start = add_n_durations(from, cadence, i)
      {start, %Tempo.Interval{from: start, to: occurrence_end_fn.(start, i), metadata: metadata}}
    end)
    |> Stream.take_while(fn {start, _} -> start_predicate.(start) end)
    |> Stream.take(@recurrence_safety_cap)
    |> Stream.flat_map(fn {_start, candidate} -> selection_fn.(candidate) end)
    # DTSTART floor — per RFC 5545, DTSTART is always the first
    # occurrence. BY-rule EXPAND can legitimately produce dates
    # earlier in the DTSTART-containing period (e.g.
    # BYMONTHDAY=1 with DTSTART=Sep 30 → also Sep 1). Drop any
    # such pre-DTSTART candidates.
    |> Stream.reject(fn %Tempo.Interval{from: f} -> before_dtstart?(f, from) end)
    |> Stream.take(output_limit)
    |> Enum.to_list()
  end

  defp before_dtstart?(%Tempo{} = candidate_from, %Tempo{} = dtstart) do
    Tempo.Compare.compare_endpoints(candidate_from, dtstart) == :earlier
  end

  # Build the per-candidate selection filter/expand function. When
  # `repeat_rule` is nil, returns a passthrough (identity). When
  # non-nil, delegates to `Tempo.RRule.Selection.apply/3` with the
  # enclosing FREQ derived from the cadence's primary unit.
  defp selection_fn(%Tempo.Interval{repeat_rule: nil}, _cadence) do
    fn candidate -> [candidate] end
  end

  defp selection_fn(%Tempo.Interval{repeat_rule: %Tempo{} = rule}, %Tempo.Duration{} = cadence) do
    freq = freq_of(cadence)
    fn candidate -> Tempo.RRule.Selection.apply(candidate, rule, freq) end
  end

  # The FREQ of a recurrence is the primary unit of its cadence —
  # e.g. `%Duration{time: [week: 1]}` → `:week`.
  defp freq_of(%Tempo.Duration{time: [{unit, _amount} | _]}), do: unit

  # Resolve a "given this iteration's start, what's the
  # occurrence's `to`?" function from the interval's metadata or
  # its AST fields. Priority order:
  #
  # 1. `metadata.occurrence_base_to` — an occurrence-0 `to` Tempo.
  #    Each occurrence's `to` is `base_to` shifted by `i × cadence`.
  #    This matches iCal semantics where DTEND − DTSTART defines
  #    the event span and every occurrence carries it forward.
  #
  # 2. `metadata.occurrence_duration` — an explicit Duration for
  #    each occurrence's span. Used when a caller knows the span
  #    as a Duration (hand-built AST, adapter layers).
  #
  # 3. The AST's `duration` — when no override is supplied, each
  #    occurrence spans one cadence.
  defp occurrence_end_fn(
         %Tempo{} = _from,
         %Tempo.Duration{} = cadence,
         %Tempo.Interval{metadata: metadata, duration: duration}
       ) do
    cond do
      match?(%{occurrence_base_to: %Tempo{}}, metadata) ->
        base_to = metadata.occurrence_base_to
        fn _start, i -> add_n_durations(base_to, cadence, i) end

      match?(%{occurrence_duration: %Tempo.Duration{}}, metadata) ->
        span = metadata.occurrence_duration
        fn start, _i -> Tempo.Math.add(start, span) end

      true ->
        fn start, _i -> Tempo.Math.add(start, duration) end
    end
  end

  # Termination predicates for the recurrence loop.
  defp under_until?(%Tempo{} = from, %Tempo{} = until) do
    Tempo.Compare.compare_endpoints(from, until) in [:earlier, :same]
  end

  defp under_bound?(%Tempo{} = from, %Tempo{} = bound_to) do
    Tempo.Compare.compare_endpoints(from, bound_to) == :earlier
  end

  # Compute the upper endpoint of a `:bound` option. Accepts any
  # Tempo value that `to_interval_set/1` handles; uses the
  # highest `:to` across the set's intervals as the termination
  # boundary.
  defp bound_upper(bound) do
    case to_interval_set(bound) do
      {:ok, %Tempo.IntervalSet{intervals: intervals}} when intervals != [] ->
        upper =
          intervals
          |> Enum.map(& &1.to)
          |> Enum.reduce(fn a, b ->
            if Tempo.Compare.compare_endpoints(a, b) == :later, do: a, else: b
          end)

        {:ok, upper}

      {:ok, _} ->
        {:error, "Empty `:bound` — nothing to terminate the recurrence against."}

      {:error, _} = err ->
        err
    end
  end

  # A "non-contiguous mask" is a mask at some unit followed by
  # one or more concrete units: `1985-XX-15` (month masked, day
  # concrete) produces 12 disjoint day-intervals, not a single
  # year-wide span. When detected, rewrite the mask position to
  # the list of valid candidate values (calendar-aware) so the
  # existing multi-expansion path handles it.
  #
  # A mask with only masks after it (`1985-XX-XX`) is still
  # "contiguous widening" — no concrete unit pins a sub-span, so
  # the enclosing year interval is the right representation.
  defp expand_non_contiguous_mask(%Tempo{time: time, calendar: calendar} = tempo) do
    case find_non_contiguous_mask(time, [], calendar) do
      nil ->
        tempo

      {new_time} ->
        %{tempo | time: new_time}
    end
  end

  defp find_non_contiguous_mask([], _previous, _calendar), do: nil

  defp find_non_contiguous_mask([{unit, {:mask, mask}} | rest], previous, calendar) do
    if tail_has_concrete?(rest) do
      # Non-contiguous: substitute the mask with candidate values.
      # Use a scalar when exactly one candidate survives the
      # calendar constraint; otherwise a list (which the multi
      # path expands via Enumerable).
      candidates = Tempo.Mask.valid_values(unit, mask, Enum.reverse(previous), calendar)
      prefix = Enum.reverse(previous)

      value =
        case candidates do
          [single] -> single
          many -> many
        end

      {prefix ++ [{unit, value}] ++ rest}
    else
      nil
    end
  end

  defp find_non_contiguous_mask([entry | rest], previous, calendar) do
    find_non_contiguous_mask(rest, [entry | previous], calendar)
  end

  defp tail_has_concrete?([]), do: false
  defp tail_has_concrete?([{_unit, {:mask, _}} | rest]), do: tail_has_concrete?(rest)
  defp tail_has_concrete?([{_unit, :any} | rest]), do: tail_has_concrete?(rest)

  defp tail_has_concrete?([{_unit, value} | _rest]) when is_integer(value) do
    true
  end

  defp tail_has_concrete?([_ | rest]), do: tail_has_concrete?(rest)

  # A Tempo is "multi" if any of its time slots holds a list of
  # more than one candidate value. The existing Enumerable
  # protocol handles the expansion — we just detect the trigger
  # here and let Enumerable do the walk.
  defp multi_tempo?(%Tempo{time: time}) do
    Enum.any?(time, &multi_slot?/1)
  end

  defp multi_slot?({_unit, value}) when is_integer(value), do: false
  defp multi_slot?({_unit, {:mask, _}}), do: false
  defp multi_slot?({_unit, :any}), do: false
  defp multi_slot?({_unit, {_value, meta}}) when is_list(meta), do: false

  defp multi_slot?({_unit, values}) when is_list(values) do
    case values do
      [] -> false
      [%Range{first: f, last: l, step: s}] -> Enum.count(f..l//s) > 1
      [_single] -> false
      _ -> true
    end
  end

  defp multi_slot?(_), do: false

  defp materialise_multi(%Tempo{} = tempo) do
    # The existing Enumerable.Tempo yields one concrete Tempo per
    # cartesian-product combination. Each of those is a single
    # Tempo we can pass through the single-interval path. Collect
    # the intervals, then build a coalesced IntervalSet.
    intervals =
      tempo
      |> Enum.to_list()
      |> Enum.map(&to_interval/1)

    case Enum.find(intervals, &match?({:error, _}, &1)) do
      nil ->
        intervals
        |> Enum.map(fn {:ok, i} -> i end)
        |> Tempo.IntervalSet.new()

      {:error, _} = err ->
        err
    end
  end

  defp members_to_interval_set(members) do
    intervals =
      Enum.reduce_while(members, {:ok, []}, fn member, {:ok, acc} ->
        case to_interval(member) do
          {:ok, %Tempo.Interval{} = i} ->
            {:cont, {:ok, [i | acc]}}

          {:ok, %Tempo.IntervalSet{intervals: inner}} ->
            {:cont, {:ok, Enum.reverse(inner) ++ acc}}

          {:error, _} = err ->
            {:halt, err}
        end
      end)

    case intervals do
      {:ok, reversed} ->
        reversed |> Enum.reverse() |> Tempo.IntervalSet.new()

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Convert any Tempo value to a `t:Tempo.IntervalSet.t/0`.

  Unlike `to_interval/1` (which may return either a single
  interval or an IntervalSet), `to_interval_set/1` always returns
  an IntervalSet — wrapping a single interval in a one-element
  set if needed. This is the convenient form when the caller
  wants a uniform shape (e.g. to pipe into set operations).

  ### Arguments

  * `value` is a `t:#{__MODULE__}.t/0`, `t:Tempo.Interval.t/0`,
    `t:Tempo.IntervalSet.t/0`, or `t:Tempo.Set.t/0`.

  ### Returns

  * `{:ok, interval_set}` on success, or `{:error, reason}` for
    the same cases that `to_interval/1` errors on.

  ### Examples

      iex> {:ok, tempo} = Tempo.from_iso8601("2026-01")
      iex> {:ok, set} = Tempo.to_interval_set(tempo)
      iex> length(set.intervals)
      1

  """
  @spec to_interval_set(
          Tempo.t()
          | Tempo.Interval.t()
          | Tempo.IntervalSet.t()
          | Tempo.Set.t()
          | Tempo.Duration.t()
        ) ::
          {:ok, Tempo.IntervalSet.t()} | {:error, error_reason()}
  def to_interval_set(value) do
    case to_interval(value) do
      {:ok, %Tempo.IntervalSet{} = set} -> {:ok, set}
      {:ok, %Tempo.Interval{} = interval} -> Tempo.IntervalSet.new([interval])
      {:error, _} = err -> err
    end
  end

  @doc """
  Raising version of `to_interval/1`.

  ### Arguments

  * `value` is a `t:#{__MODULE__}.t/0`, `t:Tempo.Interval.t/0`,
    `t:Tempo.IntervalSet.t/0`, or `t:Tempo.Set.t/0`.

  ### Returns

  * The materialised `t:Tempo.Interval.t/0` or
    `t:Tempo.IntervalSet.t/0`.

  ### Raises

  * `ArgumentError` when the input cannot be materialised. See
    `to_interval/1` for the error cases.

  ### Examples

      iex> {:ok, tempo} = Tempo.from_iso8601("2026")
      iex> interval = Tempo.to_interval!(tempo)
      iex> {interval.from.time, interval.to.time}
      {[year: 2026, month: 1], [year: 2027, month: 1]}

  """
  @spec to_interval!(
          Tempo.t()
          | Tempo.Interval.t()
          | Tempo.IntervalSet.t()
          | Tempo.Set.t()
          | Tempo.Duration.t()
        ) ::
          Tempo.Interval.t() | Tempo.IntervalSet.t()
  def to_interval!(value) do
    case to_interval(value) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Union of two Tempo values — every instant in either operand.
  See `Tempo.Operations.union/3` for full details.
  """
  defdelegate union(a, b, opts \\ []), to: Tempo.Operations

  @doc """
  Intersection of two Tempo values — every instant in both
  operands. See `Tempo.Operations.intersection/3`.
  """
  defdelegate intersection(a, b, opts \\ []), to: Tempo.Operations

  @doc """
  Complement of a Tempo value within a bounding universe. The
  `:bound` option is required. See `Tempo.Operations.complement/2`.
  """
  defdelegate complement(set, opts), to: Tempo.Operations

  @doc """
  Difference `a \\ b` — every instant in `a` that is not in
  `b`. See `Tempo.Operations.difference/3`.
  """
  defdelegate difference(a, b, opts \\ []), to: Tempo.Operations

  @doc """
  Symmetric difference `a △ b` — instants in exactly one of
  the two operands. See `Tempo.Operations.symmetric_difference/3`.
  """
  defdelegate symmetric_difference(a, b, opts \\ []), to: Tempo.Operations

  @doc """
  `true` when `a` and `b` share no instants.
  See `Tempo.Operations.disjoint?/3`.
  """
  defdelegate disjoint?(a, b, opts \\ []), to: Tempo.Operations

  @doc """
  `true` when `a` and `b` share at least one instant.
  See `Tempo.Operations.overlaps?/3`.
  """
  defdelegate overlaps?(a, b, opts \\ []), to: Tempo.Operations

  @doc """
  `true` when every instant of `a` is also in `b`.
  See `Tempo.Operations.subset?/3`.
  """
  defdelegate subset?(a, b, opts \\ []), to: Tempo.Operations

  @doc """
  `true` when every instant of `b` is also in `a`. Alias for
  `subset?(b, a, opts)`. See `Tempo.Operations.contains?/3`.
  """
  defdelegate contains?(a, b, opts \\ []), to: Tempo.Operations

  @doc """
  `true` when `a` and `b` span the same instants (at their
  aligned resolution). See `Tempo.Operations.equal?/3`.
  """
  defdelegate equal?(a, b, opts \\ []), to: Tempo.Operations

  @doc """
  Classify the Allen interval-algebra relation between two
  interval-like values.

  Thin delegate to `Tempo.Interval.compare/2` — see that
  function's docs for the full table of 13 relations.

  Use `Tempo.IntervalSet.relation_matrix/2` when both operands
  are multi-member sets and you want the per-pair breakdown.

  ### Examples

      iex> Tempo.compare(~o"2026-06-15", ~o"2026-06-16")
      :meets

      iex> a = %Tempo.Interval{from: ~o"2026-06-01", to: ~o"2026-06-10"}
      iex> b = %Tempo.Interval{from: ~o"2026-06-05", to: ~o"2026-06-15"}
      iex> Tempo.compare(a, b)
      :overlaps

  """
  defdelegate compare(a, b), to: Tempo.Interval

  @doc """
  Return the interval's length as a `%Tempo.Duration{}`, or
  `:infinity` for unbounded intervals. See `Tempo.Interval.duration/1`.
  """
  defdelegate duration(interval), to: Tempo.Interval

  @doc """
  `true` when the interval is at least as long as the given
  duration. See `Tempo.Interval.at_least?/2`.
  """
  defdelegate at_least?(interval, duration), to: Tempo.Interval

  @doc """
  `true` when the interval is at most as long as the given
  duration. See `Tempo.Interval.at_most?/2`.
  """
  defdelegate at_most?(interval, duration), to: Tempo.Interval

  @doc """
  `true` when the interval's length equals the given duration.
  See `Tempo.Interval.exactly?/2`.
  """
  defdelegate exactly?(interval, duration), to: Tempo.Interval

  @doc """
  `true` when the interval is strictly longer than the given
  duration. See `Tempo.Interval.longer_than?/2`.
  """
  defdelegate longer_than?(interval, duration), to: Tempo.Interval

  @doc """
  `true` when the interval is strictly shorter than the given
  duration. See `Tempo.Interval.shorter_than?/2`.
  """
  defdelegate shorter_than?(interval, duration), to: Tempo.Interval

  @doc """
  `true` when both endpoints of the interval are concrete
  (neither `:undefined` nor `nil`). See `Tempo.Interval.bounded?/1`.
  """
  defdelegate bounded?(interval), to: Tempo.Interval

  @doc """
  `true` when the interval has zero length. See
  `Tempo.Interval.empty?/1`.
  """
  defdelegate empty?(interval), to: Tempo.Interval

  @doc """
  `true` when `a` ends strictly before `b` starts (Allen's
  `:precedes`). See `Tempo.Interval.before?/2`.
  """
  defdelegate before?(a, b), to: Tempo.Interval

  @doc """
  `true` when `a` starts strictly after `b` ends (Allen's
  `:preceded_by`). See `Tempo.Interval.after?/2`.
  """
  defdelegate after?(a, b), to: Tempo.Interval

  @doc """
  `true` when `a`'s end coincides exactly with `b`'s start
  (Allen's `:meets`). See `Tempo.Interval.meets?/2`.
  """
  defdelegate meets?(a, b), to: Tempo.Interval

  @doc """
  `true` when the two intervals touch at a single boundary
  (Allen's `:meets | :met_by`). See `Tempo.Interval.adjacent?/2`.
  """
  defdelegate adjacent?(a, b), to: Tempo.Interval

  @doc """
  `true` when `a` is strictly inside `b` (Allen's `:during`).
  See `Tempo.Interval.during?/2`.
  """
  defdelegate during?(a, b), to: Tempo.Interval

  @doc """
  `true` when `a` fits inside `b` inclusive of shared
  endpoints. The canonical "does this fit inside that window?"
  predicate. See `Tempo.Interval.within?/2`.
  """
  defdelegate within?(a, b), to: Tempo.Interval

  @doc """
  Narrow a Tempo span by a selector — the composition primitive
  for "workdays of June", "the 15th of every month", and similar
  queries. See `Tempo.Select` for the full vocabulary.

  **Locale-dependent selectors (`:workdays`, `:weekend`) resolve at
  call time.** Do not capture such calls in module attributes or
  at compile time — see `Tempo.Select` for the rationale.

  ### Examples

      iex> {:ok, set} = Tempo.select(~o"2026-02", [1, 15])
      iex> set |> Tempo.IntervalSet.to_list() |> Enum.map(& &1.from.time[:day])
      [1, 15]

      iex> {:ok, set} = Tempo.select(~o"2026", ~o"12-25")
      iex> [xmas] = Tempo.IntervalSet.to_list(set)
      iex> {xmas.from.time[:year], xmas.from.time[:month], xmas.from.time[:day]}
      {2026, 12, 25}

  """
  defdelegate select(base, selector, opts \\ []), to: Tempo.Select

  @doc """
  Return a multi-line prose explanation of any Tempo value —
  what it is, what it spans, and how to work with it.

  Returns a plain string suitable for iex. For structured output
  that renderers can style (ANSI, HTML, visualizer components),
  use `Tempo.Explain.explain/1` directly and pick a formatter.
  """
  @spec explain(term()) :: String.t()
  def explain(value) do
    value |> Tempo.Explain.explain() |> Tempo.Explain.to_string()
  end

  @doc """
  Print a guided tour of Tempo's distinctive capabilities to the
  iex console.

  Eight short examples run live against the current build —
  implicit spans, enumeration, archaeological dates, set
  operations, cross-calendar comparison, locale-aware selectors,
  leap seconds, and femtosecond precision. Useful as a first
  contact with the library, a conference demo, or a sanity check
  after a version bump.

  Call `Tempo.tour()` at an iex prompt to see the tour's eight
  steps printed to stdout. Returns `:ok` so the prompt shows
  cleanly after the output.

  The tour is tested via `ExUnit.CaptureIO` in
  `test/tempo/tour_test.exs`; no doctest is included here because
  the tour's raison d'être is the printed output, which would
  otherwise flood every test-suite run.

  """
  @spec tour() :: :ok
  defdelegate tour(), to: Tempo.Tour, as: :run

  @valid_units Unit.units()

  @doc false
  def validate_unit(unit) when unit in @valid_units do
    {:ok, unit}
  end

  def validate_unit(unit) do
    {:error, "Invalid time unit #{inspect(unit)}"}
  end
end
