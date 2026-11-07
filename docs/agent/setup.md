# Setting the agent up on another machine

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

## 4. Start it

```sh
tmux new -s dsh-superagent
dsh --profile superagent
```

The profile opens its own tmux window (`dsh-superagent`). Leave it running:
it is the orchestrator.

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
- Treat a `ready` report as evidence only for what it names. A report that
  names no practice file read means the kit was not loaded; a model name
  establishes nothing. The kit's
  [compatibility note](https://github.com/sallaumen/elixir-agent-kit/blob/v0.5.3/docs/compatibility.md)
  describes the fresh-session check.

## 8. Merge policy

The host has no merge logic. Whether the agent merges is prompt text: the
**Delivery requirements** team section, read and saved through the panel or
the API (`GET`/`PUT http://127.0.0.1:3082/orchestrator/api/prompts`, header
`x-orchestrator-request: 1`, with the current revision as `baseRevision`).
The built-in text lets a person merge every PR.

This deployment delegates merging to the agent. The section says that nobody
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
