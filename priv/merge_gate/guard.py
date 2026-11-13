#!/usr/bin/env python3
"""Entry point for the worker's gh. Only 'pr merge' is replaced."""
import argparse
import base64
import concurrent.futures
import fcntl
import json
import os
from pathlib import Path
import re
import queue
import shlex
import subprocess
import sys
import stat
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
import task_stages

POLICY = ".github/superboard-merge.json"
SLUG = re.compile(r"[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+")
SHA = re.compile(r"[0-9a-f]{40}")


class Blocked(Exception):
    pass


def run(args):
    return subprocess.check_output(args, text=True, timeout=30).strip()


def launcher_text(slug, delegate):
    return "#!/bin/sh\nexec " + shlex.join(
        ["python3", str(Path(__file__).resolve()), "worker", slug, delegate]) + ' "$@"\n'


def installed(folder, slug, worker):
    launcher = Path(folder).resolve() / "gh"
    delegate = json.loads((launcher.parent / "superboard-delegate.json").read_text())["cli"]
    # dsh generates this wrapper when it applies the source configuration.
    # Read the executable handoff; never run either wrapper to inspect it.
    worker = Path(worker)
    lines = worker.read_text().splitlines() if worker.is_file() and os.access(worker, os.X_OK) else []
    try:
        handoff = shlex.split(lines[-1]) if lines else []
    except ValueError:
        return False
    return (handoff == ["exec", str(launcher), "$@"] and launcher.is_file() and os.access(launcher, os.X_OK) and
            isinstance(delegate, str) and os.path.isabs(delegate) and os.access(delegate, os.X_OK) and
            launcher.read_text() == launcher_text(slug, delegate))


def install(folder, slug, delegate):
    if not SLUG.fullmatch(slug) or any(x in (".", "..") for x in slug.split("/")):
        raise Blocked("Invalid repository")
    # A cloned profile may already use our launcher. Preserve its actual identity.
    prior = Path(delegate).parent / "superboard-delegate.json"
    if Path(delegate).name == "gh" and prior.is_file():
        delegate = json.loads(prior.read_text())["cli"]
    folder = Path(folder).resolve()
    folder.mkdir(mode=0o700, parents=True, exist_ok=True)
    if not os.path.isabs(delegate):
        import shutil
        delegate = shutil.which(delegate) or ""
    if not delegate:
        raise Blocked("Missing GitHub CLI")
    (folder / "superboard-delegate.json").write_text(json.dumps({"cli": delegate}))
    launcher = folder / "gh"
    launcher.write_text(launcher_text(slug, delegate))
    launcher.chmod(0o755)
    return launcher


def policy(data):
    if not isinstance(data, dict) or set(data) != {"method", "review", "local", "github"}:
        raise Blocked("Invalid project merge policy")
    if data["method"] not in ("squash", "merge", "rebase") or type(data["review"]) is not bool:
        raise Blocked("Invalid merge method or review requirement")
    local, remote = data["local"], data["github"]
    if not isinstance(local, dict) or not isinstance(remote, list) or not (local or remote):
        raise Blocked("Project has no required checks")
    for name, argv in local.items():
        if not isinstance(name, str) or not name or not isinstance(argv, list) or not argv or not all(isinstance(a, str) and a for a in argv):
            raise Blocked("Invalid local check")
    if not all(isinstance(x, str) and x.count("/") == 1 and all(x.split("/")) for x in remote) or len(set(remote)) != len(remote):
        raise Blocked("GitHub checks must name app/check")
    return data


def machine_policy(repo):
    if not SLUG.fullmatch(repo) or repo.split("/")[1] in (".", ".."):
        raise Blocked("Invalid repository")
    owner, name = repo.lower().split("/")
    root = Path.home() / ".config" / "superboard" / "quality"
    path = root / owner / (name + ".json")
    # Never follow policy links into a proposed checkout.
    for entry in [root.parent.parent, root.parent, root, path.parent, path]:
        meta = entry.lstat()
        if (meta.st_uid != os.getuid() or meta.st_mode & 0o022 or
                not (stat.S_ISREG(meta.st_mode) if entry == path else stat.S_ISDIR(meta.st_mode))):
            raise Blocked("Invalid machine policy permissions")
    if meta.st_size > 65536:
        raise Blocked("Invalid machine policy size")
    config = policy(json.loads(path.read_bytes()))
    if not config["local"]:
        raise Blocked("Machine policy requires local checks")
    return config


def check_states(required, runs, sha):
    result = {}
    for name in required:
        matches = [r for r in runs if r.get("head_sha") == sha and
                   (r.get("app") or {}).get("slug", "") + "/" + r.get("name", "") == name]
        # Different workflows can reuse a job name. An ambiguous result isn't evidence.
        if not matches:
            state = "missing"
        elif len(matches) != 1:
            state = "ambiguous"
        else:
            r = matches[0]
            state = {"in_progress": "running", "queued": "queued"}.get(r["status"], "pending")
            if r["status"] == "completed":
                state = "passed" if r.get("conclusion") == "success" else "failed"
        result[name] = state
    return result


class Merge:
    def __init__(self, cli, repo, number, expected, directory):
        self.cli, self.repo, self.number, self.expected = cli, repo, number, expected
        self.file = directory / (str(number) + ".json")
        self.snapshot = dict(repo=repo, pr=number, head=expected, state="checking", checks=[])

    def save(self, **changes):
        self.snapshot.update(changes, observed_at=int(time.time()))
        tmp = self.file.with_suffix(".tmp")
        tmp.write_text(json.dumps(self.snapshot))
        tmp.replace(self.file)

    def api(self, path):
        return json.loads(run([self.cli, "api", path]))

    def info(self):
        fields = "headRefOid,baseRefOid,baseRefName,headRefName,isCrossRepository,state,isDraft,author,reviewDecision,mergeable,mergeStateStatus"
        return json.loads(run([self.cli, "pr", "view", str(self.number), "-R", self.repo, "--json", fields]))

    def verify(self, info, owner, base):
        if info["headRefOid"] != self.expected or info["baseRefOid"] != base:
            raise Blocked("revision_changed")
        if (info["state"] != "OPEN" or info["isDraft"] or info["isCrossRepository"] or
                info["author"]["login"].casefold() != owner.casefold() or
                run(["git", "branch", "--show-current"]) != info["headRefName"]):
            raise Blocked("not_current_worker_pr")
        if run(["git", "rev-parse", "HEAD"]) != self.expected or run(["git", "status", "--porcelain"]):
            raise Blocked("worktree_changed")


    def remote(self, config):
        names = config["github"]
        if not names:
            return {}
        path = f"repos/{self.repo}/commits/{self.expected}/check-runs?per_page=100&filter=latest"
        pages = json.loads(run([self.cli, "api", "--paginate", "--slurp", path]))
        return check_states(names, [r for page in pages for r in page["check_runs"]], self.expected)

    def configuration(self, base, stages):
        try:
            item = self.api(f"repos/{self.repo}/contents/{POLICY}?ref={base}")
        except subprocess.CalledProcessError as exc:
            # An API error alone is not evidence of an absent base policy.
            if not SHA.fullmatch(base) or run(["git", "--no-replace-objects", "ls-tree",
                                               "--full-tree", base, "--", POLICY]):
                raise Blocked("policy_unavailable") from exc
            try:
                return "machine", machine_policy(self.repo)
            except FileNotFoundError as missing:
                if stages:
                    # No existing policy: the panel supplies local checks, never
                    # blanket authorization to merge without independent review.
                    return "panel", dict(method="squash", review=True, github=[], local={})
                raise Blocked("policy_unavailable") from missing
        return "repository", policy(json.loads(base64.b64decode(item["content"])))

    def optional_ci_unavailable(self):
        # UNSTABLE can also mean a real test failure. Only excuse a failed
        # Actions job if GitHub confirms it never ran and explains why.
        path = f"repos/{self.repo}"
        statuses = self.api(f"{path}/commits/{self.expected}/status")
        if statuses["total_count"] and statuses["state"] != "success":
            return False
        pages = json.loads(run([self.cli, "api", "--paginate", "--slurp",
                                f"{path}/commits/{self.expected}/check-runs?per_page=100&filter=latest"]))
        unavailable = False
        for page in pages:
            for check in page["check_runs"]:
                if check["head_sha"] != self.expected or check["status"] != "completed":
                    return False
                outcome = check["conclusion"]
                if outcome in ("success", "neutral", "skipped"):
                    continue
                if check["app"]["id"] != 15368:  # GitHub Actions
                    return False
                if outcome == "startup_failure":
                    unavailable = True
                    continue
                if outcome != "failure":
                    return False
                job = self.api(f"{path}/actions/jobs/{int(check['id'])}")
                if job["head_sha"] != self.expected or job["steps"] != []:
                    return False
                annotations = self.api(f"{path}/check-runs/{int(check['id'])}/annotations")
                if not any("job was not started" in a["message"].lower() and
                           any(x in a["message"].lower() for x in ("payments", "spending limit", "billing"))
                           for a in annotations):
                    return False
                unavailable = True
        return unavailable

    def deliver(self):
        info = self.info()
        base = info["baseRefOid"]
        owner = self.api("user")["login"]
        self.verify(info, owner, base)
        stages = task_stages.plan(self.repo, base)
        selection = task_stages.stored(self.repo)
        required = [i for i in stages if stages[i] not in ("disabled", "unrelated")]
        source, config = self.configuration(base, required)
        rows = self.snapshot["checks"]
        project_rows = {i: dict(name=" ".join(task_stages.CATALOG[i]), source="local", state="queued" if i in required else "skipped", reason=stages[i]) for i in stages}
        rows.extend(project_rows.values())
        local = config["local"]
        rows.extend(dict(name=k, source="local", state="queued") for k in local)
        local_end = len(rows)
        remote = self.remote(config)
        rows.extend(dict(name=k, source="github", state=v) for k, v in remote.items())
        self.save(review=info["reviewDecision"] or "NONE", review_required=config["review"], policy_source=source)

        def project_progress(stage, state):
            project_rows[stage]["state"] = "failed" if state == "interrupted" else state
            self.save()

        if stages:
            try:
                task_stages.execute(self.repo, stages, project_progress)
            except (OSError, ValueError, subprocess.SubprocessError) as exc:
                raise Blocked("project_stages_failed") from exc

        def refresh_remote():
            current = self.remote(config)
            for row in rows[local_end:]:
                row["state"] = current[row["name"]]
            self.save()

        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            events = queue.Queue()

            def execute(name, argv):
                events.put((name, "running"))
                try:
                    ok = subprocess.run(argv, stdin=subprocess.DEVNULL, timeout=1800).returncode == 0
                except (OSError, subprocess.TimeoutExpired):
                    ok = False
                events.put((name, "passed" if ok else "failed"))

            by_name = {row["name"]: row for row in rows[len(stages):local_end]}
            for name, argv in local.items():
                pool.submit(execute, name, argv)
            remaining = 2 * len(local)
            while remaining:
                try:
                    name, state = events.get(timeout=15)
                except queue.Empty:
                    refresh_remote()
                    continue
                remaining -= 1
                by_name[name]["state"] = state
                self.save()
        # Keep short hosted runs visible even after the local commands finish.
        until = time.monotonic() + 120
        while (all(row["state"] in ("passed", "skipped") for row in rows[:local_end])
               and any(row["state"] in ("running", "queued", "pending") for row in rows[local_end:])
               and time.monotonic() < until):
            time.sleep(5)
            refresh_remote()
        # Refetch at the decision. The hosted service still enforces branch rules.
        info = self.info()
        self.verify(info, owner, base)
        if task_stages.stored(self.repo) != selection or task_stages.plan(self.repo, base) != stages or (source != "repository" and
                self.configuration(base, required) != (source, config)):
            raise Blocked("policy_changed")
        remote = self.remote(config)
        for row in rows[local_end:]:
            row["state"] = remote[row["name"]]
        self.save(review=info["reviewDecision"] or "NONE")
        if any(r["state"] != "passed" for r in rows if r.get("reason") not in ("unrelated", "disabled")):
            raise Blocked("checks_outstanding")
        reviews = json.loads(run([self.cli, "api", "--paginate", "--slurp",
                                 f"repos/{self.repo}/pulls/{self.number}/reviews?per_page=100"]))
        latest = {}
        for review in sorted((r for page in reviews for r in page), key=lambda r: r["id"]):
            if review["state"] in ("APPROVED", "CHANGES_REQUESTED", "DISMISSED"):
                latest[review["user"]["login"].casefold()] = review
        approved = any(r["state"] == "APPROVED" and r["commit_id"] == self.expected
                       and login != owner.casefold() for login, r in latest.items())
        if (info["reviewDecision"] in ("CHANGES_REQUESTED", "REVIEW_REQUIRED")
                or any(r["state"] == "CHANGES_REQUESTED" for r in latest.values())
                or (config["review"] and not approved)):
            raise Blocked("review_required")
        state = info["mergeStateStatus"]
        if info["mergeable"] != "MERGEABLE" or not (
                state in ("CLEAN", "HAS_HOOKS") or
                (state == "UNSTABLE" and not config["github"] and self.optional_ci_unavailable())):
            raise Blocked("github_blocks_merge")
        self.save(state="merging", review="APPROVED" if approved else info["reviewDecision"] or "NONE")
        subprocess.run([self.cli, "pr", "merge", str(self.number), "-R", self.repo,
                        "--" + config["method"], "--match-head-commit", self.expected], check=True)
        self.save(state="merged")


def worker(repo, cli, args):
    # The Harness assignment guard expects the command before repository options.
    if args[:2] != ["pr", "create"] and "create" in args:
        command = []
        flags = iter(args)
        for flag in flags:
            if flag in ("-R", "--repo"):
                next(flags, None)
            elif not flag.startswith(("-R", "--repo=")):
                command.append(flag)
            if len(command) == 2:
                break
        if command == ["pr", "create"]:
            raise Blocked("Use gh pr create with repository options after create")
    if "merge" in args and "pr" in args and args[:2] != ["pr", "merge"]:
        raise Blocked("Use gh pr merge NUMBER --match-head-commit SHA")
    if args[:2] == ["pr", "create"]:
        task_stages.execute(repo, task_stages.plan(repo))
    if args[:2] != ["pr", "merge"]:
        os.execvp(cli, [cli, *args])
    parser = argparse.ArgumentParser(allow_abbrev=False)
    parser.add_argument("number", type=int)
    parser.add_argument("--match-head-commit", required=True)
    parser.add_argument("--repo", "-R", default=repo)
    method = parser.add_mutually_exclusive_group()
    for flag in ("squash", "merge", "rebase"):
        method.add_argument("--" + flag, action="store_true")
    a = parser.parse_args(args[2:])
    if a.repo.casefold() != repo.casefold() or a.number < 1 or not SHA.fullmatch(a.match_head_commit):
        raise Blocked("Use this repository, a PR number and the full verified head SHA")
    root = Path(os.environ.get("SUPERBOARD_GATE_DIR", Path.home() / ".local/state/superboard/merge"))
    directory = root / repo.lower()
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    merge = Merge(cli, repo, a.number, a.match_head_commit, directory)
    with merge.file.with_suffix(".lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        merge.save()
        try:
            merge.deliver()
        except Exception as exc:
            reason = str(exc) if isinstance(exc, Blocked) else "verification_unavailable"
            merge.save(state="blocked", reason=reason)
            raise


if __name__ == "__main__":
    try:
        if sys.argv[1] == "install":
            print(install(*sys.argv[2:]))
        elif sys.argv[1] in ("describe", "describe-local"):
            if sys.argv[1] == "describe-local":
                try:
                    config = machine_policy(sys.argv[2])
                except FileNotFoundError:
                    sys.exit(3)
            else:
                config = policy(json.loads(base64.b64decode(os.environ["SUPERBOARD_POLICY_CONTENT"])))
            print(json.dumps({"review": config["review"], "local": sorted(config["local"]),
                              "github": config["github"]}))
        elif sys.argv[1] == "installed":
            sys.exit(0 if installed(*sys.argv[2:]) else 1)
        elif sys.argv[1] == "worker":
            worker(sys.argv[2], sys.argv[3], sys.argv[4:])
        else:
            sys.exit("Expected install or worker")
    except (Blocked, OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        sys.exit(f"Merge gate: {error}")
