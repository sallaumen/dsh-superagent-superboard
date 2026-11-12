# Setting the agent up on another machine

Starting from zero — installing DeepSeek Harness, learning Creator Mode,
putting the first Super-Agent on a repository — is the
[learning path](learning-path.md); this document is the precise, machine-by-machine
reference once the pieces exist.

The agent needs four things: Node + DeepSeek Harness, a profile, a GitHub
identity for the bot, and a repository it is allowed to touch.

## 1. Prerequisites

```sh
node --version          # 22+
dsh --version           # DeepSeek Harness
gh --version
git --version
```

## 2. The bot identity

The agent acts as its own GitHub account, never as you:

```sh
mkdir -p ~/.config/gh-agent
GH_CONFIG_DIR=~/.config/gh-agent gh auth login      # log in as the bot
```

`~/.local/bin/gh-agent` is a one-line wrapper:

```sh
#!/bin/sh
GH_CONFIG_DIR="$HOME/.config/gh-agent" exec gh "$@"
```

Verify:

```sh
gh-agent auth status          # the bot's login
gh-agent api user --jq .login # must print the bot, not you
```

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
  [compatibility note](https://github.com/sallaumen/elixir-agent-kit/blob/v0.8.0/docs/compatibility.md)
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

The host has no merge logic. Whether the agent merges is prompt text: the
**Delivery requirements** team section. The three team sections --
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

The built-in text lets a person merge every PR. This deployment delegates
merging to the agent: [`prompts/delivery.md`](prompts/delivery.md) says that nobody
reviews PRs by hand and that the executor merges each PR it opened, as the
bot, once all of these hold: the work is complete; `mix precommit` passed on
the head commit and the PR and the report say so; no human review asks for
changes; `gh pr view --json mergeable` answers `MERGEABLE`. GitHub Actions
is never a reason to wait (it cannot run here: billing). It merges with
`gh pr merge <n> --merge --match-head-commit <sha>` before it reports, puts
`Closes #<issue>` in the PR so the merge closes the issue, and reports the PR
as merged, never as ready for review. It never merges a PR someone else
opened.

For that the bot needs write permission on the repository and the base
branch needs no rule that requires a review. Sessions read the newest
revision on their next model request; no restart. The panel's history
restores an earlier revision.

The board marks the task done as soon as the ticket ends `merged`, whatever
its last report said.

## 9. What not to do

- **Do not run two orchestrators** on the same state directory.
- **Do not point the bot at a repository it has no write access to**; the
  failure shows as a `failed` ticket with the HTTP error in the report.
- **Do not read `ready` as merged.** Without the merge policy above a `ready`
  ticket means "a human reviews this"; with it, the ticket ends `merged`
  within the same run or says why a person must merge.
