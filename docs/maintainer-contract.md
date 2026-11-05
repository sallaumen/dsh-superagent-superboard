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
| `AgentBoard.AI` | the door to a model: registered calls only, every one a row |
| `AgentBoard.Intake` | a free-text request -> refined spec -> tasks |
| `AgentBoard.Settings` | board-wide settings, one row per key (the voice picks) |
| `AgentBoard.Voice` | the spoken summary (the model writes it when it can) |
| `AgentBoard.ElevenLabs` | the server-side voice client: TTS, STT, voices |
| `AgentBoardWeb.BoardLive` | the real-time UI |
| `AgentBoardWeb.BoardController` | the JSON API (`/api/...`) |
| `AgentBoardWeb.VoiceController` | the voice API (`/api/voice/...`) |

## The data

- **Ecto migrations** own the schema. Never edit a migrated table by hand; add a
  migration.
- The task state is two-layered: the **issue** is the baseline (`open` →
  `queued`, `closed` → `done`) and the **ticket** is the overlay (`running`,
  `ready`, `blocked`) while the issue is open. A stopped or archived task keeps
  its state.
- A review rollup is the strongest review (`changes_requested` beats `approved`);
  a check rollup names the failing check.

## Real-time

- The sync (the Oban `Sync.Worker`, every minute) and every task action call
  `Board.broadcast/1`; the LiveView subscribes with `Board.subscribe/1` and
  reloads on `:board_updated`.
- `AgentBoard.Live` polls the agent's tickets every 10s and broadcasts only
  when their hash changed — the runner state reaches the board without waiting
  for the sync. It is idempotent: the same tickets never broadcast twice
  (`live_test.exs`). The interval is the `:live_poll_interval` knob; the test
  environment stretches it to an hour so the supervised poller never ticks
  into the sandboxed database mid-suite.
- Never poll the database from the browser; push.

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
- **Automatic speech** is `AgentBoard.Announcer`: a pure diff between the
  previous and the current board. The agent speaks task overlays moving
  between the live lanes and sync outcomes getting worse, capped at two
  utterances per update and deduped for a short window; user actions speak
  their own confirmations, so they are not announced twice. The settings
  key `elevenlabs_speak_events` (`"0"` disables, absent is on) is the
  toggle; the UI checkbox writes it and `PUT /api/voice/settings`
  accepts `speak_events`.
- The **voice ask loop**: the conversation's mic button records and
  transcribes a question into the ask form, and the asynchronous answer is
  spoken back in the agent's voice (cut at a word boundary). The recorder
  hook fills whatever `data-target` names (`#task-title` by default).

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
  `pull_error` and `comment_error` in that run.
- **sync failed … · showing saved data**: a newer `sync_error` supersedes the
  completed sync. `Board.latest_sync/1` reads the latest outcome independently
  of the 20-event activity window. With no outcome, it says `no sync yet`.

The header is the health line: if it says errors, open the activity panel,
where each failing item is one row.

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
| the repository itself fails | `sync_error` | returns `{:error, exception}` and Oban retries |

Every branch returns `:ok` or logs; nothing swallows an error silently and
nothing takes the whole sync down for one bad item. Each branch has a test in
`sync_repo_test.exs`.

## Boundaries

- The board **reads** the agent's state (the sqlite); it never writes to it.
- The web layer never talks to GitHub directly: it goes through `AgentBoard.Board`
  and `AgentBoard.GitHub`.
