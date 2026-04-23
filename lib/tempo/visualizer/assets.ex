defmodule Tempo.Visualizer.Assets do
  @moduledoc false

  # Inlined CSS for the visualizer. Written as a module attribute so
  # the visualizer is a single file per asset and runs regardless of
  # the working directory.

  @css """
  /* -------------------------------------------------------------
     Colour tokens. One declaration block; everything else derives.

     The token-palette colours (numbers, literals, qualifiers,
     syntax, brackets) use the Molokai palette — the colouring
     the visualizer uses to separate character classes inside each
     ISO 8601 glyph.
     ------------------------------------------------------------- */
  :root {
    /* Backgrounds stay neutral/black — the Molokai-green background
       gave the whole page an olive cast. Surfaces lift via a
       subtle tint, not hue. */
    --vz-bg: #000000;
    --vz-surface: #141414;
    --vz-surface-2: #1d1d1d;
    --vz-border: #2a2a2a;
    --vz-rule: #4a4a4a;
    --vz-text: #f8f8f2;           /* Molokai default foreground */
    --vz-text-dim: #a6a69c;
    --vz-text-faint: #75715e;     /* Molokai comment colour */
    --vz-accent: #66d9ef;          /* Molokai cyan */
    --vz-ok: #a6e22e;              /* Molokai green */
    --vz-warn: #fd971f;            /* Molokai orange */
    --vz-fail: #f92672;            /* Molokai magenta */
    --vz-uncertain: #ae81ff;       /* Molokai purple */
    --vz-approximate: #e6db74;     /* Molokai yellow */

    /* Token classes inside a glyph. Numbers stay neutral (so they
       read as data, not syntax); literals pop; qualifiers warm;
       syntax markers cool; brackets/separators dim. */
    --vz-tok-number:    #f8f8f2;   /* neutral cream */
    --vz-tok-literal:   #66d9ef;   /* cyan — designators Y M D W H S T Z … */
    --vz-tok-qualifier: #fd971f;   /* orange — ? ~ % */
    --vz-tok-syntax:    #a6e22e;   /* green  — L N G U */
    --vz-tok-bracket:   #ae81ff;   /* purple — { } [ ] .. , / : - + */

    --vz-radius: 10px;
    --vz-gap: clamp(12px, 2vw, 20px);
    --vz-gap-lg: clamp(24px, 4vw, 40px);

    --vz-mono: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas,
               "Liberation Mono", monospace;
    --vz-sans: ui-sans-serif, system-ui, -apple-system, "Segoe UI",
               "Helvetica Neue", Arial, sans-serif;
  }

  /* -------------------------------------------------------------
     Every-Layout box primitive defaults. box-sizing applies to
     everything so padding never bursts an element's width; logical
     properties keep right-to-left inputs sane (we reserve dir='ltr'
     on the sample itself since ISO 8601 is LTR by spec).
     ------------------------------------------------------------- */
  *, *::before, *::after { box-sizing: border-box; }

  html, body {
    margin: 0;
    padding: 0;
    background: var(--vz-bg);
    color: var(--vz-text);
    font-family: var(--vz-sans);
    font-size: 15px;
    line-height: 1.5;
    -webkit-text-size-adjust: 100%;
  }

  body { min-block-size: 100vh; }

  a { color: var(--vz-accent); text-decoration: none; }
  a:hover { text-decoration: underline; }

  /* -------------------------------------------------------------
     Header: brand, subtitle, and the input form that is the
     visualizer's raison d'\u00EAtre. Large input, large button — so
     they read as primary affordances.
     ------------------------------------------------------------- */
  header.vz-header {
    position: sticky;
    inset-block-start: 0;
    z-index: 10;
    background: var(--vz-surface);
    border-block-end: 1px solid var(--vz-border);
    padding: clamp(12px, 2vw, 20px) clamp(16px, 3vw, 28px);
    display: flex;
    flex-wrap: wrap;
    gap: var(--vz-gap);
    align-items: center;
  }

  a.vz-brand {
    display: flex;
    align-items: center;
    gap: 10px;
    color: var(--vz-text);
    flex-shrink: 0;
  }
  a.vz-brand:hover { text-decoration: none; }
  a.vz-brand h1 {
    margin: 0;
    font-size: 18px;
    font-weight: 700;
    letter-spacing: -0.01em;
  }
  .vz-logo {
    inline-size: 28px;
    block-size: 28px;
    flex-shrink: 0;
    color: var(--vz-accent);
    display: block;
  }
  .vz-subtitle {
    color: var(--vz-text-dim);
    font-size: 13px;
    align-self: center;
  }

  /* The old header form is gone — the input lives inline in the
     first card on the page, styled as the primary echo text. */
  .vz-input-label {
    position: absolute;
    inline-size: 1px;
    block-size: 1px;
    padding: 0;
    margin: -1px;
    overflow: hidden;
    clip: rect(0, 0, 0, 0);
    white-space: nowrap;
    border: 0;
  }

  form.vz-form {
    display: flex;
    gap: 10px;
    align-items: stretch;
    min-inline-size: 0;
  }

  /* The input is styled like the old echo display — large, bold
     monospace — but it's editable and the Enter key submits. A
     secondary submit button is present for accessibility / mouse
     users but styled so it doesn't dominate the card. */
  .vz-input-card .vz-input {
    flex: 1 1 auto;
    min-inline-size: 0;
    background: transparent;
    color: var(--vz-text);
    border: 0;
    border-block-end: 2px solid var(--vz-border);
    border-radius: 0;
    padding: 6px 2px;
    font-family: var(--vz-mono);
    font-size: clamp(28px, 5vw, 48px);
    font-weight: 600;
    line-height: 1.15;
    letter-spacing: -0.01em;
  }
  .vz-input-card .vz-input:focus {
    outline: 0;
    border-block-end-color: var(--vz-accent);
  }
  .vz-input-card .vz-input::placeholder {
    color: var(--vz-text-faint);
    font-weight: 500;
  }

  .vz-input-submit {
    flex-shrink: 0;
    align-self: flex-end;
    background: var(--vz-accent);
    color: #1a1b16;
    border: 0;
    border-radius: var(--vz-radius);
    padding: 10px 18px;
    font-family: var(--vz-sans);
    font-size: 14px;
    font-weight: 600;
    cursor: pointer;
    margin-block-end: 6px;
  }
  .vz-input-submit:hover { filter: brightness(1.08); }

  /* -------------------------------------------------------------
     Main layout. Two columns on wide viewports (main content +
     permanent syntax reference); stack on narrow. Grid gives the
     reference a fixed right-hand width and lets the main column
     take the rest. Clamps keep everything breathing.
     ------------------------------------------------------------- */
  .vz-layout {
    display: grid;
    grid-template-columns: minmax(0, 1fr) minmax(320px, 420px);
    gap: 0;
    align-items: start;
    max-inline-size: 1600px;
    margin-inline: auto;
  }

  @media (max-width: 1100px) {
    .vz-layout {
      grid-template-columns: 1fr;
    }
  }

  main.vz-main {
    padding: var(--vz-gap-lg) clamp(16px, 3vw, 28px);
    min-inline-size: 0;
  }

  /* The "card" box pattern per every-layout: surface colour,
     border, generous inner padding, rounded corners. No margin
     collapse because padding does the work. */
  .vz-card {
    background: var(--vz-surface);
    border: 1px solid var(--vz-border);
    border-radius: var(--vz-radius);
    padding: clamp(16px, 3vw, 28px);
  }

  .vz-card + .vz-card { margin-block-start: var(--vz-gap); }

  .vz-card h2 {
    margin: 0 0 var(--vz-gap) 0;
    font-size: 12px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--vz-text-dim);
  }

  /* The former standalone echo card is gone — the editable input
     inside `.vz-input-card` now carries that role. The `.vz-echo`
     class is kept as a namespace-friendly hook on the input in
     case users want to restyle from userland. */

  /* -------------------------------------------------------------
     The segment breakdown.

     The breakdown is a flex row (wrapping on small screens) where
     each segment is a three-stack box:

       [ display text   ]   <- large monospace
       [ --------- | ]       <- underline + end-tick
       [ label         ]    <- small uppercase
       [ detail        ]    <- short description

     The underline is the box's border-block-end (so it only draws
     when the box is a visible container). The end-tick is a
     pseudo-element positioned at the right edge of the box.
     ------------------------------------------------------------- */
  .vz-segments {
    display: flex;
    flex-wrap: wrap;
    align-items: flex-start;
    gap: 0;
    font-family: var(--vz-mono);
  }

  .vz-segment {
    position: relative;
    display: flex;
    flex-direction: column;
    padding: 0 clamp(6px, 1vw, 12px) 22px clamp(6px, 1vw, 12px);
    min-inline-size: 0;
  }

  /* Months have the longest detail text (e.g. "September (month 9)"
     or "Meteorological season 24 — Winter") and benefit from a
     wider floor so the descriptor doesn't line-wrap. Applied via
     the `--month` kind modifier emitted by the view for :month
     time-unit segments. */
  .vz-segment--month {
    min-inline-size: 20ch;
  }

  /* Qualifier detail strings ("Uncertain (?)", "Approximate (~)",
     "Uncertain & approximate (%)") are long relative to their
     single-character glyph — give them a generous floor so they
     don't cramp the whole row. */
  .vz-segment--qualification {
    min-inline-size: 22ch;
  }

  .vz-segment .vz-glyph {
    font-size: clamp(22px, 3.5vw, 36px);
    font-weight: 600;
    color: var(--vz-text);
    line-height: 1.2;
    padding-block-end: 8px;
    white-space: pre;
  }

  /* Per-character token classes inside a glyph. Numbers stay
     neutral (the value itself, not syntax); the four other
     classes use distinct Molokai hues so the character roles
     read at a glance. */
  .vz-token { color: inherit; }
  .vz-token--number    { color: var(--vz-tok-number); }
  .vz-token--literal   { color: var(--vz-tok-literal); }
  .vz-token--qualifier { color: var(--vz-tok-qualifier); }
  .vz-token--syntax    { color: var(--vz-tok-syntax); }
  .vz-token--bracket   { color: var(--vz-tok-bracket); }

  /* Bracket-class tokens (`-` `:` `/` `+` ...) are visually
     separated from adjacent numeric/literal tokens so a leading
     `-` never reads as a negative-number sign when it's actually
     a date separator. A visible gap on both sides plus the
     distinct bracket colour makes the separator role unambiguous. */
  .vz-token--bracket { margin-inline: 0.6ch; }

  /* The underline and end-tick.

     The underline is a block-end border on the segment itself.
     The end-tick is an absolutely-positioned 1px × 10px bar whose
     top aligns with the border's top, giving the "|" at the end
     of each underline the user requested. */
  .vz-segment {
    border-block-end: 1px solid var(--vz-rule);
  }
  .vz-segment::after {
    content: "";
    position: absolute;
    inset-inline-end: 0;
    block-size: 10px;
    inline-size: 1px;
    background: var(--vz-rule);
    /* The border-block-end sits at `bottom: 22px` inside the 22px of
       bottom padding below. Align the tick so its bottom edge is
       flush with the underline (i.e. its top edge is 10px above). */
    inset-block-end: calc(22px - 10px);
  }

  /* The label and detail area below the underline. */
  .vz-segment .vz-descriptor {
    position: absolute;
    inset-block-end: 0;
    inset-inline-start: clamp(6px, 1vw, 12px);
    inset-inline-end: clamp(6px, 1vw, 12px);
    padding-block-start: 4px;
    display: flex;
    flex-direction: column;
    gap: 1px;
    font-family: var(--vz-sans);
    font-size: 11px;
    line-height: 1.25;
  }
  .vz-segment .vz-label {
    color: var(--vz-text-dim);
    text-transform: uppercase;
    letter-spacing: 0.08em;
    font-weight: 600;
  }
  .vz-segment .vz-detail {
    color: var(--vz-text);
    font-variant-numeric: tabular-nums;
  }

  /* Semantic highlights for specific segment kinds. */
  .vz-segment.vz-segment--qualification .vz-glyph { color: var(--vz-uncertain); }
  .vz-segment.vz-segment--extended .vz-glyph { color: var(--vz-accent); }
  .vz-segment.vz-segment--separator .vz-glyph { color: var(--vz-text-faint); font-weight: 400; }
  .vz-segment.vz-segment--separator { border-block-end-color: transparent; }
  .vz-segment.vz-segment--separator::after { display: none; }

  /* -------------------------------------------------------------
     Detail table for the full parse: every field of the Tempo
     struct in a clean two-column layout.
     ------------------------------------------------------------- */
  .vz-details {
    display: grid;
    grid-template-columns: auto 1fr;
    gap: 6px 16px;
    font-family: var(--vz-mono);
    font-size: 13px;
  }
  .vz-details dt {
    color: var(--vz-text-dim);
    text-transform: uppercase;
    letter-spacing: 0.06em;
    font-size: 11px;
    font-weight: 600;
    align-self: center;
  }
  .vz-details dd {
    margin: 0;
    color: var(--vz-text);
    word-break: break-all;
  }

  /* -------------------------------------------------------------
     Error card. Separate styling so parse failures are
     unmistakable — same box pattern, tinted border.
     ------------------------------------------------------------- */
  .vz-card.vz-error {
    background: color-mix(in oklch, var(--vz-fail) 10%, var(--vz-surface));
    border-color: var(--vz-fail);
  }
  .vz-card.vz-error h2 { color: #fecaca; }
  .vz-card.vz-error .vz-error-message {
    font-family: var(--vz-mono);
    font-size: 14px;
    color: #fecaca;
    white-space: pre-wrap;
    word-break: break-word;
  }

  /* -------------------------------------------------------------
     Examples table. Grouped by family (dates, intervals, seasons,
     grouping, selections, sets, EDTF/IXDTF). Description first,
     click-to-load ISO string second.
     ------------------------------------------------------------- */
  table.vz-examples {
    inline-size: 100%;
    border-collapse: collapse;
    font-size: 13px;
  }

  .vz-examples tr.vz-example-group > th {
    text-align: start;
    padding: 18px 0 6px 0;
    font-family: var(--vz-sans);
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--vz-text-dim);
    border-block-end: 1px solid var(--vz-border);
  }

  .vz-examples tr.vz-example-group:first-child > th {
    padding-block-start: 0;
  }

  .vz-examples tbody > tr:not(.vz-example-group):hover {
    background: var(--vz-surface-2);
  }

  .vz-examples td {
    padding: 6px 10px;
    vertical-align: top;
  }

  .vz-examples .vz-example-label {
    color: var(--vz-text);
    font-family: var(--vz-sans);
    inline-size: 45%;
  }

  .vz-examples .vz-example-iso {
    font-family: var(--vz-mono);
    color: var(--vz-text-dim);
  }

  .vz-examples .vz-example-iso a {
    color: var(--vz-accent);
    text-decoration: none;
    word-break: break-all;
  }
  .vz-examples .vz-example-iso a:hover { text-decoration: underline; }

  /* -------------------------------------------------------------
     Footer. Tiny, unobtrusive attribution.
     ------------------------------------------------------------- */
  .vz-footer {
    margin-block-start: var(--vz-gap-lg);
    padding-block: 16px;
    border-block-start: 1px solid var(--vz-border);
    color: var(--vz-text-faint);
    font-size: 12px;
    text-align: center;
  }

  /* -------------------------------------------------------------
     Permanent syntax reference — right column of the main grid
     on wide viewports, stacked below on narrow. Sticky within
     its track so it stays visible while the main column scrolls.
     ------------------------------------------------------------- */
  aside.vz-syntax-panel {
    position: sticky;
    /* The sticky anchor and the initial top offset both match
       `main.vz-main`'s top padding so the panel's top edge aligns
       with the input card inside the main column, both at rest
       and once the user scrolls and sticky kicks in. */
    inset-block-start: var(--vz-gap-lg);
    margin-block-start: var(--vz-gap-lg);
    align-self: start;
    block-size: calc(100vh - var(--vz-gap-lg));
    background: var(--vz-surface);
    border-inline-start: 1px solid var(--vz-border);
    overflow-y: auto;
    display: flex;
    flex-direction: column;
  }

  @media (max-width: 1100px) {
    aside.vz-syntax-panel {
      position: static;
      block-size: auto;
      margin-block-start: 0;
      border-inline-start: 0;
      border-block-start: 1px solid var(--vz-border);
    }
  }

  .vz-syntax-panel__header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: clamp(14px, 2vw, 20px) clamp(16px, 2.5vw, 22px);
    border-block-end: 1px solid var(--vz-border);
    position: sticky;
    inset-block-start: 0;
    background: var(--vz-surface);
    z-index: 1;
  }
  .vz-syntax-panel__header h2 {
    margin: 0;
    font-size: 13px;
    font-weight: 700;
    color: var(--vz-text);
    text-transform: uppercase;
    letter-spacing: 0.06em;
  }

  .vz-syntax-panel__body {
    padding: clamp(14px, 2vw, 20px) clamp(16px, 2.5vw, 22px) clamp(28px, 4vw, 40px);
    font-size: 13px;
    line-height: 1.6;
  }

  .vz-syntax-intro,
  .vz-syntax-outro {
    color: var(--vz-text-dim);
    margin-block: 0 16px;
  }
  .vz-syntax-outro { margin-block: 24px 0; }

  .vz-syntax-panel h3 {
    margin: 22px 0 6px;
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--vz-accent);
  }
  .vz-syntax-panel h3:first-of-type { margin-block-start: 8px; }

  table.vz-syntax-table {
    inline-size: 100%;
    border-collapse: collapse;
  }
  .vz-syntax-table td {
    padding: 4px 8px 4px 0;
    vertical-align: top;
  }
  .vz-syntax-label {
    color: var(--vz-text);
    font-family: var(--vz-sans);
    inline-size: 45%;
  }
  .vz-syntax-iso code {
    font-family: var(--vz-mono);
    color: var(--vz-tok-literal);
    background: var(--vz-bg);
    padding: 2px 6px;
    border-radius: 4px;
    font-size: 12px;
  }
  """

  # The return is a known-length literal, but we expose it as
  # `String.t()` so callers are free to treat it as an opaque blob.
  # The supertype warning is suppressed with `@dialyzer` rather than
  # tightening the spec to a bitstring-size pattern that would be
  # meaningless to humans.
  @dialyzer {:nowarn_function, css: 0}

  @spec css() :: String.t()
  def css, do: @css
end
