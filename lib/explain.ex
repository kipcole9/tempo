defmodule Tempo.Explanation do
  @moduledoc """
  A structured explanation of a Tempo value.

  Produced by `Tempo.Explain.explain/1`. Consists of a `:kind`
  classifier and an ordered list of `{tag, text}` parts. The tag
  lets renderers (plain terminal, ANSI colour, HTML, visualizer
  components) style each part semantically without re-parsing the
  prose.

  ### Fields

  * `:kind` — a classifier atom (e.g. `:scalar_year`,
    `:masked_year`, `:duration`, `:interval_set`).

  * `:parts` — a list of `{tag :: atom(), text :: String.t()}`
    tuples. Common tags:

    * `:headline` — one-line description of what this value is.
    * `:span` — bounded interval in `[from, to)` form.
    * `:qualification` — EDTF qualifier description.
    * `:extended` — IXDTF metadata (zone, calendar, tags).
    * `:calendar` — non-default calendar.
    * `:enumeration` — iteration granularity.
    * `:hint` — pointer to relevant function.
    * `:metadata` — user metadata on an interval.
    * `:member` — list-of-members preview for sets.

  """

  @type t :: %__MODULE__{
          kind: atom(),
          parts: [{atom(), String.t()}]
        }

  defstruct [:kind, parts: []]
end

defmodule Tempo.Explain do
  import Kernel, except: [to_string: 1]

  @moduledoc """
  Plain-English explanations of Tempo values, in a form renderers
  can style.

  `Tempo.Explain.explain/1` returns a `t:Tempo.Explanation.t/0`
  with semantic part tags. Three formatters produce output for
  different surfaces:

  * `to_string/1` — plain multi-line text. Default for iex.
  * `to_ansi/1` — ANSI-coloured for terminals.
  * `to_iodata/1` — tagged iodata for HTML or visualizer renderers.

  `Tempo.explain/1` delegates here with a `to_string/1` formatter —
  the most common case for interactive use.

  ## Example

      iex> Tempo.Explain.explain(~o"156X").kind
      :masked_year

      iex> Tempo.Explain.explain(~o"156X").parts
      ...> |> Enum.map(&elem(&1, 0))
      [:headline, :span, :enumeration, :hint]

  """

  alias Tempo.{Explanation, Iso8601.Unit}

  @doc """
  Return a structured `t:Tempo.Explanation.t/0` for any Tempo
  value. Unknown shapes produce a generic fallback rather than
  raising.
  """
  @spec explain(term()) :: Explanation.t()
  def explain(value) do
    %Explanation{kind: classify(value), parts: explain_parts(value)}
  end

  @doc """
  Render an explanation as plain multi-line text.

  ### Examples

      iex> Tempo.Explain.explain(~o"2022Y") |> Tempo.Explain.to_string()
      "The year 2022.\\nSpan: [2022-01-01, 2023-01-01).\\nIterates at :month granularity.\\nMaterialise as an interval with `Tempo.to_interval/1`."

  """
  @spec to_string(Explanation.t()) :: String.t()
  def to_string(%Explanation{parts: parts}) do
    parts
    |> Enum.map(fn {_tag, text} -> text end)
    |> Enum.join("\n")
  end

  @doc """
  Render an explanation with ANSI colour codes, suitable for a
  terminal that supports them.

  The colour mapping is deliberate: headlines are bright, spans
  are cyan (technical detail), qualifications and metadata are
  yellow (notable), hints are dim.
  """
  @spec to_ansi(Explanation.t()) :: String.t()
  def to_ansi(%Explanation{parts: parts}) do
    # `emit?` forced to true — callers that want unconditional
    # ANSI get it. For terminal-aware emission the caller should
    # gate on `IO.ANSI.enabled?/0` themselves.
    parts
    |> Enum.map(&ansi_for/1)
    |> Enum.intersperse("\n")
    |> IO.ANSI.format(true)
    |> IO.iodata_to_binary()
  end

  defp ansi_for({:headline, text}), do: [:bright, text, :reset]
  defp ansi_for({:span, text}), do: [:cyan, text, :reset]
  defp ansi_for({:qualification, text}), do: [:yellow, text, :reset]
  defp ansi_for({:extended, text}), do: [:yellow, text, :reset]
  defp ansi_for({:calendar, text}), do: [:magenta, text, :reset]
  defp ansi_for({:enumeration, text}), do: [:green, text, :reset]
  defp ansi_for({:hint, text}), do: [:faint, text, :reset]
  defp ansi_for({:metadata, text}), do: [:yellow, text, :reset]
  defp ansi_for({:member, text}), do: [:cyan, text, :reset]
  defp ansi_for({_tag, text}), do: [text]

  @doc """
  Render as tagged iodata `[{tag, text}, ...]`, ready for an HTML
  or visualizer renderer to style each part by its tag.

  Each element is a 2-tuple; no string concatenation happens here.
  Callers decide how to separate parts (newlines, `<div>`s, etc.).
  """
  @spec to_iodata(Explanation.t()) :: [{atom(), String.t()}]
  def to_iodata(%Explanation{parts: parts}), do: parts

  ## ------------------------------------------------------------
  ## Classification
  ## ------------------------------------------------------------

  defp classify(%Tempo{time: time}) do
    cond do
      has_mask?(time) -> :masked
      only_time_of_day?(time) -> :time_of_day
      Keyword.has_key?(time, :year) -> :anchored
      true -> :scalar_other
    end
  end

  defp classify(%Tempo.Interval{from: :undefined, to: :undefined}), do: :fully_open_interval
  defp classify(%Tempo.Interval{from: :undefined}), do: :open_lower_interval
  defp classify(%Tempo.Interval{to: :undefined}), do: :open_upper_interval

  defp classify(%Tempo.Interval{recurrence: n}) when is_integer(n) and n > 1,
    do: :recurring_interval

  defp classify(%Tempo.Interval{}), do: :closed_interval
  defp classify(%Tempo.IntervalSet{intervals: []}), do: :empty_interval_set
  defp classify(%Tempo.IntervalSet{}), do: :interval_set
  defp classify(%Tempo.Set{type: :all}), do: :all_of_set
  defp classify(%Tempo.Set{type: :one}), do: :one_of_set
  defp classify(%Tempo.Duration{}), do: :duration
  defp classify(_), do: :unknown

  ## ------------------------------------------------------------
  ## explain_parts — one clause per input shape
  ## ------------------------------------------------------------

  defp explain_parts(%Tempo{} = tempo), do: scalar_parts(tempo)
  defp explain_parts(%Tempo.Interval{} = iv), do: interval_parts(iv)
  defp explain_parts(%Tempo.IntervalSet{} = set), do: interval_set_parts(set)
  defp explain_parts(%Tempo.Set{} = set), do: set_parts(set)
  defp explain_parts(%Tempo.Duration{} = d), do: duration_parts(d)

  defp explain_parts(other) do
    [{:headline, "A value Tempo doesn't know how to describe: #{inspect(other)}."}]
  end

  ## ------------------------------------------------------------
  ## Scalar Tempo
  ## ------------------------------------------------------------

  defp scalar_parts(%Tempo{} = tempo) do
    [
      {:headline, scalar_headline(tempo)},
      {:span, scalar_span(tempo)},
      {:qualification, qualification_text(tempo)},
      {:extended, extended_text(tempo)},
      {:calendar, calendar_text(tempo)},
      {:enumeration, enumeration_text(tempo)},
      {:hint, "Materialise as an interval with `Tempo.to_interval/1`."}
    ]
    |> Enum.reject(fn {_, v} -> v in [nil, ""] end)
  end

  defp scalar_headline(%Tempo{time: time} = tempo) do
    cond do
      has_mask?(time) -> mask_headline(tempo)
      only_time_of_day?(time) -> time_of_day_headline(time)
      true -> anchored_headline(time)
    end
  end

  defp anchored_headline(time) do
    y = Keyword.get(time, :year)
    m = Keyword.get(time, :month)
    d = Keyword.get(time, :day)
    h = Keyword.get(time, :hour)
    mi = Keyword.get(time, :minute)

    cond do
      is_integer(y) and is_integer(m) and is_integer(d) and is_integer(h) ->
        "#{month_name(m)} #{d}, #{y} at #{two_digit(h)}:#{two_digit(mi || 0)}."

      is_integer(y) and is_integer(m) and is_integer(d) ->
        "#{month_name(m)} #{d}, #{y}."

      is_integer(y) and is_integer(m) ->
        "#{month_name(m)} #{y}."

      is_integer(y) ->
        "The year #{y}."

      true ->
        "An anchored Tempo value."
    end
  end

  defp time_of_day_headline(time) do
    h = Keyword.get(time, :hour, 0)
    m = Keyword.get(time, :minute, 0)
    "The time-of-day #{two_digit(h)}:#{two_digit(m)} (non-anchored — recurs every day)."
  end

  defp mask_headline(%Tempo{time: time}) do
    case find_first_mask(time) do
      {:year, mask} ->
        {min, max} = mask_range(mask)
        sign_note = if :negative in mask, do: " BCE", else: ""
        "A masked year spanning #{decade_label(min, max)}#{sign_note}."

      {unit, _mask} ->
        "A Tempo with a masked #{unit} component."

      nil ->
        "A Tempo value."
    end
  end

  defp decade_label(min, max) when max - min == 9, do: "the #{min}s"
  defp decade_label(min, max) when max - min == 99, do: "the #{div(min, 100)}00s (century)"
  defp decade_label(min, max) when max - min == 999, do: "the #{div(min, 1000)}000s (millennium)"
  defp decade_label(min, max) when max - min == 9999, do: "all 4-digit years (#{min}–#{max})"
  defp decade_label(min, max), do: "#{min} through #{max} (#{max - min + 1} years)"

  defp scalar_span(%Tempo{} = tempo) do
    case Tempo.to_interval(tempo) do
      {:ok, %Tempo.Interval{from: from, to: to}} ->
        "Span: [#{render_endpoint(from)}, #{render_endpoint(to)})."

      {:ok, %Tempo.IntervalSet{intervals: intervals}} ->
        "Materialises to #{length(intervals)} disjoint intervals."

      {:error, _} ->
        nil
    end
  end

  defp qualification_text(%Tempo{qualification: nil, qualifications: nil}), do: nil

  defp qualification_text(%Tempo{qualification: q, qualifications: qs}) do
    parts =
      [
        q && "Expression-level qualification: #{qualification_word(q)} (EDTF #{qualification_symbol(q)}).",
        qs && map_size(qs) > 0 && "Per-component qualifications: #{inspect(qs)}."
      ]
      |> Enum.reject(&(&1 in [nil, false]))

    case parts do
      [] -> nil
      _ -> Enum.join(parts, " ")
    end
  end

  defp extended_text(%Tempo{extended: nil}), do: nil

  defp extended_text(%Tempo{extended: extended}) do
    parts =
      [
        extended[:zone_id] && "Timezone: #{extended.zone_id}.",
        extended[:zone_offset] && "UTC offset: #{extended.zone_offset} minutes.",
        extended[:calendar] && "IXDTF calendar hint: #{extended.calendar}."
      ]
      |> Enum.reject(&(&1 in [nil, false]))

    case parts do
      [] -> nil
      _ -> Enum.join(parts, " ")
    end
  end

  defp calendar_text(%Tempo{calendar: Calendrical.Gregorian}), do: nil
  defp calendar_text(%Tempo{calendar: Calendar.ISO}), do: nil
  defp calendar_text(%Tempo{calendar: cal}), do: "Calendar: #{inspect(cal)}."

  defp enumeration_text(%Tempo{} = tempo) do
    {unit, _} = Tempo.resolution(tempo)

    case Unit.implicit_enumerator(unit, tempo.calendar) do
      nil ->
        "At finest supported resolution — cannot be enumerated further."

      {next_unit, _} ->
        "Iterates at #{inspect(next_unit)} granularity."
    end
  rescue
    _ -> nil
  end

  ## ------------------------------------------------------------
  ## Tempo.Interval
  ## ------------------------------------------------------------

  defp interval_parts(%Tempo.Interval{from: :undefined, to: :undefined}) do
    [
      {:headline, "A fully open interval (`../..`)."},
      {:hint, "No anchor on either side — not enumerable, not usable in set operations."}
    ]
  end

  defp interval_parts(%Tempo.Interval{from: :undefined, to: %Tempo{} = to}) do
    [
      {:headline, "An open-lower interval (`../#{render_endpoint(to)}`)."},
      {:span, "Upper bound: #{render_endpoint(to)}."},
      {:hint, "Enumeration requires a lower bound; set operations need a `:bound` option."}
    ]
  end

  defp interval_parts(%Tempo.Interval{from: %Tempo{} = from, to: :undefined}) do
    [
      {:headline, "An open-upper interval (`#{render_endpoint(from)}/..`)."},
      {:span, "Lower bound: #{render_endpoint(from)}."},
      {:hint, "Enumerates forward forever — use `Enum.take/2` to halt."}
    ]
  end

  defp interval_parts(%Tempo.Interval{
         recurrence: n,
         from: from,
         duration: %Tempo.Duration{time: dt}
       })
       when is_integer(n) and n > 1 do
    [
      {:headline, "A recurrence of #{n} occurrences."},
      {:span, "Starting: #{render_endpoint(from)}."},
      {:span, "Cadence: #{duration_prose(dt)}."},
      {:hint,
       "Materialise with `Tempo.to_interval/1` to get an IntervalSet of the #{n} occurrences."}
    ]
  end

  defp interval_parts(%Tempo.Interval{from: %Tempo{} = from, to: %Tempo{} = to} = interval) do
    [
      {:headline, "A closed interval."},
      {:span, "From: #{render_endpoint(from)}."},
      {:span, "To:   #{render_endpoint(to)} (exclusive — half-open `[from, to)`)."},
      metadata_part(interval.metadata)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp interval_parts(%Tempo.Interval{}) do
    [{:headline, "A Tempo.Interval with an unusual shape."}]
  end

  defp metadata_part(m) when m == %{} or is_nil(m), do: nil

  defp metadata_part(m) do
    text =
      case m[:summary] do
        nil ->
          "Metadata: #{map_size(m)} key(s)."

        s ->
          loc = m[:location]
          if is_binary(loc), do: "Event: #{s} @ #{loc}.", else: "Event: #{s}."
      end

    {:metadata, text}
  end

  ## ------------------------------------------------------------
  ## Tempo.IntervalSet
  ## ------------------------------------------------------------

  defp interval_set_parts(%Tempo.IntervalSet{intervals: [], metadata: metadata}) do
    [
      {:headline, "An empty IntervalSet."},
      set_metadata_part(metadata)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp interval_set_parts(%Tempo.IntervalSet{intervals: intervals, metadata: metadata}) do
    count = length(intervals)

    preview_parts =
      intervals
      |> Enum.take(3)
      |> Enum.with_index(1)
      |> Enum.map(fn {iv, i} ->
        summary = (iv.metadata || %{})[:summary] || "(no summary)"
        {:member,
         "#{i}. #{render_endpoint(iv.from)} → #{render_endpoint(iv.to)}  · #{summary}"}
      end)

    more =
      if count > 3, do: [{:member, "… and #{count - 3} more."}], else: []

    [
      {:headline, "An IntervalSet with #{count} interval#{if count == 1, do: "", else: "s"}."}
    ] ++ preview_parts ++ more ++ List.wrap(set_metadata_part(metadata))
  end

  defp set_metadata_part(nil), do: nil
  defp set_metadata_part(m) when m == %{}, do: nil

  defp set_metadata_part(%{name: name}) when is_binary(name),
    do: {:metadata, "Calendar name: #{name}."}

  defp set_metadata_part(%{prodid: prodid}) when is_binary(prodid),
    do: {:metadata, "Producer: #{prodid}."}

  defp set_metadata_part(m),
    do: {:metadata, "Set-level metadata: #{map_size(m)} key(s)."}

  ## ------------------------------------------------------------
  ## Tempo.Set
  ## ------------------------------------------------------------

  defp set_parts(%Tempo.Set{type: :all, set: members}) do
    [
      {:headline, "An all-of set: every member happened."},
      {:member,
       "#{length(members)} member(s): #{members |> Enum.map(&inspect/1) |> Enum.join(", ")}."},
      {:hint, "Materialise as an IntervalSet with `Tempo.to_interval/1`."}
    ]
  end

  defp set_parts(%Tempo.Set{type: :one, set: members}) do
    [
      {:headline,
       "A one-of set: exactly one of the members happened — we don't know which (epistemic disjunction)."},
      {:member,
       "#{length(members)} candidate(s): #{members |> Enum.map(&inspect/1) |> Enum.join(", ")}."},
      {:hint, "Cannot be materialised to an IntervalSet; pick a specific member first."}
    ]
  end

  ## ------------------------------------------------------------
  ## Tempo.Duration
  ## ------------------------------------------------------------

  defp duration_parts(%Tempo.Duration{time: time}) do
    [
      {:headline, "A duration of #{duration_prose(time)}."},
      {:hint,
       "Has no anchor on the time line — add to or subtract from a Tempo via `Tempo.Math.add/2` / `Tempo.Math.subtract/2`."},
      {:hint, "Not directly usable in set operations."}
    ]
  end

  ## ------------------------------------------------------------
  ## Shared helpers
  ## ------------------------------------------------------------

  defp has_mask?(time) do
    Enum.any?(time, fn
      {_, {:mask, _}} -> true
      _ -> false
    end)
  end

  defp only_time_of_day?(time) do
    not Keyword.has_key?(time, :year) and
      Enum.any?(time, fn
        {u, _} when u in [:hour, :minute, :second] -> true
        _ -> false
      end)
  end

  defp find_first_mask(time) do
    Enum.find_value(time, fn
      {unit, {:mask, mask}} -> {unit, mask}
      _ -> nil
    end)
  end

  defp mask_range(mask) do
    mask
    |> Enum.reject(&(&1 == :negative))
    |> Tempo.Mask.mask_bounds()
  end

  defp qualification_word(:uncertain), do: "uncertain"
  defp qualification_word(:approximate), do: "approximate"
  defp qualification_word(:uncertain_and_approximate), do: "both uncertain and approximate"
  defp qualification_word(other), do: to_string(other)

  defp qualification_symbol(:uncertain), do: "?"
  defp qualification_symbol(:approximate), do: "~"
  defp qualification_symbol(:uncertain_and_approximate), do: "%"
  defp qualification_symbol(_), do: "?"

  # Render an endpoint in a consistent `YYYY-MM-DDTHH:MM` shape,
  # padding missing trailing units with their minimum so the
  # output reads as a concrete moment rather than a span.
  defp render_endpoint(%Tempo{time: time}) do
    y = Keyword.get(time, :year)
    m = Keyword.get(time, :month)
    d = Keyword.get(time, :day)
    h = Keyword.get(time, :hour)
    mi = Keyword.get(time, :minute)

    date_part =
      cond do
        is_integer(y) and is_integer(m) and is_integer(d) ->
          "#{y}-#{two_digit(m)}-#{two_digit(d)}"

        is_integer(y) and is_integer(m) ->
          "#{y}-#{two_digit(m)}-01"

        is_integer(y) ->
          "#{y}-01-01"

        true ->
          nil
      end

    time_part =
      cond do
        is_integer(h) and is_integer(mi) -> "#{two_digit(h)}:#{two_digit(mi)}"
        is_integer(h) -> "#{two_digit(h)}:00"
        is_integer(Keyword.get(time, :minute)) -> "00:#{two_digit(mi)}"
        true -> nil
      end

    case {date_part, time_part} do
      {nil, nil} -> "?"
      {date, nil} -> date
      {nil, time} -> "T#{time}"
      {date, time} -> "#{date}T#{time}"
    end
  end

  defp render_endpoint(other), do: inspect(other)

  defp duration_prose(time) do
    time
    |> Enum.map(fn {unit, n} -> "#{n} #{pluralise(unit, n)}" end)
    |> Enum.join(", ")
  end

  defp pluralise(unit, 1), do: Atom.to_string(unit)
  defp pluralise(unit, _), do: Atom.to_string(unit) <> "s"

  @months ~w(January February March April May June July August September October November December)

  defp month_name(n) when is_integer(n) and n in 1..12, do: Enum.at(@months, n - 1)
  defp month_name(other), do: "month #{inspect(other)}"

  defp two_digit(n) when is_integer(n) and n >= 0 and n < 10, do: "0#{n}"
  defp two_digit(n) when is_integer(n), do: Integer.to_string(n)
  defp two_digit(_), do: "??"
end
