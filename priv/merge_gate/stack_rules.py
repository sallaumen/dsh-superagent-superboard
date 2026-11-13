"""Inspect Git objects without executing project code. Root-level toolchains only."""
import fnmatch
import json
import os
from pathlib import Path
import re
import subprocess

RULES = json.loads(Path(__file__).with_name("stack-rules.json").read_text())


def git(folder, *args):
    return subprocess.check_output(["git", "--no-replace-objects", "-C", str(folder), *args],
                                   stderr=subprocess.DEVNULL, timeout=15)


def checkout(repo, folder):
    if not folder or not Path(folder).is_dir():
        return None
    try:
        origin = git(folder, "remote", "get-url", "origin").decode().strip()
        m = re.fullmatch(r"(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)([^/]+/[^/]+?)(?:\.git)?/?", origin, re.I)
        if m and m[1].casefold() == repo.casefold():
            return os.fsdecode(git(folder, "rev-parse", "--show-toplevel").strip())
    except subprocess.SubprocessError:
        pass
    return None


def base_ref(folder):
    try:
        return git(folder, "symbolic-ref", "refs/remotes/origin/HEAD").decode().strip()
    except subprocess.CalledProcessError:
        return "refs/remotes/origin/main"


def matches(path, patterns):
    return any(fnmatch.fnmatchcase(path, p) or fnmatch.fnmatchcase(path.rsplit("/", 1)[-1], p)
               for p in patterns)


def detect(folder, ref):
    listing = git(folder, "ls-tree", "-z", ref)
    names = set()
    for row in listing.split(b"\0"):
        if row.startswith((b"100644 blob ", b"100755 blob ")):
            names.add(os.fsdecode(row.split(b"\t", 1)[1]))
    cache = {}

    def content(name):
        if name not in cache:
            cache[name] = ""
            if name in names and int(git(folder, "cat-file", "-s", f"{ref}:{name}")) <= 1048576:
                cache[name] = git(folder, "show", f"{ref}:{name}").decode(errors="replace")
        return cache[name]

    ids = []
    for i, rule in RULES.items():
        if not any(matches(name, rule["markers"]) for name in names):
            continue
        if "script" in rule:
            try:
                scripts = json.loads(content(rule["manifest"])).get("scripts", {})
            except (ValueError, AttributeError):
                continue
            if not isinstance(scripts, dict) or not scripts.get(rule["script"]):
                continue
            if "no test specified" in str(scripts[rule["script"]]).lower():
                continue
        if ("contains" in rule and not (i == "pytest" and "pytest.ini" in names)
                and not any(rule["contains"] in content(m) for m in rule["markers"])):
            continue
        ids.append(i)
    return ids


def detected(folder, base=None):
    ids = set(detect(folder, "HEAD"))
    if base:
        ids.update(detect(folder, base))
    return [i for i in RULES if i in ids]


def changed(folder, base):
    try:
        ancestor = git(folder, "merge-base", "HEAD", base or base_ref(folder)).decode().strip()
        tracked = git(folder, "diff", "--name-only", "--no-renames", "-z", ancestor, "--")
        new = git(folder, "ls-files", "--others", "--exclude-standard", "-z")
        return sorted(os.fsdecode(p) for p in (tracked + new).split(b"\0") if p)
    except subprocess.SubprocessError:
        return None


def decide(ids, modes, paths):
    rows = {}
    for i in ids:
        mode = modes[i]
        if mode == "off":
            reason = "disabled"
        elif mode == "always":
            reason = "required"
        elif paths is None:
            reason = "unknown_diff"
        else:
            pattern = next((g for g in RULES[i]["paths"] if any(matches(p, [g]) for p in paths)), None)
            reason = f"matched:{pattern}" if pattern else "unrelated"
        rows[i] = reason
    return rows
