# Working in this repo alongside another agent

More than one agent works on this repository at the same time. Both write to
`main`, and both have tools that are convenient in a single-agent session and
dangerous with two.

## The two rules that prevent almost every accident

**1. Never `git add -A` or `git add .` in this repository.**

`git add -A` stages whatever is in the working tree, including another
agent's in-progress files. It happened twice here: a UI agent's audit
screenshots were swept into an unrelated PR.

```sh
git add lib/agent_board/ai.ex test/agent_board/ai_test.exs   # the files you touched
git status --short                                            # what is still loose
```

**2. Fetch and pull before you branch, and again before you merge.**

```sh
git fetch origin
git pull --rebase origin main
git checkout -b feat/your-thing
```

## The loop

```sh
git fetch origin && git pull --rebase origin main
git checkout -b feat/<thing>
# ... work ...
mix gate                                  # read the WHOLE output, not a grep
git add <the files you touched>
git commit -m "<what changed>"
git push -u origin feat/<thing>
gh pr create --base main --head feat/<thing> --title "..." --body "..."
gh pr merge <branch> --merge --delete-branch
git checkout main && git pull
```

## Boundaries, by area

| Area | Owner | Do not |
|---|---|---|
| `lib/agent_board/**` | the domain agent | restyle or rename events here for looks |
| `test/**` | whoever changes the behaviour | delete a test to make a gate pass |
| `lib/agent_board_web/components/**` | the UI agent | put domain logic in a component |
| `docs/**` | whoever documents a rule | write a claim without running it |

## When the gate is red and the code is not yours

```sh
git fetch origin && git log --oneline -5 origin/main
```

If the failure came with the other agent's merge, say so on the PR and fix it
in a separate `fix/` branch -- do not fold an unrelated repair into your
feature.

## The board itself

The board reads GitHub; it never writes to the agent's sqlite. A restart is
`launchctl kickstart -k "gui/$(id -u)/com.agentboard"` and costs nothing but a
reconnect.
