# Run the board worker without GitHub credentials

Choose this mode for a local GitHub **issue** worker that should open PRs only
through the board's publisher. Docker runs edits and checks; the Harness still
polls GitHub on the host. The model has no host shell, mounted checkout, GitHub
login, Docker socket or external network. Other profiles keep their settings.
The isolated worker can report a PR for review; it cannot merge or respond to
review by pushing more code to an already published branch.

1. Configure a project and its **bot** following [agent setup](setup.md).
   Use **Settings → Projects → Synchronize** to install the publisher on the
   existing profile. Wait for its running and queued counts to reach zero.
2. Build the image from a reviewed board revision on the operator machine.
   Only a clean Git archive is sent to Docker. The build needs the network;
   ticket containers do not. The recipe targets Alpine on arm64 or x86-64
   and includes the board's locked Mix dependencies, Git, Postgres and Linux
   tools used by the test suite. Rebuild when the toolchain or lock changes.

   ```sh
   git archive HEAD | docker build -f ops/container-worker/Dockerfile -t superboard-board-checks -
   docker image inspect --format '{{.Id}}' superboard-board-checks
   ```

3. In the existing profile's **state directory** (from Harness setup), create
   `container-worker.json` as its OS owner with permissions `0600`. Substitute
   the actual image ID, account, repo and absolute host paths. The bot CLI must
   be a trusted wrapper that selects only the bot's GitHub configuration.
   `quality_dir` must point to the installed board's `priv/merge_gate`,
   **outside** the agent's ticket directory. `tool_dirs` must resolve Python's
   child commands to trusted Git, GitHub CLI and Docker binaries.

   ```json
   {
     "image": "sha256:<64 hex characters from docker image inspect>",
     "account": "your-bot",
     "repo": "your-org/your-board",
     "email": "your-bot@users.noreply.github.com",
     "bot_cli": "/absolute/path/to/gh-agent",
     "base_branch": "main",
     "tool_dirs": ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"],
     "quality_dir": "/absolute/path/to/installed-board/priv/merge_gate",
     "checks": [["/usr/local/bin/board-publication-check"]]
   }
   ```

4. Restart **only the idle Harness profile** using its own manager to rebind
   its tool permissions. Do not restart the board or another worker. Verify
   that a ticket receives `container_work` and `managed_publish`. For a
   different project provide an image and check runner for its toolchain.
   The example runner rejects unsupported selected checks.

The publisher snapshots the edits, applies them in a separate clean container,
and runs the selected checks there. Only then does it push the checked change
to the assigned branch and create a PR as the configured bot. It records the
result outside the worker. A repeat returns the same PR after checking its
author, branch and head. A failed check blocks the assignment. Request **Retry**
in the Harness after fixing the cause; a comment can resume the same assignment
and does not reset its stop. If creation is uncertain, inspect the remote PR
before taking further action. Merge remains a separate decision with its own
[requirements](merge-checks.md).

The containers are removed after publication or a terminal report. Keep the
pinned image for future tickets. After a machine crash, inspect containers by
their exact `superboard.assignment` label and remove only those of a confirmed
ended assignment. The profile's `container-publications` directory holds the
receipts; do not delete it to unblock an assignment.
