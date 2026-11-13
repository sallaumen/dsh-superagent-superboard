"""Synchronize one registered, local Harness. No shell, no remote target discovery."""
import argparse
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request

HERE = Path(__file__).resolve().parent
ROOT = Path.home() / ".local/share/superboard/runtimes"
MANIFEST = HERE / "harness"


def run(*args, env=None, cwd=None, timeout=90):
    return subprocess.run(args, cwd=cwd, env=env, stdout=subprocess.PIPE,
                          stderr=subprocess.DEVNULL, timeout=timeout, check=True, text=True).stdout


def clean_env():
    return {k: v for k, v in os.environ.items() if k not in ("GH_TOKEN", "GITHUB_TOKEN")}


@contextlib.contextmanager
def lock(path):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    with path.open("a") as f:
        fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield


def prepare():
    digest = hashlib.sha256((MANIFEST / "package-lock.json").read_bytes()).hexdigest()
    dest = ROOT / digest
    with lock(ROOT / ".install.lock"):
        if not dest.exists():
            with tempfile.TemporaryDirectory(dir=ROOT) as tmp:
                stage = Path(tmp) / "install"
                stage.mkdir()
                for name in ("package.json", "package-lock.json"):
                    shutil.copyfile(MANIFEST / name, stage / name)
                run("npm", "ci", "--no-audit", "--no-fund", "--fetch-retries=1",
                    env={k: v for k, v in os.environ.items() if k in ("HOME", "PATH", "TMPDIR", "USER", "LOGNAME")}, cwd=stage, timeout=420)
                run(str(stage / "node_modules/.bin/dsh"), "--version", env=clean_env())
                stage.rename(dest)
        cli = dest / "node_modules/.bin/dsh"
        run(str(cli), "--version", env=clean_env())
        if Path("/etc/alpine-release").exists():
            run("node", str(HERE / "check-alpine-harness.cjs"), str(cli), env=clean_env())
        return cli


class Skip(Exception):
    pass


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args):
        return None


LOCAL_HTTP = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())


class Profile:
    def __init__(self, profile, port, repo, manager, state):
        if not re.fullmatch(r"[a-zA-Z0-9_][A-Za-z0-9_.-]*", profile) or not 0 < port < 65536:
            raise ValueError("invalid profile")
        self.profile, self.repo, self.state = profile, repo, Path(state).resolve()
        self.origin = f"http://127.0.0.1:{port}"
        self.cmd = [sys.executable, manager, "--profile", profile, "--url", self.origin]
        self.selection = ROOT / "profiles" / profile

    def api(self, path, body=None):
        data = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(self.origin + "/orchestrator/api/" + path, data=data,
                                     headers={"x-orchestrator-request": "1", "Content-Type": "application/json"})
        with LOCAL_HTTP.open(req, timeout=5) as res:
            return json.load(res)

    def snapshot(self):
        s = self.api("state")
        setup = s.get("setup") or {}
        if ((setup.get("accounts") or {}).get("repository", "").lower() != self.repo.lower()
                or (setup.get("machine") or {}).get("stateDir") != str(self.state)):
            raise Skip("identity")
        return s

    def pid(self):
        proc = subprocess.run([*self.cmd, "status"], capture_output=True, text=True, timeout=10)
        status = json.loads(proc.stdout)
        if proc.returncode or status["manually_stopped"] or len(status["pids"]) != 1:
            raise Skip("unavailable")
        return int(status["pids"][0])

    def launcher(self):
        args = run("ps", "-ww", "-p", str(self.pid()), "-o", "args=").strip()
        match = re.fullmatch(r"\S*node (/.+/dsh) --profile " + re.escape(self.profile) + r"(?: --no-open)?", args)
        if not match or not Path(match[1]).is_file():
            raise Skip("unavailable")
        return Path(match[1])

    def change(self, action, cli):
        env = clean_env()
        env["PATH"] = str(cli.parent) + os.pathsep + env["PATH"]
        run(*self.cmd, action, "--respect-stop", env=env, timeout=380)

    def recover(self, old, target):
        # An intentional stop outside this operation wins over recovery.
        status = subprocess.run([*self.cmd, "status"], capture_output=True, text=True, timeout=10)
        observed = json.loads(status.stdout)
        if observed["manually_stopped"]:
            return
        if observed["pids"] == []:
            self.change("start", old)  # manager refuses an occupied port
        elif len(observed["pids"]) == 1:
            self.snapshot()
            if self.launcher().resolve() == target.resolve():
                if idle(self.snapshot(), True):
                    self.change("restart", old)

    def select(self, cli):
        self.selection.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=self.selection.parent) as tmp:
            link = Path(tmp) / "bin"
            link.symlink_to(cli.parent, target_is_directory=True)
            link.replace(self.selection)


def idle(s, paused):
    load = s.get("load") or {}
    return (s.get("paused") is paused and type(load.get("running")) is int
            and type(load.get("queued")) is int and load["running"] == load["queued"] == 0)


def sync(p):
    with lock(ROOT / "locks" / p.profile):
        try:
            s = p.snapshot()
        except (OSError, ValueError):
            return "unavailable"
        if s.get("paused") is not False:
            return "paused"
        if (s.get("health", {}).get("runtime") or {}).get("state") != "ready":
            return "unavailable"
        if not idle(s, False):
            return "busy"
        old = p.launcher()
        cli = prepare()
        if old.resolve() == cli.resolve():
            p.select(cli)
            return "current"
        if not idle(p.snapshot(), False) or p.launcher() != old:
            return "changed"
        try:
            p.api("executor/pause", {"paused": True})
            if not idle(p.snapshot(), True) or p.launcher() != old:
                return "changed"
            try:
                # The manager holds its operation lock across stop and start.
                p.change("restart", cli)
                if p.launcher().resolve() != cli.resolve():
                    raise RuntimeError("unexpected launcher")
                p.snapshot()
                p.select(cli)
            except Exception:
                # Do not start over a foreign listener, a manual stop or duplicate.
                # The manager enforces uniqueness; a normal start cannot replace
                # a live, failed process.
                try:
                    p.recover(old, cli)
                finally:
                    raise RuntimeError("handoff failed; inspect agent status")
            return "updated"
        finally:
            # Only undo the pause on the same repo and state. A failed recovery
            # stays visible as an error; do not silently claim success.
            try:
                if p.snapshot().get("paused") is True:
                    p.api("executor/pause", {"paused": False})
                    if p.snapshot().get("paused") is not False:
                        raise RuntimeError("could not resume executor")
            except Skip as exc:
                raise RuntimeError("could not verify the original agent") from exc


def main():
    parser = argparse.ArgumentParser()
    for key in ("profile", "repo", "manager", "state"):
        parser.add_argument("--"+key, required=True)
    parser.add_argument("--port", type=int, required=True)
    try:
        print(sync(Profile(**vars(parser.parse_args()))))
    except Skip as exc:
        print(str(exc))
    except BlockingIOError:
        print("in_progress")
    except Exception:
        print("failed")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
