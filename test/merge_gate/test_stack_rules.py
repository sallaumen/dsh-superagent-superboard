import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "priv/merge_gate"))
import task_stages as stages
import stack_rules


class StackRules(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.home = Path(tmp.name)
        self.repo = self.home / "project"
        self.repo.mkdir()
        old = os.getcwd()
        os.chdir(self.repo)
        self.addCleanup(os.chdir, old)
        self.enterContext(patch.object(Path, "home", return_value=self.home))
        self.git("init", "-q")
        self.git("remote", "add", "origin", "https://github.com/org/app.git")
        self.write("package.json", json.dumps({"scripts":{"lint":"eslint .","test":"node --test","build":"vite build"}}))
        self.write("old.ts","x")
        self.commit()
        self.git("update-ref","refs/remotes/origin/main","HEAD")

    def git(self,*args):
        return subprocess.check_output(["git", *args], cwd=self.repo).decode().strip()

    def write(self,name,body):
        (self.repo/name).write_text(body)

    def commit(self):
        self.git("add","--",".")
        self.git("-c","user.name=test","-c","user.email=test@example.org","-c","commit.gpgsign=false","commit","-qm","change")

    def test_defaults_and_actual_diff_include_dirty_new_and_old_rename(self):
        self.write("README.md","docs")
        self.assertEqual(stages.plan("org/app"), {"npm-lint":"unrelated","npm-test":"required","npm-build":"unrelated"})
        self.git("mv","old.ts","old.txt")
        self.assertEqual(stages.plan("org/app")["npm-lint"],"matched:*.ts")
        self.git("reset","--hard","HEAD")
        self.write("new.ts","x")
        self.assertEqual(stages.plan("org/app")["npm-build"],"matched:*.ts")
        self.git("update-ref","-d","refs/remotes/origin/main")
        self.assertEqual(stages.plan("org/app")["npm-build"],"unknown_diff")

    def test_disabled_survives_detection_and_base_manifest_removal(self):
        stages.save_rules("org/app",{"npm-test":"off"},None)
        (self.repo/"package.json").unlink()
        self.commit()
        self.assertEqual(stages.plan("org/app")["npm-test"],"disabled")
        self.assertEqual(stages.plan("org/app")["npm-lint"],"matched:package*.json")
        with self.assertRaises(ValueError):
            stages.save_rules("org/app",{"npm-test":"always"},None)

    def test_ten_toolchains_and_no_fabricated_script(self):
        for name, data in [("mix.exs",":credo"),("Cargo.toml",""),("pytest.ini",""),
                           ("composer.json",'{"scripts":{"test":"phpunit"}}'),("go.mod",""),
                           ("Gemfile","gem 'rspec'"),("pom.xml",""),("app.csproj",""),("Package.swift","")]:
            self.write(name,data)
        self.commit()
        ids = stages.profile("org/app", self.repo)["detected"]
        self.assertEqual(len({stack_rules.RULES[i]["stack"] for i in ids}),10)
        self.assertNotIn("npm-e2e",ids)
        self.assertFalse(stages.profile("org/wrong",self.repo)["available"])
