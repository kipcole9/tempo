defmodule Tempo.Visualizer.Assets do
  @moduledoc false

  # Inlined CSS for the visualizer. Written as a module attribute so
  # the visualizer is a single file per asset and runs regardless of
  # the working directory.

  @css """
  /* -------------------------------------------------------------
     Colour tokens. One declaration block; everything else derives.
     ------------------------------------------------------------- */
  :root {
    --vz-bg: #0b0d10;
    --vz-surface: #15181d;
    --vz-surface-2: #1d2127;
    --vz-border: #2a2f37;
    --vz-rule: #3a4050;
    --vz-text: #e5e7eb;
    --vz-text-dim: #9ca3af;
    --vz-text-faint: #6b7280;
    --vz-accent: #60a5fa;
    --vz-ok: #22c55e;
    --vz-warn: #f59e0b;
    --vz-fail: #ef4444;
    --vz-uncertain: #c4b5fd;
    --vz-approximate: #fcd34d;

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
    align-items: baseline;
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
    font-size: 22px;
    line-height: 1;
  }
  .vz-subtitle {
    color: var(--vz-text-dim);
    font-size: 13px;
    align-self: center;
  }

  form.vz-form {
    display: flex;
    flex: 1 1 400px;
    gap: 10px;
    align-items: center;
    min-inline-size: 0;
  }

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

  .vz-input {
    flex: 1 1 auto;
    min-inline-size: 0;
    background: var(--vz-bg);
    color: var(--vz-text);
    border: 1px solid var(--vz-border);
    border-radius: var(--vz-radius);
    padding: 10px 14px;
    font-family: var(--vz-mono);
    font-size: 16px;
  }
  .vz-input:focus {
    outline: 2px solid var(--vz-accent);
    outline-offset: 1px;
    border-color: var(--vz-accent);
  }

  form.vz-form button {
    background: var(--vz-accent);
    color: #0b1220;
    border: 0;
    border-radius: var(--vz-radius);
    padding: 10px 18px;
    font-family: var(--vz-sans);
    font-size: 15px;
    font-weight: 600;
    cursor: pointer;
  }
  form.vz-form button:hover { filter: brightness(1.08); }

  /* -------------------------------------------------------------
     Main layout. Max-width keeps reading comfortable on wide
     monitors; padding at small screens uses clamp to breathe
     without stealing from mobile.
     ------------------------------------------------------------- */
  main.vz-main {
    padding: var(--vz-gap-lg) clamp(16px, 3vw, 28px);
    max-inline-size: 1200px;
    margin-inline: auto;
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

  /* -------------------------------------------------------------
     Echo of the parsed input in extra-large monospace. Shows the
     user exactly what was parsed, in case whitespace or quotes
     made something weird happen.
     ------------------------------------------------------------- */
  .vz-echo {
    font-family: var(--vz-mono);
    font-size: clamp(28px, 5vw, 48px);
    font-weight: 600;
    line-height: 1.15;
    color: var(--vz-text);
    word-break: break-all;
    letter-spacing: -0.01em;
  }

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

  .vz-segment .vz-glyph {
    font-size: clamp(22px, 3.5vw, 36px);
    font-weight: 600;
    color: var(--vz-text);
    line-height: 1.2;
    padding-block-end: 8px;
    white-space: pre;
  }

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
     Empty state: shown when there's no input yet. A list of
     clickable example strings that populate the input.
     ------------------------------------------------------------- */
  .vz-examples {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
  }
  .vz-examples a {
    background: var(--vz-surface-2);
    border: 1px solid var(--vz-border);
    border-radius: 8px;
    padding: 8px 12px;
    color: var(--vz-text);
    font-family: var(--vz-mono);
    font-size: 13px;
  }
  .vz-examples a:hover {
    background: var(--vz-border);
    text-decoration: none;
  }
  .vz-examples a span {
    color: var(--vz-text-dim);
    font-family: var(--vz-sans);
    font-size: 11px;
    margin-inline-start: 8px;
  }

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
  """

  @spec css() :: binary()
  def css, do: @css
end
