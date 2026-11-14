import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "priv/agent"))
import sync_runtime as runtime


class Agent:
    profile = "fixture"
    manager = Path("/agent/scripts/dsh-superagent")
    directory = Path("/profiles/fixture")

    def pid(self):
        return 1 + len(self.restarts)

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
        binding = patch.object(runtime.extension, "Binding")
        self.binding = binding.start().return_value
        self.addCleanup(binding.stop)
        self.package = Path("/installed/package")
        self.binding.source = self.package
        self.binding.link.resolve.return_value = self.package
        build = patch.object(runtime.extension, "prepare", return_value=self.package)
        self.build = build.start()
        self.addCleanup(build.stop)
        check = patch.object(runtime.extension, "has_dispatch", return_value=True)
        self.dispatch = check.start()
        self.addCleanup(check.stop)

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

    def test_work_queued_while_checking_a_current_package_remains_pending(self):
        self.agent.cli = self.target

        def check_dispatch(_):
            self.agent.load["queued"] = 1
            return True

        self.dispatch.side_effect = check_dispatch
        self.assertEqual(runtime.sync(self.agent), "busy")
        self.assertIsNone(self.agent.selected)
        self.assertFalse(self.agent.paused)
        self.assertEqual(self.agent.restarts, [])

    def test_current_result_is_not_recorded_for_a_replaced_process(self):
        self.agent.cli = self.target
        with patch.object(self.agent, "pid", side_effect=[1, 2]):
            self.assertEqual(runtime.sync(self.agent), "changed")
        self.assertIsNone(self.agent.selected)

    def test_current_package_changed_on_disk_is_not_selected(self):
        self.agent.cli = self.target
        self.binding.unchanged.return_value = False
        self.assertEqual(runtime.sync(self.agent), "changed")
        self.assertIsNone(self.agent.selected)
        self.assertEqual(self.agent.restarts, [])

    def test_binding_conflict_before_restart_leaves_the_running_agent_alone(self):
        self.agent.cli = self.target
        self.binding.source = Path("/old/package")
        self.binding.switch.side_effect = runtime.extension.ProfileChanged("profile changed")
        with patch.object(self.agent, "recover", create=True) as recover:
            self.assertEqual(runtime.sync(self.agent), "changed")
            recover.assert_not_called()
        self.binding.restore.assert_not_called()
        self.assertFalse(self.agent.paused)
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

    def test_extension_only_change_waits_for_queue_and_shares_one_restart(self):
        self.agent.cli = self.target
        self.binding.source = Path("/old/package")
        for running, queued in ((1, 1), (0, 1)):
            self.agent.load = {"running": running, "queued": queued}
            self.assertEqual(runtime.sync(self.agent), "busy")
        self.build.assert_not_called()
        self.binding.switch.assert_not_called()
        self.agent.load = {"running": 0, "queued": 0}
        self.assertEqual(runtime.sync(self.agent), "updated")
        self.binding.switch.assert_called_once_with(self.package)
        self.binding.source = self.package
        self.assertEqual(runtime.sync(self.agent), "current")
        self.assertEqual(self.agent.restarts, [self.target])

    def test_inactive_extension_after_restart_restores_old_package(self):
        self.binding.source = Path("/old/package")
        self.dispatch.return_value = False
        with patch.object(self.agent, "recover", create=True) as recover:
            with self.assertRaisesRegex(RuntimeError, "handoff failed"):
                runtime.sync(self.agent)
            self.binding.restore.assert_called_once()
            recover.assert_called_once()
        self.assertFalse(self.agent.paused)

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
