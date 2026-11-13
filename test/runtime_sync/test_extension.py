import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "priv/agent"))
from sync_extension import Binding


class ProfileBinding(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.source = self.root / "source"
        self.source.mkdir()
        self.profile = self.root / "profiles" / "arena"
        modules = self.profile / "node_modules"
        modules.mkdir(parents=True)
        (modules / "dsh-superagent").symlink_to(self.source)
        self.manifest = self.profile / "package.json"
        self.manifest.write_text(json.dumps({"dependencies": {"dsh-superagent": "link:" + str(self.source)},
                                             "dsh": {"profile": {"bundles": ["another", "dsh-superagent"]}}}))
        self.lock = self.profile / "pnpm-lock.yaml"
        self.lock.write_text("      dsh-superagent:\n        specifier: link:" + str(self.source) +
                             "\n        version: link:" + os.path.relpath(self.source, self.profile) + "\n")
        self.target = self.root / "extension"
        self.target.mkdir()

    def test_switch_and_rollback_preserve_other_configuration(self):
        old = self.manifest.read_bytes(), self.lock.read_bytes()
        b = Binding(self.profile)
        b.switch(self.target)
        self.assertEqual(Binding(self.profile).source, self.target)
        self.assertEqual(json.loads(self.manifest.read_bytes())["dsh"]["profile"]["bundles"], ["another", "dsh-superagent"])
        b.restore()
        self.assertEqual(Binding(self.profile).source, self.source)
        self.assertEqual((self.manifest.read_bytes(), self.lock.read_bytes()), old)

    def test_concurrent_edit_aborts_before_mutation(self):
        b = Binding(self.profile)
        self.lock.write_text("new owner edit")
        with self.assertRaisesRegex(ValueError, "profile changed"):
            b.switch(self.target)
        self.assertEqual(b.link.resolve(), self.source)
        self.assertEqual(self.lock.read_text(), "new owner edit")
