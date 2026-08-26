#!/usr/bin/env python3
"""Validate requirement traceability CSV completeness."""
from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

REQUIRED_COLUMNS = [
    "requirement_id", "source_doc", "source_section", "statement", "status",
    "design_refs", "work_package_refs", "test_refs", "owner", "notes",
]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv_file", type=Path)
    parser.add_argument("--gate", choices=["D2", "D3", "D5"], default="D5")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    errors: list[str] = []
    warnings: list[str] = []
    seen: set[str] = set()
    rows = 0

    try:
        with args.csv_file.open(encoding="utf-8-sig", newline="") as fh:
            reader = csv.DictReader(fh)
            missing = [c for c in REQUIRED_COLUMNS if c not in (reader.fieldnames or [])]
            if missing:
                errors.append(f"missing columns: {', '.join(missing)}")
            for line_no, row in enumerate(reader, start=2):
                rows += 1
                rid = (row.get("requirement_id") or "").strip()
                if not rid:
                    errors.append(f"line {line_no}: empty requirement_id")
                    continue
                if rid in seen:
                    errors.append(f"line {line_no}: duplicate requirement_id {rid}")
                seen.add(rid)
                for field in ("source_doc", "source_section", "statement", "status", "owner"):
                    if not (row.get(field) or "").strip():
                        errors.append(f"line {line_no} {rid}: empty {field}")
                if args.gate in ("D2", "D3", "D5") and not (row.get("design_refs") or "").strip():
                    errors.append(f"line {line_no} {rid}: missing design_refs")
                if args.gate in ("D3", "D5") and not (row.get("work_package_refs") or "").strip():
                    errors.append(f"line {line_no} {rid}: missing work_package_refs")
                if args.gate in ("D3", "D5") and not (row.get("test_refs") or "").strip():
                    errors.append(f"line {line_no} {rid}: missing test_refs")
    except OSError as exc:
        errors.append(str(exc))

    if rows == 0:
        warnings.append("traceability file has no requirement rows")
        if args.gate in ("D3", "D5"):
            errors.append(f"{args.gate} requires at least one traced requirement")

    gate_pass = not errors and not warnings
    payload = {"file": str(args.csv_file), "rows": rows, "errors": errors,
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
