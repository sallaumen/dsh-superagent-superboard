#!/usr/bin/env python3
"""Testes do validador da biblioteca de capacidades.

Os testes usam cópias temporárias da biblioteca e verificam apenas o software
auxiliar; não executam as instruções das skills. Execute com:

    python3 capabilities/tools/test_validar_biblioteca.py
"""

from __future__ import annotations

import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
LIBRARY_ROOT = TOOLS_DIR.parent
sys.path.insert(0, str(TOOLS_DIR))

import validar_biblioteca as vb  # noqa: E402


def fresh_copy() -> Path:
    tmp = Path(tempfile.mkdtemp(prefix="bib-test-"))
    shutil.copytree(LIBRARY_ROOT, tmp / "lib")
    return tmp / "lib"


def skill_file(root: Path, name: str) -> Path:
    return root / "skills" / name / "SKILL.md"


def mutate_skill(root: Path, name: str, old: str, new: str) -> None:
    path = skill_file(root, name)
    path.write_text(path.read_text(encoding="utf-8").replace(old, new), encoding="utf-8")


class ValidatorTests(unittest.TestCase):
    def test_valid_library_passes(self) -> None:
        root = fresh_copy()
        report = vb.validate(root)
        self.assertTrue(report["ok"], report["errors"])
        self.assertEqual(report["skills"], 32)
        self.assertEqual(report["contexts"], 6)

    def test_manifest_divergence_detected(self) -> None:
        root = fresh_copy()
        mutate_skill(root, "code-review", 'category: "qualidade"', 'category: "operacao"')
        report = vb.validate(root)
        self.assertFalse(report["ok"])
        self.assertTrue(any("diverge em category" in e for e in report["errors"]))

    def test_missing_frontmatter_key_detected(self) -> None:
        root = fresh_copy()
        mutate_skill(root, "code-review", 'related: [', 'norel: [')
        report = vb.validate(root)
        self.assertFalse(report["ok"])

    def test_unknown_related_detected(self) -> None:
        root = fresh_copy()
        mutate_skill(root, "code-review", '"investigar-bugs"', '"nao-existe"')
        report = vb.validate(root)
        self.assertTrue(any("skill inexistente" in e for e in report["errors"]))

    def test_self_related_detected(self) -> None:
        root = fresh_copy()
        mutate_skill(root, "code-review", '"investigar-bugs"', '"code-review"')
        report = vb.validate(root)
        self.assertTrue(any("referencia a própria skill" in e for e in report["errors"]))

    def test_incomplete_origin_coverage_detected(self) -> None:
        root = fresh_copy()
        mutate_skill(root, "code-review", 'origem: ["P27"]', 'origem: []')
        report = vb.validate(root)
        self.assertTrue(any("P27" in e and "sem destino" in e for e in report["errors"]))

    def test_duplicate_origin_detected(self) -> None:
        root = fresh_copy()
        mutate_skill(root, "code-review", 'origem: ["P27"]', 'origem: ["P27", "P28"]')
        report = vb.validate(root)
        self.assertTrue(any("P28" in e and "destino duplicado" in e for e in report["errors"]))

    def test_duplicate_name_detected(self) -> None:
        root = fresh_copy()
        other = skill_file(root, "investigar-bugs")
        other.write_text(other.read_text(encoding="utf-8").replace('name: "investigar-bugs"', 'name: "code-review"'), encoding="utf-8")
        report = vb.validate(root)
        self.assertTrue(any("Skill duplicada" in e for e in report["errors"]))

    def test_context_cycle_detected(self) -> None:
        root = fresh_copy()
        manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
        for item in manifest["contexts"]:
            if item["id"] == "colmex-base":
                item["requires"] = ["colmex-casas"]
        (root / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
        report = vb.validate(root)
        self.assertTrue(any("Dependência cíclica" in e for e in report["errors"]))

    def test_unknown_context_dependency_detected(self) -> None:
        root = fresh_copy()
        manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
        for item in manifest["contexts"]:
            if item["id"] == "forro-mobile":
                item["requires"] = ["nao-existe"]
        (root / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
        report = vb.validate(root)
        self.assertTrue(any("Contexto desconhecido" in e for e in report["errors"]))

    def test_broken_local_link_detected(self) -> None:
        root = fresh_copy()
        mutate_skill(root, "code-review", "../../parametros.md", "../../parametros-ausente.md")
        report = vb.validate(root)
        self.assertTrue(any("Link local inválido" in e for e in report["errors"]))

    def test_path_escape_rejected(self) -> None:
        root = fresh_copy()
        manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
        manifest["support_files"].append("../AGENTS.md")
        (root / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
        report = vb.validate(root)
        self.assertFalse(report["ok"])
        self.assertTrue(any("fora da biblioteca" in e for e in report["errors"]))

    def test_duplicate_body_detected(self) -> None:
        root = fresh_copy()
        source = skill_file(root, "code-review").read_text(encoding="utf-8")
        skill_file(root, "investigar-bugs").write_text(source.replace('name: "code-review"', 'name: "investigar-bugs"'), encoding="utf-8")
        report = vb.validate(root)
        self.assertTrue(any("Corpos duplicados" in e for e in report["errors"]))

    def test_invalid_mode_detected(self) -> None:
        root = fresh_copy()
        mutate_skill(root, "code-review", 'default_mode: "revisar"', 'default_mode: "consertar"')
        report = vb.validate(root)
        self.assertTrue(any("modo padrão inválido" in e for e in report["errors"]))

    def test_json_report_parses(self) -> None:
        root = fresh_copy()
        report = vb.validate(root)
        payload = json.dumps(report, ensure_ascii=False)
        self.assertIn('"ok": true', payload)

    def test_instruction_heading_required(self) -> None:
        root = fresh_copy()
        mutate_skill(root, "code-review", "## Instrução", "## Procedimento")
        report = vb.validate(root)
        self.assertTrue(any("instrução ausente" in e for e in report["errors"]))


if __name__ == "__main__":
    unittest.main(verbosity=2)
