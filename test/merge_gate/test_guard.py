import base64
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("guard", ROOT / "priv/merge_gate/guard.py")
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class Delivery(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.folder = Path(tmp.name)
        self.sha = "1" * 40
        self.cfg = dict(method="squash", review=False, local={"Rust": [sys.executable, "-c", "pass"]}, github=["ci/unit"])
        self.info = dict(headRefOid=self.sha, baseRefOid="2" * 40, headRefName="ticket", state="OPEN",
                         isDraft=False, isCrossRepository=False, author={"login":"worker"},
                         reviewDecision="", mergeable="MERGEABLE", mergeStateStatus="CLEAN")
        self.runs = [{"head_sha":self.sha, "app":{"slug":"ci"}, "name":"unit","status":"completed","conclusion":"success"}]
        self.reviews = []
        self.merge = guard.Merge("gh", "org/repo", 42, self.sha, self.folder)
        self.merges = []
        self.reads = []
        def output(args):
            self.reads.append(args)
            if args[0] == "git":
                return {"branch":"ticket","rev-parse":self.sha,"status":""}[args[1]]
            if args[1:3] == ["pr","view"]:
                return json.dumps(self.info)
            if args[-1] == "user":
                return '{"login":"worker"}'
            if "/contents/" in args[-1]:
                self.assertIn(self.info["baseRefOid"], args[-1])
                return json.dumps({"content":base64.b64encode(json.dumps(self.cfg).encode()).decode()})
            if "/reviews?" in args[-1]:
                return json.dumps([self.reviews])
            return json.dumps([{"check_runs":self.runs}])
        real_run = subprocess.run
        def execute(args, **kw):
            if args[:3] == ["gh","pr","merge"]:
                self.merges.append(args)
                return
            return real_run(args, **kw)
        self.enter = patch.object(guard, "run", side_effect=output)
        self.enter.start()
        self.addCleanup(self.enter.stop)
        self.proc = patch.object(subprocess, "run", side_effect=execute)
        self.proc.start()
        self.addCleanup(self.proc.stop)

    def test_installed_checks_actual_launcher_and_repository(self):
        launcher = guard.install(self.folder, "org/repo", sys.executable)
        worker = self.folder / "worker-gh"
        self.assertFalse(guard.installed(self.folder, "org/repo", worker))
        worker.write_text(f"#!/bin/sh\nexec '{launcher}' \"$@\"\n")
        worker.chmod(0o700)
        self.assertTrue(guard.installed(self.folder, "org/repo", worker))
        self.assertFalse(guard.installed(self.folder, "org/other", worker))
        launcher.write_text("#!/bin/sh\nexit 0\n")
        self.assertFalse(guard.installed(self.folder, "org/repo", worker))

    def test_pass_and_atomic_head(self):
        self.merge.deliver()
        self.assertEqual(self.merges[0][-3:], ["--squash","--match-head-commit",self.sha])
        self.assertEqual(json.loads(self.merge.file.read_text())["state"], "merged")

    def test_one_failed_local_blocks_other_green(self):
        self.cfg["local"]["JS"] = [sys.executable, "-c", "raise SystemExit(1)"]
        with self.assertRaisesRegex(guard.Blocked, "checks_outstanding"):
            self.merge.deliver()
        self.assertFalse(self.merges)
        self.assertEqual([r["state"] for r in self.merge.snapshot["checks"]], ["passed","failed","passed"])

    def test_stale_hosted_and_review(self):
        self.runs[0]["head_sha"] = "0" * 40
        with self.assertRaisesRegex(guard.Blocked, "checks_outstanding"):
            self.merge.deliver()
        self.runs[0]["head_sha"] = self.sha
        self.cfg["review"] = True
        self.reviews = [dict(id=1,state="APPROVED",user={"login":"alice"},commit_id="0"*40)]
        with self.assertRaisesRegex(guard.Blocked, "review_required"):
            guard.Merge("gh","org/repo",42,self.sha,self.folder).deliver()
        self.assertFalse(self.merges)

    def test_head_advancing_while_tests_run(self):
        with patch.object(self.merge, "info", side_effect=[self.info,dict(self.info,headRefOid="3"*40)]):
            with self.assertRaisesRegex(guard.Blocked,"revision_changed"):
                self.merge.deliver()
        self.assertFalse(self.merges)

    def test_empty_policy(self):
        self.cfg.update(local={},github=[])
        with self.assertRaises(guard.Blocked):
            self.merge.deliver()
        self.assertFalse(self.merges)
