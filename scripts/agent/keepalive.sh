#!/bin/sh
# Bring the agent back when it is down and nobody stopped it on purpose.
# Run by launchd (ops/com.dsh.superagent.plist) at login and every five
# minutes; safe to run by hand.
#
#   keepalive.sh
#
# It asks the prototype's own manager, never tmux or dsh directly:
#   scripts/dsh-superagent status            -> 0: running, nothing to do
#   scripts/dsh-superagent start --respect-stop
# `start` is idempotent (it finds a dsh started by hand in tmux and starts no
# second one) and `--respect-stop` skips it after `scripts/dsh-superagent
# stop`, which leaves the `manually-stopped` marker. A status of 2 or 3 (a
# component error, setup pending) needs a person: logged, never restarted.
#
# Quiet while the agent runs: one log line per action, in
# $DSH_SUPERAGENT_KEEPALIVE_LOG (default ~/Library/Logs/dsh-superagent-keepalive.log),
# moved to <log>.1 above 1 MB. Exit 0 when the agent runs or was stopped on
# purpose, the manager's exit code otherwise.
set -u
# shellcheck disable=SC1091  # shared variables, the same in every script here
. "$(dirname "$0")/_common.sh"

MANAGER="$DSH_SUPERAGENT_HOME/scripts/dsh-superagent"
PROFILE="${DSH_SUPERAGENT_PROFILE:-superagent}"
case "$PROFILE" in
  ""|[!a-zA-Z0-9_]*|*[!a-zA-Z0-9_.-]*) ;;
  *)
    runtime_bin="$HOME/.local/share/superboard/runtimes/profiles/$PROFILE"
    if [ -x "$runtime_bin/dsh" ]; then
      PATH="$runtime_bin:$PATH"; export PATH
    fi ;;
esac
LOG="${DSH_SUPERAGENT_KEEPALIVE_LOG:-$HOME/Library/Logs/dsh-superagent-keepalive.log}"
LOG_MAX_BYTES="${DSH_SUPERAGENT_KEEPALIVE_LOG_MAX_BYTES:-1048576}"

log() { printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >>"$LOG"; }

mkdir -p "$(dirname "$LOG")"
if [ -f "$LOG" ] && [ "$(wc -c <"$LOG")" -gt "$LOG_MAX_BYTES" ]; then
  mv -f "$LOG" "$LOG.1"
fi

if [ ! -f "$MANAGER" ]; then
  log "no manager at $MANAGER; set DSH_SUPERAGENT_HOME"
  exit 1
fi

STATUS=$(python3 "$MANAGER" --profile "$PROFILE" status 2>&1)
CODE=$?
[ "$CODE" -eq 0 ] && exit 0

# Stopped on purpose, or a stop/start by hand holds the manager's lock.
if printf '%s' "$STATUS" | grep -q -e '"manually_stopped": true' -e 'control operation is in progress'; then
  exit 0
fi

case "$CODE" in
  2 | 3)
    log "status $CODE: the agent runs but needs a person; not restarting"
    printf '%s\n' "$STATUS" | sed 's/^/  /' >>"$LOG"
    exit "$CODE"
    ;;
esac

log "status $CODE: starting"
OUT=$(python3 "$MANAGER" --profile "$PROFILE" start --respect-stop 2>&1)
CODE=$?
printf '%s\n' "$OUT" | grep -v '^[[:space:]]*$' | sed 's/^/  /' >>"$LOG"
log "start exited $CODE"
exit "$CODE"
