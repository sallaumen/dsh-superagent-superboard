import importlib.util
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("container_worker", Path(__file__).resolve().parents[2]/"priv/agent/container_worker.py")
broker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(broker)


class Publication(unittest.TestCase):
    def test_refuses_unrelated_author_even_if_receipt_already_has_url(self):
        cfg = dict(checks=[["false"]], bot_cli="/test/bot", account="board-bot")
        state = dict(branch="agent/ticket", url="https://github.com/org/repo/pull/7")
        args = SimpleNamespace(actor="board-bot", repo="org/repo", assignment="a"*32)
        replies = [b"board-bot\n", b'[{"isCrossRepository":false,"author":{"login":"owner"},"url":"https://github.com/org/repo/pull/7"}]']
        with patch.object(broker, "run", side_effect=replies) as run:
            with self.assertRaisesRegex(ValueError, "Foreign"):
                broker.publish(args, state, None, cfg, "task", "image", b"", "title", "body")
            self.assertEqual(run.call_count, 2)

    def test_failed_clean_check_cannot_create_or_retry(self):
        args = SimpleNamespace(actor="board-bot", repo="org/repo", assignment="a"*32)
        state = dict(branch="agent/ticket", seed="seed")
        cfg = dict(checks=[["false"]], bot_cli="/test/bot", account="board-bot")
        with tempfile.TemporaryDirectory() as tmp:
            receipt = Path(tmp)/"state.json"
            with patch.object(broker, "run", side_effect=[b"board-bot", b"[]", b"board-bot"]) as run, \
                 patch.object(broker, "start"), patch.object(broker, "seed"), patch.object(broker, "remove") as remove, \
                 patch.object(broker, "docker", side_effect=[b"", b"patch", b"", ValueError("failed check")]):
                with self.assertRaisesRegex(ValueError, "failed check"):
                    broker.publish(args, state, receipt, cfg, "task", "image", b"", "title", "body")
                with self.assertRaisesRegex(ValueError, "blocked"):
                    broker.publish(args, state, receipt, cfg, "task", "image", b"", "title", "body")
                self.assertTrue(state["blocked"])
                self.assertNotIn("create", [x for call in run.call_args_list for x in call.args])
                remove.assert_called_once_with("task-check", args.assignment)

    def test_uncertain_create_only_reconciles_the_same_bot_head(self):
        cfg = dict(checks=[["false"]], bot_cli="/test/bot", account="board-bot", base_branch="main")
        url = "https://github.com/org/repo/pull/7"
        state = dict(branch="agent/ticket", head="a"*40, creating=True, blocked=True)
        args = SimpleNamespace(actor="board-bot", repo="org/repo", assignment="a"*32)
        row = dict(isCrossRepository=False, author=dict(login="board-bot"), url=url,
                   headRefOid=state["head"], baseRefName="main")
        with tempfile.TemporaryDirectory() as tmp, patch.object(broker, "run") as call:
            receipt = Path(tmp)/"result.json"
            for attempt in range(2):
                call.side_effect = [b"board-bot", broker.json.dumps([row]).encode()]
                self.assertEqual(broker.publish(args, state, receipt, cfg, "task", "image", b"", "title", "body"), url)
                self.assertEqual(call.call_args.args[1:3], ("pr", "list"))
            row["headRefOid"] = "b"*40
            call.side_effect = [b"board-bot", broker.json.dumps([row]).encode()]
            with self.assertRaisesRegex(ValueError, "revision changed"):
                broker.publish(args, state, receipt, cfg, "task", "image", b"", "title", "body")

    def test_command_output_has_a_hard_bound(self):
        import sys
        cmd = (sys.executable, "-c", "print('X' * 100000)")
        self.assertEqual(broker.run(*cmd, cap=10, tail=True), b'XXXXXXXXX\n')
        with self.assertRaisesRegex(ValueError, "exceeds"):
            broker.run(*cmd, cap=10)
