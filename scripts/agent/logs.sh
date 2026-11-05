#!/bin/sh
# What the orchestrator is printing right now.
set -eu
SESSION="${1:-dsh-superagent}"
tmux capture-pane -pt "$SESSION" 2>/dev/null | tail -40 ||
  echo "no tmux session named $SESSION"
