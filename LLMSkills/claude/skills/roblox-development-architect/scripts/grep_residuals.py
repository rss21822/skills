#!/usr/bin/env python3
"""Scan a project for forbidden legacy terms listed one-per-line."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

TEXT_SUFFIXES = {".md", ".txt", ".json", ".yaml", ".yml", ".toml", ".lua", ".luau", ".csv", ".xml"}
SKIP_DIRS = {".git", ".svn", "node_modules", ".venv", "__pycache__"}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=Path.cwd())
    parser.add_argument("--terms", type=Path, required=True)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    terms = [line.strip() for line in args.terms.read_text(encoding="utf-8").splitlines()
             if line.strip() and not line.lstrip().startswith("#")]
    hits: list[dict[str, object]] = []

    for path in args.project_root.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in TEXT_SUFFIXES:
            continue
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        if path.resolve() == args.terms.resolve():
            continue
        try:
            lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
        except OSError:
            continue
        for no, line in enumerate(lines, start=1):
            for term in terms:
                if term in line:
                    hits.append({"file": str(path.relative_to(args.project_root)), "line": no, "term": term, "text": line.strip()[:240]})

    payload = {"terms": terms, "hits": hits, "pass": not hits}
    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        print("PASS" if not hits else "FAIL")
        for hit in hits:
            print(f"{hit['file']}:{hit['line']}: {hit['term']}: {hit['text']}")
    return 0 if not hits else 1


if __name__ == "__main__":
    raise SystemExit(main())
