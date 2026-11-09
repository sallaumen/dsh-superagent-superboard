# ADR 0005 — The board releases tasks in order

- **Decision:** a task of a split that depends on others opens without calling
  the agent. When every dependency is finished, the board comments the mention
  once. Sending the split, with a sentence that says so, is the approval for
  the whole tree.
- **Status:** accepted on 2026-11-09 by the owner, who chose it from the path
  for task splitting ("pode continuar", after the recommendation of approving
  the tree once instead of one click per task).

## Why

The agent has no queue: each mention becomes a ticket at once. Real splits
started tasks before the tasks they depended on (o_colmex #1416 before #1415).
GitHub's blocked-by only draws an icon, so the order has to come from who
writes the mention.

## Limits

- Only the DeepSeek runner, which the board dispatches by mention. Claude Code
  and Codex keep their confirmed dispatch (ADR 0004).
- Finished means `done` or `closed`. An issue closed without a merge counts.
- One comment per task, claimed before the call. A comment that failed may have
  landed, so it is never repeated by itself: the owner sees it and decides.
- A failed or blocked dependency holds what waits for it; the owner can call the
  agent early, with a confirmation.
- `AGENT_BOARD_AUTO_RELEASE=0` keeps a second board from writing.
