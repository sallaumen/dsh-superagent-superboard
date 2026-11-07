# AGENTS.md — agent-board

The board for the agent's work, in Elixir. Read this before changing code.

## Required contracts

- Before opening any source file for a change or a review, select one Elixir
  Agent Kit workflow through [.elixir-agent-kit/START.md](.elixir-agent-kit/START.md)
  (after `mix deps.get`) and name it, or NONE for a bounded, fully specified
  edit. Investigate the way the workflow says.
- Then read and follow the relevant sections of the
  [maintainer contract](docs/maintainer-contract.md): data ownership, real-time
  updates, AI calls, network failures and sync isolation are binding. The
  contract says what this board must do; the workflow says how to inspect,
  decide and prove it.
- Follow [CONTRIBUTING.md](CONTRIBUTING.md) for branches, commits and PRs.
- Follow [PIPELINES.md](PIPELINES.md) for required checks and command effects.
  Its [CI-unavailable procedure](PIPELINES.md#se-a-ci-não-consegue-rodar-sem-token-billing-ou-runner)
  is binding when GitHub Actions cannot run.
- Use the [local configuration instructions](README.md#local-secrets) when
  running the app or a worktree; never commit local secrets.
- Interface motion follows [docs/ui-motion.md](docs/ui-motion.md) and the kit's
  `motion-design` workflow: motion explains a state change, never gates an
  action and never replays on a broadcast.

## Working alongside another agent

Two agents write to `main` here. **Never `git add -A`** -- it sweeps the other
agent's files into your PR. Add the files you touched, by name. Fetch before
you branch and before you merge. The full protocol is
[`docs/agent/collaboration.md`](docs/agent/collaboration.md).

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

## Shared practices

- The kit's entry is the managed block below; workflow bodies live in the
  dependency, never in copied project files.
- Reusable improvements belong upstream in the kit; application-specific rules
  stay in this repository. Follow [practice ownership](docs/agent/practices.md).
- Do not recreate `capabilities/skills` or manually edit generated kit files.

<!-- elixir-agent-kit:start -->
## Elixir Agent Kit

Before opening any source file for a change or a review, select one workflow from
[.elixir-agent-kit/START.md](.elixir-agent-kit/START.md) and name it, or NONE for a bounded,
fully specified edit; then read the workflow with its shared contract alongside this project's
own contracts, and investigate the way the workflow says. This project's rules keep precedence.
If the files are missing, run `mix deps.get`; if you cannot read them, report that instead of
claiming the practices were applied.
<!-- elixir-agent-kit:end -->
