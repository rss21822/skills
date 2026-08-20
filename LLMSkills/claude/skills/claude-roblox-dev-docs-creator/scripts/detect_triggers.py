#!/usr/bin/env python3
"""Determine required Roblox domain specifications from an approved intake JSON.

Standard-library only. Writes JSON to stdout or --output.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import re
from pathlib import Path
from typing import Any

SPEC_MAP = {
    "repository_audit": "repository_audit.md",
    "feasibility_report": "feasibility_report.md",
    "network_security": "network_security_spec.md",
    "persistence_migration": "persistence_migration_spec.md",
    "commerce_policy": "commerce_policy_spec.md",
    "paid_random_items": "paid_random_items_annex.md",
    "analytics_observability": "analytics_observability_spec.md",
    "performance_budget": "performance_budget_spec.md",
    "asset_content_pipeline": "asset_content_pipeline_spec.md",
    "multi_place_matchmaking": "multi_place_matchmaking_spec.md",
    "physics_control": "physics_control_spec.md",
    "ugc_moderation": "ugc_moderation_spec.md",
    "localization_accessibility": "localization_accessibility_spec.md",
    "liveops_content": "liveops_content_spec.md",
    "external_services_secrets": "external_services_secrets_spec.md",
    "rights_provenance": "rights_provenance_ledger.md",
}

PREFIX_RE = re.compile(r"^[A-Z0-9]{2,6}$")
INTAKE_MODES = {"greenfield", "brownfield", "audit", "sub-spec"}
ANSWER_IDS = tuple(
    [f"D0-A{number:02d}" for number in range(1, 13)]
    + [f"D0-B{number:02d}" for number in range(1, 16)])
ANSWER_STATUSES = {"unanswered", "fact", "proposed", "approved"}
ANSWER_SOURCES = {"U", "W", "M", "J"}
ROOT_KEYS = {
    "schemaVersion", "project", "answers", "fieldSources", "product", "technical", "state",
}
PROJECT_KEYS = {"name", "prefix", "mode", "owner"}
ANSWER_KEYS = {"prompt", "value", "status", "source", "evidence", "approvedBy", "approvedAt"}
PRODUCT_KEYS = {
    "one_sentence", "primary_action", "reference_games", "unique_axes",
    "round_minutes", "session_minutes", "meta_loop", "monetization",
    "ip_risks", "top_risks", "mvp_questions", "non_goals",
}
TECHNICAL_KEYS = {
    "existing_repository", "toolchain", "multi_place", "reserved_servers", "teleport",
    "multiplayer", "pvp", "persistent_data", "commerce", "analytics", "mobile",
    "controller", "localization", "liveops", "external_services", "free_text_or_ugc",
    "vehicle_or_custom_physics", "high_npc_or_fx_load", "real_world_ip_or_history",
    "priority_devices", "priority_locales", "minimum_fps",
}
FIELD_SOURCE_KEYS = {
    "product.one_sentence", "product.primary_action", "product.reference_games",
    "product.unique_axes", "product.round_minutes", "product.session_minutes",
    "product.meta_loop", "product.monetization.enabled",
    "product.monetization.paid_random_items", "product.monetization.trading",
    "product.monetization.p2w_allowed", "product.ip_risks", "product.top_risks",
    "product.mvp_questions", "product.non_goals",
} | {f"technical.{key}" for key in TECHNICAL_KEYS}


def _nonempty_string(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _timezone_datetime(value: Any) -> bool:
    if not _nonempty_string(value):
        return False
    raw = value.strip()
    try:
        parsed = dt.datetime.fromisoformat(raw[:-1] + "+00:00" if raw.endswith("Z") else raw)
    except ValueError:
        return False
    return parsed.tzinfo is not None and parsed.utcoffset() is not None


def validate_intake(
        data: Any, *, expected_project: str | None = None,
        expected_prefix: str | None = None, require_approved: bool = True) -> list[str]:
    """Validate the standard-library subset of ``intake.schema.json``.

    The CLI must fail closed even when the optional ``jsonschema`` package is not
    installed.  Identity and approval checks are deliberately stricter than the
    structural schema because trigger generation makes the intake canonical.
    """
    errors: list[str] = []
    if not isinstance(data, dict):
        return ["intake root must be an object"]

    root_extras = sorted(set(data) - ROOT_KEYS)
    if root_extras:
        errors.append(f"intake contains unknown keys: {', '.join(root_extras)}")

    if data.get("schemaVersion") != "1.0.0":
        errors.append("schemaVersion must be 1.0.0")
    for key in ("project", "answers", "fieldSources", "product", "technical", "state"):
        if not isinstance(data.get(key), dict):
            errors.append(f"{key} must be an object")

    project = data.get("project") if isinstance(data.get("project"), dict) else {}
    state = data.get("state") if isinstance(data.get("state"), dict) else {}
    name = project.get("name")
    prefix = project.get("prefix")
    mode = project.get("mode")
    project_extras = sorted(set(project) - PROJECT_KEYS)
    if project_extras:
        errors.append(f"project contains unknown keys: {', '.join(project_extras)}")
    if not _nonempty_string(name):
        errors.append("project.name must be a non-empty string")
    if not isinstance(prefix, str) or PREFIX_RE.fullmatch(prefix) is None:
        errors.append("project.prefix must be 2-6 uppercase ASCII letters/numbers")
    if mode not in INTAKE_MODES:
        errors.append("project.mode must be greenfield, brownfield, audit, or sub-spec")
    if not _nonempty_string(project.get("owner")):
        errors.append("project.owner must be a non-empty string")

    if expected_project is not None and name != expected_project:
        errors.append(
            f"project.name {name!r} does not match --project-name {expected_project!r}")
    if expected_prefix is not None and prefix != expected_prefix:
        errors.append(
            f"project.prefix {prefix!r} does not match --prefix {expected_prefix!r}")

    answers = data.get("answers") if isinstance(data.get("answers"), dict) else {}
    for answer_id in ANSWER_IDS:
        answer = answers.get(answer_id)
        if not isinstance(answer, dict):
            errors.append(f"answers.{answer_id} must be an object")
            continue
        answer_extras = sorted(set(answer) - ANSWER_KEYS)
        if answer_extras:
            errors.append(
                f"answers.{answer_id} contains unknown keys: {', '.join(answer_extras)}")
        if not _nonempty_string(answer.get("prompt")):
            errors.append(f"answers.{answer_id}.prompt must be a non-empty string")
        if "value" not in answer:
            errors.append(f"answers.{answer_id}.value is required")
        status = answer.get("status")
        source = answer.get("source")
        evidence = answer.get("evidence")
        approved_by = answer.get("approvedBy")
        approved_at = answer.get("approvedAt")
        if status not in ANSWER_STATUSES:
            errors.append(f"answers.{answer_id}.status is invalid")
            continue
        if not isinstance(evidence, list) or any(
                not _nonempty_string(item) for item in evidence):
            errors.append(f"answers.{answer_id}.evidence must be an array of non-empty strings")
            evidence = []
        if status == "unanswered":
            if answer.get("value") is not None:
                errors.append(f"answers.{answer_id}.value must be null when unanswered")
            if source is not None:
                errors.append(f"answers.{answer_id}.source must be null when unanswered")
            if evidence:
                errors.append(f"answers.{answer_id}.evidence must be empty when unanswered")
        else:
            if source not in ANSWER_SOURCES:
                errors.append(f"answers.{answer_id}.source must be U, W, M, or J")
            if not evidence:
                errors.append(f"answers.{answer_id}.evidence requires at least one item")
            if answer.get("value") is None:
                errors.append(f"answers.{answer_id}.value must be non-null when answered")
        if status == "approved":
            if not _nonempty_string(approved_by):
                errors.append(f"answers.{answer_id}.approvedBy must be non-empty when approved")
            if not _timezone_datetime(approved_at):
                errors.append(f"answers.{answer_id}.approvedAt must be a timezone timestamp when approved")
        elif approved_by is not None or approved_at is not None:
            errors.append(
                f"answers.{answer_id}.approvedBy/approvedAt must be null unless approved")

    extras = sorted(set(answers) - set(ANSWER_IDS))
    if extras:
        errors.append(f"answers contains unknown IDs: {', '.join(extras)}")

    field_sources = data.get("fieldSources") \
        if isinstance(data.get("fieldSources"), dict) else {}
    missing_sources = sorted(FIELD_SOURCE_KEYS - set(field_sources))
    extra_sources = sorted(set(field_sources) - FIELD_SOURCE_KEYS)
    if missing_sources:
        errors.append(f"fieldSources is missing keys: {', '.join(missing_sources)}")
    if extra_sources:
        errors.append(f"fieldSources contains unknown keys: {', '.join(extra_sources)}")
    for leaf in sorted(FIELD_SOURCE_KEYS & set(field_sources)):
        refs = field_sources[leaf]
        if (not isinstance(refs, list) or not refs
                or any(ref not in ANSWER_IDS for ref in refs)
                or len(refs) != len(set(refs))):
            errors.append(
                f"fieldSources.{leaf} must be a non-empty unique array of known D0 answer IDs")

    product = data.get("product") if isinstance(data.get("product"), dict) else {}
    product_extras = sorted(set(product) - PRODUCT_KEYS)
    if product_extras:
        errors.append(f"product contains unknown keys: {', '.join(product_extras)}")
    missing_product = sorted(PRODUCT_KEYS - set(product))
    if missing_product:
        errors.append(f"product is missing keys: {', '.join(missing_product)}")
    for key in ("one_sentence", "primary_action", "meta_loop"):
        if key in product and not isinstance(product[key], str):
            errors.append(f"product.{key} must be a string")
    for key in ("reference_games", "unique_axes", "ip_risks", "top_risks",
                "mvp_questions", "non_goals"):
        value = product.get(key)
        if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
            errors.append(f"product.{key} must be an array of strings")
    if isinstance(product.get("unique_axes"), list) and len(product["unique_axes"]) > 3:
        errors.append("product.unique_axes may contain at most three items")
    for key in ("round_minutes", "session_minutes"):
        value = product.get(key)
        if value is not None and (not isinstance(value, (int, float))
                                  or isinstance(value, bool) or value <= 0):
            errors.append(f"product.{key} must be null or a positive number")
    monetization = product.get("monetization")
    monet_keys = {"enabled", "paid_random_items", "trading", "p2w_allowed"}
    if not isinstance(monetization, dict) or set(monetization) != monet_keys \
            or any(not isinstance(monetization.get(key), bool) for key in monet_keys):
        errors.append("product.monetization must contain exactly four boolean policy fields")

    technical = data.get("technical") if isinstance(data.get("technical"), dict) else {}
    technical_extras = sorted(set(technical) - TECHNICAL_KEYS)
    if technical_extras:
        errors.append(f"technical contains unknown keys: {', '.join(technical_extras)}")
    missing_technical = sorted(TECHNICAL_KEYS - set(technical))
    if missing_technical:
        errors.append(f"technical is missing keys: {', '.join(missing_technical)}")
    boolean_keys = TECHNICAL_KEYS - {"toolchain", "priority_devices", "priority_locales", "minimum_fps"}
    for key in boolean_keys:
        if key in technical and not isinstance(technical[key], bool):
            errors.append(f"technical.{key} must be boolean")
    if not _nonempty_string(technical.get("toolchain")):
        errors.append("technical.toolchain must be a non-empty string")
    for key in ("priority_devices", "priority_locales"):
        value = technical.get(key)
        minimum = 1 if key == "priority_devices" else 0
        if (not isinstance(value, list) or len(value) < minimum
                or any(not _nonempty_string(item) for item in value)
                or len(value) != len(set(value))):
            errors.append(f"technical.{key} must be a unique array of non-empty strings")
    if isinstance(technical.get("priority_locales"), list) and any(
            isinstance(item, str) and len(item) < 2
            for item in technical["priority_locales"]):
        errors.append("technical.priority_locales items must contain at least two characters")
    minimum_fps = technical.get("minimum_fps")
    if not isinstance(minimum_fps, int) or isinstance(minimum_fps, bool) or minimum_fps < 1:
        errors.append("technical.minimum_fps must be a positive integer")

    approved = state.get("approved")
    if not isinstance(approved, bool):
        errors.append("state.approved must be boolean")
    if require_approved and approved is not True:
        errors.append("state.approved must be true")
    if approved is True and not _nonempty_string(state.get("approved_by")):
        errors.append("state.approved_by must be a non-empty string")
    if approved is True and not _timezone_datetime(state.get("approved_at")):
        errors.append("state.approved_at must be an ISO-8601 timestamp with timezone")
    state_keys = {"approved", "approved_by", "approved_at", "approval_evidence"}
    state_extras = sorted(set(state) - state_keys)
    if state_extras:
        errors.append(f"state contains unknown keys: {', '.join(state_extras)}")
    if set(state) != state_keys:
        errors.append("state must contain approved, approved_by, approved_at, and approval_evidence")
    approval_evidence = state.get("approval_evidence")
    if approved is True and not _nonempty_string(approval_evidence):
        errors.append("state.approval_evidence must be non-empty")
    if approved is True:
        for answer_id in ANSWER_IDS:
            answer = answers.get(answer_id)
            if isinstance(answer, dict) and answer.get("status") not in {"fact", "approved"}:
                errors.append(
                    f"answers.{answer_id}.status must be fact or approved when state.approved is true")
            if (isinstance(answer, dict) and answer.get("source") == "J"
                    and answer.get("status") != "approved"):
                errors.append(
                    f"answers.{answer_id}: source J requires individual approved status "
                    "when state.approved is true")
        for leaf, refs in field_sources.items():
            if leaf not in FIELD_SOURCE_KEYS or not isinstance(refs, list):
                continue
            for answer_id in refs:
                answer = answers.get(answer_id) if isinstance(answer_id, str) else None
                if not isinstance(answer, dict) or answer.get("status") not in {"fact", "approved"} \
                        or answer.get("source") not in ANSWER_SOURCES \
                        or not isinstance(answer.get("evidence"), list) \
                        or not answer.get("evidence"):
                    errors.append(
                        f"fieldSources.{leaf} references ineligible answer {answer_id!r}")
        for key in ("one_sentence", "primary_action", "meta_loop"):
            if not _nonempty_string(product.get(key)):
                errors.append(f"product.{key} must be non-empty when state.approved is true")
        for key in ("round_minutes", "session_minutes"):
            value = product.get(key)
            if (not isinstance(value, (int, float)) or isinstance(value, bool)
                    or value <= 0):
                errors.append(f"product.{key} must be a positive number when approved")
        references = product.get("reference_games")
        if not isinstance(references, list) or not 2 <= len(references) <= 3 \
                or any(not _nonempty_string(item) for item in references):
            errors.append("product.reference_games requires 2-3 non-empty items when approved")
        axes = product.get("unique_axes")
        if not isinstance(axes, list) or not 1 <= len(axes) <= 3 \
                or any(not _nonempty_string(item) for item in axes):
            errors.append("product.unique_axes requires 1-3 non-empty items when approved")
        questions = product.get("mvp_questions")
        if not isinstance(questions, list) or len(questions) != 3 \
                or any(not _nonempty_string(item) for item in questions):
            errors.append("product.mvp_questions requires exactly 3 non-empty items when approved")
        if not _nonempty_string(technical.get("toolchain")) \
                or technical.get("toolchain", "").strip().lower() == "unknown":
            errors.append("technical.toolchain must be resolved when state.approved is true")
    elif approved is False and any(state.get(key) is not None for key in (
            "approved_by", "approved_at", "approval_evidence")):
        errors.append("unapproved state requires null approved_by/approved_at/approval_evidence")
    return errors


def nested(data: dict[str, Any], *keys: str, default: Any = None) -> Any:
    cur: Any = data
    for key in keys:
        if not isinstance(cur, dict) or key not in cur:
            return default
        cur = cur[key]
    return cur


def detect(data: dict[str, Any]) -> list[dict[str, str]]:
    tech = data.get("technical", {}) or {}
    product = data.get("product", {}) or {}
    monet = product.get("monetization", {}) or {}

    triggers: dict[str, str] = {}

    if bool(tech.get("existing_repository")):
        triggers["repository_audit"] = "existing repository is true"

    high_risk = any(
        bool(tech.get(k))
        for k in (
            "vehicle_or_custom_physics",
            "high_npc_or_fx_load",
            "free_text_or_ugc",
            "multi_place",
        )
    ) or bool(product.get("top_risks"))
    if high_risk:
        triggers["feasibility_report"] = "one or more high-risk mechanics or explicit top risks"

    if any(bool(tech.get(k)) for k in ("multiplayer", "pvp", "commerce", "persistent_data")):
        triggers["network_security"] = "multiplayer/PvP/economy/persistence requires trust boundaries"

    if bool(tech.get("persistent_data")):
        triggers["persistence_migration"] = "persistent data enabled"

    commerce = bool(tech.get("commerce")) or bool(monet.get("enabled"))
    if commerce:
        triggers["commerce_policy"] = "commerce or monetization enabled"

    if bool(monet.get("paid_random_items")):
        triggers["paid_random_items"] = "paid random items enabled"

    if bool(tech.get("analytics", True)):
        triggers["analytics_observability"] = "KPI/analytics enabled"

    if bool(tech.get("mobile", True)) or bool(tech.get("high_npc_or_fx_load")) or bool(tech.get("vehicle_or_custom_physics")):
        triggers["performance_budget"] = "mobile/high load/custom physics requires explicit budgets"

    # Every production game has assets; this is intentionally baseline.
    triggers["asset_content_pipeline"] = "all Roblox games require an asset provenance and budget pipeline"

    if any(bool(tech.get(k)) for k in ("multi_place", "reserved_servers", "teleport")):
        triggers["multi_place_matchmaking"] = "multi-place/reserved server/teleport enabled"

    if bool(tech.get("vehicle_or_custom_physics")):
        triggers["physics_control"] = "vehicle or custom physics/control enabled"

    if bool(tech.get("free_text_or_ugc")):
        triggers["ugc_moderation"] = "free text, drawing, UGC, or generative content enabled"

    if bool(tech.get("localization")) or len(tech.get("priority_locales", []) or []) > 1:
        triggers["localization_accessibility"] = "multiple locales/global launch"

    if bool(tech.get("liveops")):
        triggers["liveops_content"] = "seasons/events/live operations enabled"

    if bool(tech.get("external_services")):
        triggers["external_services_secrets"] = "external services or secrets enabled"

    if bool(tech.get("real_world_ip_or_history")) or bool(product.get("ip_risks")):
        triggers["rights_provenance"] = "real-world IP/history or recorded IP risks"

    return [
        {"id": key, "template": SPEC_MAP[key], "reason": reason}
        for key, reason in triggers.items()
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("intake", nargs="?", type=Path,
                        help="Path to approved intake JSON (positional compatibility form)")
    parser.add_argument("--intake", dest="intake_option", type=Path,
                        help="Path to approved intake JSON")
    parser.add_argument("--output", type=Path, help="Optional output JSON path")
    args = parser.parse_args()

    if args.intake is not None and args.intake_option is not None:
        parser.error("provide intake either positionally or with --intake, not both")
    intake_path = args.intake_option or args.intake
    if intake_path is None:
        parser.error("an intake path is required (positional or --intake)")

    try:
        data = json.loads(intake_path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        parser.error(f"Cannot read intake JSON: {exc}")

    problems = validate_intake(data)
    if problems:
        parser.error("Invalid approved intake:\n  - " + "\n  - ".join(problems))

    payload = {
        "project": nested(data, "project", "name", default=""),
        "prefix": nested(data, "project", "prefix", default=""),
        "required_specs": detect(data),
    }
    text = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8")
    else:
        print(text, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
