"""Ticket worktree branch and idempotent PR creation for the Harness worker shim."""
import contextlib
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def output(*argv):
    return subprocess.check_output(argv, text=True).strip()


def check(condition, reason):
    if not condition:
        raise ValueError(reason)


def metadata():
    return Path(output("git", "rev-parse", "--absolute-git-dir")) / "superboard-assignment.json"


@contextlib.contextmanager
def locked(path):
    with path.with_suffix(".lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def store(path, data):
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as f:
        json.dump(data, f)
    os.replace(f.name, path)


def prepare(repo, name, assignment, mode):
    check(re.fullmatch(r"[\w.-]+/[\w.-]+", repo, re.ASCII) and
          all(n not in (".", "..") for n in repo.split("/")), "Invalid repository")
    check(re.fullmatch(r"[\w-]+", name, re.ASCII) and re.fullmatch(r"[a-f0-9]{32}", assignment)
          and mode in ("new", "keep"), "Invalid assignment")
    path = metadata()
    check(Path(output("git", "rev-parse", "--show-toplevel")).resolve() == Path.cwd().resolve()
          and Path.cwd().name == name, "Unexpected ticket checkout")
    with locked(path):
        current = output("git", "symbolic-ref", "--short", "HEAD")
        old = json.loads(path.read_text()) if path.exists() else {}
        if old and old["assignment"] == assignment:
            check(old["branch"] == current and old["repo"] == repo, "Branch changed during assignment")
            return current
        check(current.split("/")[-1] == name, "Existing checkout is not on its ticket branch")
        branch = current
        if mode == "new":
            branch = f"agent/run-{assignment}/{name}"
            if current != branch:
                check(not output("git", "status", "--porcelain"), "Previous checkout has pending edits")
                # Fetch to a private ref: FETCH_HEAD is shared by concurrent ticket worktrees.
                ref = "refs/dsh-superagent/assignments/" + assignment
                output("git", "fetch", "--no-tags", f"https://github.com/{repo}.git", f"HEAD:{ref}")
                output("git", "switch", "-c", branch, output("git", "rev-parse", ref))
        store(path, {"repo": repo, "assignment": assignment, "branch": branch})
        return branch


def options(args, short, long):
    for i, arg in enumerate(args):
        if arg in (short, long):
            yield args[i + 1] if i + 1 < len(args) else ""
        elif arg.startswith(long + "="):
            yield arg.split("=", 1)[1]
        elif arg.startswith(short) and not arg.startswith("--") and len(arg) > 2:
            yield arg[2:].lstrip("=")


def head_repo(branch, repo, args):
    heads = list(options(args, "-H", "--head"))
    repos = list(options(args, "-R", "--repo"))
    check(all(h in (branch, repo.split("/")[0] + ":" + branch) for h in heads), "Wrong PR head")
    check(all(r.casefold() == repo.casefold() for r in repos), "Wrong PR repository")
    return ([] if heads else ["--head", branch]) + ([] if repos else ["--repo", repo])


def create(cli, args):
    try:
        path = metadata()
    except subprocess.CalledProcessError:
        path = None
    if path is None or not path.is_file():
        os.execvpe(cli, [cli, *args], os.environ)
    with locked(path):
        data = json.loads(path.read_text())
        branch, repo = data["branch"], data["repo"]
        check(output("git", "symbolic-ref", "--short", "HEAD") == branch, "Use the assigned branch: " + branch)
        fixed = head_repo(branch, repo, args)
        if data.get("url"):
            return data["url"]
        rows = json.loads(output(cli, "pr", "list", "-R", repo, "--state", "all", "--head", branch,
                                 "--json", "url,isCrossRepository"))
        existing = [p["url"] for p in rows if not p["isCrossRepository"]]
        check(len(existing) <= 1, "Ambiguous PR history; inspect before publishing")
        if existing:
            url = existing[0]
        else:
            check(not any(a in ("--web", "--dry-run") for a in args), "Use noninteractive PR creation")
            # The board-managed gh may print its local checks before the URL.
            lines = output(cli, *args, *fixed).splitlines()
            if lines[:-1]:
                print("\n".join(lines[:-1]), file=sys.stderr)
            url = lines[-1] if lines else ""
        check(re.fullmatch(r"https://github\.com/" + re.escape(repo) + r"/pull/[0-9]+", url, re.I), "Verify PR on GitHub before retrying")
        data["url"] = url
        store(path, data)
        return url


if __name__ == "__main__":
    try:
        if sys.argv[1] == "prepare":
            print(prepare(*sys.argv[2:]))
        elif sys.argv[1] == "create":
            print(create(sys.argv[2], sys.argv[3:]))
        else:
            sys.exit(2)
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as e:
        sys.exit(f"Assignment branch: {e}")
