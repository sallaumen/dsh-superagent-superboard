#!/bin/bash
# One local execution, started by AgentBoard.Runners in its own tmux session.
# The board never waits on this process: it observes status, session_id,
# result and error in $RUN_DIR.
set -u

RUN_DIR="${RUN_DIR:?}"
EXECUTOR="${EXECUTOR:?}"
REPO_DIR="${REPO_DIR:?}"
BRANCH="${BRANCH:?}"
WORKTREE="${WORKTREE:?}"
PROMPT_FILE="${PROMPT_FILE:?}"
MODEL="${MODEL:-}"
BUDGET_USD="${BUDGET_USD:-}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-7200}"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"
CODEX_BIN="${CODEX_BIN:-codex}"
TIMEOUT_BIN="$(command -v timeout || echo /opt/homebrew/bin/timeout)"

status() { printf '%s\n' "$1" > "$RUN_DIR/status"; }
fail() {
  printf '%s\n' "$1" > "$RUN_DIR/error"
  status "failed"
  exit 1
}

guard="$(cd "$(dirname "$0")/../.." && pwd)/priv/merge_gate/guard.py"
delegate="$(command -v gh)" || fail "GitHub CLI unavailable"
python3 "$guard" install "$RUN_DIR/merge-bin" "${REPO_SLUG:?}" "$delegate" >/dev/null || fail "Merge gate unavailable"
export PATH="$RUN_DIR/merge-bin:$PATH"

mkdir -p "$RUN_DIR"
status "starting"

# A fresh worktree from origin/main keeps the board's checkout untouched.
git -C "$REPO_DIR" fetch origin main --quiet || fail "git fetch falhou"
git -C "$REPO_DIR" worktree add -b "$BRANCH" "$WORKTREE" origin/main >/dev/null 2>&1 \
  || fail "git worktree add falhou para $BRANCH"

cd "$WORKTREE" || fail "worktree inacessível"

printf '%s\n' "$RUN_ID" > "$RUN_DIR/session_id"
status "running"

if [ "$EXECUTOR" = "claude" ]; then
  timeout_args=(--max-budget-usd "$BUDGET_USD")
  # A blank ceiling would make the CLI reject the argument; the board always
  # sets one for Claude, but be defensive.
  [ -n "$BUDGET_USD" ] || timeout_args=()

  "$TIMEOUT_BIN" "$TIMEOUT_SECONDS" "$CLAUDE_BIN" \
    -p "$(cat "$PROMPT_FILE")" \
    --session-id "$RUN_ID" \
    --output-format json \
    --permission-mode bypassPermissions \
    --model "$MODEL" \
    "${timeout_args[@]}" \
    </dev/null > "$RUN_DIR/claude.json" 2> "$RUN_DIR/stderr"
  rc=$?

  is_error="$(jq -r '.is_error // false' "$RUN_DIR/claude.json" 2>/dev/null || echo false)"
  subtype="$(jq -r '.subtype // empty' "$RUN_DIR/claude.json" 2>/dev/null || true)"

  if [ "$rc" -eq 0 ] && [ "$is_error" != "true" ]; then
    jq -r '.result // empty' "$RUN_DIR/claude.json" 2>/dev/null > "$RUN_DIR/result" || true
    [ -s "$RUN_DIR/result" ] || printf 'Execução concluída.\n' > "$RUN_DIR/result"
    jq -r '.total_cost_usd // empty' "$RUN_DIR/claude.json" 2>/dev/null > "$RUN_DIR/cost_usd" || true
    status "done"
  else
    jq -r '.total_cost_usd // empty' "$RUN_DIR/claude.json" 2>/dev/null > "$RUN_DIR/cost_usd" || true

    if [ "$subtype" = "error_max_budget_usd" ]; then
      printf 'Teto de orçamento da tarefa atingido; a execução parou antes do resultado.\n' > "$RUN_DIR/error"
    else
      detail="$(jq -r '.error // .subtype // empty' "$RUN_DIR/claude.json" 2>/dev/null || true)"
      tail -c 4000 "$RUN_DIR/stderr" > "$RUN_DIR/error" 2>/dev/null || true
      [ -s "$RUN_DIR/error" ] || printf '%s\n' "${detail:-O Claude Code saiu com $rc.}" > "$RUN_DIR/error"
    fi
    status "failed"
  fi
else
  "$TIMEOUT_BIN" "$TIMEOUT_SECONDS" "$CODEX_BIN" \
    exec --json \
    -m "$MODEL" \
    -s workspace-write \
    -C "$WORKTREE" \
    -o "$RUN_DIR/last.txt" \
    "$(cat "$PROMPT_FILE")" \
    </dev/null > "$RUN_DIR/codex.jsonl" 2> "$RUN_DIR/stderr"
  rc=$?

  thread_id="$(jq -r 'select(.type == "thread.started") | .thread_id' "$RUN_DIR/codex.jsonl" 2>/dev/null | head -1 || true)"
  [ -n "$thread_id" ] && printf '%s\n' "$thread_id" > "$RUN_DIR/session_id"

  codex_error="$(jq -r 'select(.type == "error" or .type == "turn.failed") | (.message // .error.message // .error // empty)' "$RUN_DIR/codex.jsonl" 2>/dev/null | tail -1 || true)"

  if [ "$rc" -eq 0 ] && [ -z "$codex_error" ]; then
    [ -s "$RUN_DIR/last.txt" ] && cp "$RUN_DIR/last.txt" "$RUN_DIR/result" \
      || printf 'Execução concluída.\n' > "$RUN_DIR/result"
    status "done"
  else
    if [ -n "$codex_error" ]; then
      printf '%s\n' "$codex_error" > "$RUN_DIR/error"
    else
      tail -c 4000 "$RUN_DIR/stderr" > "$RUN_DIR/error" 2>/dev/null || true
      [ -s "$RUN_DIR/error" ] || printf 'O Codex saiu com %s.\n' "$rc" > "$RUN_DIR/error"
    fi
    status "failed"
  fi
fi
