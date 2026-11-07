#!/bin/sh
# Shared config for the agent scripts. The API needs this exact header.
STATE_DIR="${SUPERAGENT_STATE_DIR:-$HOME/.dsh/state/superagent}"
API="${SUPERAGENT_API:-http://127.0.0.1:3082/orchestrator/api}"
DB="$STATE_DIR/orchestrator.sqlite"
# The prototype checkout: its scripts/dsh-superagent starts, stops and checks
# the orchestrator (keepalive.sh).
DSH_SUPERAGENT_HOME="${DSH_SUPERAGENT_HOME:-$HOME/Documents/deepseek-harness/default-workspace/dsh-superagent-prototype}"

api() { curl -s -H "x-orchestrator-request: 1" "$API/state"; }
