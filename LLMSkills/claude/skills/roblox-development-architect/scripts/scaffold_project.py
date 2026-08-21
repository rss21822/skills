#!/usr/bin/env python3
"""Create a non-destructive Roblox AI development documentation scaffold.

The script copies bundled templates, writes a docs manifest, and optionally
creates Trigger Specs from an intake JSON. It never overwrites without --force.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import shutil
from pathlib import Path
from typing import Iterable

from detect_triggers import detect

SKILL_DIR = Path(__file__).resolve().parent.parent
TEMPLATES = SKILL_DIR / "templates"
SCHEMAS = SKILL_DIR / "schemas"

CORE_DOCS = [
    ("docs_index.md", "docs/{P}_docs_index.md", "navigation and canonical boundaries"),
    ("intake.json", "docs/{P}_intake.json", "approved intake"),
    ("gdd.md", "docs/{P}_gdd.md", "product intent"),
    ("detailed_design.md", "docs/{P}_detailed_design.md", "system structure"),
    ("data_definition.md", "docs/{P}_data_definition.md", "balance and formulas"),
    ("ui_ux_input_spec.md", "docs/{P}_ui_ux_input_spec.md", "UI, UX, and input"),
    ("toolchain_spec.md", "docs/{P}_toolchain_spec.md", "repository and toolchain"),
    ("phase_plan.md", "docs/{P}_phase_plan.md", "implementation order"),
    ("work_packages.md", "docs/{P}_work_packages.md", "file-level work scope"),
    ("test_spec.md", "docs/{P}_test_spec.md", "verification"),
    ("workflow.md", "docs/{P}_workflow.md", "human and AI operation"),
    ("release_rollback_runbook.md", "docs/{P}_release_rollback_runbook.md", "release and rollback"),
]

ROOT_DOCS = [
    ("claude_md.md", "CLAUDE.md"),
    ("progress.md", "PROGRESS.md"),
    ("asset_todo.md", "ASSET_TODO.md"),
    ("human_actions.md", "HUMAN_ACTIONS.md"),
    ("ai_actions.md", "AI_ACTIONS.md"),
    ("changelog.md", "CHANGELOG.md"),
    ("decisions.md", "DECISIONS.md"),
]

SPEC_OUTPUTS = {
    "network_security": "docs/specs/{P}_network_security_spec.md",
    "persistence_migration": "docs/specs/{P}_persistence_migration_spec.md",
    "commerce_policy": "docs/specs/{P}_commerce_policy_spec.md",
    "paid_random_items": "docs/specs/{P}_paid_random_items_annex.md",
    "analytics_observability": "docs/specs/{P}_analytics_observability_spec.md",
    "performance_budget": "docs/specs/{P}_performance_budget_spec.md",
    "asset_content_pipeline": "docs/specs/{P}_asset_content_pipeline_spec.md",
    "multi_place_matchmaking": "docs/specs/{P}_multi_place_matchmaking_spec.md",
    "physics_control": "docs/specs/{P}_physics_control_spec.md",
    "ugc_moderation": "docs/specs/{P}_ugc_moderation_spec.md",
    "localization_accessibility": "docs/specs/{P}_localization_accessibility_spec.md",
    "liveops_content": "docs/specs/{P}_liveops_content_spec.md",
    "external_services_secrets": "docs/specs/{P}_external_services_secrets_spec.md",
    "rights_provenance": "docs/specs/{P}_rights_provenance_ledger.md",
    "repository_audit": "docs/{P}_repository_audit.md",
    "feasibility_report": "docs/{P}_feasibility_report.md",
}


def replace_tokens(text: str, project: str, prefix: str) -> str:
    values = {
        "{{PROJECT}}": project,
        "{{PREFIX}}": prefix,
        "{{DATE}}": dt.date.today().isoformat(),
        "{{INPUTS}}": "D0 intake and approved upstream documents",
        "{{DOWNSTREAM}}": "See documentation index",
    }
    for key, value in values.items():
        text = text.replace(key, value)
    return text


def safe_write(path: Path, text: str, force: bool, created: list[str], skipped: list[str]) -> None:
    if path.exists() and not force:
        skipped.append(str(path))
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    created.append(str(path))


def copy_template(template_name: str, destination: Path, project: str, prefix: str, force: bool,
                  created: list[str], skipped: list[str]) -> None:
    src = TEMPLATES / template_name
    text = replace_tokens(src.read_text(encoding="utf-8"), project, prefix)
    safe_write(destination, text, force, created, skipped)


def valid_prefix(value: str) -> str:
    value = value.upper()
    if not re.fullmatch(r"[A-Z0-9]{2,6}", value):
        raise argparse.ArgumentTypeError("prefix must be 2–6 uppercase ASCII letters/numbers")
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-name", required=True)
    parser.add_argument("--prefix", required=True, type=valid_prefix)
    parser.add_argument("--project-root", type=Path, default=Path.cwd())
    parser.add_argument("--intake", type=Path, help="Approved intake JSON for Trigger Specs")
    parser.add_argument("--force", action="store_true", help="Overwrite existing scaffold files")
    args = parser.parse_args()

    project_root = args.project_root.resolve()
    project_root.mkdir(parents=True, exist_ok=True)
    created: list[str] = []
    skipped: list[str] = []
    manifest_docs: list[dict[str, object]] = []

    for template, output, domain in CORE_DOCS:
        rel = output.format(P=args.prefix)
        if template == "intake.json" and args.intake:
            # The user-provided/approved intake is copied below instead of the blank template.
            manifest_docs.append({"path": rel, "domain": domain, "required": True, "status": "draft", "trigger": None})
            continue
        copy_template(template, project_root / rel, args.project_name, args.prefix, args.force, created, skipped)
        manifest_docs.append({"path": rel, "domain": domain, "required": True, "status": "draft", "trigger": None})

    for template, output in ROOT_DOCS:
        copy_template(template, project_root / output, args.project_name, args.prefix, args.force, created, skipped)
        manifest_docs.append({"path": output, "domain": "operating file", "required": True, "status": "draft", "trigger": None})

    # Machine-readable starting points.
    trace_rel = f"docs/traceability/{args.prefix}_requirements.csv"
    safe_write(project_root / trace_rel, (SCHEMAS / "requirements.csv").read_text(encoding="utf-8"),
               args.force, created, skipped)
    manifest_docs.append({"path": trace_rel, "domain": "requirements traceability", "required": True, "status": "draft", "trigger": None})

    for schema_name in ("docs_manifest.schema.json", "intake.schema.json", "work_package.schema.json",
                        "remote_contract.schema.json", "save_schema.schema.json", "analytics_event.schema.json",
                        "asset_ledger.schema.json"):
        rel = f"docs/schemas/{schema_name}"
        safe_write(project_root / rel, (SCHEMAS / schema_name).read_text(encoding="utf-8"),
                   args.force, created, skipped)

    residual_rel = f"docs/{args.prefix}_residual_terms.txt"
    safe_write(project_root / residual_rel,
               "# One forbidden legacy term per line. Lines beginning with # are ignored.\n",
               args.force, created, skipped)

    required_specs: list[dict[str, str]] = []
    if args.intake:
        data = json.loads(args.intake.read_text(encoding="utf-8"))
        required_specs = detect(data)
        # Preserve the provided intake as the canonical starting input.
        intake_rel = f"docs/{args.prefix}_intake.json"
        safe_write(project_root / intake_rel,
                   json.dumps(data, ensure_ascii=False, indent=2) + "\n",
                   args.force, created, skipped)

        for item in required_specs:
            spec_id = item["id"]
            output = SPEC_OUTPUTS[spec_id].format(P=args.prefix)
            template = item["template"]
            copy_template(template, project_root / output, args.project_name, args.prefix, args.force, created, skipped)
            manifest_docs.append({"path": output, "domain": spec_id, "required": True, "status": "draft", "trigger": item["reason"]})

    req_specs_rel = f"docs/{args.prefix}_required_specs.json"
    safe_write(project_root / req_specs_rel,
               json.dumps({"project": args.project_name, "prefix": args.prefix, "required_specs": required_specs},
                          ensure_ascii=False, indent=2) + "\n",
               args.force, created, skipped)

    manifest = {"project": args.project_name, "prefix": args.prefix, "documents": manifest_docs}
    manifest_rel = f"docs/{args.prefix}_docs_manifest.json"
    safe_write(project_root / manifest_rel, json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
               args.force, created, skipped)

    (project_root / "docs/evidence").mkdir(parents=True, exist_ok=True)
    print(json.dumps({"created": created, "skipped": skipped, "manifest": manifest_rel}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
