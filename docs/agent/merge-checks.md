# Project merge checks

A board-managed worker requests delivery from the root of its clean ticket worktree:
`gh pr merge NUMBER --match-head-commit FULL_SHA`. The guard uses that worker's GitHub identity, verifies it authored the open, non-draft PR from this branch, and reads the policy from the PR's **base commit**. A PR cannot introduce its own permission to merge. Without a valid policy or readable evidence it stays open.

The project chooses the method and checks in `.github/superboard-merge.json`. For example, a Rust project with no hosted jobs can use:

```json
{"method":"squash","review":true,"local":{"Rust tests":["cargo","test","--locked"]},"github":[]}
```

Use commands appropriate to the project: for TypeScript that could be `["npm","run","check"]`; for PHP, `["composer","test"]`. Arguments are passed directly to executables, not interpreted as shell text. Use a project script for ordered checks or environment setup. Local entries are independent, run up to four at once and must leave the tracked checkout clean; combine dependent steps into one script. Each has a 30-minute limit. At least one local or hosted check is required. Hosted entries name the GitHub App slug and exact check-run name, e.g. `github-actions/unit`; missing, ambiguous, skipped and failed runs do not pass. Classic commit statuses aren't check runs. The board's own policy names its complete preflight and all eight Actions jobs.

An approval, when required, must cover the current commit and come from someone other than the author. Outstanding changes and GitHub branch requirements also stop delivery. After validation the guard verifies both revisions and the working tree again, then supplies the exact head SHA when merging. If GitHub is unavailable or a required hosted check has not succeeded, **no automatic fallback**: use the repository's documented manual delivery procedure. For enforcement across humans, other clients and direct API calls, protect the base branch on GitHub. The worker CLI is not a substitute for branch protection.

Each attempt records a snapshot atomically under `~/.local/state/superboard/merge/OWNER/REPO/PR.json` (override with `SUPERBOARD_GATE_DIR` for both board and worker). Only check labels, states, revisions and outcomes are stored, not command output or credentials. Overlapping attempts on the same PR are refused. A later attempt reruns checks.

## Existing profiles

Newly provisioned agents and new Codex/Claude runs receive the guard automatically after updating the board. Existing DeepSeek profiles are **not** silently reconfigured. With the agent idle, use the installed board checkout and the profile's existing CLI:
```sh
python3 priv/merge_gate/guard.py install "$HOME/.dsh/profiles/PROFILE/merge-bin" OWNER/REPO /absolute/path/to/gh-agent
```
Set that printed absolute path as the profile's GitHub source CLI, verify its bot identity, then apply the updated Delivery instructions in the board. Keep the sign-in wrapper. Repeat per profile; rollback restores its previous CLI and prompt revision. A repository adopting this policy for the first time needs a human to merge the policy itself.
