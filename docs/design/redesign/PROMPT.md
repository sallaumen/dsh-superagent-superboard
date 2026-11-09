# Prompt — implement the Agent Board redesign

You will implement a visual and layout refinement of the **Agent Board**, the local panel (Phoenix LiveView,
127.0.0.1:4099) that operates the DeepSeek Super Agent and dispatches Claude Code and Codex. The design is
done; your job is to bring it into the existing code without breaking what works.

## Material

Everything is in `docs/design/redesign/` (unzipped from the zip):

- `PROMPT.md` — this file.
- `DESIGN.md` — **read first.** CSS tokens (light/dark), Tailwind/daisyUI mapping, grid per width, rules for
  each component, sync states, motion rules, accessibility, copy and hypotheses.
- `BRIEF.md` — the original brief with the product's functional map. It is the reference for what **exists**.
- `design-system/README.md` and `design-system/tokens.json` — the Agent Board design system (source of truth
  for color, type, space, voice and glyphs).
- `frames/*.dc.html` — the 13 design frames. They are HTML with inline styles: open them in the browser or read
  the code. Ignore `<x-dc>`, `<helmet>`, `support.js` and `<script type="text/x-dc">` (they belong to the design
  editor); what matters is the markup and the styles inside them. Colors are literal hex; in the code use the
  tokens from `DESIGN.md`.
- `renders/*.png` — a capture of each frame, for visual comparison.
- `reference/board-atual-1920.png` and `reference/superagentes-atual.png` — how the board looks today.

Frames: `Main` (1920 board, working, dark), `Board1366Offline` (1366, no connection, light), `Board2560Idle`
(2560 idle), `Board390` (mobile), `Inspector`, `Composer` (split request), `Superagentes`, `Voz`,
`Configuracoes` (+ shortcuts), `Hoje`, `Componentes` (states of each piece), `Sincronia`, `Grade`.

## Rules

1. **The frames are direction, not contract.** Most of them make sense and should be followed. If something on
   a screen does not make sense against the real code (data the board does not have, a flow that does not
   exist, a control that contradicts current behavior), **ignore that part** and follow the rest. Note what you
   ignored and why.
2. **Superagent limitations.** The DeepSeek Super Agent may not expose some data or actions that appear in the
   frames (e.g. current step in real time, phases, closed tickets, worker scale, desired vs actual state,
   classified failure). If there is no source, **do not invent**: show the honest state that `DESIGN.md`
   provides for (`?` with reason, `—`, or hide the element) or leave it out. Do not create fake endpoints or
   simulated data.
3. **Do not invent features.** Preserve the functional structure of `BRIEF.md`. Items marked "hypothesis" in
   `DESIGN.md` §9 **must not** be implemented now; just list them in the final summary if you think one is
   trivial.
4. **Sample data in the frames is examples.** Issue numbers, titles, values and the `o_colmex` PR titles are
   illustrative. Always use real data.
5. **Stack.** Phoenix LiveView + HEEx + Tailwind (+ daisyUI only for behavior: dropdown, modal, tabs, toggle).
   No new UI libraries, no React. Function components in `core_components` or a board component module,
   following the conventions already in the project.
6. **Data honesty comes before aesthetics.** Never show `0` for unknown; `≥` for minimums; clocks only run with
   live sync; ages become absolute time without a connection.
7. **Motion.** Only the agent dot breathes (and only live) and layers enter/exit. Data arriving via
   PubSub/stream swaps in place, without animation. `prefers-reduced-motion` zeroes everything.

## How to work

1. **Explore before touching.** Read `DESIGN.md`, look at the renders, then map the code: root layout,
   board/inspector/composer/hoje/superagentes/voz/configurações LiveViews, components, `app.css`,
   `tailwind.config.js`, current daisyUI theme, tests. Write a short plan (files to touch, order, risks) and
   what you already know you will not be able to do due to data limitations.
2. **Small slices, each green.** Suggested order, one commit (or PR) per slice:
   1. Light/dark CSS tokens + Tailwind + IBM Plex fonts; replace literal colors with tokens. No layout yet.
   2. Primitives: StatusMark (glyph + word), buttons (primary, secondary, discreet, destructive, disabled with
      reason), sync beacon, kbd, single focus ring.
   3. Board layout: rail, top, context (objectives + day summary), lanes in the grid per width (`DESIGN.md`
      §3), "Precisa de você" right below "Agora", Vazão (Throughput) as a strip below the lanes.
   4. States: empty, loading, error, idle (lanes collapse into one row on wide screens), no connection (strip,
      `≥`, frozen clocks, hatching), reconnected (toast).
   5. Inspector (header, actions with inline confirmation, tabs, executions with cost per executor, dispatch).
   6. Composer (steps, executor in radio-cards, split review, confirmation sentence, receipt).
   7. Superagentes (table; archive in the ⋯ menu far from Pausar/Parar; add project inline with review).
   8. Voz, Configurações, Atalhos, Hoje.
   9. Mobile (390) and 768.
3. **Tests.** Keep the suite green on every slice. Adjust LiveView tests that depend on text/selectors that
   changed; add tests for the honest states (unknown → `?`, no connection → `≥`, idle) and for the
   confirmations (stop execution, archive).
4. **Verify visually.** Run the app and compare with the renders at 390, 1366, 1920 and 2560, light and dark
   themes. Check contrast (≥ 4.5:1 on text), visible focus on everything clickable, tab order, and
   `prefers-reduced-motion`.
5. **Do not change behavior** (sync, dispatch, voice, ceilings) unless the layout requires it; if it does, stop
   and explain first.

## Delivery

At the end, a summary with: what was implemented per slice; what was left out and why (frame that did not make
sense, superagent limitation, missing data); §9 hypotheses that seemed trivial; and screenshots of the main
screens at the widths above.
