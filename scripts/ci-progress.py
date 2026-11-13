"""Best-effort evidence for ci-local.sh all; never a delivery gate."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time


def record(action, stage, run):
    directory = os.environ.get("PWD", "")
    if not os.path.isabs(directory) or not os.path.isdir(directory) or not os.path.samefile(directory, "."):
        directory = os.getcwd()
    directory = os.path.normpath(directory)
    key = hashlib.sha256(os.fsencode(directory)).hexdigest()
    root = Path(os.environ.get("SUPERBOARD_PREFLIGHT_DIR") or
                Path.home() / ".local/state/superboard/preflight")
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    target = root / (key + ".json")
    with (root / (key + ".lock")).open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if action == "start":
            head = subprocess.run(["git", "rev-parse", "--verify", "HEAD"], capture_output=True,
                                  text=True, check=True).stdout.strip()
            run = str(time.time_ns())
            data = dict(run=run, head=head, started=int(run) // 1000)
        else:
            data = json.loads(target.read_bytes())
            if data["run"] != run or data["state"] != "running":
                return  # A newer invocation owns this worktree.
        if action != "heartbeat":
            data.update(stage=stage, state="running" if action == "start" else action)
        data["at"] = int(time.time())
        with tempfile.NamedTemporaryFile(dir=root, delete=False, mode="w") as tmp:
            json.dump(data, tmp)
        os.replace(tmp.name, target)
        if action == "start":
            print(run)
        return True


if __name__ == "__main__":
    if sys.argv[1] == "watch":
        # The shell starts this child directly. Reparenting ends the heartbeat
        # even when the shell was killed without running its EXIT trap.
        parent = int(sys.argv[2])
        while os.getppid() == parent:
            time.sleep(15)
            if os.getppid() != parent or not record("heartbeat", None, sys.argv[3]):
                break
    else:
        record(*sys.argv[1:])
