# AGENTS.md — agent-board

The board for the agent's work, in Elixir. Read this before changing code.

## Required contracts

- Before changing application behavior, read and follow the relevant sections
  of the [maintainer contract](docs/maintainer-contract.md): data ownership,
  real-time updates, AI calls, network failures and sync isolation are binding.
- Follow [CONTRIBUTING.md](CONTRIBUTING.md) for branches, commits and PRs.
- Follow [PIPELINES.md](PIPELINES.md) for required checks and command effects.
  Its [CI-unavailable procedure](PIPELINES.md#se-a-ci-não-consegue-rodar-sem-token-billing-ou-runner)
  is binding when GitHub Actions cannot run.
- Use the [local configuration instructions](README.md#local-secrets) when
  running the app or a worktree; never commit local secrets.

## The agent

The agent is a separate process (DeepSeek Harness + `dsh-superagent`) that
watches GitHub; this board only mirrors it. It is documented in
[`docs/agent/how-it-works.md`](docs/agent/how-it-works.md), set up per
[`docs/agent/setup.md`](docs/agent/setup.md), and driven from
`scripts/agent/`:

| Script | Answers |
|---|---|
| `status.sh` | is it configured, alive and idle? |
| `tickets.sh [n]` | what did the last tickets report? |
| `counts.sh` | how much has it done, by table? |
| `logs.sh` | what is it printing right now? |

## Capabilities library

- Start at [capabilities/CATALOGO.md](capabilities/CATALOGO.md); load only the
  selected skill and its common contract.
- Follow [capabilities/README.md](capabilities/README.md) when maintaining the
  library and [capabilities/tools/README.md](capabilities/tools/README.md) for
  validation. Context selection is governed by
  [capabilities/contextos/README.md](capabilities/contextos/README.md).
