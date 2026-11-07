# Maintainer contract

Binding implementation rules for agent-board. [AGENTS.md](../AGENTS.md)
requires this guide when changing application behavior. Operator setup lives
in [README.md](../README.md); validation lives in [PIPELINES.md](../PIPELINES.md).

## Main entry points

| Module | Role |
|---|---|
| `AgentBoard.Board` | the context: repositories, tasks, comments, events, broadcast |
| `AgentBoard.Sync` | the GitHub sync: issues, pulls, reviews, checks, comments |
| `AgentBoard.Sync.Worker` | the Oban job that runs the sync |
| `AgentBoard.Live` | the 10s poller that reads the runner's tickets |
| `AgentBoard.GitHub` | the HTTP client (`body!/1`, rate limits) |
| `AgentBoard.Orchestrator` | the runner's HTTP API, read-only: the load (`running`, `queued`, `maxWorkers`) |
| `AgentBoard.Metrics` | the throughput arithmetic, pure; `Metrics.Observations` reads what it counts |
| `AgentBoard.AI` | the door to a model: registered calls only, every one a row |
| `AgentBoard.Intake` | a free-text request -> refined spec -> tasks |
| `AgentBoard.Settings` | board-wide settings, one row per key (the voice picks) |
| `AgentBoard.Voice` | the spoken summary and the voice settings (language, volume, attention) |
| `AgentBoard.Voice.Phrases` | every sentence the agent speaks, per language |
| `AgentBoard.ElevenLabs` | the server-side voice client: TTS, STT, voices |
| `AgentBoardWeb.BoardLive` | the real-time UI |
| `AgentBoardWeb.BoardController` | the JSON API (`/api/...`) |
| `AgentBoardWeb.VoiceController` | the voice API (`/api/voice/...`) |

## The data

- **Ecto migrations** own the schema. Never edit a migrated table by hand; add a
  migration.
- The task state is two-layered: the **issue** is the baseline (`open` →
  `queued`, `closed` → `done`) and the **ticket** is the overlay (`running`,
  `ready`, `blocked`) while the issue is open. A ticket that ended `merged` is
  `done` whatever its last report said. A stopped or archived task keeps its
  state.
- A review rollup is the strongest review (`changes_requested` beats `approved`);
  a check rollup names the failing check.

## Workpad

- The agent keeps one comment per issue, edited in place, headed
  `## Relatório do agente` with the sections `### Plano`, `### Validação`,
  `### Pergunta` and `### Bloqueio` (the Communication prompt,
  `docs/agent/prompts/communication.md`). `AgentBoard.Workpad.parse/1` reads
  it by section name; any other comment is `nil`, and an empty section is
  `nil`: the parser never invents a question, a block or a gate.
- When the newest agent comment on a task is a workpad, its fields decide: a
  filled Pergunta makes a `waiting` ticket a `question` with or without a
  "?" (`Board.agent_asked?/2`, `Sync.waiting_state/2`), a filled Bloqueio
  makes it `blocked` even when the ticket opened a PR, and the item in
  Precisa de você quotes the section, never the whole comment.
- Validação is the local CI of the PRs the ticket and the workpad name
  (`LocalCI.by_pr/3`, scope `:workpad`): the command, its result and the
  sha it ran on. The sha is checked against the PR's head
  (`pull_requests.head_sha`, written by the sync): a gate on another commit
  is `:stale`, shown as `CI local ?` with both shas in the tooltip, never as
  a pass. A head the sync has not written yet cannot contradict the gate.
- Without a workpad, or with the section empty, the text heuristics stay
  exactly as before: a "?" in the summary or in the newest comment, "PR" with
  "review" in the report, `mix precommit` sentences in the reports.
- The tests: `workpad_test.exs` (the parser), `sync_test.exs`,
  `board_test.exs`, `local_ci_test.exs` and `work_test.exs` (preference and
  fallback), `board_live_test.exs` and `board_workpad_test.exs` (the item
  quotes the question; the gate reaches the card from a waiting ticket).

## Real-time

- The sync (the Oban `Sync.Worker`, every five minutes) and every task action call
  `Board.broadcast/1`; the LiveView subscribes with `Board.subscribe/1` and
  reloads on `:board_updated`.
- `AgentBoard.Live` polls the agent's tickets every 10s and broadcasts only
  when their hash changed — the runner state reaches the board without waiting
  for the sync. It is idempotent: the same tickets never broadcast twice
  (`live_test.exs`). The interval is the `:live_poll_interval` knob; the test
  environment stretches it to an hour so the supervised poller never ticks
  into the sandboxed database mid-suite.
- Never poll the database from the browser; push.

## Silence (Sem sinal)

- A running ticket's **last signal** is derived on every render by
  `AgentBoard.AgentSignal`: the newest of the runner's own timestamps
  (`report.at`, `idleAt`, `startedAt`) and the worktree's last change
  (`AgentWorktree.last_activity_at/1`: the newest uncommitted file, else the
  last commit; ignored files such as `_build` are not evidence). It is
  written nowhere: not in `tasks`, never in the runner's sqlite.
- Past `:stall_after_ms` (default 15 min) the silence is shown: the Agora
  card says "sem sinal há N min" and its glyph stops pulsing, and the task
  enters Precisa de você as `:stalled`, after blocks and before reviews, with
  the moment it crossed the threshold as its age and as what "novo" means.
  The item's DOM id is `silence-<id>`: the task's card is still in Agora.
- The voice says it once, when the item first appears in the needs list
  (`Announcer`, the `:needs` option), and stays quiet while it remains.
- The item says what the board saw last (a report, a worktree change or the
  start) and when; it never says the agent died. A long model turn with no
  file change is a silence too (ADR-0003, "não verificado (a)").
- Its only action opens the task. The board does not retry or stop the
  ticket in the runner: the orchestrator client stays read-only (ADR-0003
  reserves that write for its own decision) and the runner refuses a retry
  while a ticket runs (`canRetry` in `dsh: src/core/stage.ts`).
- The tests: `agent_signal_test.exs` and `agent_worktree_test.exs` (the
  signal), `work_test.exs` (the lane, its text and its order),
  `announcer_test.exs` (spoken once) and `board_stall_test.exs` (rendered in
  both lanes).

## The voice

- The server builds the summary (`AgentBoard.Voice` — the model writes it
  when it can, the template is the fallback) and pushes it with
  `push_event/3`; the browser speaks it with the Web Speech API. That path
  runs no TTS engine on the server.
- `AgentBoard.ElevenLabs` is the server-side voice (TTS, STT and voices),
  exposed by `AgentBoardWeb.VoiceController` at `/api/voice/...`. It reads
  `ELEVENLABS_API_KEY` from the environment, never from code, and returns
  `{:ok, ...}` or a reason (`:not_configured`, `:auth_expired`,
  `:usage_limit`, `{:http, status}`) — a raise never reaches the caller.
  No retry: a retried paid request is a second charge. The key never
  reaches the browser: the endpoints answer with audio or a transcript.
- The voice the agent speaks with resolves in this order: the environment
  (`ELEVENLABS_VOICE_ID`) → the pick saved in the UI (`AgentBoard.Settings`,
  key `elevenlabs_voice_id`) → the default (George). The TTS model resolves
  the same way (`ELEVENLABS_TTS_MODEL` → `elevenlabs_tts_model` → the
  default `eleven_flash_v2_5`); a saved model must be one of the offered
  `AgentBoard.ElevenLabs.tts_models/0`. The Voice section of the settings
  menu lists the account's voices, previews them through
  `/api/voice/speech?voice=...`, saves with `PUT /api/voice/settings`,
  speaks the board status in the agent's voice and dictates a task through
  `/api/voice/transcribe` (MediaRecorder → Scribe). The controls are
  `AgentBoardWeb.Components.VoicePanel` (rendered by the settings menu) and
  its two JS hooks (`VoicePlayer`, `VoiceRecorder`) live in
  `assets/js/hooks/`; the presentation stays out of `BoardLive`.
- The endpoints refuse what would cost a wrong request before the network:
  a text over 5000 characters (400), an audio body over the cap (413,
  `:voice_audio_max_bytes`), a voice id that is not voice-shaped (400) and
  a TTS model outside the catalog (400).
- The account's voices are cached for the `:voice_voices_ttl` window
  (default 5 minutes, 0 disables — the test env disables it); a browse
  does not pay a request every time.
- **Every spoken word comes from `AgentBoard.Voice.Phrases`**, in the voice
  language (`voice_language`: `pt-BR` default, `en-US`). A sentence typed
  in English inside a caller is the language mix this rule prevents. The
  summary prompt receives the language; the TTS sends `language_code` only
  to Flash v2.5 (another model answers 400). The greeting uses the
  browser's clock (`tz_offset`), never the UTC hour.
- **Automatic speech** is `AgentBoard.Announcer`: a pure diff between the
  previous and the current board, spoken as **one utterance per update**
  (a second `voice_play` cuts the first off), capped at two sentences and
  deduped for a short window. Two kinds:
  - **attention**: a task entering `question`, `blocked` or `ready`. It
    comes first, rotates through ten phrases per kind (`voice_turn`, a
    random start per socket) and has its own toggle (`voice_attention`,
    `"0"` disables). Without an ElevenLabs key it falls back to the
    browser's voice, in the voice language.
  - **events**: a task starting or going back to the queue and sync
    outcomes getting worse, plus the confirmations of user actions and the
    spoken answers; toggled by `elevenlabs_speak_events` (`"0"` disables,
    absent is on). User actions speak their own confirmations, so they are
    not announced twice.
  The volume (`voice_volume`, 0..100) rides on `#voice-panel[data-volume]`;
  the `VoicePlayer` hook and the browser fallback read it, so a change
  applies to the audio already playing. `PUT /api/voice/settings` accepts
  `speak_events`, `attention`, `language` and `volume`.
- **Voice asks** are a write and always confirmed: a draft that ends in a
  question mark (or starts with "perguntar"/"ask") and matches no read-only
  command resolves to an `:ask` proposal showing the target task; the
  "Ask the agent" button posts it to the task the owner was reading, and the
  asynchronous answer is spoken back in the agent's voice (cut at a word
  boundary). Opening the voice panel keeps the conversation's task, or the
  ask would have no target. Read-only commands keep precedence, so
  "O que está bloqueado?" still opens the blocked report.

## AI calls

- **A call must exist in `AgentBoard.AI.Registry`.** The prompt comes from
  code; a caller cannot invent one. Adding a call is a PR with a test.
- **Every call is a row** in `ai_calls` -- engine, model, tier, tokens,
  latency, parse state. A paid answer without a row is a bug.
- **No retry.** A retried paid request is a second charge.
- **The fast tier is the default.** `:deep` only when the result itself says
  the fast one was not enough.
- **A failure is a reason**, never a fabricated answer: `:not_configured`,
  `:auth_expired`, `:usage_limit`, `{:http, status}`.
- **`Budget.check/1` runs before the network.** Over the cap answers
  `:budget_exhausted` and records nothing.
- **A task that cannot close on its own is dropped**, not created
  half-written (see `AgentBoard.Intake`).

## The request (composer)

The composer is a view of one lifecycle that `BoardLive` owns; the durable
records are the `ai_calls` rows (the split) and the tasks with their
`request_key` (the enqueue).

| Transition | Owner | Durable record |
|---|---|---|
| draft | the socket (`composer_text`, kept across close/reopen) | none |
| splitting → ready / needs_clarification / no_tasks / failed | `start_async` keyed by a `ref`; a late or cancelled result changes nothing | `ai_calls` |
| enqueuing → receipt | `start_async`, one `Board.create_request/3` per chosen task | `tasks.request_key` |
| timeout | `{:composer_timeout, ref}` after `:composer_timeout_ms`; cancels the job and names the failure | — |

- **One job at a time.** A second submit while a job runs does nothing; the
  job is the receipt. The submit button is disabled server-side, not only by
  `phx-disable-with`.
- **A request is created once.** `Board.request_key/3` hashes the repository,
  the kind of submit and the words; `Board.create_request/3` answers
  `{:ok, task, :existing}` for a task with that key or a queued task with the
  same title and body, and opens no second issue. A retry after a partial
  split creates only what is missing.
- **The receipt names what happened**: number and link for each task that
  entered, "já estava na fila" for a repeat, the reason for each failure, and
  a retry for the failures only. Closing a receipt with a failure keeps it.
- **Failures are words**, never `inspect/1`: the model's reason
  (`:malformed_output`, `:usage_limit`, `{:http, status}`, a timeout) maps to
  a sentence and a way out (retry, answer the questions, send as a single
  request).
- **The title is the first sentence**, cut at a clause boundary
  (`Titles.from_request/1`), shown and editable before the submit.

## Types at the boundary

- **A field that is a string must receive a string.** The checks rollup returned
  a tuple `{state, failed}` and the caller put it straight into the
  `checks_state` string column. Every pull failed the changeset and nothing was
  stored -- for three rounds, because the tests that did not fetch checks never
  saw it.
- When a function returns a composite, **decompose it at the call site** and let
  the changeset be the second opinion. The test that finally caught it fed a
  pull with checks through the whole sync.
- If a fetch can fail independently (reviews, checks), **guard the fetch**, not
  the caller: log a `review_error`/`check_error` and continue with an empty
  list.

## What the header shows

- **live / static / reconnecting**: whether the browser's LiveView connection
  is active, serving the static render, or reconnecting. Client connection
  events update this indicator between server renders.
- **synced YYYY-MM-DD HH:MM UTC · clean / N errors**: the latest completed
  `sync` event. `clean` means `errors == 0`; `N errors` counts `issue_error`,
  `pull_error`, `comment_error` and `commit_error` in that run.
- **sync failed … · showing saved data**: a newer `sync_error` supersedes the
  completed sync. `Board.latest_sync/1` reads the latest outcome independently
  of the 20-event activity window. With no outcome, it says `no sync yet`.

The header is the health line: if it says errors, open the activity panel,
where each failing item is one row.

## Throughput (Vazão)

The strip under the digest (`AgentBoardWeb.BoardComponents.Throughput`) shows
the agent's throughput per hour. Every value is counted from a record the
board holds; a source the board never read shows `?` and names the reason
(`Metrics.reason/1`). Nothing is estimated and nothing is backfilled.

Windows are sliding and end at the render: **última hora** is the last 60
minutes, **24 h** and **7 d** the last 24 hours and 7 days; the delta chip
compares the last 60 minutes with the 60 before. The sparkline is different on
purpose: 24 clock hours in the reader's offset (`board_tz_offset`), 23 full
ones and the current, partial one, so a bar reads "14:00–15:00". The strip is
recomputed on every `:board_updated` (the sync and the 10 s poller), never on
a browser timer, and says when it was computed.

| Tile | Numerator | Instant | Source | Known limits |
|---|---|---|---|---|
| Concluídas | tasks with `state == "done"` | `tasks.state_changed_at` | the sync (`reconcile_resolved_tasks`, the ticket overlay) | the instant the **board observed** the close, not GitHub's `closed_at`; rows migrated before the redesign have no instant and are not counted |
| Issues abertas | tasks with `kind == "issue"` | `tasks.inserted_at` | the sync's first sight of the issue | a repository added with a backlog shows that backlog in one hour |
| PRs mesclados | pull requests with `merged_at` | `pull_requests.merged_at` | GitHub's own merge time | the sync reads the 100 most recently updated pulls per run |
| Commits | rows in `commits` | `commits.committed_at` (the committer date, when it landed) | `GitHub.commits/5`: the default branch as GitHub resolves it, `since` the newest commit stored (the first read covers 7 days), up to 10 pages per run | merge commits count; a commit stays once seen, even if the branch is later rewritten; `?` until the latest completed `sync` event carries a `commits` count |
| Tickets encerrados | the agent's tickets with `ended.outcome` in `merged`, `completed` | `ended.at` (`AgentState`, `"ended_at"`) | the runner's sqlite, read-only, filtered to the tickets whose channel is one of this repository's issues | `?` when the sqlite did not answer (`agent.ok == false`); a ticket with no channel URL belongs to no repository |
| Fila | tasks queued at the instant (depth, not a rate) | queued from `inserted_at` until `started_at` (the ticket's clock) or, failing that, `state_changed_at` | tasks | a task that left the queue at an unknown instant is left out; **24 h** and **7 d** are the peak depth at hour ends |
| Ciclo | mean issue → PR and PR → merge | `tasks.inserted_at` → `pull_requests.opened_at` → `pull_requests.merged_at` | one cycle per ticket that ended `merged`: its channel issue, the newest PR in its `own_threads`, that PR's merge | over the tickets whose PR merged in the window; a leg with a missing instant is left out of that mean, never counted as zero |
| Paralelismo | `load.running` of `load.maxWorkers`, plus `load.queued` | now | `AgentBoard.Orchestrator.load/0`: `GET $SUPERAGENT_API/state` with `x-orchestrator-request: 1`, 500 ms to connect, 1 s to answer | no history: the value is the instant of the render; `?` with the reason when the API is off (`orchestrator_api: false`), unreachable or malformed |

- A commit read that fails is one `commit_error` event; the issues, pulls and
  tickets still sync, and the `sync` event has no `commits` key for that run.
  `commit_error` counts in the header's `N errors`.
- The orchestrator is never asked from the browser and never retried in the
  same render; a dead runner costs a render at most the connect timeout.
- The tests: `metrics_test.exs` (windows, the reader's clock including a
  half-hour offset, empty and unknown sources), `metrics_observations_test.exs`
  (each source against the tables), `sync_commits_test.exs` (paging, dedupe,
  isolation), `orchestrator_test.exs` and `live/throughput_test.exs` (the strip,
  `?` for the unread, the broadcast).

## Network paths

- Every GitHub call goes through `AgentBoard.GitHub`. A 4xx/5xx is **not** a
  body: `body!/1` raises `GitHub HTTP <status>` (or `GitHub rate limited: retry
  after <n>s` for 403/429), so the caller sees the real cause.
- Every function that touches the network must survive a raise: `Sync.sync_repo`
  logs a `sync_error` event and returns `{:error, exception}` so Oban retries;
  `Board.ask` deletes its optimistic placeholder and returns the error. A raise
  that reaches the caller is a bug — the test suite has a case for each.
- Network failures never erase the board's last good state: the overlay is
  skipped, the previous tasks stay.

## Sync isolation

The sync is isolated **per item**, not per repository:

| Failure | Event | The sync... |
|---|---|---|
| an issue fails validation | `issue_error` | continues |
| a pull's reviews/checks fail | `pull_error` | continues |
| a task's comments fail | `comment_error` | continues |
| the commit read fails | `commit_error` | continues, without a `commits` count in the `sync` event |
| the repository itself fails | `sync_error` | returns `{:error, exception}` and Oban retries |

Every branch returns `:ok` or logs; nothing swallows an error silently and
nothing takes the whole sync down for one bad item. Each branch has a test in
`sync_repo_test.exs`.

## Boundaries

- The board **reads** the agent's state (the sqlite); it never writes to it.
- The web layer never talks to GitHub directly: it goes through `AgentBoard.Board`
  and `AgentBoard.GitHub`.
