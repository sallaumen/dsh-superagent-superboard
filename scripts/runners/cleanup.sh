#!/bin/bash
# Remove finished runner runs left behind by the board: the worktree and the
# ~/.agent_board/runs/<uuid> directory. Dry-run by default; --apply removes.
# Only done/failed/stopped runs older than DAYS are candidates; an active or
# unknown run is never touched.
set -u

ROOT="${RUNNER_ROOT:-$HOME/.agent_board/runs}"
DAYS="${RUNNER_DAYS:-7}"
APPLY=0
FORCE=0

for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    --force) FORCE=1 ;;
    --days=*) DAYS="${arg#--days=}" ;;
    *) printf 'uso: %s [--apply] [--force] [--days=N]\n' "$0" >&2; exit 2 ;;
  esac
done

case "$DAYS" in
  ''|*[!0-9]*) printf 'dias inválidos: %s\n' "$DAYS" >&2; exit 2 ;;
esac

[ -d "$ROOT" ] || { printf 'nada em %s\n' "$ROOT"; exit 0; }

now=$(date +%s)
removed=0
skipped=0

remove_run() {
  local dir="$1" worktree="$2"
  if [ "$APPLY" -eq 1 ]; then
    if [ -d "$worktree" ]; then
      local common repo
      common="$(git -C "$worktree" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
      if [ -n "$common" ]; then
        repo="$(dirname "$common")"
        if [ "$FORCE" -eq 1 ]; then
          git -C "$repo" worktree remove --force "$worktree" >/dev/null 2>&1 || true
        else
          git -C "$repo" worktree remove "$worktree" >/dev/null 2>&1 || {
            printf 'worktree sujo, mantido (use --force): %s\n' "$worktree"
            skipped=$((skipped + 1))
            return
          }
        fi
      fi
    fi
    rm -rf "$dir"
    printf 'removido: %s\n' "$dir"
    removed=$((removed + 1))
  else
    printf 'removeria: %s (%s)\n' "$dir" "$(du -sh "$dir" 2>/dev/null | cut -f1)"
    removed=$((removed + 1))
  fi
}

for dir in "$ROOT"/*; do
  [ -d "$dir" ] || continue
  mtime="$(stat -c %Y "$dir" 2>/dev/null || stat -f %m "$dir" 2>/dev/null || echo "$now")"
  [ "$mtime" -lt $((now - DAYS * 86400)) ] || continue
  status="$(cat "$dir/status" 2>/dev/null || true)"
  case "$status" in
    done|failed|stopped) remove_run "$dir" "$dir/worktree" ;;
    *) printf 'ativo/desconhecido, mantido: %s (%s)\n' "$dir" "${status:-sem status}"; skipped=$((skipped + 1)) ;;
  esac
done

printf 'candidatos: %s, mantidos: %s%s\n' "$removed" "$skipped" "$([ "$APPLY" -eq 0 ] && printf ' (dry-run; use --apply)')"
