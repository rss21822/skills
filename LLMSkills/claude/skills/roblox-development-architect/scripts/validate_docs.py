#!/usr/bin/env python3
"""Validate a scaffolded Roblox documentation system at a named gate."""
from __future__ import annotations

import argparse
import csv
import json
import re
from pathlib import Path
from urllib.parse import unquote

ROOT_REQUIRED = [
    "CLAUDE.md", "PROGRESS.md", "ASSET_TODO.md", "HUMAN_ACTIONS.md",
    "AI_ACTIONS.md", "CHANGELOG.md", "DECISIONS.md",
]
LINK_RE = re.compile(r"\[[^\]]+\]\(([^)]+)\)")
PLACEHOLDER_RE = re.compile(r"\{\{[^}]+\}\}|TODO-UNRESOLVED")


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
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        manifest = {"documents": []}
        errors.append(f"cannot read manifest {manifest_path}: {exc}")

    required_paths = [item.get("path") for item in manifest.get("documents", []) if item.get("required")]
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
        if path.suffix.lower() == ".md":
            errors.extend(markdown_links(path, root))
            text = path.read_text(encoding="utf-8", errors="ignore")
            if args.gate == "D5":
                for token, label in (
                    ("[PROPOSAL]", "unapproved proposal"),
                    ("[ASSUMPTION]", "unverified assumption"),
                    ("[OPEN blocking: yes]", "blocking open question"),
                ):
                    if token in text:
                        errors.append(f"{rel}: contains {label} {token}")
                if PLACEHOLDER_RE.search(text):
                    errors.append(f"{rel}: contains unresolved template placeholder")
        elif path.suffix.lower() == ".json":
            try:
                json.loads(path.read_text(encoding="utf-8"))
            except json.JSONDecodeError as exc:
                errors.append(f"invalid JSON {rel}: {exc}")

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

    payload = {"gate": args.gate, "checked": checked, "errors": errors, "warnings": warnings, "pass": not errors}
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        print("PASS" if not errors else "FAIL")
        for msg in errors:
            print(f"ERROR: {msg}")
        for msg in warnings:
            print(f"WARN: {msg}")
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
