"""Board-owned stage selections and execution. Only catalog IDs cross the UI boundary."""
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile
import time

import stack_rules

CATALOG = json.loads(Path(__file__).with_name("stages.json").read_text())


def selection(ids):
    if (not isinstance(ids, list) or len(ids) > len(CATALOG)
            or any(not isinstance(i, str) or i not in CATALOG for i in ids)
            or len(set(ids)) != len(ids)):
        raise ValueError("Invalid stage selection")
    return [i for i in CATALOG if i in ids]


def location(repo, create=False):
    if not re.fullmatch(r"[A-Za-z0-9_-]+/[A-Za-z0-9_.-]+", repo) or repo.split("/")[1] in (".", ".."):
        raise ValueError("Invalid repository")
    owner, name = repo.lower().split("/")
    folder = Path.home()
    for part in (".config", "superboard", "task-stages", owner):
        folder /= part
        if create:
            folder.mkdir(mode=0o700, exist_ok=True)
        info = folder.lstat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o022:
            raise ValueError("Unsafe stage configuration directory")
    return folder / (name + ".json")


def stored(repo):
    try:
        path = location(repo)
        info = path.lstat()
    except FileNotFoundError:
        return None
    if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
            or info.st_mode & 0o022 or info.st_size > 2048):
        raise ValueError("Invalid stage configuration")
    raw = json.loads(path.read_bytes())
    return selection(raw) if isinstance(raw, list) else overrides(raw)


def overrides(values):
    if not isinstance(values, dict) or any(i not in CATALOG or m not in ("always", "changed", "off")
                                          for i, m in values.items()):
        raise ValueError("Invalid project rules")
    return values


def load(repo):
    raw = stored(repo)
    return raw if isinstance(raw, list) else [i for i in CATALOG if (raw or {}).get(i, "off") != "off"]


def profile(repo, folder, base=None):
    folder = stack_rules.checkout(repo, folder)
    detected = []
    if folder:
        if not base:
            candidate = stack_rules.base_ref(folder)
            try:
                stack_rules.git(folder, "rev-parse", "--verify", candidate)
                base = candidate
            except subprocess.CalledProcessError:
                pass
        detected = stack_rules.detected(folder, base)
    raw = stored(repo)
    if isinstance(raw, list):
        modes = {i: ("always" if i in raw else "off") for i in CATALOG}
    else:
        modes = {i: (raw or {}).get(i, stack_rules.RULES[i]["mode"] if i in detected else "off")
                 for i in CATALOG}
    return dict(detected=detected, modes=modes, stored=raw, available=bool(folder))


def plan(repo, base=None):
    if not stack_rules.checkout(repo, "."):
        raise ValueError("Project does not match worktree origin")
    data = profile(repo, ".", base)
    ids = [i for i in CATALOG if i in data["detected"] or data["modes"][i] != "off"
           or isinstance(data["stored"], dict) and i in data["stored"]]
    paths = stack_rules.changed(".", base) if any(data["modes"][i] == "changed" for i in ids) else []
    return stack_rules.decide(ids, data["modes"], paths)


def save_rules(repo, changes, expected):
    changes = overrides(changes)
    path = location(repo, create=True)
    with path.with_suffix(".lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        raw = stored(repo)
        if raw != expected:
            raise ValueError("Project rules changed")
        # Legacy selections are explicit, including every unchecked old option.
        old = {i: ("always" if i in raw else "off") for i in CATALOG} if isinstance(raw, list) else (raw or {})
        atomic(path, {**old, **changes})


def atomic(path, data):
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False, mode="w") as tmp:
        json.dump(data, tmp)
    os.replace(tmp.name, path)


def save(repo, ids, expected):
    ids, expected = selection(ids), selection(expected)
    path = location(repo, create=True)
    with path.with_suffix(".lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if load(repo) != expected:
            raise ValueError("Selection changed; reload before saving")
        atomic(path, ids)


@contextmanager
def stage_process(argv):
    import signal
    # Make cancellation of the managed runner stop both the tool and its children.
    proc = subprocess.Popen(argv, stdin=subprocess.DEVNULL, start_new_session=True)
    def cancel(signum, _frame):
        raise InterruptedError(f"Interrupted by signal {signum}")
    handlers = {sig: signal.signal(sig, cancel) for sig in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM)}
    try:
        yield proc
    finally:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.wait()
        for sig, handler in handlers.items():
            signal.signal(sig, handler)


def execute(repo, ids, observe=None):
    if not ids:
        return
    reasons = ids if isinstance(ids, dict) else {i: "required" for i in ids}
    active = [i for i in ids if reasons[i] not in ("unrelated", "disabled")]
    remote = subprocess.check_output(["git", "remote", "get-url", "origin"], text=True).strip()
    target = re.fullmatch(r"(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)([^/]+/[^/]+?)(?:\.git)?/?", remote, re.I)
    if not target or target[1].casefold() != repo.casefold():
        raise ValueError("Project does not match worktree origin")
    root_dir = subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip()
    if not os.path.samefile(root_dir, "."):
        os.chdir(root_dir)
    wd = os.environ.get("PWD", "")
    if not os.path.isabs(wd) or not os.path.isdir(wd) or not os.path.samefile(wd, "."):
        wd = os.getcwd()
    key = hashlib.sha256(os.fsencode(os.path.normpath(wd))).hexdigest()
    root = Path(os.environ.get("SUPERBOARD_PREFLIGHT_DIR") or Path.home() / ".local/state/superboard/preflight")
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    path = root / (key + ".stages.json")
    with path.with_suffix(".lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        data = dict(started=time.time_ns() // 1000, stages=list(ids), reasons=reasons,
                    head=subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip())

        def record(stage, state):
            data.update(stage=stage, state=state, at=int(time.time()))
            atomic(path, data)
            if observe:
                observe(stage, state)

        if not active:
            record(next(iter(ids)), "skipped")
            return
        for stage in active:
            record(stage, "running")
            try:
                with stage_process(CATALOG[stage]) as proc:
                    deadline = time.monotonic() + 1800
                    while True:
                        try:
                            code = proc.wait(timeout=10)
                            break
                        except subprocess.TimeoutExpired:
                            if time.monotonic() >= deadline:
                                raise
                            record(stage, "running")
            except InterruptedError:
                record(stage, "interrupted")
                raise
            except (OSError, subprocess.TimeoutExpired):
                record(stage, "failed")
                raise
            if code:
                record(stage, "failed")
                raise ValueError("Failed stage: " + stage)
            if observe and stage != active[-1]:
                observe(stage, "passed")
        record(active[-1], "passed")


if __name__ == "__main__":
    try:
        action, repo, *args = sys.argv[1:]
        if action == "get":
            print(json.dumps(load(repo)))
        elif action == "profile":
            print(json.dumps(profile(repo, args[0])))
        elif action == "rules":
            save_rules(repo, *(json.loads(arg) for arg in args))
        elif action == "save":
            save(repo, *(json.loads(arg) for arg in args))
        elif action == "run":
            execute(repo, plan(repo))
        else:
            raise ValueError("Unknown stage operation")
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        sys.exit(str(error))
