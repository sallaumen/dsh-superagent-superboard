#!/usr/bin/env python3
"""Valida estrutura, referências locais e metadados da biblioteca de capacidades.

Este script confere formato, caminhos, manifesto e links locais. Ele não avalia
a eficácia das skills em projetos reais nem executa suas instruções.
Requer Python 3.10 ou superior; somente biblioteca padrão.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from urllib.parse import unquote, urlparse

MODES = {"analisar", "revisar", "analisar-e-corrigir", "coordenar"}
ORIGIN_IDS = {f"P{i:02d}" for i in range(1, 35)}
SKILL_SECTIONS = ("## Quando usar",)
INSTRUCTION_HEADINGS = ("## Instrução", "### Instrução")


class LibraryError(ValueError):
    """Arquivo ou parâmetro incompatível com o contrato da biblioteca."""


def library_root() -> Path:
    return Path(__file__).resolve().parent.parent


def safe_path(root: Path, relative: str) -> Path:
    if not isinstance(relative, str) or not relative or "\\" in relative or "\0" in relative:
        raise LibraryError(f"Caminho relativo inválido: {relative!r}")
    candidate = Path(relative)
    if candidate.is_absolute() or ".." in candidate.parts:
        raise LibraryError(f"Caminho fora da biblioteca: {relative!r}")
    target = (root / candidate).resolve()
    if not target.is_relative_to(root.resolve()):
        raise LibraryError(f"Caminho resolve para fora da biblioteca: {relative!r}")
    if not target.is_file():
        raise LibraryError(f"Arquivo ausente: {relative}")
    return target


def load_manifest(root: Path) -> dict:
    try:
        manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise LibraryError(f"Não foi possível ler manifest.json: {exc}") from exc
    if not isinstance(manifest, dict) or manifest.get("schema_version") != 2:
        raise LibraryError("Manifesto não reconhecido; esperado schema_version 2.")
    if manifest.get("kind") != "capabilities-library":
        raise LibraryError("Este script aceita somente uma biblioteca de capacidades.")
    for field in ("skills", "contexts"):
        if not isinstance(manifest.get(field), list):
            raise LibraryError(f"Campo ausente ou inválido: {field}")
    for field in ("common_contract", "parameters"):
        if not isinstance(manifest.get(field), str) or not manifest[field].strip():
            raise LibraryError(f"Caminho ausente ou inválido no manifesto: {field}")
    support = manifest.get("support_files", [])
    if not isinstance(support, list) or not all(isinstance(item, str) for item in support):
        raise LibraryError("support_files precisa ser uma lista de caminhos relativos.")
    return manifest


def _frontmatter(text: str, path: Path) -> dict:
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        raise LibraryError(f"{path.name}: frontmatter ausente.")
    try:
        closing = next(i for i, line in enumerate(lines[1:], start=1) if line.strip() == "---")
    except StopIteration as exc:
        raise LibraryError(f"{path.name}: frontmatter não foi fechado.") from exc
    metadata: dict = {}
    for line in lines[1:closing]:
        if not line.strip():
            continue
        if ":" not in line:
            raise LibraryError(f"{path.name}: linha inválida no frontmatter.")
        key, raw = line.split(":", 1)
        if key in metadata:
            raise LibraryError(f"{path.name}: campo duplicado: {key}.")
        try:
            metadata[key] = json.loads(raw.strip())
        except json.JSONDecodeError as exc:
            raise LibraryError(f"{path.name}: {key} deve ter um valor JSON em uma linha.") from exc
    return metadata


def read_skill(path: Path) -> tuple[dict, str]:
    text = path.read_text(encoding="utf-8")
    metadata = _frontmatter(text, path)
    expected = {"name", "title", "category", "default_mode", "origem", "related", "description"}
    if set(metadata) != expected:
        raise LibraryError(
            f"{path.name}: campos esperados: {', '.join(sorted(expected))}."
        )
    if not isinstance(metadata["name"], str) or not re.fullmatch(r"[a-z0-9-]+", metadata["name"]):
        raise LibraryError(f"{path.name}: name inválido; use kebab-case minúsculo.")
    for key in ("title", "category", "description"):
        if not isinstance(metadata[key], str) or not metadata[key].strip():
            raise LibraryError(f"{path.name}: {key} inválido.")
    if not isinstance(metadata["default_mode"], str) or metadata["default_mode"] not in MODES:
        raise LibraryError(f"{path.name}: modo padrão inválido.")
    origem = metadata["origem"]
    if (
        not isinstance(origem, list)
        or not origem
        or not all(isinstance(x, str) for x in origem)
        or any(x not in ORIGIN_IDS for x in origem)
        or len(origem) != len(set(origem))
    ):
        raise LibraryError(f"{path.name}: origem precisa listar IDs P01–P34 sem repetição.")
    related = metadata["related"]
    if not isinstance(related, list) or not all(isinstance(x, str) for x in related):
        raise LibraryError(f"{path.name}: related precisa ser uma lista de nomes.")
    for section in SKILL_SECTIONS:
        if section not in text:
            raise LibraryError(f"{path.name}: seção ausente: {section}")
    if not any(heading in text for heading in INSTRUCTION_HEADINGS):
        raise LibraryError(f"{path.name}: instrução ausente (## Instrução ou ### Instrução).")
    if f"# {metadata['title']}\n" not in text:
        raise LibraryError(f"{path.name}: título divergente do frontmatter.")
    body_start = min(
        text.index(heading)
        for heading in INSTRUCTION_HEADINGS
        if heading in text
    )
    body = text[body_start:]
    return metadata, body


def _check_contexts(root: Path, manifest: dict) -> None:
    contexts: dict[str, dict] = {}
    for item in manifest["contexts"]:
        if not isinstance(item, dict) or not isinstance(item.get("id"), str) or not item["id"]:
            raise LibraryError("Registro de contexto inválido.")
        if item["id"] in contexts:
            raise LibraryError(f"Contexto duplicado: {item['id']}")
        contexts[item["id"]] = item
    visited: set[str] = set()
    active: set[str] = set()

    def visit(context_id: str) -> None:
        if context_id in active:
            raise LibraryError(f"Dependência cíclica de contextos: {context_id}")
        if context_id in visited:
            return
        if context_id not in contexts:
            raise LibraryError(f"Contexto desconhecido: {context_id}")
        item = contexts[context_id]
        required = item.get("requires", [])
        if not isinstance(required, list) or not all(isinstance(x, str) for x in required):
            raise LibraryError(f"Dependências inválidas: {context_id}")
        active.add(context_id)
        for dependency in required:
            visit(dependency)
        safe_path(root, item.get("path"))
        active.remove(context_id)
        visited.add(context_id)

    for context_id in contexts:
        visit(context_id)


def validate(root: Path) -> dict:
    manifest = load_manifest(root)
    errors: list[str] = []
    warnings: list[str] = []
    stats: list[dict] = []
    names: set[str] = set()
    paths: set[str] = set()
    origins_seen: list[tuple[str, str]] = []
    bodies: dict[str, str] = {}
    for item in manifest["skills"]:
        try:
            if not isinstance(item, dict):
                raise LibraryError("Registro de skill inválido no manifesto.")
            path = safe_path(root, item.get("path"))
            metadata, body = read_skill(path)
            name = metadata["name"]
            if name in names:
                errors.append(f"Skill duplicada: {name}")
            names.add(name)
            if item["path"] in paths:
                errors.append(f"Arquivo duplicado: {item['path']}")
            paths.add(item["path"])
            expected_location = Path("skills") / name / "SKILL.md"
            if path != safe_path(root, expected_location.as_posix()):
                errors.append(f"{name}: SKILL.md fora de skills/<name>/.")
            for field in ("name", "title", "category", "default_mode", "origem", "related"):
                if item.get(field) != metadata[field]:
                    errors.append(f"{name}: manifesto diverge em {field}.")
            for origin_id in metadata["origem"]:
                origins_seen.append((origin_id, name))
            for related_name in metadata["related"]:
                if related_name == name:
                    errors.append(f"{name}: related referencia a própria skill.")
                elif related_name not in {s.get("name") for s in manifest["skills"]}:
                    errors.append(f"{name}: referência a skill inexistente: {related_name}")
            digest = hashlib.sha256(body.encode("utf-8")).hexdigest()
            if digest in bodies:
                errors.append(f"Corpos duplicados: {name} e {bodies[digest]}")
            bodies[digest] = name
            words = len(body.split())
            if not 300 <= words <= 1400:
                warnings.append(f"{name}: instrução tem {words} palavras; conferir densidade editorial.")
            stats.append({"name": name, "words": words})
        except (LibraryError, OSError, UnicodeError) as exc:
            errors.append(str(exc))
    actual = {p.relative_to(root).as_posix() for p in (root / "skills").glob("*/SKILL.md")}
    if paths != actual:
        errors.append(f"Arquivos e manifesto divergem: {sorted(paths ^ actual)}")
    origin_counts: dict[str, list[str]] = {}
    for origin_id, name in origins_seen:
        origin_counts.setdefault(origin_id, []).append(name)
    for origin_id in sorted(ORIGIN_IDS):
        if origin_id not in origin_counts:
            errors.append(f"{origin_id}: sem destino registrado no manifesto.")
        elif len(origin_counts[origin_id]) > 1:
            errors.append(f"{origin_id}: destino duplicado em {origin_counts[origin_id]}.")
    try:
        _check_contexts(root, manifest)
        for relative in [manifest["common_contract"], manifest["parameters"], *manifest.get("support_files", [])]:
            safe_path(root, relative)
    except (LibraryError, KeyError, OSError) as exc:
        errors.append(str(exc))
    local_links = 0
    for doc in sorted(root.rglob("*.md")):
        text = doc.read_text(encoding="utf-8")
        for target in re.findall(r"\[[^\]\n]*\]\(([^)\n]+)\)", text):
            if urlparse(target).scheme or target.startswith("#"):
                continue
            target = unquote(target.split("#", 1)[0])
            if not target:
                continue
            local_links += 1
            resolved = (doc.parent / target).resolve()
            if not resolved.is_relative_to(root.resolve()) or not resolved.exists():
                errors.append(f"Link local inválido em {doc.relative_to(root)}: {target}")
    return {
        "ok": not errors,
        "skills": len(stats),
        "contexts": len(manifest["contexts"]),
        "body_words": sum(s["words"] for s in stats),
        "local_links_checked": local_links,
        "errors": errors,
        "warnings": warnings,
        "skill_stats": stats,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true", help="Retorna relatório estruturado")
    args = parser.parse_args()
    try:
        report = validate(library_root())
    except (LibraryError, OSError, UnicodeError) as exc:
        parser.exit(2, f"Erro: {exc}\n")
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        print(
            f"{'OK' if report['ok'] else 'FALHOU'}: {report['skills']} skills; "
            f"{report['contexts']} contextos; {report['body_words']} palavras nas instruções; "
            f"{report['local_links_checked']} links locais conferidos."
        )
        for item in report["errors"]:
            print(f"ERRO: {item}")
        for item in report["warnings"]:
            print(f"AVISO: {item}")
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
