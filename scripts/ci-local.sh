#!/usr/bin/env bash
# Preflight local: roda os mesmos pipelines da CI antes de abrir um PR.
#
# Uso:   scripts/ci-local.sh [backend|frontend|library|release|all]
# Padrão: all (backend + frontend + library; release é opt-in por ser lento).
#
# Pré-requisitos: Elixir/OTP no PATH; Postgres em 127.0.0.1:5434
# (user/password "board"); Python 3.10+ no PATH.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
PYTHON="${PYTHON:-python3}"

run_backend() {
  echo "== backend: mix gate =="
  if ! pg_isready -h 127.0.0.1 -p 5434 -q 2>/dev/null; then
    echo "ERRO: Postgres não responde em 127.0.0.1:5434 (o backend precisa dele)." >&2
    exit 1
  fi
  MIX_ENV=test mix gate
}

run_frontend() {
  echo "== frontend: assets.setup -> build -> deploy (MIX_ENV=dev) =="
  MIX_ENV=dev mix assets.setup
  MIX_ENV=dev mix assets.build
  MIX_ENV=dev mix assets.deploy
}

run_library() {
  echo "== library: validador + testes da biblioteca de capacidades =="
  "$PYTHON" capabilities/tools/validar_biblioteca.py
  "$PYTHON" capabilities/tools/test_validar_biblioteca.py
}

run_release() {
  echo "== release: assets (dev) + compile/digest/release (prod) =="
  MIX_ENV=dev mix assets.setup
  MIX_ENV=dev mix assets.build
  MIX_ENV=prod mix compile --warnings-as-errors
  MIX_ENV=prod mix phx.digest
  MIX_ENV=prod mix release --overwrite
}

case "${1:-all}" in
  backend) run_backend ;;
  frontend) run_frontend ;;
  library) run_library ;;
  release) run_release ;;
  all) run_backend; run_frontend; run_library ;;
  *)
    echo "Uso: $0 [backend|frontend|library|release|all]" >&2
    exit 2
    ;;
esac

echo "OK: pipeline(s) verdes."
