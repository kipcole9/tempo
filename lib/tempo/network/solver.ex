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
      ...> |> Tempo.Network.add_period(:k, start: ~o"1200Y", end: ~o"1180Y")
      ...> |> Tempo.Network.Solver.consistent?()
      false

  """
  @spec consistent?(Network.t()) :: boolean()
  def consistent?(%Network{} = network) do
    %{dist: distances} = network |> Normalize.normalize() |> shortest_paths()
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
      ...>   |> Tempo.Network.add_period(:k1, start: ~o"1200Y", duration: {:at_least, ~o"P20Y"})
      ...>   |> Tempo.Network.add_period(:k2, duration: {:at_least, ~o"P35Y"})
      ...>   |> Tempo.Network.add_sequence([:k1, :k2])
      ...>   |> Tempo.Network.Solver.tighten()
      iex> tightened.periods[:k2].earliest_end
      ~o"1255Y"

  """
  @spec tighten(Network.t()) :: {:ok, Network.t()} | {:error, :inconsistent}
  def tighten(%Network{} = network) do
    normalized = Normalize.normalize(network)
    %{dist: distances} = shortest_paths(normalized)

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

  @doc """
  Classify whether two periods overlap in time, given the whole network.

  Returns `:certain` when the constraints force the periods to be
  contemporary, `:possible` when they merely allow it, and `:impossible`
  when they forbid it. The verdict is read from the minimal (tightened)
  network, so it accounts for every constraint — not just the two
  periods' own bounds — in the spirit of Geeraerts, Levy & Pluquet,
  *Models and Algorithms for Chronology* (TIME 2017), Props. 7 and 10.

  Two periods that merely touch (one ends exactly where the other
  begins) count as contemporary, matching `add_relation(:contemporary,
  …)` — the endpoints are treated as closed here.

  ### Arguments

  * `network` is a `t:Tempo.Network.t/0`.

  * `p1` and `p2` are ids of periods present in the network.

  ### Returns

  * `:certain` when every valid chronology has the periods overlapping;

  * `:possible` when some but not all valid chronologies do;

  * `:impossible` when none do; or

  * `{:error, :inconsistent}` when the network has no valid chronology.

  ### Examples

      iex> network =
      ...>   Tempo.Network.new()
      ...>   |> Tempo.Network.add_period(:k1, start: {:not_before, 1200}, duration: {:at_most, 15})
      ...>   |> Tempo.Network.add_period(:k2, end: {:not_after, 1300}, duration: {30, 100})
      ...>   |> Tempo.Network.add_period(:s1, duration: {20, 100})
      ...>   |> Tempo.Network.add_period(:s2, duration: {20, 100})
      ...>   |> Tempo.Network.add_sequence([:k1, :k2])
      ...>   |> Tempo.Network.add_sequence([:s1, :s2])
      ...>   |> Tempo.Network.add_relation(:starts_during, :s1, :k1)
      ...>   |> Tempo.Network.add_relation(:ends_during, :s2, :k2)
      iex> Tempo.Network.Solver.contemporaneity(network, :k1, :s2)
      :impossible

  """
  @spec contemporaneity(Network.t(), term(), term()) ::
          :certain | :possible | :impossible | {:error, :inconsistent}
  def contemporaneity(%Network{} = network, p1, p2) do
    %{dist: distances} = network |> Normalize.normalize() |> shortest_paths()

    cond do
      negative_cycle?(distances) -> {:error, :inconsistent}
      sure_overlap?(distances, p1, p2) -> :certain
      possible_overlap?(distances, p1, p2) -> :possible
      true -> :impossible
    end
  end

  @doc """
  Whether two periods are *certainly* contemporary — true only when
  every valid chronology has them overlapping. See `contemporaneity/3`.
  """
  @spec certainly_contemporary?(Network.t(), term(), term()) :: boolean()
  def certainly_contemporary?(%Network{} = network, p1, p2),
    do: contemporaneity(network, p1, p2) == :certain

  @doc """
  Whether two periods are *possibly* contemporary — true when at least
  one valid chronology has them overlapping. See `contemporaneity/3`.
  """
  @spec possibly_contemporary?(Network.t(), term(), term()) :: boolean()
  def possibly_contemporary?(%Network{} = network, p1, p2),
    do: contemporaneity(network, p1, p2) in [:certain, :possible]

  # Prop. 7 — overlap is entailed iff both synchronism inequalities
  # beg(p₁) ≤ end(p₂) and beg(p₂) ≤ end(p₁) are already implied, i.e. the
  # tightest bound on each difference (its shortest-path weight) is ≤ 0.
  defp sure_overlap?(distances, p1, p2) do
    at_most_zero?(get(distances, {:start, p1}, {:end, p2})) and
      at_most_zero?(get(distances, {:start, p2}, {:end, p1}))
  end

  # Prop. 10 — overlap is achievable iff adding both synchronism edges
  # keeps the network satisfiable: the tight bound on each reverse
  # difference end − beg must leave room to be non-negative.
  defp possible_overlap?(distances, p1, p2) do
    at_least_zero?(get(distances, {:end, p2}, {:start, p1})) and
      at_least_zero?(get(distances, {:end, p1}, {:start, p2}))
  end

  defp at_most_zero?(:inf), do: false
  defp at_most_zero?(weight), do: weight <= 0

  defp at_least_zero?(:inf), do: true
  defp at_least_zero?(weight), do: weight >= 0

  @doc """
  Explain a tightened bound as a trace — the chain of constraints that
  forces it.

  Reconstructs the shortest path in the constraint graph that produces
  the `:earliest` or `:latest` value of a boundary, mirroring the
  paper's Fig. 6c. Each step names the constraint responsible and the
  bound derived so far, and `:prose` renders the whole chain as a
  sentence.

  ### Arguments

  * `network` is a `t:Tempo.Network.t/0`.

  * `boundary` is `{:start, period_id}` or `{:end, period_id}`.

  ### Options

  * `:bound` is `:earliest` (the default) or `:latest`.

  ### Returns

  * `{:ok, %{value: t:Tempo.t/0, steps: list, prose: String.t()}}`;

  * `{:error, :unbounded}` when the constraints leave the bound open;
    or

  * `{:error, :inconsistent}` when the network has no valid assignment.

  ### Examples

      iex> {:ok, trace} =
      ...>   Tempo.Network.new()
      ...>   |> Tempo.Network.add_period(:k1, start: {:not_before, ~o"1200Y"}, duration: {:at_least, ~o"P20Y"})
      ...>   |> Tempo.Network.add_period(:k2, duration: {:at_least, ~o"P35Y"})
      ...>   |> Tempo.Network.add_sequence([:k1, :k2])
      ...>   |> Tempo.Network.Solver.trace({:end, :k2})
      iex> trace.value
      ~o"1255Y"

  """
  @spec trace(Network.t(), {:start | :end, term()}, keyword()) ::
          {:ok, map()} | {:error, :unbounded | :inconsistent}
  def trace(%Network{} = network, {edge, _id} = boundary, options \\ [])
      when edge in [:start, :end] do
    bound = Keyword.get(options, :bound, :earliest)
    normalized = Normalize.normalize(network)
    %{dist: distances, next: next} = shortest_paths(normalized)

    if negative_cycle?(distances) do
      {:error, :inconsistent}
    else
      {from_node, to_node} =
        case bound do
          :earliest -> {:origin, boundary}
          :latest -> {boundary, :origin}
        end

      case get(distances, from_node, to_node) do
        :inf ->
          {:error, :unbounded}

        _weight ->
          path = reconstruct(next, from_node, to_node)
          provenance = build_provenance(normalized.edges)
          steps = build_steps(path, distances, provenance, bound, normalized.unit)

          {:ok,
           %{
             boundary: boundary,
             bound: bound,
             value: bound_value(distances, boundary, bound, normalized.unit),
             steps: steps,
             prose: render_prose(steps, boundary, bound, network)
           }}
      end
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

  # Floyd–Warshall returning both the all-pairs distances and a
  # next-hop map for path reconstruction (`next[{i, j}]` is the first
  # node after `i` on a shortest path to `j`).
  defp shortest_paths(%{nodes: nodes, edges: edges}) do
    distances =
      for from <- nodes, to <- nodes, into: %{} do
        {{from, to}, if(from == to, do: 0, else: :inf)}
      end

    seeded =
      Enum.reduce(edges, {distances, %{}}, fn {from, to, weight, _source}, {dist, next} ->
        if less?(weight, dist[{from, to}]) do
          {%{dist | {from, to} => weight}, Map.put(next, {from, to}, to)}
        else
          {dist, next}
        end
      end)

    {dist, next} =
      for k <- nodes, i <- nodes, j <- nodes, reduce: seeded do
        {dist, next} ->
          via = add_weight(dist[{i, k}], dist[{k, j}])

          if less?(via, dist[{i, j}]) do
            {%{dist | {i, j} => via}, Map.put(next, {i, j}, next[{i, k}])}
          else
            {dist, next}
          end
      end

    %{dist: dist, next: next}
  end

  defp negative_cycle?(distances) do
    Enum.any?(distances, fn
      {{node, node}, weight} -> weight != :inf and weight < 0
      _other -> false
    end)
  end

  defp get(distances, from, to), do: Map.get(distances, {from, to}, :inf)

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

  # --- trace reconstruction --------------------------------------

  defp reconstruct(_next, node, node), do: [node]

  defp reconstruct(next, from, to) do
    case Map.get(next, {from, to}) do
      nil -> [from]
      hop -> [from | reconstruct(next, hop, to)]
    end
  end

  # The source of the minimal-weight direct edge for each {from, to}.
  defp build_provenance(edges) do
    Enum.reduce(edges, %{}, fn {from, to, weight, source}, acc ->
      case acc[{from, to}] do
        {best, _} when best <= weight -> acc
        _ -> Map.put(acc, {from, to}, {weight, source})
      end
    end)
  end

  # Each path hop becomes a step naming the constraint that justifies it
  # and the bound derived at the reached boundary. The origin carries no
  # bound of its own, so it never appears as a step.
  defp build_steps(path, distances, provenance, bound, unit) do
    path
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reject(fn [_prev, node] -> node == :origin end)
    |> Enum.map(fn [prev, node] ->
      {_weight, source} = Map.fetch!(provenance, {prev, node})
      %{boundary: node, value: bound_value(distances, node, bound, unit), source: source}
    end)
  end

  defp bound_value(distances, boundary, :earliest, unit) do
    axis_to_date(-get(distances, :origin, boundary), unit)
  end

  defp bound_value(distances, boundary, :latest, unit) do
    axis_to_date(get(distances, boundary, :origin), unit)
  end

  # --- trace prose -----------------------------------------------

  defp render_prose(steps, _boundary, bound, network) do
    Enum.map_join(steps, "; ", fn step ->
      "#{render_source(step.source, network)} ⇒ " <>
        "#{boundary_phrase(step.boundary, network)} #{comparison(bound)} #{year_label(step.value)}"
    end)
  end

  defp render_source({:bound, :start, :lower, id, value}, network),
    do: "#{label(network, id)} starts no earlier than #{year_label(value)}"

  defp render_source({:bound, :start, :upper, id, value}, network),
    do: "#{label(network, id)} starts no later than #{year_label(value)}"

  defp render_source({:bound, :end, :lower, id, value}, network),
    do: "#{label(network, id)} ends no earlier than #{year_label(value)}"

  defp render_source({:bound, :end, :upper, id, value}, network),
    do: "#{label(network, id)} ends no later than #{year_label(value)}"

  defp render_source({:duration, :min, id, duration}, network),
    do: "#{label(network, id)} lasts at least #{duration_label(duration)}"

  defp render_source({:duration, :max, id, duration}, network),
    do: "#{label(network, id)} lasts at most #{duration_label(duration)}"

  defp render_source({:non_negative, id}, network),
    do: "#{label(network, id)} cannot end before it starts"

  defp render_source({:sequence, a, b}, network),
    do: "#{label(network, a)} immediately precedes #{label(network, b)}"

  defp render_source({:relation, relation}, network) do
    "#{label(network, relation.from)} #{relation_phrase(relation.type)} #{label(network, relation.to)}"
  end

  defp relation_phrase(:starts_during), do: "starts during"
  defp relation_phrase(:ends_during), do: "ends during"
  defp relation_phrase(:includes_start), do: "includes the start of"
  defp relation_phrase(:includes_end), do: "includes the end of"
  defp relation_phrase(:included_in), do: "is included in"
  defp relation_phrase(:includes), do: "includes"
  defp relation_phrase(:contemporary), do: "is contemporary with"
  defp relation_phrase(:overlaps), do: "overlaps"
  defp relation_phrase(:overlapped_by), do: "is overlapped by"
  defp relation_phrase(:before), do: "is before"
  defp relation_phrase(:after), do: "is after"
  defp relation_phrase(:immediately_precedes), do: "immediately precedes"
  defp relation_phrase(:immediately_follows), do: "immediately follows"
  defp relation_phrase(:synchronous_start), do: "shares a start with"
  defp relation_phrase(:synchronous_end), do: "shares an end with"
  defp relation_phrase(:equals), do: "equals"
  defp relation_phrase({:delay, _, _, _, _}), do: "is offset from"

  defp boundary_phrase({:start, id}, network), do: "the start of #{label(network, id)}"
  defp boundary_phrase({:end, id}, network), do: "the end of #{label(network, id)}"

  defp comparison(:earliest), do: "≥"
  defp comparison(:latest), do: "≤"

  defp label(network, id) do
    case network.periods[id] do
      %{name: name} when is_binary(name) -> name
      _ -> to_string(id)
    end
  end

  defp year_label(%Tempo{time: time}), do: "#{Keyword.get(time, :year)}"

  defp duration_label(%Tempo.Duration{time: time}) do
    case Keyword.get(time, :year) do
      nil -> Inspect.inspect(%Tempo.Duration{time: time}, %Inspect.Opts{})
      years -> "#{years} years"
    end
  end
end
