# A merged PR's rows show what its task cost

Captured on an isolated server (a copy of the development database and a read-only copy of the runner's tickets), `sallaumen/arena-rogue`, 1920 px, English.

Measured on that copy: at 1920 px, 18 of 21 visible merge-log rows carry a cost; at 3440 px, 43 of 51; in History, 48 of the 50 loaded PRs. No horizontal overflow at either width. The rows without one have no task, or no execution attributed to it: they print nothing, never a zero.

The value is the task's (`Usage.TaskCosts`), so a task delivered by several PRs shows its whole cost on each, as the tooltip says. A PR that closes several issues shows the first the board tracks, the task its row opens.

The row grows by one line at 1920 px, where the cost does not fit beside the time.
