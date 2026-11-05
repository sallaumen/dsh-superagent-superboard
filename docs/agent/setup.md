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

## 7. What not to do

- **Do not run two orchestrators** on the same state directory.
- **Do not point the bot at a repository it has no write access to**; the
  failure shows as a `failed` ticket with the HTTP error in the report.
- **Do not assume it merges.** A `ready` ticket means "a human reviews this".
