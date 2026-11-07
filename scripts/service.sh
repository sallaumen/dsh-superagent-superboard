#!/bin/sh
# The launchd entry point. Runs the board on 4099, forever, from this checkout.
# Everything comes from .env.local through config/runtime.exs -- no secret here.
set -eu

cd "$(dirname "$0")/.."

export MIX_ENV="${MIX_ENV:-dev}"
export PORT="${PORT:-4099}"
export PHX_SERVER=true
export AGENT_BOARD_RESTART_MODE="${AGENT_BOARD_RESTART_MODE:-supervised}"
# Info, not the dev default of debug: the log keeps errors, retries and the
# voice pipeline's lines instead of every SQL query the poller runs.
export LOG_LEVEL="${LOG_LEVEL:-info}"

mix deps.get
mix ecto.migrate
exec mix phx.server
