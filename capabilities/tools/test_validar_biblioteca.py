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


MINI_SKILL = """---
name: "%s"
title: "%s"
category: "teste"
default_mode: "analisar"
origem: ["%s"]
related: []
description: "Skill de teste para a biblioteca estrangeira."
---

# %s

## Quando usar

Quando o cenário de teste pedir.

## Instrução

Execute apenas o comportamento descrito no cenário de origem %s.

## Referências

- Contrato comum (obrigatório): [contrato.md](../../contrato.md)
"""


def mini_library(origins: list[str], declared: list[str] | None = None) -> Path:
    """Constrói uma biblioteca mínima com IDs de origem arbitrários."""
    root = Path(tempfile.mkdtemp(prefix="bib-estrangeira-"))
    (root / "contrato.md").write_text("# Contrato\n\nRegras comuns.\n", encoding="utf-8")
    (root / "parametros.md").write_text("# Parâmetros\n\nModos e parâmetros.\n", encoding="utf-8")
    skills = []
    for i, origin_id in enumerate(origins, start=1):
        name = f"skill-{i}"
        (root / "skills" / name).mkdir(parents=True)
        (root / "skills" / name / "SKILL.md").write_text(
            MINI_SKILL % (name, f"Skill {i}", origin_id, f"Skill {i}", origin_id), encoding="utf-8"
        )
        skills.append(
            {"name": name, "title": f"Skill {i}", "category": "teste",
             "default_mode": "analisar", "origem": [origin_id], "related": [],
             "path": f"skills/{name}/SKILL.md"}
        )
    manifest = {
        "schema_version": 2,
        "kind": "capabilities-library",
        "common_contract": "contrato.md",
        "parameters": "parametros.md",
        "skills": skills,
        "contexts": [],
    }
    if declared is not None:
        manifest["origin_ids"] = declared
    (root / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    return root


def skill_file(root: Path, name: str) -> Path:
    return root / "skills" / name / "SKILL.md"


def mutate_skill(root: Path, name: str, old: str, new: str) -> None:
    path = skill_file(root, name)
    path.write_text(path.read_text(encoding="utf-8").replace(old, new), encoding="utf-8")


class ValidatorTests(unittest.TestCase):
    def test_valid_library_passes(self) -> None:
        root = fresh_copy()
        report = vb.validate(root)
        manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
        self.assertTrue(report["ok"], report["errors"])
        self.assertEqual(report["skills"], len(manifest["skills"]))
        self.assertEqual(report["contexts"], len(manifest["contexts"]))
        self.assertEqual(report["origins"], len(manifest.get("origin_ids", [])))

    def test_foreign_library_with_custom_origins_passes(self) -> None:
        root = mini_library(["A1", "A2"], declared=["A1", "A2"])
        report = vb.validate(root)
        self.assertTrue(report["ok"], report["errors"])
        self.assertEqual(report["origins"], 2)

    def test_foreign_library_derives_origins_when_absent(self) -> None:
        root = mini_library(["X7", "Y9"])
        report = vb.validate(root)
        self.assertTrue(report["ok"], report["errors"])
        self.assertEqual(report["origins"], 2)

    def test_foreign_library_missing_origin_coverage_detected(self) -> None:
        root = mini_library(["A1"], declared=["A1", "A2"])
        report = vb.validate(root)
        self.assertFalse(report["ok"])
        self.assertTrue(any("A2" in e and "sem destino" in e for e in report["errors"]))

    def test_foreign_library_undeclared_origin_detected(self) -> None:
        root = mini_library(["A1", "A2"], declared=["A1"])
        report = vb.validate(root)
        self.assertFalse(report["ok"])
        self.assertTrue(any("A2" in e and "não declarada" in e for e in report["errors"]))

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
