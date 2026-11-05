#!/bin/sh
# The launchd entry point. Runs the board on 4099, forever, from this checkout.
# Everything comes from .env.local through config/runtime.exs -- no secret here.
set -eu

cd "$(dirname "$0")/.."

export MIX_ENV="${MIX_ENV:-dev}"
export PORT="${PORT:-4099}"
export PHX_SERVER=true

exec mix phx.server
