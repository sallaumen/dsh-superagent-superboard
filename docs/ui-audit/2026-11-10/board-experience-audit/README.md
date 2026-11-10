# Board experience audit — 2026-11-10

Baseline `origin/main` 9e31055 (unified layout, PR #475, already merged). Workflow: `navigation-ux`,
Elixir Agent Kit 0.8.0, size large. The owner reported three losses of context: a concluded card
vanishes, the merge log opens only the pull request, and cost is buried.

## How it was exercised

An isolated dev server of this worktree on port 4731, on a copy of the dev database
(`agent_board_audit_eaca5f`, dropped afterwards), no GitHub or model keys, auto-retry and release off, a
fake orchestrator. Driven with the Playwright MCP (headless WebKit, one tab, closed at the end), pt-BR
and English. Lane states (3 running, 1 blocked, 1 question, 2 review, 17 queued, one 190-character
title, two equal titles) were written into the copy only.

The copy held 737 merged PRs within 7 days (arena-rogue 97, o_colmex 478, superboard 162) and 115 tasks
(112 `done`).

| Window | `main` | Lanes | Days | Flow | Horizontal scroll |
|---|---|---|---|---|---|
| 1920×1080 | 1696 | 456/456/593 | 7 × 226 | 8 × 197 | none |
| 2560×1440 | 1980 (cap) | 542/542/704 | 7 × 267 | 8 × 232 | none |
| 3440×1440 | 1980, 618 px free each side | same | same | same | none |
| 3840×1080 | 1980, 818 px free each side | same | same | same | none |
| 5120×1440 | 1980, 1458 px free each side | same | same | same | none |
| 1366×768 | 1142 | 2 columns | 4 | 4 × 2 | none |
| 1100×800 | 876 | 1 column | 2 | 2 × 4 | none |
| 760×900 | 704, rail 56 | 1 column | 2 | 2 × 4 | none |
| 390×844 | 390, no rail | 1 column | 1 | folded | none |

Zoom was emulated by the equivalent CSS width: 1920 at 125 % is 1536 (2 lane columns), at 150 % is 1280
(1 lane column); 3440 and 5120 at 150 % are 2293 and 3413 (capped at 1980). Also covered: dark theme
(1920, 3440, 390), inspector open at eight widths, idle and working board, o_colmex with 478 merges,
frozen sync ("Sem conexão", `≥` counts, absolute ages), orchestrator down ("Agente fora do ar"),
socket down ("Reconectando"), Tab order, `J`/`K`/`Enter`/`Esc`, browser back.

## Journey map

| Step | URL | Transition | Back | Observed |
|---|---|---|---|---|
| Board | `/?repo=o/n` | load | leaves | lanes hold running, retrying, question, ready, blocked, queued; `done` is not loaded |
| Open a lane task | `…&panel=conversation&task=<id>` | `push_patch` | closes the inspector | focus goes to the close button; `Esc` returns it to the card |
| Inspector tab | `…&tab=…` | `push_patch` | previous tab | reload keeps task and tab |
| History | `…&panel=history` | `push_patch` | closes the panel | 50 merged PRs per page, more on scroll; no search, no filter |
| Merge log row, history row | GitHub, new tab | plain link | — | **context lost**: no way into the task from the PR |
| Task concluded | — | sync or poller sets `done` | — | **context lost**: the card leaves every lane; nothing in the board links to it |
| Done task by URL | `…&panel=conversation&task=<id>` | deep link | board | works: conversation, activity, AI calls, executions and PR are all there |

A done task's inspector is complete. What is missing is a door to it: the Messages window reaches it
only while its reply is among the 30 newest, and a completed objective lists its tasks.

## Findings

Class: **D** confirmed defect, **F** UX friction with observable impact, **S** product suggestion or taste.

| # | Class | Finding | Evidence | Status |
|---|---|---|---|---|
| 1 | F | A merged PR never leads to its task. `pull_requests.closes_issues` already says which task it closes (87 of 97 in arena-rogue, 9 of 478 in o_colmex) | `a.ab-pr[target=_blank]`, `.archive-row a` | fixed in the second delivery (P1) |
| 2 | F | A concluded task is in no list. History is PRs only: 15 done tasks have no closing PR and appear nowhere; a stopped task and an issue closed without a merge cannot be told apart from a merge | `Board.@task_states`, `Archive` | proposal P2 |
| 3 | F | Cost of a task takes: knowing the task URL, the "Chamadas de IA" tab, and the "Executor do agente" block under the board's own calls. No PR and no list row shows any cost | `inspector.ex` | header line in the second delivery (P3a); rows wait for P3b |
| 4 | D | A board call under one cent read **$0.00**, in the row and in the total | `before-inspector-cost-1920.png` | fixed: `< $0.01` |
| 5 | D | The "Execuções" tab said **0** until it was opened, then 2: the ledger is read only on that tab | same task, tabs `conversa` → `execucoes` | fixed: no number until read |
| 6 | D | History trend counted only the loaded page and showed **0** for days with merges (4–7 Nov: 0, 0, 0, 0; the board beside it: 8, 3, 8, 14) | `before-history-panel-1920.png` | fixed: `?` for unread days, `≥` for the partial one |
| 7 | D | History rows in pt-BR said "NO REVIEW", "CI FAILED: GATES", "Merged:"; "carregados" and an `aria-label` were hard-coded in one language each | same capture | fixed: gettext, both languages |
| 8 | D | Inspector header: "atualizado há há 7 min" | `aside.ab-insp .ab-insp__facts` | fixed |
| 9 | D | Throughput tile "concluído" beside "Issues abertas", "PRs mesclados" (the contract names it "Concluídas") | `#fold-flow` | fixed |
| 10 | D | English is not complete: with the default locale the board mixes "Needs you" with "Desde hoje às 10:13 nada mudou", "Ontem, 9 nov", "sem revisão", "CI local ?", "desde yesterday at 08:00", "US$ 5,10". pt-BR is coherent. The strings live in `Lanes`, `Board` and `Time`, not in gettext | English walk at 1920 | proposal P5 |
| 11 | F | Ultrawide: above a 2204 px window the extra width is margin only. The rail stays at x = 0 and the inspector at the right edge: at 5120 the content is 1458 px from the rail and 1190 px from the inspector, and it shifts 252 px when the inspector opens | `board-working-5120x1440.png`, `inspector-open-5120x1440.png` | fixed in the third delivery (two panes) |
| 12 | F | The same PR reads "CI FALHOU: GATES" in red in History (GitHub Actions, blocked by billing) and "CI local ok" in the merge log (#195) | both captures | proposal P6 |
| 13 | F | Activity shows the raw kind `task_released`, and reads only the repository's last 50 events: an older task loses its own | `Board.task_repo_events/2` | proposal P6 |
| 14 | F | DeepSeek cost is always `≥`: cache reads have no price, and on the sampled task they were 48.4 M tokens against 316 k of input. The minimum can be far from the cost | `before-inspector-cost-1920.png` | proposal P3c |
| 15 | F | A task with more than 20 board calls totals only the newest 20, unsaid; executions older than 90 days leave the tab; executor usage needs the runner's ticket and its transcripts still on disk | `AI.recent_for_task/2`, `Report.by_task/2` | proposal P3 |
| 16 | F | Cycle tile at 1920 cuts its values with an ellipsis ("4 h 15…"); the source line of Parallelism too | first walk, real tickets; no capture kept | not fixed |
| 17 | S | A 1280 px window (1920 at 150 %) gives `main` 976 px of content: one lane column 976 px wide. The cut is the content box, not the 1000 px of `main` | `board-1280-zoom150.png` | owner's call |
| 18 | S | A merged task's inspector still offers Perguntar, Parar and Arquivar | `after-inspector-cost-1920.png` | owner's call |
| 19 | S | History keeps the old look: spaced capitals in "PRS MESCLADOS", bars in the primary blue | `after-history-panel-1920.png` | with P2 |
| 20 | S | "Agente fora do ar" is the label and the title of the same card | `state-frozen-agent-offline-1920.png` | taste |
| 21 | S | Opening the inspector above 2000 px widens the rail from 224 to 240 px | `board.css` `@container board (min-width: 1880px)` | still there |

No finding blocks the main task on the current lanes: nothing overflows, is cut or is out of reach at any
width tested, and no control lost its focus ring.

## Fixed in this delivery

All in the web layer; no query, schema, sync, dispatch or click destination changed.

- `inspector.ex`: `< $0.01` for a cost under a cent (`≥ $0.00` for a partial total that small); the
  Execuções count appears only once the ledger was read.
- `merge_trend.ex`, `archive.ex`: unread days are `?`, the oldest loaded day and the caption are `≥`.
- `presentation.ex`, `card.ex`, `archive.ex`: review, CI and stamp labels through gettext.
- `throughput.ex`: the tile label has its own context ("Concluídas").
- `pt_BR/default.po`: the new strings and "atualizado %{age}".
- Tests: `inspector_test.exs` (sub-cent), `executors_test.exs` (count), `board_live_test.exs` (partial
  trend; four assertions that pinned the English badges in a pt-BR render now assert the translation).

## Second delivery: P1 and P3a (P4 rejected)

The owner approved the three small proposals on 2026-11-10.

- **P1.** A merged PR that closes an issue has a second, quiet link, "tarefa #184", in the merge log and
  in History. The row still opens GitHub. The click reads the PR and the first closed issue the board
  tracks (`Board.find_pull_request/2`, `Board.find_task/2`) and patches to the inspector; an untracked
  issue answers with a notice. The board load gained no query. Walked: 17 of 20 rows in the log and 48
  of 50 in History carry the link; back returns to the board or to History; the link is a Tab stop with
  a focus ring, 68 × 25 px (`after-task-door-merge-log-1920.png`, `after-task-door-history-1920.png`).
- **P3a.** The inspector header says "1 chamada · < $0.01" and "executor ≥ $0.17", two links to the
  AI calls tab, from data the inspector already loads. Two numbers, never a sum; the executor one
  appears only with a measured reading (`after-inspector-header-cost-1920.png`).
- **P4, rejected.** #520 centred rail, content and inspector as one block. On the owner's 3440 px window
  that left the rail 618 px from the edge beside an empty rectangle: the margin had moved, the width was
  still unused. The validation only checked that nothing overflowed. Reverted in #521; replaced by the
  third delivery below.

The link adds one line under each such row: the merged band is about 90 px taller at 1920.

## Third delivery: a layout that uses the width

Workflow `responsive-layout` (kit 0.8.0, medium). The 1980 px cap is gone: the board fills `main` at
every width, and from 2500 px of content the same document is arranged in two panes.

| Content of `main` | Arrangement |
|---|---|
| below 2500 px (a 2560 window: 2224) | one flow, as before, now without side margins |
| 2500 px and up (3440, 3840, 5120) | left pane: header, summary, context, lanes, and Vazão under them in 4 × 2. Right pane: Mesclados, seven days with up to eight merges each |
| 2500 to 2859 px (3440 with the inspector open) | same panes, lanes in two columns |

- The document order never changes (work, merged, throughput), so nothing differs for a narrower
  window, a phone or a screen reader. `.ab-cols` became `.ab-stage`, with the header and context
  inside `.ab-pane--work`.
- **More of the record.** A day showed three merges and "and 26 more". `Lanes.merge_log/2` now also
  hands the next five (`extra`, `more_wide`); a wide window shows them, with its own "8 of 29" and
  "and 21 more". They come from the PRs the log already read: no query.
- **Throughput in 4 × 2** under the lanes: 350 px cells at 3440, where the Cycle table and the
  Parallelism source no longer cut their text (finding 16, on wide windows).
- **Hoje** from 2000 px of content: what needs the owner on the left, projects and the week on the
  right, the day's spending beside the title. It was a 1100 px column in a 3216 px area.
- Fixed in passing: "Source" overflowed its 34 px column in English and read "Sourceorquestrador".

Measured (WebKit, emulated): no horizontal scroll and no hard-clipped text at 3440×1440, 3840×1080,
5120×1440, 2560×1440, 1920, 1366 and 390. At 3440×1440 a working board fits without vertical scroll
(work pane ends at 816 px, throughput at 1158, merged at 1058). Lane, day and cell columns at 1920,
1366 and 390 are the same as before.

| Window | Left pane | Right pane | Lanes | Days | Cells |
|---|---|---|---|---|---|
| 3440 | 280–1724 | 1724–3384 | 401/401/521 | 7 × 231 | 4 × 350 |
| 3840 | 280–1910 | 1910–3784 | 458/458/595 | 7 × 262 | 4 × 396 |
| 5120 | 280–2505 | 2505–5064 | 638/638/829 | 7 × 360 | 4 × 545 |
| 3440 + inspector | 296–1490 | 1490–2864 | 557/557 | 7 × 190 | 4 × 287 |

Known costs, said plainly:

- On an idle board the left pane ends early (451 px at 3440×1317) while the record runs to 974 px: the
  space under the throughput is empty because there is no work to show.
- Tab order is the document's: work, merged, then throughput, which sits under the lanes on the left.
- Opening a task at 3440 takes the lanes from three columns to two, so the queue moves 269 px left. The
  old layout moved the content 252 px on the same click.
- At 5120 the panes are 2200 and 2560 px wide: sparse, though nothing stretches. Only emulated.
- At 3440 with the inspector open a day column is 190 px, the narrowest it gets.

Captures in `wide/`: `colmex-idle-en-dark-3440x1317.png` (the owner's case: idle, English, dark),
`busy-3440x1440.png`, `busy-dark-3440x1440.png`, `busy-3840x1080.png`, `busy-5120x1440.png`,
`busy-2560x1440.png`, `busy-1920x1080.png`, `inspector-3440x1440.png`, `inspector-5120x1440.png`,
`hoje-3440x1440.png`, `hoje-2560x1440.png`.

## Languages (finding 10, proposal P5)

Inventory of 2026-11-10 at b8dff0e: 652 Portuguese and 110 English user-facing literals outside
Gettext, 8 browser strings never localized, no Portuguese in `Logger` or raises, a complete pt-BR
catalog. Workflow `house-patterns` (kit 0.8.0).

Most of it was converted on `main` by the other agent while this audit's slice was being written:
#527 (menus, message hub, status words, numbers in the viewer's format), #529 (confirmation sentences
in the interface language) and #530 (lanes, blocks and activity). This audit's own conversion of the
same modules was dropped in favour of those. What it adds on top:

- `AgentBoard.Time` words relative ages, day headings and "since" labels through Gettext; it was still
  Portuguese ("há 7 min", "terça", "nov"). `AgentBoardWeb.Time`, its translated copy, now only forwards.
- Eight browser strings joined `assets/js/i18n.js` ("Listening…", "You", "Agent"…).
- "of N" (queue filters) and "thought for N" (voice log). The inbox placeholders are left to #531.

Still Portuguese outside Gettext, by a rough search of `main`: `actions` 84 lines (results and the
Portuguese branch of the sentences), `voice/commands` 26, `agent_control` 17, `routing` 12,
`conversation/agent` 8 and `voice_controller` 4 (voice activity, shown and logged), `runners` 5,
`auto_retry` 5 and `bot_access` 4 (stored text), `freshness` 19 and `Logs.summary/1` (not rendered).
`merge_log` and `needs_you` pick a CSS class by comparing a note with a translated string.

## Fifth delivery: ended tasks in History (finding 2, proposal P2)

History now opens on **Ended tasks**: the tasks in `done`, `closed`, `stopped` or `archived`, newest
first, under day headings, each saying how it ended (merged only with a merged PR that closes the
issue; otherwise "closed, no merged PR", stopped or archived) and opening the task's inspector. A
search by number or title is answered by the server and kept in the URL. **Merged PRs** is the second
list, unchanged; "and N more" in the merged strip opens it.

Walked on the copy of the real data (arena-rogue, 107 done, 1 stopped): 50 rows on the first page
under "Today", "Yesterday, 9 Nov", "Sunday, 8 Nov"; `#184` finds one row and "arco" four; a row opens
the inspector and back returns to History with the search in place; a reload keeps list and search;
`Esc` closes the panel; no horizontal scroll at 390 px. Two new reads when the panel shows the list,
none in the board load, no schema change. Captures in `concluded/`.

Not done here: the list does not refresh on a broadcast while open, and no search across the tasks
still in the lanes.

## Proposals, in priority order

Each one changes behavior, a query or the layout. P1 and P3a are implemented and P4 was replaced by
the third delivery (above); the rest wait.

### P1 — From a merged PR to its task (small)

Keep the row opening GitHub and add a second, smaller link on rows whose PR closes an issue: "tarefa
#184". The click asks the server, which finds the task with the existing `Board.find_task/2` and patches
to the inspector. `closes_issues` is already on the rows `merge_log/2` and the history page load, so the
board load gains no query; the lookup happens on the click. A closed issue the board does not track
answers with a notice.

- Rejected: making the inspector the row's primary target. In o_colmex 98 % of the merged PRs have no
  task, so the same row would behave in two ways.
- The relation is not 1:1 by schema. Today no PR closes two tasks and no task has two closing PRs, but
  `Attribution.task_for_pull/2` takes the first closed issue that is a task; the link follows that rule.

### P2 — Concluídos: order, state and search (medium)

Turn History into the place for concluded work instead of adding a lane (a fourth lane competes with
"Precisa de você" for the one screen that asks for action).

- A list of tasks that ended, newest first by `state_changed_at` (the instant the board observed it; 7
  old rows have none), with the state in words: mesclada (linked PR merged), fechada sem PR, parada,
  arquivada. Row: state, number, title, PR, when; the click opens the inspector.
- "PRs sem tarefa" stays as a second view of the same panel: it is what History shows today.
- A search field on the server: exact number, or title. One page of 50 by keyset, like `merged_page/3`.
- Data: two new reads (the page and the search), no schema. At today's 115 tasks no index is needed; a
  title index is a later decision if the table grows by two orders of magnitude.

### P3 — Cost where the decision is made

- **a (small).** One line in the inspector header, beside "PR #199 · 1 chamada": "executor ≥ $0.17 ·
  board < $0.01", each part opening its tab. Both numbers are already loaded when the inspector opens.
  Never one sum: the board's calls, the DeepSeek estimate, the Claude Code list price and the Codex
  quota are four units.
- **b (needs data).** Cost on a row (merge log, Concluídos) needs a per-task value the board load can
  read. The board's own calls are one `GROUP BY task_id` on an indexed column, but only 2 of the 8 call
  kinds record a task (100 of 109 rows have none). The executor's cost, the large one, needs a pass
  over 90 days of ledger plus the attribution index: too much per load. It asks for a stored per-task
  rollup written by `Usage.Worker`, which is a schema decision.
- **c (pricing).** Give cache reads a price in `AI.Providers`, so DeepSeek stops being a floor.
- **Per PR:** there is no PR cost and no apportioning rule. With P1 a PR shows its task's cost, said as
  "custo da tarefa #184". A PR without a task has no attributable cost; the board should say "—", not
  guess by branch or title.
- **Per request:** exists for the board's calls. The executor's requests are counted per session, not
  listed; listing them means reading transcripts on demand. Not promised.

### P4 — An explicit rule for ultrawide (small, CSS)

The 1980 px cap is intentional (`board.css`: "center the reading area") and reads well: seven days at
267 px and eight cells at 232 px are comparable, nothing stretches. Three options:

1. Keep as is, and call the margins the decision.
2. **Recommended:** keep the cap and keep the three parts together above about 2400 px: rail, content
   and inspector as one centred block. It removes the 1.2 to 1.5 thousand pixels between a card and its
   detail and the 252 px shift; content and breakpoints stay.
3. Use the width: a fourth band at 2600 px or more. Only worth it with P2, where "Concluídos" is the
   natural candidate. Raising the cap alone only spreads the same lanes thinner.

### P5 — English as a complete language (medium)

Move the sentences the domain modules write in Portuguese (`Lanes`, `Board`, `Time`: summary, day
labels, CI and review notes, activity, ages) behind gettext, and format numbers per locale. A delivery
of its own; it touches the domain agent's files.

### P6 — Smaller truths (small each)

- History uses the merge log's CI wording (local gate first, Actions named when billing blocked it).
- Activity names its events in words and reads the task's own events instead of filtering the last 50
  of the repository.
- The AI calls total says when it shows the newest 20 only.

## What to preserve

- One structure at every width; only the container changes the columns. Empty lanes keep their place.
- The order: summary, context, Agora, Precisa de você, Fila, Mesclados, Vazão. The next action is always
  in "Precisa de você", and its verb is on the card.
- URL state for inspector, tab and panels: back closes, reload restores, `Esc` returns focus to the card.
- Tab order rail → top → context → lanes → merged, one focus ring on every stop; `J`/`K` across the lanes.
- The frozen state: banner with "Tentar agora", hatched cards, `≥`, absolute ages. It reads as the
  board's condition, not the reader's mistake.
- `≥`, `—` and `?` with the reason beside them, and currencies never added.
- No motion on data that arrives. Nothing here adds or changes motion.

## Not verified

- A physical ultrawide monitor and real browser zoom: widths and zoom were emulated in headless WebKit.
- Chromium and Firefox; touch; a screen reader (names and roles were read from the accessibility tree).
- Running cards with live ticket phases under the fabricated states (the runner database was replaced by
  an empty one so the copy kept its states); executor cost after the fixes for the same reason.
- An active objective and a day without merges on real data: every objective in the copy was complete
  and every day had merges. Both have LiveView tests.
- English beyond the first walk at nine widths.
