defmodule Tempo.Network.Normalize do
  @moduledoc """
  Reduce a `t:Tempo.Network.t/0` to a Simple Temporal Problem: a
  set of boundary nodes and integer-weighted constraints of the single
  shape `b₁ − b₂ ≤ k`.

  Every period contributes a `start` and an `end` boundary; a single
  shared origin `z₀` (`:origin`) anchors absolute dates. The network's
  **finest unit** (the finest resolution among its dates) fixes the
  integer axis: a date becomes its count of that unit relative to `z₀`,
  a duration its count of that unit.

  The output feeds `Tempo.Network.Solver`. Conversion is exact when the
  network is uniform-unit (as the canonical year-grained chronologies
  are); a duration expressed across units (e.g. years on a day axis)
  uses nominal calendar lengths and is rounded.

  """

  alias Tempo.Network
  alias Tempo.Network.Relation

  # Coarsest → finest. The finest unit *present* fixes the axis.
  @unit_order [:year, :month, :week, :day, :hour, :minute, :second]

  @days_per_year 365.2425
  @days_per_month 30.436875

  @type boundary :: Relation.boundary()
  @type edge :: {boundary(), boundary(), integer()}
  @type t :: %{nodes: [boundary()], edges: [edge()], unit: atom()}

  @doc """
  Normalise a network into `%{nodes, edges, unit}`.

  ### Arguments

  * `network` is a `t:Tempo.Network.t/0`.

  ### Returns

  * a map with `:nodes` (boundary variables including `:origin`),
    `:edges` (integer `{from, to, weight}` constraints meaning
    `from − to ≤ weight`), and `:unit` (the axis unit atom).

  ### Examples

      iex> network =
      ...>   Tempo.Network.new()
      ...>   |> Tempo.Network.add_period(:k1, start: 1200, duration: {:at_least, 20})
      iex> normalized = Tempo.Network.Normalize.normalize(network)
      iex> normalized.unit
      :year
      iex> {{:start, :k1}, {:end, :k1}, -20} in normalized.edges
      true

  """
  @spec normalize(Network.t()) :: t()
  def normalize(%Network{} = network) do
    unit = finest_unit(network)

    period_edges =
      Enum.flat_map(network.periods, fn {id, period} ->
        period_constraints(id, period, unit)
      end)

    sequence_edges = Enum.flat_map(network.sequences, &sequence_constraints/1)

    relation_edges =
      network.relations
      |> Enum.flat_map(&Relation.to_atomic/1)
      |> Enum.map(&resolve_weight(&1, unit))

    edges = period_edges ++ sequence_edges ++ relation_edges
    nodes = edges |> Enum.flat_map(fn {from, to, _} -> [from, to] end) |> Enum.uniq()

    %{nodes: nodes, edges: edges, unit: unit}
  end

  @doc """
  The finest date resolution present in the network's period bounds.

  Defaults to `:year` when the network carries no dated bounds.

  ### Examples

      iex> Tempo.Network.new()
      ...> |> Tempo.Network.add_period(:a, start: "1200-06-15")
      ...> |> Tempo.Network.Normalize.finest_unit()
      :day

  """
  @spec finest_unit(Network.t()) :: atom()
  def finest_unit(%Network{} = network) do
    network.periods
    |> Map.values()
    |> Enum.flat_map(&date_bounds/1)
    |> Enum.map(&unit_of/1)
    |> Enum.max_by(&unit_rank/1, fn -> :year end)
  end

  # --- period → constraints --------------------------------------

  defp period_constraints(id, period, unit) do
    start = {:start, id}
    finish = {:end, id}

    [
      # A period never ends before it starts.
      {start, finish, 0}
    ]
    |> lower_bound(:origin, start, period.earliest_start, unit)
    |> upper_bound(start, :origin, period.latest_start, unit)
    |> lower_bound(:origin, finish, period.earliest_end, unit)
    |> upper_bound(finish, :origin, period.latest_end, unit)
    |> min_duration(start, finish, period.min_duration, unit)
    |> max_duration(start, finish, period.max_duration, unit)
  end

  # value(node) ≥ bound  ⇒  origin − node ≤ −bound.
  defp lower_bound(edges, origin, node, %Tempo{} = value, unit) do
    [{origin, node, -date_axis(value, unit)} | edges]
  end

  defp lower_bound(edges, _origin, _node, nil, _unit), do: edges

  # value(node) ≤ bound  ⇒  node − origin ≤ bound.
  defp upper_bound(edges, node, origin, %Tempo{} = value, unit) do
    [{node, origin, date_axis(value, unit)} | edges]
  end

  defp upper_bound(edges, _node, _origin, nil, _unit), do: edges

  # end − start ≥ min  ⇒  start − end ≤ −min.
  defp min_duration(edges, start, finish, %Tempo.Duration{} = duration, unit) do
    [{start, finish, -duration_axis(duration, unit)} | edges]
  end

  defp min_duration(edges, _start, _finish, nil, _unit), do: edges

  # end − start ≤ max  ⇒  end − start ≤ max.
  defp max_duration(edges, start, finish, %Tempo.Duration{} = duration, unit) do
    [{finish, start, duration_axis(duration, unit)} | edges]
  end

  defp max_duration(edges, _start, _finish, nil, _unit), do: edges

  # --- sequence → immediately-precedes links ---------------------

  defp sequence_constraints(period_ids) do
    period_ids
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(fn [a, b] ->
      # end(a) = start(b).
      [{{:end, a}, {:start, b}, 0}, {{:start, b}, {:end, a}, 0}]
    end)
  end

  # --- relation duration weights → integers ----------------------

  defp resolve_weight({from, to, {:duration, duration}}, unit) do
    {from, to, duration_axis(duration, unit)}
  end

  defp resolve_weight({from, to, {:neg_duration, duration}}, unit) do
    {from, to, -duration_axis(duration, unit)}
  end

  defp resolve_weight({from, to, weight}, _unit) when is_integer(weight) do
    {from, to, weight}
  end

  # --- unit machinery --------------------------------------------

  defp date_bounds(period) do
    [
      period.earliest_start,
      period.latest_start,
      period.earliest_end,
      period.latest_end
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp unit_of(%Tempo{} = value) do
    {unit, _factor} = Tempo.resolution(value)
    unit
  end

  defp unit_rank(unit), do: Enum.find_index(@unit_order, &(&1 == unit)) || 0

  # Convert a date to an integer count of `unit` relative to year 0.
  defp date_axis(%Tempo{time: time}, :year), do: Keyword.fetch!(time, :year)

  defp date_axis(%Tempo{time: time}, :month) do
    Keyword.fetch!(time, :year) * 12 + (Keyword.get(time, :month, 1) - 1)
  end

  defp date_axis(%Tempo{time: time}, :day) do
    year = Keyword.fetch!(time, :year)
    month = Keyword.get(time, :month, 1)
    day = Keyword.get(time, :day, 1)
    {:ok, date} = Date.new(year, month, day)
    Date.to_gregorian_days(date)
  end

  # Convert a duration to an integer count of `unit`. Exact for a
  # duration already expressed in `unit`; otherwise via nominal lengths.
  defp duration_axis(%Tempo.Duration{time: time}, :year),
    do: round(duration_days(time) / @days_per_year)

  defp duration_axis(%Tempo.Duration{time: time}, :month),
    do: round(duration_days(time) / @days_per_month)

  defp duration_axis(%Tempo.Duration{time: time}, :day), do: round(duration_days(time))

  defp duration_days(time) do
    Enum.reduce(time, 0.0, fn
      {:year, years}, acc -> acc + years * @days_per_year
      {:month, months}, acc -> acc + months * @days_per_month
      {:week, weeks}, acc -> acc + weeks * 7
      {:day, days}, acc -> acc + days
      _other, acc -> acc
    end)
  end
end
