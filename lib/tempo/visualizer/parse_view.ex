defmodule Tempo.Visualizer.ParseView do
  @moduledoc false

  alias Tempo.Visualizer.Render

  @doc """
  Render the main page for an optional ISO 8601 / EDTF input.

  ### Arguments

  * `params` — map with an optional `:input` key holding the
    user's input string (may be `""` or `nil`).

  * `base` — URL base prefix for asset and form links.

  ### Returns

  * iodata representing the full HTML page.

  """
  def render(params, base) do
    input = Map.get(params, :input, "") || ""

    body =
      cond do
        input == "" ->
          [empty_card(base)]

        true ->
          case Tempo.from_iso8601(input) do
            {:ok, value} ->
              [echo_card(input), segments_card(value), details_card(value)]

            {:error, reason} ->
              [echo_card(input), error_card(reason)]
          end
      end

    Render.page(
      title: "Parse",
      base: base,
      input: input,
      body: body
    )
  end

  ## Empty / landing card

  @examples [
    {"2022-06-15", "Calendar date"},
    {"2022-W24-3", "ISO week date"},
    {"2022-166", "Ordinal date"},
    {"2022-06-15T10:30:00Z", "Datetime with UTC"},
    {"2022-06-15T10:30:00+05:30", "Datetime with offset"},
    {"2022-25", "Season (N spring, astronomical)"},
    {"2022-?06-15", "Uncertain month (EDTF L2)"},
    {"1984?/2004~", "Interval with per-endpoint qualification"},
    {"156X-12-25", "Unspecified decade"},
    {"-1XXX-XX", "Negative year, unspecified digits"},
    {"1985/..", "Open-ended interval"},
    {"{1960,1961,1962}", "Set of dates"},
    {"2022-11-20T10:30:00Z[Europe/Paris][u-ca=hebrew]", "IXDTF with zone and calendar"},
    {"R5/2022-01-01/P1M", "Recurring interval"},
    {"Y17E8", "Long year with exponent"}
  ]

  defp empty_card(base) do
    [
      "<div class=\"vz-card\">",
      "<h2>Try an example</h2>",
      "<div class=\"vz-examples\">",
      Enum.map(@examples, fn {iso, label} ->
        [
          "<a href=\"",
          Render.escape(base),
          "/?iso=",
          URI.encode_www_form(iso),
          "\">",
          Render.escape(iso),
          "<span>",
          Render.escape(label),
          "</span></a>"
        ]
      end),
      "</div>",
      "</div>"
    ]
  end

  ## Echo the raw input

  defp echo_card(input) do
    [
      "<div class=\"vz-card\">",
      "<h2>Input</h2>",
      "<div class=\"vz-echo\" dir=\"ltr\">",
      Render.escape(input),
      "</div>",
      "</div>"
    ]
  end

  ## Error

  defp error_card(reason) do
    [
      "<div class=\"vz-card vz-error\">",
      "<h2>Parse error</h2>",
      "<div class=\"vz-error-message\">",
      Render.escape(to_string(reason)),
      "</div>",
      "</div>"
    ]
  end

  ## Segment breakdown

  defp segments_card(value) do
    [
      "<div class=\"vz-card\">",
      "<h2>Components</h2>",
      "<div class=\"vz-segments\">",
      segments_for(value) |> Enum.map(&render_segment/1),
      "</div>",
      "</div>"
    ]
  end

  defp render_segment(%{glyph: glyph, label: label, detail: detail, kind: kind}) do
    class = "vz-segment vz-segment--#{kind}"

    [
      "<div class=\"",
      class,
      "\">",
      "<div class=\"vz-glyph\">",
      Render.escape(glyph),
      "</div>",
      "<div class=\"vz-descriptor\">",
      "<div class=\"vz-label\">",
      Render.escape(label),
      "</div>",
      "<div class=\"vz-detail\">",
      Render.escape(detail),
      "</div>",
      "</div>",
      "</div>"
    ]
  end

  ## Produces the ordered list of segments from a parsed value.
  ## Each segment is a map: %{glyph, label, detail, kind}.

  defp segments_for(%Tempo{} = tempo) do
    tempo_segments(tempo, _is_endpoint = false)
  end

  defp segments_for(%Tempo.Interval{from: from, to: to, duration: duration, recurrence: r}) do
    List.flatten([
      recurrence_segment(r),
      endpoint_segments(from),
      separator("/"),
      endpoint_segments(to || duration)
    ])
    |> Enum.reject(&is_nil/1)
  end

  defp segments_for(%Tempo.Duration{time: time}) do
    [%{glyph: "P", label: "Duration", detail: "marker", kind: "separator"}] ++
      Enum.map(time, &duration_unit_segment/1)
  end

  defp segments_for(%Tempo.Set{set: set, type: type}) do
    # `Tempo.Set.type` is `:all | :one` per its struct spec —
    # no catch-all fallback needed.
    {open, close} =
      case type do
        :all -> {"{", "}"}
        :one -> {"[", "]"}
      end

    set_type_detail =
      case type do
        :all -> "All of"
        :one -> "One of"
      end

    opener = %{glyph: open, label: "Set", detail: set_type_detail, kind: "extended"}
    closer = %{glyph: close, label: "Set end", detail: "", kind: "separator"}

    members =
      set
      |> Enum.with_index()
      |> Enum.flat_map(fn {member, i} ->
        prefix = if i == 0, do: [], else: [separator(",")]
        prefix ++ List.wrap(segment_for_set_member(member))
      end)

    [opener] ++ members ++ [closer]
  end

  defp segments_for(other) do
    [
      %{
        glyph: inspect(other),
        label: "Unrecognised",
        detail: "no visualisation available",
        kind: "separator"
      }
    ]
  end

  defp segment_for_set_member(%Tempo{} = t), do: tempo_segments(t, true)
  defp segment_for_set_member({:range, [a, b]}), do: range_segments(a, b)

  defp segment_for_set_member(other),
    do: [%{glyph: inspect(other), label: "Member", detail: "", kind: "separator"}]

  defp range_segments(a, b) do
    a_segs = segment_or_undefined(a)
    b_segs = segment_or_undefined(b)
    a_segs ++ [separator("..")] ++ b_segs
  end

  defp segment_or_undefined(:undefined),
    do: [%{glyph: "..", label: "Open", detail: "Undefined endpoint", kind: "extended"}]

  defp segment_or_undefined(%Tempo{} = t), do: tempo_segments(t, true)
  defp segment_or_undefined(list) when is_list(list), do: tempo_segments(%Tempo{time: list}, true)

  defp segment_or_undefined(other),
    do: [%{glyph: inspect(other), label: "", detail: "", kind: "separator"}]

  # Build segments for a single `%Tempo{}`. When `is_endpoint?` is true
  # the year is rendered without a leading `-` separator, since it's
  # the first glyph of a sub-expression.
  defp tempo_segments(%Tempo{time: time} = tempo, is_endpoint?) when is_list(time) do
    time_segments =
      time
      |> Enum.with_index()
      |> Enum.map(fn {{unit, value}, i} ->
        time_unit_segment(unit, value, i == 0 or is_endpoint?)
      end)

    time_segments ++
      shift_segments(tempo.shift) ++
      qualification_segments(tempo.qualification, tempo.qualifications) ++
      extended_segments(tempo.extended)
  end

  defp tempo_segments(%Tempo{time: nil} = _tempo, _is_endpoint?) do
    []
  end

  defp endpoint_segments(:undefined),
    do: [%{glyph: "..", label: "Open", detail: "Undefined endpoint", kind: "extended"}]

  defp endpoint_segments(nil), do: []
  defp endpoint_segments(%Tempo{} = t), do: tempo_segments(t, true)
  defp endpoint_segments(%Tempo.Duration{} = d), do: segments_for(d)

  # `recurrence` on `%Tempo.Interval{}` is constrained by the
  # struct's type to `pos_integer() | :infinity` — the four
  # clauses above cover every reachable value; no fallback.
  defp recurrence_segment(1), do: nil

  defp recurrence_segment(:infinity) do
    %{glyph: "R/", label: "Recurrence", detail: "Infinite", kind: "extended"}
  end

  defp recurrence_segment(n) when is_integer(n) do
    %{glyph: "R#{n}/", label: "Recurrence", detail: "#{n} repeats", kind: "extended"}
  end

  ## Time-unit segments

  defp time_unit_segment(:year, value, first?) do
    prefix = if first?, do: "", else: ""
    {glyph, detail} = year_display(value)

    %{
      glyph: prefix <> glyph,
      label: "Year",
      detail: detail,
      kind: "primary"
    }
  end

  defp time_unit_segment(:month, value, _first?) do
    {glyph, detail} = month_display(value)
    %{glyph: "-" <> glyph, label: "Month", detail: detail, kind: "primary"}
  end

  defp time_unit_segment(:day, value, _first?) do
    {glyph, detail} = day_display(value)
    %{glyph: "-" <> glyph, label: "Day", detail: detail, kind: "primary"}
  end

  defp time_unit_segment(:week, value, _first?) do
    {glyph, detail} = integer_display(value, "W")
    %{glyph: "-W" <> glyph, label: "Week", detail: detail, kind: "primary"}
  end

  defp time_unit_segment(:day_of_week, value, _first?) do
    {glyph, detail} = integer_display(value, "")
    %{glyph: "-" <> glyph, label: "Day of week", detail: detail, kind: "primary"}
  end

  defp time_unit_segment(:hour, value, _first?) do
    {glyph, detail} = integer_display(value, "")
    %{glyph: "T" <> glyph, label: "Hour", detail: detail, kind: "primary"}
  end

  defp time_unit_segment(:minute, value, _first?) do
    {glyph, detail} = integer_display(value, "")
    %{glyph: ":" <> glyph, label: "Minute", detail: detail, kind: "primary"}
  end

  defp time_unit_segment(:second, value, _first?) do
    {glyph, detail} = integer_display(value, "")
    %{glyph: ":" <> glyph, label: "Second", detail: detail, kind: "primary"}
  end

  defp time_unit_segment(:century, value, _first?) do
    {glyph, detail} = integer_display(value, "")
    %{glyph: glyph <> "C", label: "Century", detail: detail, kind: "primary"}
  end

  defp time_unit_segment(:decade, value, _first?) do
    {glyph, detail} = integer_display(value, "")
    %{glyph: glyph <> "J", label: "Decade", detail: detail, kind: "primary"}
  end

  defp time_unit_segment(unit, value, _first?) do
    %{
      glyph: inspect(value),
      label: unit |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize(),
      detail: inspect(value),
      kind: "primary"
    }
  end

  defp duration_unit_segment({:direction, :negative}),
    do: %{glyph: "-", label: "Direction", detail: "Negative", kind: "extended"}

  defp duration_unit_segment({unit, value}) do
    suffix =
      case unit do
        :century -> "C"
        :decade -> "J"
        :year -> "Y"
        :month -> "M"
        :week -> "W"
        :day -> "D"
        :hour -> "H"
        :minute -> "M"
        :second -> "S"
        _ -> ""
      end

    %{
      glyph: "#{value}#{suffix}",
      label: unit |> Atom.to_string() |> String.capitalize(),
      detail: "#{value}",
      kind: "primary"
    }
  end

  ## Display helpers for individual unit values

  defp year_display(y) when is_integer(y) and y >= 0,
    do: {pad(y, 4), "Year #{y} CE"}

  defp year_display(y) when is_integer(y) and y < 0,
    do: {"-" <> pad(abs(y), 4), "#{abs(y)} BCE"}

  defp year_display({:mask, _} = mask), do: {mask_display(mask), "Year with unspecified digits"}

  defp year_display({y, opts}) when is_integer(y) and is_list(opts) do
    digits = Keyword.get(opts, :significant_digits)
    margin = Keyword.get(opts, :margin_of_error)

    suffix =
      [if(digits, do: "S#{digits}"), if(margin, do: "±#{margin}")]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("")

    detail =
      ["Year #{y}"] ++
        List.wrap(if digits, do: "#{digits} significant digit(s)") ++
        List.wrap(if margin, do: "margin ±#{margin}")

    {"#{y}#{suffix}", Enum.join(detail, ", ")}
  end

  defp year_display(other), do: {inspect(other), ""}

  defp month_display(m) when is_integer(m) and m in 1..12 do
    {pad(m, 2), "#{month_name(m)} (month #{m})"}
  end

  defp month_display(m) when is_integer(m) and m in 21..24 do
    {pad(m, 2), "Meteorological season #{m} — #{season_name(m)}"}
  end

  defp month_display(m) when is_integer(m) and m in 25..28 do
    {pad(m, 2), "Astronomical season #{m} — #{season_name(m)} (Northern)"}
  end

  defp month_display(m) when is_integer(m) and m in 29..32 do
    {pad(m, 2), "Astronomical season #{m} — #{season_name(m)} (Southern)"}
  end

  defp month_display(m) when is_integer(m) and m in 33..36 do
    {pad(m, 2), "Quarter Q#{m - 32}"}
  end

  defp month_display(m) when is_integer(m) and m in 40..41 do
    {pad(m, 2), "Half H#{m - 39}"}
  end

  defp month_display({:mask, _} = mask), do: {mask_display(mask), "Month with unspecified digits"}

  defp month_display(other), do: {inspect(other), ""}

  defp day_display(d) when is_integer(d) and d in 1..31, do: {pad(d, 2), "Day #{d}"}
  defp day_display({:mask, _} = mask), do: {mask_display(mask), "Day with unspecified digits"}
  defp day_display(other), do: {inspect(other), ""}

  defp integer_display(v, _suffix) when is_integer(v), do: {pad(v, 2), "#{v}"}
  defp integer_display({:mask, _} = mask, _), do: {mask_display(mask), "With unspecified digits"}
  defp integer_display(other, _), do: {inspect(other), ""}

  defp mask_display({:mask, [:negative | rest]}), do: "-" <> mask_display({:mask, rest})
  defp mask_display({:mask, :"X*"}), do: "X*"

  defp mask_display({:mask, list}) when is_list(list) do
    Enum.map_join(list, "", fn
      :X -> "X"
      d when is_integer(d) -> Integer.to_string(d)
      other -> inspect(other)
    end)
  end

  defp pad(value, width) when is_integer(value) and value >= 0 do
    value |> Integer.to_string() |> String.pad_leading(width, "0")
  end

  defp pad(value, _width), do: inspect(value)

  @months %{
    1 => "January",
    2 => "February",
    3 => "March",
    4 => "April",
    5 => "May",
    6 => "June",
    7 => "July",
    8 => "August",
    9 => "September",
    10 => "October",
    11 => "November",
    12 => "December"
  }

  defp month_name(m), do: Map.get(@months, m, "")

  @seasons %{
    21 => "Spring",
    22 => "Summer",
    23 => "Autumn",
    24 => "Winter",
    25 => "Spring",
    26 => "Summer",
    27 => "Autumn",
    28 => "Winter",
    29 => "Spring",
    30 => "Summer",
    31 => "Autumn",
    32 => "Winter"
  }

  defp season_name(code), do: Map.get(@seasons, code, "")

  ## Time shift

  defp shift_segments(nil), do: []

  defp shift_segments(shift) when is_list(shift) do
    hour = Keyword.get(shift, :hour, 0)
    minute = Keyword.get(shift, :minute, 0)

    cond do
      hour == 0 and minute == 0 ->
        [%{glyph: "Z", label: "Time shift", detail: "UTC", kind: "extended"}]

      true ->
        sign = if hour >= 0, do: "+", else: "-"
        glyph = "#{sign}#{pad(abs(hour), 2)}:#{pad(minute, 2)}"
        detail = "#{sign}#{abs(hour)}h#{if minute != 0, do: " #{minute}m", else: ""} from UTC"
        [%{glyph: glyph, label: "Time shift", detail: detail, kind: "extended"}]
    end
  end

  defp shift_segments(_), do: []

  ## Qualification

  defp qualification_segments(nil, nil), do: []

  defp qualification_segments(expression_q, component_qs) do
    expr =
      case expression_q do
        nil ->
          []

        q ->
          [
            %{
              glyph: qualifier_glyph(q),
              label: "Qualification",
              detail: qualifier_name(q),
              kind: "qualification"
            }
          ]
      end

    comp =
      case component_qs do
        nil ->
          []

        map when map_size(map) == 0 ->
          []

        map ->
          [
            %{
              glyph: "?~%",
              label: "Component qualifiers",
              detail: component_qualifier_detail(map),
              kind: "qualification"
            }
          ]
      end

    expr ++ comp
  end

  defp qualifier_glyph(:uncertain), do: "?"
  defp qualifier_glyph(:approximate), do: "~"
  defp qualifier_glyph(:uncertain_and_approximate), do: "%"
  defp qualifier_glyph(_), do: "?"

  defp qualifier_name(:uncertain), do: "Uncertain (?)"
  defp qualifier_name(:approximate), do: "Approximate (~)"
  defp qualifier_name(:uncertain_and_approximate), do: "Uncertain & approximate (%)"
  defp qualifier_name(other), do: to_string(other)

  defp component_qualifier_detail(map) do
    map
    |> Enum.map(fn {unit, qual} -> "#{unit}: #{qualifier_name(qual)}" end)
    |> Enum.join(", ")
  end

  ## Extended (IXDTF)

  defp extended_segments(nil), do: []

  defp extended_segments(%{zone_id: nil, zone_offset: nil, calendar: nil, tags: tags})
       when tags == %{},
       do: []

  defp extended_segments(%{} = extended) do
    []
    |> zone_segment(extended)
    |> calendar_segment(extended)
    |> tags_segment(extended)
  end

  defp zone_segment(acc, %{zone_id: nil, zone_offset: nil}), do: acc

  defp zone_segment(acc, %{zone_id: zone_id}) when is_binary(zone_id) do
    acc ++
      [
        %{
          glyph: "[#{zone_id}]",
          label: "Time zone",
          detail: "IANA zone: #{zone_id}",
          kind: "extended"
        }
      ]
  end

  defp zone_segment(acc, %{zone_offset: offset}) when is_integer(offset) do
    sign = if offset >= 0, do: "+", else: "-"
    abs_offset = abs(offset)
    hh = div(abs_offset, 60)
    mm = rem(abs_offset, 60)
    glyph = "[#{sign}#{pad(hh, 2)}:#{pad(mm, 2)}]"

    acc ++
      [
        %{
          glyph: glyph,
          label: "Offset",
          detail: "#{sign}#{hh}h #{mm}m from UTC",
          kind: "extended"
        }
      ]
  end

  defp zone_segment(acc, _), do: acc

  defp calendar_segment(acc, %{calendar: nil}), do: acc

  defp calendar_segment(acc, %{calendar: calendar}) do
    acc ++
      [
        %{
          glyph: "[u-ca=#{calendar}]",
          label: "Calendar",
          detail: "u-ca = #{calendar}",
          kind: "extended"
        }
      ]
  end

  defp tags_segment(acc, %{tags: tags}) when map_size(tags) == 0, do: acc

  defp tags_segment(acc, %{tags: tags}) do
    segments =
      Enum.map(tags, fn {key, values} ->
        joined = Enum.join(values, "-")

        %{
          glyph: "[#{key}=#{joined}]",
          label: "IXDTF tag",
          detail: "#{key} = #{joined}",
          kind: "extended"
        }
      end)

    acc ++ segments
  end

  defp separator(text) do
    %{glyph: text, label: "", detail: "", kind: "separator"}
  end

  ## Details card — a full dump of the parsed struct fields

  defp details_card(value) do
    [
      "<div class=\"vz-card\">",
      "<h2>Parsed value</h2>",
      "<dl class=\"vz-details\">",
      detail_rows(value),
      "</dl>",
      "</div>"
    ]
  end

  defp detail_rows(%Tempo{} = t) do
    [
      row("Type", "Tempo"),
      row("Time", inspect(t.time)),
      row_if(t.shift, "Shift", &inspect/1),
      row_if(t.calendar, "Calendar", &inspect/1),
      row_if(t.qualification, "Qualification", &qualifier_name/1),
      row_if(t.qualifications, "Qualifications", &inspect/1),
      row_if(t.extended, "Extended (IXDTF)", &inspect/1)
    ]
  end

  defp detail_rows(%Tempo.Interval{} = i) do
    [
      row("Type", "Tempo.Interval"),
      row_if(i.recurrence && i.recurrence != 1, "Recurrence", &inspect/1),
      row("From", inspect(i.from)),
      row_if(i.to, "To", &inspect/1),
      row_if(i.duration, "Duration", &inspect/1),
      row_if(i.repeat_rule, "Repeat rule", &inspect/1)
    ]
  end

  defp detail_rows(%Tempo.Duration{} = d) do
    [
      row("Type", "Tempo.Duration"),
      row("Time", inspect(d.time))
    ]
  end

  defp detail_rows(%Tempo.Set{} = s) do
    [
      row("Type", "Tempo.Set"),
      row("Set kind", to_string(s.type)),
      row("Members", "#{length(s.set)}")
    ]
  end

  defp detail_rows(other), do: [row("Value", inspect(other))]

  defp row(label, detail) do
    [
      "<dt>",
      Render.escape(label),
      "</dt><dd>",
      Render.escape(detail),
      "</dd>"
    ]
  end

  defp row_if(nil, _, _), do: []
  defp row_if(false, _, _), do: []
  defp row_if(value, label, formatter), do: row(label, formatter.(value))
end
