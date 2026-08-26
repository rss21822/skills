#!/usr/bin/env python3
"""Determine required Roblox domain specifications from an approved intake JSON.

Standard-library only. Writes JSON to stdout or --output.
"""
from __future__ import annotations

import argparse
import json
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
    parser.add_argument("intake", type=Path, help="Path to approved intake JSON")
    parser.add_argument("--output", type=Path, help="Optional output JSON path")
    args = parser.parse_args()

    try:
        data = json.loads(args.intake.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        parser.error(f"Cannot read intake JSON: {exc}")

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
