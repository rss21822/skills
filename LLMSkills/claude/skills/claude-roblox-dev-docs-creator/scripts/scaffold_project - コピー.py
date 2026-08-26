#!/usr/bin/env python3
"""Create a non-destructive Roblox AI development documentation scaffold.

The script copies bundled templates, writes a docs manifest, and optionally
creates Trigger Specs from an intake JSON. It never overwrites without --force.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import tempfile
from pathlib import Path
from typing import Any

from detect_triggers import detect, validate_intake
from strict_json import loads as strict_json_loads

SKILL_DIR = Path(__file__).resolve().parent.parent
TEMPLATES = SKILL_DIR / "templates"
SCHEMAS = SKILL_DIR / "schemas"
MANIFEST_VERSION = "1.0.0"

SCHEMA_PHASES = {
    "intake.schema.json": "D0",
    "remote_contract.schema.json": "D2",
    "save_schema.schema.json": "D2",
    "analytics_event.schema.json": "D2",
    "asset_ledger.schema.json": "D2",
    "commerce_ledger.schema.json": "D2",
    "work_package.schema.json": "D3",
    "docs_manifest.schema.json": "D3",
    "baseline_manifest.schema.json": "D4",
    "d4_audit_capsule.schema.json": "D4",
    "d4_capsule_assembly_attestation.schema.json": "D4",
    "d4_audit_policy_manifest.schema.json": "D4",
    "d4_runtime_allowlist.schema.json": "D4",
    "d4_audit_request.schema.json": "D4",
    "d4_auditor_attestation.schema.json": "D4",
    "gate_approval_record.schema.json": "D1",
    "human_approval_capture.schema.json": "D1",
    "human_approval_challenge.schema.json": "D1",
    "human_approval_presentation.schema.json": "D1",
    "human_interaction_transcript.schema.json": "D1",
    "pinned_signature_evidence.schema.json": "D1",
    "provenance_verification.schema.json": "D1",
    "trusted_runtime_query_result.schema.json": "D1",
    "d15_measurement_evidence.schema.json": "D1.5",
    "required_specs.schema.json": "D1.5",
    "lifecycle_transition_attestation.schema.json": "P0",
    "lifecycle_write_log.schema.json": "P0",
    "post_sync_manifest.schema.json": "D5",
    "w0_handoff_package.schema.json": "D5",
    "w0_run_authorization.schema.json": "W0",
    "w0_run_admission_attestation.schema.json": "W0",
}
OPERATOR_ONLY_SCHEMAS = {
    "provenance_verifier_config.schema.json",
    "w0_runtime_launch_challenge.schema.json",
    "w0_runtime_prelaunch_assertion.schema.json",
    "w0_runtime_prepare_execution_attestation.schema.json",
    "w0_runtime_postexecution_attestation.schema.json",
    "w0_runtime_admit_execution_attestation.schema.json",
}
INSTANCE_PHASES = {
    "remote_contracts.json": "D2",
    "save_schema.json": "D2",
    "analytics_events.json": "D2",
    "asset_ledger.json": "D2",
    "commerce_ledger.json": "D2",
}

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
    atomic_write_many({path: text})
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


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def atomic_write_many(writes: dict[Path, str]) -> None:
    """Replace a derived-file set as one rollback-capable transaction.

    Each temporary file is placed beside its destination, so ``os.replace`` is
    atomic even when the project root is on another volume.  If a later replace
    fails, earlier destinations are restored from their in-memory preimages.
    """
    staged: dict[Path, Path] = {}
    previous: dict[Path, bytes | None] = {}
    replaced: list[Path] = []
    try:
        for path, text in writes.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            previous[path] = path.read_bytes() if path.exists() else None
            with tempfile.NamedTemporaryFile(
                    mode="w", encoding="utf-8", newline="", delete=False,
                    dir=path.parent, prefix=f".{path.name}.", suffix=".tmp") as fh:
                fh.write(text)
                fh.flush()
                os.fsync(fh.fileno())
                staged[path] = Path(fh.name)
        for path, temporary in staged.items():
            os.replace(temporary, path)
            replaced.append(path)
    except Exception:
        for path in reversed(replaced):
            prior = previous[path]
            if prior is None:
                try:
                    path.unlink()
                except FileNotFoundError:
                    pass
            else:
                with tempfile.NamedTemporaryFile(
                        mode="wb", delete=False, dir=path.parent,
                        prefix=f".{path.name}.rollback.", suffix=".tmp") as fh:
                    fh.write(prior)
                    fh.flush()
                    os.fsync(fh.fileno())
                    rollback = Path(fh.name)
                os.replace(rollback, path)
        raise
    finally:
        for temporary in staged.values():
            try:
                temporary.unlink()
            except FileNotFoundError:
                pass


def read_json(path: Path, label: str) -> Any:
    try:
        return strict_json_loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"cannot read {label} {path}: {exc}") from exc


def generated_intake(project: str, prefix: str) -> dict[str, Any]:
    text = replace_tokens((TEMPLATES / "intake.json").read_text(encoding="utf-8"), project, prefix)
    return strict_json_loads(text)


def can_replace_intake_placeholder(path: Path, project: str, prefix: str) -> bool:
    """Only the byte-equivalent generated, unapproved placeholder is replaceable."""
    try:
        existing = read_json(path, "existing intake")
    except ValueError:
        return False
    return existing == generated_intake(project, prefix) \
        and (existing.get("state") or {}).get("approved") is False


def document_entry(
        path: str, domain: str, *, phase: str, required: bool = True,
        status: str = "draft", trigger: str | None = None,
        doc_id: str | None = None, version: str = "0.1.0") -> dict[str, Any]:
    return {
        "id": doc_id or path,
        "path": path,
        "domain": domain,
        "required": required,
        "status": status,
        "version": version,
        "phase": phase,
        "trigger": trigger,
    }


def markdown_header(path: Path) -> dict[str, str]:
    fields: dict[str, str] = {}
    if not path.is_file():
        return fields
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = re.match(r"^\|\s*(Document ID|Version|Status|Canonical domain)\s*\|\s*(.*?)\s*\|$", line)
        if match:
            fields[match.group(1)] = match.group(2).strip(" `")
        elif fields and not line.startswith("|"):
            break
    return fields


def normalize_manifest_status(raw: str) -> str:
    value = raw
    for separator in ("（", "(", "。", "、", ",", "<!--"):
        value = value.split(separator)[0]
    value = value.replace("`", "").replace("*", "").strip().lower()
    return {"draft": "draft", "review": "review", "in review": "review",
            "approved": "approved", "superseded": "superseded"}.get(value, "draft")


def refresh_entry_from_disk(root: Path, item: dict[str, Any]) -> dict[str, Any]:
    header = markdown_header(root / item["path"])
    if not header:
        return item
    updated = dict(item)
    updated["id"] = header.get("Document ID") or updated["id"]
    updated["version"] = header.get("Version") or updated["version"]
    updated["status"] = normalize_manifest_status(header.get("Status") or updated["status"])
    updated["domain"] = header.get("Canonical domain") or updated["domain"]
    return updated


def merge_manifest(
        existing: dict[str, Any] | None, expected: list[dict[str, Any]],
        project: str, prefix: str) -> dict[str, Any]:
    """Merge generated registry rows without discarding user-owned documents."""
    prior: dict[str, dict[str, Any]] = {}
    if existing is not None:
        if existing.get("project") != project or existing.get("prefix") != prefix:
            raise ValueError("existing manifest project/prefix does not match requested identity")
        documents = existing.get("documents")
        if not isinstance(documents, list):
            raise ValueError("existing manifest documents must be an array")
        for item in documents:
            if not isinstance(item, dict) or not isinstance(item.get("path"), str):
                raise ValueError("existing manifest contains an invalid document entry")
            raw = item["path"].replace("\\", "/")
            while raw.startswith("./"):
                raw = raw[2:]
            candidate = Path(raw)
            if candidate.is_absolute() or ".." in candidate.parts or not raw:
                raise ValueError(f"existing manifest path must stay project-relative: {item['path']}")
            key = candidate.as_posix()
            if key in prior:
                raise ValueError(f"existing manifest has duplicate path: {key}")
            prior[key] = dict(item, path=key)

    merged: list[dict[str, Any]] = []
    expected_paths: set[str] = set()
    for generated in expected:
        path = generated["path"]
        expected_paths.add(path)
        old = prior.get(path, {})
        item = dict(generated)
        # Status/version are current-state fields; retain an established value.
        for key in ("status", "version"):
            if key in old:
                item[key] = old[key]
        merged.append(item)
    for path, item in prior.items():
        if path not in expected_paths:
            # Normalize legacy entries to the current manifest contract.
            merged.append(document_entry(
                path, str(item.get("domain") or "user-managed artifact"),
                phase=str(item.get("phase") or "D2"),
                required=bool(item.get("required", True)),
                status=str(item.get("status") or "draft"),
                trigger=item.get("trigger") if isinstance(item.get("trigger"), str) else None,
                doc_id=str(item.get("id") or path),
                version=str(item.get("version") or "0.1.0")))
    merged.sort(key=lambda item: (item["phase"], item["path"]))
    return {
        "schemaVersion": MANIFEST_VERSION,
        "generatedAt": utc_now(),
        "baselineId": (existing or {}).get("baselineId"),
        "project": project,
        "prefix": prefix,
        "documents": merged,
    }


def reconcile_p0_config(
        path: Path, project: str, prefix: str, triggered: list[dict[str, str]],
        force: bool) -> tuple[str, bool]:
    """Return P0 config text and whether the project file must be replaced.

    Trigger Specs participate in strict open-evidence and decision-reference
    checks.  A late approved intake therefore updates only those two derived
    path lists while retaining user-owned config choices and unknown future
    config keys.
    """
    template_path = TEMPLATES / "p0-check.json"
    template = strict_json_loads(replace_tokens(
        template_path.read_text(encoding="utf-8"), project, prefix))
    if not isinstance(template, dict):
        raise ValueError("bundled p0-check.json root must be an object")
    exists = path.is_file()
    if exists and not force:
        current = read_json(path, "existing P0 config")
        if not isinstance(current, dict):
            raise ValueError("existing P0 config root must be an object")
        config = current
    else:
        config = template

    all_conditional = {
        SPEC_OUTPUTS[spec_id].format(P=prefix) for spec_id in SPEC_OUTPUTS
    }
    required_conditional = [
        SPEC_OUTPUTS[item["id"]].format(P=prefix) for item in triggered
        if item.get("id") in SPEC_OUTPUTS
    ]
    for key in ("open_docs", "decision_ref_docs"):
        values = config.get(key)
        if not isinstance(values, list) or any(
                not isinstance(value, str) or not value for value in values):
            raise ValueError(f"P0 config {key} must be an array of non-empty paths")
        retained = [value for value in values if value not in all_conditional]
        config[key] = retained + [value for value in required_conditional if value not in retained]
    text = json.dumps(config, ensure_ascii=False, indent=2) + "\n"
    unchanged = exists and path.read_text(encoding="utf-8-sig") == text
    return text, not unchanged


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-name", required=True)
    parser.add_argument("--prefix", required=True, type=valid_prefix)
    parser.add_argument("--project-root", type=Path, default=Path.cwd())
    parser.add_argument("--intake", type=Path, help="Approved intake JSON for Trigger Specs")
    parser.add_argument("--force", action="store_true", help="Overwrite existing scaffold files")
    args = parser.parse_args()

    project_root = args.project_root.resolve()
    intake_data: dict[str, Any] | None = None
    intake_text: str | None = None
    intake_rel = f"docs/{args.prefix}_intake.json"
    intake_destination = project_root / intake_rel
    if args.intake:
        try:
            intake_data = read_json(args.intake, "intake")
        except ValueError as exc:
            parser.error(str(exc))
        problems = validate_intake(
            intake_data, expected_project=args.project_name,
            expected_prefix=args.prefix, require_approved=True)
        if problems:
            parser.error("invalid approved intake:\n  - " + "\n  - ".join(problems))
        intake_text = json.dumps(intake_data, ensure_ascii=False, indent=2) + "\n"
        if intake_destination.exists() and not args.force:
            try:
                same_intake = read_json(intake_destination, "existing intake") == intake_data
            except ValueError:
                same_intake = False
            if not same_intake and not can_replace_intake_placeholder(
                    intake_destination, args.project_name, args.prefix):
                parser.error(
                    f"refusing to overwrite existing canonical intake: {intake_destination}; "
                    "use --force only after reviewing the canonical replacement")

    manifest_rel = f"docs/{args.prefix}_docs_manifest.json"
    manifest_path = project_root / manifest_rel
    existing_manifest: dict[str, Any] | None = None
    if manifest_path.exists():
        try:
            loaded_manifest = read_json(manifest_path, "existing manifest")
        except ValueError as exc:
            parser.error(str(exc))
        if not isinstance(loaded_manifest, dict):
            parser.error("existing manifest root must be an object")
        existing_manifest = loaded_manifest
        if (existing_manifest.get("project") != args.project_name
                or existing_manifest.get("prefix") != args.prefix):
            parser.error("existing manifest project/prefix does not match requested identity")

    # Preflight every bundled source before mutating the project.
    triggered = detect(intake_data) if intake_data is not None else []
    source_paths = [TEMPLATES / name for name, _, _ in CORE_DOCS]
    source_paths.extend(TEMPLATES / name for name, _ in ROOT_DOCS)
    source_paths.extend(
        source for source in SCHEMAS.iterdir()
        if source.name not in OPERATOR_ONLY_SCHEMAS)
    source_paths.extend(TEMPLATES / item["template"] for item in triggered)
    for source in source_paths:
        if not source.is_file():
            parser.error(f"bundled scaffold source is missing: {source}")

    p0_config_path = project_root / ".claude" / "p0-check.json"
    p0_config_text: str | None = None
    p0_config_write = False
    if (TEMPLATES / "p0-check.json").is_file() and (
            intake_data is not None or args.force or not p0_config_path.exists()):
        try:
            p0_config_text, p0_config_write = reconcile_p0_config(
                p0_config_path, args.project_name, args.prefix, triggered, args.force)
        except ValueError as exc:
            parser.error(str(exc))

    project_root.mkdir(parents=True, exist_ok=True)
    created: list[str] = []
    skipped: list[str] = []
    manifest_docs: list[dict[str, Any]] = []

    core_phase = {
        "intake.json": "D0", "gdd.md": "D1",
        "detailed_design.md": "D2", "data_definition.md": "D2",
        "ui_ux_input_spec.md": "D2", "toolchain_spec.md": "D2",
        "phase_plan.md": "D3", "work_packages.md": "D3",
        "test_spec.md": "D3", "workflow.md": "D3",
        "release_rollback_runbook.md": "D3", "docs_index.md": "D0",
    }

    for template, output, domain in CORE_DOCS:
        rel = output.format(P=args.prefix)
        if template == "intake.json" and args.intake:
            manifest_docs.append(document_entry(
                rel, domain, phase="D0", status="approved",
                doc_id=f"{args.prefix}-INTAKE"))
            continue
        copy_template(template, project_root / rel, args.project_name, args.prefix, args.force, created, skipped)
        manifest_docs.append(document_entry(
            rel, domain, phase=core_phase[template],
            doc_id=f"{args.prefix}-{Path(rel).stem.upper()}"))

    for template, output in ROOT_DOCS:
        copy_template(template, project_root / output, args.project_name, args.prefix, args.force, created, skipped)
        manifest_docs.append(document_entry(
            output, "operating file", phase="D0",
            doc_id=f"{args.prefix}-OPS-{Path(output).stem}"))

    # Machine-readable starting points.
    trace_rel = f"docs/traceability/{args.prefix}_requirements.csv"
    safe_write(project_root / trace_rel, (SCHEMAS / "requirements.csv").read_text(encoding="utf-8"),
               args.force, created, skipped)
    manifest_docs.append(document_entry(
        trace_rel, "requirements traceability", phase="D3",
        doc_id=f"{args.prefix}-TRACEABILITY"))

    # Discover bundled schemas and initial instances.  New artifacts are picked
    # up automatically instead of requiring another hard-coded allowlist edit.
    for source in sorted(SCHEMAS.iterdir()):
        if not source.is_file() or source.name == "requirements.csv":
            continue
        if source.name in OPERATOR_ONLY_SCHEMAS:
            continue
        if source.name.endswith(".schema.json"):
            if source.name not in SCHEMA_PHASES:
                parser.error(
                    f"bundled schema has no explicit lifecycle phase: {source.name}")
            rel = f"docs/schemas/{source.name}"
            domain = "machine-readable schema"
            phase = SCHEMA_PHASES[source.name]
        elif source.suffix.lower() == ".json":
            if source.name not in INSTANCE_PHASES:
                parser.error(
                    f"bundled initial instance has no explicit lifecycle phase: {source.name}")
            rel = f"docs/schemas/{args.prefix}_{source.name}"
            domain = "machine-readable initial instance"
            phase = INSTANCE_PHASES[source.name]
        else:
            continue
        text = replace_tokens(source.read_text(encoding="utf-8"), args.project_name, args.prefix)
        safe_write(project_root / rel, text, args.force, created, skipped)
        manifest_docs.append(document_entry(
            rel, domain, phase=phase,
            doc_id=f"{args.prefix}-MACHINE-{source.name.upper()}"))

    # Validator configuration is part of the reproducible scaffold. P0 config
    # is committed with the intake-derived transaction below.
    for config_name in ("doc-lint.json",):
        source = TEMPLATES / config_name
        if not source.is_file():
            continue
        rel = f".claude/{config_name}"
        copy_template(config_name, project_root / rel, args.project_name, args.prefix,
                      args.force, created, skipped)
        manifest_docs.append(document_entry(
            rel, "validator configuration", phase="D0",
            doc_id=f"{args.prefix}-CONFIG-{Path(config_name).stem.upper()}"))
    if (TEMPLATES / "p0-check.json").is_file():
        rel = ".claude/p0-check.json"
        if not p0_config_write and p0_config_path.exists():
            skipped.append(str(p0_config_path))
        manifest_docs.append(document_entry(
            rel, "validator configuration", phase="D0",
            doc_id=f"{args.prefix}-CONFIG-P0-CHECK"))

    residual_rel = f"docs/{args.prefix}_residual_terms.txt"
    safe_write(project_root / residual_rel,
               "# One forbidden legacy term per line. Lines beginning with # are ignored.\n",
               args.force, created, skipped)
    manifest_docs.append(document_entry(
        residual_rel, "legacy-term denylist", phase="D0",
        doc_id=f"{args.prefix}-RESIDUAL-TERMS"))

    required_specs: list[dict[str, Any]] = triggered
    if intake_data is not None:
        for item in required_specs:
            spec_id = item["id"]
            output = SPEC_OUTPUTS[spec_id].format(P=args.prefix)
            template = item["template"]
            copy_template(template, project_root / output, args.project_name, args.prefix, args.force, created, skipped)
            manifest_docs.append(document_entry(
                output, spec_id, phase="D2", trigger=item["reason"],
                doc_id=f"{args.prefix}-SPEC-{spec_id.upper()}"))

    req_specs_rel = f"docs/{args.prefix}_required_specs.json"
    manifest_docs.append(document_entry(
        req_specs_rel, "trigger-derived required specifications", phase="D1.5",
        status="approved" if intake_data is not None else "draft",
        doc_id=f"{args.prefix}-REQUIRED-SPECS"))
    manifest_docs.append(document_entry(
        manifest_rel, "machine-readable document inventory", phase="D3",
        doc_id=f"{args.prefix}-DOCS-MANIFEST"))

    manifest_docs = [refresh_entry_from_disk(project_root, item) for item in manifest_docs]
    try:
        manifest = merge_manifest(
            existing_manifest, manifest_docs, args.project_name, args.prefix)
    except ValueError as exc:
        parser.error(str(exc))

    required_specs_text = json.dumps(
        {"schemaVersion": "1.0.0", "project": args.project_name, "prefix": args.prefix,
         "required_specs": required_specs}, ensure_ascii=False, indent=2) + "\n"
    req_specs_path = project_root / req_specs_rel
    transaction = {manifest_path: json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"}
    # Without an explicit intake, an existing trigger decision is canonical
    # state, not an empty value to regenerate over it.
    if intake_data is not None or args.force or not req_specs_path.exists():
        transaction[req_specs_path] = required_specs_text
    else:
        skipped.append(str(req_specs_path))
    if intake_text is not None:
        transaction[intake_destination] = intake_text
    if p0_config_text is not None and p0_config_write:
        transaction[p0_config_path] = p0_config_text
    try:
        atomic_write_many(transaction)
    except OSError as exc:
        parser.error(f"cannot atomically reconcile intake/required specs/manifest: {exc}")
    for path in transaction:
        label = str(path)
        if label not in created:
            created.append(label)

    (project_root / "docs/evidence").mkdir(parents=True, exist_ok=True)
    reconciled = [path.relative_to(project_root).as_posix() for path in transaction]
    print(json.dumps({"created": created, "skipped": skipped, "manifest": manifest_rel,
                      "reconciled": reconciled},
                     ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
