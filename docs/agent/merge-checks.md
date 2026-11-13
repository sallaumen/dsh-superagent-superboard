# Project merge checks

A board-managed worker requests delivery from the root of its clean ticket worktree:
`gh pr merge NUMBER --match-head-commit FULL_SHA`. The guard uses that worker's GitHub identity, verifies it authored the open, non-draft PR from this branch, and checks the PR's **base commit** for a repository policy. A PR cannot introduce its own permission to merge. Without a valid policy or readable evidence it stays open.

If the destination contains `.github/superboard-merge.json`, it is authoritative.
Otherwise the worker can use a file on its machine, without writing to the
project. Create `~/.config/superboard/quality/OWNER/REPO.json` using lowercase
GitHub names under the OS account shared by board and worker. For example, for
`acme/game`, create `~/.config/superboard/quality/acme/game.json` (create the
directories first). The directories from `~/.config` down and the file must
belong to that account, must not be symlinks or writable by group/others.
Settings → project merge requirements identifies the source and lists the checks.
There is no catch-all policy. A machine policy must name at least one local check.

For a Rust project with no hosted jobs, the file could contain:

```json
{"method":"squash","review":true,"local":{"Rust tests":["cargo","test","--locked"]},"github":[]}
```

Use commands appropriate to the project: for TypeScript that could be `["npm","run","check"]`; for PHP, `["composer","test"]`. Arguments are passed directly to executables, not interpreted as shell text. Use a project script for ordered checks or environment setup. Local entries are independent, run up to four at once and must leave the tracked checkout clean; combine dependent steps into one script. Each has a 30-minute limit. At least one local or hosted check is required. Hosted entries name the GitHub App slug and exact check-run name, e.g. `github-actions/unit`; missing, ambiguous, skipped and failed runs do not pass. Classic commit statuses aren't check runs. An absolute executable path can point to a quality script outside the managed repository. The board itself runs its complete local preflight followed by release packaging; its single hosted smoke check is supplemental.

An approval, when required, must cover the current commit and come from someone other than the author. Outstanding changes and GitHub branch requirements also stop delivery. After validation the guard verifies both revisions and the working tree again, then supplies the exact head SHA when merging. If GitHub is unavailable or a required hosted check has not succeeded, **no automatic fallback**. With no required hosted checks, a missing workflow is fine. An unstable PR still needs positive evidence that its optional checks failed to start, not a guess based on runtime; see the [CI-unavailable rule](../../PIPELINES.md#if-ci-cannot-run-no-token-billing-or-runner). For enforcement across humans, other clients and direct API calls, protect the base branch on GitHub. The worker CLI is not a substitute for branch protection.

Each attempt records a snapshot atomically under `~/.local/state/superboard/merge/OWNER/REPO/PR.json` (override with `SUPERBOARD_GATE_DIR` for both board and worker). Only policy origin, check labels, states, revisions and outcomes are stored, not command output or credentials. Overlapping attempts on the same PR are refused. A later attempt reruns checks.

## Choose task checks in the panel

In **Settings → Projects**, expand the project row. In **Project policy**, open **Local task checks**. Select
the commands your project supports and save. For example, a Node.js project
can run lint, unit tests, its build and its browser test script. Nothing is
installed and saving does not run a command. Clear the selection to remove
only these additional checks. Existing repository and machine policies remain
in force. If neither exists, a nonempty selection provides a local-only policy
with squash and independent review; with no selection the guard refuses delivery.

The selection is stored outside the checkout under
`~/.config/superboard/task-stages/owner/repo.json` for the board/worker OS user.
Only the fixed catalog in `priv/merge_gate/stages.json` can be selected. Local
tools and project scripts must already be available. A missing tool or script
fails that stage and stops the sequence. A concurrent settings change must be
refreshed before saving.

A managed worker runs the selected stages in order before `gh pr create`, then
verifies them again on the exact head at guarded merge. Codex/Claude local
dispatch also checks before reporting successful completion, even without a PR.
Existing DeepSeek profiles need an active merge guard (see below); an inactive
worker does not produce evidence. The running card names the current command,
and the task inspector keeps each outcome for that worktree and attempt. No
GitHub Actions run is involved. Changing a selection during merge verification
blocks delivery; an older receipt never authorizes a new commit.

## The executor's self-review

Before requesting delivery, the executor reviews its own diff and leaves one
comment on the PR, labelled as the author's self-review. That is not independent
approval: it does not satisfy a policy's `review: true`, and the executor never
submits a formal GitHub approval of its own work. When review is required, a
different person approves the current commit.

The comment records the full head SHA it covers, the scope reviewed, the exact
commands and their real results, and what was not validated. Refresh it when the
head changes; a comment for an older SHA is not evidence for the current one.
Use placeholders only in this template — fill the comment with real values from
that head, never with a result copied from another commit, PR or ticket.

```markdown
This is by an automated agent, not a human.

## Author's self-review

This is the author's self-review, not independent approval.

- Head: `<full 40-character SHA>`
- Scope: `<files/areas read in the diff and the acceptance criteria checked>`
- Commands and actual results:
  - `<exact command>` — `<actual result on this head>`
- Not validated: `<check skipped and why, or the limitation>`
```

## Existing profiles

Newly provisioned agents and new Codex/Claude runs receive the guard automatically after updating the board. Existing DeepSeek profiles are **not** silently reconfigured. With the agent idle, use the installed board checkout and the profile's existing CLI:
```sh
python3 priv/merge_gate/guard.py install "$HOME/.dsh/profiles/PROFILE/merge-bin" OWNER/REPO /absolute/path/to/gh-agent
```
Set that printed absolute path as the profile's GitHub source CLI, verify its bot identity, then apply the updated Delivery instructions in the board. Keep the sign-in wrapper. Repeat per profile; rollback restores its previous CLI and prompt revision. A repository adopting this policy for the first time needs a human to merge the policy itself.
