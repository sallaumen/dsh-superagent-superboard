# How the agent works

The agent is **not** in this repository. It is a separate process
(`dsh-superagent`, TypeScript, running inside DeepSeek Harness) that watches
GitHub. This board only **mirrors** what it did -- stop the board and the
agent keeps working.

## The loop

```
GitHub comment mentioning @sallaumen-agent
        │
        ▼
  1. TRIGGER     the event, with its author and text
        │
        ▼
  2. THREAD      github:<issue number> -- the conversation it belongs to
        │
        ▼
  3. DECISION    is this work? for whom? with what strength of mandate?
        │
        ▼
  4. TICKET      the unit of work: mandate + channels + assignments
        │
        ▼
  5. EXECUTOR    a worker on deepseek-flash, in an isolated worktree:
                 branch -> implement -> gates -> open PR -> write a report
        │
        ▼
  6. OUTBOX      the reply posted back on the issue
```

## The pieces, and where each lives

| Piece | What it is | Where |
|---|---|---|
| Orchestrator | the state machine above | `~/.dsh/state/superagent/orchestrator.sqlite` |
| Profile | the model and the plugin config | `~/.dsh/profiles/superagent/cordis.patch.yml` |
| Web/API | the management surface | `127.0.0.1:3082` (needs `x-orchestrator-request: 1`) |
| Worker bin | the tools the executor may call | `~/.dsh/state/superagent/worker-bin/` |
| Bot identity | the `gh` the worker uses | `~/.local/bin/gh-agent` (config `~/.config/gh-agent`) |
| Worktrees | one checkout per assignment | `~/.dsh/state/superagent/work/` |

## The tables

`trigger`, `thread`, `decision`, `ticket`, `outbox`, `effect`, plus `kv`,
`disposition`, `trigger_thread`. There is no `task` table: a **ticket** is the
unit of work, and its `assignments[]` carry the executor runs.

A ticket carries a **mandate** -- the reason it exists:

```json
"mandate": {
  "strength": "explicit",
  "basis": {"source": "github", "row": "issues", "sender": "sallaumen",
            "via": "addressed", "addressed": "mention"},
  "scope": "Combat feedback and game states"
}
```

`via: addressed` + `addressed: mention` means: **the human named the bot**.
Nothing runs without that. There is no queue of "pending tasks" the agent
polls; the human sentence is the trigger.

## The four outcomes a ticket can report

| State | Meaning |
|---|---|
| `ready` | a PR is open and waiting for a human |
| `progress` | the executor is still working |
| `waiting` | the executor needs input |
| `failed` | the run ended without a PR |

The report always carries a `summary` and an `at`. A `ready` report names the
PR, its head sha, the gates that ran, and the limitations -- it is evidence,
not a claim.

## What the board adds

- **Visibility**: the five columns, the conversation, the AI panel.
- **Intake**: a rough request refined into tasks before it becomes an issue
  (see [`../ai-layer.md`](../ai-layer.md)).
- **Version**: whether this checkout is behind `main`, and a manual update.

None of that is on the agent's critical path.
