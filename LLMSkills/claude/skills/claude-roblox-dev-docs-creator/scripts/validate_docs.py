#!/usr/bin/env python3
"""Validate a scaffolded Roblox documentation system at a named gate."""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import re
from pathlib import Path
from urllib.parse import unquote

from detect_triggers import detect, validate_intake
from state_readiness import scan_readiness_text
from strict_json import loads as strict_json_loads

ROOT_REQUIRED = [
    "CLAUDE.md", "PROGRESS.md", "ASSET_TODO.md", "HUMAN_ACTIONS.md",
    "AI_ACTIONS.md", "CHANGELOG.md", "DECISIONS.md",
]
LINK_RE = re.compile(r"\[[^\]]+\]\(([^)]+)\)")
SKILL_SCHEMAS = Path(__file__).resolve().parent.parent / "schemas"
MACHINE_CONTRACTS = {
    "remote_contracts.json": ("remote_contract.schema.json", "network_security", "contracts"),
    "save_schema.json": ("save_schema.schema.json", "persistence_migration", "root"),
    "analytics_events.json": ("analytics_event.schema.json", "analytics_observability", "events"),
    "asset_ledger.json": ("asset_ledger.schema.json", "asset_content_pipeline", "assets"),
    "commerce_ledger.json": ("commerce_ledger.schema.json", "commerce_policy", "products"),
}


def _schema_type(value, expected) -> bool:
    if expected == "object":
        return isinstance(value, dict)
    if expected == "array":
        return isinstance(value, list)
    if expected == "string":
        return isinstance(value, str)
    if expected == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if expected == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    if expected == "boolean":
        return isinstance(value, bool)
    if expected == "null":
        return value is None
    return True


def structural_schema_errors(
        value, schema: dict, root_schema: dict, location: str = "$") -> list[str]:
    """Small draft-2020-12 subset used by the five bundled D2 contracts."""
    errors: list[str] = []
    if "$ref" in schema:
        ref = schema["$ref"]
        if not isinstance(ref, str) or not ref.startswith("#/$defs/"):
            return [f"{location}: unsupported schema reference {ref!r}"]
        target = root_schema.get("$defs", {}).get(ref.rsplit("/", 1)[-1])
        if not isinstance(target, dict):
            return [f"{location}: unresolved schema reference {ref}"]
        return structural_schema_errors(value, target, root_schema, location)
    if "const" in schema and value != schema["const"]:
        errors.append(f"{location}: must equal {schema['const']!r}")
    if "enum" in schema and value not in schema["enum"]:
        errors.append(f"{location}: value is outside enum")
    expected = schema.get("type")
    if expected is not None:
        choices = expected if isinstance(expected, list) else [expected]
        if not any(_schema_type(value, choice) for choice in choices):
            return [f"{location}: expected type {expected!r}"]
    if isinstance(value, str):
        if len(value) < schema.get("minLength", 0):
            errors.append(f"{location}: string is too short")
        pattern = schema.get("pattern")
        if isinstance(pattern, str) and re.search(pattern, value) is None:
            errors.append(f"{location}: does not match {pattern}")
        if schema.get("format") == "date-time":
            raw = value[:-1] + "+00:00" if value.endswith("Z") else value
            try:
                parsed = dt.datetime.fromisoformat(raw)
                if parsed.tzinfo is None:
                    raise ValueError
            except ValueError:
                errors.append(f"{location}: invalid timezone date-time")
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if "minimum" in schema and value < schema["minimum"]:
            errors.append(f"{location}: value is below minimum {schema['minimum']}")
        if "maximum" in schema and value > schema["maximum"]:
            errors.append(f"{location}: value is above maximum {schema['maximum']}")
        if "exclusiveMinimum" in schema and value <= schema["exclusiveMinimum"]:
            errors.append(
                f"{location}: value is not above exclusiveMinimum {schema['exclusiveMinimum']}")
        if "exclusiveMaximum" in schema and value >= schema["exclusiveMaximum"]:
            errors.append(
                f"{location}: value is not below exclusiveMaximum {schema['exclusiveMaximum']}")
    if isinstance(value, list):
        if len(value) < schema.get("minItems", 0):
            errors.append(f"{location}: array has too few items")
        if "maxItems" in schema and len(value) > schema["maxItems"]:
            errors.append(f"{location}: array has too many items")
        if schema.get("uniqueItems") and len({json.dumps(v, sort_keys=True) for v in value}) != len(value):
            errors.append(f"{location}: array items are not unique")
        item_schema = schema.get("items")
        if isinstance(item_schema, dict):
            for index, item in enumerate(value):
                errors.extend(structural_schema_errors(
                    item, item_schema, root_schema, f"{location}[{index}]"))
    if isinstance(value, dict):
        if len(value) < schema.get("minProperties", 0):
            errors.append(f"{location}: object has too few properties")
        if "maxProperties" in schema and len(value) > schema["maxProperties"]:
            errors.append(f"{location}: object has too many properties")
        required = schema.get("required", [])
        for key in required:
            if key not in value:
                errors.append(f"{location}: missing required key {key}")
        properties = schema.get("properties", {})
        if schema.get("additionalProperties") is False:
            for key in value:
                if key not in properties:
                    errors.append(f"{location}: unknown key {key}")
        additional = schema.get("additionalProperties")
        for key, item in value.items():
            child = properties.get(key)
            if isinstance(child, dict):
                errors.extend(structural_schema_errors(
                    item, child, root_schema, f"{location}.{key}"))
            elif isinstance(additional, dict):
                errors.extend(structural_schema_errors(
                    item, additional, root_schema, f"{location}.{key}"))
    for part in schema.get("allOf", []):
        if isinstance(part, dict) and "if" not in part:
            errors.extend(structural_schema_errors(value, part, root_schema, location))
    return errors


def validate_d2_machine_contracts(
        root: Path, prefix: str, manifest: dict, errors: list[str], checked: list[str],
        gate: str = "D2") -> None:
    project = manifest.get("project")
    intake_path = root / "docs" / f"{prefix}_intake.json"
    required_specs_path = root / "docs" / f"{prefix}_required_specs.json"
    try:
        intake = strict_json_loads(intake_path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        errors.append(f"cannot read approved intake for D2 contracts: {exc}")
        return
    intake_errors = validate_intake(
        intake, expected_project=project if isinstance(project, str) else None,
        expected_prefix=prefix, require_approved=True)
    errors.extend(f"intake: {message}" for message in intake_errors)
    try:
        declared = strict_json_loads(required_specs_path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        errors.append(f"cannot read required specs for D2 contracts: {exc}")
        return
    if declared.get("project") != project or declared.get("prefix") != prefix:
        errors.append("required specs identity does not match docs manifest")
    expected_specs = detect(intake)
    if declared.get("required_specs") != expected_specs:
        errors.append("required specs file does not equal trigger detection output")
    triggered = {item["id"] for item in expected_specs}
    manifest_documents = manifest.get("documents")
    if not isinstance(manifest_documents, list):
        errors.append("docs manifest documents must be an array")
        manifest_documents = []

    for instance_name, (schema_name, trigger, collection) in MACHINE_CONTRACTS.items():
        if trigger not in triggered:
            continue
        rel = f"docs/schemas/{prefix}_{instance_name}"
        registered = [item for item in manifest_documents
                      if isinstance(item, dict)
                      and str(item.get("path", "")).replace("\\", "/") == rel]
        if len(registered) != 1:
            errors.append(
                f"triggered machine-readable contract must have exactly one manifest row: {rel}")
        else:
            row = registered[0]
            if (row.get("domain") != "machine-readable initial instance"
                    or row.get("phase") != "D2" or row.get("required") is not True):
                errors.append(
                    f"{rel}: manifest row requires domain=machine-readable initial instance, "
                    "phase=D2, required=true")
        path = root / rel
        if not path.is_file():
            errors.append(f"missing triggered machine-readable contract: {rel}")
            continue
        checked.append(rel)
        try:
            data = strict_json_loads(path.read_text(encoding="utf-8-sig"))
            schema = strict_json_loads(
                (SKILL_SCHEMAS / schema_name).read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            errors.append(f"invalid machine-readable contract {rel}: {exc}")
            continue
        errors.extend(f"{rel}: {message}" for message in structural_schema_errors(data, schema, schema))
        if not isinstance(data, dict) or data.get("project") != project or data.get("prefix") != prefix:
            errors.append(f"{rel}: project/prefix identity mismatch")
            continue
        value = data.get(collection)
        if not value:
            errors.append(f"{rel}: triggered D2 contract `{collection}` is empty")
        if gate == "D5":
            active_rows = [data] if collection == "root" else (
                value if isinstance(value, list) else [])
            for index, item in enumerate(active_rows):
                if isinstance(item, dict) and item.get("status") == "proposed":
                    errors.append(
                        f"{rel}: D5 active record {index} remains proposed")


def markdown_links(path: Path, root: Path) -> list[str]:
    errors: list[str] = []
    text = path.read_text(encoding="utf-8", errors="ignore")
    for target in LINK_RE.findall(text):
        target = unquote(target.split("#", 1)[0].strip())
        if not target or target.startswith(("http://", "https://", "mailto:", "#")):
            continue
        candidate = (path.parent / target).resolve()
        try:
            candidate.relative_to(root.resolve())
        except ValueError:
            continue
        if not candidate.exists():
            errors.append(f"broken link in {path.relative_to(root)} -> {target}")
    return errors


def count_non_goals(gdd_text: str) -> int:
    match = re.search(r"(?im)^##\s+\d*\.?\s*Non-Goals\s*$", gdd_text)
    if not match:
        return 0
    tail = gdd_text[match.end():]
    next_heading = re.search(r"(?m)^##\s+", tail)
    section = tail[: next_heading.start()] if next_heading else tail
    numbered = re.findall(r"(?m)^\s*\d+[.)]\s+", section)
    bullets = re.findall(r"(?m)^\s*[-*]\s+", section)
    table_rows = [line for line in section.splitlines() if line.startswith("|") and "---" not in line]
    return max(len(numbered), len(bullets), max(0, len(table_rows) - 1))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=Path.cwd())
    parser.add_argument("--prefix", required=True)
    parser.add_argument("--gate", choices=["D0", "D1", "D2", "D3", "D5"], default="D5")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    root = args.project_root.resolve()
    manifest_path = root / "docs" / f"{args.prefix}_docs_manifest.json"
    errors: list[str] = []
    warnings: list[str] = []
    checked: list[str] = []

    try:
        manifest = strict_json_loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        manifest = {"documents": []}
        errors.append(f"cannot read manifest {manifest_path}: {exc}")

    documents = manifest.get("documents", []) if isinstance(manifest, dict) else []
    required_paths = [item.get("path") for item in documents
                      if isinstance(item, dict)
                      and (args.gate == "D5" or item.get("required"))]
    for rel in ROOT_REQUIRED:
        if rel not in required_paths:
            required_paths.append(rel)

    for rel in required_paths:
        if not rel:
            continue
        path = root / rel
        if not path.exists():
            errors.append(f"missing required file: {rel}")
            continue
        checked.append(rel)
        suffix = path.suffix.lower()
        if suffix == ".md":
            errors.extend(markdown_links(path, root))
            text = path.read_text(encoding="utf-8", errors="ignore")
        elif suffix == ".json":
            text = path.read_text(encoding="utf-8", errors="ignore")
            try:
                strict_json_loads(text)
            except json.JSONDecodeError as exc:
                errors.append(f"invalid JSON {rel}: {exc}")
        elif suffix in {".csv", ".txt", ".yaml", ".yml"}:
            text = path.read_text(encoding="utf-8", errors="ignore")
        else:
            text = ""
        if args.gate == "D5" and text:
            for issue in scan_readiness_text(text, suffix):
                errors.append(
                    f"{rel}:{issue['line']}: contains {issue['label']} {issue['token']}")

    if args.gate in ("D2", "D3", "D5") and isinstance(manifest, dict):
        validate_d2_machine_contracts(
            root, args.prefix, manifest, errors, checked, args.gate)

    gdd = root / "docs" / f"{args.prefix}_gdd.md"
    if gdd.exists() and args.gate in ("D1", "D2", "D3", "D5"):
        count = count_non_goals(gdd.read_text(encoding="utf-8", errors="ignore"))
        if count < 6:
            errors.append(f"GDD Non-Goals count is {count}; minimum is 6")

    decisions = root / "DECISIONS.md"
    if decisions.exists() and args.gate in ("D2", "D3", "D5"):
        text = decisions.read_text(encoding="utf-8", errors="ignore")
        d_ids = set(re.findall(r"\bD-(\d+)\b", text))
        f_ids = set(re.findall(r"\bF-(\d+)\b", text))
        missing_f = sorted(d_ids - f_ids)
        if missing_f:
            warnings.append(f"decisions without same-number fallback: {', '.join(missing_f)}")

    # Basic traceability check at later gates.
    trace = root / "docs" / "traceability" / f"{args.prefix}_requirements.csv"
    if args.gate in ("D2", "D3", "D5"):
        if not trace.exists():
            errors.append(f"missing traceability file: {trace.relative_to(root)}")
        elif args.gate == "D5":
            with trace.open(encoding="utf-8-sig", newline="") as fh:
                rows = list(csv.DictReader(fh))
            if not rows:
                errors.append("D5 requires at least one requirement row")
            for idx, row in enumerate(rows, start=2):
                for field in ("design_refs", "work_package_refs", "test_refs"):
                    if not (row.get(field) or "").strip():
                        errors.append(f"traceability line {idx}: empty {field}")

    gate_pass = not errors and not warnings
    payload = {"gate": args.gate, "checked": checked, "errors": errors,
               "warnings": warnings, "pass": gate_pass}
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        print("PASS" if gate_pass else "FAIL")
        for msg in errors:
            print(f"ERROR: {msg}")
        for msg in warnings:
            print(f"WARN: {msg}")
    return 0 if gate_pass else 1


if __name__ == "__main__":
    raise SystemExit(main())
