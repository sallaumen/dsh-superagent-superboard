#!/usr/bin/env bash
# Pré-voo local de PR; contratos e relação com a CI em PIPELINES.md.
#
# Uso:   scripts/ci-local.sh [backend|frontend|library|release|all]
# Padrão: all (backend + frontend + library; release é opt-in por ser lento).
#
# Pré-requisitos e efeitos: PIPELINES.md, seção "Matriz de scripts".
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
PYTHON="${PYTHON:-python3}"

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

require_python() {
  local version
  if ! version="$("$PYTHON" -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null)"; then
    echo "ERRO: Python (>= 3.10) não encontrado no PATH; o pipeline library precisa dele." >&2
    exit 1
  fi
  local major minor
  IFS=. read -r major minor <<<"$version"
  if ((major < 3 || (major == 3 && minor < 10))); then
    echo "ERRO: Python $version encontrado; o pipeline library exige >= 3.10." >&2
    exit 1
  fi
}

run_backend() {
  CURRENT="backend"
  echo "== backend: mix gate + sobelow =="
  require_mix
  require "Postgres não responde em 127.0.0.1:5434 (user/password \"board\")" \
    pg_isready -h 127.0.0.1 -p 5434 -q
  MIX_ENV=test mix gate
  MIX_ENV=test mix sobelow --exit
}

run_frontend() {
  CURRENT="frontend"
  echo "== frontend: check_assets -> assets.setup -> build -> deploy (MIX_ENV=dev) =="
  require_mix
  bash scripts/check_assets.sh
  MIX_ENV=dev mix assets.setup
  MIX_ENV=dev mix assets.build
  MIX_ENV=dev mix assets.deploy
}

run_library() {
  CURRENT="library"
  echo "== library: validador + testes da biblioteca de capacidades =="
  require_python
  "$PYTHON" capabilities/tools/validar_biblioteca.py
  "$PYTHON" capabilities/tools/test_validar_biblioteca.py
}

run_release() {
  CURRENT="release"
  echo "== release: assets (dev) + compile/digest/release (prod) =="
  require_mix
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

CURRENT="—"
echo "OK: pipeline(s) verdes."
