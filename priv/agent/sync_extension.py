"""Build an isolated Super Agent package and switch only the selected profile."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

PATCH = Path(__file__).with_name("duplicate-issue-notice.patch")
UPSTREAM = "8c32a9dc5d72c033816c6a8110b37f40cf94fba4"
PACKAGE = "dsh-superagent"


def compiled(path):
    bundle = path / "lib/index.js"
    return bundle.is_file() and b"duplicate-issue-notice" in bundle.read_bytes()


def has_dispatch(profile):
    return any(part.get("key") == "runtime/dispatch" and
               "duplicate_of_ticket_id" in part.get("text", "")
               for part in profile.api("prompts")["parts"])


def replace(path, value):
    with tempfile.TemporaryDirectory(dir=path.parent) as tmp:
        new = Path(tmp) / "new"
        if isinstance(value, bytes):
            new.write_bytes(value)
            new.chmod(path.stat().st_mode & 0o777)
        else:
            new.symlink_to(value)
        new.replace(path)


class Binding:
    def __init__(self, directory):
        self.directory = directory.resolve(strict=True)
        self.link = directory / "node_modules" / PACKAGE
        self.manifest = directory / "package.json"
        self.lockfile = directory / "pnpm-lock.yaml"
        if not self.link.is_symlink() or any(p.is_symlink() for p in (directory, self.manifest, self.lockfile, self.link.parent)):
            raise ValueError("unsupported package binding")
        self.original = os.readlink(self.link)
        self.source = self.link.resolve(strict=True)
        self.before = {self.manifest: self.manifest.read_bytes(), self.lockfile: self.lockfile.read_bytes()}
        self.config = json.loads(self.before[self.manifest])
        spec = self.config["dependencies"][PACKAGE]
        if not spec.startswith("link:") or (directory / spec[5:]).resolve() != self.source:
            raise ValueError("manifest differs from installed package")
        self.spec = spec

    def switch(self, target):
        if os.readlink(self.link) != self.original or any(p.read_bytes() != b for p, b in self.before.items()):
            raise ValueError("profile changed")
        # Change only this importer's package entry, preserving other dependencies.
        old = self.before[self.lockfile].decode()
        block = ("      dsh-superagent:\n        specifier: " + self.spec +
                 "\n        version: link:" + os.path.relpath(self.source, self.directory) + "\n")
        if old.count(block) != 1:
            raise ValueError("unsupported profile lockfile")
        new = ("      dsh-superagent:\n        specifier: link:" + str(target) +
               "\n        version: link:" + os.path.relpath(target, self.directory) + "\n")
        self.config["dependencies"][PACKAGE] = "link:" + str(target)
        try:
            replace(self.lockfile, old.replace(block, new).encode())
            replace(self.manifest, (json.dumps(self.config, indent=2) + "\n").encode())
            replace(self.link, target)
        except Exception:
            self.restore()
            raise

    def restore(self):
        for path, value in self.before.items():
            replace(path, value)
        replace(self.link, self.original)


def prepare(binding, root, manager, run, lock):
    source = binding.source
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    patch = PATCH.read_bytes()
    version = hashlib.sha256(patch).hexdigest()
    receipt = ".superboard-extension"
    if source.parent == root and (source / receipt).is_file() and (source / receipt).read_text() == version and compiled(source):
        return source
    # Only build from the registered manager or previous board-managed checkouts.
    if source != manager.parent.parent.resolve() and source.parent != root:
        raise ValueError("unrecognized prototype location")
    def git(*args):
        return run("git", "-C", str(source), *args)
    if git("rev-parse", "HEAD").strip() != UPSTREAM:
        raise ValueError("unsupported prototype revision")
    if git("ls-files", "--others", "--exclude-standard").strip():
        raise ValueError("untracked prototype files")
    # Preserve tracked local source fixes; never execute locally altered install/build scripts.
    names = git("diff", "--name-only", "HEAD").splitlines()
    if any(not n.startswith(("src/", "tests/", "prompts/")) for n in names):
        raise ValueError("custom prototype build")
    diff = subprocess.check_output(["git", "-C", str(source), "diff", "--binary", "--no-ext-diff", "HEAD"])
    digest = hashlib.sha256(UPSTREAM.encode() + patch + diff).hexdigest()
    dest = root / digest
    with lock(root / ".build.lock"):
        if not dest.exists():
            with tempfile.TemporaryDirectory(dir=root) as tmp:
                stage = Path(tmp) / "package"
                run("git", "clone", "--quiet", "--no-hardlinks", "--no-checkout", str(source), str(stage))
                run("git", "checkout", "--quiet", "--detach", UPSTREAM, cwd=stage)
                if diff:
                    local = Path(tmp) / "local.patch"
                    local.write_bytes(diff)
                    run("git", "apply", str(local), cwd=stage)
                try:
                    run("git", "apply", "--reverse", "--check", str(PATCH), cwd=stage)
                except subprocess.CalledProcessError:
                    run("git", "apply", str(PATCH), cwd=stage)
                env = {k: v for k, v in os.environ.items() if k in ("HOME", "PATH", "TMPDIR", "USER", "LOGNAME")}
                # Do not inherit a service working directory or GitHub credentials.
                run("pnpm", "install", "--frozen-lockfile", cwd=stage, env=env, timeout=420)
                run("pnpm", "build", cwd=stage, env=env, timeout=420)
                if not compiled(stage):
                    raise ValueError("missing compiled notice")
                (stage / receipt).write_text(version)
                stage.rename(dest)
        if not compiled(dest) or (dest / receipt).read_text() != version:
            raise ValueError("invalid extension build")
        return dest
