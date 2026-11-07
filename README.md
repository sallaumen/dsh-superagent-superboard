# agent-board

The board for the agent's work, in Elixir: **Ecto** for the data, **Oban** for
the durable sync, **LiveView** for the real-time UI and **Req** for GitHub.

## Why Elixir

- The **sync is a durable job**, not a hand-rolled loop: Oban retries it, the
  supervisor restarts it, and the dashboard shows it. Cron runs it every five minutes.
- The **board is real-time**: a `Phoenix.PubSub` broadcast updates every connected
  LiveView when the sync or an action changes a task — no browser polling.
- The **data is migrations**, not a SQL file applied on boot: Ecto owns the
  schema, the changesets and the history.
- **One language** across the board, the sync and the web layer.

## Run it

```sh
mix setup            # deps, database, assets
PORT=4002 mix phx.server  # http://127.0.0.1:4002
```

The explicit `PORT` keeps the example URL deterministic; runtime configuration
otherwise uses the environment or its own default. The dev database is on the
local Postgres at `127.0.0.1:5434`.

## Run as a service

The board is meant to be always on. [ops/com.agentboard.plist](ops/com.agentboard.plist)
is a launchd example with absolute paths for one checkout; before loading it,
set `ProgramArguments`, `WorkingDirectory`, the log paths and the toolchain `PATH`
for your machine. It runs [scripts/service.sh](scripts/service.sh); its defaults
and environment overrides are documented in the [script matrix](PIPELINES.md#matriz-de-scripts).

```sh
mkdir -p ~/Library/LaunchAgents
cp ops/com.agentboard.plist ~/Library/LaunchAgents/com.agentboard.plist
# Edit the copied plist with the paths described above before loading it.
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.agentboard.plist
```

`KeepAlive` restarts the board after a crash or an update; `RunAtLoad` starts
it with the system. The plist names the log in `AGENT_BOARD_LOG`; at every
start `scripts/service.sh` moves it to `<log>.1` once it passes 50 MB
(`AGENT_BOARD_LOG_MAX_BYTES`), keeping one old copy, and reopens it, as the
`o_colmex` hive does. The plist's `StandardOutPath` only catches what fails
before that. A manual run without `AGENT_BOARD_LOG` writes to the terminal.

The board cannot boot without its Postgres on `127.0.0.1:5434`, and launchd
starts the script before Docker has brought containers back. If that Postgres
runs in Docker, give its container a restart policy (`restart: unless-stopped`
in its compose file, or `docker update --restart unless-stopped <container>`):
without one, Docker leaves it stopped after a reboot and the board never comes
up. `scripts/service.sh` waits for the database before migrating, up to
`AGENT_BOARD_DB_WAIT` seconds (300), then exits and launchd tries again. The
**Atualizar e reiniciar** button is in **Configurações → Versão** and appears
after **Verificar** when the checkout is behind; the service log records the
deps/migrate/boot sequence.

```sh
launchctl bootout "gui/$(id -u)/com.agentboard"   # stop for good
launchctl kickstart -k "gui/$(id -u)/com.agentboard"  # restart now
```

Unlike the `o_colmex` updater, **nothing here updates on a timer**: the board
watches agents, and a restart would interrupt them. Updating is a button.

On a checkout already running the new code, **Atualizar e reiniciar** fast-forwards
to `origin/main` and then restarts; a successful update always gets a clean boot,
and a changed `mix.lock` or config file is never hot-reloaded. Under
`scripts/service.sh` the updater sets
`AGENT_BOARD_RESTART_MODE=supervised`, stops, and lets launchd boot the new code
(the script refreshes deps and migrations first). A bare `mix phx.server` instead
starts a detached shell and logs to `agent-board-update-restart.log` in the system
temp directory. The page keeps the old assets until you accept the **Recarregar**
notice, so a restart cannot leave the browser on a dead navigation.

## Logs

The board logs with a timestamp on every line. `LOG_LEVEL=debug|info|warning|error`
picks the level (the `scripts/service.sh` service on 4099 runs at `info`; dev
defaults to `debug`, which logs every SQL query). Voice pipeline lines start
with `voice stage=`; the same events show live in the voice panel. See
[docs/voice-conversation.md](docs/voice-conversation.md#diagnóstico-logs-e-bastidores).

## Local secrets

`.env.local` feeds the environment before any config: `KEY=value` lines, `#`
comments, and a variable already set to a non-empty value in the shell is left alone. It is
gitignored. `.env` is the committed list of variables -- copy what you need.

```sh
cp .env .env.local        # then fill DEEPSEEK_API_KEY, GEMINI_API_KEY or OPENAI_API_KEY
```

The app picks the first provider with a key; `AI_PROVIDER` pins one. Without
any key the AI answers `:not_configured`, and `AI_REHEARSAL=1` runs the whole
panel against free fixtures instead. Tests never read `.env.local`.
`AGENT_BOARD_ENV_FILE` selects another file, for example when running a worktree.
The loader lives in [config/runtime.exs](config/runtime.exs).

## What it does

- **Syncs** the tracked repositories' issues and pull requests (the Oban
  `Sync.Worker`, one cron run every five minutes).
- **Syncs reviews and CI** per pull request: `review_state` (approved, changes
  requested, pending) and `checks_state` (success, failure, pending), with the
  failing check named.
- **Reads the agent's tickets** (read-only, from the mounted sqlite) and overlays
  the live state on the issue: running, ready, blocked — while the issue is open.
- **Creates a task** by opening a GitHub issue that mentions the agent.
- **Stops** (the flag plus closing the issue) and **archives** a task.
- **Speaks**: "Speak status" reads the board out loud (the Web Speech API);
  "Dictate task" turns a sentence into a task title.
- **Speaks back, unprompted**: the board announces what changed in the
  agent's voice — task overlays moving between the lanes, syncs getting
  worse, answers to spoken questions — and the mic in the task conversation
  records a question straight into the ask form. The toggle lives in the
  Voice settings.
- **Speaks back**: the ElevenLabs client (`AgentBoard.ElevenLabs`) generates
  server-side speech and transcription at `/api/voice/...` — text to speech,
  speech to text and the account's voices, with the key read from
  `ELEVENLABS_API_KEY` in `.env.local`, never from code. The **Voice** section
  of the settings menu configures the agent's voice: list the account's voices and
  preview each one, pick the TTS model (flash-fast vs v4-quality), save —
  the choices persist in the database and `ELEVENLABS_VOICE_ID` /
  `ELEVENLABS_TTS_MODEL` in the environment override them. From the same
  section the agent speaks the board status aloud and dictates a task
  (mic recording → ElevenLabs Scribe → task title).
- **Exposes a JSON API** under `/api` — the board, the repositories and the
  task actions; documented in [docs/api.md](docs/api.md).
- **More docs** — the AI-layer plan and the recorded decisions live in
  [docs/](docs/README.md).

## What it costs

- **The sync** reads a bounded window of recently updated issues and pull
  requests per repository, plus each pull's reviews/checks and active task
  comments. Each scheduled run produces GitHub API traffic. The window lives in
  [AgentBoard.GitHub](lib/agent_board/github.ex); the comment selection lives in
  [AgentBoard.Sync](lib/agent_board/sync.ex). Check those limits when estimating
  traffic for a deployment.
- **The 10s poller does not touch GitHub**: it reads the agent's sqlite and
  only broadcasts when the ticket hash changed.

## Validation and contributing

Use [PIPELINES.md](PIPELINES.md) for the command matrix, local checks and CI
jobs, including the
[procedure when CI is unavailable](PIPELINES.md#se-a-ci-não-consegue-rodar-sem-token-billing-ou-runner).
The branch and pull request workflow is in [CONTRIBUTING.md](CONTRIBUTING.md).

## When something is wrong

| Symptom | Cause | Fix |
|---|---|---|
| `no sync yet` in the header | no sync outcome recorded yet | wait for the next sync and inspect Activity |
| `sync failed … · showing saved data` | the latest repository sync failed | open Activity from the health line; `sync_error` names the cause |
| a repo with Issues disabled | GitHub answers 404 | handled: issues are optional, pulls still sync |
| `No task is running.` | the runner has no active ticket | not an error; it is the empty state |
| every card says `no review` / `no ci` | the repo has no reviews or CI | accurate, not a bug |
| CI red on every PR | GitHub Billing: payments failed / spending limit | fix Billing & plans; no code change turns it green |
| `sync_error` with 401/403 | `GITHUB_TOKEN` missing, expired, or rate limited | export a fresh token (`gh auth token`) |

## The tests

`mix test` covers each layer: the state mapping (the ticket overlay, the review
and check rollups), the voice summary, the ElevenLabs client (stubbed, no
network), the sync against a fake GitHub (no network), the JSON API controllers
(board and voice), the LiveView (the columns, the empty state, the voice
events, the PubSub broadcast) and the pipeline contract.

## The limits

- The board is **eventually consistent**: the poller reads the runner every 10s
  and the GitHub sync runs every five minutes, so a merged PR can take up to that
  long to show up.
- The **poller is a one-shot per tick by design now**: `handle_info(:poll)`
  reschedules before polling, so a slow poll delays the next tick instead of
  stacking them (the interval is a floor, not a guarantee).
- **Stop** is the board's flag plus closing the issue. A worker already running
  finishes its current ticket: the Super-Agent API has no cancel endpoint.
- The board **reads** the agent's state; it never writes to it.
- The spoken summary uses the browser's Web Speech API; server-side TTS and
  STT (ElevenLabs) live behind `/api/voice` and answer with a reason on
  failure, never a raise.

## Shared agent practices

The board consumes [Elixir Agent Kit v0.6.0](https://github.com/sallaumen/elixir-agent-kit/releases/tag/v0.6.0)
through a public, pinned Mix dependency available only in development/tests.
No download token or application startup is required.

After `mix deps.get`, use [.elixir-agent-kit/START.md](.elixir-agent-kit/START.md).
It points to the dependency's contract and workflows. Only the small index,
ownership state and references in `AGENTS.md`/`CLAUDE.md` remain in this project;
there are no copied workflow bodies or per-skill native wrappers.
The dependency's routing guide groups practices into frontend, backend and data,
code structure and quality, operational domains, and delivery; each workflow
includes concrete quality and validation criteria. The installer also generates
one pointer skill per client under `.claude/skills/` and `.agents/skills/`.

`mix agent_kit.check` validates those references against the loaded version and
configuration. `mix gate`, `make library` and CI run that check. A fresh checkout
needs dependencies fetched before agents can read practices; a harness must allow
direct reading of ignored `deps/` files. A DeepSeek executor needs those files and
instruction loading in its actual worktree. Live client behavior is not certified
by successful installation.

`mix agent_kit.outdated` explicitly queries stable public release tags. Review a
release, update the pinned tag, run `mix deps.update elixir_agent_kit`, then
`mix agent_kit.sync --dry-run`, `mix agent_kit.sync` and the required checks.
There is no background update. Preserve modified generated files before restoring
their recorded originals; never delete ownership state to bypass a conflict.

Reusable improvements go to the kit; local rules remain here. The former
Portuguese collection is retired as an editable source. See
[ownership and migration](docs/agent/practices.md) for the full disposition.
For other projects, use the [AI installation/migration prompt](https://github.com/sallaumen/elixir-agent-kit/blob/v0.6.0/docs/INSTALL_WITH_AI.md).
