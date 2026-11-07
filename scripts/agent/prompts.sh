#!/bin/sh
# The three team prompt sections -- Communication, Ticket scope and Delivery
# requirements -- are the agent's policy. The orchestrator holds the active
# text; git holds docs/agent/prompts/{communication,scope,delivery}.md plus
# `revision`, the revision those files were read from. This script moves the
# text between the two:
#
#   prompts.sh get    write the active sections and their revision to the files
#   prompts.sh diff   compare the files with the active revision; exit 1 if they differ
#   prompts.sh put    save the files as a new revision on top of the one in `revision`
#
# `put` refuses when the panel saved a newer revision than `revision`, so an
# edit made in the panel is never overwritten unseen: run `get`, review the
# change, commit it, then `put` again. Team skills and built-in overrides stay
# in the orchestrator; `put` sends them back unchanged. Needs curl and jq.
set -eu
# shellcheck disable=SC1091
. "$(dirname "$0")/_common.sh"

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DIR="$ROOT/docs/agent/prompts"
SECTIONS="communication scope delivery"
HEADER="x-orchestrator-request: 1"

fetch() {
  if ! PROMPTS=$(curl -sf -H "$HEADER" "$API/prompts") || [ -z "$PROMPTS" ]; then
    echo "AGENT DOWN: no answer at $API"
    echo "  start it:  scripts/agent/keepalive.sh   (stopped on purpose? python3 $DSH_SUPERAGENT_HOME/scripts/dsh-superagent start)"
    exit 1
  fi
  ACTIVE=$(printf '%s' "$PROMPTS" | jq -r '.current.revision')
}

# A file is the section's text plus one newline, so a diff reads as prose.
# `config` below strips that newline again when it reads the files back.
get() {
  fetch
  mkdir -p "$DIR"
  for S in $SECTIONS; do
    printf '%s' "$PROMPTS" | jq -r ".current.config.$S" > "$DIR/$S.md"
  done
  echo "$ACTIVE" > "$DIR/revision"
  echo "revision $ACTIVE -> docs/agent/prompts/"
}

# Prints each difference between the files and the active revision; returns 1
# when there is any. Lines marked + are what `put` would send.
compare() {
  CHANGED=0
  for S in $SECTIONS; do
    if [ ! -f "$DIR/$S.md" ]; then
      echo "$S.md: missing (run get)"
      CHANGED=1
    elif ! printf '%s' "$PROMPTS" | jq -r ".current.config.$S" |
      diff -u -L "orchestrator:$S (revision $ACTIVE)" -L "git:$S.md" - "$DIR/$S.md"; then
      CHANGED=1
    fi
  done
  REV=$(cat "$DIR/revision" 2>/dev/null || echo none)
  if [ "$REV" != "$ACTIVE" ]; then
    echo "revision: git $REV, active $ACTIVE"
    CHANGED=1
  fi
  return "$CHANGED"
}

diff_cmd() {
  fetch
  if compare; then
    echo "the files match revision $ACTIVE"
  else
    exit 1
  fi
}

# The active config with the three sections replaced by the files: skills and
# overrides travel unchanged, and the API refuses unknown keys anyway.
config() {
  printf '%s' "$PROMPTS" | jq \
    --rawfile communication "$DIR/communication.md" \
    --rawfile scope "$DIR/scope.md" \
    --rawfile delivery "$DIR/delivery.md" \
    '{config: (.current.config
               | .communication = ($communication | sub("\n$"; ""))
               | .scope = ($scope | sub("\n$"; ""))
               | .delivery = ($delivery | sub("\n$"; ""))),
      baseRevision: .current.revision}'
}

put() {
  fetch
  REV=$(cat "$DIR/revision" 2>/dev/null || echo none)
  if [ "$REV" != "$ACTIVE" ]; then
    echo "REFUSED: the files come from revision $REV; the active one is $ACTIVE"
    echo "  the panel saved since: run get, review the change, commit it, then put again"
    exit 1
  fi
  if compare > /dev/null; then
    echo "nothing to save: the files match revision $ACTIVE"
    exit 0
  fi
  BODY=$(mktemp)
  OUT=$(mktemp)
  trap 'rm -f "$BODY" "$OUT"' EXIT
  config > "$BODY"
  CODE=$(curl -s -o "$OUT" -w '%{http_code}' -X PUT -H "$HEADER" \
    -H 'content-type: application/json' --data-binary @"$BODY" "$API/prompts")
  if [ "$CODE" != 200 ]; then
    echo "REFUSED ($CODE): $(jq -r '.error // .' "$OUT" 2>/dev/null || cat "$OUT")"
    exit 1
  fi
  NEW=$(jq -r '.revision' "$OUT")
  echo "$NEW" > "$DIR/revision"
  echo "saved revision $NEW (was $ACTIVE); commit docs/agent/prompts/revision"
}

case "${1:-}" in
  get) get ;;
  diff) diff_cmd ;;
  put) put ;;
  *) echo "usage: $0 get|diff|put"; exit 2 ;;
esac
