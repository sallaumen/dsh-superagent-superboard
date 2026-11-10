#!/bin/sh
# Open an agent's dsh panel in the default browser, signed in.
#
#   panel.sh [profile]      # superagent (default), superagent-colmex, ...
#
# A browser that never opened the URL dsh printed at start gets "dsh web
# authentication required" from http://127.0.0.1:<port>/. That URL carries the
# process's launch token; opening it once leaves a cookie, and from then on
# the plain address (the link in Configurações → Projetos) opens directly.
# The URL is read from the newest log the manager wrote for the profile and
# handed to `open`. It is a credential: this script never prints it.
set -eu
# shellcheck disable=SC1091  # shared variables, the same in every script here
. "$(dirname "$0")/_common.sh"

PROFILE="${1:-$PROFILE}"
# [0-9]: "superagent" must not match the logs of "superagent-colmex".
# shellcheck disable=SC2012  # the manager names these files; no odd characters
LOG=$(ls -t "$DSH_SUPERAGENT_HOME/.artifacts/dsh-superagent-$PROFILE-"[0-9]*.log 2>/dev/null | head -1)
[ -n "$LOG" ] || {
  echo "no log for profile $PROFILE in $DSH_SUPERAGENT_HOME/.artifacts" >&2
  exit 1
}
URL=$(sed -n 's/^dsh web: //p' "$LOG" | tail -1)
[ -n "$URL" ] || {
  echo "$LOG has no 'dsh web:' line; start the agent with the manager (docs/agent/setup.md §4)" >&2
  exit 1
}
open "$URL"
