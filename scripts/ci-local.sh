#!/usr/bin/env bash
# Pré-voo local de PR; contratos e relação com a CI em PIPELINES.md.
#
# Uso:   scripts/ci-local.sh [backend|frontend|library|release|all]
# Padrão: all (backend + frontend + library; release é opt-in por ser lento).
#
# Pré-requisitos e efeitos: PIPELINES.md, seção "Matriz de scripts".
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CURRENT="início"
on_error() {
  echo "FALHOU no pipeline: $CURRENT (comando anterior; saída $?)." >&2
}
trap on_error ERR

require() {
  # require <descrição> <comando...>  — falha com instrução clara de setup.
  local description="$1"
  shift
  if ! "$@" >/dev/null 2>&1; then
    echo "ERRO: $description — instale/configure antes de rodar o pré-voo." >&2
    exit 1
  fi
}

require_mix() {
  require "mix não está no PATH (Elixir/OTP)" mix --version
}

run_backend() {
  CURRENT="backend"
  echo "== backend: mix gate (com dialyzer) + sobelow =="
  require_mix
  require "Postgres não responde em 127.0.0.1:5434 (user/password \"board\")" \
    pg_isready -h 127.0.0.1 -p 5434 -q
  MIX_ENV="test" mix gate
  MIX_ENV="test" mix sobelow --exit
}

run_frontend() {
  CURRENT="frontend"
  echo "== frontend: check_assets -> assets.setup -> build -> deploy (MIX_ENV=dev) =="
  require_mix
  npm audit --prefix scripts/agent/alpine --audit-level=low
  bash scripts/check_assets.sh
  MIX_ENV="dev" mix assets.setup
  MIX_ENV="dev" mix assets.build
  MIX_ENV="dev" mix assets.deploy
}

run_library() {
  CURRENT="library"
  echo "== library: referências ao Elixir Agent Kit =="
  require_mix
  mix agent_kit.check
}

run_release() {
  CURRENT="release"
  echo "== release: assets (dev) + compile/digest/release (prod) =="
  require_mix
  MIX_ENV="dev" mix assets.setup
  MIX_ENV="dev" mix assets.build
  MIX_ENV="prod" mix compile --warnings-as-errors
  MIX_ENV="prod" mix phx.digest
  MIX_ENV="prod" mix release --overwrite
}

# Progress is observational. A missing reporter or unwritable state directory
# must never skip a command, change its exit status or block a focused run.
progress() {
  python3 "$ROOT/scripts/ci-progress.py" "$1" "$CURRENT" "$RUN" 2>/dev/null || :
}

finish_progress() {
  local rc=$?
  if [[ -n "$RUN" ]]; then
    kill "$WATCH" 2>/dev/null || :
    wait "$WATCH" 2>/dev/null || :
    if [[ "$CURRENT" == ui_review ]]; then
      case "$rc" in
        10) export UI_FAILED_SCREEN=board ;;
        11) export UI_FAILED_SCREEN=inspector ;;
        12) export UI_FAILED_SCREEN=composer ;;
        13) export UI_FAILED_SCREEN=settings ;;
      esac
    fi
    if [[ $rc == 0 ]]; then progress passed
    elif [[ $rc == 130 || $rc == 143 ]]; then progress interrupted
    elif [[ "$CURRENT" == ui_review && $rc == 2 ]]; then progress unavailable
    else progress failed; fi
  fi
}

run_all() {
  CURRENT=backend
  RUN=""
  unset UI_FAILED_SCREEN
  UI_REASON=$(python3 "$ROOT/scripts/ui-review/select.py") || UI_REASON=unknown
  export UI_REASON
  RUN=$(progress start)
  if [[ -n "$RUN" ]]; then
    python3 "$ROOT/scripts/ci-progress.py" watch "$$" "$RUN" </dev/null >/dev/null 2>&1 &
    WATCH=$!
    trap finish_progress EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
  fi
  run_backend
  CURRENT=frontend
  if [[ -n "$RUN" ]]; then progress running; fi
  run_frontend
  CURRENT=library
  if [[ -n "$RUN" ]]; then progress running; fi
  run_library
  if [[ "$UI_REASON" != none ]]; then
    CURRENT=ui_review
    if [[ -n "$RUN" ]]; then progress running; fi
    echo "== UI review: WebKit (reason: $UI_REASON) =="
    # Use the test database already prepared by backend; only fixture rows,
    # inside a transaction. No dev server, external URL or delivery action.
    MIX_ENV=test mix run --no-start scripts/ui-review/run.exs
  fi
}

case "${1:-all}" in
  backend) run_backend ;;
  frontend) run_frontend ;;
  library) run_library ;;
  release) run_release ;;
  all) run_all ;;
  *)
    echo "Uso: $0 [backend|frontend|library|release|all]" >&2
    exit 2
    ;;
esac

echo "OK: pipeline(s) verdes."
