defmodule Tempo.Network.Solver do
  @moduledoc """
  Consistency checking and bound tightening for a chronological
  network, by solving its Simple Temporal Problem.

  The network normalises (`Tempo.Network.Normalize`) to a directed
  weighted graph — one node per boundary plus the origin `z₀` — whose
  all-pairs shortest paths are the **minimal network**: the tightest
  bound on `b₁ − b₂` is the shortest-path weight `b₁ → b₂` (Dechter,
  Meiri & Pearl 1991; the paper's Floyd 1962). The network is
  **consistent** iff the graph has no negative cycle.

  * `consistent?/1` — does any valid assignment of dates exist?

  * `tighten/1` — the narrowest start, end, and duration each period can
    take given every constraint together.

  Both run in O(n³) on the boundary count (Floyd–Warshall), which is
  interactive for the hundreds of periods these chronologies contain.

  """

  alias Tempo.Network
  alias Tempo.Network.Normalize

  @doc """
  Is the network consistent — does it admit at least one valid
  assignment of dates?

  ### Arguments

  * `network` is a `t:Tempo.Network.t/0`.

  ### Returns

  * `true` when consistent, `false` when the constraints contradict
    (the graph has a negative cycle).

  ### Examples

      iex> Tempo.Network.new()
      ...> |> Tempo.Network.add_period(:k, start: 1200, end: 1180)
      ...> |> Tempo.Network.Solver.consistent?()
      false

  """
  @spec consistent?(Network.t()) :: boolean()
  def consistent?(%Network{} = network) do
    distances = network |> Normalize.normalize() |> shortest_paths()
    not negative_cycle?(distances)
  end

  @doc """
  Tighten every period's start, end, and duration to the narrowest
  bounds the network implies.

  ### Arguments

  * `network` is a `t:Tempo.Network.t/0`.

  ### Returns

  * `{:ok, network}` with each period's bounds replaced by the computed
    tightest bounds (a bound that the constraints leave unbounded
    becomes `nil`); or

  * `{:error, :inconsistent}` when no valid assignment exists.

  ### Examples

      iex> {:ok, tightened} =
      ...>   Tempo.Network.new()
      ...>   |> Tempo.Network.add_period(:k1, start: 1200, duration: {:at_least, 20})
      ...>   |> Tempo.Network.add_period(:k2, duration: {:at_least, 35})
      ...>   |> Tempo.Network.add_sequence([:k1, :k2])
      ...>   |> Tempo.Network.Solver.tighten()
      iex> Tempo.Network.TimePeriod.year(tightened.periods[:k2].earliest_end)
      1255

  """
  @spec tighten(Network.t()) :: {:ok, Network.t()} | {:error, :inconsistent}
  def tighten(%Network{} = network) do
    normalized = Normalize.normalize(network)
    distances = shortest_paths(normalized)

    if negative_cycle?(distances) do
      {:error, :inconsistent}
    else
      periods =
        Map.new(network.periods, fn {id, period} ->
          {id, tighten_period(id, period, distances, normalized.unit)}
        end)

      {:ok, %{network | periods: periods}}
    end
  end

  # --- bound extraction ------------------------------------------

  defp tighten_period(id, period, distances, unit) do
    start = {:start, id}
    finish = {:end, id}

    %{
      period
      | earliest_start: lower(distances, start, unit),
        latest_start: upper(distances, start, unit),
        earliest_end: lower(distances, finish, unit),
        latest_end: upper(distances, finish, unit),
        min_duration: min_span(distances, start, finish, unit),
        max_duration: max_span(distances, start, finish, unit)
    }
  end

  # node ≤ origin + dist(node, origin)  → latest value of node.
  defp upper(distances, node, unit) do
    case get(distances, node, :origin) do
      :inf -> nil
      weight -> axis_to_date(weight, unit)
    end
  end

  # origin − node ≤ dist(origin, node)  → node ≥ −dist(origin, node).
  defp lower(distances, node, unit) do
    case get(distances, :origin, node) do
      :inf -> nil
      weight -> axis_to_date(-weight, unit)
    end
  end

  # end − start ≤ dist(end, start) → max duration.
  defp max_span(distances, start, finish, unit) do
    case get(distances, finish, start) do
      :inf -> nil
      weight -> axis_to_duration(weight, unit)
    end
  end

  # start − end ≤ dist(start, end) → end − start ≥ −dist(start, end).
  defp min_span(distances, start, finish, unit) do
    case get(distances, start, finish) do
      :inf -> nil
      weight when -weight <= 0 -> nil
      weight -> axis_to_duration(-weight, unit)
    end
  end

  # --- Floyd–Warshall --------------------------------------------

  defp shortest_paths(%{nodes: nodes, edges: edges}) do
    initial =
      for from <- nodes, to <- nodes, into: %{} do
        {{from, to}, if(from == to, do: 0, else: :inf)}
      end

    seeded =
      Enum.reduce(edges, initial, fn {from, to, weight}, acc ->
        Map.update!(acc, {from, to}, &min_weight(&1, weight))
      end)

    Enum.reduce(nodes, seeded, fn k, dk ->
      Enum.reduce(nodes, dk, fn i, di ->
        Enum.reduce(nodes, di, fn j, distances ->
          via = add_weight(distances[{i, k}], distances[{k, j}])

          if less?(via, distances[{i, j}]) do
            %{distances | {i, j} => via}
          else
            distances
          end
        end)
      end)
    end)
  end

  defp negative_cycle?(distances) do
    Enum.any?(distances, fn
      {{node, node}, weight} -> weight != :inf and weight < 0
      _other -> false
    end)
  end

  defp get(distances, from, to), do: Map.get(distances, {from, to}, :inf)

  defp min_weight(:inf, weight), do: weight
  defp min_weight(weight, :inf), do: weight
  defp min_weight(a, b), do: min(a, b)

  defp add_weight(:inf, _), do: :inf
  defp add_weight(_, :inf), do: :inf
  defp add_weight(a, b), do: a + b

  defp less?(_a, :inf), do: true
  defp less?(:inf, _b), do: false
  defp less?(a, b), do: a < b

  # --- axis → Tempo ----------------------------------------------

  defp axis_to_date(value, :year), do: Tempo.from_iso8601!("#{value}Y")

  defp axis_to_date(value, :month) do
    year = Integer.floor_div(value, 12)
    month = Integer.mod(value, 12) + 1
    Tempo.from_iso8601!("#{year}-#{pad(month)}")
  end

  defp axis_to_date(value, :day) do
    value |> Date.from_gregorian_days() |> Tempo.from_elixir()
  end

  defp axis_to_duration(value, :year), do: Tempo.from_iso8601!("P#{value}Y")
  defp axis_to_duration(value, :month), do: Tempo.from_iso8601!("P#{value}M")
  defp axis_to_duration(value, :day), do: Tempo.from_iso8601!("P#{value}D")

  defp pad(month) when month < 10, do: "0#{month}"
  defp pad(month), do: "#{month}"
end
