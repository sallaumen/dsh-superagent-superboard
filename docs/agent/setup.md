# Setting the agent up on another machine

For a first installation from Settings, use [Connect the Super Agent](../getting-started.md#connect-the-super-agent). This reference covers the bot account, profiles, startup and merge policy.

## 1. Prerequisites

Check the [agent requirements table](../getting-started.md#connect-the-super-agent) before setting up the bot account. On the host, run `dsh --version` to confirm the Harness CLI is available to the board.

### Alpine Linux (ARM64)

Tested with Alpine `3.24.3`, musl, Node `22.23.5`, pnpm `11.7.0` and Harness `0.2.1-rc.3`. In the board's OS account, use a **Node 22 build for musl** (for containers, the [official Node 22 Alpine image](https://hub.docker.com/_/node) provides it). Install `procps-ng`, Python 3, tmux, Git and GitHub CLI on the agent machine. The native npm build may also need `cmake`, `build-base` and `linux-headers`.

From the board checkout, install the CLI into a **dedicated directory**. The lockfile pins the audited dependency tree, including the Koffi build for musl. Use the same two files and `npm ci` to update this dedicated installation. An existing global Harness is not updated by the board.

```sh
node --version   # 22.19+ on the 22.x line
agent_tools="$HOME/.local/share/superboard/alpine-harness"
mkdir -p "$agent_tools"
cp scripts/agent/alpine/package.json scripts/agent/alpine/package-lock.json "$agent_tools/"
npm ci --prefix "$agent_tools"
export PATH="$agent_tools/node_modules/.bin:$PATH"
dsh --version
node priv/agent/check-alpine-harness.cjs "$(command -v dsh)"
```

The last command should exit successfully without output. Keep **this PATH and Node 22** in the environment that starts the board, including its service after a restart. Continue with the [bot login](#2-the-bot-identity) and confirm the installation in Settings.

**Why Alpine differs:** Koffi `3.1.1` tries its generic Linux binary before the musl binary. On the tested ARM64 system the generic binary aborted Node (exit `134`) as the Harness checked the GitHub account. Koffi `3.3.8` detects musl. Separately, the upstream manager looks for a process named `node` or `dsh`; the tested Alpine Node `24.22.3` reported `MainThread` (probe exit `42`). No version of a model or GitHub token fixes either condition.

## 2. The bot identity

The agent acts as its own GitHub account, never as you:

```sh
mkdir -p ~/.config/gh-agent
env -u GH_TOKEN -u GITHUB_TOKEN GH_CONFIG_DIR=~/.config/gh-agent gh auth login      # log in as the bot
```

Verify the separate sign-in **before** starting installation. The login below must be the bot, not the account used by the board:

```sh
env -u GH_TOKEN -u GITHUB_TOKEN GH_CONFIG_DIR="$HOME/.config/gh-agent" gh api user --jq .login
```

When you install through Settings, the board creates the bot wrapper at `~/.local/bin/gh-agent` if missing. For a manual installation, follow the [upstream account instructions](https://github.com/deepseek-ai/dsh-superagent-prototype/blob/main/docs/006-deployment.md#agent-github-account).

## 3. The profile

`~/.dsh/profiles/superagent/cordis.patch.yml`:

```yaml
- id: webserver
  config:
    host: 127.0.0.1
    port: 3082
- id: dsh-superagent
  config:
    stateDir: /Users/<you>/.dsh/state/superagent
- id: agent-default-model
  name: "@deepseek-ai/dsh-agent-default-model"
  config:
    provider: deepseek-account
    model: deepseek-flash
    reasoningEffort: high
```

The state directory is created on first start; it holds the sqlite, the
worktrees and the worker binaries.

## 4. Start it, and keep it up

The prototype's manager starts the orchestrator in the tmux session
`dsh-superagent`, writes its log under the prototype's `.artifacts/` and
refuses to start a second one:

```sh
cd <prototype>     # ~/Documents/deepseek-harness/default-workspace/dsh-superagent-prototype here
python3 scripts/dsh-superagent start     # idempotent; also clears a stop marker
python3 scripts/dsh-superagent status    # exit 0 = running and healthy
python3 scripts/dsh-superagent stop      # graceful; leaves the manually-stopped marker
```

`tmux new -s dsh-superagent && dsh --profile superagent` still works; the
manager finds that process and does not start another.

Nothing starts the orchestrator after a reboot on its own. The LaunchAgent
[`ops/com.dsh.superagent.plist`](../../ops/com.dsh.superagent.plist) runs
[`scripts/agent/keepalive.sh`](../../scripts/agent/keepalive.sh) at login and
every five minutes. The script asks the manager for `status` and, only when
the orchestrator is down and was not stopped on purpose, runs
`start --respect-stop`. A component error or a pending setup (status 2 or 3)
needs a person and is logged, never restarted. The paths in the plist are
this machine's; change them for another one.

Install it (once):

```sh
cp ops/com.dsh.superagent.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.dsh.superagent.plist
launchctl print gui/$(id -u)/com.dsh.superagent | grep -E 'state|last exit'
```

Run a check now, without waiting for the interval:

```sh
launchctl kickstart gui/$(id -u)/com.dsh.superagent
```

Stop the agent and keep it stopped: `python3 scripts/dsh-superagent stop` in
the prototype. The marker it leaves makes every later check skip the start;
`start` (or `restart`) removes it and the checks resume. To remove the
LaunchAgent itself:

```sh
launchctl bootout gui/$(id -u)/com.dsh.superagent
rm ~/Library/LaunchAgents/com.dsh.superagent.plist
```

Logs: `~/Library/Logs/dsh-superagent-keepalive.log` holds one line per action
the check took (quiet while the agent runs; moved to `.1` above 1 MB); the
orchestrator's own output is in the newest
`<prototype>/.artifacts/dsh-superagent-superagent-*.log` and in
`scripts/agent/logs.sh`.

### Opening the panel

The panel at `http://127.0.0.1:3082/` answers `dsh web authentication
required; reopen the URL printed by dsh web.` to a browser that never opened
the URL dsh printed when it started. That URL carries the process's launch
token and is in the manager's log; opening it once leaves a cookie in that
browser, and the plain address works from then on.

In the board, each project's controls (Configurações → Projetos, "Painel
dsh") have the button "Abrir o painel já autenticado": it opens the panel
signed in, in a new tab of the browser you are using. It works for a browser
on the machine where the agent runs. From a terminal, the same:

```sh
scripts/agent/panel.sh                     # the primary agent
scripts/agent/panel.sh superagent-colmex   # a second one, by profile
```

The script hands the URL to `open` and never prints it: the token is a
credential, so do not paste it into an issue, a chat or a commit. Each row in
Configurações → Projetos links to its agent's plain address, and the number
of agents is changed there or on the board's flow tile, without the panel.

### A second repository (optional)

One superagent watches one repository. To have DeepSeek on `o_colmex` while
the primary keeps `arena-rogue`, create a second profile and state:

```sh
cp -R ~/.dsh/profiles/superagent ~/.dsh/profiles/superagent-colmex
# edit cordis.patch.yml: webserver port 3083, stateDir
# ~/.dsh/state/superagent-colmex
mkdir -p ~/.dsh/state/superagent-colmex
cd <prototype>
python3 scripts/dsh-superagent --profile superagent-colmex \
  --url http://127.0.0.1:3083 start
```

In the new panel at `http://127.0.0.1:3083`, set the GitHub repository to
`owner/second-repo`, the agent CLI to the same `gh-agent`, the executor
directory/prepare command to the second clone, and the policy allowed list
(changed afterwards in Configurações → Projetos, per person and project).
The bot account needs write access to that repository (invite it, then accept
the invitation as the bot).

Install the second keepalive:

```sh
cp ops/com.dsh.superagent.colmex.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.dsh.superagent.colmex.plist
```

There is no routing list to fill in: the board suggests DeepSeek for the
repositories of the agents listed in Configurações → Projetos.

`AgentState` reads both `~/.dsh/state/superagent*/orchestrator.sqlite` files,
so the board shows both DeepSeek lanes without a restart of the agents.

On a machine that never had an agent, the board does this document's steps
3 and 4 itself: "Adicionar projeto" in Configurações → Projetos installs the
first agent once `dsh` is on the machine and the bot is signed in (§2), and
"IAs e setup" says which of the two is missing.

An agent set up this way is not on the board yet. Configurações → Projetos
lists it under "Agentes nesta máquina que o board não acompanha"; "Adicionar
ao board" asks the agent which repository it serves and registers it.

## 5. Verify it is configured and alive

```sh
scripts/agent/status.sh
```

It must print:

- `health.runtime.state = ready`
- `health.relay.state = ready`
- `paused = false`
- `accounts.repository` = the repo it may touch
- `accounts.agent` = the bot login
- `problem` = null

If `problem` is not null, it names the fix. Nothing else in this document is
worth debugging until it is null.

## 6. First task

Open an issue in the tracked repository and mention the bot:

```
@sallaumen-agent implement X
```

Then:

```sh
scripts/agent/tickets.sh     # the ticket appears within seconds
```

The ticket goes `progress` -> `ready` and the PR appears in the issue thread.

## 7. Shared practices in the executor's worktree

The executor reads `AGENTS.md` in its own worktree under
`~/.dsh/state/superagent/work/`. That worktree is a fresh checkout: the
practice index `.elixir-agent-kit/START.md` links into `deps/`, which exists
only after `mix deps.get` runs there. `mix gate` fetches nothing on its own.

- Run `mix deps.get` in the worktree before the executor follows the index,
  through the harness's per-worktree bootstrap when it has one, otherwise as
  the first step of the assignment. Until then the index is a dead link and
  the instruction block tells the agent to report the missing setup.
- **When the kit tag moves** (the repository's `mix.exs` pins a newer
  version), nothing manual is needed beyond `mix deps.get`: a fresh worktree
  already fetches the new pin; an existing worktree fails its next
  `mix gate`/`mix precommit` with the lock-mismatch error, whose message says
  to run `mix deps.get` — run it and continue. `mix deps.get` only fetches
  and checks out the pinned dependencies; **it never compiles the project**.
  Compilation happens only in the gates the delivery prompt requires
  (`mix precommit` on the head), so do not build or test code the assignment
  does not touch. `mix agent_kit.check` (part of the gate) verifies that the
  index matches the loaded dependency.
- Treat a `ready` report as evidence only for what it names. A report that
  names no practice file read means the kit was not loaded; a model name
  establishes nothing. The kit's
  [compatibility note](https://github.com/sallaumen/elixir-agent-kit/blob/v1.0.0/docs/compatibility.md)
  describes the fresh-session check.
- **Recommended: [Ponytail](https://github.com/DietrichGebert/ponytail) on
  every executor.** It keeps the executor to the least new code that solves the
  ticket, while the kit still decides the workflow, the checks and the
  evidence; where they disagree, this repository's instructions and the kit
  win. DeepSeek Harness has no Ponytail plugin, so install it
  instruction-only, once per machine: clone Ponytail at a release tag, link its
  `AGENTS.md` to `~/.dsh/AGENTS.md` and each folder in its `skills/` into
  `~/.dsh/skills/`. Every dsh profile reads that home, so the `superagent`
  executor and a second repository's profile both pick it up on their next
  session; nothing in the profile changes. The default level is `full`
  (`~/.config/ponytail/config.json`). Claude Code and Codex install it as a
  plugin; see the kit's
  [companion setup](https://github.com/sallaumen/elixir-agent-kit/blob/main/docs/compatibility.md#recommended-companion-ponytail).
  For a kit evaluation round, record the Ponytail level with each run, or
  rename `~/.dsh/AGENTS.md` for the round to run without it.

## 8. Merge policy

The managed worker CLI enforces the [project merge checks](merge-checks.md). Delivery requirements tell the worker when to request that operation. The three team sections --
Communication, Ticket scope and Delivery requirements -- are versioned in
[`prompts/communication.md`](prompts/communication.md),
[`prompts/scope.md`](prompts/scope.md) and
[`prompts/delivery.md`](prompts/delivery.md) as the literal text the orchestrator holds, next to
`revision`, the revision they were read from.

**Applying them is a click, not a command.** Those three files are the
board's policy (`AgentBoard.Superagents.Policy`): they reach every board with
an update, the Attention bell says when an agent holds another text, and
Configurações → Projetos → the project's controls → "Instruções do agente"
shows what differs and applies it. Nobody who uses the board needs a terminal
for this. The script below is the maintainer's tool for the files themselves
(reading what the dsh panel holds into git, comparing):

```sh
scripts/agent/prompts.sh get    # write the active sections and their revision to the files
scripts/agent/prompts.sh diff   # compare the files with the active revision; exit 1 if they differ
scripts/agent/prompts.sh put    # save the files as a new revision
```

The panel and the API (`GET`/`PUT http://127.0.0.1:3082/orchestrator/api/prompts`,
header `x-orchestrator-request: 1`, body `{config, baseRevision}`) read and
save the same text. `put` refuses when the panel saved a revision newer than
`revision`, so an edit made there is never overwritten unseen: run `get`,
review the change, commit it, then `put` again. To change the policy, edit
the file in a PR, merge it, run `put`, and commit the new `revision`. Team
skills and overrides of built-in parts stay in the orchestrator only.

The second agent (`superagent-colmex`, port 3083) holds its own three
sections, versioned in [`prompts/colmex/`](prompts/colmex/). The same
commands reach it with its port and directory:

```sh
DSH_SUPERAGENT_PORT=3083 SUPERAGENT_PROMPTS_DIR=docs/agent/prompts/colmex scripts/agent/prompts.sh diff
```

Its Delivery section names a different gate, the one `o_colmex`'s AGENTS.md
asks for: `mix format --check-formatted`, `mix lint` and the focused tests,
with the full `mix precommit` for a broad-risk change.

Existing profiles keep their CLI and active revision until their owner adopts the
guard and updates their prompts. Do not apply the prompt on its own.
See [existing profile setup](merge-checks.md#existing-profiles).

The board marks the task done as soon as the ticket ends `merged`, whatever
its last report said.

## 9. What not to do

- **Do not run two orchestrators** on the same state directory.
- **Do not point the bot at a repository it has no write access to**; the
  failure shows as a `failed` ticket with the HTTP error in the report.
- **Do not read `ready` as merged.** Without the merge policy above a `ready`
  ticket means "a human reviews this"; with it, the ticket ends `merged`
  within the same run or says why a person must merge.

### Names in the Harness Sessions list

Open **Settings → AI and setup → Harness session names**. The check compares the
managed home patch and installed files with this checkout; it makes no writes.
Use **Recheck installation** after running the command. An installed status is
evidence on the board host, not proof a running Harness profile has loaded it.
For a remote Harness host, run the command there and use `--check` there too.

Run `scripts/agent/install-worker-titles.py` on the Harness host (Node 22.19+
or 24+). It installs a host plugin and one marked entry in the home patch,
preserving the other entries. It also applies to future profiles. To uninstall,
remove the marked entry and reload the host. Do not restart a profile with an
assignment in progress.

The worker title uses the repository and the ticket title: `AR - Redesign do HUD`,
`COL - Ajustar menu` or `SB - Corrigir filtros`. Other project names use up to
three initials, or three letters for a single word. When a separate desktop host
lists a worker whose title has not reached its in-memory cache, the plugin reads
that ticket's title without opening its session. It never modifies the agent
database. It recognizes the standard `state/<profile>/work/<name>-<id-prefix>`
layout and leaves other sessions and custom session names alone.

Run the host-specific tests with the same Node runtime as DSH:

`node --test ops/harness-worker-titles/worker-titles.test.mjs`.

### Update the Harness for connected projects

Open the board on **localhost → Settings → Projects → Sync agent runtimes**.
The list above the button is the scope you are approving. Progress and the
last result appear beside each project; you can leave Settings while it runs.

The board uses the Harness dependency lock shipped with **this board version**.
It installs that runtime once per machine and checks each registered local
profile against its repository, state directory and manager. An outdated, idle
agent briefly pauses and reloads on the same profile and port. An up-to-date
agent keeps its process. Busy, paused, stopped and unverified agents are
skipped; click again after work finishes. GitHub-only projects need no action.
The board stays online, the global npm installation is unchanged, and no code
is written to the connected repositories. Manage agents on another machine
from that machine's board. A failed result means the handoff could not be
verified: check the project status and logs before retrying.
