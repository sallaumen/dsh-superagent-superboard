"""Trusted broker for a networkless worker. Input is data; only Docker executes its shell."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import selectors
import shlex
import stat
import time
import subprocess
import sys
import tempfile


def require(value, message):
    if not value:
        raise ValueError(message)


def run(*argv, data=None, limit=120, cwd=None, env=None, cap=128_000_000, tail=False):
    # A worker controls command output (including stderr). Drain both pipes
    # without retaining an unbounded stream or extending the deadline.
    with tempfile.TemporaryFile() as stdin, selectors.DefaultSelector() as sel:
        if data:
            stdin.write(data)
            stdin.seek(0)
        proc = subprocess.Popen(argv, stdin=stdin, stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=cwd, env=env)
        out, err = bytearray(), bytearray()
        deadline = time.monotonic() + limit
        try:
            for stream in (proc.stdout, proc.stderr):
                sel.register(stream, selectors.EVENT_READ)
            while sel.get_map():
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise TimeoutError(f"{argv[0]} timed out")
                for key, _ in sel.select(remaining):
                    chunk = os.read(key.fd, 65536)
                    if not chunk:
                        sel.unregister(key.fileobj)
                    elif key.fileobj is proc.stdout:
                        out.extend(chunk)
                        if len(out) > cap:
                            require(tail, "Command output exceeds the allowed size")
                            del out[:-cap]
                    else:
                        err.extend(chunk)
                        del err[:-4096]
            if proc.wait(timeout=max(0.1, deadline - time.monotonic())):
                details = (out + err).decode(errors="replace")
                failures = re.findall(r"(?m)^ *[0-9]+\) test [^\n]+", details)
                raise ValueError(str(argv[0]) + " failed: " + err[-300:].decode(errors="replace") +
                                 "\n" + "\n".join(failures[-3:])[:450] + "\n" + out[-750:].decode(errors="replace"))
            return bytes(out)
        finally:
            if proc.poll() is None:
                proc.kill()
            proc.wait()
            proc.stdout.close()
            proc.stderr.close()


def record(path, state):
    with tempfile.NamedTemporaryFile(dir=path.parent, mode="w", delete=False) as f:
        json.dump(state, f)
    os.replace(f.name, path)


def docker(name, *argv, data=None, limit=120, **bounds):
    return run("docker", "exec", "-i", name, *argv, data=data, limit=limit, **bounds)


def start(name, image, label):
    # No volumes or host ports. Both copies disappear with the container.
    run("docker", "run", "-d", "--name", name, "--label", "superboard.assignment=" + label,
        "--init", "--hostname", "superboard-worker", "--add-host", "superboard-worker:127.0.0.1",
        "--network", "none", "--add-host", "api.github.com:127.0.0.1", "--add-host", "github.com:127.0.0.1", "--user", "1001:1001", "--read-only", "--cap-drop=ALL",
        "--security-opt", "no-new-privileges", "--pids-limit", "512", "--memory", "4g",
        "--cpus", "4", "--tmpfs", "/tmp:rw,exec,nosuid,nodev,size=2g,mode=1777",
        "--tmpfs", "/home/worker:rw,nosuid,nodev,size=256m,uid=1001,gid=1001",
        "--tmpfs", "/workspace:rw,exec,nosuid,nodev,size=1g,uid=1001,gid=1001",
        "--workdir", "/workspace", "--entrypoint", "/bin/sleep", image, "infinity")


def remove(name, label):
    objects = run("docker", "ps", "-aq", "--filter", "name=^/" + name + "$",
                  "--filter", "label=superboard.assignment=" + label).split()
    if objects:
        run("docker", "rm", "-f", objects[0].decode())


def seed(name, tree, branch):
    # tree originates from git archive at a trusted commit, never from the worker.
    docker(name, "tar", "-x", data=tree)
    docker(name, "git", "init", "-q", "-b", branch)
    docker(name, "git", "add", "-f", ".")
    docker(name, "git", "-c", "user.name=fixture", "-c", "user.email=fixture@localhost",
           "commit", "-qm", "Workspace baseline")
    return docker(name, "git", "rev-parse", "HEAD").decode().strip()


def selected_checks(config, repo, base, check):
    # Only import the operator's installed board, never a file from the ticket.
    folder = Path(config["quality_dir"]).resolve(strict=True)
    require(folder.is_absolute() and not folder.is_relative_to(Path.cwd()), "Unsafe quality catalog")
    sys.path.insert(0, str(folder))
    import task_stages
    import stack_rules
    policy = task_stages.profile(repo, ".", base)
    require(policy["available"], "Unknown project quality policy")
    paths = docker(check, "git", "diff", "--cached", "--name-only", "--no-renames", "-z").split(b"\0")
    changed = stack_rules.changed(".", None)
    paths = None if changed is None else changed + [os.fsdecode(p) for p in paths if p]
    rules = stack_rules.decide(policy["modes"], policy["modes"], paths)
    return [key for key, reason in rules.items() if reason not in ("disabled", "unrelated")]


def publish(a, state, path, config, name, image, tree, title, body):
    require(0 < len(title) <= 180 and 0 < len(body) <= 16000, "Invalid PR text")
    checks = config["checks"]
    require(isinstance(checks, list) and checks and all(isinstance(row, list) and row and
            all(isinstance(x, str) and x for x in row) for row in checks), "No trusted checks configured")
    # One read-only reconciliation is allowed after a lost response, never another create.
    cli = config["bot_cli"]
    api_env = {k: v for k, v in os.environ.items() if k not in ("GH_TOKEN", "GITHUB_TOKEN", "GH_ENTERPRISE_TOKEN", "GITHUB_ENTERPRISE_TOKEN")}
    def bot(*args):
        return run(cli, *args, env=api_env)
    if not (state.get("url") or state.get("creating")):
        require(not state.get("blocked"), "This assignment is blocked; report the failure")
        state["blocked"] = True
        record(path, state)
    who = bot("api", "--hostname", "github.com", "user", "--jq", ".login").decode().strip()
    require(who.casefold() == a.actor.casefold() == config["account"].casefold(), "Wrong publishing account")
    def existing():
        rows = json.loads(bot("pr", "list", "-R", a.repo, "--head", state["branch"], "--state", "all",
                              "--json", "url,author,isCrossRepository,headRefOid,baseRefName"))
        rows = [p for p in rows if not p["isCrossRepository"]]
        require(len(rows) <= 1 and all(p["author"]["login"].casefold() == who.casefold() for p in rows),
                "Foreign or ambiguous PR; stop")
        if rows and state.get("head"):
            require(rows[0]["headRefOid"] == state["head"] and rows[0]["baseRefName"] == config["base_branch"],
                    "Published revision changed; stop")
        return rows[0]["url"] if rows else None
    if state.get("url") or state.get("creating"):
        url = existing()
        require(url and (not state.get("url") or url == state["url"]), "Publication uncertain; human review required")
        state.update(url=url, blocked=False)
        record(path, state)
        return url
    require(not existing(), "PR already exists outside this publisher")
    # Stop collecting changes before validation. This patch, not a writable worker
    # directory, is the input to both the clean check container and the publisher.
    docker(name, "git", "add", "-A")
    diff = docker(name, "git", "diff", "--no-ext-diff", "--no-textconv", "--cached", "--binary", state["seed"], cap=4_000_000)
    require(0 < len(diff) <= 4_000_000, "Empty or oversized change")
    for line in diff.splitlines():
        if line.startswith((b"old mode ", b"new mode ", b"new file mode ", b"deleted file mode ")):
            require(line.rsplit(b" ", 1)[1] in (b"100644", b"100755"), "Special file needs manual review")
        require(line != b"GIT binary patch", "Binary change needs manual review")
    check = name + "-check"
    start(check, image, a.assignment)
    try:
        seed(check, tree, state["branch"])
        docker(check, "git", "apply", "--index", "-", data=diff)
        for cmd in checks:
            stages = selected_checks(config, a.repo, state["base"], check) if config.get("quality_dir") else []
            docker(check, *cmd, *stages, limit=1800, cap=64000, tail=True)
    finally:
        remove(check, a.assignment)
    require(run("git", "rev-parse", "HEAD").decode().strip() == state["base"] and
            not run("git", "status", "--porcelain") and
            run("git", "branch", "--show-current").decode().strip() == state["branch"], "Host checkout changed")
    # No checkout hooks, filters, shell or repository commands from the patch run
    # on the host. Apply to a temporary index and construct the commit directly.
    with tempfile.TemporaryDirectory() as tmp:
        env = {k:v for k,v in api_env.items() if not k.startswith("GIT_")}
        env.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1", GIT_TERMINAL_PROMPT="0", GIT_INDEX_FILE=str(Path(tmp)/"index"), GIT_AUTHOR_NAME=who,
                   GIT_COMMITTER_NAME=who, GIT_AUTHOR_EMAIL=config["email"], GIT_COMMITTER_EMAIL=config["email"])
        def git(*args, data=None):
            return run("git", "-c", "core.hooksPath=/dev/null", *args, env=env, data=data)
        git("read-tree", state["base"])
        git("apply", "--cached", "--binary", "-", data=diff)
        commit = git("commit-tree", git("write-tree").strip().decode(), "-p", state["base"],
                     data=(title + "\n").encode()).decode().strip()
        # The ticket may have pushed the blocked commit on a previous assignment.
        # Accept a fast-forward only; never force a remote branch.
        git("-c", "credential.helper=", "-c", "credential.helper=!" + shlex.quote(cli) + " auth git-credential", "push", "--no-verify", "https://github.com/" + a.repo + ".git", commit + ":refs/heads/" + state["branch"])
    state.update(creating=True, head=commit)
    record(path, state)
    url = bot("pr", "create", "-R", a.repo, "--base", config["base_branch"], "--head", state["branch"],
              "--title", title, "--body", body + "\n\nCloses #" + a.issue).decode().strip()
    require(url == existing(), "Created PR was not confirmed")
    state.update(url=url, blocked=False)
    record(path, state)
    return url


def main():
    parser = argparse.ArgumentParser()
    for key in ("state", "repo", "actor", "assignment", "issue"):
        parser.add_argument("--" + key, required=True)
    parser.add_argument("operation", choices=["work", "publish", "cleanup"])
    a = parser.parse_args()
    require(re.fullmatch("[a-f0-9]{32}", a.assignment) and re.fullmatch("[1-9][0-9]*", a.issue), "Invalid ticket")
    root = Path(a.state).resolve()
    config_path = root/"container-worker.json"
    info = config_path.lstat()
    require(stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid() and not info.st_mode & 0o022,
            "Unsafe publisher configuration")
    config = json.loads(config_path.read_text())
    # The bot login wrapper resolves gh by name. Never recurse through worker
    # shims or let an assignment select the binaries used by this broker.
    dirs = config["tool_dirs"]
    require(isinstance(dirs, list) and dirs and all(Path(d).is_absolute() and
            not str(Path(d).resolve()).startswith(str(root) + os.sep) for d in dirs), "Invalid broker PATH")
    os.environ["PATH"] = os.pathsep.join(dirs)
    image = config["image"]
    require(re.fullmatch("sha256:[a-f0-9]{64}", image) and config["repo"] == a.repo and
            re.fullmatch(r"[\w.-]+/[\w.-]+", a.repo) and config["account"] == a.actor and
            Path(config["bot_cli"]).is_absolute(), "Invalid profile binding")
    receipt = Path(run("git", "rev-parse", "--absolute-git-dir").decode().strip())/"superboard-assignment.json"
    meta = json.loads(receipt.read_text())
    require(meta["assignment"] == a.assignment and meta["repo"] == a.repo and
            Path.cwd().resolve().parent == root/"work", "Not the assigned worktree")
    name = "superboard-task-" + a.assignment
    records = root/"container-publications"
    records.mkdir(mode=0o700, exist_ok=True)
    path = records/(a.assignment+".json")
    with path.with_suffix(".lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        state = json.loads(path.read_text()) if path.exists() else {}
        if a.operation == "cleanup":
            remove(name, a.assignment)
            remove(name+"-check", a.assignment)
            return
        base = state.get("base") or run("git", "rev-parse", "HEAD").decode().strip()
        tree = run("git", "archive", base)
        if state:
            require(state.get("image") == image, "Image changed during assignment")
        if not state:
            require(not meta.get("blocked"), "Previous publisher blocked this assignment; request a fresh assignment")
            branch = meta["branch"]
            require(run("git", "branch", "--show-current").decode().strip() == branch, "Wrong branch")
            start(name, image, a.assignment)
            try:
                state = dict(branch=branch, base=base, image=image, seed=seed(name, tree, branch))
                record(path, state)
            except BaseException:
                remove(name, a.assignment)
                raise
        request = json.load(sys.stdin)
        if a.operation == "publish":
            try:
                print(publish(a, state, path, config, name, image, tree, request["title"], request["body"]))
            finally:
                remove(name, a.assignment)
        else:
            require(not state.get("blocked") and not state.get("url"), "Assignment stopped; report its outcome")
            cmd = request["command"]
            require(isinstance(cmd, str) and 0 < len(cmd) <= 32768, "Invalid command")
            print(docker(name, "/bin/sh", "-c", cmd, limit=100, cap=16000, tail=True).decode(errors="replace"))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        sys.exit("Container publication: " + str(exc))
