import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HELPER = Path(__file__).resolve().parents[2] / "priv/agent/superboard-branch.py"


class AssignmentBranch(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.name = "example-123abc"
        self.w = root / self.name
        self.w.mkdir()
        self.env = dict(os.environ, GIT_CONFIG_GLOBAL=str(root / "gitconfig"), GIT_CONFIG_NOSYSTEM="1")
        self.run_cmd("git", "init", "-b", "main")
        self.run_cmd("git", "-c", "user.name=Test", "-c", "user.email=test@example.org", "commit", "--allow-empty", "-m", "initial")
        self.run_cmd("git", "config", "--global", f"url.{self.w.as_uri()}.insteadOf", "https://github.com/org/demo.git")
        self.run_cmd("git", "switch", "-c", "agent/" + self.name)
        self.cli = root / "gh"
        self.cli.write_text("""#!/bin/sh
if [ "$2" = list ]; then echo '[]'; exit; fi
echo "Local checks passed"
echo create >> publishes
echo https://github.com/org/demo/pull/7
""")
        self.cli.chmod(0o755)

    def run_cmd(self, *args, ok=True):
        r = subprocess.run(args, cwd=self.w, env=self.env, text=True, capture_output=True)
        self.assertEqual(r.returncode == 0, ok, r.stderr)
        return r.stdout.strip()

    def helper(self, *args, ok=True):
        return self.run_cmd(sys.executable, str(HELPER), *args, ok=ok)

    def test_reopened_checkout_is_prepared_before_publication_and_retries_reuse_pr(self):
        self.helper("prepare", "org/demo", self.name, "a"*32, "keep")
        pending = self.w / "notes"
        pending.write_text("local edits")
        self.helper("prepare", "org/demo", self.name, "b"*32, "new", ok=False)
        self.assertEqual(pending.read_text(), "local edits")
        pending.unlink()
        expected = "agent/run-" + "b"*32 + "/" + self.name
        self.assertEqual(self.helper("prepare", "org/demo", self.name, "b"*32, "new"), expected)
        self.assertEqual(self.run_cmd("git", "branch", "--show-current"), expected)
        self.helper("create", str(self.cli), "pr", "create", "--head", "wrong", ok=False)
        self.assertFalse((self.w / "publishes").exists())
        self.assertEqual(self.helper("prepare", "org/demo", self.name, "b"*32, "new"), expected)
        url = self.helper("create", str(self.cli), "pr", "create")
        self.assertEqual(url, "https://github.com/org/demo/pull/7")
        self.assertEqual(self.helper("create", str(self.cli), "pr", "create"), url)
        self.assertEqual((self.w / "publishes").read_text(), "create\n")
