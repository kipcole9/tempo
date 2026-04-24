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

    parsed_body =
      cond do
        input == "" ->
          []

        true ->
          case Tempo.from_iso8601(input) do
            {:ok, value} ->
              [segments_card(input, value), details_card(value)]

            {:error, reason} ->
              [error_card(reason)]
          end
      end

    body =
      [input_card(input, base)] ++
        parsed_body ++
        [examples_card(base)]

    Render.page(
      title: "Parse",
      base: base,
      input: input,
      body: body
    )
  end

  ## Editable input card — replaces both the old header input and
  ## the old echo-of-input card. One box: the user's source of
  ## truth, large enough to read, submits on Enter.

  defp input_card(input, base) do
    [
      "<div class=\"vz-card vz-input-card\">",
      "<form class=\"vz-form\" method=\"get\" action=\"",
      Render.escape(base),
      "/\">",
      "<label class=\"vz-input-label\" for=\"vz-iso-input\">",
      "ISO 8601 or EDTF input",
      "</label>",
      "<input id=\"vz-iso-input\" class=\"vz-input vz-echo\" type=\"text\" name=\"iso\" ",
      "value=\"",
      Render.escape(input),
      "\" placeholder=\"2022-06-15 · 1984?/2004~ · 2022-11-20T10:30:00Z[Europe/Paris]\" ",
      "dir=\"ltr\" autocomplete=\"off\" spellcheck=\"false\" autofocus>",
      "<button type=\"submit\" class=\"vz-input-submit\" aria-label=\"Parse\">Parse</button>",
      "</form>",
      "</div>"
    ]
  end

  ## Examples card — always visible below the parsed info.
  ##
  ## Organised by family so a reader can scan from the familiar
  ## (plain calendar dates, datetimes) out to the rare / exotic
  ## shapes Tempo uniquely supports (selections, grouping, masks,
  ## long-year exponents). Each row is description first, example
  ## second — the reader sees the intent before the syntax.

  @example_groups [
    {"Dates and datetimes",
     [
       {"Calendar date", "2022-06-15"},
       {"ISO week date", "2022-W24-3"},
       {"Ordinal date (day-of-year)", "2022-166"},
       {"Datetime with UTC", "2022-06-15T10:30:00Z"},
       {"Datetime with offset", "2022-06-15T10:30:00+05:30"},
       {"Long year with exponent", "Y17E8"}
     ]},
    {"Intervals, durations, recurrence",
     [
       {"Closed interval", "2022-01-01/2022-06-30"},
       {"Open-ended interval", "1985/.."},
       {"Duration from start", "2022-01-01/P3M"},
       {"Recurring interval", "R5/2022-01-01/P1M"},
       {"Interval with per-endpoint qualification", "1984?/2004~"}
     ]},
    {"Seasons and quarters",
     [
       {"Northern spring (astronomical)", "2022-25"},
       {"Northern summer (astronomical)", "2022-26"},
       {"Southern spring (astronomical)", "2022-29"},
       {"First quarter", "2022Y1Q"},
       {"Third quarter", "2022Y3Q"},
       {"First half (semestral)", "2022Y1H"}
     ]},
    {"Grouping (ISO 8601-2 §5)",
     [
       {"Fifth ten-day group of the year", "5G10DU"},
       {"Four 60-day groups, day 6 of group 4", "2018Y4G60DU6D"}
     ]},
    {"Selection of days, weeks, months",
     [
       {"Every Monday in 2022", "2022YL1KN"},
       {"Every last day-of-week (Sunday)", "2022YL-1KN"},
       {"Last day of year (Dec 31)", "2022YL-1DN"},
       {"First month (January)", "2022YL1MN"}
     ]},
    {"Slots, sets, masks",
     [
       {"Month range as a slot", "2022Y{1..3}M"},
       {"Set of specific months", "2022Y{5,6,7}M"},
       {"Set of three years", "{1960,1961,1962}"},
       {"Unspecified decade", "156X-12-25"},
       {"Negative year, unspecified digits", "-1XXX-XX"}
     ]},
    {"EDTF and IXDTF",
     [
       {"Uncertain month (EDTF L2)", "2022-?06-15"},
       {"IXDTF with zone and calendar", "2022-11-20T10:30:00Z[Europe/Paris][u-ca=hebrew]"}
     ]}
  ]

  defp examples_card(base) do
    [
      "<div class=\"vz-card\">",
      "<h2>Examples</h2>",
      "<table class=\"vz-examples\">",
      "<tbody>",
      Enum.map(@example_groups, fn {group_name, rows} ->
        [
          "<tr class=\"vz-example-group\">",
          "<th colspan=\"2\">",
          Render.escape(group_name),
          "</th>",
          "</tr>",
          Enum.map(rows, fn {label, iso} ->
            [
              "<tr>",
              "<td class=\"vz-example-label\">",
              Render.escape(label),
              "</td>",
              "<td class=\"vz-example-iso\">",
              "<a href=\"",
              Render.escape(base),
              "/?iso=",
              URI.encode_www_form(iso),
              "\">",
              Render.escape(iso),
              "</a>",
              "</td>",
              "</tr>"
            ]
          end)
        ]
      end),
      "</tbody>",
      "</table>",
      "</div>"
    ]
  end

  ## Error

  defp error_card(reason) do
    [
      "<div class=\"vz-card vz-error\">",
      "<h2>Parse error</h2>",
      "<div class=\"vz-error-message\">",
      Render.escape(error_message(reason)),
      "</div>",
      "</div>"
    ]
  end

  defp error_message(reason) when is_exception(reason), do: Exception.message(reason)
  defp error_message(reason), do: inspect(reason)

  ## Segment breakdown
  ##
  ## The segments together reproduce the input string character-for-
  ## character — no canonicalisation, no hyphen-vs-designator
  ## rewrite. Each segment is a substring of the input, classified
  ## for syntax colouring and (where the AST has a matching slot)
  ## annotated with a human-readable label and detail.
  ##
  ## Strategy: tokenise the input into runs of same-class characters
  ## (reusing `classify_chars/1`), walk the AST to produce an ordered
  ## list of semantic slots (year, month, day, hour, shift, qualifier,
  ## zone, …), then pair them: the N-th *number* run in the input
  ## consumes the N-th numeric slot; qualifier characters consume
  ## qualifier slots; designator characters (Y, M, D, T, Z, …) stay
  ## unlabelled because their role is already obvious from the class
  ## colour.

  defp segments_card(input, value) do
    segments = annotate_input(input, value)

    [
      "<div class=\"vz-card\">",
      "<h2>Components</h2>",
      "<div class=\"vz-segments\">",
      Enum.map(segments, &render_segment/1),
      "</div>",
      "</div>"
    ]
  end

  # Walks the input string to produce segment maps whose `glyph`
  # fields taken together reconstitute the input verbatim, with
  # labels/details pulled from the parsed AST.
  defp annotate_input(input, value) do
    tokens = classify_chars(input)
    slots = semantic_slots(value)

    {segments, _remaining_slots} =
      Enum.reduce(tokens, {[], slots}, fn {class, text}, {acc, slots} ->
        {segment, slots} = attach_slot({class, text}, slots)
        {[segment | acc], slots}
      end)

    Enum.reverse(segments)
  end

  # Attach a slot to the current token if the token type expects
  # one. Number runs consume the next `:numeric` slot; qualifier
  # characters (`? ~ %`) consume the next `:qualifier` slot; a
  # lone `Z` consumes a `:shift` slot; everything else renders
  # unlabelled.
  defp attach_slot({"number", text}, slots) do
    case pop_slot(slots, :numeric) do
      {%{label: label, detail: detail, kind: kind}, rest} ->
        {%{glyph: text, label: label, detail: detail, kind: kind}, rest}

      {nil, slots} ->
        {%{glyph: text, label: "", detail: "", kind: "primary"}, slots}
    end
  end

  defp attach_slot({"qualifier", text}, slots) do
    case pop_slot(slots, :qualifier) do
      {%{label: label, detail: detail, kind: kind}, rest} ->
        {%{glyph: text, label: label, detail: detail, kind: kind}, rest}

      {nil, slots} ->
        {%{glyph: text, label: "", detail: "", kind: "qualification"}, slots}
    end
  end

  defp attach_slot({"literal", "Z"}, slots) do
    case pop_slot(slots, :shift) do
      {%{label: label, detail: detail, kind: kind}, rest} ->
        {%{glyph: "Z", label: label, detail: detail, kind: kind}, rest}

      {nil, slots} ->
        {%{glyph: "Z", label: "", detail: "", kind: "separator"}, slots}
    end
  end

  defp attach_slot({class, text}, slots) do
    {%{glyph: text, label: "", detail: "", kind: class_to_kind(class)}, slots}
  end

  defp class_to_kind("number"), do: "primary"
  defp class_to_kind("literal"), do: "separator"
  defp class_to_kind("qualifier"), do: "qualification"
  defp class_to_kind("syntax"), do: "extended"
  defp class_to_kind("bracket"), do: "separator"
  defp class_to_kind(_), do: "separator"

  # Pop the first slot tagged with the given `kind_tag`, returning
  # `{slot_map, remaining_slots}` or `{nil, slots}` if none match.
  # Non-matching slots at the head are preserved in order.
  defp pop_slot(slots, kind_tag) do
    case Enum.split_while(slots, fn {tag, _} -> tag != kind_tag end) do
      {before, [{^kind_tag, slot} | after_]} -> {slot, before ++ after_}
      {_, []} -> {nil, slots}
    end
  end

  defp render_segment(%{glyph: glyph, label: label, detail: detail, kind: kind}) do
    class = "vz-segment vz-segment--#{kind}"

    [
      "<div class=\"",
      class,
      "\">",
      "<div class=\"vz-glyph\">",
      colored_glyph(glyph),
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

  ## Syntax colouring for the glyph text.
  ##
  ## Each character is classified into one of five token classes
  ## (Molokai palette — see CSS):
  ##
  ##   * number    — `0-9`, decimal points, signs attached to numbers
  ##   * literal   — ISO designators (Y M D W H S T Z P R C J O K X)
  ##                  and zone/calendar string bodies
  ##   * qualifier — EDTF qualifiers `? ~ %`
  ##   * syntax    — selection/group markers `L N G U`
  ##   * bracket   — structural punctuation `{ } [ ] / .. , : -` etc.
  ##
  ## Adjacent same-class characters are merged into a single span so
  ## the rendered HTML stays compact.

  @literal_chars ~c"YMDWHSTZPRCJOKX"
  @qualifier_chars ~c"?~%"
  @syntax_chars ~c"LNGU"
  @bracket_chars ~c"{}[]()/,:-+.·="

  defp colored_glyph(text) when is_binary(text) do
    text
    |> classify_chars()
    |> Enum.map(fn {class, chunk} ->
      [
        "<span class=\"vz-token vz-token--",
        class,
        "\">",
        Render.escape(chunk),
        "</span>"
      ]
    end)
  end

  defp colored_glyph(other), do: Render.escape(to_string(other))

  # Walk the string, classifying each character, and merge runs of
  # the same class into a single chunk. Returns a list of
  # {class :: String.t(), chunk :: String.t()} pairs in order.
  defp classify_chars(text) do
    text
    |> String.graphemes()
    |> Enum.reduce([], fn g, acc ->
      class = char_class(g)

      case acc do
        [{^class, chunk} | rest] -> [{class, chunk <> g} | rest]
        _ -> [{class, g} | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp char_class(<<c>>) when c in ?0..?9, do: "number"

  defp char_class(g) when is_binary(g) do
    cond do
      single_char_in?(g, @literal_chars) -> "literal"
      single_char_in?(g, @qualifier_chars) -> "qualifier"
      single_char_in?(g, @syntax_chars) -> "syntax"
      single_char_in?(g, @bracket_chars) -> "bracket"
      # Anything else (spaces, letters inside zone ids, etc.) falls
      # through as a literal — we don't want neutral-white non-digit
      # blobs inside the coloured token stream.
      true -> "literal"
    end
  end

  defp single_char_in?(<<c>>, list), do: c in list
  defp single_char_in?(_, _), do: false

  ## Semantic slot extraction
  ##
  ## Walks the parsed AST and produces a flat ordered list of
  ## `{kind_tag, slot}` pairs. `kind_tag` is one of `:numeric`,
  ## `:qualifier`, `:shift` — the token aligner uses it to decide
  ## which input token each slot attaches to. `slot` is a map with
  ## `:label`, `:detail`, and `:kind` (the *rendering* kind, for
  ## the CSS class).
  ##
  ## Order matters. Slots are produced in the order their
  ## character positions appear in an ISO 8601 serialisation —
  ## recurrence first, then from-endpoint time fields, then
  ## from-endpoint shift/qualification, then the interval
  ## separator's trailing side, and so on.

  defp semantic_slots(%Tempo{} = tempo), do: tempo_slots(tempo)

  defp semantic_slots(%Tempo.Interval{from: from, to: to, duration: duration}) do
    endpoint_slots(from) ++ endpoint_slots(to || duration)
  end

  defp semantic_slots(%Tempo.Duration{time: time}) do
    Enum.flat_map(time, fn {_unit, _value} = item -> duration_unit_slots(item) end)
  end

  defp semantic_slots(%Tempo.Set{set: members}) do
    Enum.flat_map(members, fn
      %Tempo{} = t -> tempo_slots(t)
      {:range, [a, b]} -> endpoint_slots(a) ++ endpoint_slots(b)
      _ -> []
    end)
  end

  defp semantic_slots(_), do: []

  defp endpoint_slots(:undefined), do: []
  defp endpoint_slots(nil), do: []
  defp endpoint_slots(%Tempo{} = t), do: tempo_slots(t)
  defp endpoint_slots(%Tempo.Duration{} = d), do: semantic_slots(d)
  defp endpoint_slots(_), do: []

  defp tempo_slots(%Tempo{time: nil}), do: []

  defp tempo_slots(%Tempo{time: time} = tempo) when is_list(time) do
    time_slots =
      Enum.map(time, fn {unit, value} -> time_unit_slot(unit, value) end)

    time_slots ++
      shift_slots(tempo.shift) ++
      qualification_slots(tempo.qualification)
  end

  defp time_unit_slot(:year, value) do
    {_glyph, detail} = year_display(value)
    {:numeric, %{label: "Year", detail: detail, kind: "primary"}}
  end

  defp time_unit_slot(:month, value) do
    {_glyph, detail} = month_display(value)
    # `kind: "month"` widens the descriptor floor — month detail
    # strings ("September (month 9)", meteorological season names)
    # are the longest and would otherwise wrap.
    {:numeric, %{label: "Month", detail: detail, kind: "month"}}
  end

  defp time_unit_slot(:day, value) do
    {_glyph, detail} = day_display(value)
    {:numeric, %{label: "Day", detail: detail, kind: "primary"}}
  end

  defp time_unit_slot(:week, value) do
    {_glyph, detail} = integer_display(value, "W")
    {:numeric, %{label: "Week", detail: detail, kind: "primary"}}
  end

  defp time_unit_slot(:day_of_year, value) do
    {_glyph, detail} = integer_display(value, "")
    {:numeric, %{label: "Day of year", detail: detail, kind: "primary"}}
  end

  defp time_unit_slot(:day_of_week, value) do
    {_glyph, detail} = integer_display(value, "")
    {:numeric, %{label: "Day of week", detail: detail, kind: "primary"}}
  end

  defp time_unit_slot(:hour, value) do
    {_glyph, detail} = integer_display(value, "")
    {:numeric, %{label: "Hour", detail: detail, kind: "primary"}}
  end

  defp time_unit_slot(:minute, value) do
    {_glyph, detail} = integer_display(value, "")
    {:numeric, %{label: "Minute", detail: detail, kind: "primary"}}
  end

  defp time_unit_slot(:second, value) do
    {_glyph, detail} = integer_display(value, "")
    {:numeric, %{label: "Second", detail: detail, kind: "primary"}}
  end

  defp time_unit_slot(:century, value) do
    {_glyph, detail} = integer_display(value, "")
    {:numeric, %{label: "Century", detail: detail, kind: "primary"}}
  end

  defp time_unit_slot(:decade, value) do
    {_glyph, detail} = integer_display(value, "")
    {:numeric, %{label: "Decade", detail: detail, kind: "primary"}}
  end

  defp time_unit_slot(unit, value) do
    label = unit |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()
    {:numeric, %{label: label, detail: inspect(value), kind: "primary"}}
  end

  defp shift_slots(nil), do: []

  defp shift_slots(shift) when is_list(shift) do
    hour = Keyword.get(shift, :hour, 0)
    minute = Keyword.get(shift, :minute, 0)

    cond do
      hour == 0 and minute == 0 ->
        [{:shift, %{label: "Time shift", detail: "UTC", kind: "extended"}}]

      true ->
        sign = if hour >= 0, do: "+", else: "-"
        detail = "#{sign}#{abs(hour)}h#{if minute != 0, do: " #{minute}m", else: ""} from UTC"

        # Two numeric slots (hour, minute) because the input
        # writes them as two digit groups separated by `:`.
        [
          {:numeric, %{label: "Shift hour", detail: detail, kind: "extended"}},
          {:numeric, %{label: "Shift minute", detail: detail, kind: "extended"}}
        ]
    end
  end

  defp shift_slots(_), do: []

  defp qualification_slots(nil), do: []

  defp qualification_slots(qualification) do
    [
      {:qualifier,
       %{
         label: "Qualification",
         detail: qualifier_name(qualification),
         kind: "qualification"
       }}
    ]
  end

  defp duration_unit_slots({:direction, :negative}), do: []

  defp duration_unit_slots({unit, _value}) do
    label = unit |> Atom.to_string() |> String.capitalize()
    [{:numeric, %{label: label, detail: label, kind: "primary"}}]
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

  ## Qualification names (still used by the shift/qualifier slot
  ## builders and the Details card).

  defp qualifier_name(:uncertain), do: "Uncertain (?)"
  defp qualifier_name(:approximate), do: "Approximate (~)"
  defp qualifier_name(:uncertain_and_approximate), do: "Uncertain & approximate (%)"
  defp qualifier_name(other), do: to_string(other)

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
