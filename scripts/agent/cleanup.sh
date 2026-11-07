#!/bin/sh
# Remove the worktrees of ended tickets and close the PRs they left open.
# Nothing in dsh-superagent deletes old records: a ticket that ended keeps its
# worktree under <state>/work/ and, when it ended without a merge, its PR.
#
#   cleanup.sh [--dry-run] [--apply] [--force] [--repo DIR]
#
# --dry-run  (default) print one line per action and change nothing
# --apply    do it: git worktree remove + prune, gh pr close as the agent
# --force    also remove worktrees that still hold uncommitted changes
# --repo DIR the main checkout the prepare command adds worktrees from; by
#            default read from each worktree's own .git file
#
# Never touches an open ticket, a PR someone else opened, a merged PR, or a
# PR of a ticket that ended completed/merged. Exit 0 when nothing was left to
# do or everything was done, 1 on a failed action or a bad invocation.
set -eu
# shellcheck disable=SC1091  # three variables and one function, shared by every script here
. "$(dirname "$0")/_common.sh"

WORK_DIR="${SUPERAGENT_WORK_DIR:-$STATE_DIR/work}"
GH_AGENT_CONFIG="${SUPERAGENT_GH_CONFIG_DIR:-$HOME/.config/gh-agent}"
MODE=dry-run
FORCE=0
REPO=""

usage() { sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) MODE=dry-run ;;
    --apply) MODE=apply ;;
    --force) FORCE=1 ;;
    --repo)
      [ $# -ge 2 ] || { echo "--repo needs a directory" >&2; exit 1; }
      REPO="$2"
      shift
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

for tool in sqlite3 git gh; do
  command -v "$tool" >/dev/null 2>&1 || { echo "$tool not in PATH" >&2; exit 1; }
done
[ -f "$DB" ] || { echo "no database at $DB" >&2; exit 1; }
if [ -n "$REPO" ] && ! git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  echo "--repo $REPO is not a git checkout" >&2
  exit 1
fi

agent_gh() { GH_CONFIG_DIR="$GH_AGENT_CONFIG" gh "$@"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Field separators: 0x1F for sqlite rows (a tab in IFS would swallow an empty
# field), a tab for gh's @tsv rows, whose fields are never empty.
SEP=$(printf '\037')
TAB=$(printf '\t')

# One row per ended ticket: name, directory, outcome, issue url, id, last report.
# The last Assignment is the one that counts; [0] is the first run only.
sqlite3 -list -separator "$SEP" "$DB" "
SELECT coalesce(json_extract(value,'\$.execution.name'),''),
       coalesce(json_extract(value,'\$.execution.directory'),''),
       json_extract(value,'\$.ended.outcome'),
       coalesce(json_extract(value,'\$.channels[0].address.url'),''),
       id,
       coalesce(json_extract(value,'\$.assignments[#-1].report.state'),'-')
FROM ticket WHERE json_extract(value,'\$.ended') IS NOT NULL ORDER BY rowid;" > "$TMP/ended"

# Directories of open tickets: never removed, whatever else says so.
sqlite3 "$DB" "SELECT json_extract(value,'\$.execution.directory') FROM ticket
               WHERE json_extract(value,'\$.ended') IS NULL;" > "$TMP/open"

is_open_dir() { grep -qxF -- "$1" "$TMP/open"; }

# Directories that match no ticket (an earlier database, another repository)
# are not this script's to remove; say so once, on stderr.
sqlite3 "$DB" "SELECT json_extract(value,'\$.execution.directory') FROM ticket;" > "$TMP/known"
STRAY=""
for d in "$WORK_DIR"/*/; do
  d=${d%/}
  [ -d "$d" ] || continue
  grep -qxF -- "$d" "$TMP/known" || STRAY="$STRAY ${d##*/}"
done
[ -z "$STRAY" ] || echo "note: left alone, no ticket in $DB:$STRAY" >&2

ENDED=$(wc -l < "$TMP/ended" | tr -d ' ')
OPEN=$(wc -l < "$TMP/open" | tr -d ' ')
WORKTREES=0
PRS=0
SKIPPED=0
FAILED=0
: > "$TMP/mains"

say() { printf '%s\n' "$*"; }

# --- worktrees -------------------------------------------------------------

while IFS="$SEP" read -r name dir outcome _url _id _state; do
  [ -n "$dir" ] || continue
  [ -d "$dir" ] || continue
  if is_open_dir "$dir"; then
    say "skip      $name  $outcome  directory belongs to an open ticket"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi
  case "$dir" in
    "$WORK_DIR"/*) ;;
    *)
      say "skip      $name  $outcome  $dir is outside $WORK_DIR"
      SKIPPED=$((SKIPPED + 1))
      continue
      ;;
  esac

  common=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
  main=""
  if [ -n "$REPO" ]; then
    main="$REPO"
    if [ -n "$common" ] && [ "$common" != "$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir)" ]; then
      say "skip      $name  $outcome  worktree of $(dirname "$common"), not of --repo $REPO"
      SKIPPED=$((SKIPPED + 1))
      continue
    fi
  elif [ -n "$common" ]; then
    main=$(dirname "$common")
  else
    say "FAILED    $name  $outcome  $dir is not a git worktree; pass --repo DIR"
    FAILED=$((FAILED + 1))
    continue
  fi

  force=""
  if [ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]; then
    if [ "$FORCE" -eq 1 ]; then
      force="--force"
    else
      say "skip      $name  $outcome  uncommitted changes in $dir; pass --force"
      SKIPPED=$((SKIPPED + 1))
      continue
    fi
  fi

  grep -qxF -- "$main" "$TMP/mains" || say "$main" >> "$TMP/mains"
  if [ "$MODE" = dry-run ]; then
    say "remove    $name  $outcome  $dir${force:+  ($force)}"
    WORKTREES=$((WORKTREES + 1))
  elif git -C "$main" worktree remove ${force:+"$force"} "$dir" 2> "$TMP/err"; then
    say "removed   $name  $outcome  $dir"
    WORKTREES=$((WORKTREES + 1))
  else
    say "FAILED    $name  $outcome  $dir: $(tr '\n' ' ' < "$TMP/err")"
    FAILED=$((FAILED + 1))
  fi
done < "$TMP/ended"

# A --repo is pruned even when every directory was already gone.
if [ -n "$REPO" ] && ! grep -qxF -- "$REPO" "$TMP/mains"; then say "$REPO" >> "$TMP/mains"; fi
while read -r main; do
  [ -n "$main" ] || continue
  if [ "$MODE" = dry-run ]; then
    say "prune     $main"
  elif git -C "$main" worktree prune 2> "$TMP/err"; then
    say "pruned    $main"
  else
    say "FAILED    prune $main: $(tr '\n' ' ' < "$TMP/err")"
    FAILED=$((FAILED + 1))
  fi
done < "$TMP/mains"

# --- pull requests ---------------------------------------------------------

# Tickets that ended without a merge; only their PRs are orphans.
awk -F "$SEP" '$3 == "closed" || $3 == "dropped" || $3 == "stopped"' "$TMP/ended" > "$TMP/terminal"

if [ -s "$TMP/terminal" ]; then
  if ! AGENT=$(agent_gh api user --jq .login 2> "$TMP/err") || [ -z "$AGENT" ]; then
    echo "the agent's gh is not logged in (GH_CONFIG_DIR=$GH_AGENT_CONFIG): $(tr '\n' ' ' < "$TMP/err")" >&2
    exit 1
  fi
fi

# Prints the path of a file listing the repository's open PRs, one per line:
# number, head branch, author. One gh call per repository.
prs_file() {
  cache="$TMP/prs-$(printf '%s' "$1" | tr '/' '_')"
  if [ ! -f "$cache" ]; then
    agent_gh pr list --repo "$1" --state open --limit 200 \
      --json number,headRefName,author \
      --jq '.[] | [.number, .headRefName, .author.login] | @tsv' > "$cache" 2> "$TMP/err" ||
      { rm -f "$cache"; echo "gh pr list --repo $1 failed: $(tr '\n' ' ' < "$TMP/err")" >&2; return 1; }
  fi
  printf '%s\n' "$cache"
}

while IFS="$SEP" read -r name _dir outcome url id _state; do
  repo=$(printf '%s' "$url" | sed -n 's#^https://github.com/\([^/]*/[^/]*\)/.*#\1#p')
  if [ -z "$repo" ]; then
    say "skip      $name  $outcome  no GitHub issue on the ticket, PRs not checked"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi
  short=$(printf '%s' "$id" | cut -c1-12)
  prs=$(prs_file "$repo") || exit 1
  while IFS="$TAB" read -r number head author; do
    # The branch the prepare command names, or any agent/* branch of this ticket.
    case "$head" in
      "agent/$name") ;;
      agent/*-"$short") ;;
      *) continue ;;
    esac
    if [ "$author" != "$AGENT" ]; then
      say "skip      $name  $outcome  PR #$number $head opened by $author, not by $AGENT"
      SKIPPED=$((SKIPPED + 1))
      continue
    fi
    if [ "$MODE" = dry-run ]; then
      say "close     $name  $outcome  $repo#$number  $head"
      PRS=$((PRS + 1))
    elif agent_gh pr close "$number" --repo "$repo" \
      --comment "Ticket \`$name\` ended \`$outcome\` without a merge; closing this orphan PR (scripts/agent/cleanup.sh)." \
      > /dev/null 2> "$TMP/err"; then
      say "closed    $name  $outcome  $repo#$number  $head"
      PRS=$((PRS + 1))
    else
      say "FAILED    $name  $outcome  $repo#$number: $(tr '\n' ' ' < "$TMP/err")"
      FAILED=$((FAILED + 1))
    fi
  done < "$prs"
done < "$TMP/terminal"

# --- summary ---------------------------------------------------------------

if [ "$MODE" = dry-run ]; then
  say "dry-run: $ENDED ended tickets, $OPEN open (untouched); $WORKTREES worktrees to remove, $PRS PRs to close, $SKIPPED skipped. Rerun with --apply."
else
  say "done: $ENDED ended tickets, $OPEN open (untouched); $WORKTREES worktrees removed, $PRS PRs closed, $SKIPPED skipped, $FAILED failed."
fi
[ "$FAILED" -eq 0 ]
