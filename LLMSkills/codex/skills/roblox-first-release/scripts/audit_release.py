"""Read-only consistency checks; not a Roblox API client or authorization engine."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import uuid


CHECKS = (
    "local_validation", "settings_saved", "source_language_consistent",
    "localization_registered", "translations_generated", "monetization_ready",
    "cleanup", "player_acceptance", "publication_eligibility", "compliance",
    "asset_rights", "asset_access", "public_saved",
)
PROFILES = {
    "create-roblox-private-experience": {"configuration-upload", "full-validation"},
    "prepare-roblox-private-production": {"configuration-upload", "full-validation"},
    "roblox-monetization-setup": {"setup"},
    "roblox-group-auto-localization": {"settings-only", "with-player"},
    "roblox-experience-launcher": {"scenario"},
    "roblox-purchase-revenue-check": {"read-only"},
}


def positive_id(value):
    return isinstance(value, int) and not isinstance(value, bool) and value > 0


def file_matches(path, expected):
    if not isinstance(path, str) or not Path(path).is_absolute():
        return False
    if not isinstance(expected, str) or not re.fullmatch(r"[a-fA-F0-9]{64}", expected):
        return False
    try:
        return hashlib.sha256(Path(path).read_bytes()).hexdigest() == expected.lower()
    except OSError:
        return False


def recorded(check, allow_na=False):
    return (
        check.get("status") in ({"confirmed", "not_applicable"} if allow_na else {"confirmed"})
        and isinstance(check.get("evidence"), str)
        and bool(check["evidence"].strip())
    )


def publication_matches(place):
    pub = place.get("published")
    return isinstance(pub, dict) and (
        isinstance(pub.get("uploaded_sha256"), str)
        and pub["uploaded_sha256"].lower() == place["sha256"].lower()
        and positive_id(pub.get("observed_version"))
        and (pub.get("response_version") is None or pub["response_version"] == pub["observed_version"])
        and bool(pub.get("evidence")) and bool(pub.get("observed_at"))
    )


def audit(data, stage):
    errors = []
    if stage not in {"preflight", "root", "finish", "public"}:
        raise ValueError("unsupported stage")
    if data.get("schema") != 1:
        errors.append("schema must be 1")
    try:
        uuid.UUID(data.get("run_id", ""))
    except (ValueError, AttributeError, TypeError):
        errors.append("run_id must be a valid UUID")
    target, observed = data["target"], data["observed"]
    requested, excluded = data["requested"], data["excluded"]
    for field in ("player", "public", "localization", "monetization"):
        if not isinstance(requested.get(field), bool):
            errors.append(f"requested.{field} must be bool")
    if "require_translation_generation" in requested and not isinstance(requested["require_translation_generation"], bool):
        errors.append("require_translation_generation must be bool")
    if target.get("environment") != "production-private":
        errors.append("target is not production-private")
    for field in ("owner_id", "universe_id", "root_place_id"):
        if not positive_id(target.get(field)) or not positive_id(observed.get(field)) or observed.get(field) != target.get(field):
            errors.append(f"unconfirmed target.{field}")
    if not observed.get("evidence") or not observed.get("observed_at"):
        errors.append("current target observation needs evidence and time")
    allowed_audience = {"Private"}
    if requested.get("public") and stage in {"finish", "public"}:
        allowed_audience.add("Public")
    if observed.get("audience") not in allowed_audience:
        errors.append("unexpected audience: do not widen or silently privatize")
    if target.get("universe_id") in excluded["universe_ids"]:
        errors.append("target Universe overlaps excluded environment")
    for item in data["inputs"]:
        if not file_matches(item.get("path"), item.get("sha256")):
            errors.append("input changed or missing: " + str(item.get("path")))
    if not data["inputs"]:
        errors.append("input snapshot is empty")
    for child in data["children"]:
        name, profile = child.get("name"), child.get("profile")
        if profile not in PROFILES.get(name, set()) or child.get("contract_accepted") is not True:
            errors.append("unsupported or conflicting child contract: " + str(name))
        if not file_matches(child.get("path"), child.get("accepted_sha256")):
            errors.append("child Skill changed or missing: " + str(name))
        if not requested.get("player") and (profile in {"full-validation", "with-player", "scenario"}):
            errors.append("child would run unrequested Player: " + str(name))
    places, ids = data["places"], []
    for place in places:
        pid = place.get("place_id")
        if not positive_id(pid) or pid in ids:
            errors.append("invalid or duplicate Place ID")
        ids.append(pid)
        if pid in excluded["place_ids"] or place.get("universe_id") != target.get("universe_id"):
            errors.append("Place belongs to wrong/excluded environment")
        if place.get("role") not in {"root", "child"}:
            errors.append("unknown Place role")
        if not file_matches(place.get("path"), place.get("sha256")):
            errors.append("artifact changed or missing: " + str(place.get("path")))
    roots = [p for p in places if p.get("role") == "root"]
    if len(roots) != 1 or roots[0].get("place_id") != target.get("root_place_id"):
        errors.append("exactly one matching root Place required")
    checks = data["checks"]
    for name in CHECKS:
        if checks[name].get("status") not in {"confirmed", "not_applicable", "pending", "failed", "unknown"}:
            errors.append("invalid check status: " + name)
    baseline = list(errors)
    config_checks = ["local_validation", "settings_saved", "cleanup"]
    if requested.get("localization"):
        config_checks += ["source_language_consistent", "localization_registered"]
    if requested.get("monetization"):
        config_checks += ["monetization_ready"]
    all_published = bool(places) and all(publication_matches(p) for p in places)
    config_complete = not baseline and all_published and all(recorded(checks[n]) for n in config_checks)
    translation_complete = not baseline and recorded(checks["translations_generated"])
    player_complete = config_complete and recorded(checks["player_acceptance"])
    public_checks = ["publication_eligibility", "compliance", "asset_rights", "asset_access"]
    public_ready = config_complete and all(recorded(checks[n], allow_na=n in {"asset_rights", "asset_access"}) for n in public_checks)
    if requested.get("player"):
        public_ready = public_ready and player_complete
    if requested.get("require_translation_generation"):
        public_ready = public_ready and translation_complete
    public_complete = requested.get("public") and public_ready and recorded(checks["public_saved"]) and observed.get("audience") == "Public"
    if stage == "root":
        if not recorded(checks["local_validation"]):
            errors.append("local validation not confirmed")
        if requested.get("localization") and not recorded(checks["source_language_consistent"]):
            errors.append("source language mismatch or unresolved")
        if not all(publication_matches(p) for p in places if p.get("role") == "child"):
            errors.append("child publication partial/unknown: stop root upload")
    if stage in {"finish", "public"}:
        for name in config_checks:
            if not recorded(checks[name]):
                errors.append("configuration check unresolved: " + name)
        if not all_published:
            errors.append("not all Place versions independently matched")
        if requested.get("player") and not player_complete:
            errors.append("requested Player acceptance incomplete")
        if requested.get("require_translation_generation") and not translation_complete:
            errors.append("requested translation generation incomplete")
    if stage == "public" or (stage == "finish" and requested.get("public")):
        if not requested.get("public"):
            errors.append("general public not requested")
        if not public_ready:
            errors.append("public readiness gates unresolved")
        if stage == "finish" and not public_complete:
            errors.append("requested general public save unconfirmed")
    return {
        "stage": stage, "errors": errors,
        "configuration_upload_complete": config_complete,
        "translation_generation": ("complete" if translation_complete else "incomplete") if requested.get("localization") else "not_requested",
        "player_acceptance": ("complete" if player_complete else "incomplete") if requested.get("player") else "not_requested",
        "public_ready": bool(requested.get("public") and public_ready),
        "general_public": ("complete" if public_complete else "incomplete") if requested.get("public") else "not_requested",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--stage", choices=("preflight", "root", "finish", "public"), required=True)
    args = parser.parse_args()
    try:
        with Path(args.manifest).open(encoding="utf-8-sig") as stream:
            result = audit(json.load(stream), args.stage)
    except (OSError, ValueError, KeyError, TypeError, AttributeError, IndexError) as exc:
        result = {"errors": ["invalid manifest: " + str(exc)]}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 1 if result["errors"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
