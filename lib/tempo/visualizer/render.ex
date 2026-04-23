defmodule Tempo.Visualizer.Render do
  @moduledoc false

  # Shared HTML helpers. Pure functions, no templates, iodata in /
  # iodata out. All literal markup is written as double-quoted
  # strings so it's immune to Elixir's sigil-vs-keyword edge cases.

  @doc "HTML-escapes a binary or iodata."
  @spec escape(iodata()) :: iodata()
  def escape(iodata) when is_list(iodata), do: Enum.map(iodata, &escape/1)

  def escape(binary) when is_binary(binary) do
    binary
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  def escape(other), do: escape(to_string(other))

  @doc """
  Wraps the supplied body iodata in the full HTML page chrome.

  ### Options

  * `:title` — page title (required).

  * `:body` — iodata for the page body (required).

  * `:base` — base URL prefix (e.g. `""` or `"/visualize"`) used to
    resolve asset and form links (required).

  * `:input` — the current ISO 8601 input string for the top form
    (defaults to `""`).

  """
  def page(assigns) do
    title = Keyword.fetch!(assigns, :title)
    body = Keyword.fetch!(assigns, :body)
    base = Keyword.fetch!(assigns, :base)
    input = Keyword.get(assigns, :input, "")

    [
      "<!doctype html><html lang=\"en\"><head>",
      "<meta charset=\"utf-8\">",
      "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
      "<title>",
      escape(title),
      " — Tempo ISO 8601 Visualizer</title>",
      "<link rel=\"stylesheet\" href=\"",
      escape(base),
      "/assets/style.css\">",
      "</head><body>",
      header(base, input),
      "<div class=\"vz-layout\">",
      "<main class=\"vz-main\">",
      body,
      footer(),
      "</main>",
      syntax_panel(),
      "</div>",
      "</body></html>"
    ]
  end

  defp header(base, _input) do
    [
      "<header class=\"vz-header\">",
      "<a class=\"vz-brand\" href=\"",
      escape(base),
      "/\">",
      logo_svg(),
      "<h1>Tempo</h1>",
      "<span class=\"vz-subtitle\">ISO 8601 Visualizer</span>",
      "</a>",
      "</header>"
    ]
  end

  # Permanent right-column syntax reference. Appears beside the
  # main content on wide viewports and stacks below on narrow
  # ones. Purely presentational — no toggle, always visible.
  defp syntax_panel do
    [
      "<aside class=\"vz-syntax-panel\" aria-labelledby=\"vz-syntax-title\">",
      "<div class=\"vz-syntax-panel__header\">",
      "<h2 id=\"vz-syntax-title\">ISO 8601 syntax reference</h2>",
      "</div>",
      "<div class=\"vz-syntax-panel__body\">",
      syntax_panel_body(),
      "</div>",
      "</aside>"
    ]
  end

  defp syntax_panel_body do
    [
      "<p class=\"vz-syntax-intro\">",
      "ISO 8601 specifies three representation styles. Each is ",
      "supported by Tempo and round-trips through the parser.",
      "</p>",
      syntax_section("Implicit (compact, no separators)", [
        {"YYYYMMDD", "20220615"},
        {"YYYYMMDDTHHMMSS", "20220615T103000"},
        {"YYYYMMDDTHHMMSSZ", "20220615T103000Z"},
        {"YYYY-Www-D (week date, hyphenated)", "2022-W24-3"},
        {"YYYY-DDD (ordinal)", "2022-166"}
      ]),
      syntax_section("Extended (human-readable, hyphenated)", [
        {"YYYY-MM-DD", "2022-06-15"},
        {"YYYY-MM-DDTHH:MM:SS", "2022-06-15T10:30:00"},
        {"YYYY-MM-DDTHH:MM:SS±HH:MM", "2022-06-15T10:30:00+05:30"},
        {"YYYY-MM-DD/YYYY-MM-DD", "2022-01-01/2022-06-30"},
        {"YYYY-MM-DD/PnYnMnD", "2022-01-01/P3M"}
      ]),
      syntax_section("Explicit (ISO 8601-2 §4.3 — designator-per-unit)", [
        {"YEARY", "2022Y"},
        {"YEARY MONTHM", "2022Y6M"},
        {"YEARY MONTHM DAYD", "2022Y6M15D"},
        {"Quarter: YEARY nQ", "2022Y3Q"},
        {"Half (semester): YEARY nH", "2022Y1H"},
        {"Century / decade", "20C · 202J"},
        {"Slot / range", "2022Y{1..3}M · 2022Y{5,7,9}M"}
      ]),
      syntax_section("EDTF qualifications (ISO 8601-2 §8)", [
        {"Uncertain", "2022?"},
        {"Approximate", "2022~"},
        {"Uncertain & approximate", "2022%"},
        {"Component-level", "2022-?06-15"}
      ]),
      syntax_section("IXDTF extensions (RFC 9557)", [
        {"Zone", "2022-06-15T10:30:00Z[Europe/Paris]"},
        {"Calendar", "2022-06-15[u-ca=hebrew]"},
        {"Both", "2022-06-15T10:30:00Z[Europe/Paris][u-ca=hebrew]"}
      ]),
      syntax_section("Selection and grouping (ISO 8601-2 §5, §12)", [
        {"Selection: L <rule> N", "2022YL1KN"},
        {"Grouping: nG <unit> U", "2018Y4G60DU6D"},
        {"Unspecified digits (mask)", "156X · 1985-XX-15"}
      ]),
      syntax_section("Duration and recurrence (ISO 8601-1 §5.5, §5.6)", [
        {"Duration", "P1Y6M3DT4H"},
        {"Recurring", "R5/2022-01-01/P1M"},
        {"Infinite recurrence", "R/2022-01-01/P1M"}
      ]),
      "<p class=\"vz-syntax-outro\">",
      "See Tempo's ",
      "<a href=\"https://hexdocs.pm/ex_tempo/iso8601-conformance.html\">",
      "ISO 8601 conformance guide",
      "</a>",
      " for the full table.",
      "</p>"
    ]
  end

  defp syntax_section(title, rows) do
    [
      "<h3>",
      escape(title),
      "</h3>",
      "<table class=\"vz-syntax-table\"><tbody>",
      Enum.map(rows, fn {label, iso} ->
        [
          "<tr>",
          "<td class=\"vz-syntax-label\">",
          escape(label),
          "</td>",
          "<td class=\"vz-syntax-iso\"><code>",
          escape(iso),
          "</code></td>",
          "</tr>"
        ]
      end),
      "</tbody></table>"
    ]
  end

  defp footer do
    [
      "<div class=\"vz-footer\">",
      "Powered by ",
      "<a href=\"https://hexdocs.pm/tempo\">Tempo</a>",
      " — ISO 8601 Parts 1 &amp; 2 and ",
      "<a href=\"https://www.ietf.org/archive/id/draft-ietf-sedate-datetime-extended-09.html\">IXDTF</a>",
      "</div>"
    ]
  end

  # Inlined Tempo mark. `currentColor` lets it inherit the brand
  # anchor's colour so it matches the wordmark without a separate
  # asset round-trip.
  defp logo_svg do
    """
    <svg class="vz-logo" viewBox="0 0 256 256" aria-hidden="true"
         fill="none" stroke="currentColor" stroke-width="24"
         stroke-linecap="round" stroke-linejoin="round">
      <path d="M 88 56 H 56 V 200 H 88"/>
      <circle cx="128" cy="128" r="18" fill="currentColor" stroke="none"/>
      <path d="M 168 56 Q 212 128 168 200"/>
    </svg>
    """
  end
end
