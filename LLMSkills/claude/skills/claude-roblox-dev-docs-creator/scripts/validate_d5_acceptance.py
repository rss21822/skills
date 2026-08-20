#!/usr/bin/env python3
"""Fail-closed D5/W0 acceptance validation.

Validates the handoff package, baseline promotion chain, post-sync hashes,
formal-document approval metadata, generated index/manifest agreement, three
post-P0 D4 audit tracks, distinct approval IDs, and the first authorized WP.
Standard-library only.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import re
import subprocess
from pathlib import Path
from typing import Any

import gen_index


SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
WP_STATUS_RE = re.compile(r"(?im)^\s*[-*]\s*Status\s*[:：]\s*`?Approved`?\s*$")
UNRESOLVED_RE = re.compile(r"\{\{[^}]+\}\}|TODO-UNRESOLVED")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def timezone_datetime(value: Any) -> bool:
    if not isinstance(value, str) or not value.strip():
        return False
    raw = value.strip()
    try:
        parsed = dt.datetime.fromisoformat(raw[:-1] + "+00:00" if raw.endswith("Z") else raw)
    except ValueError:
        return False
    return parsed.tzinfo is not None and parsed.utcoffset() is not None


def manifest_status(raw: Any, path: str, errors: list[str]) -> str | None:
    try:
        return gen_index.normalize_status(raw if isinstance(raw, str) else "", path)
    except SystemExit as exc:
        errors.append(str(exc))
        return None


def load_json(path: Path, errors: list[str], label: str) -> dict[str, Any] | None:
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        errors.append(f"{label}: cannot read JSON {path}: {exc}")
        return None
    if not isinstance(value, dict):
        errors.append(f"{label}: root must be an object: {path}")
        return None
    return value


def resolve_path(root: Path, raw: Any, errors: list[str], label: str) -> Path | None:
    if not isinstance(raw, str) or not raw.strip():
        errors.append(f"{label}: path must be a non-empty relative string")
        return None
    rel = Path(raw)
    if rel.is_absolute():
        errors.append(f"{label}: absolute path is forbidden: {raw}")
        return None
    candidate = (root / rel).resolve()
    try:
        candidate.relative_to(root)
    except ValueError:
        errors.append(f"{label}: path escapes project root: {raw}")
        return None
    return candidate


def verify_ref(
        root: Path, ref: Any, errors: list[str], label: str) -> tuple[Path, dict[str, Any]] | None:
    if not isinstance(ref, dict):
        errors.append(f"{label}: reference must be an object")
        return None
    path = resolve_path(root, ref.get("path"), errors, label)
    expected_hash = ref.get("sha256")
    if path is None:
        return None
    if not path.is_file():
        errors.append(f"{label}: referenced file does not exist: {ref.get('path')}")
        return None
    if not isinstance(expected_hash, str) or SHA256_RE.fullmatch(expected_hash) is None:
        errors.append(f"{label}: sha256 must be 64 lowercase hex characters")
    else:
        actual = sha256(path)
        if actual != expected_hash:
            errors.append(f"{label}: sha256 mismatch for {ref.get('path')}: {actual}")
    data = load_json(path, errors, label)
    return (path, data) if data is not None else None


def verify_file_hash(
        root: Path, raw_path: Any, expected_hash: Any,
        errors: list[str], label: str) -> Path | None:
    path = resolve_path(root, raw_path, errors, label)
    if path is None:
        return None
    if not path.is_file():
        errors.append(f"{label}: referenced file does not exist: {raw_path}")
        return None
    if not isinstance(expected_hash, str) or SHA256_RE.fullmatch(expected_hash) is None:
        errors.append(f"{label}: sha256 must be 64 lowercase hex characters")
    elif sha256(path) != expected_hash:
        errors.append(f"{label}: sha256 mismatch for {raw_path}")
    return path


def canonical_file_set_hash(files: list[Any]) -> str:
    payload = json.dumps(files, ensure_ascii=False, sort_keys=True,
                         separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def historical_bytes(
        root: Path, source_root: Path, revision: Any, rel: str,
        errors: list[str], label: str) -> bytes | None:
    if not isinstance(revision, dict):
        errors.append(f"{label}: revision must be an object")
        return None
    kind, value = revision.get("kind"), revision.get("value")
    if kind == "commit":
        if not isinstance(value, str) or re.fullmatch(r"[a-f0-9]{40}(?:[a-f0-9]{24})?", value) is None:
            errors.append(f"{label}: commit revision must be a full 40/64-hex object ID")
            return None
        try:
            result = subprocess.run(
                ["git", "-C", str(source_root), "show", f"{value}:{rel}"],
                capture_output=True, timeout=20)
        except (OSError, subprocess.SubprocessError) as exc:
            errors.append(f"{label}: cannot read commit snapshot: {exc}")
            return None
        if result.returncode != 0:
            errors.append(f"{label}: git object is unavailable for {value}:{rel}")
            return None
        return result.stdout
    if kind == "snapshot":
        def evidence_path(raw: Any, part: str) -> Path | None:
            for base in dict.fromkeys((root, source_root)):
                local_errors: list[str] = []
                candidate = resolve_path(base, raw, local_errors, f"{label}.{part}")
                if candidate is not None and candidate.exists():
                    return candidate
            return resolve_path(root, raw, errors, f"{label}.{part}")

        snapshot_root = evidence_path(revision.get("snapshotRoot"), "snapshotRoot")
        evidence = evidence_path(revision.get("gitStatusEvidence"), "gitStatusEvidence")
        if evidence is not None and not evidence.is_file():
            errors.append(f"{label}: gitStatusEvidence is missing")
        if snapshot_root is None or not snapshot_root.is_dir():
            if snapshot_root is not None:
                errors.append(f"{label}: immutable snapshotRoot is missing")
            return None
        candidate = (snapshot_root / Path(rel)).resolve()
        try:
            candidate.relative_to(snapshot_root)
        except ValueError:
            errors.append(f"{label}: snapshot member escapes snapshotRoot: {rel}")
            return None
        try:
            return candidate.read_bytes()
        except OSError as exc:
            errors.append(f"{label}: snapshot member cannot be read: {rel}: {exc}")
            return None
    errors.append(f"{label}: revision.kind must be commit or snapshot")
    return None


def verify_historical_files(
        root: Path, source_root: Path, manifest: dict[str, Any],
        records: dict[str, dict[str, Any]],
        errors: list[str], label: str) -> dict[str, bytes]:
    content: dict[str, bytes] = {}
    revision = manifest.get("revision")
    for rel, item in records.items():
        data = historical_bytes(root, source_root, revision, rel, errors, f"{label}:{rel}")
        if data is None:
            continue
        content[rel] = data
        if item.get("bytes") != len(data):
            errors.append(f"{label}:{rel}: historical byte count mismatch")
        actual = hashlib.sha256(data).hexdigest()
        if item.get("sha256") != actual:
            errors.append(f"{label}:{rel}: historical sha256 mismatch: {actual}")
    return content


def validate_file_records(
        root: Path, manifest: dict[str, Any], errors: list[str], label: str,
        verify_current: bool, require_file_set_hash: bool = True) -> dict[str, dict[str, Any]]:
    files = manifest.get("files")
    if not isinstance(files, list) or not files:
        errors.append(f"{label}.files must be a non-empty array")
        return {}
    paths = [item.get("path") if isinstance(item, dict) else None for item in files]
    if any(not isinstance(path, str) or not path for path in paths):
        errors.append(f"{label}.files entries require a non-empty path")
    if len(paths) != len(set(paths)):
        errors.append(f"{label}.files contains duplicate paths")
    if all(isinstance(path, str) for path in paths) and paths != sorted(paths):
        errors.append(f"{label}.files must be sorted by path for canonical hashing")
    if require_file_set_hash:
        expected_set_hash = manifest.get("fileSetSha256")
        actual_set_hash = canonical_file_set_hash(files)
        if expected_set_hash != actual_set_hash:
            errors.append(f"{label}.fileSetSha256 mismatch: calculated {actual_set_hash}")

    result: dict[str, dict[str, Any]] = {}
    for index, item in enumerate(files):
        row_label = f"{label}.files[{index}]"
        if not isinstance(item, dict):
            errors.append(f"{row_label} must be an object")
            continue
        if set(item) != {"path", "bytes", "sha256", "version", "status"}:
            errors.append(f"{row_label}: unknown/missing fields")
        raw_path = item.get("path")
        if not isinstance(raw_path, str) or not raw_path:
            continue
        result[raw_path] = item
        expected_bytes = item.get("bytes")
        expected_hash = item.get("sha256")
        if not isinstance(expected_bytes, int) or expected_bytes < 0:
            errors.append(f"{row_label}.bytes must be a non-negative integer")
        if not isinstance(expected_hash, str) or SHA256_RE.fullmatch(expected_hash) is None:
            errors.append(f"{row_label}.sha256 must be 64 lowercase hex characters")
        version = item.get("version")
        if version is not None and (not isinstance(version, str) or not version):
            errors.append(f"{row_label}.version must be non-empty string or null")
        if item.get("status") not in {"draft", "review", "approved", "superseded", None}:
            errors.append(f"{row_label}.status is invalid")
        if not verify_current:
            continue
        path = resolve_path(root, raw_path, errors, row_label)
        if path is None or not path.is_file():
            if path is not None:
                errors.append(f"{row_label}: current file is missing")
            continue
        actual_bytes = path.stat().st_size
        actual_hash = sha256(path)
        if expected_bytes != actual_bytes:
            errors.append(f"{row_label}: byte count {expected_bytes!r} != current {actual_bytes}")
        if expected_hash != actual_hash:
            errors.append(f"{row_label}: sha256 {expected_hash!r} != current {actual_hash}")
    return result


def validate_post_sync_records(
        root: Path, manifest: dict[str, Any], errors: list[str]) -> dict[str, dict[str, Any]]:
    """Validate the deliberately smaller post-sync ``files`` record shape."""
    files = manifest.get("files")
    if not isinstance(files, list) or not files:
        errors.append("postSyncManifest.files must be a non-empty array")
        return {}
    result: dict[str, dict[str, Any]] = {}
    paths: list[str] = []
    for index, item in enumerate(files):
        label = f"postSyncManifest.files[{index}]"
        if not isinstance(item, dict):
            errors.append(f"{label} must be an object")
            continue
        if set(item) != {"path", "bytes", "sha256"}:
            errors.append(f"{label}: unknown/missing fields")
        rel = item.get("path")
        if not isinstance(rel, str) or not rel:
            errors.append(f"{label}.path must be non-empty")
            continue
        paths.append(rel)
        if rel in result:
            errors.append(f"postSyncManifest.files contains duplicate path: {rel}")
        result[rel] = item
        path = resolve_path(root, rel, errors, label)
        if path is None or not path.is_file():
            if path is not None:
                errors.append(f"{label}: synchronized file is missing")
            continue
        expected_bytes = item.get("bytes")
        expected_hash = item.get("sha256")
        if not isinstance(expected_bytes, int) or isinstance(expected_bytes, bool) \
                or expected_bytes < 0:
            errors.append(f"{label}.bytes must be a non-negative integer")
        elif expected_bytes != path.stat().st_size:
            errors.append(f"{label}: byte count mismatch")
        if not isinstance(expected_hash, str) or SHA256_RE.fullmatch(expected_hash) is None:
            errors.append(f"{label}.sha256 must be 64 lowercase hex characters")
        elif expected_hash != sha256(path):
            errors.append(f"{label}: sha256 mismatch")
    if paths != sorted(paths):
        errors.append("postSyncManifest.files must be sorted by path")
    return result


def validate_baseline_audits(
        root: Path, audits: Any, stage: Any, promoted_from: Any,
        baseline_file_set: Any, errors: list[str], label: str) -> None:
    if not isinstance(audits, list):
        errors.append(f"{label}.auditRecords must be an array")
        return
    if stage not in {"B0", "B1", "B2"}:
        if audits:
            errors.append(f"{label}.auditRecords must be empty for a candidate")
        return
    tracks = {"consistency", "roblox-readiness", "clean-room"}
    expected_candidate_pattern = (
        r"D4-CAND-[A-Z0-9][A-Z0-9._-]*" if stage == "B0"
        else r"P0-CAND-[A-Z0-9][A-Z0-9._-]*"
    )
    seen: set[str] = set()
    candidate_refs: list[dict[str, Any]] = []
    if len(audits) != 3:
        errors.append(f"{label}.auditRecords must contain exactly three records")
    for index, record in enumerate(audits):
        row_label = f"{label}.auditRecords[{index}]"
        if not isinstance(record, dict):
            errors.append(f"{row_label} must be an object")
            continue
        allowed = {
            "id", "auditTrack", "path", "sha256", "candidateBaseline",
            "criticalCount", "majorCount", "verdict",
        }
        if set(record) != allowed:
            errors.append(f"{row_label}: unknown/missing fields")
        track = record.get("auditTrack")
        if track not in tracks or track in seen:
            errors.append(f"{row_label}.auditTrack is invalid or duplicated")
        if isinstance(track, str):
            seen.add(track)
        if not isinstance(record.get("id"), str) or not record["id"].strip():
            errors.append(f"{row_label}.id must be non-empty")
        if record.get("criticalCount") != 0 or record.get("majorCount") != 0 \
                or record.get("verdict") != "pass":
            errors.append(f"{row_label}: only Critical 0 / Major 0 / pass can be promoted")
        candidate_ref = record.get("candidateBaseline")
        if not isinstance(candidate_ref, dict) or set(candidate_ref) != {
                "id", "path", "sha256", "fileSetSha256"}:
            errors.append(f"{row_label}.candidateBaseline has unknown/missing fields")
            continue
        candidate_refs.append(candidate_ref)
        if not isinstance(candidate_ref.get("id"), str) or re.fullmatch(
                expected_candidate_pattern, candidate_ref["id"]) is None:
            errors.append(f"{row_label}.candidateBaseline.id has the wrong lifecycle stage")
        if stage in {"B0", "B1"}:
            if candidate_ref.get("id") != promoted_from:
                errors.append(
                    f"{row_label}.candidateBaseline.id must equal {label}.promotedFrom")
            if candidate_ref.get("fileSetSha256") != baseline_file_set:
                errors.append(
                    f"{row_label}.candidateBaseline.fileSetSha256 must equal {label}")
        loaded = verify_ref(root, candidate_ref, errors, f"{row_label}.candidateBaseline")
        if loaded is not None:
            candidate = loaded[1]
            expected_stage = "D4-CANDIDATE" if stage == "B0" else "P0-CANDIDATE"
            if candidate.get("stage") != expected_stage \
                    or candidate.get("baselineId") != candidate_ref.get("id"):
                errors.append(f"{row_label}: candidate manifest identity/stage mismatch")
            if candidate.get("fileSetSha256") != candidate_ref.get("fileSetSha256"):
                errors.append(f"{row_label}: candidate fileSetSha256 mismatch")
        raw_path = verify_file_hash(
            root, record.get("path"), record.get("sha256"), errors, row_label)
        if raw_path is not None:
            parse_d4_record(raw_path, record, candidate_ref, errors, row_label)
    if seen != tracks:
        errors.append(f"{label}.auditRecords must cover all three D4 tracks")
    if candidate_refs and any(ref != candidate_refs[0] for ref in candidate_refs[1:]):
        errors.append(f"{label}.auditRecords must reference one exact candidate")


def validate_baseline(
        root: Path, source_root: Path, data: dict[str, Any], errors: list[str], label: str,
        expected_stage: str, expected_id: Any, project: str, prefix: str,
        verify_current: bool,
        historical_content: dict[str, bytes] | None = None) -> dict[str, dict[str, Any]]:
    if data.get("schemaVersion") != "1.0.0":
        errors.append(f"{label}.schemaVersion must be 1.0.0")
    if data.get("stage") != expected_stage:
        errors.append(f"{label}.stage must be {expected_stage}")
    if data.get("baselineId") != expected_id:
        errors.append(f"{label}.baselineId does not match package reference")
    if data.get("project") != project or data.get("prefix") != prefix:
        errors.append(f"{label}: project/prefix identity mismatch")
    if not timezone_datetime(data.get("createdAt")):
        errors.append(f"{label}.createdAt must be an ISO-8601 timestamp with timezone")
    expected_keys = {
        "schemaVersion", "baselineId", "stage", "project", "prefix", "createdAt",
        "revision", "parentBaselineId", "promotedFrom", "approvalId",
        "fileSetSha256", "files", "auditRecords",
    }
    if set(data) != expected_keys:
        errors.append(f"{label}: unknown/missing baseline fields")
    revision = data.get("revision")
    if not isinstance(revision, dict) or set(revision) != {
            "kind", "value", "snapshotRoot", "gitStatusEvidence"}:
        errors.append(f"{label}.revision has unknown/missing fields")
    else:
        kind, revision_value = revision.get("kind"), revision.get("value")
        if kind == "commit":
            if not isinstance(revision_value, str) or re.fullmatch(
                    r"[a-f0-9]{40}(?:[a-f0-9]{24})?", revision_value) is None:
                errors.append(f"{label}.revision.value must be a full commit object ID")
            if revision.get("snapshotRoot") is not None:
                errors.append(f"{label}.revision.snapshotRoot must be null for commit")
            if revision.get("gitStatusEvidence") is not None and not isinstance(
                    revision.get("gitStatusEvidence"), str):
                errors.append(f"{label}.revision.gitStatusEvidence must be string or null")
        elif kind == "snapshot":
            for key in ("value", "snapshotRoot", "gitStatusEvidence"):
                if not isinstance(revision.get(key), str) or not revision[key].strip():
                    errors.append(f"{label}.revision.{key} must be non-empty for snapshot")
        else:
            errors.append(f"{label}.revision.kind must be commit or snapshot")
    stage = data.get("stage")
    baseline_id = data.get("baselineId")
    parent = data.get("parentBaselineId")
    promoted = data.get("promotedFrom")
    approval = data.get("approvalId")
    id_patterns = {
        "D4-CANDIDATE": r"D4-CAND-[A-Z0-9][A-Z0-9._-]*",
        "P0-CANDIDATE": r"P0-CAND-[A-Z0-9][A-Z0-9._-]*",
        "B0": r"B0-[A-Z0-9][A-Z0-9._-]*",
        "B1": r"B1-[A-Z0-9][A-Z0-9._-]*",
        "B2": r"B2-[A-Z0-9][A-Z0-9._-]*",
    }
    if not isinstance(baseline_id, str) or re.fullmatch(id_patterns.get(stage, r"(?!)"), baseline_id) is None:
        errors.append(f"{label}.baselineId does not match stage")
    if stage == "D4-CANDIDATE" and (parent is not None or promoted is not None or approval is not None):
        errors.append(f"{label}: D4 candidate parent/promotedFrom/approvalId must be null")
    elif stage == "P0-CANDIDATE":
        if not isinstance(parent, str) or re.fullmatch(id_patterns["B0"], parent) is None \
                or promoted is not None or approval is not None:
            errors.append(f"{label}: invalid P0 candidate temporal fields")
    elif stage == "B0":
        if parent is not None or not isinstance(promoted, str) \
                or re.fullmatch(id_patterns["D4-CANDIDATE"], promoted) is None or approval is not None:
            errors.append(f"{label}: invalid B0 temporal fields")
    elif stage == "B1":
        if not isinstance(parent, str) or re.fullmatch(id_patterns["B0"], parent) is None \
                or not isinstance(promoted, str) \
                or re.fullmatch(id_patterns["P0-CANDIDATE"], promoted) is None or approval is not None:
            errors.append(f"{label}: invalid B1 temporal fields")
    elif stage == "B2":
        if not isinstance(parent, str) or re.fullmatch(id_patterns["B1"], parent) is None \
                or promoted is not None or not isinstance(approval, str) or not approval:
            errors.append(f"{label}: invalid B2 temporal fields")
    validate_baseline_audits(
        root, data.get("auditRecords"), stage, data.get("promotedFrom"),
        data.get("fileSetSha256"), errors, label)
    records = validate_file_records(root, data, errors, label, verify_current)
    if not verify_current:
        content = verify_historical_files(root, source_root, data, records, errors, label)
        if historical_content is not None:
            historical_content.update(content)
    return records


def find_baseline(root: Path, baseline_id: Any, errors: list[str], label: str) -> tuple[Path, dict[str, Any]] | None:
    if not isinstance(baseline_id, str) or not baseline_id:
        errors.append(f"{label}: baseline ID is missing")
        return None
    matches: list[tuple[Path, dict[str, Any]]] = []
    evidence = root / "docs" / "evidence"
    if evidence.is_dir():
        for path in evidence.rglob("*.json"):
            data = load_json(path, [], "candidate")
            if data is not None and data.get("baselineId") == baseline_id:
                matches.append((path, data))
    if len(matches) != 1:
        errors.append(f"{label}: expected exactly one baseline {baseline_id!r}, found {len(matches)}")
        return None
    return matches[0]


def validate_promotion_chain(
        root: Path, source_root: Path, b0: dict[str, Any],
        b1: dict[str, Any], b2: dict[str, Any],
        errors: list[str], project: str, prefix: str) -> None:
    if b2.get("parentBaselineId") != b1.get("baselineId"):
        errors.append("B2.parentBaselineId must equal B1.baselineId")
    if b2.get("promotedFrom") is not None:
        errors.append("B2.promotedFrom must be null")
    if not b0 or b1.get("parentBaselineId") != b0.get("baselineId"):
        errors.append("B1.parentBaselineId must equal the package-pinned B0.baselineId")
    p0_match = find_baseline(root, b1.get("promotedFrom"), errors, "B1 promotedFrom P0 candidate")
    if b0:
        if b0.get("parentBaselineId") is not None:
            errors.append("B0.parentBaselineId must be null")
        if b0.get("approvalId") is not None:
            errors.append("B0.approvalId must be null")
        d4_match = find_baseline(root, b0.get("promotedFrom"), errors, "B0 promotedFrom D4 candidate")
        if d4_match is not None:
            _, candidate = d4_match
            validate_baseline(root, source_root, candidate, errors, "D4 candidate", "D4-CANDIDATE",
                              candidate.get("baselineId"), project, prefix, False)
            if candidate.get("promotedFrom") is not None:
                errors.append("D4 candidate.promotedFrom must be null")
            if candidate.get("approvalId") is not None:
                errors.append("D4 candidate.approvalId must be null")
            if candidate.get("fileSetSha256") != b0.get("fileSetSha256"):
                errors.append("D4 candidate -> B0 promotion changed fileSetSha256")
    if p0_match is not None:
        _, candidate = p0_match
        validate_baseline(root, source_root, candidate, errors, "P0 candidate", "P0-CANDIDATE",
                          candidate.get("baselineId"), project, prefix, False)
        if candidate.get("promotedFrom") is not None:
            errors.append("P0 candidate.promotedFrom must be null")
        if candidate.get("approvalId") is not None:
            errors.append("P0 candidate.approvalId must be null")
        if candidate.get("parentBaselineId") != b1.get("parentBaselineId"):
            errors.append("P0 candidate.parentBaselineId must equal B1.parentBaselineId")
        if candidate.get("fileSetSha256") != b1.get("fileSetSha256"):
            errors.append("P0 candidate -> B1 promotion changed fileSetSha256")


def parse_index(path: Path, errors: list[str]) -> dict[str, dict[str, str]]:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        errors.append(f"docs index cannot be read: {exc}")
        return {}
    if text.count(gen_index.INDEX_BEGIN) != 1 or text.count(gen_index.INDEX_END) != 1:
        errors.append("docs index must contain exactly one generated marker pair")
        return {}
    body = text.split(gen_index.INDEX_BEGIN, 1)[1].split(gen_index.INDEX_END, 1)[0]
    rows: dict[str, dict[str, str]] = {}
    header_seen = False
    for line in body.splitlines():
        cells = gen_index.split_row(line)
        if not cells or len(cells) != 5:
            continue
        if cells[0] == "Document ID":
            header_seen = True
            continue
        if set("".join(cells)) <= set("-: "):
            continue
        raw_path = cells[1].strip(" `").replace("\\", "/")
        if raw_path in rows:
            errors.append(f"docs index has duplicate path: {raw_path}")
            continue
        rows[raw_path] = {
            "id": cells[0], "version": cells[2], "status": cells[3],
            "domain": cells[4],
        }
    if not header_seen:
        errors.append("docs index generated table header is missing")
    return rows


def parse_d4_record(
        path: Path, record: dict[str, Any], candidate_ref: dict[str, Any],
        errors: list[str], label: str) -> None:
    """Bind W0 metadata to the actual human-readable D4 findings record."""
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        errors.append(f"{label}: raw D4 record must be readable strict UTF-8: {exc}")
        return
    fields: dict[str, str] = {}
    duplicates: set[str] = set()
    for line in text.splitlines():
        cells = gen_index.split_row(line)
        if cells is None or len(cells) != 2:
            continue
        key, value = cells[0].strip(), cells[1].strip().strip("`")
        if key in fields:
            duplicates.add(key)
        else:
            fields[key] = value
    required = {
        "Record ID": str(record.get("id") or ""),
        "Audit track": str(record.get("auditTrack") or ""),
        "Candidate baseline ID": str(candidate_ref.get("id") or ""),
        "Candidate manifest": str(candidate_ref.get("path") or ""),
        "Candidate manifest SHA-256": str(candidate_ref.get("sha256") or ""),
        "Candidate fileSetSha256": str(candidate_ref.get("fileSetSha256") or ""),
        "Verdict": "pass",
    }
    for key, expected in required.items():
        if key in duplicates or fields.get(key) != expected:
            errors.append(f"{label}: raw D4 field {key!r} must uniquely equal {expected!r}")
    for name, expected in (("Critical", record.get("criticalCount")),
                           ("Major", record.get("majorCount"))):
        matches = re.findall(
            rf"(?im)^\s*[-*]\s*{re.escape(name)}\s*[:：]\s*`?(\d+)`?\s*$", text)
        if len(matches) != 1 or int(matches[0]) != expected:
            errors.append(f"{label}: raw D4 {name} count does not match W0 metadata")
    verdicts = re.findall(
        r"(?im)^\s*[-*]\s*Verdict(?:\s+rule)?\s*[:：]\s*(.*?)\s*$", text)
    if not verdicts or not any(re.search(r"\bpass\b", value, re.I) for value in verdicts):
        errors.append(f"{label}: raw D4 summary does not assert pass")


def wp_section(text: str, wp_id: str) -> str | None:
    lines = text.splitlines()
    start = None
    level = None
    for index, line in enumerate(lines):
        match = re.match(r"^(#{2,6})\s+.*\b" + re.escape(wp_id) + r"\b", line)
        if match:
            start, level = index, len(match.group(1))
            break
    if start is None or level is None:
        return None
    end = len(lines)
    for index in range(start + 1, len(lines)):
        match = re.match(r"^(#{1,6})\s+", lines[index])
        if match and len(match.group(1)) <= level:
            end = index
            break
    return "\n".join(lines[start:end])


def _line_parts(line: str) -> tuple[str, str]:
    if line.endswith("\r\n"):
        return line[:-2], "\r\n"
    if line.endswith("\n") or line.endswith("\r"):
        return line[:-1], line[-1]
    return line, ""


def parse_header_text(text: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    in_table = False
    for line in text.splitlines():
        cells = gen_index.split_row(line)
        if cells is None or len(cells) < 2:
            if in_table:
                break
            if line.startswith("## "):
                break
            continue
        if set("".join(cells[:2])) <= set("-: "):
            in_table = True
            continue
        key, value = cells[0], cells[1].strip("`")
        if key in gen_index.FIELDS:
            if key in fields:
                fields[key] = "<DUPLICATE>"
            else:
                fields[key] = value
            in_table = True
        elif in_table and len(cells) > 2:
            break
    return fields


def normalize_formal_transition(
        old: str, new: str, rel: str, d5_id: str, approved_at: str,
        errors: list[str], *, index: bool, wp_id: str | None) -> tuple[str, str]:
    """Erase only the D5-authorized metadata deltas, preserving every other byte."""
    old_lines = old.splitlines(keepends=True)
    new_lines = new.splitlines(keepends=True)
    old_header, new_header = parse_header_text(old), parse_header_text(new)
    try:
        old_status = gen_index.normalize_status(old_header.get("Status", ""), rel)
    except SystemExit:
        old_status = None
    if old_status not in {"draft", "review"}:
        errors.append(f"{rel}: historical B1 formal Status must be Draft or Review")
    old_approved = old_header.get("Last approved", "").strip().casefold()
    if old_approved not in {"", "—", "-", "none", "null", "n/a", "never"}:
        errors.append(f"{rel}: historical B1 Last approved must be unset")
    try:
        new_status = gen_index.normalize_status(new_header.get("Status", ""), rel)
    except SystemExit:
        new_status = None
    if new_status != "approved" or new_header.get("Last approved") != approved_at:
        errors.append(f"{rel}: D5 formal header must set Approved and the exact approval timestamp")

    def history_rows(lines: list[str]) -> set[str]:
        active = False
        rows: set[str] = set()
        for line in lines:
            body, _ = _line_parts(line)
            heading = re.match(r"^##\s+", body)
            if heading:
                active = "change history" in body.lower()
                continue
            if active and body.lstrip().startswith("|"):
                rows.add(body)
        return rows

    old_history = history_rows(old_lines)
    added_history = 0

    def normalize(lines: list[str], is_new: bool) -> str:
        nonlocal added_history
        out: list[str] = []
        in_history = False
        in_wp = False
        skip_index = False
        before_h2 = True
        for line in lines:
            body, ending = _line_parts(line)
            if index and body == gen_index.INDEX_BEGIN:
                skip_index = True
                out.append(gen_index.INDEX_BEGIN + ending)
                out.append("<GENERATED-DOCUMENT-INDEX>" + ending)
                continue
            if index and skip_index:
                if body == gen_index.INDEX_END:
                    skip_index = False
                    out.append(gen_index.INDEX_END + ending)
                continue

            heading = re.match(r"^(#{1,6})\s+(.*)$", body)
            if heading:
                if len(heading.group(1)) == 2:
                    before_h2 = False
                    in_history = "change history" in heading.group(2).lower()
                if wp_id is not None:
                    in_wp = wp_id in heading.group(2)
                out.append(line)
                continue

            if is_new and in_history and body.lstrip().startswith("|") \
                    and body not in old_history:
                same_approval_time = approved_at in body or (
                    bool(approved_at) and approved_at[:10] in body)
                if d5_id and d5_id in body and same_approval_time:
                    added_history += 1
                    continue

            if before_h2 and re.fullmatch(r"\|\s*Status\s*\|.*\|", body):
                out.append("| Status | <D5-STATUS> |" + ending)
                continue
            if before_h2 and re.fullmatch(r"\|\s*Last approved\s*\|.*\|", body):
                out.append("| Last approved | <D5-LAST-APPROVED> |" + ending)
                continue

            if wp_id is not None and in_wp \
                    and re.match(r"^\s*[-*]\s*Status\s*[:：]", body):
                prefix_part = re.match(r"^(\s*[-*]\s*Status\s*[:：]).*$", body)
                out.append(prefix_part.group(1) + " <D5-WP-STATUS>" + ending)
                continue
            if wp_id is not None and in_wp \
                    and re.match(r"^\s*[-*]\s*Authorized by\s*[:：]", body, re.I):
                prefix_part = re.match(
                    r"^(\s*[-*]\s*Authorized by\s*[:：]).*$", body, re.I)
                out.append(prefix_part.group(1) + " <D5-WP-AUTH>" + ending)
                continue
            if wp_id is not None and in_wp \
                    and re.match(r"^\s*[-*]\s*Authorization baseline\s*[:：]", body, re.I):
                prefix_part = re.match(
                    r"^(\s*[-*]\s*Authorization baseline\s*[:：]).*$", body, re.I)
                out.append(prefix_part.group(1) + " <D5-WP-BASELINE>" + ending)
                continue
            if wp_id is not None and in_wp \
                    and re.match(r"^\s*[-*]\s*Authorization evidence\s*[:：]", body, re.I):
                prefix_part = re.match(
                    r"^(\s*[-*]\s*Authorization evidence\s*[:：]).*$", body, re.I)
                out.append(prefix_part.group(1) + " <D5-WP-EVIDENCE>" + ending)
                continue
            if wp_id is not None and body.lstrip().startswith("|") and wp_id in body:
                body = re.sub(
                    r"(?i)(?<![A-Za-z])(?:Proposed|Approved|In progress|Verified|Superseded)(?![A-Za-z])",
                    "<D5-WP-STATUS>", body)
                out.append(body + ending)
                continue
            out.append(line)
        return "".join(out)

    normalized_old = normalize(old_lines, False)
    normalized_new = normalize(new_lines, True)
    if added_history != 1:
        errors.append(f"{rel}: D5 transition must append exactly one change-history row")
    return normalized_old, normalized_new


def validate_manifest_transition(
        old_bytes: bytes, current: dict[str, Any], b2_id: str,
        formal: dict[str, tuple[dict[str, Any], dict[str, str]]],
        errors: list[str]) -> None:
    try:
        old = json.loads(old_bytes.decode("utf-8-sig"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        errors.append(f"B1 docs manifest is invalid: {exc}")
        return
    if not isinstance(old, dict):
        errors.append("B1 docs manifest root must be an object")
        return
    for key in ("schemaVersion", "project", "prefix"):
        if old.get(key) != current.get(key):
            errors.append(f"docs manifest transition changed immutable {key}")
    if current.get("baselineId") != b2_id:
        errors.append("docs manifest transition did not set B2 baselineId")
    if not timezone_datetime(current.get("generatedAt")):
        errors.append("docs manifest generatedAt must be a timezone timestamp")
    allowed_top = {"schemaVersion", "project", "prefix", "generatedAt", "baselineId", "documents"}
    if set(current) != allowed_top:
        errors.append("docs manifest contains unknown/missing top-level fields")

    def by_path(value: Any, label: str) -> dict[str, dict[str, Any]]:
        result: dict[str, dict[str, Any]] = {}
        if not isinstance(value, list):
            errors.append(f"{label} documents must be an array")
            return result
        for item in value:
            if not isinstance(item, dict) or not isinstance(item.get("path"), str):
                errors.append(f"{label} contains an invalid document row")
                continue
            if item["path"] in result:
                errors.append(f"{label} contains duplicate path {item['path']}")
            result[item["path"]] = item
        return result

    old_docs = by_path(old.get("documents"), "B1 manifest")
    new_docs = by_path(current.get("documents"), "B2 manifest")
    if set(old_docs) != set(new_docs):
        errors.append("docs manifest generator changed the registered file set")
    allowed_item = {"id", "path", "version", "domain", "required", "status", "phase", "trigger"}
    for rel in sorted(set(old_docs) & set(new_docs)):
        before, after = old_docs[rel], new_docs[rel]
        if set(before) != allowed_item or set(after) != allowed_item:
            errors.append(f"docs manifest {rel}: unknown/missing fields")
        for key in allowed_item - {"status"}:
            if before.get(key) != after.get(key):
                errors.append(f"docs manifest {rel}: generator changed immutable {key}")
        before_status, after_status = before.get("status"), after.get("status")
        if rel in formal and (before_status not in {"draft", "review"}
                              or after_status != "approved"):
            errors.append(
                f"docs manifest {rel}: formal D5 transition must be draft/review -> approved")
        allowed_status_change = (
            before_status == after_status
            or (before_status in {"draft", "review"} and after_status == "approved")
        )
        if not allowed_status_change:
            kind = "formal" if rel in formal else "non-formal"
            errors.append(
                f"docs manifest {rel}: invalid {kind} D5 status transition "
                f"{before_status!r} -> {after_status!r}")


def validate_approval_record(
        root: Path, ref_path: Any, ref_hash: Any, expected_id: Any,
        expected_type: str, expected_baseline_ref: Any,
        expected_baseline: dict[str, Any], errors: list[str], label: str,
        *, package_approver: Any = None, package_approved_at: Any = None,
        first_wp_id: Any = None) -> dict[str, Any] | None:
    loaded = verify_ref(
        root, {"path": ref_path, "sha256": ref_hash}, errors, label)
    if loaded is None:
        return None
    record = loaded[1]
    allowed = {
        "schemaVersion", "id", "type", "approvalKind", "approver", "approvedAt",
        "scope", "baseline", "firstAuthorizedWpId", "sourceEvidence",
    }
    if set(record) != allowed:
        errors.append(f"{label}: unknown/missing approval-record fields")
    if record.get("schemaVersion") != "1.0.0":
        errors.append(f"{label}.schemaVersion must be 1.0.0")
    if record.get("id") != expected_id:
        errors.append(f"{label}.id does not match W0 package")
    if record.get("type") != expected_type:
        errors.append(f"{label}.type must be {expected_type}")
    if not isinstance(record.get("scope"), str) or not record["scope"].strip():
        errors.append(f"{label}.scope must be non-empty")
    if not timezone_datetime(record.get("approvedAt")):
        errors.append(f"{label}.approvedAt must be a timezone timestamp")
    if not isinstance(record.get("approver"), str) or not record["approver"].strip():
        errors.append(f"{label}.approver must be non-empty")

    if expected_type == "d5":
        if record.get("approvalKind") != "human-direct":
            errors.append("D5 approval record must be human-direct")
        if record.get("approver") != package_approver:
            errors.append("D5 approval record approver does not match W0 package")
        if record.get("approvedAt") != package_approved_at:
            errors.append("D5 approval record approvedAt does not match W0 package")
        if record.get("firstAuthorizedWpId") != first_wp_id:
            errors.append("D5 approval record firstAuthorizedWpId does not match W0 package")
    elif expected_type == "p0-start":
        if record.get("approvalKind") != "human-direct":
            errors.append("P0 start approval record must be human-direct")
        if record.get("firstAuthorizedWpId") is not None:
            errors.append(f"{label}.firstAuthorizedWpId must be null")
    elif record.get("firstAuthorizedWpId") is not None:
        errors.append(f"{label}.firstAuthorizedWpId must be null")
    if record.get("approvalKind") not in {"human-direct", "delegated-process"}:
        errors.append(f"{label}.approvalKind is invalid")

    baseline = record.get("baseline")
    if not isinstance(baseline, dict):
        errors.append(f"{label}.baseline must be an object")
    else:
        if set(baseline) != {"id", "path", "sha256", "fileSetSha256", "revision"}:
            errors.append(f"{label}.baseline has unknown/missing fields")
        expected_path = expected_baseline_ref.get("path") if isinstance(expected_baseline_ref, dict) else None
        expected_hash = expected_baseline_ref.get("sha256") if isinstance(expected_baseline_ref, dict) else None
        expected_set = (expected_baseline_ref.get("fileSetSha256")
                        if isinstance(expected_baseline_ref, dict) else None)
        if baseline.get("id") != expected_baseline.get("baselineId"):
            errors.append(f"{label}.baseline.id mismatch")
        if baseline.get("path") != expected_path:
            errors.append(f"{label}.baseline.path mismatch")
        if baseline.get("sha256") != expected_hash:
            errors.append(f"{label}.baseline.sha256 mismatch")
        if baseline.get("fileSetSha256") != expected_set \
                or expected_set != expected_baseline.get("fileSetSha256"):
            errors.append(f"{label}.baseline.fileSetSha256 mismatch")
        revision = expected_baseline.get("revision")
        expected_revision = revision.get("value") if isinstance(revision, dict) else None
        if baseline.get("revision") != expected_revision:
            errors.append(f"{label}.baseline.revision mismatch")

    source = record.get("sourceEvidence")
    if not isinstance(source, dict):
        errors.append(f"{label}.sourceEvidence must be an object")
    else:
        if set(source) != {"path", "sha256"}:
            errors.append(f"{label}.sourceEvidence has unknown/missing fields")
        verify_file_hash(root, source.get("path"), source.get("sha256"), errors,
                         f"{label}.sourceEvidence")
        if source.get("path") == ref_path:
            errors.append(f"{label}: approval record cannot cite itself as source evidence")
    return record


def verify_transition_diff(
        root: Path, b1_content: dict[str, bytes], b2_files: dict[str, dict[str, Any]],
        docs_manifest: dict[str, Any], formal: dict[str, tuple[dict[str, Any], dict[str, str]]],
        manifest_rel: str, b1_id: str, b1_file_set: str, b2_id: str,
        d5_id: str, approved_at: str, d5_record_rel: str,
        first_wp_path: str | None, first_wp_id: str | None,
        post_sync_path: str | None, errors: list[str]) -> None:
    if post_sync_path is not None and set(b2_files) != set(b1_content) | {post_sync_path}:
        errors.append("B2 file set must equal verified B1 file set plus postSyncManifest")
    append_only = {"DECISIONS.md", "PROGRESS.md", "CHANGELOG.md"}
    for rel, old_bytes in b1_content.items():
        path = resolve_path(root, rel, errors, f"B2 transition {rel}")
        if path is None or not path.is_file():
            continue
        current_bytes = path.read_bytes()
        if current_bytes == old_bytes:
            continue
        if rel == manifest_rel:
            validate_manifest_transition(old_bytes, docs_manifest, b2_id, formal, errors)
            continue
        if rel in append_only:
            if not current_bytes.startswith(old_bytes):
                errors.append(f"{rel}: D5 record update is not byte-for-byte append-only")
                continue
            appended = current_bytes[len(old_bytes):].decode("utf-8", errors="replace")
            if d5_id not in appended or approved_at not in appended:
                errors.append(f"{rel}: appended D5 record lacks approval ID/timestamp")
            if rel == "DECISIONS.md":
                required = {
                    "[DECISION]": "decision marker",
                    "human-direct": "human-direct approval kind",
                    b1_id: "B1 baseline ID",
                    b1_file_set: "B1 fileSetSha256",
                    d5_record_rel: "structured approval record path",
                }
                for token, description in required.items():
                    if not token or token not in appended:
                        errors.append(
                            f"DECISIONS.md: appended D5 decision lacks {description}")
            continue
        if rel in formal:
            try:
                old_text = old_bytes.decode("utf-8")
                new_text = current_bytes.decode("utf-8")
            except UnicodeDecodeError:
                errors.append(f"{rel}: formal document is not strict UTF-8")
                continue
            norm_old, norm_new = normalize_formal_transition(
                old_text, new_text, rel, d5_id, approved_at, errors,
                index=rel.endswith("_docs_index.md"),
                wp_id=first_wp_id if rel == first_wp_path else None)
            if norm_old != norm_new:
                errors.append(f"{rel}: D5 changed content outside authorized metadata")
            continue
        errors.append(f"{rel}: D5 changed an unauthorized artifact")


def git_clean_metadata_diff(root: Path, revision: dict[str, Any], errors: list[str]) -> None:
    """Confirm a commit baseline exists before internal blob reconstruction.

    Snapshot baselines are valid without Git. Commit-backed historical bytes
    are reconstructed and diffed by ``historical_bytes``/``verify_transition_diff``;
    this helper only provides an early, explicit object-resolution diagnostic.
    """
    if not isinstance(revision, dict) or revision.get("kind") != "commit":
        return
    value = revision.get("value")
    if not isinstance(value, str) or not value:
        errors.append("B1.revision.value must name the approved commit")
        return
    try:
        result = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "--verify", f"{value}^{{commit}}"],
            capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=20)
    except (OSError, subprocess.SubprocessError) as exc:
        errors.append(f"cannot verify B1 commit revision: {exc}")
        return
    if result.returncode != 0:
        errors.append(f"B1 commit revision cannot be resolved: {value}")


def validate(
        root: Path, prefix: str, package_path: Path,
        source_root: Path | None = None) -> dict[str, Any]:
    errors: list[str] = []
    checked: list[str] = []
    source_root = (source_root or root).resolve()
    package = load_json(package_path, errors, "W0 package")
    if package is None:
        return {"pass": False, "errors": errors, "checked": checked}
    checked.append(str(package_path))

    if package.get("schemaVersion") != "1.0.0":
        errors.append("W0 package.schemaVersion must be 1.0.0")
    expected_package_keys = {
        "schemaVersion", "packageId", "project", "prefix", "createdAt",
        "d5Approval", "p0", "baselines", "postSyncManifest",
        "firstAuthorizedWp", "postP0D4Records",
    }
    if set(package) != expected_package_keys:
        errors.append("W0 package has unknown/missing top-level fields")
    project = package.get("project")
    if not isinstance(package.get("packageId"), str) or not package["packageId"].strip():
        errors.append("W0 package.packageId must be non-empty")
    if not isinstance(project, str) or not project:
        errors.append("W0 package.project must be non-empty")
        project = ""
    if package.get("prefix") != prefix:
        errors.append("W0 package.prefix does not match --prefix")
    if not timezone_datetime(package.get("createdAt")):
        errors.append("W0 package.createdAt must be an ISO-8601 timezone timestamp")

    d5 = package.get("d5Approval")
    p0 = package.get("p0")
    if not isinstance(d5, dict):
        errors.append("d5Approval must be an object")
        d5 = {}
    elif set(d5) != {"id", "approvedAt", "approver", "recordPath", "recordSha256"}:
        errors.append("d5Approval has unknown/missing fields")
    if not isinstance(p0, dict):
        errors.append("p0 must be an object")
        p0 = {}
    elif set(p0) != {
            "startApprovalId", "startApprovalRecordPath", "startApprovalRecordSha256",
            "contractApprovalId", "contractApprovalRecordPath", "contractApprovalRecordSha256"}:
        errors.append("p0 has unknown/missing fields")
    d5_id = d5.get("id")
    ids = [d5_id, p0.get("startApprovalId"), p0.get("contractApprovalId")]
    if any(not isinstance(value, str) or not value.strip() for value in ids):
        errors.append("D5, P0 start, and P0 contract approval IDs must be non-empty")
    elif len(set(ids)) != 3:
        errors.append("D5, P0 start, and P0 contract approval IDs must be distinct")
    approved_at = d5.get("approvedAt")
    if not timezone_datetime(approved_at):
        errors.append("d5Approval.approvedAt must be an ISO-8601 timezone timestamp")
    if not isinstance(d5.get("approver"), str) or not d5["approver"].strip():
        errors.append("d5Approval.approver must be non-empty")
    record_path = resolve_path(root, d5.get("recordPath"), errors, "D5 approval record")
    if record_path is not None:
        if not record_path.is_file():
            errors.append("D5 approval record file is missing")
        elif d5.get("recordSha256") != sha256(record_path):
            errors.append("D5 approval record sha256 mismatch")

    baselines = package.get("baselines")
    if not isinstance(baselines, dict):
        errors.append("baselines must be an object")
        baselines = {}
    elif set(baselines) != {"b0", "b1", "b2"}:
        errors.append("baselines must contain exactly b0/b1/b2")
    b0_ref, b1_ref, b2_ref = baselines.get("b0"), baselines.get("b1"), baselines.get("b2")
    for name, ref in (("b0", b0_ref), ("b1", b1_ref), ("b2", b2_ref)):
        if not isinstance(ref, dict) or set(ref) != {"id", "path", "sha256", "fileSetSha256"}:
            errors.append(f"baselines.{name} has unknown/missing fields")
    b0_loaded = verify_ref(root, b0_ref, errors, "B0 reference")
    b1_loaded = verify_ref(root, b1_ref, errors, "B1 reference")
    b2_loaded = verify_ref(root, b2_ref, errors, "B2 reference")
    b0: dict[str, Any] = b0_loaded[1] if b0_loaded else {}
    b1: dict[str, Any] = b1_loaded[1] if b1_loaded else {}
    b2: dict[str, Any] = b2_loaded[1] if b2_loaded else {}
    b1_files: dict[str, dict[str, Any]] = {}
    b2_files: dict[str, dict[str, Any]] = {}
    b1_content: dict[str, bytes] = {}
    if b0:
        validate_baseline(
            root, source_root, b0, errors, "B0", "B0", (b0_ref or {}).get("id"),
            project, prefix, False)
    if b1:
        b1_files = validate_baseline(
            root, source_root, b1, errors, "B1", "B1", (b1_ref or {}).get("id"), project, prefix,
            False, b1_content)
    if b2:
        b2_files = validate_baseline(
            root, source_root, b2, errors, "B2", "B2", (b2_ref or {}).get("id"),
            project, prefix, True)
    if b1 and b2:
        validate_promotion_chain(
            root, source_root, b0, b1, b2, errors, project, prefix)
    for name, ref, baseline in (("B0", b0_ref, b0), ("B1", b1_ref, b1), ("B2", b2_ref, b2)):
        if isinstance(ref, dict) and baseline:
            if ref.get("fileSetSha256") != baseline.get("fileSetSha256"):
                errors.append(f"{name} package reference fileSetSha256 mismatch")

    post_ref_value = package.get("postSyncManifest")
    if not isinstance(post_ref_value, dict) or set(post_ref_value) != {"path", "sha256"}:
        errors.append("postSyncManifest reference has unknown/missing fields")
    post_loaded = verify_ref(root, post_ref_value, errors, "postSyncManifest")
    post_files: dict[str, dict[str, Any]] = {}
    if post_loaded:
        post_data = post_loaded[1]
        expected_post_fields = {
            "schemaVersion", "transactionId", "baselineId", "generatedAt",
            "selfIncluded", "files",
        }
        if set(post_data) != expected_post_fields:
            errors.append("postSyncManifest has unknown/missing fields")
        if post_data.get("schemaVersion") != "1.0.0":
            errors.append("postSyncManifest.schemaVersion must be 1.0.0")
        if post_data.get("transactionId") != d5_id:
            errors.append("postSyncManifest.transactionId must equal D5 approval ID")
        if not timezone_datetime(post_data.get("generatedAt")):
            errors.append("postSyncManifest.generatedAt must be a timezone timestamp")
        if post_data.get("selfIncluded") is not False:
            errors.append("postSyncManifest.selfIncluded must be false")
        post_files = validate_post_sync_records(root, post_data, errors)
        if b2 and post_data.get("baselineId") != b2.get("baselineId"):
            errors.append("postSyncManifest baselineId must match B2")

    # Three independent post-P0 D4 audit tracks, all bound to the B1 candidate.
    records = package.get("postP0D4Records")
    required_tracks = {"consistency", "roblox-readiness", "clean-room"}
    seen_tracks: set[str] = set()
    seen_record_ids: set[str] = set()
    candidate_refs: list[dict[str, Any]] = []
    if not isinstance(records, list) or len(records) != 3:
        errors.append("postP0D4Records requires exactly three records")
        records = []
    for index, record in enumerate(records):
        label = f"postP0D4Records[{index}]"
        if not isinstance(record, dict):
            errors.append(f"{label} must be an object")
            continue
        if set(record) != {
                "id", "auditTrack", "path", "sha256", "candidateBaseline",
                "criticalCount", "majorCount", "verdict"}:
            errors.append(f"{label} has unknown/missing fields")
        track, record_id = record.get("auditTrack"), record.get("id")
        if track not in required_tracks:
            errors.append(f"{label}.auditTrack is invalid")
        if not isinstance(record_id, str) or not record_id.strip():
            errors.append(f"{label}.id must be non-empty")
        if track in seen_tracks:
            errors.append(f"{label}: duplicate auditTrack {track!r}")
        if record_id in seen_record_ids:
            errors.append(f"{label}: duplicate record ID {record_id!r}")
        if isinstance(track, str):
            seen_tracks.add(track)
        if isinstance(record_id, str):
            seen_record_ids.add(record_id)
        if record.get("criticalCount") != 0 or record.get("majorCount") != 0:
            errors.append(f"{label}: Critical/Major counts must both be zero")
        if str(record.get("verdict", "")).lower() != "pass":
            errors.append(f"{label}.verdict must be pass")
        candidate_ref = record.get("candidateBaseline")
        if not isinstance(candidate_ref, dict):
            errors.append(f"{label}.candidateBaseline must be an object")
        else:
            if set(candidate_ref) != {"id", "path", "sha256", "fileSetSha256"}:
                errors.append(f"{label}.candidateBaseline has unknown/missing fields")
            candidate_refs.append(candidate_ref)
            candidate_id = candidate_ref.get("id")
            if not isinstance(candidate_id, str) or re.fullmatch(
                    r"P0-CAND-[A-Z0-9][A-Z0-9._-]*", candidate_id) is None:
                errors.append(f"{label}.candidateBaseline.id must be P0-CAND-*")
        if isinstance(candidate_ref, dict) and b1:
            if candidate_ref.get("id") != b1.get("promotedFrom"):
                errors.append(f"{label}.candidateBaseline.id must equal B1.promotedFrom")
            if candidate_ref.get("fileSetSha256") != b1.get("fileSetSha256"):
                errors.append(f"{label}.candidateBaseline.fileSetSha256 must equal B1")
            candidate_loaded = verify_ref(root, candidate_ref, errors, f"{label}.candidateBaseline")
            if candidate_loaded:
                candidate = candidate_loaded[1]
                if candidate.get("baselineId") != candidate_ref.get("id"):
                    errors.append(f"{label}: candidate manifest ID mismatch")
                if candidate.get("stage") != "P0-CANDIDATE":
                    errors.append(f"{label}: candidate manifest stage must be P0-CANDIDATE")
                if candidate.get("fileSetSha256") != b1.get("fileSetSha256"):
                    errors.append(f"{label}: candidate manifest fileSetSha256 must equal B1")
        raw_path = verify_file_hash(
            root, record.get("path"), record.get("sha256"), errors, label)
        if raw_path is not None and isinstance(candidate_ref, dict):
            parse_d4_record(raw_path, record, candidate_ref, errors, label)
    if seen_tracks != required_tracks:
        errors.append("postP0D4Records must contain each audit track exactly once")
    if candidate_refs and any(ref != candidate_refs[0] for ref in candidate_refs[1:]):
        errors.append("postP0D4Records must all reference the same P0 candidate manifest")
    p0_candidate_ref = candidate_refs[0] if candidate_refs else {}
    p0_candidate_loaded = (verify_ref(root, p0_candidate_ref, errors, "P0 candidate reference")
                           if p0_candidate_ref else None)
    p0_candidate = p0_candidate_loaded[1] if p0_candidate_loaded else {}
    package_audits = {
        item.get("auditTrack"): item for item in records if isinstance(item, dict)
    }
    for label, baseline in (("B1", b1), ("B2", b2)):
        baseline_audits = baseline.get("auditRecords") if baseline else None
        by_track = ({item.get("auditTrack"): item for item in baseline_audits
                     if isinstance(item, dict)}
                    if isinstance(baseline_audits, list) else {})
        if by_track != package_audits:
            errors.append(f"{label}.auditRecords must equal W0 postP0D4Records")

    manifest_rel = f"docs/{prefix}_docs_manifest.json"
    manifest_path = root / manifest_rel
    docs_manifest = load_json(manifest_path, errors, "docs manifest") or {}
    if docs_manifest:
        checked.append(manifest_rel)
        if docs_manifest.get("project") != project or docs_manifest.get("prefix") != prefix:
            errors.append("docs manifest project/prefix mismatch")
        if docs_manifest.get("schemaVersion") != gen_index.MANIFEST_VERSION:
            errors.append("docs manifest schemaVersion mismatch")
        if b2 and docs_manifest.get("baselineId") != b2.get("baselineId"):
            errors.append("docs manifest baselineId must equal B2.baselineId")

    formal: dict[str, tuple[dict[str, Any], dict[str, str]]] = {}
    documents = docs_manifest.get("documents")
    if not isinstance(documents, list):
        errors.append("docs manifest documents must be an array")
        documents = []
    manifest_paths: set[str] = set()
    for index, item in enumerate(documents):
        if not isinstance(item, dict) or not isinstance(item.get("path"), str):
            errors.append(f"docs manifest documents[{index}] is invalid")
            continue
        rel = item["path"].replace("\\", "/")
        if rel in manifest_paths:
            errors.append(f"docs manifest duplicate path: {rel}")
        manifest_paths.add(rel)
        if item.get("status") != "approved":
            errors.append(f"{rel}: D5 docs manifest inventory status must be approved")
        path = resolve_path(root, rel, errors, f"docs manifest {rel}")
        if path is None:
            continue
        if not path.is_file():
            errors.append(f"docs manifest inventory file is missing: {rel}")
            continue
        if path.suffix.lower() in {".md", ".json", ".csv", ".txt", ".yaml", ".yml"}:
            text = path.read_text(encoding="utf-8", errors="replace")
            for token in ("[PROPOSAL]", "[ASSUMPTION]", "[OPEN blocking: yes]"):
                if token in text:
                    errors.append(f"{rel}: unresolved D5 state token {token}")
            if UNRESOLVED_RE.search(text):
                errors.append(f"{rel}: unresolved template placeholder")
        if path.suffix.lower() != ".md":
            continue
        header, dupes = gen_index.parse_header(path)
        if dupes:
            errors.append(f"{rel}: duplicate formal header fields: {', '.join(dupes)}")
        if not header.get("Document ID"):
            continue
        formal[rel] = (item, header)
        if manifest_status(header.get("Status", ""), rel, errors) != "approved":
            errors.append(f"{rel}: formal Status must be Approved")
        if item.get("status") != "approved":
            errors.append(f"{rel}: docs manifest status must be approved")
        if header.get("Version") != item.get("version"):
            errors.append(f"{rel}: header/manifest version mismatch")
        if header.get("Document ID") != item.get("id"):
            errors.append(f"{rel}: header/manifest document ID mismatch")
        if header.get("Last approved") != approved_at:
            errors.append(f"{rel}: Last approved must equal D5 approvedAt")

    last_approved = {header.get("Last approved") for _, header in formal.values()}
    if not formal:
        errors.append("no formal documents found in docs manifest")
    elif len(last_approved) != 1:
        errors.append("formal Last approved timestamps are not identical")

    index_candidates = [rel for rel in formal if rel.endswith(f"/{prefix}_docs_index.md")]
    if len(index_candidates) != 1:
        errors.append("docs manifest must contain exactly one formal docs index")
        index_rows = {}
    else:
        index_rows = parse_index(root / index_candidates[0], errors)
        manifest_by_path = {
            item["path"].replace("\\", "/"): item for item in documents
            if isinstance(item, dict) and isinstance(item.get("path"), str)
        }
        if set(index_rows) != set(manifest_by_path):
            missing = sorted(set(manifest_by_path) - set(index_rows))
            extra = sorted(set(index_rows) - set(manifest_by_path))
            errors.append(f"docs index/manifest file set mismatch; missing={missing}, extra={extra}")
        for rel, item in manifest_by_path.items():
            row = index_rows.get(rel)
            if row is None:
                continue
            if row["id"] != item.get("id"):
                errors.append(f"docs index ID mismatch: {rel}")
            if row["version"] != item.get("version"):
                errors.append(f"docs index version mismatch: {rel}")
            if manifest_status(row["status"], rel, errors) != item.get("status"):
                errors.append(f"docs index status mismatch: {rel}")
            if row["domain"] != item.get("domain"):
                errors.append(f"docs index domain mismatch: {rel}")

    first_wp = package.get("firstAuthorizedWp")
    if not isinstance(first_wp, dict):
        errors.append("firstAuthorizedWp must be an object")
        first_wp = {}
    elif set(first_wp) != {"id", "path", "sha256"}:
        errors.append("firstAuthorizedWp has unknown/missing fields")
    wp_id = first_wp.get("id")
    wp_path = resolve_path(root, first_wp.get("path"), errors, "firstAuthorizedWp")
    if not isinstance(wp_id, str) or not wp_id:
        errors.append("firstAuthorizedWp.id must be non-empty")
    if wp_path is not None:
        if not wp_path.is_file():
            errors.append("firstAuthorizedWp.path does not exist")
        else:
            if first_wp.get("sha256") != sha256(wp_path):
                errors.append("firstAuthorizedWp.sha256 mismatch")
            text = wp_path.read_text(encoding="utf-8", errors="replace")
            section = wp_section(text, wp_id) if isinstance(wp_id, str) else None
            if section is None:
                errors.append("first authorized WP section was not found")
            else:
                if WP_STATUS_RE.search(section) is None:
                    errors.append("first authorized WP Status must be Approved")
                if not isinstance(d5_id, str) or d5_id not in section:
                    errors.append("first authorized WP must reference the D5 approval ID")
                b2_id = b2.get("baselineId")
                baseline_match = re.search(
                    r"(?im)^\s*[-*]\s*Authorization baseline\s*[:：]\s*`?([^`\s]+)`?\s*$",
                    section)
                if baseline_match is None or baseline_match.group(1) != b2_id:
                    errors.append("first authorized WP Authorization baseline must equal B2 ID")
                package_rel = package_path.relative_to(root).as_posix()
                evidence_match = re.search(
                    r"(?im)^\s*[-*]\s*Authorization evidence\s*[:：]\s*`?([^`\s]+)`?\s*$",
                    section)
                if evidence_match is None or evidence_match.group(1).replace("\\", "/") != package_rel:
                    errors.append("first authorized WP Authorization evidence must equal W0 package path")
                indexed = False
                for line in text.splitlines():
                    cells = gen_index.split_row(line)
                    if cells and wp_id in cells[0] and any(
                            cell.replace("`", "").strip().lower() == "approved" for cell in cells):
                        indexed = True
                        break
                if not indexed:
                    errors.append("first authorized WP package-index row must be Approved")

    # Approval IDs are not evidence by themselves.  Bind each to one structured,
    # outer-hashed record with the expected gate type, scope, baseline, and source.
    validate_approval_record(
        root, d5.get("recordPath"), d5.get("recordSha256"), d5_id, "d5",
        b1_ref, b1, errors, "D5 approval record",
        package_approver=d5.get("approver"), package_approved_at=approved_at,
        first_wp_id=wp_id)
    validate_approval_record(
        root, p0.get("startApprovalRecordPath"), p0.get("startApprovalRecordSha256"),
        p0.get("startApprovalId"), "p0-start", b0_ref, b0, errors,
        "P0 start approval record")
    validate_approval_record(
        root, p0.get("contractApprovalRecordPath"),
        p0.get("contractApprovalRecordSha256"), p0.get("contractApprovalId"),
        "p0-contract", p0_candidate_ref, p0_candidate, errors,
        "P0 contract approval record")
    if b0 and b0.get("approvalId") is not None:
        errors.append("B0.approvalId must be null; P0 start approval stays in its gate record")
    if b1 and b1.get("approvalId") is not None:
        errors.append("B1.approvalId must be null; P0 contract approval stays in its gate record")
    if b2 and b2.get("approvalId") != d5_id:
        errors.append("B2.approvalId must equal D5 approval ID")

    # Post-sync evidence must cover every synchronized target.
    required_post_paths = set(formal) | {
        manifest_rel, "DECISIONS.md", "PROGRESS.md", "CHANGELOG.md",
    }
    if isinstance(first_wp.get("path"), str):
        required_post_paths.add(first_wp["path"].replace("\\", "/"))
    if post_files:
        missing = sorted(required_post_paths - set(post_files))
        if missing:
            errors.append(f"postSyncManifest omits synchronized paths: {missing}")
    post_ref = package.get("postSyncManifest")
    post_rel = post_ref.get("path") if isinstance(post_ref, dict) else None
    if isinstance(post_rel, str):
        post_rel = post_rel.replace("\\", "/")
        if post_rel in post_files:
            errors.append("postSyncManifest must not hash itself")
        if b2_files and post_rel not in b2_files:
            errors.append("B2 must include the independent postSyncManifest")
        if b1_files and b2_files and set(b2_files) != set(b1_files) | {post_rel}:
            errors.append("B2 file set must equal B1 file set plus postSyncManifest")
        if b2_files and set(b2_files) != manifest_paths | {post_rel}:
            missing = sorted((manifest_paths | {post_rel}) - set(b2_files))
            extra = sorted(set(b2_files) - (manifest_paths | {post_rel}))
            errors.append(
                f"docs manifest/B2 canonical file set mismatch; missing={missing}, extra={extra}")
        if b2_files:
            manifest_by_path = {
                item.get("path", "").replace("\\", "/"): item
                for item in documents if isinstance(item, dict)
                and isinstance(item.get("path"), str)
            }
            for rel, item in manifest_by_path.items():
                baseline_row = b2_files.get(rel)
                if baseline_row is None:
                    continue
                if baseline_row.get("status") != item.get("status"):
                    errors.append(f"B2/docs manifest status mismatch: {rel}")
                if baseline_row.get("version") != item.get("version"):
                    errors.append(f"B2/docs manifest version mismatch: {rel}")
    if b2_files and post_files and not set(post_files) <= set(b2_files):
        errors.append("B2 omits one or more postSyncManifest target files")

    first_wp_rel = (first_wp.get("path").replace("\\", "/")
                    if isinstance(first_wp.get("path"), str) else None)
    verify_transition_diff(
        root, b1_content, b2_files, docs_manifest, formal, manifest_rel,
        str(b1.get("baselineId") or ""), str(b1.get("fileSetSha256") or ""),
        str(b2.get("baselineId") or ""), str(d5_id or ""),
        str(approved_at or ""), str(d5.get("recordPath") or ""), first_wp_rel,
        wp_id if isinstance(wp_id, str) else None,
        post_rel if isinstance(post_rel, str) else None, errors)

    return {"pass": not errors, "errors": errors, "checked": checked,
            "formal_documents": len(formal), "post_sync_files": len(post_files),
            "d4_tracks": sorted(seen_tracks)}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=Path.cwd())
    parser.add_argument(
        "--source-project-root", type=Path, default=None,
        help="commit/snapshot historical evidence root; defaults to project-root")
    parser.add_argument("--prefix", required=True)
    parser.add_argument("--package", type=Path, required=True,
                        help="W0 handoff package path (project-root relative unless absolute)")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    root = args.project_root.resolve()
    if not root.is_dir():
        parser.error(f"project root does not exist: {root}")
    source_root = (args.source_project_root or root).resolve()
    if not source_root.is_dir():
        parser.error(f"source project root does not exist: {source_root}")
    package_path = args.package if args.package.is_absolute() else root / args.package
    package_path = package_path.resolve()
    try:
        package_path.relative_to(root)
    except ValueError:
        parser.error("--package must stay inside --project-root")
    result = validate(root, args.prefix, package_path, source_root)
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print("PASS" if result["pass"] else "FAIL")
        for error in result["errors"]:
            print(f"ERROR: {error}")
        print(f"formal {result.get('formal_documents', 0)} / "
              f"post-sync {result.get('post_sync_files', 0)} / "
              f"D4 tracks {len(result.get('d4_tracks', []))}")
    return 0 if result["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
