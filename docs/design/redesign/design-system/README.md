Agent Board is the workbench for someone who leaves agents coding and comes back to see what changed. It is not a metrics dashboard: it is a reading. The question each screen answers, in this order, is **what the agent is doing now, what only I can unblock, what changed since I left and how recent all of it is**.

## Principles

1. **Truth before form.** A number appears only if it came from observed data. Stale data declares itself stale (`stale`, hatching, “≥”, “visto às 09:36” (seen at 09:36)); unknown data becomes `?` or “desconhecido” (unknown), never `0`. A timer only runs while sync is live.
2. **Your work is blue, the agent's is green, what got stuck is tile.** `you` marks everything waiting for a decision from you (review, question, selection, primary action). `agent` marks what the agent is doing. `halt` marks a block and failure. What finished recedes to `ink-muted`.
3. **Space separates, not boxes.** Sections live loose on `paper`, divided by space (`space-7`) and `line` hairlines. Only things that ask for an action from you get a surface (`surface`). No four equal columns with emptiness inside.
4. **Stay on the page.** Opening a task opens the side panel; writing a request opens the composer on top. The list stays visible and focus returns to where it was when you close (`Esc`).
5. **Calm for hours.** Warm, low-saturation background in both themes, a single continuous motion (the agent dot breathing) and nothing else.

## Content and voice

- Brazilian Portuguese, short sentences, normal case. Labels never in spaced UPPERCASE.
- Give the reason, not the state: “**CI falhou em `gates`** depois do merge. A main está vermelha desde 23:58.” (**CI failed in `gates`** after the merge. Main has been red since 23:58.) instead of “CI FAILED: GATES”.
- The top summary is **one sentence**, written from the data since your last visit: “Desde ontem às 22:10 o agente mesclou 3 PRs, os 3 com CI falhando, abriu 1 PR para revisão…” (“Since yesterday at 22:10 the agent merged 3 PRs, all 3 with failing CI, opened 1 PR for review…”). Each fragment is a link colored by role (`you`, `agent`, `halt`).
- Relative time for what is recent (“há 41 min” — 41 min ago), absolute time in `data` for what is a record (“23:41”). When the connection drops, switch to absolute: “dados de 09:36” (data from 09:36).
- Task titles as the agent or you wrote them; do not translate or rewrite them.
- No emoji, no exclamation mark, no “Ops!”.

## Color

- Page background `paper`; rail and recessed fields `paper-sunk`; actionable items and the panel `surface`; what floats `surface-raised` with `shadow-layer`.
- Text in `ink`; reasons and metadata in `ink-muted`; timestamps and PR numbers in `ink-faint`. All three pass 4.5:1 over all backgrounds and washes in both themes.
- Each role has a tone and a wash: `agent`/`agent-wash`, `you`/`you-wash`, `halt`/`halt-wash`, `stale`/`stale-wash`. The tone is for text and marks; the wash is background only. Text over a `you` fill uses `on-you`, over `agent` uses `on-agent` — never literal white.
- `agent` and `halt` have similar luminosity: **never** rely on color alone. Every state carries a glyph and a word (see StatusMark).
- Control borders in `line-strong` (≥3:1). `line` is decorative.

## Typography

- `sans` (IBM Plex Sans) for interface and reading; `mono` (IBM Plex Mono) only for machine data: times, durations, tokens, costs, hashes, paths, commands. Mono always with `tabular-nums`.
- Scale: `display` once per screen (repository name), `title` for sections and the panel, `task` for titles in lists, `body` for conversation, `meta` for reasons, `label` for labels and counts, `data`/`data-small` for values.

## Space, shape and layers

- Page with gutter `space-6` (`space-5` on mobile); `space-7` between sections; `space-4` vertical padding per row.
- `radius-sm` for controls, `radius-md` for focused rows and “Precisa de você” cards, `radius-lg` for the panel, the composer and the “Agora” strip, `radius-pill` for the sync beacon and filters.
- Shadow only on a layer that floats (`shadow-layer`). Cards in the flow use `line`, not shadow.

## Screen structure

- **Rail** (224px, `paper-sunk`): repositories with attention marks — agent dot if something is running, `◆ n` waiting for you, `■ n` blocked or with failing CI, `?` if the repository data is stale.
- **Top**: repository name, the **sync beacon** glued to it, and the actions `Dividir pedido` and `Novo pedido` (`N`).
- **Summary** of one sentence since the last visit.
- **Main column**, in this order: **Agora** (the agent's real step) → **Precisa de você** (order: failing CI on main, blocks, reviews, questions; what is new since the visit comes before the “before your last visit” line) → **Fila** (numbered, top to bottom, with a duplicate warning).
- **Side column**: **Mesclados** — seven days as dots (one dot per PR, a tile if CI failed) and the record per day.
- **Side panel** (440px; 520px on ultrawide): Conversa, Atividade, Chamadas de IA, PR. Below ~1240px wide it floats over the content; on mobile it takes the screen.

## Sync and honesty

- The beacon has five states: **Ao vivo** (all sources answered in the last minute), **Atrasado**, **Reconectando**, **Sem conexão** and **Sem dados ainda**. Clicking opens the detail per source (GitHub, agent process, local queue).
- No connection: `stale-wash` strip “Mostrando o que sabíamos às HH:MM”, counts with “≥”, clocks stopped at “visto às”, the “Agora” card hatched, the rail with `?`, the data area slightly desaturated.
- On reconnect: a single notice in the corner (“Reconectado. 3 mudanças desde 09:36.”) with `Mostrar`, which highlights those changes with the **new** mark.
- Missing cost or tokens: show `—` and total as a minimum (“≥ $1.52”), saying it is a minimum.

## Motion

- The `agent` dot breathes (2.4s) only while sync is live. Stopped = we do not know.
- Layers enter with 180–220ms of a short rise; nothing else animates. `prefers-reduced-motion` turns everything off.

## Keyboard and focus

- `J`/`K` moves through tasks in screen order, `Enter` opens in the panel, `Esc` closes the top layer and returns focus, `N` new request, `V` dictate, `1–4` switches the panel tab, `?` lists the shortcuts.
- Single focus ring: `focus-ring`, 2px solid, offset 2px. Passes 3:1 over all backgrounds in both themes.

## Iconography

- States are geometric glyphs drawn in CSS: ● running, ◆ waiting for you, ■ blocked/failed, ○ queued, ✓ merged, hatched circle stale data, dashed circle unknown.
- Action icons are 1.6px strokes at 16×16 (`AgentBoard.ico`). There is no logo: the name is set in type, with a simple `agent` dot mark over `ink`.

## Using the components

`components/bundle.js` exposes `window.AgentBoard` without React: functions that take data and return HTML (`needsSection`, `nowSection`, `queueSection`, `logSection`, `inspector`, `composer`, `beacon`) and `mount(el, estado)`, which wires keyboard, panel and clock. `AgentBoard.demo` brings the sample states used in the screens (`morning`, `working`, `offline`, `reconnected`, `volume`, `empty`). The data formats are in `components/index.d.ts`.
