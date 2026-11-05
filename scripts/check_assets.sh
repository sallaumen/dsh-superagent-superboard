#!/usr/bin/env bash
# Checks determinísticos sobre os fontes de frontend, além do build.
#
# Roda antes de `mix assets.build` no pipeline frontend (make frontend,
# scripts/ci-local.sh frontend e o job "frontend · assets" da CI).
# Somente leitura: não gera nem altera arquivos.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
errors=0

fail() {
  echo "ERRO: $1" >&2
  errors=$((errors + 1))
}

# 1. Pontos de entrada existem e não estão vazios.
for f in assets/js/app.js assets/css/app.css; do
  [[ -s "$f" ]] || fail "$f ausente ou vazio"
done

# 2. O CSS usa o entry do Tailwind e escaneia as classes do app (HEEx incluído).
grep -q '@import "tailwindcss"' assets/css/app.css ||
  fail 'assets/css/app.css sem @import "tailwindcss"'
grep -q '@source "../../lib/agent_board_web"' assets/css/app.css ||
  fail 'assets/css/app.css não escaneia lib/agent_board_web (classes em HEEx)'

# 3. Sem sobras de debug no JS autoral (o vendor em assets/vendor fica fora).
matches="$(grep -rnE 'console\.log\(|console\.debug\(|debugger' assets/js --include='*.js' || true)"
if [[ -n "$matches" ]]; then
  while IFS= read -r line; do
    fail "sobra de debug no JS autoral: $line"
  done <<<"$matches"
fi

if ((errors > 0)); then
  echo "check_assets: $errors problema(s)." >&2
  exit 1
fi
echo "check_assets: OK (entradas, pipeline tailwind e JS sem debug)."
