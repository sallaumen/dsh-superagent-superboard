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
needs a person and is logged, never restarted. Render the template to resolve paths on this machine. Set `DSH_SUPERAGENT_HOME` if the manager is not at `~/.dsh/dsh-superagent`.

Install it (once):

```sh
mkdir -p ~/Library/LaunchAgents
python3 scripts/render-launchagent.py agent > ~/Library/LaunchAgents/com.dsh.superagent.plist
plutil -lint ~/Library/LaunchAgents/com.dsh.superagent.plist
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
scripts/agent/panel.sh superagent-portal   # a second one, by profile
```

The script hands the URL to `open` and never prints it: the token is a
credential, so do not paste it into an issue, a chat or a commit. Each row in
Configurações → Projetos links to its agent's plain address, and the number
of agents is changed there or on the board's flow tile, without the panel.

### A second repository (optional)

Add the repository in **Settings → Projects**. Choose **Connect Super Agent** only for the projects it should watch. The board provisions a separate profile and port for each one; it does not need another LaunchAgent.


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
@YOUR-BOT-LOGIN implement X
```

Then:

```sh
scripts/agent/tickets.sh     # the ticket appears within seconds
```

The ticket goes `progress` -> `ready` and the PR appears in the issue thread.

### Duplicate GitHub issues

When the Super Agent identifies a new issue as the same request as an already accepted issue, it can leave one comment on the duplicate with the original issue link and the reason. The duplicate stays open; the agent neither assigns another worker nor adds the duplicate to the original worker's conversation. Related requests with different deliverables remain separate. Decisions to ignore ordinary discussion stay silent.

This is an extension of the upstream Super Agent, installed by the board when it builds a **new** prototype checkout. If a first build fails, inspect and move the partial `dsh-superagent.installing` directory aside before retrying. For an existing local installation, use **Settings → Projects → Sync agent runtimes**. This builds the tested extension separately, preserves tracked local source fixes, and switches only the linked profile once it is idle. An incompatible revision, custom build configuration or unsupported package link is left unchanged; inspect it before retrying.

## 7. Follow the target project's instructions

Each worker gets a fresh worktree. Read the target repository’s contributor instructions, tool versions and required checks there. Use its documented bootstrap and CI commands, and record what actually ran on the PR’s head. No Elixir, Node or other target stack is assumed. The board’s own runtime requirements are separate from the software it tracks.

For example, a repository that pins the [Elixir Agent Kit](https://github.com/sallaumen/elixir-agent-kit) may require `mix deps.get` before opening its practice index. A different repository may use entirely different tooling or have no skill pack. Optional skills belong in the target project or local executor configuration; no one needs to install a global skill for every profile.

## 8. Merge policy

The managed worker CLI enforces the [target project's merge checks](merge-checks.md). The board ships shared [communication](prompts/communication.md), [scope](prompts/scope.md) and [delivery](prompts/delivery.md) instructions for all projects. Review their differences and apply them in **Settings → Projects**. Additional project rules belong to the local profile; the shared files are not an export of any one person's agent.

To inspect the active policy, run `scripts/agent/prompts.sh get`. The export goes to that profile's state folder (`board-prompts/`). `diff` compares that local copy; `put` saves a deliberate edit only if the base revision still matches. To use another location, set `SUPERAGENT_PROMPTS_DIR` to a local directory outside the checkout. For another profile, set the profile and its port. Propose changes to the shared defaults separately in a PR.

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

Open the board on **localhost → Settings → Projects → Agent maintenance → Sync agent runtimes**.
The list above the button is the scope you are approving. Progress and the
last result appear beside each project. The date and time are when the status last
changed, in your local time. You can close and reopen Settings without losing the result;
older results recorded before timestamps were available show only the status.

First install and synchronization use the same [list of extension fixes](../../priv/agent/extension-files.json).
The board uses the Harness dependency lock shipped with **this board version**.
It installs that runtime once per machine and checks each registered local
profile against its repository, state directory and manager. An outdated, idle
agent briefly pauses and reloads on the same profile and port. An up-to-date
agent keeps its process. Busy agents show **Update pending**. The board checks again every 15 seconds;
once both running and queued work reach zero, it applies the requested version
or reports that the Harness is already current. The request survives closing
Settings or restarting the board. Paused, stopped and unverified profiles are
not restarted. A changed repository, profile, extension or dependency lock needs a new click. GitHub-only projects need no action.
The board stays online, the global npm installation is unchanged, and no code
is written to the connected repositories. Manage agents on another machine
from that machine's board. A failed result means the handoff could not be
verified: check the project status and logs before retrying.

The delivery rules that profile then follows — the branch the next run prepares
and whether it reuses an open PR — are in
[What a ticket leaves behind](how-it-works.md#what-a-ticket-leaves-behind).
Synchronizing a profile only installs that behavior; it never creates a PR in
the connected repository. If the managed publication command stops, the worker
reports the block on the ticket; the recovery steps are in
[When a managed PR cannot be published](merge-checks.md#when-a-managed-pr-cannot-be-published).
