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

# The database is a Docker container that comes back a minute or two after
# login, later than launchd starts this script. Wait for it here: without the
# wait, `mix ecto.migrate` fails and launchd retries every ten seconds, and a
# container that never returns looks like a board that never starts. If it
# does not answer in time, exit and let launchd try again.
db_host="${AGENT_BOARD_DB_HOST:-127.0.0.1}"
db_port="${AGENT_BOARD_DB_PORT:-5434}"
db_wait="${AGENT_BOARD_DB_WAIT:-300}"

# pg_isready knows a Postgres still recovering from an unclean shutdown; nc
# only knows the port is open. Homebrew's libpq is keg-only, off the PATH.
db_ready() {
  if command -v pg_isready >/dev/null 2>&1; then
    pg_isready -q -h "$db_host" -p "$db_port" -t 2
  elif [ -x /opt/homebrew/opt/libpq/bin/pg_isready ]; then
    /opt/homebrew/opt/libpq/bin/pg_isready -q -h "$db_host" -p "$db_port" -t 2
  else
    nc -z -G 2 "$db_host" "$db_port" >/dev/null 2>&1
  fi
}

waited=0
until db_ready; do
  if [ "$waited" -ge "$db_wait" ]; then
    echo "service.sh: Postgres at $db_host:$db_port did not answer in ${db_wait}s; is its container running? launchd will retry"
    exit 75
  fi
  if [ $((waited % 30)) -eq 0 ]; then
    echo "service.sh: waiting for Postgres at $db_host:$db_port (${waited}s)"
  fi
  sleep 2
  waited=$((waited + 2))
done

mix deps.get
mix ecto.migrate
exec mix phx.server
