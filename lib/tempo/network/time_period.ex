defmodule Tempo.Network.TimePeriod do
  @moduledoc """
  A single time-period in a chronological network — a reign, era, or
  the time-span of a stratum.

  Following the ChronoLog data model (Levy et al. 2020), a period
  carries **independent** bounds on three quantities, each of which may
  be unknown (`nil`), known, lower-bounded, upper-bounded, or known
  within a range:

  * its **start** — `earliest_start`..`latest_start`;

  * its **end** — `earliest_end`..`latest_end`;

  * its **duration** — `min_duration`..`max_duration`.

  Duration is modelled separately from the start/end pair (it is not
  forced to equal `end - start` at construction time); the solver
  reconciles all three through the constraint `end - start ∈
  [min_duration, max_duration]`.

  Start/end bounds are `t:Tempo.t/0` values (so they carry their own
  calendar and resolution); duration bounds are `t:Tempo.Duration.t/0`.
  An EDTF/ISO 8601 string or a bare integer year is accepted by the
  constructor and normalised to the corresponding Tempo value.

  """

  alias Tempo.Network.TimePeriod

  @typedoc "A start/end bound: a Tempo value, or `nil` when unknown."
  @type date_bound :: Tempo.t() | nil

  @typedoc "A duration bound: a Tempo duration, or `nil` when unknown."
  @type duration_bound :: Tempo.Duration.t() | nil

  @type t :: %__MODULE__{
          id: term(),
          name: String.t() | nil,
          earliest_start: date_bound(),
          latest_start: date_bound(),
          earliest_end: date_bound(),
          latest_end: date_bound(),
          min_duration: duration_bound(),
          max_duration: duration_bound(),
          metadata: map()
        }

  defstruct id: nil,
            name: nil,
            earliest_start: nil,
            latest_start: nil,
            earliest_end: nil,
            latest_end: nil,
            min_duration: nil,
            max_duration: nil,
            metadata: %{}

  @doc """
  Build a time-period.

  ### Arguments

  * `id` is any term uniquely identifying the period within its
    network (commonly an atom such as `:k1` or a string).

  ### Options

  * `:name` is a human-readable label.

  * `:start` constrains the start boundary. It accepts an exact value,
    a `{lower, upper}` range, `{:not_before, value}`, or
    `{:not_after, value}` (see "Bound specifications").

  * `:end` constrains the end boundary, with the same shapes as
    `:start`.

  * `:duration` constrains the duration. It accepts an exact duration,
    a `{min, max}` range, `{:at_least, duration}`, or
    `{:at_most, duration}`.

  * `:metadata` is an arbitrary map carried with the period (EDTF
    qualifiers, provenance, notes). It does not affect the solver.

  ### Bound specifications

  A date value is a `t:Tempo.t/0` — idiomatically a sigil literal such
  as `~o"1200Y"`, `~o"-664Y"`, or `~o"1200-06-15"`. As a year-grained
  convenience an EDTF/ISO 8601 string (`"1200Y"`) or a bare integer year
  (`1200`, `-664` for BCE) is also accepted and normalised to the
  corresponding Tempo value.

  A duration value is a `t:Tempo.Duration.t/0` (`~o"P20Y"`); an ISO 8601
  duration string (`"P20Y"`) or a bare integer number of years is
  likewise accepted.

  All bounds are stored, and returned, as Tempo values.

  ### Returns

  * a `t:Tempo.Network.TimePeriod.t/0`.

  ### Examples

      iex> period = Tempo.Network.TimePeriod.new(:k1, name: "King 1", start: {:not_before, ~o"1200Y"})
      iex> {period.id, period.name, period.earliest_start}
      {:k1, "King 1", ~o"1200Y"}

      iex> period = Tempo.Network.TimePeriod.new(:s1, duration: {:at_least, ~o"P20Y"})
      iex> period.min_duration
      ~o"P20Y"

  """
  @spec new(term(), keyword()) :: t()
  def new(id, options \\ []) do
    {start_lower, start_upper} = date_bounds(Keyword.get(options, :start))
    {end_lower, end_upper} = date_bounds(Keyword.get(options, :end))
    {min_duration, max_duration} = duration_bounds(Keyword.get(options, :duration))

    %TimePeriod{
      id: id,
      name: Keyword.get(options, :name),
      earliest_start: start_lower,
      latest_start: start_upper,
      earliest_end: end_lower,
      latest_end: end_upper,
      min_duration: min_duration,
      max_duration: max_duration,
      metadata: Keyword.get(options, :metadata, %{})
    }
  end

  @doc """
  The integer year of a date bound, or `nil`.

  A convenience for tests and traces; the solver works at the network's
  finest unit rather than always in years.

  ### Examples

      iex> Tempo.Network.TimePeriod.year(~o"1200Y")
      1200

      iex> Tempo.Network.TimePeriod.year(nil)
      nil

  """
  @spec year(date_bound()) :: integer() | nil
  def year(nil), do: nil
  def year(%Tempo{time: time}), do: Keyword.get(time, :year)

  # --- bound normalisation ---------------------------------------

  # No constraint supplied.
  defp date_bounds(nil), do: {nil, nil}

  defp date_bounds({:not_before, value}), do: {to_tempo(value), nil}
  defp date_bounds({:not_after, value}), do: {nil, to_tempo(value)}
  defp date_bounds({lower, upper}), do: {to_tempo(lower), to_tempo(upper)}
  defp date_bounds(exact), do: {to_tempo(exact), to_tempo(exact)}

  defp duration_bounds(nil), do: {nil, nil}
  defp duration_bounds({:at_least, value}), do: {to_duration(value), nil}
  defp duration_bounds({:at_most, value}), do: {nil, to_duration(value)}
  defp duration_bounds({min, max}), do: {to_duration(min), to_duration(max)}
  defp duration_bounds(exact), do: {to_duration(exact), to_duration(exact)}

  defp to_tempo(nil), do: nil
  defp to_tempo(%Tempo{} = value), do: value
  defp to_tempo(year) when is_integer(year), do: Tempo.from_iso8601!("#{year}Y")
  defp to_tempo(string) when is_binary(string), do: Tempo.from_iso8601!(string)

  defp to_duration(nil), do: nil
  defp to_duration(%Tempo.Duration{} = value), do: value
  defp to_duration(years) when is_integer(years), do: Tempo.from_iso8601!("P#{years}Y")
  defp to_duration(string) when is_binary(string), do: Tempo.from_iso8601!(string)
end
