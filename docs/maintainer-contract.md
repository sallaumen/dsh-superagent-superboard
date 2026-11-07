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
| `AgentBoard.Orchestrator` | the runner's HTTP API: the load (`running`, `queued`, `maxWorkers`) and its two writes, `retry/2` and `set_max_workers/2` |
| `AgentBoard.AgentFailure` | what a `failed` report means: transient (network, provider) or a person's, pure |
| `AgentBoard.AutoRetry` | the automatic retry of a transient failure: `plan/2` (pure, what the board shows) and the 30 s tick |
| `AgentBoard.AgentBlock` | what the board says about a failed ticket: the card line, what the system does, what is left to the owner, the attempts; pure |
| `AgentBoard.AgentControl` | the owner's two confirmed asks: "Tentar de novo" (`retry/2`) and "Religar o agente" (`start_agent/1`) |
| `AgentBoard.Metrics` | the throughput arithmetic, pure; `Metrics.Observations` reads what it counts |
| `AgentBoard.AI` | the door to a model: registered calls only, every one a row |
| `AgentBoard.ExecutorUsage` | what the executor spent on a task, read from the harness transcripts; tokens measured, cost estimated |
| `AgentBoard.Executors` | who a task is for (`dsh`, `claude`, `codex`): the label and the issue body each gets; pure |
| `AgentBoard.Attribution` | which task a session or a PR worked for: exact, `pr-link`, branch, repository or outside; pure |
| `AgentBoard.Usage.ClaudeCode` | what Claude Code spent, read from its transcripts (`~/.claude/projects`); one count per `message.id` across files, numbers and named metadata only (`Usage.Fields`) |
| `AgentBoard.Usage.Codex` | what Codex spent: the `threads` table by named columns (never `title`, `preview`, `name`, `first_user_message`) and the rollouts' cumulative totals as daily differences, plus the last `rate_limits`; zstd rollouts through `Usage.Lines` |
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
  `retrying`, `ready`, `blocked`) while the issue is open. `retrying` is a
  failure `AgentBoard.AutoRetry` will retry by itself, or a retry waiting
  for a worker ("Automatic retry" below). A ticket that ended `merged` is
  `done` whatever its last report said. A stopped or archived task keeps its
  state.
- The sync's insert sets the baseline once and keeps the state on conflict,
  so an overlay is not reset to `queued` every five minutes. A **closed
  issue** is the exception: every sync moves its task to `done`, unless it
  is stopped or archived (`Sync.close_task/2`). Before this, an issue closed
  after it entered the board stayed in Fila while the runner had nothing to
  do (`sync_repo_test.exs`). A reopened issue is not moved back yet.
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
- The board is read once per render of the page (in `handle_params/3`, never
  also in `mount/3`), again on every `:board_updated` and task action, and
  never for a patch inside the same repository: opening a task, a panel or a
  tab changes only the panel. Every read is the `[:agent_board, :board,
  :load]` telemetry span, on the dashboard as `agent_board.board.load`
  (`board_load_test.exs`).

## Silence (Sem sinal)

- A running ticket's **last signal** is derived on every render by
  `AgentBoard.AgentSignal`: the newest of the runner's own timestamps
  (`report.at`, `idleAt`, `startedAt`) and the worktree's last change
  (`AgentWorktree.last_activity_at/1`: the newest uncommitted file, else the
  last commit; ignored files such as `_build` are not evidence). It is
  written nowhere: not in `tasks`, never in the runner's sqlite.
- The worktree is observed once for both the signal and the card's step (one
  `git status`, at most one `git log`), and the observation is shared by
  every render for `:worktree_ttl_ms` (10 s, the poll interval; 0 in tests),
  in memory only (`AgentWorktree.Cache`). A render therefore shows the
  worktree as it was at most 10 s earlier; a fresh read per render cost 40 ms
  of `git` per running ticket, per LiveView, per broadcast.
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
  ticket in the runner: the automatic retry (below) covers only a `failed`
  report, never a silence, and the runner refuses a retry
  while a ticket runs (`canRetry` in `dsh: src/core/stage.ts`).
- The tests: `agent_signal_test.exs` and `agent_worktree_test.exs` (the
  signal), `work_test.exs` (the lane, its text and its order),
  `announcer_test.exs` (spoken once) and `board_stall_test.exs` (rendered in
  both lanes).

## Automatic retry

The board's first write in the runner (the ceiling, under Boundaries, is the
other), authorized by the owner on
2026-11-07 after a reboot left six tickets `failed` on a dead network
(ADR-0003, "Retentativa automática"). `AgentBoard.AutoRetry` asks
`POST tickets/<id>/retry` (`Orchestrator.retry/2`) and nothing else; the
board still never writes the runner's sqlite.

- **Only a transient failure.** The latest Assignment's report is `failed`
  and `AgentFailure.classify/1` reads its summary as the network or the
  provider: the model's transport, a host that did not resolve, a
  connection refused or reset, a timeout, a rate limit, a 5xx. An unknown
  text, a refused credential, a test failure or a command the runner
  aborted at its own deadline need a person. A prepare failure that left
  files in the ticket's directory needs a person too: the runner would
  take them for a prepared worktree (`dsh: src/executor/dsh.ts`,
  `PrepareFailed`).
- **Three retries per streak, after 1, 5 and 15 minutes.** The streak is
  the trailing Assignments that failed, counted from the runner's own
  `endedReason: "retried"` (whoever asked), back to the last report that
  was not a failure. A fourth failure is `:exhausted`: the owner decides.
- **Once per Assignment.** A row in `agent_retries` (unique
  `assignment_id`) is claimed before the request; a board restart or a
  second board on the same database cannot ask twice. Only an unanswered
  request (`unreachable`, `timeout`) may be claimed again, after 60 s and
  while the same Assignment is still the latest failure. The runner's
  `canRetry` is the second guard: it refuses a ticket whose latest
  Assignment did not fail.
- **Only when the orchestrator answers.** A tick with something due asks
  `GET /state` first and sends nothing when it fails; a tick with nothing
  due sends nothing at all.
- **Every request is recorded**: the row, a log line `auto_retry ticket=…
  outcome=…`, and an `agent_retry` event (`agent_retry_error` when the
  runner refused or did not answer) in the activity of each repository the
  ticket worked.
- **Switch:** `AGENT_BOARD_AUTO_RETRY=0` (`config :agent_board,
  auto_retry: false`) makes a board read-only again, for a second board on
  another database.
- **Why not the runner's own retry:** the runner retries a turn that failed
  for a passing reason three times within about two minutes (15/30/60 s,
  constants in `dsh: src/executor/dsh.ts`, not configurable) and never
  retries a failed prepare on purpose; an outage longer than that, like a
  boot without network, ends in `failed` and waits for a person.
- The tests: `agent_failure_test.exs` (the classification),
  `auto_retry_test.exs` (plan, delays, streak, limit, once per Assignment,
  orchestrator down, unanswered and refused requests, the switch) and
  `orchestrator_test.exs` (the request and its reasons).

**What the board shows** (`AgentBoard.AgentBlock`, one source for the card,
Agora and the detail):

- A ticket the board retries by itself is `retrying` (`Sync.ticket_state/2`
  asks `AutoRetry.plan/2`; a retry still waiting for a worker is
  `retrying` too). It is a row in **Agora**, after the running cards, not an
  item in Precisa de você: nobody has to act, the system is on it, and
  Agora is where the board says what is happening now. The row says what
  failed and when the next attempt goes out ("Falha de rede ao chamar o
  modelo. Nova tentativa automática às 14:20 (2 de 3)."). Entering
  `retrying` is silent (`Announcer`); leaving it for `blocked` is the call.
- When the retries ran out or the failure is not transient, the task is
  `blocked` and its item in Precisa de você says what failed and the step
  left to the owner, never only the raw error.
- When the orchestrator does not answer `GET /state` (asked once per load,
  the same answer as the throughput strip), the blocks and silences collapse
  into **one** item, "Agente fora do ar", with "Religar o agente". A board
  with the API switched off does not know, and collapses nothing.
- The detail of a failed task shows the headline, what the system will do,
  what is left to the owner, the whole error and every Assignment as an
  attempt (when, what happened, whether the board or a person asked for the
  retry).
- **Every action asks first** (`AgentBoardWeb.BoardComponents.AgentAction`):
  the first click shows what will happen, only the confirmation acts, the
  button shows a loading state and the result stays in place.
  "Tentar de novo" / "Tentar agora" is the same `POST tickets/<id>/retry`,
  asked by the owner and recorded as `agent_retry_manual`; "Parar" keeps
  the board's stop (`act`), now behind a confirmation; "Religar o agente"
  runs the prototype's manager (`python3 scripts/dsh-superagent start`,
  idempotent, `DSH_SUPERAGENT_HOME`) on this machine, never from the
  browser, and clears a stop made on purpose because the owner asked.
- The tests: `agent_block_test.exs` (every sentence), `sync_test.exs`
  (`retrying`), `work_test.exs` (the item, the Agora row, the collapse),
  `announcer_test.exs` (quiet, then the call), `agent_control_test.exs`
  (both actions and their sentences) and `board_agent_failure_test.exs`
  (rendered lanes, confirm, cancel, loading, result, Parar, Religar).

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
  **Bounded retry** (`AgentBoard.ElevenLabs.Retry`, decided with the owner
  on 2026-11-07): only failures with nothing to pay for are retried — a
  transport error before a response, a 429 (honoring `retry-after` up to
  2 s) and a 500/502/503/504 — at most twice, with a growing delay; a 4xx
  about the key, voice or text is final, and a stream is never retried after
  its first chunk reached the browser. Every retry is a voice activity
  event. The AI calls keep "no retry" below. The key never reaches the
  browser: the endpoints answer with audio or a transcript.
- **ElevenLabs spending is a ledger** (`AgentBoard.ElevenLabs.Usage`, table
  `eleven_labs_usage`, one row per UTC day): the client records every paid
  TTS answer (characters from `x-character-count`, else the text length) and
  every transcription (`audio_duration_secs`) where the 200 arrives; the
  controller records cache hits at zero cost. A retried failure records
  nothing. `over_cap?/0` compares today with `ELEVENLABS_DAILY_CHAR_CAP`
  (default 20000, 0 = none) and the call that crosses it records one voice
  activity event a day; the cap itself never refuses a call, the voice
  routing reads `over_cap?/0`. A ledger write that fails is logged and
  skipped, never a failed speech. `GET /api/voice/status` and the
  "Bastidores da voz" summary show today's totals.
- **Voice activity** (`AgentBoard.Voice.Activity`): each stage of a turn,
  every retry and every failure (server, or browser via
  `voice_client_error`) is one event: a log line `voice stage=… status=…`,
  a broadcast on the `"voice:activity"` PubSub topic shown live in the
  voice panel ("Bastidores da voz"), and an entry in a 60-event ring. It
  never carries a secret or a whole utterance.
- **Settings forms opt out of form recovery** (`phx-auto-recover="ignore"`):
  they mirror saved settings, and recovery re-sent them on every reconnect
  (a picker without a value crashed the board; the language confirmation
  replayed). `BoardLive.handle_event/3` ends with a clause that records an
  unexpected event instead of raising.
- The voice the agent speaks with resolves in this order: the environment
  (`ELEVENLABS_VOICE_ID`) → the pick saved in the UI (`AgentBoard.Settings`,
  key `elevenlabs_voice_id`) → the default (George). The TTS model resolves
  the same way (`ELEVENLABS_TTS_MODEL` → `elevenlabs_tts_model` → the
  default `eleven_flash_v2_5`); a saved model must be one of the offered
  `AgentBoard.ElevenLabs.tts_models/0`. The Voice section of the settings
  menu lists the account's voices and **saves a voice when it is picked**,
  like every other field there (a separate "Salvar" left picks unsaved);
  the name is kept with it (`elevenlabs_voice_name`, filled from the list
  when missing) so the picker names the voice in use after a reload, and a
  note says what that voice speaks under the chosen engine. It previews
  through `/api/voice/speech?voice=...`, the API saves with
  `PUT /api/voice/settings`,
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
- **Settings are board-wide and live**: `AgentBoard.Settings.put/2`
  broadcasts `{:setting_changed, key}` on the `"settings"` topic and every
  `BoardLive` re-reads its voice assign, so a change in another tab, by the
  API or by a spoken command reaches every open board without a reload.
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
- **The spoken conversation** (`docs/voice-conversation.md`) is the default
  for a double Space outside the composer: the `VoiceCommand` hook ends the
  turn on silence and pushes `voice_turn`; `AgentBoardWeb.VoiceConversation`
  records it, runs `AgentBoard.Conversation.Agent` keyed by a `ref` (a newer
  turn cancels an older one, `:voice_turn_timeout_ms` drops a slow one) and
  speaks the reply. Memory is `voice_turns` (summary + recent turns); the
  model call is `:voice_agent`, the summary `:summarize_conversation`.
  **Writes wait for a spoken yes**: create, stop and archive become a
  proposal (`proposal_status`), settled once by a conditional update; yes
  and no are recognized locally. `:voice_agent` refines a request itself
  (title, acceptance criteria, or one question): no second model call.
  The one exception is a **direct create**: only when the owner says so
  ("cria direto", the model's `direct` flag) the task is created at once,
  recorded as `%{"kind" => "created"}` with `proposal_status` `done`, and
  "desfaz" closes it (`Board.stop_task/2`) within 10 minutes, claimed once
  (`done` → `undone`). A task that already existed is never undoable.
- **Voice reads** (`look`) never write: `AgentBoard.Conversation.Lookup`
  reads the board's own data (tasks, PRs, the runner's tickets, the voice
  activity ring) and the registered `:voice_explain` call answers only from
  those facts, with ages precomputed in minutes. A missing task, an empty
  search or no project is said without a model call. The catalog the owner
  sees ("O que posso pedir", the spoken "ajuda") is
  `AgentBoard.Voice.Commands`; a new lookup kind is added there and to the
  `:voice_agent` schema together (a test compares them). "Status",
  "ajuda", "desfaz", "repete" and the voice adjustments are local: no
  model, no cost.
- **Playback** goes through `/api/voice/stream` (ElevenLabs streaming) and
  `AgentBoard.ElevenLabs.SpeechCache` (short texts, keyed by every input
  that changes the audio, bounded, off in tests; ETS in front of the
  durable `voice_speech_cache` table, so a fixed phrase is paid once, not
  once per restart). Every spoken text passes
  `AgentBoard.Voice.Speakable.clean/1` (via `AgentBoardWeb.VoiceSpeech`).
  Speed (`voice_speed`), intonation (`voice_style` → stability), pause
  (`voice_pause`) and microphone sounds (`voice_earcons`) are settings. The conversation never reaches the coding
  agent except through the board actions a button would take.
- **Cost defaults** (owner's decision, 2026-11-07): the owner's speech comes
  from WisprFlow typing into the board (`voice_input` = `wispr`, the
  `VoiceWispr` hook sends a dictated text once it settles); the board's own
  recorder and ElevenLabs Scribe are the opt-in `microphone` input. Every
  utterance is routed by `AgentBoardWeb.VoiceSpeech.push/3`: the free browser
  voice by default (`voice_engine` = `browser`), ElevenLabs only for calls in
  `mixed` or for everything in `elevenlabs`, and never without a key or past
  the day's cap. Free replies speak their first sentence (`voice_replies` =
  `short`); narration (`voice_narrate`) is off by default.
- **Voice asks** are a write and always confirmed: the conversation's
  `ask_task` action becomes a proposal naming the task and the question,
  and only the spoken yes posts it (`Board.ask/3`, a comment with
  `@sallaumen-agent`). Its reply — the first new agent comment on the task
  after the confirmation that is not the workpad, within a day — is spoken
  once on a board update (`Conversation.arrived_answers/1`, claimed by the
  conditional `mark_answered/1` so a second tab stays quiet), joins the
  memory and is silenced by `voice_attention`. "Repete" and "mais devagar/rápido/alto/baixo" are
  local commands of the conversation, no model. The old draft panel
  (`VoiceCommand.draft`, `VoiceMutations`, `VoiceActionConfirmation`) was
  removed; `AgentBoardWeb.VoiceCommands` stays as the no-model fallback and
  `AgentBoardWeb.VoiceAnswer` only feeds the board AI evaluation.

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

## Executor usage (Executor do agente)

- The board's own calls are rows in `ai_calls` (above). The **executor's**
  calls are not the board's: `AgentBoard.ExecutorUsage` reads them from the
  harness transcripts, `~/.dsh/sessions/<ticket directory with / as ->/<session>/session.v4.jsonl.zstd`
  (`:dsh_sessions_dir`), one per worker and one per subagent. It only reads;
  nothing is stored in `tasks`, `ai_calls` or the runner's sqlite.
- **Tokens are measured**: each `assistant/message` counts once (by
  `data.message.id`), summing `data.usage` input, output, cache read and
  cache write. Input excludes cache reads.
- **Cost is an estimate** from `AI.Providers` prices, matched by model id
  (`prices_for_model/1`). A token kind without a price (cache reads today)
  makes the cost a minimum, shown `≥`; a model without a price makes it
  unknown, shown `—`. Never zero for "no price".
- It is read only while a task is open in the inspector, and a reading is
  reused while no transcript changed (same files, sizes, mtimes). Without
  `zstd` on the PATH (the launchd service's PATH includes Homebrew) the
  transcripts are `:unavailable`, not empty. OTP 27 has no native zstd.
- The encoded folder name was observed in `~/.dsh/sessions`, not documented
  by the harness; a harness upgrade can move it. Reconciled on 2026-11-07
  against an independent count of one finished ticket (302 requests,
  232,749 input, 238,848 output tokens in its worker).
- The tests: `executor_usage_test.exs` (parsing, dedupe, folder name, cost,
  no `zstd`, reuse) and `inspector_test.exs` (rendered states).

## Executors

A task the board creates can be for the DeepSeek runner (`dsh`), Claude
Code (`claude`) or Codex (`codex`): `tasks.executor`, nil for an issue the
sync found or a task created before the choice existed.

- **The runner is dispatched by the mention, and only the runner.** Its
  issue ends with `@sallaumen-agent`; anyone else's mentions nobody, and a
  mention inside the text loses its `@` (`Executors.issue_body/2`). Every
  board issue for an executor carries the label `executor:<name>`, which
  GitHub creates on first use.
- **Choosing Claude Code or Codex records the choice; nothing starts them**
  (decisions D1 to D5 are open, `docs/research/alfred.md`).
- **Why the runner leaves those issues alone, and its limit.** The board
  opens issues as `sallaumen`, a listed sender. An issue without the
  mention is a `listedUnaddressed` message: the runner admits it as an
  *inferred* candidate and runs its evaluation, and with `eval.mode`
  `observe` (read 2026-11-07) an inferred acceptance only becomes
  `observed`, never a ticket (`dsh: src/policy.ts`, `assessmentOutcome`).
  Observed live on 2026-11-07 with `sallaumen/arena-rogue#69` (decision
  `ignore`, strength `inferred`, no ticket) and before on `#14`. With
  `eval.mode` `auto`, an issue matching the copy or visual rule would become
  an inferred ticket; the unconditional guard is the runner's setting
  `listedUnaddressed: ignore` for issues, which belongs to the owner.
- The tests: `executors_test.exs` and `create_request_test.exs` (the body
  and the label GitHub receives, the stored executor, a repeat).

## Attribution

Which task an executor's session or a PR worked for
(`AgentBoard.Attribution`, pure; `docs/research/alfred.md`, 3.4). The sync
writes what it needs from the pull it already fetches, at no extra call:
`pull_requests.head_ref` (`head.ref`, `nil` for a fork's branch, which does
not exist in this repository) and `pull_requests.closes_issues` (the issues
the body closes with GitHub's keywords, `Closes #n`, `owner/repo#n` or the
issue URL of the same repository, in the order named).

| Rule | Holds when | Result |
|---|---|---|
| exact | the session carries its task id (dispatched, or a DSH ticket's issue) | `{:task, id, :exact}` |
| pr-link | a Claude Code `pr-link` names a stored PR whose body closes a task's issue | `{:task, id, :pr_link}` |
| branch | the session's branch is the `head_ref` of a PR in the same repository that closes a task's issue (`HEAD` is not a branch) | `{:task, id, :branch}` |
| repository | the remote, a `pr-link` or the project folder names one board repository | `{:repository, id}` |
| outside | none of the above | `{:outside, folder}`, or `:unknown` with no folder |

- **A PR without `Closes #n` has no task.** The board never guesses by
  title, branch name or the conversation: a session is metadata the reader
  chose field by field.
- The first closed issue that is a task wins; a folder name two board
  repositories share picks neither.
- The tests: `attribution_test.exs` (each rule and keyword) and
  `sync_repo_test.exs` (the columns through the sync, the fork, a session
  attributed by branch).

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
- **The split classifies, the task keeps it.** `:propose_tasks` answers each
  task's `kind` (where the work lands: `ui`, `backend`, `docs`, `bug`,
  `research`, `infra`) and `size` (`S`, `M`, `L`), from the lists
  `Task.work_types/0` and `Task.sizes/0` that the registry's schema reads,
  so an answer outside them is `:malformed_output`, never a default. The
  chosen tasks store them in `tasks.work_type` and `tasks.size`; the review
  list, the receipt and the inspector show them in Portuguese ("UI · P",
  `WorkTag`). A single request, a voice task or a synced issue has neither,
  and shows nothing.

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
  It writes to the runner only through the API, twice: the automatic retry
  above, and the ceiling when the owner clicks − or + in the Paralelismo
  tile (`set_max_workers/2`: `GET settings`, then `PUT settings/executor`
  with the whole block and the revision it read; a save in between is a
  conflict, never an overwrite; 1..16, the runner's range). Changing only
  `maxWorkers` does not restart the runner (`worker_limit_test.exs`).
- The web layer never talks to GitHub directly: it goes through `AgentBoard.Board`
  and `AgentBoard.GitHub`.
