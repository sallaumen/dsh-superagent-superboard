#!/bin/sh
# Is the agent configured, alive and idle? One screen, no guessing.
set -eu
. "$(dirname "$0")/_common.sh"

if ! STATE=$(api) || [ -z "$STATE" ]; then
  echo "AGENT DOWN: no answer at $API"
  echo "  start it:  tmux new -s dsh-superagent && dsh --profile superagent"
  exit 1
fi

echo "$STATE" | python3 -c '
import json,sys
d = json.load(sys.stdin)
s = d.get("setup") or {}
h = d.get("health") or {}
a = s.get("accounts") or {}
l = d.get("load") or {}

def line(label, ok, detail=""):
    print(("  OK   " if ok else "  FAIL ") + label + ("  " + detail if detail else ""))

print("ORCHESTRATOR")
print("  master   " + str(d.get("masterId"))[:20])
print("  paused   " + ("yes" if d.get("paused") else "no"))
print("  load     running %s / queued %s / max %s" % (l.get("running"), l.get("queued"), l.get("maxWorkers")))
print("HEALTH")
for name in ("runtime", "relay", "notice"):
    v = h.get(name) or {}
    line(name, v.get("state") == "ready", str(v.get("detail") or ""))
print("CONFIG")
line("repository", bool(a.get("repository")), str(a.get("repository") or ""))
line("agent bot", bool(a.get("agent")), str(a.get("agent") or ""))
p = s.get("problem")
line("problem", p is None, str(p) if p else "none")
sys.exit(0 if (not d.get("paused") and p is None and a.get("repository")) else 2)
'
CODE=$?
[ "$CODE" -eq 0 ] || echo "  -> not ready (exit $CODE)"
