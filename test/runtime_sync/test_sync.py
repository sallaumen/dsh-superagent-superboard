import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "priv/agent"))
import sync_runtime as runtime


class Agent:
    profile = "fixture"

    def __init__(self):
        self.paused = False
        self.load = {"running": 0, "queued": 0}
        self.cli = Path("/old/dsh")
        self.restarts = []
        self.selected = None

    def launcher(self):
        return self.cli

    def snapshot(self):
        return {"paused": self.paused, "load": self.load, "health": {"runtime": {"state": "ready"}}}

    def api(self, _, body):
        self.paused = body["paused"]

    def change(self, action, cli):
        assert action == "restart" and self.paused
        self.restarts.append(cli)
        self.cli = cli

    def select(self, cli):
        self.selected = cli


class Synchronization(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        root = patch.object(runtime, "ROOT", Path(directory.name))
        root.start()
        self.addCleanup(root.stop)
        self.target = Path("/new/dsh")
        prepare = patch.object(runtime, "prepare", return_value=self.target)
        self.prepare = prepare.start()
        self.addCleanup(prepare.stop)
        self.agent = Agent()

    def test_restart_only_once_and_keep_selection(self):
        self.assertEqual(runtime.sync(self.agent), "updated")
        self.assertFalse(self.agent.paused)
        self.assertEqual(runtime.sync(self.agent), "current")
        self.assertEqual(self.agent.restarts, [self.target])
        self.assertEqual(self.agent.selected, self.target)

    def test_never_touch_paused_busy_or_unknown_load(self):
        self.agent.paused = True
        self.assertEqual(runtime.sync(self.agent), "paused")
        self.agent.paused = False
        for load in ({"running": 1, "queued": 0}, {"running": 0, "queued": 1}):
            self.agent.load = load
            self.assertEqual(runtime.sync(self.agent), "busy")
        for load in ({}, {"running": False, "queued": 0}, {"running": 0, "queued": -1}):
            self.agent.load = load
            self.assertEqual(runtime.sync(self.agent), "unavailable")
        self.prepare.assert_not_called()
        self.assertEqual(self.agent.restarts, [])

    def test_work_arriving_during_pause_prevents_restart(self):
        def change_pause(_, body):
            self.agent.paused = body["paused"]
            self.agent.load["queued"] = 1

        self.agent.api = change_pause
        self.assertEqual(runtime.sync(self.agent), "busy")
        self.assertFalse(self.agent.paused)
        self.assertEqual(self.agent.restarts, [])

    def test_busy_then_queued_then_idle_applies_the_same_runtime_once(self):
        for running, queued, outcome in ((1, 0, "busy"), (0, 1, "busy"), (0, 0, "updated"), (0, 0, "current")):
            self.agent.load = {"running": running, "queued": queued}
            self.assertEqual(runtime.sync(self.agent), outcome)
            if running or queued:
                self.assertFalse(self.agent.paused)
                self.assertEqual(self.agent.restarts, [])
        self.assertEqual(self.agent.restarts, [self.target])

    def test_process_failure_recovers_previous_launcher_then_resumes(self):
        with patch.object(self.agent, "change", side_effect=RuntimeError), \
             patch.object(self.agent, "recover", create=True) as rollback:
            with self.assertRaises(RuntimeError):
                runtime.sync(self.agent)
            rollback.assert_called_once_with(self.agent.cli, self.target)
        self.assertFalse(self.agent.paused)
        self.assertIsNone(self.agent.selected)

    def test_other_operator_holds_same_profile_lock(self):
        with runtime.lock(runtime.ROOT / "locks" / self.agent.profile):
            with self.assertRaises(BlockingIOError):
                runtime.sync(self.agent)
        self.prepare.assert_not_called()

    def test_foreign_repository_and_state_are_never_operated(self):
        p = runtime.Profile("test", 3199, "fixture/repo", "/unused", "/tmp/test-state")
        for repo, directory in (("fixture/other", "/tmp/test-state"), ("fixture/repo", "/other")):
            with patch.object(p, "api", return_value={"setup": {
                    "accounts": {"repository": repo}, "machine": {"stateDir": directory}}}) as api:
                with self.assertRaisesRegex(runtime.Skip, "identity"):
                    runtime.sync(p)
                api.assert_called_once_with("state")
