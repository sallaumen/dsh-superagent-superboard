# Agent Board — DESIGN.md

Base: the **Agent Board** design system (tokens, voice, glyphs) remains the source of truth. This file is the
delta for the current board and the bridge to LiveView + HEEx + Tailwind/daisyUI. No new libraries.

## 1. What changes from the current board

| Today | Becomes | Why |
|---|---|---|
| Cold gray, pure black | warm `paper` in both themes | Calm for hours; the DS already decided this |
| 8 throughput tiles in boxes, mid-screen | A strip of 8 cells divided by hairlines, **below the lanes** | Throughput is telemetry; the decision is the lanes |
| "Precisa de você" at the bottom of the page (y≈750 to 1920) | Right below "Agora" (Now), in the 1st column, above the fold | It is the only lane that asks for your action |
| Objectives in two stacked boxes | Rows with a hairline, 4 px bar, mono count on the right; a completed one recedes to an `ink-muted` row | Less box, same information |
| "SUPERAGENTES" in all caps + repeated "Superagentes DeepSeek" | One title in normal case | DS rule: no spaced capitals |
| Agent cards inside a modal (box inside a box) | Table: one row per project | Compare 2 projects side by side; aligned actions |
| "Remover" glued to "Parar" | "Arquivar" in the ⋯ menu, far from Pausar/Parar | Destructive never next to the common |
| "ligado" twice (badge + desired) | "Ligado · como desejado"; divergence becomes a tile: "Parado · desejado ligado" | Show only what informs |
| "Parar / Arquivar" as colored links in the inspector | Buttons; Parar in a tile outline with inline confirmation | 32–44 px target, visible focus |
| Loose "−7", "+13" deltas | Same numbers + "comparado com a hora anterior" (compared with the previous hour) in the strip header | A delta without a reference is noise |

## 2. Tokens

Copy into `assets/css/app.css`. Dark is `[data-theme="dark"]`; light is the default.

```css
:root {
  --paper:#f6f4ef; --paper-sunk:#eeebe4; --surface:#fdfcf9; --surface-raised:#ffffff;
  --line:#e3ded4; --line-strong:#8a8275;
  --ink:#1f1d1a; --ink-muted:#5c564d; --ink-faint:#6f685e;
  --agent:#2c6a4d; --agent-wash:#e2eee6; --on-agent:#ffffff;
  --you:#2f4f9e;   --you-wash:#e7ecf8;   --on-you:#ffffff;
  --halt:#a8401a;  --halt-wash:#f8e7dd;  --on-halt:#ffffff;
  --stale:#7f5a08; --stale-wash:#f5edd8;
  --focus-ring:var(--you);
  --shadow-layer:0 1px 2px rgba(31,29,26,.06),0 8px 24px rgba(31,29,26,.08);
  --font-sans:"IBM Plex Sans",ui-sans-serif,system-ui,sans-serif;
  --font-mono:"IBM Plex Mono",ui-monospace,"SF Mono",Menlo,monospace;
}
[data-theme="dark"] {
  --paper:#171614; --paper-sunk:#121110; --surface:#201e1b; --surface-raised:#292723;
  --line:#34312c; --line-strong:#7d756a;
  --ink:#ece8e1; --ink-muted:#aaa398; --ink-faint:#958e83;
  --agent:#7cc29d; --agent-wash:#1d2c24; --on-agent:#0e1d15;
  --you:#a3b7ef;   --you-wash:#1e2538;   --on-you:#111a33;
  --halt:#f09670;  --halt-wash:#36211a;  --on-halt:#2a130b;
  --stale:#dcb15e; --stale-wash:#2d2616;
  --shadow-layer:0 1px 2px rgba(0,0,0,.4),0 12px 32px rgba(0,0,0,.45);
}
```

`--on-halt` is new (filled destructive confirmation button). Divider hairline inside `agent-wash`:
`#2b3f33` dark / `#c9dccf` light.

Tailwind (`tailwind.config.js` → `theme.extend`): `colors: { paper:'var(--paper)', 'paper-sunk':'var(--paper-sunk)', surface:'var(--surface)', raised:'var(--surface-raised)', line:'var(--line)', 'line-strong':'var(--line-strong)', ink:'var(--ink)', muted:'var(--ink-muted)', faint:'var(--ink-faint)', agent:'var(--agent)', 'agent-wash':'var(--agent-wash)', you:'var(--you)', 'you-wash':'var(--you-wash)', halt:'var(--halt)', 'halt-wash':'var(--halt-wash)', stale:'var(--stale)', 'stale-wash':'var(--stale-wash)' }`.
daisyUI: map in the installed version's theme `primary→you`, `success→agent`, `error→halt`, `warning→stale`,
`base-100→paper`, `base-200→paper-sunk`, `base-300→line`, `base-content→ink`. Use daisyUI only for
behavior (`dropdown`, `modal`, `tabs`, `toggle`); the look comes from the tokens.

### Type (Plex Sans for reading, Plex Mono only for machine data, always `tabular-nums`)

| Name | Size/line | Weight | Use |
|---|---|---|---|
| display | 26/32 | 600, −0.01em | repository name, once per screen |
| title | 16/22 | 600 | section, panel |
| task | 14.5/21 | 500 | task title in lists |
| body | 14/21 | 400 | conversation, summary |
| meta | 12.5/18 | 400 | reason, metadata |
| label | 12/16 | 600 | label, count — normal case |
| data | 12.5/18 mono | 450 | time, duration, cost, path |
| data-lg | 22/28 mono | 400 | throughput cell value (new) |
| data-small | 11.5/16 mono | 450 | #number, kbd |

### Space and shape

`space-1..8` = 2, 4, 8, 12, 16, 24, 40, 64 px. Radius: 6 controls · 10 attention cards and focused row ·
16 panel, composer, Agora strip · 999 beacon and filters. Shadow only on what floats.

## 3. Grid and density

| Width | Structure |
|---|---|
| 390 | No rail (repository becomes a selector at the top). One column: summary → Agora → Precisa de você → Fila (Queue). Mesclados (Merged), Vazão (Throughput) and Resumo do dia (Day summary) become one-line `<details>`. Fixed bottom bar: Novo pedido + voice (48 px). Gutter 16. |
| 768 | Rail collapses to 56 px (icon + marks). One lane column; Mesclados below. Inspector takes the screen. |
| 1366 | Rail 224. Lanes in 2 columns `3fr 2fr`: [Agora, Precisa, Fila] · [Mesclados, Vazão 2×2]. Inspector floats (below 1240 px of content). |
| 1920 | Context in `7fr 5fr` (objectives · day summary). Lanes in 3 columns `5fr 4fr 3fr`: [Agora + Precisa] · [Fila] · [Mesclados]. Vazão in an 8-cell strip below. Inspector 440 px pushes the content. |
| 2560 | Same layout as 1920 with gutter 48 and inspector 520. **Idle**: the four lanes collapse into a single row; below, a 7-day history in 7 columns and the throughput strip showing 24 h/7 d. Back to lanes when something comes in. |
| 3440 and wider | No width cap: the board fills `main`. From 2500 px of content the same document sits in two panes. Left: header, summary, context, lanes (two columns, three from 2860 px) and Vazão in 4 × 2 under them. Right: Mesclados, seven days with up to eight merges each instead of three. Below 2500 px (a 2560 window) the single flow fills the width. |

Reading width: running text (summary, conversation, reasons) ≤ 760 px / ~80 characters, even at 2560.
Gaps: 40 between columns and sections, 32 between blocks in a column, 12 between a section title and its
content.
List row: 10–12 px vertical; minimum target 32 px on desktop, 44 px on touch.

## 4. Components (short rules)

- **Beacon**: a pill glued to the repository name. Only "Ao vivo" animates. Amber for stale data; never red.
- **Agora strip**: `agent-wash`, radius 16. Run card = status + #id + executor · title · real step in mono
  `agent` · phases (✓ done, ● current, ○ upcoming). Failure on retry: ■ tile glyph + "tentativa n de m"
  (attempt n of m) + countdown. Silence: hatched glyph + "sem saída há N min" (no output for N min), and it
  also enters Precisa de você.
- **Attention item**: `surface` + `line`, radius 10. Line 1: glyph ◆/■ + type + #id + age (+ **new**).
  Line 2: title. Line 3: reason with cause. One primary action on the right. Order: CI on main → block →
  review → question → silence. Separator "antes da sua última visita" (before your last visit).
- **Queue row**: number · ○ · #id + title · age. Selected = `you-wash` radius 10. Text marks "possível
  repetida" (possible duplicate; amber) and "dividida" (split; muted). Filters as pills with `aria-pressed`.
- **Merge row**: ✓ · #id + title · "CI ✓/?/falhou · revisão · hora" (CI ✓/?/failed · review · time). Failed CI
  swaps ✓ for ■ tile.
- **Throughput cell**: label · data-lg value + unit + delta · sparkline 20 px, 1.5 px `ink-muted` stroke ·
  24 h/7 d. Four truths: measured (no mark), estimated ("≥" + sentence), unknown ("?" + dashed glyph +
  reason), no data ("—"). Never 0 for unknown.
- **Inspector**: header (status, title, #id · age · type · size · link), actions as buttons (Perguntar, Tentar
  de novo, Parar execução in a tile, Arquivar as a discreet button), inline confirmation in `halt-wash` with
  the sentence and two named buttons ("Parar execução" / "Continuar rodando" (Keep running)). Tabs with
  counts; `1–5` switches. Cost per executor, never summed. Dispatch: executor in a radio-card with suggestion
  and reason, ceiling, time, monthly ceiling balance, button named after the executor.
- **Composer**: `surface-raised` dialog, radius 16, steps Pedido · Revisar · Recibo (Request · Review ·
  Receipt). Executor in 3 radio-cards (suggestion, reason, expected cost in its own currency). Split in rows
  with checkbox, type and size (P/M/G); a possible duplicate comes unchecked. Footer = confirmation sentence
  with numbers + "Criar N tarefas" (Create N tasks). Receipt: created · already in the queue · failures with
  reason and "Tentar de novo".
- **Superagentes**: table (Projeto + state dir · Estado · Workers stepper · Profile · porta (port) · Última
  leitura · Pausar/Parar/⋯). "Adicionar projeto" is an inline form with a review sentence and "Adicionar e
  iniciar" (Add and start).
- **Voz**: history in bubbles (`you-wash` you, `agent-wash` board); spoken confirmation in `halt-wash` with
  buttons; "Bastidores" as a list of steps with time; "O que posso pedir" grouped; the day's voice spend vs
  ceiling.
- **Configurações**: dialog with side navigation; sections in the order of the current menu; explicit save.
- **Hoje**: one list; repository as a fixed 120 px column; glyph legend at the bottom.

## 5. Sync

Table labels follow the viewer's board language. English is the initial choice;
Brazilian Portuguese remains available in Settings. The original Portuguese
labels in the brief are historical references: Ao vivo (Live), Atrasado (Delayed),
Reconectando (Reconnecting), Sem conexão (No connection), Sem dados (No data).

| | Live | Delayed | Reconnecting | No connection | No data |
|---|---|---|---|---|---|
| Beacon | ● breathes | ○ amber + "data from HH:MM · N min ago" | ◌ dashed amber + "attempt N" | hatched + `stale-wash` | ◌ neutral dashed |
| Clocks | run | run | stop | "last seen at" | — |
| Counts | exact | exact | exact | "≥" | — |
| Ages | relative | relative | relative | absolute | — |
| Top strip | — | — | — | yes + "Try now" | — |
| Now card | normal | normal | normal | hatched, dashed border | empty "—" |

On reconnect: a toast "Reconectado. N mudanças desde HH:MM." (Reconnected. N changes since HH:MM.) +
"Mostrar" (Show; marks **new**). It disappears in 8 s or Esc.

## 6. Motion

| Animates | How |
|---|---|
| Agent dot | opacity 1 → .35, 2.4 s, only with live sync |
| Layers (inspector, composer, menus, toast) | enter 180–220 ms, `translateY(4px)` + opacity, `cubic-bezier(.2,0,0,1)`; exit 120 ms |
| Item state change (queue → running → merged) | color and glyph swap in 150 ms; the row does not move on its own |
| Objective bar | width in 300 ms when it changes through your action |

**Does not animate**: data arriving by broadcast (PubSub) — swap the text in place, no fade, no progressive
count; queue reordering; sparkline; skeleton (static, no shimmer); beacon outside "Ao vivo".
Nothing blocks action: buttons respond during any transition.
`prefers-reduced-motion: reduce` → all durations 0 and the dot stays still; feedback continues through text
(the beacon says "Ao vivo", the button says "Parando…" (Stopping…)).

LiveView: `phx-mounted`/`JS.transition` only on layers; stream updates without animated `phx-update`.

## 7. Accessibility

- Text ≥ 4.5:1 on all backgrounds (tokens already pass); control borders `line-strong` ≥ 3:1.
- One focus ring: 2 px `focus-ring`, offset 2 px. Tab order: rail → top → context → Agora → Precisa → Fila →
  Mesclados → Vazão. `J/K` moves through tasks in screen order, `Enter` opens, `Esc` closes and returns focus.
- State never by color alone: glyph + word. `agent` and `halt` have close luminosity.
- Icon buttons with `aria-label`; charts with `role="img"` and an `aria-label` with the numbers; stale-data
  strip with `role="status"`; confirmations with `role="alertdialog"`.
- Letter shortcuts do not fire inside fields.

## 8. Copy

Short, active sentences, normal case. Error = cause + recovery ("Não lemos os PRs. O token do GitHub expirou."
— "We did not read the PRs. The GitHub token expired."). Confirmation repeats the object and the consequence
("Parar a execução de #116? A nova tentativa agendada é cancelada." — "Stop the execution of #116? The
scheduled retry is cancelled."). Buttons name the action ("Parar execução", "Criar 7 tarefas"), never
"OK"/"Sim".

## 9. Hypotheses (out of current scope, marked)

1. **hypothesis** — Group the Fila by objective when there is an open objective (today "0 de 13" and "13 na
   fila" do not connect visually).
2. **hypothesis** — The inspector has 5 tabs in the product (Conversa, Atividade, Chamadas de IA, Execuções,
   PR) and 4 in the brief; decide whether Chamadas de IA goes into Execuções.
3. **hypothesis** — Requests and replies written while offline are kept and sent on reconnect. I do not know
   the current behavior; I designed without promising it.
4. **hypothesis** — Codex quota outside the US$ ceiling in Configurações (the brief lists ceilings without
   saying per executor).
5. **hypothesis** — "Execution silence" context: suggested threshold 10 min without output.
