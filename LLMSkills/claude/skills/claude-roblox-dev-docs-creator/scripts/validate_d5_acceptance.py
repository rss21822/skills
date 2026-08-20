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
import math
import os
import re
import secrets
import shutil
import stat
import subprocess
import sys
import tempfile
from functools import total_ordering
from pathlib import Path
from typing import Any

import gen_index
import state_readiness as state_readiness_module
import strict_json as strict_json_module
from state_readiness import scan_readiness_text


SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
RFC3339_RE = re.compile(
    r"^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})"
    r"(?:\.([0-9]{1,7}))?(Z|[+-][0-9]{2}:[0-9]{2})$")
TICKS_PER_SECOND = 10_000_000
EPOCH_UTC = dt.datetime(1970, 1, 1, tzinfo=dt.timezone.utc)


class Duration100ns:
    __slots__ = ("ticks",)

    def __init__(self, ticks: int) -> None:
        self.ticks = ticks

    def total_seconds(self) -> float:
        return self.ticks / TICKS_PER_SECOND


@total_ordering
class Timestamp100ns:
    """UTC instant preserving RFC3339's seventh (100 ns) fractional digit."""

    __slots__ = ("ticks",)

    def __init__(self, ticks: int) -> None:
        self.ticks = ticks

    def __hash__(self) -> int:
        return hash(self.ticks)

    @staticmethod
    def _coerce(value: object) -> int | NotImplemented:
        if isinstance(value, Timestamp100ns):
            return value.ticks
        if isinstance(value, dt.datetime) and value.tzinfo is not None \
                and value.utcoffset() is not None:
            delta = value.astimezone(dt.timezone.utc) - EPOCH_UTC
            return ((delta.days * 86400 + delta.seconds) * TICKS_PER_SECOND
                    + delta.microseconds * 10)
        return NotImplemented

    def __eq__(self, other: object) -> bool:
        value = self._coerce(other)
        return False if value is NotImplemented else self.ticks == value

    def __lt__(self, other: object) -> bool:
        value = self._coerce(other)
        if value is NotImplemented:
            return NotImplemented
        return self.ticks < value

    def __sub__(self, other: object) -> Duration100ns:
        value = self._coerce(other)
        if value is NotImplemented:
            return NotImplemented
        return Duration100ns(self.ticks - value)

    def isoformat(self) -> str:
        seconds, fractional = divmod(self.ticks, TICKS_PER_SECOND)
        base = EPOCH_UTC + dt.timedelta(seconds=seconds)
        fraction = f"{fractional:07d}".rstrip("0")
        suffix = f".{fraction}" if fraction else ""
        return base.strftime("%Y-%m-%dT%H:%M:%S") + suffix + "+00:00"


def _parse_rfc3339_100ns(value: Any) -> Timestamp100ns | None:
    if not isinstance(value, str) or not value or value != value.strip():
        return None
    match = RFC3339_RE.fullmatch(value)
    if match is None:
        return None
    year, month, day, hour, minute, second = map(int, match.groups()[:6])
    fraction = (match.group(7) or "").ljust(7, "0")
    zone = match.group(8)
    if zone == "Z":
        timezone = dt.timezone.utc
    else:
        sign = 1 if zone[0] == "+" else -1
        zone_hour, zone_minute = map(int, zone[1:].split(":"))
        if zone_hour > 14 or zone_minute > 59 \
                or (zone_hour == 14 and zone_minute != 0):
            return None
        timezone = dt.timezone(sign * dt.timedelta(hours=zone_hour, minutes=zone_minute))
    try:
        base = dt.datetime(year, month, day, hour, minute, second, tzinfo=timezone)
    except ValueError:
        return None
    delta = base.astimezone(dt.timezone.utc) - EPOCH_UTC
    ticks = ((delta.days * 86400 + delta.seconds) * TICKS_PER_SECOND
             + int(fraction or "0"))
    return Timestamp100ns(ticks)
WP_STATUS_RE = re.compile(r"(?im)^\s*[-*]\s*Status\s*[:：]\s*`?Approved`?\s*$")
PROVENANCE_CONFIG_KEYS = {
    "schemaVersion", "d4RuntimePins", "w0ValidatorRuntime",
    "trustedRuntimeAdapters", "signatureVerifiers",
}
PROVENANCE_RUNNER_KEYS = {
    "id", "authority", "adapter", "adapterVersion", "launchMode",
    "executable", "adapterArtifact",
    "supportArtifacts", "runtimeLibraryRoots", "staticArgs", "inputProtocol",
    "allowedEnvNames", "timeoutSeconds", "maxOutputBytes",
}
SIGNATURE_RUNNER_KEYS = (PROVENANCE_RUNNER_KEYS - {"adapter", "adapterVersion"}) | {
    "algorithm", "keyId", "trustAnchor"}
EXTERNAL_FILE_REF_KEYS = {"path", "sha256"}
COPY_ARTIFACT_REF_KEYS = {"path", "sha256", "copyPath"}
TRUSTED_QUERY_RESULT_KEYS = {
    "schemaVersion", "id", "authority", "adapter", "adapterVersion", "nonce",
    "queriedAt", "requestId", "responseId", "subjectType", "subjectId",
    "claimsSha256", "rawResponseArtifact",
}
PINNED_SIGNATURE_EVIDENCE_KEYS = {
    "schemaVersion", "id", "authority", "algorithm", "keyId", "verifiedAt",
    "claimsSha256", "trustAnchorArtifact", "signedPayloadArtifact",
    "signatureArtifact",
}
PROVENANCE_VERIFICATION_KEYS = {
    "schemaVersion", "id", "subjectType", "subject", "verificationMode",
    "verifier", "sourceArtifact", "verificationContext", "verifiedAt", "claims",
    "claimsSha256", "verdict",
}
INSTALLED_SKILL_ROOT: Path | None = None


def installed_skill_root(errors: list[str] | None = None) -> Path:
    if INSTALLED_SKILL_ROOT is None:
        if errors is not None:
            errors.append("--installed-skill-root is required; copied __file__ is not authoritative")
        return Path(__file__).resolve().parent.parent
    return INSTALLED_SKILL_ROOT


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def timezone_datetime(value: Any) -> bool:
    return _parse_rfc3339_100ns(value) is not None


def manifest_status(raw: Any, path: str, errors: list[str]) -> str | None:
    try:
        return gen_index.normalize_status(raw if isinstance(raw, str) else "", path)
    except SystemExit as exc:
        errors.append(str(exc))
        return None


def load_json(path: Path, errors: list[str], label: str) -> dict[str, Any] | None:
    # All security/lifecycle JSON enters through the same duplicate- and
    # non-finite-rejecting parser.  JSON Schema cannot observe a duplicate key
    # after a last-wins parser has already collapsed it.
    return strict_json_file(path, errors, label)


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


def prescan_forbidden_query_provenance(
        root: Path, package: dict[str, Any], errors: list[str]) -> bool:
    """Reject W0 query provenance before loading or invoking any external runner.

    The walk follows project-relative JSON references reachable from the selected
    package.  This keeps unrelated historical evidence out of scope while making
    the offline-only decision before Python/version probes or verifier adapters.
    Hash/schema validation still happens in the normal pass after this zero-runner
    pre-scan.
    """
    queue: list[Any] = [package]
    seen_paths: set[Path] = set()
    found = False
    while queue:
        value = queue.pop()
        if isinstance(value, list):
            queue.extend(value)
            continue
        if not isinstance(value, dict):
            continue
        mode = value.get("verificationMode")
        if mode == "trusted-runtime-query":
            errors.append(
                "W0 lifecycle v1 forbids trusted-runtime-query provenance; "
                "offline pinned-signature evidence is required and no external "
                "runner was invoked")
            found = True
        queue.extend(value.values())
        raw_path = value.get("path")
        expected_hash = value.get("sha256")
        if not isinstance(raw_path, str) or not raw_path.lower().endswith(".json") \
                or not isinstance(expected_hash, str):
            continue
        candidate = resolve_path(root, raw_path, [], "offline provenance pre-scan")
        if candidate is None or candidate in seen_paths or not candidate.is_file():
            continue
        seen_paths.add(candidate)
        loaded = strict_json_file(candidate, [], "offline provenance pre-scan")
        if loaded is not None:
            queue.append(loaded)
    return found


def canonical_file_set_hash(files: list[Any]) -> str:
    payload = json.dumps(files, ensure_ascii=False, sort_keys=True,
                         separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def identity_key(value: Any) -> str:
    """Case/path-normalized key for IDs and project-relative artifact refs."""
    def normalize(item: Any) -> Any:
        if isinstance(item, dict):
            return {str(key).casefold(): normalize(val)
                    for key, val in sorted(item.items(), key=lambda pair: str(pair[0]))}
        if isinstance(item, list):
            return [normalize(val) for val in item]
        if isinstance(item, str):
            return item.replace("\\", "/").casefold()
        return item
    return json.dumps(normalize(value), ensure_ascii=False, sort_keys=True,
                      separators=(",", ":"))


def canonical_json_bytes(value: Any) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")


def canonical_json_sha256(value: Any) -> str:
    return hashlib.sha256(canonical_json_bytes(value)).hexdigest()


def outside_roots(path: Path, roots: tuple[Path, ...]) -> bool:
    for root in roots:
        try:
            path.relative_to(root)
            return False
        except ValueError:
            pass
        try:
            root.relative_to(path)
            return False
        except ValueError:
            pass
    return True


def strict_json_file(path: Path, errors: list[str], label: str) -> dict[str, Any] | None:
    class DuplicateKey(ValueError):
        pass

    def closed_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise DuplicateKey(f"duplicate key {key!r}")
            result[key] = value
        return result

    try:
        value = json.loads(
            path.read_text(encoding="utf-8-sig"), object_pairs_hook=closed_pairs,
            parse_constant=lambda token: (_ for _ in ()).throw(
                ValueError(f"non-finite JSON constant {token!r}")))
    except (OSError, UnicodeError, json.JSONDecodeError, DuplicateKey, ValueError) as exc:
        errors.append(f"{label}: cannot read strict JSON {path}: {exc}")
        return None
    if not isinstance(value, dict):
        errors.append(f"{label}: root must be an object")
        return None
    return value


def external_path(
        raw: Any, roots: tuple[Path, ...], errors: list[str], label: str,
        *, file: bool) -> Path | None:
    if not isinstance(raw, str) or not raw.strip():
        errors.append(f"{label}: absolute path is required")
        return None
    candidate = Path(raw)
    if not candidate.is_absolute():
        errors.append(f"{label}: path must be absolute")
        return None
    try:
        candidate = candidate.resolve(strict=True)
    except OSError as exc:
        errors.append(f"{label}: path cannot be resolved: {exc}")
        return None
    if not outside_roots(candidate, roots):
        errors.append(f"{label}: path must stay outside project and installed-skill roots")
        return None
    if not file:
        for protected in roots:
            try:
                protected.resolve(strict=True).relative_to(candidate)
            except (OSError, ValueError):
                continue
            errors.append(
                f"{label}: directory must not contain a project or installed-skill root")
            return None
    if file and not candidate.is_file():
        errors.append(f"{label}: path must resolve to a file")
        return None
    if not file and not candidate.is_dir():
        errors.append(f"{label}: path must resolve to a directory")
        return None
    return candidate


def validate_external_file_ref(
        value: Any, roots: tuple[Path, ...], errors: list[str],
        label: str) -> Path | None:
    if not isinstance(value, dict) or set(value) != EXTERNAL_FILE_REF_KEYS:
        errors.append(f"{label}: external file reference has unknown/missing fields")
        return None
    path = external_path(value.get("path"), roots, errors, f"{label}.path", file=True)
    expected = value.get("sha256")
    if not isinstance(expected, str) or SHA256_RE.fullmatch(expected) is None:
        errors.append(f"{label}.sha256 must be 64 lowercase hex characters")
    elif path is not None and sha256(path) != expected:
        errors.append(f"{label}: externally pinned sha256 mismatch")
    return path


def validate_external_copy_ref(
        value: Any, roots: tuple[Path, ...], errors: list[str],
        label: str) -> Path | None:
    if not isinstance(value, dict) or set(value) != COPY_ARTIFACT_REF_KEYS:
        errors.append(f"{label}: copy artifact pin has unknown/missing fields")
        return None
    path = external_path(value.get("path"), roots, errors, f"{label}.path", file=True)
    expected = value.get("sha256")
    if not isinstance(expected, str) or SHA256_RE.fullmatch(expected) is None:
        errors.append(f"{label}.sha256 must be 64 lowercase hex characters")
    elif path is not None and sha256(path) != expected:
        errors.append(f"{label}: externally pinned sha256 mismatch")
    copy_path = value.get("copyPath")
    if not isinstance(copy_path, str) or re.fullmatch(
            r"(?!/)(?!.*(?:^|/)\.\.?($|/))(?!.*\\)(?!.*//)"
            r"[A-Za-z0-9._-]+(?:/[A-Za-z0-9._-]+)*", copy_path or "") is None:
        errors.append(f"{label}.copyPath is not safe canonical relative POSIX")
    return path


def validate_skill_copy_ref(
        value: Any, skill_root: Path, expected_rel: str,
        errors: list[str], label: str) -> Path | None:
    if not isinstance(value, dict) or set(value) != COPY_ARTIFACT_REF_KEYS:
        errors.append(f"{label}: installed-skill copy pin has unknown/missing fields")
        return None
    try:
        path = Path(value.get("path", "")).resolve(strict=True)
    except (OSError, TypeError) as exc:
        errors.append(f"{label}.path cannot be resolved: {exc}")
        return None
    expected = (skill_root / expected_rel).resolve()
    if path != expected or not path.is_file():
        errors.append(f"{label}.path must equal installed {expected_rel}")
    if value.get("sha256") != sha256(expected):
        errors.append(f"{label}.sha256 does not pin installed {expected_rel}")
    copy_path = value.get("copyPath")
    if not isinstance(copy_path, str) or re.fullmatch(
            r"(?!/)(?!.*(?:^|/)\.\.?($|/))(?!.*\\)(?!.*//)"
            r"[A-Za-z0-9._-]+(?:/[A-Za-z0-9._-]+)*", copy_path or "") is None:
        errors.append(f"{label}.copyPath is invalid")
    return path


def validate_library_root_pin(
        value: Any, roots: tuple[Path, ...], errors: list[str],
        label: str, *, pinned_root: Path | None = None) -> dict[str, Any] | None:
    expected = {
        "path", "manifestFormat", "manifestPath", "manifestSha256", "treeSha256"}
    if not isinstance(value, dict) or set(value) != expected:
        errors.append(f"{label}: library-root pin has unknown/missing fields")
        return None
    if value.get("manifestFormat") != "canonical-library-tree-v1":
        errors.append(f"{label}.manifestFormat must be canonical-library-tree-v1")
    if pinned_root is None:
        library_root = external_path(
            value.get("path"), roots, errors, f"{label}.path", file=False)
    else:
        try:
            configured_root = Path(value.get("path", "")).resolve(strict=True)
        except (OSError, TypeError) as exc:
            errors.append(f"{label}.path cannot be resolved: {exc}")
            configured_root = None
        library_root = pinned_root.resolve()
        if configured_root != library_root or not library_root.is_dir():
            errors.append(f"{label}.path must equal the installed skill root")
            library_root = None
    manifest = external_path(
        value.get("manifestPath"), roots, errors, f"{label}.manifestPath", file=True)
    for key in ("manifestSha256", "treeSha256"):
        if not isinstance(value.get(key), str) or SHA256_RE.fullmatch(value[key]) is None:
            errors.append(f"{label}.{key} must be 64 lowercase hex characters")
    if manifest is not None and isinstance(value.get("manifestSha256"), str) \
            and sha256(manifest) != value["manifestSha256"]:
        errors.append(f"{label}: library manifest sha256 mismatch")
    if library_root is None or manifest is None:
        return None
    if pinned_root is None:
        for protected_root in roots:
            try:
                protected_root.resolve().relative_to(library_root)
            except ValueError:
                continue
            errors.append(f"{label}.path must not contain a protected project/skill root")
    try:
        manifest.relative_to(library_root)
    except ValueError:
        pass
    else:
        errors.append(f"{label}.manifestPath must stay outside the pinned library root")
    raw_manifest = strict_json_file(manifest, errors, f"{label}.manifest")
    if not isinstance(raw_manifest, dict) or set(raw_manifest) != {"files"}:
        errors.append(f"{label}.manifest must be a closed files object")
    files = raw_manifest.get("files") if isinstance(raw_manifest, dict) else None
    if not isinstance(files, list):
        errors.append(f"{label}.manifest must be a closed object with files array")
        files = []
    expected_files: list[dict[str, Any]] = []
    for path in sorted(library_root.rglob("*"), key=lambda item: item.as_posix()):
        try:
            info = path.lstat()
        except OSError as exc:
            errors.append(f"{label}: cannot stat pinned library entry: {exc}")
            continue
        reparse = bool(getattr(info, "st_file_attributes", 0)
                       & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400))
        if path.is_symlink() or reparse:
            errors.append(f"{label}: pinned library contains symlink/reparse point")
            continue
        if path.is_dir():
            continue
        if not path.is_file():
            errors.append(f"{label}: pinned library contains special file")
            continue
        expected_files.append({
            "path": path.relative_to(library_root).as_posix(),
            "bytes": path.stat().st_size, "sha256": sha256(path),
        })
    if isinstance(files, list) and any(not isinstance(item, dict) or set(item) != {
            "path", "bytes", "sha256"} for item in files):
        errors.append(f"{label}.manifest rows must be closed path/bytes/sha256 objects")
    if files != expected_files:
        errors.append(f"{label}: pinned library manifest does not exact-cover current tree")
    expected_manifest_bytes = canonical_json_bytes({"files": expected_files})
    try:
        manifest_bytes = manifest.read_bytes()
    except OSError as exc:
        errors.append(f"{label}: cannot read pinned library manifest bytes: {exc}")
    else:
        if manifest_bytes != expected_manifest_bytes:
            errors.append(
                f"{label}: library manifest must be exact canonical JSON without newline")
    actual_tree = canonical_json_sha256(expected_files)
    if value.get("treeSha256") != actual_tree:
        errors.append(f"{label}: library treeSha256 mismatch: {actual_tree}")
    return dict(value, _path=library_root, _manifest=manifest)


def python_is_covered(
        python_pin: dict[str, Any] | None, libraries: list[Any],
        errors: list[str], label: str) -> None:
    python_path = python_pin.get("_path") if isinstance(python_pin, dict) else None
    roots = [item.get("_path") for item in libraries if isinstance(item, dict)]
    if not isinstance(python_path, Path) or not any(
            isinstance(root, Path)
            and (python_path == root or root in python_path.parents)
            for root in roots):
        errors.append(f"{label}: pinned Python must be inside a complete library root")


def validate_unique_library_roots(
        libraries: list[Any], errors: list[str], label: str) -> None:
    """Reject duplicate normalized runtime roots even when pin objects differ."""
    seen: set[str] = set()
    for item in libraries:
        root = item.get("_path") if isinstance(item, dict) else None
        if not isinstance(root, Path):
            continue
        key = os.path.normcase(str(root.resolve()))
        if key in seen:
            errors.append(f"{label} must contain unique normalized root paths")
        seen.add(key)


def validate_python_pin(
        value: Any, roots: tuple[Path, ...], errors: list[str],
        label: str) -> dict[str, Any] | None:
    if not isinstance(value, dict) or set(value) != {
            "path", "bytes", "sha256", "version", "fixedArgs"}:
        errors.append(f"{label}: Python pin has unknown/missing fields")
        return None
    path = external_path(value.get("path"), roots, errors, f"{label}.path", file=True)
    if value.get("fixedArgs") != ["-B", "-S", "-E", "-X", "utf8"]:
        errors.append(f"{label}.fixedArgs must equal -B -S -E -X utf8")
    if type(value.get("bytes")) is not int or value.get("bytes", 0) < 1:
        errors.append(f"{label}.bytes must be a positive integer")
    if not isinstance(value.get("sha256"), str) or SHA256_RE.fullmatch(
            value.get("sha256", "")) is None:
        errors.append(f"{label}.sha256 must be 64 lowercase hex characters")
    if not isinstance(value.get("version"), str) or not value["version"].strip():
        errors.append(f"{label}.version must be non-empty")
    if path is not None:
        if path.stat().st_size != value.get("bytes") or sha256(path) != value.get("sha256"):
            errors.append(f"{label}: pinned Python bytes/hash mismatch")
        try:
            version = subprocess.run(
                [str(path), "-B", "-S", "-E", "-X", "utf8", "--version"],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20,
                shell=False, env={key: os.environ[key] for key in ("SYSTEMROOT", "WINDIR")
                                  if key in os.environ}).stdout.decode("utf-8").strip()
        except (OSError, UnicodeError, subprocess.SubprocessError) as exc:
            errors.append(f"{label}: cannot resolve pinned Python version: {exc}")
        else:
            if version != value.get("version"):
                errors.append(f"{label}: pinned Python version mismatch: {version!r}")
    return dict(value, _path=path)


def validate_binary_pin(
        value: Any, roots: tuple[Path, ...], errors: list[str],
        label: str, *, nullable: bool = False) -> dict[str, Any] | None:
    if value is None and nullable:
        return None
    if not isinstance(value, dict) or set(value) != {"path", "bytes", "sha256"}:
        errors.append(f"{label}: binary pin has unknown/missing fields")
        return None
    path = external_path(value.get("path"), roots, errors, f"{label}.path", file=True)
    if type(value.get("bytes")) is not int or value.get("bytes", 0) < 1 \
            or not isinstance(value.get("sha256"), str) \
            or SHA256_RE.fullmatch(value.get("sha256", "")) is None:
        errors.append(f"{label}: bytes/hash is invalid")
    elif path is not None and (path.stat().st_size != value["bytes"] \
            or sha256(path) != value["sha256"]):
        errors.append(f"{label}: binary bytes/hash mismatch")
    return dict(value, _path=path)


def validate_installed_file_pin(
        value: Any, skill_root: Path, expected_rel: str,
        errors: list[str], label: str) -> Path | None:
    if not isinstance(value, dict) or set(value) != {"path", "sha256"}:
        errors.append(f"{label}: installed file pin has unknown/missing fields")
        return None
    expected = (skill_root / expected_rel).resolve()
    try:
        actual = Path(value.get("path", "")).resolve(strict=True)
    except (OSError, TypeError) as exc:
        errors.append(f"{label}.path cannot be resolved: {exc}")
        return None
    if actual != expected or not actual.is_file():
        errors.append(f"{label}.path must equal installed {expected_rel}")
    expected_hash = value.get("sha256")
    if not isinstance(expected_hash, str) or SHA256_RE.fullmatch(expected_hash) is None:
        errors.append(f"{label}.sha256 must be 64 lowercase hex characters")
    elif expected.is_file() and sha256(expected) != expected_hash:
        errors.append(f"{label}.sha256 does not pin installed {expected_rel}")
    return actual


def validate_receiver_bootstrap_config(
        value: Any, roots: tuple[Path, ...], skill_root: Path,
        errors: list[str]) -> dict[str, Any] | None:
    label = "w0ValidatorRuntime.receiverBootstrap"
    expected_keys = {
        "script", "hostExecutable", "hostVersion", "hostFixedArgs",
        "hostRuntimeRoots", "trustBoundary", "threePhaseProtocol",
        "phaseFlag", "phaseValues", "phaseInvocationProtocol", "phaseArgvTailGrammar",
    }
    if not isinstance(value, dict) or set(value) != expected_keys:
        errors.append(f"{label} has unknown/missing fields")
        return None
    script = validate_installed_file_pin(
        value.get("script"), skill_root, "scripts/w0_receiver_bootstrap.ps1",
        errors, f"{label}.script")
    host = validate_binary_pin(
        value.get("hostExecutable"), roots, errors, f"{label}.hostExecutable")
    raw_roots = value.get("hostRuntimeRoots")
    if not isinstance(raw_roots, list) or not raw_roots:
        errors.append(f"{label}.hostRuntimeRoots must be non-empty")
        raw_roots = []
    host_roots = [validate_library_root_pin(
        item, roots, errors, f"{label}.hostRuntimeRoots[{index}]")
        for index, item in enumerate(raw_roots)]
    validate_unique_library_roots(host_roots, errors, f"{label}.hostRuntimeRoots")
    python_is_covered(host, host_roots, errors, f"{label}.hostExecutable")
    constants = {
        "hostFixedArgs": [
            "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy",
            "Bypass", "-File"],
        "trustBoundary": "operator-pinned-powershell-os-host-and-bootstrap-v1",
        "threePhaseProtocol": "prepare-validate-admit-continuous-lock-v1",
        "phaseFlag": "-Phase",
        "phaseValues": ["PREPARE", "VALIDATE", "ADMIT"],
        "phaseInvocationProtocol":
            "host-fixed-args-script-phase-first-absolute-named-paths-v1",
        "phaseArgvTailGrammar": {
            "PREPARE": ["-ConfigPath", "<ABS>", "-ExpectedConfigSha256", "<LOWER64HEX>", "-PackagePath", "<ABS>",
                        "-ProjectRoot", "<ABS>", "-LaunchChallengeOutputPath", "<ABS>",
                        "-AuthorizationEvidenceRoot", "<ABS>"],
            "VALIDATE": ["-ConfigPath", "<ABS>", "-ExpectedConfigSha256", "<LOWER64HEX>", "-PackagePath", "<ABS>",
                         "-ProjectRoot", "<ABS>", "-LaunchChallengePath", "<ABS>",
                         "-PrepareAttestationPath", "<ABS>", "-PrepareSignaturePath", "<ABS>",
                         "-PrelaunchAssertionPath", "<ABS>", "-PrelaunchSignaturePath", "<ABS>",
                         "-PostexecutionAttestationPath", "<ABS>",
                         "-PostexecutionSignaturePath", "<ABS>"],
            "ADMIT": ["-ConfigPath", "<ABS>", "-ExpectedConfigSha256", "<LOWER64HEX>", "-PackagePath", "<ABS>",
                      "-ProjectRoot", "<ABS>", "-LaunchChallengePath", "<ABS>",
                      "-PresentationPath", "<ABS>", "-HumanChallengePath", "<ABS>",
                      "-TranscriptPath", "<ABS>", "-StatementPath", "<ABS>",
                      "-CapturePath", "<ABS>", "-CaptureProvenancePath", "<ABS>",
                      "-RunAuthorizationPath", "<ABS>",
                      "-RunAdmissionAttestationPath", "<ABS>",
                      "-RunAdmissionSignaturePath", "<ABS>",
                      "-AdmitExecutionAttestationPath", "<ABS>",
                      "-AdmitExecutionSignaturePath", "<ABS>"],
        },
    }
    for key, expected in constants.items():
        if value.get(key) != expected:
            errors.append(f"{label}.{key} does not match the v1 receiver contract")
    if not isinstance(value.get("hostVersion"), str) or not value["hostVersion"].strip():
        errors.append(f"{label}.hostVersion must be non-empty")
    return dict(value, _script=script, _hostExecutable=host,
                _hostRuntimeRoots=host_roots)


def validate_immutable_runtime_authority_config(
        value: Any, roots: tuple[Path, ...], errors: list[str]) -> dict[str, Any] | None:
    label = "w0ValidatorRuntime.immutableRuntimeAuthority"
    expected_keys = {
        "authority", "verificationMode", "keyId", "trustAnchor",
        "trustAnchorFormat", "prepareExecutionSchemaId", "prelaunchSchemaId",
        "postexecutionSchemaId", "runAuthorizationSchemaId", "runAdmissionSchemaId",
        "admitExecutionSchemaId",
        "detachedSignatureProtocol", "signedBytesSerialization", "signatureEncoding",
        "rsaPssSaltLength", "argvDigestProtocol", "cwdDigestProtocol",
        "envDigestProtocol", "projectTreeDigestProtocol", "readInputDigestProtocol",
        "readInputIdentityDigestProtocol", "assertionInputs",
        "maxPrelaunchAgeSeconds", "maxAdmissionLifetimeSeconds",
        "maxWorkerReadyLifetimeSeconds", "maxClockSkewSeconds",
    }
    if not isinstance(value, dict) or set(value) != expected_keys:
        errors.append(f"{label} has unknown/missing fields")
        return None
    for key in ("authority", "keyId"):
        if not isinstance(value.get(key), str) or not value[key].strip():
            errors.append(f"{label}.{key} must be non-empty")
    constants = {
        "verificationMode": "receiver-native-rsa-pss-sha256",
        "trustAnchorFormat": "x509-der",
        "prepareExecutionSchemaId":
            "https://example.invalid/roblox-ai-development-os/w0-runtime-prepare-execution-attestation.schema.json",
        "prelaunchSchemaId":
            "https://example.invalid/roblox-ai-development-os/w0-runtime-prelaunch-assertion.schema.json",
        "postexecutionSchemaId":
            "https://example.invalid/roblox-ai-development-os/w0-runtime-postexecution-attestation.schema.json",
        "runAuthorizationSchemaId":
            "https://example.invalid/roblox-ai-development-os/w0-run-authorization.schema.json",
        "runAdmissionSchemaId":
            "https://example.invalid/roblox-ai-development-os/w0-run-admission-attestation.schema.json",
        "admitExecutionSchemaId":
            "https://example.invalid/roblox-ai-development-os/w0-runtime-admit-execution-attestation.schema.json",
        "detachedSignatureProtocol":
            "raw-fixed-order-json-detached-rsa-pss-sha256-v1",
        "signedBytesSerialization":
            "fixed-property-order-minified-utf8-no-bom-no-newline-v1",
        "signatureEncoding": "base64-text-no-whitespace",
        "rsaPssSaltLength": "hash-length",
        "argvDigestProtocol": "utf8-nul-joined-no-trailing-nul-v1",
        "cwdDigestProtocol": "normalized-absolute-path-utf8-v1",
        "envDigestProtocol":
            "ordinal-name-equals-value-utf8-nul-joined-no-trailing-nul-v1",
        "projectTreeDigestProtocol": "all-regular-project-files-canonical-json-v1",
        "readInputDigestProtocol": "sorted-read-input-records-canonical-json-v1",
        "readInputIdentityDigestProtocol":
            "authority-observed-read-input-identities-canonical-json-v1",
    }
    for key, expected in constants.items():
        if value.get(key) != expected:
            errors.append(f"{label}.{key} does not match the v1 receiver contract")
    anchor = validate_external_file_ref(
        value.get("trustAnchor"), roots, errors, f"{label}.trustAnchor")
    assertion = value.get("assertionInputs")
    assertion_constants = {
        "pathSource":
            "validate-challenge-plus-six-and-admit-external-input-set-absolute-cli-paths-only",
        "expectedConfigHashSource":
            "operator-authority-or-user-out-of-band-lower64hex-never-config-project-package",
        "challengeSource": "pinned-bootstrap-cryptographic-rng-before-authority-issuance",
        "challengeInputs": "schema-valid-launch-challenge-with-run-id-nonce-temp-and-digests",
        "prepareExecutionAvailability":
            "prepare-attestation-and-signature-created-by-authority-after-monitored-prepare-before-prelaunch",
        "prelaunchAvailability":
            "assertion-and-signature-exist-before-launch-and-remain-byte-identical",
        "postexecutionAvailability":
            "attestation-and-signature-absent-before-validate-created-by-authority-after-validator-exit",
        "runAuthorizationAvailability":
            "external-human-chain-and-authorization-created-after-post-pass-under-continuous-lock-before-admit",
        "runAdmissionAvailability":
            "admission-attestation-and-signature-created-after-run-authorization-before-admit-invocation",
        "admitExecutionAvailability":
            "receipt-and-signature-paths-predeclared-and-absent-before-admit-created-by-authority-after-semantic-pass-token-consumption-and-suspended-worker-observation",
        "admitPathSet": [
            "presentation", "challenge", "transcript", "statement", "capture",
            "capture-provenance", "run-authorization", "run-admission-attestation",
            "run-admission-signature", "admit-execution-attestation",
            "admit-execution-signature"],
    }
    if not isinstance(assertion, dict) or set(assertion) != set(assertion_constants):
        errors.append(f"{label}.assertionInputs has unknown/missing fields")
    else:
        for key, expected in assertion_constants.items():
            if assertion.get(key) != expected:
                errors.append(f"{label}.assertionInputs.{key} is invalid")
    limits = {
        "maxPrelaunchAgeSeconds": (1, 300),
        "maxAdmissionLifetimeSeconds": (1, 60),
        "maxWorkerReadyLifetimeSeconds": (1, 60),
        "maxClockSkewSeconds": (0, 30),
    }
    for key, (minimum, maximum) in limits.items():
        current = value.get(key)
        if type(current) is not int or not minimum <= current <= maximum:
            errors.append(f"{label}.{key} must be {minimum}..{maximum}")
    return dict(value, _trustAnchor=anchor)


def validate_runner_config(
        item: Any, roots: tuple[Path, ...], errors: list[str], label: str,
        *, signature: bool) -> dict[str, Any] | None:
    expected_keys = SIGNATURE_RUNNER_KEYS if signature else PROVENANCE_RUNNER_KEYS
    if not isinstance(item, dict) or set(item) != expected_keys:
        errors.append(f"{label}: runner has unknown/missing fields")
        return None
    required_strings = ["id", "authority"]
    if not signature:
        required_strings += ["adapter", "adapterVersion"]
    for key in required_strings:
        if not isinstance(item.get(key), str) or not item[key].strip():
            errors.append(f"{label}.{key} must be non-empty")
    executable = validate_external_file_ref(
        item.get("executable"), roots, errors, f"{label}.executable")
    adapter_artifact = validate_external_copy_ref(
        item.get("adapterArtifact"), roots, errors, f"{label}.adapterArtifact")
    support = item.get("supportArtifacts")
    if not isinstance(support, list):
        errors.append(f"{label}.supportArtifacts must be an array")
        support = []
    support_paths = [
        validate_external_copy_ref(value, roots, errors, f"{label}.supportArtifacts[{index}]")
        for index, value in enumerate(support)]
    copy_names = [str(value.get("copyPath", "")).casefold()
                  for value in [item.get("adapterArtifact"), *support]
                  if isinstance(value, dict)]
    if len(copy_names) != len(set(copy_names)):
        errors.append(f"{label}: adapter/support copyPath values must be unique")
    if item.get("launchMode") not in {
            "host-with-adapter-arg", "adapter-is-executable"}:
        errors.append(f"{label}.launchMode is invalid")
    if item.get("launchMode") == "adapter-is-executable" \
            and isinstance(item.get("executable"), dict) \
            and isinstance(item.get("adapterArtifact"), dict) \
            and item["executable"].get("sha256") != item["adapterArtifact"].get("sha256"):
        errors.append(f"{label}: adapter-is-executable pins must have identical hashes")
    library_values = item.get("runtimeLibraryRoots")
    if not isinstance(library_values, list) or not library_values:
        errors.append(f"{label}.runtimeLibraryRoots must be a non-empty array")
        library_values = []
    libraries = [
        validate_library_root_pin(value, roots, errors, f"{label}.runtimeLibraryRoots[{index}]")
        for index, value in enumerate(library_values)]
    library_roots = [value.get("_path") for value in libraries if isinstance(value, dict)]
    if not isinstance(executable, Path) or not any(
            isinstance(library_root, Path)
            and (executable == library_root or library_root in executable.parents)
            for library_root in library_roots):
        errors.append(f"{label}.executable must be an exact member of a pinned runtimeLibraryRoot")
    static_args = item.get("staticArgs")
    if not isinstance(static_args, list) or any(
            not isinstance(token, str) for token in static_args):
        errors.append(f"{label}.staticArgs must be a literal string array")
        static_args = []
    elif any(re.search(r"\{\{|\$\{|%[A-Za-z_][A-Za-z0-9_]*%", token)
             for token in static_args):
        errors.append(f"{label}.staticArgs cannot contain runtime placeholders")
    if item.get("inputProtocol") != "json-stdin-v1":
        errors.append(f"{label}.inputProtocol must be json-stdin-v1")
    env_names = item.get("allowedEnvNames")
    if not isinstance(env_names, list) or any(
            not isinstance(name, str) or re.fullmatch(
                r"[A-Za-z_][A-Za-z0-9_]*", name) is None
            for name in env_names):
        errors.append(f"{label}.allowedEnvNames must be an uppercase-name array")
        env_names = []
    elif len(env_names) != len(set(env_names)):
        errors.append(f"{label}.allowedEnvNames must be unique")
    banned_env = re.compile(r"^(?:PATH|PATHEXT|PYTHON.*|LD_.*|DYLD_.*)$", re.IGNORECASE)
    if any(banned_env.fullmatch(name) for name in env_names):
        errors.append(f"{label}.allowedEnvNames contains a loader/search-path variable")
    timeout = item.get("timeoutSeconds")
    cap = item.get("maxOutputBytes")
    if type(timeout) is not int or not 1 <= timeout <= 600:
        errors.append(f"{label}.timeoutSeconds must be an integer from 1 to 600")
    if type(cap) is not int or not 1 <= cap <= 100 * 1024 * 1024:
        errors.append(f"{label}.maxOutputBytes must be 1..104857600")
    if signature:
        if item.get("algorithm") not in {
                "ed25519", "ecdsa-p256-sha256", "rsa-pss-sha256"}:
            errors.append(f"{label}.algorithm is invalid")
        if not isinstance(item.get("keyId"), str) or not item["keyId"].strip():
            errors.append(f"{label}.keyId must be non-empty")
        validate_external_copy_ref(
            item.get("trustAnchor"), roots, errors, f"{label}.trustAnchor")
    return dict(
        item, _executable=executable, _adapterArtifact=adapter_artifact,
        _supportArtifacts=support_paths, _runtimeLibraryRoots=libraries)


def load_provenance_runtime(
        config_path: Path | None, root: Path, skill_root: Path,
        errors: list[str], *, require_w0_execution: bool = True) -> dict[str, Any] | None:
    if config_path is None:
        errors.append("--provenance-config is required; auto-discovery is forbidden")
        return None
    roots = (root.resolve(), skill_root.resolve())
    if not config_path.is_absolute():
        errors.append("--provenance-config must be an absolute path")
        return None
    resolved = external_path(
        str(config_path), roots, errors, "--provenance-config", file=True)
    if resolved is None:
        return None
    config = strict_json_file(resolved, errors, "provenance verifier config")
    if config is None:
        return None
    if set(config) != PROVENANCE_CONFIG_KEYS:
        errors.append("provenance verifier config has unknown/missing fields")
    if config.get("schemaVersion") != "1.0.0":
        errors.append("provenance verifier config.schemaVersion must be 1.0.0")
    trusted_raw = config.get("trustedRuntimeAdapters")
    signature_raw = config.get("signatureVerifiers")
    d4_raw = config.get("d4RuntimePins")
    w0_raw = config.get("w0ValidatorRuntime")
    if not isinstance(d4_raw, list) or not d4_raw:
        errors.append("provenance verifier config.d4RuntimePins must be a non-empty array")
        d4_raw = []
    if not isinstance(trusted_raw, list):
        errors.append("provenance verifier config.trustedRuntimeAdapters must be an array")
        trusted_raw = []
    if not isinstance(signature_raw, list):
        errors.append("provenance verifier config.signatureVerifiers must be an array")
        signature_raw = []
    d4_pins: dict[str, dict[str, Any]] = {}
    for index, item in enumerate(d4_raw):
        label = f"d4RuntimePins[{index}]"
        if not isinstance(item, dict) or set(item) != {
                "id", "pythonExecutable", "readOnlyLibraryRoots",
                "gitExecutable", "gitRuntimeRoots"}:
            errors.append(f"{label} has unknown/missing fields")
            continue
        pin_id = item.get("id")
        if not isinstance(pin_id, str) or not pin_id.strip():
            errors.append(f"{label}.id must be non-empty")
            continue
        python_pin = validate_python_pin(
            item.get("pythonExecutable"), roots, errors, f"{label}.pythonExecutable")
        raw_libraries = item.get("readOnlyLibraryRoots")
        if not isinstance(raw_libraries, list) or not raw_libraries:
            errors.append(f"{label}.readOnlyLibraryRoots must be non-empty")
            raw_libraries = []
        libraries = [validate_library_root_pin(
            value, roots, errors, f"{label}.readOnlyLibraryRoots[{library_index}]")
            for library_index, value in enumerate(raw_libraries)]
        python_is_covered(python_pin, libraries, errors, f"{label}.pythonExecutable")
        git_pin = validate_binary_pin(
            item.get("gitExecutable"), roots, errors, f"{label}.gitExecutable",
            nullable=True)
        git_roots_raw = item.get("gitRuntimeRoots")
        if not isinstance(git_roots_raw, list):
            errors.append(f"{label}.gitRuntimeRoots must be an array")
            git_roots_raw = []
        git_roots = [validate_library_root_pin(
            value, roots, errors, f"{label}.gitRuntimeRoots[{root_index}]")
            for root_index, value in enumerate(git_roots_raw)]
        if git_pin is None and git_roots_raw:
            errors.append(f"{label}.gitRuntimeRoots must be empty without gitExecutable")
        if git_pin is not None and not git_roots_raw:
            errors.append(f"{label}.gitRuntimeRoots is required with gitExecutable")
        key = identity_key(pin_id)
        if key in d4_pins:
            errors.append(f"{label}.id must be unique")
        d4_pins[key] = dict(
            item, _pythonExecutable=python_pin, _readOnlyLibraryRoots=libraries,
            _gitExecutable=git_pin, _gitRuntimeRoots=git_roots)

    w0_runtime: dict[str, Any] | None = None
    w0_keys = {
        "id", "installedSkillRoot", "installedSkillReadClosure",
        "pythonExecutable", "validatorEntrypoint", "supportArtifacts",
        "readOnlyLibraryRoots", "gitExecutable", "gitRuntimeRoots",
        "receiverBootstrap", "immutableRuntimeAuthority",
    }
    if require_w0_execution and (not isinstance(w0_raw, dict) or set(w0_raw) != w0_keys):
        errors.append("w0ValidatorRuntime has unknown/missing fields")
    elif require_w0_execution:
        if not isinstance(w0_raw.get("id"), str) or not w0_raw["id"].strip():
            errors.append("w0ValidatorRuntime.id must be non-empty")
        try:
            configured_skill_root = Path(w0_raw.get("installedSkillRoot", "")).resolve(
                strict=True)
        except (OSError, TypeError) as exc:
            errors.append(f"w0ValidatorRuntime.installedSkillRoot is invalid: {exc}")
            configured_skill_root = None
        if configured_skill_root != skill_root:
            errors.append("w0ValidatorRuntime.installedSkillRoot must equal CLI skill root")
        skill_closure = validate_library_root_pin(
            w0_raw.get("installedSkillReadClosure"), roots, errors,
            "w0ValidatorRuntime.installedSkillReadClosure", pinned_root=skill_root)
        w0_python = validate_python_pin(
            w0_raw.get("pythonExecutable"), roots, errors,
            "w0ValidatorRuntime.pythonExecutable")
        entry = validate_skill_copy_ref(
            w0_raw.get("validatorEntrypoint"), skill_root,
            "scripts/validate_d5_acceptance.py", errors,
            "w0ValidatorRuntime.validatorEntrypoint")
        supports = w0_raw.get("supportArtifacts")
        expected_support = {
            "scripts/gen_index.py": None, "scripts/state_readiness.py": None,
            "scripts/strict_json.py": None,
        }
        if not isinstance(supports, list):
            errors.append("w0ValidatorRuntime.supportArtifacts must be an array")
            supports = []
        for index, value in enumerate(supports):
            raw_path = value.get("path") if isinstance(value, dict) else None
            matched = next((rel for rel in expected_support
                            if Path(raw_path or "").resolve() == (skill_root / rel).resolve()), None)
            if matched is None:
                errors.append(
                    f"w0ValidatorRuntime.supportArtifacts[{index}] is not canonical support")
                continue
            expected_support[matched] = validate_skill_copy_ref(
                value, skill_root, matched, errors,
                f"w0ValidatorRuntime.supportArtifacts[{index}]")
        if any(value is None for value in expected_support.values()) \
                or len(supports) != len(expected_support):
            errors.append("w0ValidatorRuntime.supportArtifacts must exact-cover local imports")
        copy_paths = [value.get("copyPath") for value in
                      [w0_raw.get("validatorEntrypoint"), *supports]
                      if isinstance(value, dict)]
        if len(copy_paths) != len({identity_key(value) for value in copy_paths}):
            errors.append("w0ValidatorRuntime copyPath values must be unique")
        raw_libraries = w0_raw.get("readOnlyLibraryRoots")
        if not isinstance(raw_libraries, list) or not raw_libraries:
            errors.append("w0ValidatorRuntime.readOnlyLibraryRoots must be non-empty")
            raw_libraries = []
        w0_libraries = [validate_library_root_pin(
            value, roots, errors,
            f"w0ValidatorRuntime.readOnlyLibraryRoots[{index}]")
            for index, value in enumerate(raw_libraries)]
        validate_unique_library_roots(
            w0_libraries, errors, "w0ValidatorRuntime.readOnlyLibraryRoots")
        python_is_covered(
            w0_python, w0_libraries, errors,
            "w0ValidatorRuntime.pythonExecutable")
        w0_git = validate_binary_pin(
            w0_raw.get("gitExecutable"), roots, errors,
            "w0ValidatorRuntime.gitExecutable", nullable=True)
        w0_git_roots = w0_raw.get("gitRuntimeRoots")
        if w0_git is not None or w0_git_roots != []:
            errors.append(
                "lifecycle v1 W0 runtime requires gitExecutable null and gitRuntimeRoots empty")
        receiver_bootstrap = validate_receiver_bootstrap_config(
            w0_raw.get("receiverBootstrap"), roots, skill_root, errors)
        immutable_authority = validate_immutable_runtime_authority_config(
            w0_raw.get("immutableRuntimeAuthority"), roots, errors)
        expected_python = Path(sys.executable).resolve()
        if w0_python is None or w0_python.get("_path") != expected_python:
            errors.append("W0 validator must run under the externally pinned Python")
        flags_ok = (sys.flags.dont_write_bytecode == 1 and sys.flags.no_site == 1
                    and sys.flags.ignore_environment == 1 and sys.flags.utf8_mode == 1)
        if not flags_ok:
            errors.append("W0 validator Python must run with -B -S -E -X utf8")
        current_entry = Path(__file__).resolve()
        if entry is None or not current_entry.is_file() \
                or current_entry.read_bytes() != entry.read_bytes():
            errors.append("W0 validator temp entrypoint differs from pinned installed bytes")
        if entry is not None and current_entry == entry:
            errors.append("W0 validator must run from a fresh copied capsule, not installed path")
        copy_root = current_entry
        entry_copy_path = w0_raw.get("validatorEntrypoint", {}).get("copyPath")
        if isinstance(entry_copy_path, str):
            for _ in Path(entry_copy_path).parts:
                copy_root = copy_root.parent
            if current_entry != copy_root / Path(entry_copy_path):
                errors.append("W0 validator current path does not equal configured copyPath")
        expected_copy_paths = {
            value.get("copyPath") for value in
            [w0_raw.get("validatorEntrypoint"), *supports] if isinstance(value, dict)}
        actual_copy_paths = {
            path.relative_to(copy_root).as_posix()
            for path in copy_root.rglob("*") if path.is_file()}
        if actual_copy_paths != expected_copy_paths \
                or any(path.name == "__pycache__" for path in copy_root.rglob("*")):
            errors.append("W0 validator temp capsule must contain only exact pinned closure")
        loaded_support_paths = {
            Path(gen_index.__file__).resolve(),
            Path(state_readiness_module.__file__).resolve(),
            Path(strict_json_module.__file__).resolve(),
        }
        expected_loaded_supports = {
            copy_root / value.get("copyPath") for value in supports if isinstance(value, dict)}
        if loaded_support_paths != expected_loaded_supports:
            errors.append("W0 validator imported support modules outside fresh copied capsule")
        w0_runtime = dict(
            w0_raw, _pythonExecutable=w0_python, _validatorEntrypoint=entry,
            _supportArtifacts=expected_support,
            _readOnlyLibraryRoots=w0_libraries, _gitExecutable=w0_git,
            _installedSkillReadClosure=skill_closure,
            _receiverBootstrap=receiver_bootstrap,
            _immutableRuntimeAuthority=immutable_authority)
    trusted: dict[tuple[str, str, str], dict[str, Any]] = {}
    for index, item in enumerate(trusted_raw):
        runner = validate_runner_config(
            item, roots, errors, f"trustedRuntimeAdapters[{index}]", signature=False)
        if runner is None:
            continue
        runner["_configPath"] = resolved
        key = (runner.get("authority"), runner.get("adapter"), runner.get("adapterVersion"))
        if key in trusted:
            errors.append(f"trustedRuntimeAdapters[{index}] duplicates a pinned runner")
        trusted[key] = runner
    signatures: dict[tuple[str, str, str], dict[str, Any]] = {}
    for index, item in enumerate(signature_raw):
        runner = validate_runner_config(
            item, roots, errors, f"signatureVerifiers[{index}]", signature=True)
        if runner is None:
            continue
        runner["_configPath"] = resolved
        key = (runner.get("authority"), runner.get("algorithm"), runner.get("keyId"))
        if key in signatures:
            errors.append(f"signatureVerifiers[{index}] duplicates a pinned verifier")
        signatures[key] = runner
    return {
        "configPath": resolved, "trusted": trusted, "signatures": signatures,
        "d4RuntimePins": d4_pins, "w0ValidatorRuntime": w0_runtime,
        "cache": {}, "roots": roots,
    }


def invoke_external_runner(
        runner: dict[str, Any], request: dict[str, Any], errors: list[str],
        label: str) -> dict[str, Any] | None:
    executable = runner.get("_executable")
    adapter = runner.get("_adapterArtifact")
    if not isinstance(executable, Path) or not isinstance(adapter, Path):
        errors.append(f"{label}: externally pinned runner is unavailable")
        return None
    env: dict[str, str] = {}
    for name in runner.get("allowedEnvNames", []):
        if name in os.environ:
            env[name] = os.environ[name]
    for name in ("SYSTEMROOT", "WINDIR"):
        if name in os.environ:
            env[name] = os.environ[name]
    config_path = runner.get("_configPath")
    temp_parent = config_path.parent if isinstance(config_path, Path) else executable.parent
    try:
        with tempfile.TemporaryDirectory(prefix="d5-provenance-", dir=temp_parent) as raw_temp:
            cwd = Path(raw_temp).resolve(strict=True)
            output_dir = cwd / "output"
            output_dir.mkdir()
            adapter_copy_rel = runner.get("adapterArtifact", {}).get("copyPath")
            copied_adapter = cwd / str(adapter_copy_rel)
            copied_adapter.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(adapter, copied_adapter)
            if sha256(copied_adapter) != runner.get("adapterArtifact", {}).get("sha256"):
                errors.append(f"{label}: copied adapter hash mismatch")
                return None
            for source in runner.get("_supportArtifacts", []):
                if not isinstance(source, Path):
                    continue
                configured = next((item for item in runner.get("supportArtifacts", [])
                                   if item.get("path") == str(source)), None)
                if not isinstance(configured, dict):
                    errors.append(f"{label}: copied support artifact is not configured")
                    return None
                target = cwd / configured.get("copyPath", "")
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, target)
                if not isinstance(configured, dict) or sha256(target) != configured.get("sha256"):
                    errors.append(f"{label}: copied support artifact hash mismatch")
                    return None
            if runner.get("launchMode") == "adapter-is-executable":
                command = [str(copied_adapter), *runner.get("staticArgs", [])]
            else:
                command = [str(executable), *runner.get("staticArgs", []),
                           str(copied_adapter)]
            closed_request = dict(request, outputDirectory=str(output_dir))
            result = subprocess.run(
                command, input=canonical_json_bytes(closed_request), stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, cwd=cwd, env=env, shell=False,
                timeout=runner.get("timeoutSeconds", 20), check=False)
            cap = runner.get("maxOutputBytes", 1024 * 1024)
            if len(result.stdout) > cap or len(result.stderr) > cap:
                errors.append(f"{label}: pinned runner exceeded the configured output cap")
                return None
            if result.returncode != 0:
                errors.append(f"{label}: pinned runner exited {result.returncode}")
                return None
            try:
                decoded = result.stdout.decode("utf-8")
                response = strict_json_module.loads(decoded)
            except (UnicodeDecodeError, ValueError) as exc:
                errors.append(
                    f"{label}: runner stdout must be exactly one UTF-8 JSON object: {exc}")
                return None
            if not isinstance(response, dict) or canonical_json_bytes(response) != result.stdout:
                errors.append(
                    f"{label}: runner stdout must be canonical JSON with no leading/trailing bytes")
                return None
            raw_ref = response.get("rawResponseArtifact")
            if isinstance(raw_ref, dict):
                raw_name = raw_ref.get("path")
                if not isinstance(raw_name, str) or not raw_name:
                    errors.append(f"{label}: fresh rawResponseArtifact.path is invalid")
                    return None
                raw_path = Path(raw_name)
                raw_path = (raw_path if raw_path.is_absolute() else output_dir / raw_path).resolve()
                try:
                    raw_path.relative_to(output_dir)
                except ValueError:
                    errors.append(f"{label}: fresh raw response must stay in validator outputDirectory")
                    return None
                if not raw_path.is_file() or raw_ref.get("sha256") != sha256(raw_path):
                    errors.append(f"{label}: fresh raw response file/hash mismatch")
                    return None
            return response
    except (OSError, subprocess.SubprocessError) as exc:
        errors.append(f"{label}: pinned runner invocation failed: {exc}")
        return None


def historical_bytes(
        root: Path, source_root: Path, revision: Any, rel: str,
        errors: list[str], label: str, git_executable: Path | None = None) -> bytes | None:
    if not isinstance(revision, dict):
        errors.append(f"{label}: revision must be an object")
        return None
    kind, value = revision.get("kind"), revision.get("value")
    if kind == "commit":
        if not isinstance(value, str) or re.fullmatch(r"[a-f0-9]{40}(?:[a-f0-9]{24})?", value) is None:
            errors.append(f"{label}: commit revision must be a full 40/64-hex object ID")
            return None
        if git_executable is None:
            errors.append(f"{label}: commit evidence requires externally pinned Git; STOP/HUMAN")
            return None
        try:
            result = subprocess.run(
                [str(git_executable), "-C", str(source_root), "show", f"{value}:{rel}"],
                capture_output=True, timeout=20, shell=False,
                env={key: os.environ[key] for key in ("SYSTEMROOT", "WINDIR")
                     if key in os.environ})
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
        errors: list[str], label: str,
        git_executable: Path | None = None) -> dict[str, bytes]:
    content: dict[str, bytes] = {}
    revision = manifest.get("revision")
    for rel, item in records.items():
        data = historical_bytes(
            root, source_root, revision, rel, errors, f"{label}:{rel}", git_executable)
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
        if "\\" in raw_path or raw_path.startswith("./"):
            errors.append(f"{row_label}.path must use canonical project-relative POSIX form")
        resolved_path = resolve_path(root, raw_path, errors, row_label)
        result[raw_path] = item
        expected_bytes = item.get("bytes")
        expected_hash = item.get("sha256")
        if not isinstance(expected_bytes, int) or isinstance(expected_bytes, bool) \
                or expected_bytes < 0:
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
        path = resolved_path
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
        if "\\" in rel or rel.startswith("./"):
            errors.append(f"{label}.path must use canonical project-relative POSIX form")
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


def exact_artifact_ref(
        root: Path, ref: Any, errors: list[str], label: str) -> tuple[Path, dict[str, Any]] | None:
    if not isinstance(ref, dict) or set(ref) != {"path", "sha256"}:
        errors.append(f"{label}: artifact reference has unknown/missing fields")
        return None
    return verify_ref(root, ref, errors, label)


def verify_artifact_file_ref(
        root: Path, ref: Any, errors: list[str], label: str) -> Path | None:
    if not isinstance(ref, dict) or set(ref) != {"path", "sha256"}:
        errors.append(f"{label}: artifact reference has unknown/missing fields")
        return None
    return verify_file_hash(root, ref.get("path"), ref.get("sha256"), errors, label)


def validate_trusted_query_source(
        root: Path, ref: Any, pv: dict[str, Any], errors: list[str],
        label: str) -> dict[str, Any] | None:
    loaded = exact_artifact_ref(root, ref, errors, label)
    if loaded is None:
        return None
    _, source = loaded
    if set(source) != TRUSTED_QUERY_RESULT_KEYS:
        errors.append(f"{label}: trusted query result has unknown/missing fields")
    if source.get("schemaVersion") != "1.0.0" or not isinstance(
            source.get("id"), str) or re.fullmatch(
                r"TRQ-[A-Z0-9][A-Z0-9._-]*", source.get("id", "")) is None:
        errors.append(f"{label}: trusted query result identity is invalid")
    verifier = pv.get("verifier") if isinstance(pv.get("verifier"), dict) else {}
    context = (pv.get("verificationContext")
               if isinstance(pv.get("verificationContext"), dict) else {})
    subject = pv.get("subject") if isinstance(pv.get("subject"), dict) else {}
    bindings = {
        "authority": verifier.get("authority"),
        "adapter": verifier.get("adapter"),
        "adapterVersion": verifier.get("adapterVersion"),
        "nonce": context.get("nonce"),
        "requestId": context.get("requestId"),
        "responseId": context.get("responseId"),
        "subjectType": pv.get("subjectType"),
        "subjectId": subject.get("id"),
        "claimsSha256": pv.get("claimsSha256"),
    }
    for key, expected in bindings.items():
        if source.get(key) != expected:
            errors.append(f"{label}.{key} must exactly bind provenance verification")
    if not timezone_datetime(source.get("queriedAt")):
        errors.append(f"{label}.queriedAt must be a timezone timestamp")
    raw = source.get("rawResponseArtifact")
    if not isinstance(raw, dict) or set(raw) != {"path", "sha256"}:
        errors.append(f"{label}.rawResponseArtifact has unknown/missing fields")
    else:
        verify_artifact_file_ref(root, raw, errors, f"{label}.rawResponseArtifact")
    return source


def validate_pinned_signature_source(
        root: Path, ref: Any, pv: dict[str, Any], errors: list[str],
        label: str) -> dict[str, Any] | None:
    loaded = exact_artifact_ref(root, ref, errors, label)
    if loaded is None:
        return None
    _, source = loaded
    if set(source) != PINNED_SIGNATURE_EVIDENCE_KEYS:
        errors.append(f"{label}: pinned signature evidence has unknown/missing fields")
    context = (pv.get("verificationContext")
               if isinstance(pv.get("verificationContext"), dict) else {})
    verifier = pv.get("verifier") if isinstance(pv.get("verifier"), dict) else {}
    for key, expected in (
            ("authority", verifier.get("authority")),
            ("algorithm", context.get("algorithm")),
            ("keyId", context.get("keyId")),
            ("claimsSha256", pv.get("claimsSha256"))):
        if source.get(key) != expected:
            errors.append(f"{label}.{key} must exactly bind provenance verification")
    if source.get("schemaVersion") != "1.0.0" or not isinstance(
            source.get("id"), str) or re.fullmatch(
                r"PSE-[A-Z0-9][A-Z0-9._-]*", source.get("id", "")) is None:
        errors.append(f"{label}: pinned signature evidence identity is invalid")
    if not timezone_datetime(source.get("verifiedAt")):
        errors.append(f"{label}.verifiedAt must be a timezone timestamp")
    for field in ("trustAnchorArtifact", "signedPayloadArtifact", "signatureArtifact"):
        if not isinstance(source.get(field), dict) or set(source[field]) != {
                "path", "sha256"}:
            errors.append(f"{label}.{field} has unknown/missing fields")
            continue
        verify_artifact_file_ref(root, source[field], errors, f"{label}.{field}")
    payload_ref = source.get("signedPayloadArtifact")
    payload_path = (resolve_path(root, payload_ref.get("path"), errors, f"{label}.payload")
                    if isinstance(payload_ref, dict) else None)
    if payload_path is not None and payload_path.is_file() \
            and payload_path.read_bytes() != canonical_json_bytes(pv.get("claims")):
        errors.append(f"{label}: signed payload must be exact canonical provenance claims bytes")
    anchor = source.get("trustAnchorArtifact")
    if isinstance(anchor, dict) and anchor.get("sha256") != context.get("trustAnchorSha256"):
        errors.append(f"{label}: trust anchor hash must equal verificationContext")
    return source


def validate_provenance_verification(
        root: Path, ref: Any, expected_subject_type: str,
        expected_subject: dict[str, Any], expected_claims: dict[str, Any],
        runtime: dict[str, Any] | None, errors: list[str], label: str) -> dict[str, Any] | None:
    loaded = exact_artifact_ref(root, ref, errors, label)
    if loaded is None:
        return None
    _, pv = loaded
    if set(pv) != PROVENANCE_VERIFICATION_KEYS:
        errors.append(f"{label}: provenance verification has unknown/missing fields")
    if pv.get("schemaVersion") != "1.0.0" or not isinstance(
            pv.get("id"), str) or re.fullmatch(
                r"PV-[A-Z0-9][A-Z0-9._-]*", pv.get("id", "")) is None:
        errors.append(f"{label}: provenance verification identity is invalid")
    if pv.get("subjectType") != expected_subject_type:
        errors.append(f"{label}.subjectType is incorrect")
    if pv.get("subject") != expected_subject:
        errors.append(f"{label}.subject must exactly bind the verified artifact")
    if pv.get("claims") != expected_claims:
        errors.append(f"{label}.claims do not exactly match reconstructed facts")
    claims_hash = canonical_json_sha256(pv.get("claims"))
    if pv.get("claimsSha256") != claims_hash:
        errors.append(f"{label}.claimsSha256 mismatch: {claims_hash}")
    if pv.get("verdict") != "verified" or not timezone_datetime(pv.get("verifiedAt")):
        errors.append(f"{label}: verdict/verifiedAt is invalid")
    verified_at = parsed_timestamp(pv.get("verifiedAt"))
    subject_time_raw: Any = None
    if expected_subject_type == "human-approval-capture":
        subject_time_raw = expected_claims.get("sentAt")
    elif expected_subject_type == "d4-auditor-attestation":
        subject_time_raw = expected_claims.get("completedAt")
    elif expected_subject_type == "d4-capsule-assembly-attestation":
        subject_time_raw = expected_claims.get("assembledAt")
    elif expected_subject_type == "d1.5-measurement-evidence":
        subject_time_raw = expected_claims.get("completedAt")
    elif expected_subject_type == "lifecycle-transition-attestation":
        actual = expected_claims.get("actual")
        subject_time_raw = actual.get("completedAt") if isinstance(actual, dict) else None
    subject_time = parsed_timestamp(subject_time_raw)
    if subject_time is None or verified_at is None or subject_time > verified_at:
        errors.append(
            f"{label}: authoritative subject completion must not follow provenance verifiedAt")
    verifier = pv.get("verifier")
    if not isinstance(verifier, dict) or set(verifier) != {
            "id", "authority", "adapter", "adapterVersion"} or any(
                not isinstance(verifier.get(key), str) or not verifier[key].strip()
                for key in ("id", "authority", "adapter", "adapterVersion")):
        errors.append(f"{label}.verifier has unknown/missing/empty fields")
        verifier = {}
    mode = pv.get("verificationMode")
    context = pv.get("verificationContext")
    source_ref = pv.get("sourceArtifact")
    if not isinstance(source_ref, dict) or set(source_ref) != {"path", "sha256"}:
        errors.append(f"{label}.sourceArtifact has unknown/missing fields")
        source_ref = {}
    # W0 v1 is deliberately offline.  Reject query provenance before resolving
    # or invoking any configured adapter; receiver send/network permission has
    # not been reacquired yet and D5 cannot grant it.
    if mode == "trusted-runtime-query":
        errors.append(
            f"{label}: W0 v1 accepts pinned-signature provenance only; "
            "trusted-runtime-query is forbidden and no adapter was invoked")
        if runtime is not None:
            cache_key = identity_key({"pv": ref, "subject": expected_subject})
            runtime.setdefault("cache", {})[cache_key] = False
        return None
    if runtime is None:
        errors.append(f"{label}: external provenance runtime is unavailable; STOP/HUMAN")
        return pv

    cache_key = identity_key({"pv": ref, "subject": expected_subject})
    if cache_key in runtime.get("cache", {}):
        return pv if runtime["cache"][cache_key] else None

    success = False
    if mode == "trusted-runtime-query":  # unreachable by the offline-W0 guard above
        if not isinstance(context, dict) or set(context) != {
                "kind", "nonce", "requestId", "responseId"} \
                or context.get("kind") != "trusted-runtime-query-v1" \
                or not isinstance(context.get("nonce"), str) \
                or len(context["nonce"]) < 16:
            errors.append(f"{label}.verificationContext is not a closed trusted-query context")
        source = validate_trusted_query_source(
            root, source_ref, pv, errors, f"{label}.sourceArtifact")
        source_queried = parsed_timestamp(source.get("queriedAt")) \
            if isinstance(source, dict) else None
        if subject_time is None or verified_at is None or source_queried is None \
                or not (subject_time <= source_queried <= verified_at):
            errors.append(
                f"{label}.sourceArtifact: subject <= queriedAt <= verifiedAt is required")
        key = (verifier.get("authority"), verifier.get("adapter"),
               verifier.get("adapterVersion"))
        runner = runtime.get("trusted", {}).get(key)
        if runner is None:
            errors.append(f"{label}: no external pinned adapter matches {key!r}; STOP/HUMAN")
        elif source is not None:
            fresh_nonce = secrets.token_hex(32)
            if fresh_nonce == context.get("nonce"):
                errors.append(f"{label}: fresh nonce unexpectedly reused recorded nonce")
            request_started = dt.datetime.now(dt.timezone.utc)
            request = {
                "schemaVersion": "1.0.0", "operation": "fresh-provenance-query-v1",
                "authority": verifier.get("authority"), "nonce": fresh_nonce,
                "subjectType": expected_subject_type,
                "subjectId": expected_subject.get("id"),
                "claimsSha256": claims_hash,
                "requestedAt": request_started.isoformat(),
            }
            fresh = invoke_external_runner(runner, request, errors, f"{label}.freshQuery")
            request_completed = dt.datetime.now(dt.timezone.utc)
            if fresh is not None:
                if set(fresh) != TRUSTED_QUERY_RESULT_KEYS:
                    errors.append(f"{label}.freshQuery: result has unknown/missing fields")
                expected = {
                    "schemaVersion": "1.0.0", "authority": verifier.get("authority"),
                    "adapter": verifier.get("adapter"),
                    "adapterVersion": verifier.get("adapterVersion"),
                    "nonce": fresh_nonce, "subjectType": expected_subject_type,
                    "subjectId": expected_subject.get("id"), "claimsSha256": claims_hash,
                }
                for field, value in expected.items():
                    if fresh.get(field) != value:
                        errors.append(
                            f"{label}.freshQuery.{field} must equal the fresh request/trust pin")
                if fresh.get("nonce") == context.get("nonce"):
                    errors.append(f"{label}.freshQuery reflected the stale recorded nonce")
                if not timezone_datetime(fresh.get("queriedAt")):
                    errors.append(f"{label}.freshQuery.queriedAt must be a timezone timestamp")
                fresh_queried = parsed_timestamp(fresh.get("queriedAt"))
                # The recorded query is creation-time evidence.  A receiver query is
                # deliberately later and must fall inside this invocation's nonce
                # window; comparing it as <= the historical verifiedAt makes every
                # durable handoff permanently unverifiable.
                if verified_at is None or fresh_queried is None \
                        or not (verified_at <= fresh_queried \
                                and request_started <= fresh_queried <= request_completed):
                    errors.append(
                        f"{label}.freshQuery: recorded verifiedAt <= queriedAt within "
                        "the current nonce invocation window is required")
                for field in ("id", "requestId", "responseId"):
                    if not isinstance(fresh.get(field), str) or not fresh[field].strip():
                        errors.append(f"{label}.freshQuery.{field} must be non-empty")
                raw = fresh.get("rawResponseArtifact")
                if not isinstance(raw, dict) or set(raw) != {"path", "sha256"} \
                        or not isinstance(raw.get("path"), str) \
                        or not isinstance(raw.get("sha256"), str) \
                        or SHA256_RE.fullmatch(raw.get("sha256", "")) is None:
                    errors.append(f"{label}.freshQuery.rawResponseArtifact is invalid")
                success = not any(error.startswith(f"{label}.freshQuery") for error in errors)
    elif mode == "pinned-signature":
        if not isinstance(context, dict) or set(context) != {
                "kind", "algorithm", "keyId", "trustAnchorSha256"} \
                or context.get("kind") != "pinned-signature-v1":
            errors.append(f"{label}.verificationContext is not a closed signature context")
        source = validate_pinned_signature_source(
            root, source_ref, pv, errors, f"{label}.sourceArtifact")
        signature_verified = parsed_timestamp(source.get("verifiedAt")) \
            if isinstance(source, dict) else None
        if subject_time is None or verified_at is None or signature_verified is None \
                or not (subject_time <= signature_verified <= verified_at):
            errors.append(
                f"{label}.sourceArtifact: subject <= signature verifiedAt <= "
                "provenance verifiedAt is required")
        key = (verifier.get("authority"), context.get("algorithm") if isinstance(
            context, dict) else None, context.get("keyId") if isinstance(context, dict) else None)
        runner = runtime.get("signatures", {}).get(key)
        if runner is None:
            errors.append(f"{label}: no external pinned signature verifier matches {key!r}; STOP/HUMAN")
        elif source is not None:
            configured_anchor = runner.get("trustAnchor")
            anchor_hash = (configured_anchor.get("sha256")
                           if isinstance(configured_anchor, dict) else None)
            if anchor_hash != context.get("trustAnchorSha256"):
                errors.append(f"{label}: external trust anchor does not match verification context")
            request = {
                "schemaVersion": "1.0.0", "operation": "verify-pinned-signature-v1",
                "authority": verifier.get("authority"), "algorithm": context.get("algorithm"),
                "keyId": context.get("keyId"), "claimsSha256": claims_hash,
                "trustAnchorPath": configured_anchor.get("path")
                if isinstance(configured_anchor, dict) else None,
                "signedPayloadPath": str((root / source.get(
                    "signedPayloadArtifact", {}).get("path", "")).resolve()),
                "signaturePath": str((root / source.get(
                    "signatureArtifact", {}).get("path", "")).resolve()),
            }
            verified = invoke_external_runner(runner, request, errors, f"{label}.signature")
            expected = {
                "verified": True, "authority": verifier.get("authority"),
                "algorithm": context.get("algorithm"), "keyId": context.get("keyId"),
                "claimsSha256": claims_hash,
            }
            if verified != expected:
                errors.append(f"{label}.signature: verifier did not return exact success binding")
            else:
                success = True
    else:
        errors.append(f"{label}.verificationMode must be trusted-runtime-query or pinned-signature")
    runtime.setdefault("cache", {})[cache_key] = success
    return pv if success else None


D4_REFERENCE_PATHS = [
    "references/absolute-rules.md", "references/audit-d4.md",
    "references/audit-dimensions.md", "references/autonomous-execution.md",
    "references/config-example.md", "references/defect-catalog.md",
    "references/document-system.md", "references/execution-envelope.md",
    "references/findings-report.md", "references/gdd-and-intake.md",
    "references/orchestration.md", "references/ordering.md",
    "references/output-layout.md", "references/p0-approval-and-state.md",
    "references/p0-gate-design.md", "references/p0-rework-catalog.md",
    "references/p0-work-units.md", "references/phase-definitions.md",
    "references/quality-gates.md", "references/repository-audit.md",
    "references/review-protocol.md", "references/roblox-readiness.md",
    "references/trigger-matrix.md", "references/worker-registry.md",
]
D4_CHECKLIST_CLOSURE = [
    "checklists/clean_room.md", "checklists/completion.md",
    "checklists/consistency.md", "checklists/production_readiness.md",
    "checklists/security.md",
]
D4_LANE_CHECKLIST_TRACK = {
    "checklists/clean_room.md": "clean-room",
    "checklists/consistency.md": "consistency",
    "checklists/production_readiness.md": "roblox-readiness",
}
D4_POLICY_COMPONENTS = [
    ("skill-d4", None, "SKILL.md"),
    *[("policy-reference", None, path) for path in D4_REFERENCE_PATHS],
    *[("policy-checklist", D4_LANE_CHECKLIST_TRACK.get(path), path)
      for path in D4_CHECKLIST_CLOSURE],
    ("findings-template", None, "templates/d4_findings.md"),
    ("validator", None, "scripts/validate_d5_acceptance.py"),
    ("validator", None, "scripts/validate_lifecycle_transition.py"),
]
D4_RUNTIME_FILES = {
    "scripts/d4_preflight.py": "entrypoint",
    "scripts/lint_docs.py": "entrypoint",
    "scripts/validate_docs.py": "entrypoint",
    "scripts/validate_traceability.py": "entrypoint",
    "scripts/validate_lifecycle_transition.py": "entrypoint",
    "scripts/check_p0_state.py": "entrypoint",
    "scripts/validate_d5_acceptance.py": "local-import",
    "scripts/gen_index.py": "local-import",
    "scripts/detect_triggers.py": "local-import",
    "scripts/state_readiness.py": "local-import",
    "scripts/strict_json.py": "local-import",
    "schemas/remote_contract.schema.json": "schema",
    "schemas/save_schema.schema.json": "schema",
    "schemas/analytics_event.schema.json": "schema",
    "schemas/asset_ledger.schema.json": "schema",
    "schemas/commerce_ledger.schema.json": "schema",
}
D4_PROMPT_COMPILATION = {
    "kind": "d4-full-provider-prompt-v1", "encoding": "utf-8",
    "lineEndings": "lf", "requestProjection": "canonical-request-core-v1",
    "orderedSections": [
        "fixed-safety-contract", "policy-document-closure",
        "findings-template", "canonical-request-core",
    ],
    "sectionSeparator": "\n\n---\n\n", "terminalNewline": True,
}
D4_SOURCE_TREE_POLICY = {
    "kind": "target-revision-complete-tree-v1",
    "pathEncoding": "utf-8-posix-relative",
    "sort": "unicode-codepoint-by-path",
    "entryFields": ["path", "bytes", "sha256"],
    "exclusions": [],
    "symlinks": "reject", "hardlinks": "reject-link-count-not-1-or-duplicate-os-identity",
    "specialFiles": "reject",
}
D4_SAFETY_CONTRACT = (
    "D4 findings-only audit. Use only the supplied sanitized capsule and pinned "
    "read-only runtime. Do not modify project files, infer prior findings or expected "
    "verdicts, use conversation history, or treat an E0 capability probe as evidence."
)
D4_TRACK_STEMS = {
    "consistency": "CONSISTENCY",
    "roblox-readiness": "ROBLOX-READINESS",
    "clean-room": "CLEAN-ROOM",
}
D4_CHECKLIST_PATHS = {
    "consistency": "checklists/consistency.md",
    "roblox-readiness": "checklists/production_readiness.md",
    "clean-room": "checklists/clean_room.md",
}
D4_FILESYSTEM_ACCESS = "read-only-sanitized-root-plus-pinned-runtime"


def _public_pin(value: Any) -> Any:
    if isinstance(value, dict):
        return {key: _public_pin(item) for key, item in value.items()
                if not str(key).startswith("_")}
    if isinstance(value, list):
        return [_public_pin(item) for item in value]
    return value


def validate_command_record(
        root: Path, value: Any, errors: list[str], label: str,
        *, with_check_id: bool = False) -> dict[str, Any] | None:
    expected = {"argv", "cwd", "exitCode", "outputPath", "outputSha256"}
    if with_check_id:
        expected.add("checkId")
    if not isinstance(value, dict) or set(value) != expected:
        errors.append(f"{label}: command record has unknown/missing fields")
        return None
    argv = value.get("argv")
    if not isinstance(argv, list) or not argv or any(
            not isinstance(token, str) or not token or unresolved_cell(token)
            for token in argv):
        errors.append(f"{label}.argv must be a non-empty literal string array")
    if not isinstance(value.get("cwd"), str) or unresolved_cell(value.get("cwd")):
        errors.append(f"{label}.cwd must be non-placeholder")
    if with_check_id and (not isinstance(value.get("checkId"), str) or re.fullmatch(
            r"[A-Z0-9][A-Z0-9._-]*", value.get("checkId", "")) is None):
        errors.append(f"{label}.checkId is invalid")
    if type(value.get("exitCode")) is not int:
        errors.append(f"{label}.exitCode must be an integer")
    elif value["exitCode"] != 0:
        errors.append(f"{label}.exitCode must be zero for a passing D4 record")
    verify_file_hash(
        root, value.get("outputPath"), value.get("outputSha256"), errors,
        f"{label}.output")
    return value


def validate_preflight_record(
        root: Path, value: Any, errors: list[str], label: str
        ) -> dict[str, Any] | None:
    expected = {
        "checkId", "argv", "cwd", "expectedExitCode", "actualExitCode",
        "outputPath", "outputSha256",
    }
    if not isinstance(value, dict) or set(value) != expected:
        errors.append(f"{label}: preflight record has unknown/missing fields")
        return None
    if value.get("checkId") not in {
            "D4-PREFLIGHT-SOURCE-STATE-001", "D4-PREFLIGHT-REVISION-001",
            "D4-PREFLIGHT-TREE-001"}:
        errors.append(f"{label}.checkId is not an installed preflight ID")
    argv = value.get("argv")
    if not isinstance(argv, list) or not argv or any(
            not isinstance(token, str) or not token or unresolved_cell(token)
            for token in argv):
        errors.append(f"{label}.argv must be a non-empty literal string array")
    if not isinstance(value.get("cwd"), str) or unresolved_cell(value.get("cwd")):
        errors.append(f"{label}.cwd must be non-placeholder")
    if value.get("expectedExitCode") != 0 or value.get("actualExitCode") != 0:
        errors.append(f"{label}: expected and actual exit code must both be zero")
    verify_file_hash(root, value.get("outputPath"), value.get("outputSha256"),
                     errors, f"{label}.output")
    return value


def _d4_runtime_commands(
        track: str, python_path: str, runtime_root: Path, sanitized_root: Path,
        prefix: str, errors: list[str], git_path: str | None = None,
        capsule_path: Path | None = None,
        provenance_config: Path | None = None) -> list[dict[str, Any]]:
    stem = D4_TRACK_STEMS[track]
    fixed = [python_path, "-B", "-S", "-E", "-X", "utf8"]
    commands = [
        {
            "checkId": f"{stem}-LINT-001", "applicability": "all",
            "argv": [*fixed, str(runtime_root / "scripts" / "lint_docs.py"),
                     "--project-root", str(sanitized_root), "--config",
                     str(sanitized_root / ".claude" / "doc-lint.json"), "--json"],
            "cwd": str(sanitized_root), "expectedExitCode": 0,
        },
        {
            "checkId": f"{stem}-DOCS-D3-001", "applicability": "all",
            "argv": [*fixed, str(runtime_root / "scripts" / "validate_docs.py"),
                     "--project-root", str(sanitized_root), "--prefix", prefix,
                     "--gate", "D3", "--json"],
            "cwd": str(sanitized_root), "expectedExitCode": 0,
        },
        {
            "checkId": f"{stem}-TRACE-D3-001", "applicability": "all",
            "argv": [*fixed, str(runtime_root / "scripts" / "validate_traceability.py"),
                     str(sanitized_root / "docs" / "traceability" /
                         f"{prefix}_requirements.csv"), "--gate", "D3", "--json"],
            "cwd": str(sanitized_root), "expectedExitCode": 0,
        },
    ]
    p0_argv = [*fixed, str(runtime_root / "scripts" / "check_p0_state.py"),
               "--project-root", str(sanitized_root), "--prefix", prefix,
               "--config", str(sanitized_root / ".claude" / "p0-check.json"),
               "--strict", "--json"]
    p0_config = sanitized_root / ".claude" / "p0-check.json"
    if p0_config.is_file():
        parsed = strict_json_file(p0_config, errors, "D4 policy P0 config")
        git_enabled = isinstance(parsed, dict) and isinstance(parsed.get("rules"), dict) \
            and parsed["rules"].get("git-current-facts") is True
        if git_enabled:
            if not git_path:
                errors.append(
                    "D4 policy P0 config enables git-current-facts without pinned Git")
            else:
                p0_argv.extend(["--git-executable", git_path])
    commands.append({
        "checkId": f"{stem}-P0-STRICT-001", "applicability": "post-p0",
        "argv": p0_argv, "cwd": str(sanitized_root), "expectedExitCode": 0,
    })
    lifecycle_argv = [
        *fixed, str(runtime_root / "scripts" / "validate_lifecycle_transition.py"),
        "--project-root", str(sanitized_root),
        "--capsule", str(capsule_path) if capsule_path is not None else "",
        "--transition-type", "p0",
        "--provenance-config",
        str(provenance_config) if provenance_config is not None else "",
        "--fresh-authenticate", "--json",
    ]
    if capsule_path is None or provenance_config is None:
        errors.append(
            "post-P0 D4 policy requires absolute capsule and operator provenance paths")
    commands.append({
        "checkId": f"{stem}-P0-LIFECYCLE-001", "applicability": "post-p0",
        "argv": lifecycle_argv, "cwd": str(sanitized_root), "expectedExitCode": 0,
    })
    return commands


def _d4_revision_source_root(
        root: Path, revision: Any, errors: list[str], label: str) -> Path | None:
    if not isinstance(revision, dict):
        errors.append(f"{label}: candidate revision must be an object")
        return None
    if revision.get("kind") == "snapshot":
        return resolve_path(root, revision.get("snapshotRoot"), errors, label)
    if revision.get("kind") == "commit":
        # Commit enumeration is relative to the explicit receiver/source project.
        return root
    errors.append(f"{label}: candidate revision kind must be snapshot or commit")
    return None


def _d4_preflight_commands(
        root: Path, candidate_ref: dict[str, Any], candidate: dict[str, Any],
        python_path: str, runtime_root: Path, sanitized_root: Path,
        git_path: str | None, errors: list[str], label: str) -> list[dict[str, Any]]:
    revision = candidate.get("revision")
    source_root = _d4_revision_source_root(root, revision, errors, label)
    candidate_path = resolve_path(
        root, candidate_ref.get("path"), errors, f"{label}.candidate")
    if source_root is None or candidate_path is None:
        return []
    script = runtime_root / "scripts" / "d4_preflight.py"
    fixed = [python_path, "-B", "-S", "-E", "-X", "utf8", str(script)]
    git_arg = git_path or "disabled"
    result = []
    for operation in ("source-state", "revision", "tree"):
        result.append({
            "checkId": f"D4-PREFLIGHT-{operation.upper()}-001",
            "argv": [*fixed, "--operation", operation,
                     "--source-root", str(source_root),
                     "--candidate-manifest", str(candidate_path),
                     "--git-executable", git_arg],
            "cwd": str(sanitized_root), "expectedExitCode": 0,
        })
    return result


def _snapshot_tree_entries(
        source_root: Path, errors: list[str], label: str) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    identities: set[tuple[int, int]] = set()
    if not source_root.is_dir():
        errors.append(f"{label}: snapshot source root is missing")
        return entries
    try:
        for path in sorted(source_root.rglob("*"), key=lambda value: value.as_posix()):
            rel = path.relative_to(source_root).as_posix()
            try:
                info = path.lstat()
            except OSError as exc:
                errors.append(f"{label}: cannot stat source-tree entry {rel}: {exc}")
                continue
            reparse = bool(getattr(info, "st_file_attributes", 0)
                           & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400))
            if path.is_symlink() or reparse:
                errors.append(f"{label}: source tree contains a symlink/reparse point: {rel}")
                continue
            if path.is_dir():
                continue
            if not path.is_file():
                errors.append(f"{label}: source tree contains a special file: {rel}")
                continue
            if info.st_nlink != 1:
                errors.append(f"{label}: source tree contains a hardlinked file: {rel}")
                continue
            identity = (info.st_dev, info.st_ino)
            if identity in identities:
                errors.append(f"{label}: source tree reuses one OS file identity: {rel}")
                continue
            identities.add(identity)
            payload = path.read_bytes()
            entries.append({
                "path": rel, "bytes": len(payload),
                "sha256": hashlib.sha256(payload).hexdigest(),
            })
    except OSError as exc:
        errors.append(f"{label}: cannot enumerate snapshot source tree: {exc}")
    return entries


def _commit_tree_entries(
        source_root: Path, revision: str, git_pin: Any,
        errors: list[str], label: str) -> list[dict[str, Any]]:
    if not isinstance(git_pin, dict) or not isinstance(git_pin.get("path"), str):
        errors.append(f"{label}: commit source tree requires externally pinned Git")
        return []
    git = Path(git_pin["path"])
    clean_env = {key: os.environ[key] for key in ("SYSTEMROOT", "WINDIR")
                 if key in os.environ}
    try:
        listed = subprocess.run(
            [str(git), "-C", str(source_root), "ls-tree", "-r", "-z",
             "--full-tree", revision], shell=False, env=clean_env,
            stdin=subprocess.DEVNULL, capture_output=True, timeout=60)
    except (OSError, subprocess.SubprocessError) as exc:
        errors.append(f"{label}: pinned Git tree enumeration failed: {exc}")
        return []
    if listed.returncode != 0:
        errors.append(f"{label}: pinned Git cannot enumerate candidate revision")
        return []
    entries: list[dict[str, Any]] = []
    for record in listed.stdout.split(b"\0"):
        if not record:
            continue
        try:
            header, raw_path = record.split(b"\t", 1)
            mode, kind, object_id = header.decode("ascii").split(" ", 2)
            rel = raw_path.decode("utf-8")
        except (ValueError, UnicodeError):
            errors.append(f"{label}: pinned Git returned malformed tree data")
            continue
        if kind != "blob" or mode == "120000":
            errors.append(f"{label}: commit source tree contains non-regular entry {rel}")
            continue
        try:
            blob = subprocess.run(
                [str(git), "-C", str(source_root), "cat-file", "blob", object_id],
                shell=False, env=clean_env, stdin=subprocess.DEVNULL,
                capture_output=True, timeout=60)
        except (OSError, subprocess.SubprocessError) as exc:
            errors.append(f"{label}: pinned Git blob read failed: {exc}")
            continue
        if blob.returncode != 0:
            errors.append(f"{label}: pinned Git cannot read blob {object_id}")
            continue
        entries.append({"path": rel, "bytes": len(blob.stdout),
                        "sha256": hashlib.sha256(blob.stdout).hexdigest()})
    entries.sort(key=lambda item: item["path"])
    return entries


def _candidate_source_tree(
        root: Path, candidate: dict[str, Any], runtime_data: dict[str, Any] | None,
        errors: list[str], label: str) -> list[dict[str, Any]]:
    revision = candidate.get("revision")
    source_root = _d4_revision_source_root(root, revision, errors, label)
    if source_root is None or not isinstance(revision, dict):
        return []
    if revision.get("kind") == "snapshot":
        return _snapshot_tree_entries(source_root, errors, label)
    return _commit_tree_entries(
        source_root, str(revision.get("value") or ""),
        runtime_data.get("gitExecutable") if isinstance(runtime_data, dict) else None,
        errors, label)


def validate_d4_runtime_allowlist(
        root: Path, ref: Any, sanitized_root: Path | None,
        runtime: dict[str, Any] | None, errors: list[str], label: str
        ) -> tuple[dict[str, Any] | None, Path | None]:
    if not isinstance(ref, dict) or set(ref) != {"path", "sha256", "digestSha256"}:
        errors.append(f"{label}: runtime allowlist reference has unknown/missing fields")
        return None, None
    loaded = verify_ref(
        root, {"path": ref.get("path"), "sha256": ref.get("sha256")}, errors, label)
    if loaded is None:
        return None, None
    _, data = loaded
    expected = {
        "schemaVersion", "id", "createdAt", "operatorRuntimePinId",
        "pythonExecutable", "gitExecutable", "readOnlyLibraryRoots", "policyRuntimeRoot",
        "policyRuntimeFiles", "digestSha256",
    }
    if set(data) != expected:
        errors.append(f"{label}: runtime allowlist has unknown/missing fields")
    if data.get("schemaVersion") != "1.0.0" or not isinstance(data.get("id"), str) \
            or re.fullmatch(r"D4-RUNTIME-[A-Z0-9][A-Z0-9._-]*",
                            data.get("id", "")) is None:
        errors.append(f"{label}: runtime allowlist identity is invalid")
    if not timezone_datetime(data.get("createdAt")):
        errors.append(f"{label}.createdAt must be a timezone timestamp")
    pin_id = data.get("operatorRuntimePinId")
    pin = runtime.get("d4RuntimePins", {}).get(identity_key(pin_id)) \
        if isinstance(runtime, dict) else None
    if pin is None:
        errors.append(f"{label}: operator runtime pin is unavailable; STOP/HUMAN")
    else:
        if data.get("pythonExecutable") != _public_pin(pin.get("pythonExecutable")):
            errors.append(f"{label}.pythonExecutable does not equal the external pin")
        if data.get("gitExecutable") != _public_pin(pin.get("gitExecutable")):
            errors.append(f"{label}.gitExecutable does not equal the external pin")
        if data.get("readOnlyLibraryRoots") != _public_pin(pin.get("readOnlyLibraryRoots")):
            errors.append(f"{label}.readOnlyLibraryRoots do not equal the external pin")
    raw_runtime_root = data.get("policyRuntimeRoot")
    runtime_root = resolve_path(root, raw_runtime_root, errors, f"{label}.policyRuntimeRoot")
    if sanitized_root is not None and runtime_root != sanitized_root / "_policy_runtime":
        errors.append(f"{label}.policyRuntimeRoot must be sanitizedRoot/_policy_runtime")
    files = data.get("policyRuntimeFiles")
    if not isinstance(files, list):
        errors.append(f"{label}.policyRuntimeFiles must be an array")
        files = []
    by_source: dict[str, dict[str, Any]] = {}
    capsule_keys: list[str] = []
    skill_root = installed_skill_root(errors)
    for index, item in enumerate(files):
        row_label = f"{label}.policyRuntimeFiles[{index}]"
        if not isinstance(item, dict) or set(item) != {
                "sourcePath", "capsulePath", "bytes", "sha256", "role"}:
            errors.append(f"{row_label}: unknown/missing fields")
            continue
        source = item.get("sourcePath")
        if not isinstance(source, str) or source not in D4_RUNTIME_FILES \
                or item.get("role") != D4_RUNTIME_FILES.get(source):
            errors.append(f"{row_label}: sourcePath/role is not in installed closure")
            continue
        if source in by_source:
            errors.append(f"{row_label}.sourcePath is duplicated")
        by_source[source] = item
        installed = (skill_root / source).resolve()
        try:
            installed.relative_to(skill_root)
        except ValueError:
            errors.append(f"{row_label}.sourcePath escapes installed skill")
            continue
        copied = resolve_path(root, item.get("capsulePath"), errors, row_label)
        if copied is not None:
            capsule_keys.append(str(copied).casefold())
            if runtime_root is not None:
                try:
                    copied.relative_to(runtime_root)
                except ValueError:
                    errors.append(f"{row_label}.capsulePath must stay below policyRuntimeRoot")
            if not installed.is_file() or not copied.is_file():
                errors.append(f"{row_label}: installed source/capsule copy is missing")
            else:
                actual_bytes, actual_hash = installed.stat().st_size, sha256(installed)
                if item.get("bytes") != actual_bytes or item.get("sha256") != actual_hash \
                        or copied.read_bytes() != installed.read_bytes():
                    errors.append(f"{row_label}: copy does not exactly equal installed source")
    if set(by_source) != set(D4_RUNTIME_FILES):
        errors.append(f"{label}.policyRuntimeFiles must exact-cover transitive runtime closure")
    if len(capsule_keys) != len(set(capsule_keys)):
        errors.append(f"{label}.policyRuntimeFiles capsule paths must be unique")
    digest_payload = {
        "operatorRuntimePinId": pin_id,
        "pythonExecutable": data.get("pythonExecutable"),
        "gitExecutable": data.get("gitExecutable"),
        "readOnlyLibraryRoots": sorted(
            data.get("readOnlyLibraryRoots", []), key=lambda value: str(value.get("path", ""))
            if isinstance(value, dict) else ""),
        "policyRuntimeRoot": raw_runtime_root,
        "policyRuntimeFiles": sorted(files, key=lambda value: str(value.get("capsulePath", ""))
                                     if isinstance(value, dict) else ""),
    }
    if data.get("digestSha256") != canonical_json_sha256(digest_payload):
        errors.append(f"{label}.digestSha256 mismatch")
    if isinstance(ref, dict) and ref.get("digestSha256") != data.get("digestSha256"):
        errors.append(f"{label}: reference digest does not bind runtime allowlist")
    return data, runtime_root


def validate_d4_policy(
        root: Path, ref: Any, runtime_data: dict[str, Any] | None,
        runtime_root: Path | None, sanitized_root: Path | None, prefix: str,
        candidate_ref: dict[str, Any], candidate: dict[str, Any],
        errors: list[str], label: str, *, capsule_path: Path | None = None,
        provenance_config: Path | None = None) -> dict[str, Any] | None:
    if not isinstance(ref, dict) or set(ref) != {
            "id", "path", "sha256", "compiledPolicySha256"}:
        errors.append(f"{label}: policy reference has unknown/missing fields")
        return None
    loaded = verify_ref(
        root, {"path": ref.get("path"), "sha256": ref.get("sha256")}, errors, label)
    if loaded is None:
        return None
    _, policy = loaded
    expected = {
        "schemaVersion", "id", "policyVersion", "createdAt", "installedSkillRoot",
        "sourceComponents", "promptCompilation", "sourceTreePolicy",
        "preflightCommands", "lanePolicies", "denyCategories", "compiledPolicySha256",
    }
    if set(policy) != expected:
        errors.append(f"{label}: policy has unknown/missing fields")
    if policy.get("schemaVersion") != "1.0.0" \
            or policy.get("policyVersion") != "d4-audit-policy-v1" \
            or policy.get("id") != ref.get("id") \
            or not isinstance(policy.get("id"), str) \
            or re.fullmatch(r"D4-POLICY-[A-Z0-9][A-Z0-9._-]*",
                            policy.get("id", "")) is None:
        errors.append(f"{label}: policy identity/version is invalid")
    if not timezone_datetime(policy.get("createdAt")):
        errors.append(f"{label}.createdAt must be a timezone timestamp")
    if not isinstance(policy.get("installedSkillRoot"), str) \
            or not policy["installedSkillRoot"].strip():
        errors.append(f"{label}.installedSkillRoot must be non-empty informational data")
    skill_root = installed_skill_root(errors)
    expected_components: list[dict[str, Any]] = []
    for role, track, rel in D4_POLICY_COMPONENTS:
        path = skill_root / rel
        if not path.is_file():
            errors.append(f"{label}: installed policy source is missing: {rel}")
            continue
        expected_components.append({
            "role": role, "auditTrack": track, "path": rel,
            "sha256": sha256(path),
        })
    expected_components.sort(key=lambda value: value["path"])
    components = policy.get("sourceComponents")
    if not isinstance(components, list) or components != expected_components:
        errors.append(f"{label}.sourceComponents do not equal installed policy sources")
    if policy.get("promptCompilation") != D4_PROMPT_COMPILATION:
        errors.append(f"{label}.promptCompilation is not canonical-request-core-v1")
    if policy.get("sourceTreePolicy") != D4_SOURCE_TREE_POLICY:
        errors.append(f"{label}.sourceTreePolicy is not the installed complete-tree policy")
    expected_lanes: list[dict[str, Any]] = []
    expected_preflight: list[dict[str, Any]] = []
    if runtime_data is not None and runtime_root is not None \
            and sanitized_root is not None:
        python_pin = runtime_data.get("pythonExecutable")
        python_path = python_pin.get("path") if isinstance(python_pin, dict) else None
        git_pin = runtime_data.get("gitExecutable")
        git_path = git_pin.get("path") if isinstance(git_pin, dict) else None
        if not isinstance(python_path, str):
            errors.append(f"{label}: pinned Python path is unavailable")
        else:
            expected_preflight = _d4_preflight_commands(
                root, candidate_ref, candidate, python_path, runtime_root,
                sanitized_root, git_path, errors, f"{label}.preflightCommands")
            for track in ("consistency", "roblox-readiness", "clean-room"):
                commands = _d4_runtime_commands(
                    track, python_path, runtime_root, sanitized_root, prefix, errors,
                    git_path, capsule_path, provenance_config)
                checklist_path = D4_CHECKLIST_PATHS[track]
                expected_lanes.append({
                    "auditTrack": track,
                    "checklist": {
                        "path": checklist_path,
                        "sha256": sha256(skill_root / checklist_path),
                    },
                    "requiredCheckIds": [value["checkId"] for value in commands],
                    "requiredCommands": commands,
                })
    lanes = policy.get("lanePolicies")
    if not isinstance(lanes, list) or sorted(lanes, key=identity_key) != sorted(
            expected_lanes, key=identity_key):
        errors.append(f"{label}.lanePolicies differ from installed built-in compiler")
    preflight = policy.get("preflightCommands")
    if not isinstance(preflight, list) or sorted(
            preflight, key=lambda value: str(value.get("checkId", ""))
            if isinstance(value, dict) else "") != sorted(
                expected_preflight, key=lambda value: value["checkId"]):
        errors.append(f"{label}.preflightCommands differ from installed built-in compiler")
    if policy.get("denyCategories") != D4_DENY_CATEGORIES:
        errors.append(f"{label}.denyCategories must equal the clean-room denylist")
    compiled_payload = {
        "policyVersion": policy.get("policyVersion"),
        "sourceComponents": sorted(
            components if isinstance(components, list) else [],
            key=lambda value: str(value.get("path", ""))
            if isinstance(value, dict) else ""),
        "promptCompilation": policy.get("promptCompilation"),
        "sourceTreePolicy": policy.get("sourceTreePolicy"),
        "preflightCommands": sorted(
            preflight if isinstance(preflight, list) else [],
            key=lambda value: str(value.get("checkId", ""))
            if isinstance(value, dict) else ""),
        "lanePolicies": sorted(
            lanes if isinstance(lanes, list) else [],
            key=lambda value: str(value.get("auditTrack", ""))
            if isinstance(value, dict) else ""),
        "denyCategories": policy.get("denyCategories"),
    }
    compiled = canonical_json_sha256(compiled_payload)
    if policy.get("compiledPolicySha256") != compiled \
            or ref.get("compiledPolicySha256") != compiled:
        errors.append(f"{label}.compiledPolicySha256 mismatch")
    return policy


def compile_d4_prompt(
        request_core: dict[str, Any], track: str, errors: list[str], label: str) -> bytes | None:
    skill_root = installed_skill_root(errors)
    sections: list[bytes] = [D4_SAFETY_CONTRACT.encode("utf-8")]
    for rel in ["SKILL.md", *sorted(D4_REFERENCE_PATHS + D4_CHECKLIST_CLOSURE),
                "templates/d4_findings.md"]:
        path = skill_root / rel
        try:
            content = path.read_bytes().decode("utf-8").replace("\r\n", "\n").replace(
                "\r", "\n").rstrip("\n").encode("utf-8")
        except (OSError, UnicodeError) as exc:
            errors.append(f"{label}: cannot compile installed prompt section {rel}: {exc}")
            return None
        sections.append(content)
    sections.append(canonical_json_bytes(request_core))
    return D4_PROMPT_COMPILATION["sectionSeparator"].encode("utf-8").join(
        section.rstrip(b"\n") for section in sections) + b"\n"


def validate_d4_capsule_assembly(
        root: Path, capsule: dict[str, Any], candidate_ref: dict[str, Any],
        candidate: dict[str, Any], policy: dict[str, Any] | None,
        runtime_data: dict[str, Any] | None, provenance_runtime: dict[str, Any] | None,
        errors: list[str], label: str) -> dict[str, Any] | None:
    assembly_ref = capsule.get("assemblyAttestation")
    if not isinstance(assembly_ref, dict) or set(assembly_ref) != {"id", "path", "sha256"}:
        errors.append(f"{label}.assemblyAttestation has unknown/missing fields")
        return None
    loaded = verify_ref(
        root, {"path": assembly_ref.get("path"), "sha256": assembly_ref.get("sha256")},
        errors, f"{label}.assemblyAttestation")
    if loaded is None:
        return None
    _, attestation = loaded
    keys = {
        "schemaVersion", "id", "candidate", "auditPolicy", "runtimeAllowlist",
        "sourceTreePolicySha256", "resolvedSource", "sourceStateEvidence",
        "sourceTree", "inputSetSha256", "inputCount", "dependencyClosure",
        "preflight", "assembledAt",
    }
    if set(attestation) != keys:
        errors.append(f"{label}.assemblyAttestation has unknown/missing fields")
    if attestation.get("schemaVersion") != "1.0.0" \
            or attestation.get("id") != assembly_ref.get("id") \
            or not isinstance(attestation.get("id"), str) \
            or re.fullmatch(r"D4-CAPSULE-ASSEMBLY-[A-Z0-9][A-Z0-9._-]*",
                            str(attestation.get("id"))) is None:
        errors.append(f"{label}.assemblyAttestation identity/version is invalid")
    expected_candidate = {**candidate_ref, "revision": candidate.get("revision")}
    if attestation.get("candidate") != expected_candidate:
        errors.append(f"{label}.assemblyAttestation candidate/revision mismatch")
    if attestation.get("auditPolicy") != capsule.get("auditPolicy"):
        errors.append(f"{label}.assemblyAttestation auditPolicy mismatch")
    if attestation.get("runtimeAllowlist") != capsule.get("runtimeAllowlist"):
        errors.append(f"{label}.assemblyAttestation runtimeAllowlist mismatch")
    if attestation.get("sourceTreePolicySha256") != canonical_json_sha256(
            D4_SOURCE_TREE_POLICY):
        errors.append(f"{label}.assemblyAttestation sourceTreePolicySha256 mismatch")
    if attestation.get("inputSetSha256") != capsule.get("inputSetSha256") \
            or attestation.get("inputCount") != len(capsule.get("inputs", [])):
        errors.append(f"{label}.assemblyAttestation input-set binding mismatch")
    dependency = capsule.get("auditScope", {}).get("dependencyClosure") \
        if isinstance(capsule.get("auditScope"), dict) else None
    if attestation.get("dependencyClosure") != dependency:
        errors.append(f"{label}.assemblyAttestation dependencyClosure mismatch")
    verify_artifact_file_ref(
        root, attestation.get("dependencyClosure"), errors,
        f"{label}.assemblyAttestation.dependencyClosure")
    if not timezone_datetime(attestation.get("assembledAt")):
        errors.append(f"{label}.assemblyAttestation.assembledAt must be a timezone timestamp")

    entries = _candidate_source_tree(
        root, candidate, runtime_data, errors, f"{label}.sourceTree")
    revision = candidate.get("revision") if isinstance(candidate.get("revision"), dict) else {}
    source_root = _d4_revision_source_root(root, revision, errors, f"{label}.resolvedSource")
    entries_hash = canonical_json_sha256(entries)
    expected_resolved = {
        "kind": "immutable-snapshot" if revision.get("kind") == "snapshot"
        else "commit-repository",
        "path": str(source_root) if source_root is not None else None,
        "revisionValue": revision.get("value"),
        "treeEntriesSha256": entries_hash,
    }
    if attestation.get("resolvedSource") != expected_resolved:
        errors.append(f"{label}.assemblyAttestation resolvedSource mismatch")
    verify_artifact_file_ref(
        root, attestation.get("sourceStateEvidence"), errors,
        f"{label}.assemblyAttestation.sourceStateEvidence")
    source_tree = attestation.get("sourceTree")
    if not isinstance(source_tree, dict) or set(source_tree) != {
            "entryCount", "entriesSha256", "outputPath", "outputSha256"}:
        errors.append(f"{label}.assemblyAttestation.sourceTree has unknown/missing fields")
        source_tree = {}
    if source_tree.get("entryCount") != len(entries) \
            or source_tree.get("entriesSha256") != entries_hash:
        errors.append(f"{label}.assemblyAttestation source-tree digest/count mismatch")
    tree_path = verify_artifact_file_ref(
        root, {"path": source_tree.get("outputPath"),
               "sha256": source_tree.get("outputSha256")},
        errors, f"{label}.assemblyAttestation.sourceTree.output")
    expected_tree_bytes = canonical_json_bytes(entries) + b"\n"
    if tree_path is not None and tree_path.read_bytes() != expected_tree_bytes:
        errors.append(f"{label}.assemblyAttestation TREE output is not canonical complete tree")
    candidate_rows = {
        item.get("path"): {"path": item.get("path"), "bytes": item.get("bytes"),
                           "sha256": item.get("sha256")}
        for item in candidate.get("files", []) if isinstance(item, dict)
    }
    tree_rows = {item["path"]: item for item in entries}
    if tree_rows != candidate_rows:
        errors.append(f"{label}.assemblyAttestation source tree must exactly equal candidate file set")

    preflight = attestation.get("preflight")
    capsule_preflight = capsule.get("preflight")
    if not isinstance(preflight, list) or len(preflight) != 3:
        errors.append(f"{label}.assemblyAttestation.preflight must exact-cover three checks")
        preflight = []
    for index, row in enumerate(preflight):
        validate_preflight_record(
            root, row, errors, f"{label}.assemblyAttestation.preflight[{index}]")
    source_state_row = next((row for row in preflight if isinstance(row, dict)
                             and row.get("checkId") ==
                             "D4-PREFLIGHT-SOURCE-STATE-001"), None)
    expected_source_state_ref = ({
        "path": source_state_row.get("outputPath"),
        "sha256": source_state_row.get("outputSha256"),
    } if isinstance(source_state_row, dict) else None)
    if attestation.get("sourceStateEvidence") != expected_source_state_ref:
        errors.append(
            f"{label}.assemblyAttestation sourceStateEvidence must bind SOURCE-STATE output")
    if preflight != capsule_preflight:
        errors.append(f"{label}.assemblyAttestation preflight differs from capsule")
    policy_preflight = policy.get("preflightCommands", []) if isinstance(policy, dict) else []
    by_id = {row.get("checkId"): row for row in policy_preflight if isinstance(row, dict)}
    for row in preflight:
        if not isinstance(row, dict):
            continue
        expected = by_id.get(row.get("checkId"))
        actual = {key: row.get(key) for key in (
            "checkId", "argv", "cwd", "expectedExitCode")}
        if expected != actual:
            errors.append(
                f"{label}.assemblyAttestation preflight is not installed-policy exact")
        operation = {
            "D4-PREFLIGHT-SOURCE-STATE-001": "source-state",
            "D4-PREFLIGHT-REVISION-001": "revision",
            "D4-PREFLIGHT-TREE-001": "tree",
        }.get(str(row.get("checkId", "")), "invalid")
        output_path = resolve_path(root, row.get("outputPath"), errors, label)
        if output_path is None or not output_path.is_file():
            continue
        manifest_path = resolve_path(root, candidate_ref.get("path"), errors, label)
        if operation == "tree":
            expected_output = expected_tree_bytes
        elif operation == "revision":
            expected_output = canonical_json_bytes({
                "candidateId": candidate.get("baselineId"),
                "revision": candidate.get("revision"),
                "candidateManifestSha256": sha256(manifest_path)
                if manifest_path is not None and manifest_path.is_file() else None,
            }) + b"\n"
        else:
            evidence = revision.get("gitStatusEvidence")
            evidence_hash = None
            if isinstance(evidence, str):
                evidence_path = resolve_path(root, evidence, errors, label)
                if evidence_path is not None and evidence_path.is_file():
                    evidence_hash = sha256(evidence_path)
            expected_output = canonical_json_bytes({
                "candidateId": candidate.get("baselineId"),
                "revisionKind": revision.get("kind"),
                "sourceTreeEntriesSha256": entries_hash,
                "sourceStateEvidence": ({"path": evidence, "sha256": evidence_hash}
                                        if isinstance(evidence, str) else None),
            }) + b"\n"
        if output_path.read_bytes() != expected_output:
            errors.append(f"{label}.assemblyAttestation {operation.upper()} output mismatch")

    claims = {
        "kind": "d4-capsule-assembly-v1", "attestationId": attestation.get("id"),
        **{key: attestation.get(key) for key in (
            "candidate", "auditPolicy", "runtimeAllowlist", "sourceTreePolicySha256",
            "resolvedSource", "sourceStateEvidence", "sourceTree", "inputSetSha256",
            "inputCount", "dependencyClosure", "preflight", "assembledAt")},
    }
    subject = {"id": assembly_ref.get("id"), "path": assembly_ref.get("path"),
               "sha256": assembly_ref.get("sha256")}
    pv = validate_provenance_verification(
        root, capsule.get("capsuleAssemblyProvenance"),
        "d4-capsule-assembly-attestation", subject, claims,
        provenance_runtime, errors, f"{label}.capsuleAssemblyProvenance")
    return attestation if pv is not None else None


D4_DENY_CATEGORIES = [
    "conversation-history", "worker-identity", "prior-findings", "expected-verdict",
    "e0-capability-probe", "handoff-conversation", "self-evaluation",
]


def validate_d4_capsule(
        root: Path, ref: Any, candidate_ref: dict[str, Any], prefix: str,
        runtime: dict[str, Any] | None, errors: list[str],
        label: str) -> dict[str, Any] | None:
    loaded = exact_artifact_ref(root, ref, errors, label)
    if loaded is None:
        return None
    capsule_path, capsule = loaded
    expected_keys = {
        "schemaVersion", "id", "candidate", "auditScope", "auditPolicy",
        "runtimeAllowlist", "assemblyAttestation", "capsuleAssemblyProvenance",
        "p0LifecycleTransition",
        "createdAt", "sanitizedRoot", "inputs",
        "inputSetSha256", "preflight", "requiredAuditCommands", "denyCategories",
    }
    if set(capsule) != expected_keys:
        errors.append(f"{label}: capsule has unknown/missing fields")
    if capsule.get("schemaVersion") != "1.0.0":
        errors.append(f"{label}.schemaVersion must be 1.0.0")
    if not isinstance(capsule.get("id"), str) or re.fullmatch(
            r"D4-CAPSULE-[A-Z0-9][A-Z0-9._-]*", capsule["id"]) is None:
        errors.append(f"{label}.id is invalid")
    candidate_loaded = verify_ref(root, candidate_ref, errors, f"{label}.candidate")
    candidate_manifest: dict[str, Any] = candidate_loaded[1] if candidate_loaded else {}
    expected_capsule_candidate = {
        **candidate_ref,
        "revision": candidate_manifest.get("revision"),
    }
    if capsule.get("candidate") != expected_capsule_candidate:
        errors.append(
            f"{label}.candidate must exactly bind the candidate reference and revision")
    if not timezone_datetime(capsule.get("createdAt")):
        errors.append(f"{label}.createdAt must be a timezone timestamp")
    sanitized_root = resolve_path(root, capsule.get("sanitizedRoot"), errors, label)
    if sanitized_root is not None and not sanitized_root.is_dir():
        errors.append(f"{label}.sanitizedRoot must be an immutable directory")
    runtime_data, runtime_root = validate_d4_runtime_allowlist(
        root, capsule.get("runtimeAllowlist"), sanitized_root, runtime,
        errors, f"{label}.runtimeAllowlist")
    policy = validate_d4_policy(
        root, capsule.get("auditPolicy"), runtime_data, runtime_root,
        sanitized_root, prefix, candidate_ref, candidate_manifest,
        errors, f"{label}.auditPolicy", capsule_path=capsule_path,
        provenance_config=(runtime.get("configPath")
                           if isinstance(runtime, dict) else None))

    scope = capsule.get("auditScope")
    if not isinstance(scope, dict) or set(scope) != {
            "kind", "mode", "sourceBaseline", "machineDiff", "dependencyClosure"}:
        errors.append(f"{label}.auditScope has unknown/missing fields")
        scope = {}
    candidate_id = candidate_ref.get("id") if isinstance(candidate_ref, dict) else None
    if isinstance(candidate_id, str) and candidate_id.startswith("D4-CAND-"):
        if scope.get("kind") != "initial-d4-v1" or scope.get("mode") != "full" \
                or scope.get("sourceBaseline") is not None \
                or scope.get("machineDiff") is not None:
            errors.append(f"{label}.auditScope: initial D4 must be full with no B0/diff")
        if capsule.get("p0LifecycleTransition") is not None:
            errors.append(f"{label}.p0LifecycleTransition must be null for initial D4")
    elif isinstance(candidate_id, str) and candidate_id.startswith("P0-CAND-"):
        if scope.get("kind") != "post-p0-d4-v1" \
                or scope.get("mode") not in {"full", "delta"}:
            errors.append(f"{label}.auditScope: post-P0 kind/mode is invalid")
        proof = capsule.get("p0LifecycleTransition")
        if not isinstance(proof, dict) or set(proof) != {
                "attestation", "writeLog", "provenanceVerification"}:
            errors.append(
                f"{label}.p0LifecycleTransition must be a closed post-P0 proof ref")
        source = scope.get("sourceBaseline")
        if not isinstance(source, dict) or set(source) != {
                "id", "path", "sha256", "fileSetSha256"}:
            errors.append(f"{label}.auditScope.sourceBaseline is invalid")
        else:
            source_loaded = verify_ref(root, source, errors, f"{label}.auditScope.sourceBaseline")
            candidate_loaded_for_scope = verify_ref(
                root, candidate_ref, errors, f"{label}.auditScope.candidate")
            if candidate_loaded_for_scope is not None and source.get("id") != \
                    candidate_loaded_for_scope[1].get("parentBaselineId"):
                errors.append(f"{label}.auditScope.sourceBaseline must equal candidate B0 parent")
            if source_loaded is not None and (source_loaded[1].get("stage") != "B0" \
                    or source_loaded[1].get("fileSetSha256") != source.get("fileSetSha256")):
                errors.append(f"{label}.auditScope.sourceBaseline identity/file set mismatch")
        verify_artifact_file_ref(
            root, scope.get("machineDiff"), errors, f"{label}.auditScope.machineDiff")
    verify_artifact_file_ref(
        root, scope.get("dependencyClosure"), errors,
        f"{label}.auditScope.dependencyClosure")

    candidate_files: dict[str, dict[str, Any]] = {}
    if candidate_loaded is not None:
        raw_files = candidate_loaded[1].get("files")
        if isinstance(raw_files, list):
            candidate_files = {
                item.get("path"): item for item in raw_files
                if isinstance(item, dict) and isinstance(item.get("path"), str)
            }
    inputs = capsule.get("inputs")
    if not isinstance(inputs, list) or not inputs:
        errors.append(f"{label}.inputs must be a non-empty array")
        inputs = []
    source_paths: list[str] = []
    capsule_paths: list[str] = []
    canonical_sources: set[str] = set()
    for index, item in enumerate(inputs):
        row_label = f"{label}.inputs[{index}]"
        if not isinstance(item, dict) or set(item) != {
                "sourcePath", "capsulePath", "bytes", "sha256", "role"}:
            errors.append(f"{row_label}: unknown/missing fields")
            continue
        source_path, capsule_path = item.get("sourcePath"), item.get("capsulePath")
        if not isinstance(source_path, str) or not source_path or "\\" in source_path:
            errors.append(f"{row_label}.sourcePath must be canonical project-relative POSIX")
            continue
        source_paths.append(source_path)
        if item.get("role") not in {
                "canonical", "baseline-canonical", "validation", "evidence", "repo-fact",
                "machine-diff", "dependency"}:
            errors.append(f"{row_label}.role is invalid")
        if item.get("role") == "canonical":
            canonical_sources.add(source_path)
        copied = resolve_path(root, capsule_path, errors, row_label)
        if isinstance(capsule_path, str):
            capsule_paths.append(capsule_path.replace("\\", "/"))
        if copied is not None:
            if sanitized_root is not None:
                try:
                    copied.relative_to(sanitized_root)
                except ValueError:
                    errors.append(f"{row_label}.capsulePath must stay below sanitizedRoot")
            if not copied.is_file():
                errors.append(f"{row_label}.capsulePath is missing")
            else:
                if type(item.get("bytes")) is not int or item.get("bytes") != copied.stat().st_size:
                    errors.append(f"{row_label}.bytes mismatch")
                if item.get("sha256") != sha256(copied):
                    errors.append(f"{row_label}.sha256 mismatch")
        candidate_item = candidate_files.get(source_path)
        if item.get("role") == "canonical" and candidate_item is not None:
            if item.get("bytes") != candidate_item.get("bytes") \
                    or item.get("sha256") != candidate_item.get("sha256"):
                errors.append(f"{row_label}: canonical copy differs from candidate manifest")
    source_role_keys = [identity_key((item.get("role"), item.get("sourcePath")))
                        for item in inputs if isinstance(item, dict)]
    if len(source_role_keys) != len(set(source_role_keys)) \
            or len(capsule_paths) != len(set(value.casefold() for value in capsule_paths)):
        errors.append(f"{label}.inputs role/sourcePath and capsulePath values must be unique")
    if canonical_sources != set(candidate_files):
        errors.append(f"{label}.inputs must canonically cover every candidate file exactly once")
    sorted_inputs = sorted(inputs, key=lambda value: (
        str(value.get("role", "")), str(value.get("sourcePath", "")),
        str(value.get("capsulePath", ""))) if isinstance(value, dict) else ("", "", ""))
    if capsule.get("inputSetSha256") != canonical_json_sha256(sorted_inputs):
        errors.append(f"{label}.inputSetSha256 mismatch")
    if scope.get("kind") == "post-p0-d4-v1":
        baseline_sources = {
            item.get("sourcePath") for item in inputs if isinstance(item, dict)
            and item.get("role") == "baseline-canonical"}
        source_ref = scope.get("sourceBaseline")
        source_loaded = verify_ref(root, source_ref, errors, f"{label}.B0 coverage") \
            if isinstance(source_ref, dict) else None
        source_files = set()
        if source_loaded is not None and isinstance(source_loaded[1].get("files"), list):
            source_files = {item.get("path") for item in source_loaded[1]["files"]
                            if isinstance(item, dict) and isinstance(item.get("path"), str)}
            source_rows = {item.get("path"): item for item in source_loaded[1]["files"]
                           if isinstance(item, dict) and isinstance(item.get("path"), str)}
            for item in inputs:
                if not isinstance(item, dict) or item.get("role") != "baseline-canonical":
                    continue
                source_row = source_rows.get(item.get("sourcePath"))
                if source_row is None or item.get("bytes") != source_row.get("bytes") \
                        or item.get("sha256") != source_row.get("sha256"):
                    errors.append(
                        f"{label}.inputs baseline copy differs from B0 manifest record")
        if baseline_sources != source_files:
            errors.append(f"{label}.inputs must exact-cover historical B0 canonical paths")
        for required_role in ("machine-diff", "dependency"):
            if not any(isinstance(item, dict) and item.get("role") == required_role
                       for item in inputs):
                errors.append(f"{label}.inputs missing post-P0 {required_role} evidence")

    preflight = capsule.get("preflight")
    if not isinstance(preflight, list) or len(preflight) != 3:
        errors.append(f"{label}.preflight must exact-cover three command records")
        preflight = []
    for index, command in enumerate(preflight):
        validate_preflight_record(root, command, errors, f"{label}.preflight[{index}]")
    expected_preflight = policy.get("preflightCommands", []) \
        if isinstance(policy, dict) else []
    actual_preflight_contract = [{
        key: row.get(key) for key in ("checkId", "argv", "cwd", "expectedExitCode")
    } for row in preflight if isinstance(row, dict)]
    if sorted(actual_preflight_contract, key=identity_key) != sorted(
            expected_preflight, key=identity_key):
        errors.append(f"{label}.preflight differs from installed policy commands")
    required_commands = capsule.get("requiredAuditCommands")
    if not isinstance(required_commands, list) or len(required_commands) < 3:
        errors.append(f"{label}.requiredAuditCommands requires all three lanes")
        required_commands = []
    command_ids: list[str] = []
    command_keys: list[tuple[Any, Any, Any, Any]] = []
    command_tracks: set[str] = set()
    for index, command in enumerate(required_commands):
        row_label = f"{label}.requiredAuditCommands[{index}]"
        if not isinstance(command, dict) or set(command) != {
                "auditTrack", "checkId", "argv", "cwd", "expectedExitCode"}:
            errors.append(f"{row_label}: unknown/missing fields")
            continue
        track, check_id = command.get("auditTrack"), command.get("checkId")
        if track not in {"consistency", "roblox-readiness", "clean-room"}:
            errors.append(f"{row_label}.auditTrack is invalid")
        else:
            command_tracks.add(track)
        if not isinstance(check_id, str) or re.fullmatch(
                r"[A-Z0-9][A-Z0-9._-]*", check_id) is None:
            errors.append(f"{row_label}.checkId is invalid")
        else:
            command_ids.append(check_id)
        argv = command.get("argv")
        if not isinstance(argv, list) or not argv or any(
                not isinstance(token, str) or not token or unresolved_cell(token)
                for token in argv):
            errors.append(f"{row_label}.argv must be a non-empty literal string array")
        if not isinstance(command.get("cwd"), str) or unresolved_cell(command.get("cwd")):
            errors.append(f"{row_label}.cwd must be non-placeholder")
        if type(command.get("expectedExitCode")) is not int:
            errors.append(f"{row_label}.expectedExitCode must be an integer")
        command_keys.append((
            track, identity_key(command.get("argv")), command.get("cwd"),
            command.get("expectedExitCode")))
    if len(command_ids) != len(set(value.casefold() for value in command_ids)):
        errors.append(f"{label}.requiredAuditCommands checkId values must be unique")
    if len(command_keys) != len(set(command_keys)):
        errors.append(f"{label}.requiredAuditCommands entries must be unique")
    if command_tracks != {"consistency", "roblox-readiness", "clean-room"}:
        errors.append(f"{label}.requiredAuditCommands must cover all three tracks")
    if capsule.get("denyCategories") != D4_DENY_CATEGORIES:
        errors.append(f"{label}.denyCategories must equal the clean-room denylist")
    if isinstance(policy, dict):
        applicability = {"all", "initial" if str(candidate_id).startswith("D4-CAND-")
                         else "post-p0"}
        expected_commands = []
        for lane in policy.get("lanePolicies", []):
            if not isinstance(lane, dict):
                continue
            expected_commands.extend({
                "auditTrack": lane.get("auditTrack"), "checkId": command.get("checkId"),
                "argv": command.get("argv"), "cwd": command.get("cwd"),
                "expectedExitCode": command.get("expectedExitCode"),
            } for command in lane.get("requiredCommands", [])
                if isinstance(command, dict) and command.get("applicability") in applicability)
        if sorted(required_commands, key=identity_key) != sorted(
                expected_commands, key=identity_key):
            errors.append(f"{label}.requiredAuditCommands differ from installed policy subset")
    capsule["_assembly"] = validate_d4_capsule_assembly(
        root, capsule, candidate_ref, candidate_manifest, policy, runtime_data,
        runtime, errors, label)
    capsule["_validatedPolicy"] = policy
    capsule["_validatedRuntime"] = runtime_data
    capsule["_runtimeRoot"] = runtime_root
    return capsule


def validate_d4_request(
        root: Path, ref: Any, track: Any, candidate_ref: dict[str, Any],
        capsule_ref: Any, capsule: dict[str, Any] | None,
        errors: list[str], label: str) -> dict[str, Any] | None:
    loaded = exact_artifact_ref(root, ref, errors, label)
    if loaded is None:
        return None
    _, request = loaded
    expected_keys = {
        "schemaVersion", "id", "requestCore", "requestCoreSha256",
        "fullPromptArtifact",
    }
    if set(request) != expected_keys:
        errors.append(f"{label}: request has unknown/missing fields")
    if request.get("schemaVersion") != "1.0.0":
        errors.append(f"{label}.schemaVersion must be 1.0.0")
    if not isinstance(request.get("id"), str) or re.fullmatch(
            r"D4-REQUEST-[A-Z0-9][A-Z0-9._-]*", request["id"]) is None:
        errors.append(f"{label}.id is invalid")
    core = request.get("requestCore")
    core_keys = {
        "laneRunId", "auditTrack", "mode", "candidate", "capsule", "auditPolicy",
        "runtimeAllowlist", "purpose", "writePolicy", "contextMode",
        "denyCategories", "requiredCheckIds",
    }
    if not isinstance(core, dict) or set(core) != core_keys:
        errors.append(f"{label}.requestCore has unknown/missing fields")
        core = {}
    if request.get("requestCoreSha256") != canonical_json_sha256(core):
        errors.append(f"{label}.requestCoreSha256 mismatch")
    if not isinstance(core.get("laneRunId"), str) or re.fullmatch(
            r"D4-RUN-[A-Z0-9][A-Z0-9._-]*", core.get("laneRunId", "")) is None:
        errors.append(f"{label}.requestCore.laneRunId is invalid")
    if core.get("auditTrack") != track:
        errors.append(f"{label}.auditTrack must equal the audit record track")
    if core.get("mode") not in {"full", "delta"}:
        errors.append(f"{label}.mode must be full or delta")
    if isinstance(candidate_ref.get("id"), str) \
            and candidate_ref["id"].startswith("D4-CAND-") \
            and core.get("mode") != "full":
        errors.append(f"{label}.mode must be full for an initial D4 candidate")
    if core.get("candidate") != candidate_ref:
        errors.append(f"{label}.candidate must exactly equal the audit candidate")
    if core.get("capsule") != capsule_ref:
        errors.append(f"{label}.capsule must exactly equal the audit capsule")
    if capsule is not None:
        if core.get("mode") != capsule.get("auditScope", {}).get("mode"):
            errors.append(f"{label}.mode must equal capsule.auditScope.mode")
        if core.get("auditPolicy") != capsule.get("auditPolicy"):
            errors.append(f"{label}.auditPolicy must equal capsule.auditPolicy")
        if core.get("runtimeAllowlist") != capsule.get("runtimeAllowlist"):
            errors.append(f"{label}.runtimeAllowlist must equal capsule.runtimeAllowlist")
    for key, expected in (
            ("purpose", "findings-only"), ("writePolicy", "read-only"),
            ("contextMode", "clean")):
        if core.get(key) != expected:
            errors.append(f"{label}.{key} must be {expected}")
    if core.get("denyCategories") != D4_DENY_CATEGORIES:
        errors.append(f"{label}.denyCategories must equal the clean-room denylist")
    required = core.get("requiredCheckIds")
    if not isinstance(required, list) or any(
            not isinstance(item, str) or not item for item in required):
        errors.append(f"{label}.requiredCheckIds must be non-empty strings")
        required = []
    if len(required) != len(set(item.casefold() for item in required)):
        errors.append(f"{label}.requiredCheckIds must be unique")
    expected_ids = sorted(
        command.get("checkId") for command in (
            capsule.get("requiredAuditCommands", []) if capsule is not None else [])
        if isinstance(command, dict) and command.get("auditTrack") == track
        and isinstance(command.get("checkId"), str))
    if sorted(required) != expected_ids:
        errors.append(f"{label}.requiredCheckIds must exact-cover its capsule lane")
    prompt_ref = request.get("fullPromptArtifact")
    prompt_path = verify_artifact_file_ref(
        root, prompt_ref, errors, f"{label}.fullPromptArtifact")
    compiled = compile_d4_prompt(core, str(track), errors, label)
    if prompt_path is not None and compiled is not None \
            and prompt_path.read_bytes() != compiled:
        errors.append(f"{label}.fullPromptArtifact is not the installed-policy compilation")
    request["_core"] = core
    return request


def validate_d4_attestation(
        root: Path, ref: Any, track: Any, capsule_ref: Any,
        capsule: dict[str, Any] | None, raw_ref: dict[str, Any],
        request_ref: Any, request: dict[str, Any] | None,
        errors: list[str], label: str) -> dict[str, Any] | None:
    loaded = exact_artifact_ref(root, ref, errors, label)
    if loaded is None:
        return None
    _, attestation = loaded
    expected_keys = {
        "schemaVersion", "id", "laneRunId", "executionId", "sessionId",
        "auditTrack", "auditorClass", "worker",
        "requestedModel", "resolvedModel", "toolVersion", "contextMode",
        "filesystemAccess", "capsule", "auditPolicy", "runtimeAllowlist",
        "fullPromptArtifact", "requestCoreSha256", "inspectedInputs", "commands",
        "requestArtifact", "responseArtifact", "finishReason", "startedAt",
        "completedAt",
    }
    if set(attestation) != expected_keys:
        errors.append(f"{label}: attestation has unknown/missing fields")
    if attestation.get("schemaVersion") != "1.0.0":
        errors.append(f"{label}.schemaVersion must be 1.0.0")
    if not isinstance(attestation.get("id"), str) or re.fullmatch(
            r"D4-ATTEST-[A-Z0-9][A-Z0-9._-]*", attestation["id"]) is None:
        errors.append(f"{label}.id is invalid")
    if attestation.get("auditTrack") != track:
        errors.append(f"{label}.auditTrack must equal the audit record track")
    request_core = request.get("_core", {}) if isinstance(request, dict) else {}
    if request is None or attestation.get("laneRunId") != request_core.get("laneRunId"):
        errors.append(f"{label}.laneRunId must exactly equal the audit request")
    for key in ("laneRunId", "executionId", "sessionId"):
        if not isinstance(attestation.get(key), str) or unresolved_cell(attestation[key]):
            errors.append(f"{label}.{key} must be non-placeholder")
    if attestation.get("auditorClass") != "A":
        errors.append(f"{label}.auditorClass must be A")
    for key in ("worker", "requestedModel", "resolvedModel", "toolVersion", "finishReason"):
        if not isinstance(attestation.get(key), str) or unresolved_cell(attestation[key]):
            errors.append(f"{label}.{key} must be non-placeholder")
    if str(attestation.get("resolvedModel", "")).casefold() == "unverifiable":
        errors.append(f"{label}.resolvedModel must be independently resolved")
    if attestation.get("finishReason") != "stop":
        errors.append(f"{label}.finishReason must be stop")
    if attestation.get("contextMode") != "clean":
        errors.append(f"{label}.contextMode must be clean")
    if attestation.get("filesystemAccess") != D4_FILESYSTEM_ACCESS:
        errors.append(f"{label}.filesystemAccess must be {D4_FILESYSTEM_ACCESS}")
    if attestation.get("capsule") != capsule_ref:
        errors.append(f"{label}.capsule must exactly equal auditRecords.auditCapsule")
    if capsule is not None and attestation.get("auditPolicy") != capsule.get("auditPolicy"):
        errors.append(f"{label}.auditPolicy must equal capsule/request policy")
    if capsule is not None and attestation.get("runtimeAllowlist") != capsule.get(
            "runtimeAllowlist"):
        errors.append(f"{label}.runtimeAllowlist must equal capsule/request runtime")
    if request is not None and attestation.get("fullPromptArtifact") != request.get(
            "fullPromptArtifact"):
        errors.append(f"{label}.fullPromptArtifact must equal the audit request")
    if request is not None and attestation.get("requestCoreSha256") != request.get(
            "requestCoreSha256"):
        errors.append(f"{label}.requestCoreSha256 must equal the audit request")

    expected_inputs: list[dict[str, Any]] = []
    if capsule is not None and isinstance(capsule.get("inputs"), list):
        expected_inputs = sorted(({
            "path": item.get("capsulePath"), "sha256": item.get("sha256")}
            for item in capsule["inputs"] if isinstance(item, dict)), key=lambda item: str(item["path"]))
    inspected = attestation.get("inspectedInputs")
    if not isinstance(inspected, list):
        errors.append(f"{label}.inspectedInputs must be an array")
        inspected = []
    normalized_inspected: list[dict[str, Any]] = []
    for index, item in enumerate(inspected):
        if not isinstance(item, dict) or set(item) != {"path", "sha256"}:
            errors.append(f"{label}.inspectedInputs[{index}] has unknown/missing fields")
            continue
        verify_file_hash(root, item.get("path"), item.get("sha256"), errors,
                         f"{label}.inspectedInputs[{index}]")
        normalized_inspected.append(item)
    if sorted(normalized_inspected, key=lambda item: str(item["path"])) != expected_inputs:
        errors.append(f"{label}.inspectedInputs must exactly cover the capsule inputs")

    commands = attestation.get("commands")
    if not isinstance(commands, list) or not commands:
        errors.append(f"{label}.commands must be non-empty")
        commands = []
    for index, command in enumerate(commands):
        validate_command_record(
            root, command, errors, f"{label}.commands[{index}]", with_check_id=True)
    selected_ids = request_core.get("requiredCheckIds", [])
    required_commands = [
        command for command in (
            capsule.get("requiredAuditCommands", []) if capsule is not None else [])
        if isinstance(command, dict) and command.get("auditTrack") == track
        and command.get("checkId") in selected_ids
    ]
    expected_command_keys = sorted((
        command.get("checkId"), identity_key(command.get("argv")),
        command.get("cwd"), command.get("expectedExitCode"))
        for command in required_commands)
    actual_command_keys = sorted((
        command.get("checkId"), identity_key(command.get("argv")),
        command.get("cwd"), command.get("exitCode"))
        for command in commands if isinstance(command, dict))
    if actual_command_keys != expected_command_keys:
        errors.append(f"{label}.commands must exact-cover required capsule commands")
    request_artifact = attestation.get("requestArtifact")
    response = attestation.get("responseArtifact")
    verify_artifact_file_ref(root, request_artifact, errors, f"{label}.requestArtifact")
    verify_artifact_file_ref(root, response, errors, f"{label}.responseArtifact")
    if response != raw_ref:
        errors.append(f"{label}.responseArtifact must exactly bind the raw D4 response")
    if request_artifact != request_ref:
        errors.append(f"{label}.requestArtifact must exactly bind the machine audit request")
    for key in ("startedAt", "completedAt"):
        if not timezone_datetime(attestation.get(key)):
            errors.append(f"{label}.{key} must be a timezone timestamp")
    if timezone_datetime(attestation.get("startedAt")) and timezone_datetime(
            attestation.get("completedAt")):
        start = dt.datetime.fromisoformat(attestation["startedAt"])
        end = dt.datetime.fromisoformat(attestation["completedAt"])
        if end < start:
            errors.append(f"{label}.completedAt must not precede startedAt")
    attestation["_claimsBase"] = {
        "kind": "d4-runtime-v1",
        "attestationId": attestation.get("id"),
        "laneRunId": attestation.get("laneRunId"),
        "executionId": attestation.get("executionId"),
        "sessionId": attestation.get("sessionId"),
        "auditTrack": attestation.get("auditTrack"),
        "auditorClass": attestation.get("auditorClass"),
        "worker": attestation.get("worker"),
        "requestedModel": attestation.get("requestedModel"),
        "resolvedModel": attestation.get("resolvedModel"),
        "toolVersion": attestation.get("toolVersion"),
        "contextMode": attestation.get("contextMode"),
        "filesystemAccess": attestation.get("filesystemAccess"),
        "capsule": attestation.get("capsule"),
        "auditPolicy": attestation.get("auditPolicy"),
        "runtimeAllowlist": attestation.get("runtimeAllowlist"),
        "fullPromptSha256": (attestation.get("fullPromptArtifact", {}).get("sha256")
                             if isinstance(attestation.get("fullPromptArtifact"), dict)
                             else None),
        "inspectedInputs": sorted(normalized_inspected, key=identity_key),
        "inspectedInputsSha256": canonical_json_sha256(
            sorted(normalized_inspected, key=identity_key)),
        "requestId": request.get("id") if isinstance(request, dict) else None,
        "requestCoreSha256": attestation.get("requestCoreSha256"),
        "requestSha256": (request_ref.get("sha256") if isinstance(request_ref, dict) else None),
        "requiredCheckIds": selected_ids,
        "commands": [{
            "checkId": command.get("checkId"), "argv": command.get("argv"),
            "cwd": command.get("cwd"), "expectedExitCode": next((
                required.get("expectedExitCode") for required in required_commands
                if required.get("checkId") == command.get("checkId")), None),
            "actualExitCode": command.get("exitCode"),
            "outputPath": command.get("outputPath"),
            "outputSha256": command.get("outputSha256"),
        } for command in commands if isinstance(command, dict)],
        "responseSha256": raw_ref.get("sha256"),
        "finishReason": attestation.get("finishReason"),
        "startedAt": attestation.get("startedAt"),
        "completedAt": attestation.get("completedAt"),
    }
    return attestation


def validate_baseline_audits(
        root: Path, audits: Any, stage: Any, promoted_from: Any,
        baseline_file_set: Any, prefix: str, runtime: dict[str, Any] | None,
        errors: list[str], label: str) -> None:
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
    record_ids: list[str] = []
    raw_refs: list[tuple[Any, Any]] = []
    candidate_refs: list[dict[str, Any]] = []
    capsule_refs: list[dict[str, Any]] = []
    capsule_p0_transition_refs: list[Any] = []
    attestation_refs: list[dict[str, Any]] = []
    attestation_ids: list[Any] = []
    request_refs: list[Any] = []
    provenance_refs: list[Any] = []
    lane_run_ids: list[Any] = []
    execution_ids: list[Any] = []
    session_ids: list[Any] = []
    modes: list[Any] = []
    if len(audits) != 3:
        errors.append(f"{label}.auditRecords must contain exactly three records")
    for index, record in enumerate(audits):
        row_label = f"{label}.auditRecords[{index}]"
        if not isinstance(record, dict):
            errors.append(f"{row_label} must be an object")
            continue
        allowed = {
            "id", "auditTrack", "path", "sha256", "auditCapsule",
            "auditRequest", "auditorAttestation", "provenanceVerification",
            "candidateBaseline",
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
        else:
            record_ids.append(record["id"])
        raw_refs.append((record.get("path"), record.get("sha256")))
        if (type(record.get("criticalCount")) is not int
                or type(record.get("majorCount")) is not int
                or record.get("criticalCount") != 0
                or record.get("majorCount") != 0
                or record.get("verdict") != "pass"):
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
        capsule_ref = record.get("auditCapsule")
        if isinstance(capsule_ref, dict):
            capsule_refs.append(capsule_ref)
        capsule = validate_d4_capsule(
            root, capsule_ref, candidate_ref, prefix, runtime, errors,
            f"{row_label}.auditCapsule")
        request_ref = record.get("auditRequest")
        if isinstance(request_ref, dict):
            request_refs.append(request_ref)
        request = validate_d4_request(
            root, request_ref, track, candidate_ref, capsule_ref, capsule,
            errors, f"{row_label}.auditRequest")
        if request is not None:
            modes.append(request.get("_core", {}).get("mode"))
        attestation_ref = record.get("auditorAttestation")
        if isinstance(attestation_ref, dict):
            attestation_refs.append(attestation_ref)
        attestation = validate_d4_attestation(
            root, attestation_ref, track, capsule_ref, capsule,
            {"path": record.get("path"), "sha256": record.get("sha256")},
            request_ref, request, errors, f"{row_label}.auditorAttestation")
        if attestation is not None:
            attestation_ids.append(attestation.get("id"))
            lane_run_ids.append(attestation.get("laneRunId"))
            execution_ids.append(attestation.get("executionId"))
            session_ids.append(attestation.get("sessionId"))
        provenance_ref = record.get("provenanceVerification")
        if not isinstance(provenance_ref, dict) or set(provenance_ref) != {
                "path", "sha256"}:
            errors.append(f"{row_label}.provenanceVerification has unknown/missing fields")
        else:
            provenance_refs.append(provenance_ref)
            loaded_pv = verify_ref(
                root, provenance_ref, errors, f"{row_label}.provenanceVerification")
            claims_base = attestation.get("_claimsBase") \
                if isinstance(attestation, dict) else None
            if loaded_pv is not None and isinstance(claims_base, dict):
                provider_policy = loaded_pv[1].get("claims", {}).get("providerPolicy") \
                    if isinstance(loaded_pv[1].get("claims"), dict) else None
                if not isinstance(provider_policy, dict) or set(provider_policy) != {
                        "id", "sha256"} or not isinstance(provider_policy.get("id"), str) \
                        or not provider_policy["id"].strip() \
                        or not isinstance(provider_policy.get("sha256"), str) \
                        or SHA256_RE.fullmatch(provider_policy.get("sha256", "")) is None:
                    errors.append(f"{row_label}.provenanceVerification providerPolicy invalid")
                expected_claims = dict(claims_base, providerPolicy=provider_policy)
                attestation["_providerPolicy"] = provider_policy
                validate_provenance_verification(
                    root, provenance_ref, "d4-auditor-attestation",
                    {"id": attestation.get("id"),
                     "path": attestation_ref.get("path")
                     if isinstance(attestation_ref, dict) else None,
                     "sha256": attestation_ref.get("sha256")
                     if isinstance(attestation_ref, dict) else None},
                    expected_claims, runtime, errors,
                    f"{row_label}.provenanceVerification")
        if raw_path is not None:
            parse_d4_record(
                raw_path, record, candidate_ref, errors, row_label,
                capsule_ref=capsule_ref, attestation=attestation)
    if seen != tracks:
        errors.append(f"{label}.auditRecords must cover all three D4 tracks")
    if candidate_refs and any(ref != candidate_refs[0] for ref in candidate_refs[1:]):
        errors.append(f"{label}.auditRecords must reference one exact candidate")
    if capsule_refs and any(ref != capsule_refs[0] for ref in capsule_refs[1:]):
        errors.append(f"{label}.auditRecords must reference one exact D4 audit capsule")
    if len(modes) != 3 or len({identity_key(value) for value in modes}) != 1:
        errors.append(f"{label}.auditRecords must use one identical audit mode")
    for values, description in (
            (record_ids, "record IDs"), (raw_refs, "raw response refs"),
            (attestation_refs, "attestation refs"), (attestation_ids, "attestation IDs"),
            (request_refs, "request artifact refs"),
            (provenance_refs, "provenance verification refs"),
            (lane_run_ids, "lane run IDs"),
            (execution_ids, "execution IDs"), (session_ids, "session IDs")):
        if len(values) != 3 or len(values) != len(
                {identity_key(value) for value in values}):
            errors.append(f"{label}.auditRecords must use unique lane {description}")


def validate_d15_registry(
        root: Path, ref: Any, project: str, prefix: str,
        errors: list[str], label: str) -> tuple[list[str], dict[str, dict[str, Any]]]:
    if not isinstance(ref, dict) or set(ref) != {
            "path", "sha256", "applicableMeasurementCount"}:
        errors.append(f"{label}: trigger registry reference has unknown/missing fields")
        return [], {}
    count = ref.get("applicableMeasurementCount")
    if type(count) is not int or count < 0:
        errors.append(f"{label}.applicableMeasurementCount must be a non-negative integer")
    loaded = verify_ref(
        root, {"path": ref.get("path"), "sha256": ref.get("sha256")}, errors, label)
    if loaded is None:
        return [], {}
    registry = loaded[1]
    if set(registry) != {"schemaVersion", "project", "prefix", "required_specs"}:
        errors.append(f"{label}: trigger registry has unknown/missing fields")
    if registry.get("schemaVersion") != "1.0.0":
        errors.append(f"{label}.schemaVersion must be 1.0.0")
    if registry.get("project") != project or registry.get("prefix") != prefix:
        errors.append(f"{label}: trigger registry project/prefix identity mismatch")
    specs = registry.get("required_specs")
    if not isinstance(specs, list):
        errors.append(f"{label}.required_specs must be an array")
        specs = []
    ids: list[str] = []
    measurement_ids: list[str] = []
    measurement_contracts: dict[str, dict[str, Any]] = {}
    for index, item in enumerate(specs):
        if not isinstance(item, dict) or set(item) != {
                "id", "template", "reason", "measurementContract"}:
            errors.append(f"{label}.required_specs[{index}] has unknown/missing fields")
            continue
        spec_id = item.get("id")
        if not isinstance(spec_id, str) or not spec_id:
            errors.append(f"{label}.required_specs[{index}].id must be non-empty")
            continue
        ids.append(spec_id)
        if spec_id == "feasibility_report":
            measurement_ids.append(spec_id)
            expected_contract = {
                "kind": "d1.5-combined-suite-v1",
                "experimentId": "feasibility_report-combined-v1",
                "cardinality": "exactly-one",
                "coverage": "all-triggered-high-risk-subchecks",
            }
            contract = item.get("measurementContract")
            if item.get("template") != "feasibility_report.md" \
                    or not isinstance(contract, dict) \
                    or set(contract) != set(expected_contract) | {
                        "requiredSubchecks", "requiredSubchecksSha256"} \
                    or any(contract.get(key) != value
                           for key, value in expected_contract.items()):
                errors.append(
                    f"{label}.required_specs[{index}]: invalid feasibility measurement contract")
                contract = {}
            subchecks = contract.get("requiredSubchecks") if isinstance(contract, dict) else None
            valid_subchecks: list[dict[str, Any]] = []
            if not isinstance(subchecks, list) or not subchecks:
                errors.append(
                    f"{label}.required_specs[{index}]: requiredSubchecks must be non-empty")
                subchecks = []
            for sub_index, subcheck in enumerate(subchecks):
                if not isinstance(subcheck, dict) or set(subcheck) != {
                        "id", "source", "sourceValueSha256"} \
                        or subcheck.get("id") != subcheck.get("source") \
                        or not isinstance(subcheck.get("id"), str) \
                        or re.fullmatch(
                            r"technical\.(?:vehicle_or_custom_physics|high_npc_or_fx_load|"
                            r"high_frequency_projectiles_or_fast_pvp|free_text_or_ugc|multi_place)",
                            subcheck.get("id", "")) is None \
                        or not isinstance(subcheck.get("sourceValueSha256"), str) \
                        or SHA256_RE.fullmatch(subcheck.get("sourceValueSha256", "")) is None:
                    errors.append(
                        f"{label}.required_specs[{index}].requiredSubchecks[{sub_index}] invalid")
                    continue
                valid_subchecks.append(subcheck)
            if subchecks != sorted(subchecks, key=lambda value: str(value.get("id", ""))
                                   if isinstance(value, dict) else "") \
                    or len(valid_subchecks) != len({identity_key(value.get("id"))
                                                   for value in valid_subchecks}):
                errors.append(
                    f"{label}.required_specs[{index}].requiredSubchecks must be sorted/unique")
            if isinstance(contract, dict) and contract.get(
                    "requiredSubchecksSha256") != canonical_json_sha256(subchecks):
                errors.append(
                    f"{label}.required_specs[{index}].requiredSubchecksSha256 mismatch")
            if isinstance(contract, dict):
                measurement_contracts[spec_id] = contract
        elif item.get("measurementContract") is not None:
            errors.append(
                f"{label}.required_specs[{index}].measurementContract must be null")
    if len(ids) != len({identity_key(item) for item in ids}):
        errors.append(f"{label}.required_specs IDs must be unique")
    if count != len(measurement_ids):
        errors.append(
            f"{label}.applicableMeasurementCount must equal trigger-derived D1.5 count")
    return measurement_ids, measurement_contracts


def validate_d15_binding_refs(
        root: Path, values: Any, trigger_ids: list[str] | None,
        errors: list[str], label: str, runtime: dict[str, Any] | None = None,
        gate1_approved_at: str | None = None,
        measurement_contracts: dict[str, dict[str, Any]] | None = None
        ) -> list[dict[str, Any]]:
    if not isinstance(values, list):
        errors.append(f"{label} must be an array")
        return []
    result: list[dict[str, Any]] = []
    seen_experiments: set[str] = set()
    seen_evidence: set[tuple[Any, ...]] = set()
    seen_provenance: set[tuple[Any, ...]] = set()
    for index, item in enumerate(values):
        row_label = f"{label}[{index}]"
        if not isinstance(item, dict) or set(item) != {
                "triggerId", "experimentId", "evidence", "provenanceVerification",
                "result"}:
            errors.append(f"{row_label} has unknown/missing fields")
            continue
        if item.get("result") != "pass":
            errors.append(f"{row_label}.result must be pass")
        if trigger_ids is not None and item.get("triggerId") not in trigger_ids:
            errors.append(f"{row_label}.triggerId is not an applicable D1.5 trigger")
        experiment = item.get("experimentId")
        if not isinstance(experiment, str) or not experiment:
            errors.append(f"{row_label}.experimentId must be non-empty")
        elif identity_key(experiment) in seen_experiments:
            errors.append(f"{row_label}.experimentId must be unique")
        else:
            seen_experiments.add(identity_key(experiment))
        if item.get("triggerId") == "feasibility_report" \
                and experiment != "feasibility_report-combined-v1":
            errors.append(
                f"{row_label}.experimentId must be feasibility_report-combined-v1")
        evidence = item.get("evidence")
        if not isinstance(evidence, dict) or set(evidence) != {"id", "path", "sha256"}:
            errors.append(f"{row_label}.evidence has unknown/missing fields")
            loaded_evidence = None
        else:
            key = identity_key(evidence)
            if key in seen_evidence:
                errors.append(f"{row_label}.evidence must be unique")
            seen_evidence.add(key)
            loaded_evidence = verify_ref(root, evidence, errors, f"{row_label}.evidence")
        provenance = item.get("provenanceVerification")
        if not isinstance(provenance, dict) or set(provenance) != {"path", "sha256"}:
            errors.append(f"{row_label}.provenanceVerification has unknown/missing fields")
        else:
            key = identity_key(provenance)
            if key in seen_provenance:
                errors.append(f"{row_label}.provenanceVerification must be unique")
            seen_provenance.add(key)

        evidence_data = loaded_evidence[1] if loaded_evidence is not None else None
        if isinstance(evidence_data, dict):
            expected_keys = {
                "schemaVersion", "id", "triggerId", "experimentId", "target",
                "requestArtifact", "commandArtifact", "rawResponseArtifact",
                "preFixedThresholdArtifact", "combinedSuite", "result", "runtime",
                "startedAt", "completedAt",
            }
            if set(evidence_data) != expected_keys:
                errors.append(f"{row_label}.evidence: unknown/missing fields")
            if evidence_data.get("schemaVersion") != "1.0.0" \
                    or not isinstance(evidence_data.get("id"), str) \
                    or re.fullmatch(r"D15-EVIDENCE-[A-Z0-9][A-Z0-9._-]*",
                                    evidence_data.get("id", "")) is None:
                errors.append(f"{row_label}.evidence: identity is invalid")
            if evidence_data.get("id") != evidence.get("id"):
                errors.append(f"{row_label}.evidence.id does not bind the reference")
            for field in ("triggerId", "experimentId", "result"):
                if evidence_data.get(field) != item.get(field):
                    errors.append(f"{row_label}.evidence.{field} does not bind the row")
            target = evidence_data.get("target")
            target_keys = {
                "studioVersion", "universeId", "placeId", "sessionId",
                "dataModelSha256",
            }
            if not isinstance(target, dict) or set(target) != target_keys or any(
                    not isinstance(target.get(field), str) or not target[field].strip()
                    for field in target_keys - {"dataModelSha256"}) \
                    or not isinstance(target.get("dataModelSha256"), str) \
                    or SHA256_RE.fullmatch(target.get("dataModelSha256", "")) is None:
                errors.append(f"{row_label}.evidence.target is invalid")
            artifact_hashes: dict[str, Any] = {}
            for field in (
                    "requestArtifact", "commandArtifact", "rawResponseArtifact",
                    "preFixedThresholdArtifact"):
                ref = evidence_data.get(field)
                if not isinstance(ref, dict) or set(ref) != {"path", "sha256"}:
                    errors.append(f"{row_label}.evidence.{field} is not a closed artifact ref")
                    continue
                verify_artifact_file_ref(
                    root, ref, errors, f"{row_label}.evidence.{field}")
                artifact_hashes[field] = ref.get("sha256")
            suite = evidence_data.get("combinedSuite")
            suite_valid = isinstance(suite, dict) and set(suite) == {
                "kind", "coverage", "requiredSubchecksSha256",
                "subcheckEvidenceSetSha256", "overallRule", "subchecks"}
            if not suite_valid or suite.get("kind") != "d1.5-combined-suite-v1" \
                    or suite.get("coverage") != "all-triggered-high-risk-subchecks" \
                    or suite.get("overallRule") != "all-subchecks-pass":
                errors.append(f"{row_label}.evidence.combinedSuite is invalid")
                suite = {}
            subchecks = suite.get("subchecks") if isinstance(suite, dict) else None
            contract = ((measurement_contracts or {}).get(item.get("triggerId"), {}))
            expected_subchecks = contract.get("requiredSubchecks") \
                if isinstance(contract, dict) else None
            expected_subcheck_hash = contract.get("requiredSubchecksSha256") \
                if isinstance(contract, dict) else None
            if suite.get("requiredSubchecksSha256") != expected_subcheck_hash:
                errors.append(
                    f"{row_label}.evidence.combinedSuite requiredSubchecksSha256 mismatch")
            subcheck_ids: list[str] = []
            subcheck_artifacts: set[tuple[str, str, str]] = set()
            if not isinstance(subchecks, list) or not subchecks:
                errors.append(f"{row_label}.evidence.combinedSuite.subchecks must be non-empty")
                subchecks = []
            for sub_index, subcheck in enumerate(subchecks):
                expected_subcheck_keys = {
                    "id", "source", "sourceValueSha256", "trialArtifact",
                    "thresholdArtifact", "rawOutputArtifact", "result",
                    "subcheckEvidenceSha256",
                }
                if not isinstance(subcheck, dict) or set(subcheck) != expected_subcheck_keys \
                        or not isinstance(subcheck.get("id"), str) \
                        or re.fullmatch(
                            r"technical\.(?:vehicle_or_custom_physics|high_npc_or_fx_load|"
                            r"high_frequency_projectiles_or_fast_pvp|free_text_or_ugc|multi_place)",
                            subcheck.get("id", "")) is None \
                        or subcheck.get("source") != subcheck.get("id") \
                        or not isinstance(subcheck.get("sourceValueSha256"), str) \
                        or SHA256_RE.fullmatch(subcheck.get("sourceValueSha256", "")) is None \
                        or subcheck.get("result") not in {"pass", "fail", "inconclusive"}:
                    errors.append(
                        f"{row_label}.evidence.combinedSuite.subchecks[{sub_index}] is invalid")
                    continue
                evidence_payload = {key: subcheck.get(key) for key in (
                    "id", "source", "sourceValueSha256", "trialArtifact",
                    "thresholdArtifact", "rawOutputArtifact", "result")}
                if subcheck.get("subcheckEvidenceSha256") != canonical_json_sha256(
                        evidence_payload):
                    errors.append(
                        f"{row_label}.evidence.combinedSuite.subchecks[{sub_index}] "
                        "subcheckEvidenceSha256 mismatch")
                for artifact_field in (
                        "trialArtifact", "thresholdArtifact", "rawOutputArtifact"):
                    artifact_ref = subcheck.get(artifact_field)
                    if not isinstance(artifact_ref, dict) or set(artifact_ref) != {
                            "path", "sha256"}:
                        errors.append(
                            f"{row_label}.evidence.combinedSuite.subchecks[{sub_index}]."
                            f"{artifact_field} is not a closed artifact ref")
                        continue
                    verify_artifact_file_ref(
                        root, artifact_ref, errors,
                        f"{row_label}.evidence.combinedSuite.subchecks[{sub_index}]."
                        f"{artifact_field}")
                    artifact_key = (
                        artifact_field, str(artifact_ref.get("path")),
                        str(artifact_ref.get("sha256")))
                    if artifact_key in subcheck_artifacts:
                        errors.append(
                            f"{row_label}.evidence {artifact_field} refs must be unique "
                            "per subcheck")
                    subcheck_artifacts.add(artifact_key)
                subcheck_ids.append(subcheck["id"])
            if len(subcheck_ids) != len({identity_key(value) for value in subcheck_ids}):
                errors.append(f"{row_label}.evidence combined subcheck IDs must be unique")
            projected = [{key: value.get(key) for key in (
                "id", "source", "sourceValueSha256")} for value in subchecks
                if isinstance(value, dict)]
            if projected != expected_subchecks:
                errors.append(
                    f"{row_label}.evidence combined subchecks do not exact-cover required specs")
            if subchecks != sorted(
                    subchecks, key=lambda value: str(value.get("id", ""))
                    if isinstance(value, dict) else ""):
                errors.append(f"{row_label}.evidence combined subchecks must be sorted")
            derived_evidence_set = canonical_json_sha256(subchecks)
            if suite.get("subcheckEvidenceSetSha256") != derived_evidence_set:
                errors.append(
                    f"{row_label}.evidence.combinedSuite subcheckEvidenceSetSha256 mismatch")
            derived = ("pass" if subchecks and all(
                isinstance(value, dict) and value.get("result") == "pass"
                for value in subchecks) else "fail" if any(
                    isinstance(value, dict) and value.get("result") == "fail"
                    for value in subchecks) else "inconclusive")
            if evidence_data.get("result") != derived:
                errors.append(f"{row_label}.evidence.result does not match combined subchecks")
            runtime_data = evidence_data.get("runtime")
            if not isinstance(runtime_data, dict) or set(runtime_data) != {
                    "runtimeId", "toolId", "toolVersion"} or any(
                        not isinstance(runtime_data.get(field), str)
                        or not runtime_data[field].strip()
                        for field in ("runtimeId", "toolId", "toolVersion")):
                errors.append(f"{row_label}.evidence.runtime is invalid")
                runtime_data = {}
            started, completed = evidence_data.get("startedAt"), evidence_data.get("completedAt")
            if not timezone_datetime(started) or not timezone_datetime(completed):
                errors.append(f"{row_label}.evidence timestamps must include timezone")
            else:
                started_dt, completed_dt = dt.datetime.fromisoformat(started), dt.datetime.fromisoformat(completed)
                if completed_dt <= started_dt:
                    errors.append(f"{row_label}.evidence.startedAt must precede completedAt")
                if timezone_datetime(gate1_approved_at) and started_dt <= dt.datetime.fromisoformat(
                        gate1_approved_at):
                    errors.append(f"{row_label}.evidence must start after Gate1 approval")
            claims = {
                "kind": "d1.5-measurement-v1",
                "evidenceId": evidence_data.get("id"),
                "evidencePath": evidence.get("path"),
                "evidenceSha256": evidence.get("sha256"),
                "triggerId": evidence_data.get("triggerId"),
                "experimentId": evidence_data.get("experimentId"),
                "target": target,
                "requestSha256": artifact_hashes.get("requestArtifact"),
                "commandSha256": artifact_hashes.get("commandArtifact"),
                "rawResponseSha256": artifact_hashes.get("rawResponseArtifact"),
                "preFixedThresholdSha256": artifact_hashes.get("preFixedThresholdArtifact"),
                "requiredSubchecksSha256": suite.get("requiredSubchecksSha256"),
                "subcheckEvidenceSetSha256": suite.get("subcheckEvidenceSetSha256"),
                "combinedSuiteSha256": canonical_json_sha256(evidence_data.get("combinedSuite")),
                "result": evidence_data.get("result"),
                "runtimeId": runtime_data.get("runtimeId"),
                "toolId": runtime_data.get("toolId"),
                "toolVersion": runtime_data.get("toolVersion"),
                "startedAt": started,
                "completedAt": completed,
            }
            validate_provenance_verification(
                root, provenance, "d1.5-measurement-evidence",
                {"id": evidence.get("id"), "path": evidence.get("path"),
                 "sha256": evidence.get("sha256")}, claims, runtime, errors,
                f"{row_label}.provenanceVerification")
        result.append(item)
    if trigger_ids is not None and (len(result) != len(trigger_ids) or sorted(
            item.get("triggerId") for item in result) != sorted(trigger_ids)):
        errors.append(f"{label} must bind every applicable D1.5 trigger exactly once")
    return result


def validate_baseline(
        root: Path, source_root: Path, data: dict[str, Any], errors: list[str], label: str,
        expected_stage: str, expected_id: Any, project: str, prefix: str,
        verify_current: bool,
        historical_content: dict[str, bytes] | None = None,
        provenance_runtime: dict[str, Any] | None = None) -> dict[str, dict[str, Any]]:
    stage = data.get("stage")
    if data.get("schemaVersion") != "1.0.0":
        errors.append(f"{label}.schemaVersion must be 1.0.0")
    if stage != expected_stage:
        errors.append(f"{label}.stage must be {expected_stage}")
    if data.get("baselineId") != expected_id:
        errors.append(f"{label}.baselineId does not match package reference")
    if data.get("project") != project or data.get("prefix") != prefix:
        errors.append(f"{label}: project/prefix identity mismatch")
    if not timezone_datetime(data.get("createdAt")):
        errors.append(f"{label}.createdAt must be an ISO-8601 timestamp with timezone")
    expected_keys = {
        "schemaVersion", "baselineId", "stage", "project", "prefix", "createdAt",
        "revision", "admission", "gddGate1", "d15Measurements", "p0Transition",
        "parentBaselineId", "promotedFrom", "approvalId",
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
            errors.append(
                f"{label}.revision.kind commit is not W0-eligible in lifecycle v1; "
                "an immutable snapshot is required")
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
    p0_transition = data.get("p0Transition")
    if stage in {"D4-CANDIDATE", "P0-CANDIDATE", "B0"}:
        if p0_transition is not None:
            errors.append(f"{label}.p0Transition must be null before post-P0 D4")
    elif stage in {"B1", "B2"}:
        if not isinstance(p0_transition, dict) or set(p0_transition) != {
                "attestation", "writeLog", "provenanceVerification"}:
            errors.append(f"{label}.p0Transition must be a closed P0 proof reference")
    admission = data.get("admission")
    trigger_ids: list[str] = []
    measurement_contracts: dict[str, dict[str, Any]] = {}
    complete_admission = False
    if not isinstance(admission, dict) or set(admission) != {
            "status", "d15TriggerRegistry", "deficiencies"}:
        errors.append(f"{label}.admission has unknown/missing fields")
        admission = {}
    status = admission.get("status")
    deficiencies = admission.get("deficiencies")
    if status not in {"complete", "deficient-audit-admission"}:
        errors.append(f"{label}.admission.status is invalid")
    if not isinstance(deficiencies, list):
        errors.append(f"{label}.admission.deficiencies must be an array")
        deficiencies = []
    if status == "complete":
        complete_admission = True
        if deficiencies:
            errors.append(f"{label}: complete admission cannot retain deficiencies")
        trigger_ids, measurement_contracts = validate_d15_registry(
            root, admission.get("d15TriggerRegistry"), project, prefix,
            errors, f"{label}.admission.d15TriggerRegistry")
    else:
        if stage != "D4-CANDIDATE":
            errors.append(f"{label}: only D4-CANDIDATE may use deficient audit admission")
        if not deficiencies:
            errors.append(f"{label}: deficient audit admission requires deficiencies")
        valid_codes = {
            "missing-gdd-gate1", "missing-d1.5-trigger-registry",
            "incomplete-d1.5-evidence", "missing-required-document",
            "invalid-machine-contract", "unresolved-d0-d3-gate",
        }
        for index, item in enumerate(deficiencies):
            if not isinstance(item, dict) or set(item) != {
                    "code", "artifactPath", "detail"}:
                errors.append(f"{label}.admission.deficiencies[{index}] is not closed")
                continue
            if item.get("code") not in valid_codes \
                    or not isinstance(item.get("detail"), str) \
                    or not item["detail"].strip() \
                    or (item.get("artifactPath") is not None and not isinstance(
                        item.get("artifactPath"), str)):
                errors.append(f"{label}.admission.deficiencies[{index}] is invalid")
    gate1 = data.get("gddGate1")
    gate1_approved_at: str | None = None
    if gate1 is None and not (stage == "D4-CANDIDATE" and not complete_admission):
        errors.append(f"{label}.gddGate1 is required after complete audit admission")
    elif gate1 is not None and (not isinstance(gate1, dict) or set(gate1) != {
            "id", "path", "sha256"}):
        errors.append(f"{label}.gddGate1 has unknown/missing fields")
    elif isinstance(gate1, dict):
        loaded_gate1 = verify_ref(root, gate1, errors, f"{label}.gddGate1")
        if loaded_gate1 is not None:
            gate1_approved_at = loaded_gate1[1].get("approvedAt")
    validate_d15_binding_refs(
        root, data.get("d15Measurements"), trigger_ids if complete_admission else None, errors,
        f"{label}.d15Measurements", provenance_runtime, gate1_approved_at,
        measurement_contracts)
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
        data.get("fileSetSha256"), prefix, provenance_runtime, errors, label)
    records = validate_file_records(root, data, errors, label, verify_current)
    if not verify_current:
        w0_runtime = provenance_runtime.get("w0ValidatorRuntime") \
            if isinstance(provenance_runtime, dict) else None
        git_pin = w0_runtime.get("_gitExecutable") \
            if isinstance(w0_runtime, dict) else None
        git_executable = git_pin.get("_path") if isinstance(git_pin, dict) else None
        content = verify_historical_files(
            root, source_root, data, records, errors, label, git_executable)
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
        errors: list[str], project: str, prefix: str,
        provenance_runtime: dict[str, Any] | None = None) -> None:
    if b2.get("parentBaselineId") != b1.get("baselineId"):
        errors.append("B2.parentBaselineId must equal B1.baselineId")
    if b2.get("promotedFrom") is not None:
        errors.append("B2.promotedFrom must be null")
    if not b0 or b1.get("parentBaselineId") != b0.get("baselineId"):
        errors.append("B1.parentBaselineId must equal the package-pinned B0.baselineId")
    gate_refs = [item.get("gddGate1") for item in (b0, b1, b2) if item]
    if gate_refs and any(item != gate_refs[0] for item in gate_refs[1:]):
        errors.append("B0/B1/B2 must inherit the same gddGate1 record reference")
    admission_refs = [item.get("admission") for item in (b0, b1, b2) if item]
    if admission_refs and any(item != admission_refs[0] for item in admission_refs[1:]):
        errors.append("B0/B1/B2 must inherit the same complete audit admission")
    d15_refs = [item.get("d15Measurements") for item in (b0, b1, b2) if item]
    if d15_refs and any(item != d15_refs[0] for item in d15_refs[1:]):
        errors.append("B0/B1/B2 must inherit the same D1.5 measurement bindings")
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
                              candidate.get("baselineId"), project, prefix, False,
                              provenance_runtime=provenance_runtime)
            if candidate.get("promotedFrom") is not None:
                errors.append("D4 candidate.promotedFrom must be null")
            if candidate.get("approvalId") is not None:
                errors.append("D4 candidate.approvalId must be null")
            if candidate.get("fileSetSha256") != b0.get("fileSetSha256"):
                errors.append("D4 candidate -> B0 promotion changed fileSetSha256")
            if candidate.get("gddGate1") != b0.get("gddGate1"):
                errors.append("D4 candidate -> B0 changed gddGate1 reference")
            if candidate.get("admission") != b0.get("admission") \
                    or candidate.get("admission", {}).get("status") != "complete":
                errors.append("D4 candidate -> B0 requires identical complete audit admission")
            if candidate.get("d15Measurements") != b0.get("d15Measurements"):
                errors.append("D4 candidate -> B0 changed D1.5 measurement bindings")
    if p0_match is not None:
        _, candidate = p0_match
        validate_baseline(root, source_root, candidate, errors, "P0 candidate", "P0-CANDIDATE",
                          candidate.get("baselineId"), project, prefix, False,
                          provenance_runtime=provenance_runtime)
        if candidate.get("promotedFrom") is not None:
            errors.append("P0 candidate.promotedFrom must be null")
        if candidate.get("approvalId") is not None:
            errors.append("P0 candidate.approvalId must be null")
        if candidate.get("parentBaselineId") != b1.get("parentBaselineId"):
            errors.append("P0 candidate.parentBaselineId must equal B1.parentBaselineId")
        if candidate.get("fileSetSha256") != b1.get("fileSetSha256"):
            errors.append("P0 candidate -> B1 promotion changed fileSetSha256")
        if candidate.get("gddGate1") != b1.get("gddGate1"):
            errors.append("P0 candidate -> B1 changed gddGate1 reference")
        if candidate.get("admission") != b1.get("admission"):
            errors.append("P0 candidate -> B1 changed audit admission")
        if candidate.get("d15Measurements") != b1.get("d15Measurements"):
            errors.append("P0 candidate -> B1 changed D1.5 measurement bindings")


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
        errors: list[str], label: str, *, capsule_ref: Any = None,
        attestation: dict[str, Any] | None = None) -> None:
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
        "Audit capsule path": str(
            capsule_ref.get("path") if isinstance(capsule_ref, dict) else ""),
        "Audit capsule SHA-256": str(
            capsule_ref.get("sha256") if isinstance(capsule_ref, dict) else ""),
        "Verdict": "pass",
    }
    if attestation is not None:
        request = attestation.get("requestArtifact")
        policy = attestation.get("auditPolicy")
        runtime_ref = attestation.get("runtimeAllowlist")
        prompt = attestation.get("fullPromptArtifact")
        provider_policy = attestation.get("_providerPolicy")
        required.update({
            "Installed-policy manifest path / SHA-256 / compiledPolicySha256": (
                f"{policy.get('path')} / {policy.get('sha256')} / "
                f"{policy.get('compiledPolicySha256')}"
                if isinstance(policy, dict) else ""),
            "Runtime allowlist path / SHA-256 / digestSha256": (
                f"{runtime_ref.get('path')} / {runtime_ref.get('sha256')} / "
                f"{runtime_ref.get('digestSha256')}"
                if isinstance(runtime_ref, dict) else ""),
            "Audit request ID": str(attestation.get("_claimsBase", {}).get("requestId")),
            "Audit request artifact path": str(
                request.get("path") if isinstance(request, dict) else ""),
            "Audit request artifact SHA-256": str(
                request.get("sha256") if isinstance(request, dict) else ""),
            "Canonical requestCore SHA-256": str(attestation.get("requestCoreSha256")),
            "Exact orchestrator-submitted payload path / SHA-256": (
                f"{prompt.get('path')} / {prompt.get('sha256')}"
                if isinstance(prompt, dict) else ""),
            "Lane run ID": str(attestation.get("laneRunId")),
        })
    for key, expected in required.items():
        if key in duplicates or fields.get(key) != expected:
            errors.append(f"{label}: raw D4 field {key!r} must uniquely equal {expected!r}")
    findings = markdown_section(text, "Findings", 2)
    derived = {"critical": 0, "major": 0, "minor": 0, "observation": 0}
    if findings is None:
        errors.append(f"{label}: raw D4 Findings section must be unique")
    else:
        finding_lines = findings.splitlines()
        open_high = 0
        finding_ids: set[str] = set()
        expected_prefix = str(record.get("auditTrack") or "").upper()
        headings: list[tuple[int, re.Match[str]]] = []
        for index, line in enumerate(finding_lines):
            if re.match(r"^###\s+", line) is None:
                continue
            heading = re.fullmatch(
                rf"###\s+(D4-{re.escape(expected_prefix)}-[0-9]{{3}})\s*[:：]\s*\S.*",
                line, re.I)
            if heading is None:
                errors.append(
                    f"{label}: every Findings heading must match "
                    f"D4-{expected_prefix}-NNN: title")
                continue
            headings.append((index, heading))
        for heading_index, (index, heading) in enumerate(headings):
            finding_id = heading.group(1)
            end = headings[heading_index + 1][0] if heading_index + 1 < len(headings) \
                else len(finding_lines)
            block = "\n".join(finding_lines[index + 1:end])
            bullet, duplicate = parse_named_bullets(block)
            if finding_id in finding_ids or bullet.get("Finding ID") != finding_id:
                errors.append(f"{label}: raw D4 finding IDs must be unique and self-consistent")
            finding_ids.add(finding_id)
            for required_key in (
                    "Severity", "Confidence", "State tag", "Canonical evidence",
                    "Impact", "Required correction direction", "Owning D0-D3 document/role",
                    "Status", "Resolution evidence"):
                if required_key in duplicate or required_key not in bullet \
                        or unresolved_cell(bullet.get(required_key, "")):
                    errors.append(
                        f"{label}: finding {finding_id} field {required_key!r} is missing/placeholder")
            severity = bullet.get("Severity", "").casefold()
            status = bullet.get("Status", "").casefold()
            if severity not in {"critical", "major", "minor", "observation"}:
                errors.append(f"{label}: finding {finding_id} Severity is invalid")
            else:
                derived[severity] += 1
            if status not in {"open", "resolved", "accepted observation"}:
                errors.append(f"{label}: finding {finding_id} Status is invalid")
            if severity in {"critical", "major"} and status == "open":
                open_high += 1
        if open_high:
            errors.append(f"{label}: raw Findings contain {open_high} open Critical/Major item(s)")
        if not finding_ids and findings.strip().casefold().strip(".` ") not in {
                "none", "no findings", "no findings found"}:
            errors.append(f"{label}: empty raw Findings must explicitly say no findings")

    summary = markdown_section(text, "Summary", 2)
    if summary is None:
        errors.append(f"{label}: raw D4 Summary section must be unique")
    else:
        summary_fields, summary_dupes = parse_named_bullets(summary)
        for name in ("Critical", "Major", "Minor", "Observation"):
            raw = summary_fields.get(name)
            if name in summary_dupes or raw is None or re.fullmatch(r"`?[0-9]+`?", raw) is None:
                errors.append(f"{label}: raw D4 Summary {name} must be one integer")
                continue
            actual = int(raw.strip("`"))
            if actual != derived[name.casefold()]:
                errors.append(
                    f"{label}: raw D4 Summary {name} does not equal parsed findings")
            if name == "Critical" and actual != record.get("criticalCount"):
                errors.append(f"{label}: raw D4 Critical count does not match W0 metadata")
            if name == "Major" and actual != record.get("majorCount"):
                errors.append(f"{label}: raw D4 Major count does not match W0 metadata")
        verdict = summary_fields.get("Verdict rule", "")
        if "Verdict rule" in summary_dupes or re.fullmatch(
                r"Critical 0 and Major 0 only\s*(?:->|→)\s*pass", verdict, re.I) is None:
            errors.append(
                f"{label}: raw D4 summary must uniquely derive Critical 0 / Major 0 / pass")

    coverage = markdown_section(text, "Coverage", 2)
    if coverage is None:
        errors.append(f"{label}: raw D4 Coverage section must be unique")
    else:
        coverage_fields, coverage_dupes = parse_named_bullets(coverage)
        coverage_required = {
            "Canonical allowlist received", "Sanitized evidence manifest received",
            "GDD Gate 1 chain checked",
            "Initial-D4 inventory source", "post-P0 inventory source",
            "post-P0 candidate state", "Remaining proposal/open/assumption IDs found",
            "Inventory coverage verdict", "post-P0 closure evidence checked",
            "Files inspected", "Required files not received",
        }
        for key in coverage_required:
            value = coverage_fields.get(key, "")
            if key in coverage_dupes or key not in coverage_fields or not value.strip() \
                    or re.search(r"\{[^}]+\}|TODO|UNRESOLVED", value, re.I):
                errors.append(f"{label}: Coverage field {key!r} is missing/placeholder")
        if coverage_fields.get("Inventory coverage verdict", "").casefold() != "complete":
            errors.append(f"{label}: Inventory coverage verdict must be complete")
        if coverage_fields.get("Required files not received", "").casefold() != "none":
            errors.append(f"{label}: Required files not received must be none")
        if isinstance(candidate_ref.get("id"), str) \
                and candidate_ref["id"].startswith("P0-CAND-") \
                and coverage_fields.get(
                    "Remaining proposal/open/assumption IDs found", "").casefold() != "none":
            errors.append(f"{label}: post-P0 D4 remaining proposal/open/assumption IDs must be none")

    commands_section = markdown_section(text, "Commands run and outputs", 2)
    command_rows = (section_table_rows(
        commands_section, "Argv (exact minified JSON array; shell=false)", 5)
                    if commands_section is not None else None)
    expected_commands = attestation.get("commands") if attestation is not None else None
    if command_rows is None or not isinstance(expected_commands, list):
        errors.append(f"{label}: raw D4 Commands table must bind the attestation")
    else:
        expected_rows = [[
            json.dumps(item.get("argv"), ensure_ascii=False, separators=(",", ":")),
            str(item.get("cwd")), str(item.get("exitCode")),
            str(item.get("outputPath")), str(item.get("outputSha256")),
        ] for item in expected_commands if isinstance(item, dict)]
        if command_rows != expected_rows:
            errors.append(f"{label}: raw D4 Commands table differs from the attestation")

    execution = markdown_section(text, "Execution facts in this worker response", 2)
    if execution is None or attestation is None:
        errors.append(f"{label}: raw D4 execution facts must bind a machine attestation")
    else:
        execution_fields, execution_dupes = parse_named_bullets(execution)
        request = attestation.get("requestArtifact")
        policy = attestation.get("auditPolicy")
        runtime_ref = attestation.get("runtimeAllowlist")
        prompt = attestation.get("fullPromptArtifact")
        inspected = attestation.get("inspectedInputs")
        expected_execution = {
            "lane run / execution / session IDs": (
                f"{attestation.get('laneRunId')} / {attestation.get('executionId')} / "
                f"{attestation.get('sessionId')}"),
            "worker / class": f"{attestation.get('worker')} / A",
            "requested and resolved model/version": (
                f"{attestation.get('requestedModel')} / {attestation.get('resolvedModel')}"),
            "tool version": str(attestation.get("toolVersion")),
            "context mode": "clean",
            "filesystem access": D4_FILESYSTEM_ACCESS,
            "provider policy ID / SHA-256": (
                f"{provider_policy.get('id')} / {provider_policy.get('sha256')}"
                if isinstance(provider_policy, dict) else ""),
            "capsule path / SHA-256": (
                f"{capsule_ref.get('path')} / {capsule_ref.get('sha256')}"
                if isinstance(capsule_ref, dict) else ""),
            "installed-policy manifest path / SHA-256 / compiledPolicySha256": (
                f"{policy.get('path')} / {policy.get('sha256')} / "
                f"{policy.get('compiledPolicySha256')}"
                if isinstance(policy, dict) else ""),
            "runtime allowlist path / SHA-256 / digestSha256": (
                f"{runtime_ref.get('path')} / {runtime_ref.get('sha256')} / "
                f"{runtime_ref.get('digestSha256')}"
                if isinstance(runtime_ref, dict) else ""),
            "request artifact path / SHA-256 / requestCore SHA-256": (
                f"{request.get('path')} / {request.get('sha256')} / "
                f"{attestation.get('requestCoreSha256')}"
                if isinstance(request, dict) else ""),
            "exact orchestrator-submitted payload path / SHA-256": (
                f"{prompt.get('path')} / {prompt.get('sha256')}"
                if isinstance(prompt, dict) else ""),
            "raw response output path": str(record.get("path")),
            "started at / completed at": (
                f"{attestation.get('startedAt')} / {attestation.get('completedAt')}"),
        }
        for key, expected in expected_execution.items():
            if key in execution_dupes or execution_fields.get(key) != expected:
                errors.append(f"{label}: execution fact {key!r} differs from attestation")
        inspected_value = execution_fields.get("inspected input paths / SHA-256", "")
        for item in inspected if isinstance(inspected, list) else []:
            if isinstance(item, dict) and (
                    str(item.get("path")) not in inspected_value
                    or str(item.get("sha256")) not in inspected_value):
                errors.append(f"{label}: execution inspected-input facts are incomplete")
        sandbox = execution_fields.get("read-only sandbox / network", "")
        if "read-only" not in sandbox.casefold():
            errors.append(f"{label}: execution sandbox fact must assert read-only")
        finish = execution_fields.get("finish reason / exit code", "")
        if str(attestation.get("finishReason")) not in finish \
                or re.search(r"/\s*0\s*$", finish) is None:
            errors.append(f"{label}: execution finish facts differ from attestation")


def parse_named_bullets(text: str) -> tuple[dict[str, str], set[str]]:
    fields: dict[str, str] = {}
    duplicates: set[str] = set()
    for line in text.splitlines():
        match = re.match(r"^\s*[-*]\s*([^:：]+?)\s*[:：]\s*(.*?)\s*$", line)
        if match is None:
            continue
        key, value = match.group(1).strip(), match.group(2).strip().strip("`")
        if key in fields:
            duplicates.add(key)
        else:
            fields[key] = value
    return fields, duplicates


def markdown_section(text: str, heading_text: str, level: int) -> str | None:
    lines = text.splitlines()
    start = None
    for index, line in enumerate(lines):
        match = re.match(r"^(#{1,6})\s+(.*?)\s*$", line)
        if match and len(match.group(1)) == level \
                and match.group(2).strip().casefold() == heading_text.casefold():
            if start is not None:
                return None
            start = index + 1
    if start is None:
        return None
    end = len(lines)
    for index in range(start, len(lines)):
        match = re.match(r"^(#{1,6})\s+", lines[index])
        if match and len(match.group(1)) <= level:
            end = index
            break
    return "\n".join(lines[start:end])


def section_table_rows(section: str, first_header: str, columns: int) -> list[list[str]] | None:
    rows: list[list[str]] = []
    in_table = False
    for line in section.splitlines():
        cells = gen_index.split_row(line)
        if cells is None:
            if in_table:
                break
            continue
        if len(cells) != columns:
            if in_table:
                return None
            continue
        if cells[0].strip() == first_header:
            if in_table:
                return None
            in_table = True
            continue
        if not in_table:
            continue
        if set("".join(cells)) <= set("-: "):
            continue
        rows.append([cell.strip().strip("`") for cell in cells])
    return rows if in_table else None


def unresolved_cell(value: str) -> bool:
    clean = value.strip().strip("`").strip()
    return (not clean or clean.casefold() in {"—", "-", "none", "null", "n/a", "tbd"}
            or re.search(r"\{[^}]+\}|TODO|UNRESOLVED", clean, re.I) is not None)


def decision_definition_count(decisions: str, qualified_ref: str) -> int:
    count = 0
    heading = re.compile(
        r"^#{1,6}\s+`?" + re.escape(qualified_ref) + r"`?\s*(?::|：|—|-|$)", re.I)
    for line in decisions.splitlines():
        if heading.match(line.strip()):
            count += 1
            continue
        cells = gen_index.split_row(line)
        if cells and cells[0].strip().strip("`") == qualified_ref:
            count += 1
    return count


PATH_TOKEN_RE = re.compile(
    r"(?<![A-Za-z0-9_.-])(?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+\."
    r"(?:md|json|csv|txt|ya?ml)(?![A-Za-z0-9_.-])", re.I)
P0_PROCEDURAL_PATHS = {"PROGRESS.md", "DECISIONS.md", "CHANGELOG.md"}


def canonical_paths_in_cell(value: str) -> list[str]:
    return [match.group(0).replace("\\", "/") for match in PATH_TOKEN_RE.finditer(value)]


def validate_p0_closure_transition(
        root: Path, b0_content: dict[str, bytes], b1_content: dict[str, bytes],
        errors: list[str]) -> dict[str, Any] | None:
    b0_bytes, b1_bytes = b0_content.get("PROGRESS.md"), b1_content.get("PROGRESS.md")
    if b0_bytes is None or b1_bytes is None:
        errors.append("B0 and B1 file sets must both contain historical PROGRESS.md")
        return None
    decisions_bytes = b1_content.get("DECISIONS.md")
    if decisions_bytes is None:
        errors.append("B1 file set must contain historical DECISIONS.md")
        return None
    try:
        b0_text, b1_text = b0_bytes.decode("utf-8"), b1_bytes.decode("utf-8")
        decisions_text = decisions_bytes.decode("utf-8")
    except UnicodeDecodeError:
        errors.append("B0/B1 historical PROGRESS.md must be strict UTF-8")
        return None
    b0_section = markdown_section(b0_text, "Proposed P0 closure inventory", 2)
    b1_section = markdown_section(b1_text, "Proposed P0 closure inventory", 2)
    completed_section = markdown_section(b1_text, "P0 closure records", 3)
    if b0_section is None or b1_section is None or completed_section is None:
        errors.append("B0/B1 PROGRESS.md closure inventory sections must each be unique")
        return None
    inventory_ids = re.findall(
        r"(?im)^\s*[-*]\s*Inventory ID\s*[:：]\s*`?([^`\s]+)`?\s*$", b0_section)
    if len(inventory_ids) != 1 or unresolved_cell(inventory_ids[0]):
        errors.append("B0 PROGRESS closure Inventory ID must be unique and non-placeholder")
        return None
    inventory_id = inventory_ids[0]
    b0_rows = section_table_rows(b0_section, "Source item ID", 7)
    b1_open_rows = section_table_rows(b1_section, "Source item ID", 7)
    completed_rows = section_table_rows(completed_section, "Source item ID", 6)
    if b0_rows is None or b1_open_rows is None or completed_rows is None:
        errors.append("B0/B1 PROGRESS closure tables have an invalid shape")
        return None
    if b1_open_rows:
        errors.append("B1 Proposed P0 closure inventory must have zero data rows")
    source_ids: list[str] = []
    affected_by_source: dict[str, set[str]] = {}
    for index, row in enumerate(b0_rows):
        if any(unresolved_cell(cell) for cell in row):
            errors.append(f"B0 closure inventory row {index + 1} contains a placeholder")
        source_id = row[0]
        source_ids.append(source_id)
        affected = canonical_paths_in_cell(row[6])
        if not affected or len(affected) != len(set(affected)):
            errors.append(
                f"B0 closure inventory {source_id}: affected canonical paths must be nonempty/unique")
        unknown = sorted(set(affected) - set(b0_content))
        if unknown:
            errors.append(
                f"B0 closure inventory {source_id}: affected paths are absent from B0: {unknown}")
        affected_by_source[source_id] = set(affected)
    if len(source_ids) != len(set(source_ids)):
        errors.append("B0 closure inventory Source item IDs must be unique")
    b0_progress_hash = hashlib.sha256(b0_bytes).hexdigest()
    used_evidence: set[tuple[str, str]] = set()
    for source_id in source_ids:
        matches = [row for row in completed_rows if row[0] == source_id]
        if len(matches) != 1:
            errors.append(
                f"B1 P0 closure records must resolve B0 Source item ID {source_id!r} exactly once")
            continue
        row = matches[0]
        if re.fullmatch(
                re.escape(inventory_id) + r"\s*/\s*" + re.escape(b0_progress_hash),
                row[1]) is None:
            errors.append(
                f"B1 closure {source_id}: inventory ID/B0 PROGRESS sha256 mismatch")
        decision_ref = row[2]
        if unresolved_cell(decision_ref) or re.fullmatch(
                r"\S(?:.*\S)?\s+D-[A-Z0-9][A-Z0-9._-]*", decision_ref, re.I) is None:
            errors.append(
                f"B1 closure {source_id}: Decision ID must be a fully-qualified reference")
        else:
            definitions = decision_definition_count(decisions_text, decision_ref)
            if definitions != 1:
                errors.append(
                    f"B1 closure {source_id}: Decision reference {decision_ref!r} "
                    f"must resolve exactly once in historical B1 DECISIONS.md")
        evidence_match = re.fullmatch(
            r"\s*((?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+\.[A-Za-z0-9_.-]+)"
            r"\s*/\s*([0-9a-f]{64})\s*/\s*pass\s*", row[3], re.I)
        if evidence_match is None:
            errors.append(
                f"B1 closure {source_id}: actual closure evidence must be exact "
                "project-relative path / sha256 / pass")
        else:
            evidence_rel = evidence_match.group(1).replace("\\", "/")
            evidence_hash = evidence_match.group(2).lower()
            evidence_key = (identity_key(evidence_rel), evidence_hash)
            if evidence_key in used_evidence:
                errors.append(f"B1 closure {source_id}: closure evidence cannot be reused")
            used_evidence.add(evidence_key)
            evidence_path = resolve_path(
                root, evidence_rel, errors, f"B1 closure {source_id} evidence")
            if evidence_path is not None:
                if not evidence_path.is_file():
                    errors.append(f"B1 closure {source_id}: closure evidence file is missing")
                elif sha256(evidence_path) != evidence_hash:
                    errors.append(f"B1 closure {source_id}: closure evidence sha256 mismatch")
        affected = canonical_paths_in_cell(row[4])
        expected_affected = affected_by_source.get(source_id, set())
        if set(affected) != expected_affected or len(affected) != len(set(affected)):
            errors.append(
                f"B1 closure {source_id}: affected canonical paths must exactly equal B0 inventory")
        if unresolved_cell(row[4]) or any(
                rel not in b1_content
                or row[4].lower().count(hashlib.sha256(b1_content[rel]).hexdigest()) != 1
                for rel in expected_affected):
            errors.append(f"B1 closure {source_id}: affected-doc post-change sha256 is missing")
        if not timezone_datetime(row[5]):
            errors.append(f"B1 closure {source_id}: Completed at requires a timezone timestamp")
    affected_union = set().union(*affected_by_source.values()) if affected_by_source else set()
    all_paths = set(b0_content) | set(b1_content)
    changed = {rel for rel in all_paths if b0_content.get(rel) != b1_content.get(rel)}
    return {
        "inventoryId": inventory_id,
        "progressSha256": b0_progress_hash,
        "sourceIds": source_ids,
        "affectedBySource": {
            source_id: sorted(paths)
            for source_id, paths in sorted(affected_by_source.items())},
        "affectedPaths": sorted(affected_union),
        "changedPaths": sorted(changed),
    }


def normalize_p0_management_wp(
        old: str, new: str, wp_id: str, errors: list[str],
        expected_new: dict[str, str] | None = None) -> tuple[str, str]:
    allowed_old = {"proposed", "approved", "in progress"}
    fields = ("Status", "Authorized by", "Authorization baseline", "Authorization evidence")
    expected_new = expected_new or {"Status": "Verified"}

    def normalize(text: str, is_new: bool) -> str:
        lines = text.splitlines(keepends=True)
        heading_hits = 0
        field_hits = {field: 0 for field in fields}
        index_hits = 0
        in_target = False
        output: list[str] = []
        for line in lines:
            body, ending = _line_parts(line)
            heading = re.match(r"^(#{2,6})\s+(.*?)\s*$", body)
            if heading:
                in_target = re.search(
                    r"(?<![A-Za-z0-9._-])" + re.escape(wp_id) +
                    r"(?![A-Za-z0-9._-])", heading.group(2)) is not None
                if in_target:
                    heading_hits += 1
                output.append(line)
                continue
            if in_target:
                matched = False
                for field in fields:
                    match = re.match(
                        r"^(\s*[-*]\s*" + re.escape(field) + r"\s*[:：]\s*)(.*?)\s*$",
                        body, re.I)
                    if match is None:
                        continue
                    actual = match.group(2).strip().strip("`").replace("\\", "/")
                    if is_new:
                        if actual != expected_new.get(field):
                            errors.append(
                                f"P0 management WP {wp_id} {field} has an invalid final value")
                    elif field == "Status":
                        if actual.casefold() not in allowed_old:
                            errors.append(
                                f"P0 management WP {wp_id} detail Status has an invalid old value")
                    elif not unresolved_cell(actual):
                        errors.append(
                            f"P0 management WP {wp_id} old {field} must be unset")
                    field_hits[field] += 1
                    token = field.upper().replace(" ", "-")
                    output.append(match.group(1) + f"<P0-MANAGEMENT-{token}>" + ending)
                    matched = True
                    break
                if matched:
                    continue
            cells = gen_index.split_row(body)
            if cells and cells[0].strip().strip("`") == wp_id:
                status_positions = [
                    index for index, cell in enumerate(cells)
                    if cell.strip().strip("`").casefold() in allowed_old | {"verified"}
                ]
                if len(status_positions) != 1:
                    errors.append(f"P0 management WP {wp_id} index row Status is ambiguous")
                    output.append(line)
                    continue
                actual = cells[status_positions[0]].strip().strip("`").casefold()
                if (is_new and actual != "verified") or (not is_new and actual not in allowed_old):
                    errors.append(
                        f"P0 management WP {wp_id} index Status has an invalid transition value")
                pattern = re.compile(
                    r"(?i)(?<![A-Za-z])(?:Proposed|Approved|In progress|Verified)(?![A-Za-z])")
                replaced, count = pattern.subn("<P0-MANAGEMENT-STATUS>", body)
                if count != 1:
                    errors.append(f"P0 management WP {wp_id} index row is ambiguous")
                index_hits += 1
                output.append(replaced + ending)
                continue
            output.append(line)
        if heading_hits != 1 or index_hits != 1 or any(
                count != 1 for count in field_hits.values()):
            errors.append(
                f"P0 management WP {wp_id} must have one detail/four fields and one index mirror")
        return "".join(output)

    return normalize(old, False), normalize(new, True)


def validate_p0_management_transition(
        b0_content: dict[str, bytes], b1_content: dict[str, bytes], scope: Any,
        inventory: dict[str, Any] | None, errors: list[str], *,
        approval_id: str = "", candidate_id: str = "",
        capture_path: str = "") -> None:
    management = scope.get("p0ManagementWp") if isinstance(scope, dict) else None
    management_path: str | None = None
    if not isinstance(management, dict) or set(management) != {"id", "path"}:
        errors.append("P0 start scope.p0ManagementWp has unknown/missing fields")
    else:
        wp_id, path = management.get("id"), management.get("path")
        if not isinstance(wp_id, str) or re.fullmatch(
                r"WP-[A-Z0-9]+-[A-Z0-9][A-Z0-9._-]*", wp_id) is None:
            errors.append("P0 start scope.p0ManagementWp.id is invalid")
        if not isinstance(path, str) or re.fullmatch(
                r"docs/[A-Za-z0-9._-]+_work_packages\.md", path) is None:
            errors.append("P0 start scope.p0ManagementWp.path is invalid")
        elif path not in b0_content or path not in b1_content:
            errors.append("P0 management WP path must exist in both B0 and B1")
        elif isinstance(wp_id, str):
            management_path = path
            try:
                old, new = b0_content[path].decode("utf-8"), b1_content[path].decode("utf-8")
            except UnicodeDecodeError:
                errors.append("P0 management WP file must be strict UTF-8")
            else:
                norm_old, norm_new = normalize_p0_management_wp(
                    old, new, wp_id, errors, {
                        "Status": "Verified", "Authorized by": approval_id,
                        "Authorization baseline": candidate_id,
                        "Authorization evidence": capture_path,
                    })
                if norm_old != norm_new:
                    errors.append(
                        "P0 management WP changed bytes outside its exact Verified transition")
    if inventory is not None:
        unexpected = set(inventory["changedPaths"]) - set(inventory["affectedPaths"]) \
            - P0_PROCEDURAL_PATHS
        if management_path is not None:
            unexpected.discard(management_path)
        if unexpected:
            errors.append(
                "B0 -> B1 changed product-content paths outside the closure inventory: "
                f"{sorted(unexpected)}")


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
        old = strict_json_module.loads(old_bytes.decode("utf-8-sig"))
    except (UnicodeDecodeError, ValueError) as exc:
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
        gate1_gdd_preserved = (rel.endswith("_gdd.md")
                               and before_status == after_status == "approved")
        if rel in formal and not gate1_gdd_preserved and (
                before_status not in {"draft", "review"} or after_status != "approved"):
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


def parsed_timestamp(value: Any) -> Timestamp100ns | None:
    return _parse_rfc3339_100ns(value)


def baseline_approval_target(ref: Any, baseline: dict[str, Any]) -> dict[str, Any]:
    revision = baseline.get("revision")
    return {
        "id": ref.get("id") if isinstance(ref, dict) else None,
        "path": ref.get("path") if isinstance(ref, dict) else None,
        "sha256": ref.get("sha256") if isinstance(ref, dict) else None,
        "fileSetSha256": ref.get("fileSetSha256") if isinstance(ref, dict) else None,
        "revision": revision.get("value") if isinstance(revision, dict) else None,
    }


def canonical_challenge_digest(
        gate_type: str, target_key: str, target: Any, scope: Any) -> str:
    kind = ({"targetArtifact": "artifact", "targetBaseline": "baseline",
             "plannedCandidate": "planned-candidate"}.get(target_key))
    typed_target = dict({"kind": kind}, **target) if isinstance(target, dict) else target
    payload = {"gateType": gate_type, "target": typed_target, "scope": scope}
    encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True,
                         separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


REQUIRED_SPEC_TEMPLATES = {
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
    "external_services_secrets": "external_services_secrets.md",
    "rights_provenance": "rights_provenance_ledger.md",
}


def derive_required_specs_projection(intake: dict[str, Any]) -> dict[str, Any]:
    technical = intake.get("technical") if isinstance(intake.get("technical"), dict) else {}
    product = intake.get("product") if isinstance(intake.get("product"), dict) else {}
    monetization = (product.get("monetization")
                    if isinstance(product.get("monetization"), dict) else {})
    triggers: dict[str, str] = {}
    if technical.get("existing_repository") is True:
        triggers["repository_audit"] = "existing repository is true"
    high_keys = (
        "vehicle_or_custom_physics", "high_npc_or_fx_load", "free_text_or_ugc",
        "multi_place", "high_frequency_projectiles_or_fast_pvp",
    )
    high_risk = any(technical.get(key) is True for key in high_keys)
    if high_risk:
        triggers["feasibility_report"] = (
            "one or more measurable high-risk technical flags")
    if any(technical.get(key) is True for key in (
            "multiplayer", "pvp", "commerce", "persistent_data")):
        triggers["network_security"] = (
            "multiplayer/PvP/economy/persistence requires trust boundaries")
    if technical.get("persistent_data") is True:
        triggers["persistence_migration"] = "persistent data enabled"
    commerce = technical.get("commerce") is True or monetization.get("enabled") is True
    if commerce:
        triggers["commerce_policy"] = "commerce or monetization enabled"
    if monetization.get("paid_random_items") is True:
        triggers["paid_random_items"] = "paid random items enabled"
    if bool(technical.get("analytics", True)):
        triggers["analytics_observability"] = "KPI/analytics enabled"
    if bool(technical.get("mobile", True)) or technical.get("high_npc_or_fx_load") is True \
            or technical.get("vehicle_or_custom_physics") is True:
        triggers["performance_budget"] = (
            "mobile/high load/custom physics requires explicit budgets")
    triggers["asset_content_pipeline"] = (
        "all Roblox games require an asset provenance and budget pipeline")
    if any(technical.get(key) is True for key in (
            "multi_place", "reserved_servers", "teleport")):
        triggers["multi_place_matchmaking"] = (
            "multi-place/reserved server/teleport enabled")
    if technical.get("vehicle_or_custom_physics") is True:
        triggers["physics_control"] = "vehicle or custom physics/control enabled"
    if technical.get("free_text_or_ugc") is True:
        triggers["ugc_moderation"] = (
            "free text, drawing, UGC, or generative content enabled")
    locales = technical.get("priority_locales")
    if technical.get("localization") is True or isinstance(locales, list) and len(locales) > 1:
        triggers["localization_accessibility"] = "multiple locales/global launch"
    if technical.get("liveops") is True:
        triggers["liveops_content"] = "seasons/events/live operations enabled"
    if technical.get("external_services") is True:
        triggers["external_services_secrets"] = "external services or secrets enabled"
    if technical.get("real_world_ip_or_history") is True or bool(product.get("ip_risks")):
        triggers["rights_provenance"] = (
            "real-world IP/history or recorded IP risks")
    subchecks: list[dict[str, str]] = []
    for key in high_keys:
        if technical.get(key) is True:
            source = f"technical.{key}"
            subchecks.append({
                "id": source, "source": source,
                "sourceValueSha256": canonical_json_sha256(True),
            })
    subchecks.sort(key=lambda value: value["id"])
    measurement = {
        "kind": "d1.5-combined-suite-v1",
        "experimentId": "feasibility_report-combined-v1",
        "cardinality": "exactly-one",
        "coverage": "all-triggered-high-risk-subchecks",
        "requiredSubchecks": subchecks,
        "requiredSubchecksSha256": canonical_json_sha256(subchecks),
    }
    project = intake.get("project") if isinstance(intake.get("project"), dict) else {}
    return {
        "schemaVersion": "1.0.0", "project": project.get("name"),
        "prefix": project.get("prefix"),
        "required_specs": [{
            "id": key, "template": REQUIRED_SPEC_TEMPLATES[key], "reason": reason,
            "measurementContract": measurement if key == "feasibility_report" else None,
        } for key, reason in triggers.items()],
    }


def validate_human_capture(
        root: Path, package_ref: Any, expected_gate: str, target_key: str,
        expected_target: Any, expected_scope: Any, errors: list[str],
        label: str) -> dict[str, Any] | None:
    if not isinstance(package_ref, dict) or set(package_ref) != {"id", "path", "sha256"}:
        errors.append(f"{label}: W0 capture reference has unknown/missing fields")
        return None
    loaded = verify_ref(
        root, {"path": package_ref.get("path"), "sha256": package_ref.get("sha256")},
        errors, label)
    if loaded is None:
        return None
    capture = loaded[1]
    common = {
        "schemaVersion", "id", "gateType", "approvalMethod", "approved",
        "approver", "occurredAt", "sourceInteractionRef", "scope",
        "challengeArtifact", "statementArtifact", "statementSha256",
    }
    if set(capture) != common | {target_key}:
        errors.append(f"{label}: capture has unknown/missing fields")
    if capture.get("schemaVersion") != "1.0.0":
        errors.append(f"{label}.schemaVersion must be 1.0.0")
    if capture.get("id") != package_ref.get("id") or not isinstance(
            capture.get("id"), str) or re.fullmatch(
                r"HAC-[A-Z0-9][A-Z0-9._-]*", str(capture.get("id"))) is None:
        errors.append(f"{label}.id must match its W0 HAC-* reference")
    if capture.get("gateType") != expected_gate:
        errors.append(f"{label}.gateType must be {expected_gate}")
    if capture.get("approvalMethod") != "human-direct" or capture.get("approved") is not True:
        errors.append(f"{label}: only an approved human-direct capture is valid")
    if not isinstance(capture.get("approver"), str) or not capture["approver"].strip():
        errors.append(f"{label}.approver must be non-empty")
    if not timezone_datetime(capture.get("occurredAt")):
        errors.append(f"{label}.occurredAt must be a timezone timestamp")
    if capture.get(target_key) != expected_target:
        errors.append(f"{label}.{target_key} must exactly bind the gate target")
    if capture.get("scope") != expected_scope:
        errors.append(f"{label}.scope must exactly bind the closed gate scope")

    challenge_loaded = exact_artifact_ref(
        root, capture.get("challengeArtifact"), errors, f"{label}.challengeArtifact")
    challenge: dict[str, Any] = challenge_loaded[1] if challenge_loaded else {}
    expected_digest = canonical_challenge_digest(
        expected_gate, target_key, expected_target, expected_scope)
    expected_response = f"APPROVE {challenge.get('id')} {expected_digest}"
    if challenge:
        if set(challenge) != {
                "schemaVersion", "id", "gateType", "issuedAt",
                "targetScopeSha256", "canonicalResponse", "presentationArtifact"}:
            errors.append(f"{label}.challengeArtifact has unknown/missing fields")
        if challenge.get("schemaVersion") != "1.0.0" or not isinstance(
                challenge.get("id"), str) or re.fullmatch(
                    r"HCH-[A-Z0-9][A-Z0-9._-]*", str(challenge.get("id"))) is None:
            errors.append(f"{label}.challengeArtifact identity/schemaVersion is invalid")
        if challenge.get("gateType") != expected_gate:
            errors.append(f"{label}.challengeArtifact.gateType mismatch")
        if not timezone_datetime(challenge.get("issuedAt")):
            errors.append(f"{label}.challengeArtifact.issuedAt must be a timezone timestamp")
        if challenge.get("targetScopeSha256") != expected_digest:
            errors.append(f"{label}.challengeArtifact target/scope digest mismatch")
        if challenge.get("canonicalResponse") != expected_response:
            errors.append(f"{label}.challengeArtifact canonicalResponse mismatch")

    kind = ({"targetArtifact": "artifact", "targetBaseline": "baseline",
             "plannedCandidate": "planned-candidate"}.get(target_key))
    typed_target = dict({"kind": kind}, **expected_target) \
        if isinstance(expected_target, dict) else expected_target
    expected_presentation = {
        "schemaVersion": "1.0.0", "challengeId": challenge.get("id"),
        "gateType": expected_gate, "issuedAt": challenge.get("issuedAt"),
        "target": typed_target, "scope": expected_scope,
        "targetScopeSha256": expected_digest, "canonicalResponse": expected_response,
    }
    presentation_ref = challenge.get("presentationArtifact")
    presentation_path = verify_artifact_file_ref(
        root, presentation_ref, errors, f"{label}.challenge.presentationArtifact")
    presentation_bytes = canonical_json_bytes(expected_presentation)
    if presentation_path is not None and presentation_path.read_bytes() != presentation_bytes:
        errors.append(f"{label}: approval presentation bytes differ from target/scope")

    statement_ref = capture.get("statementArtifact")
    statement_path = verify_artifact_file_ref(
        root, statement_ref, errors, f"{label}.statementArtifact")
    statement = statement_path.read_bytes() if statement_path is not None else None
    if not isinstance(statement_ref, dict) or capture.get("statementSha256") != statement_ref.get(
            "sha256"):
        errors.append(f"{label}.statementSha256 must equal statementArtifact.sha256")
    canonical_bytes = expected_response.encode("utf-8")
    if statement is not None and statement != canonical_bytes:
        errors.append(
            f"{label}.statementArtifact must contain only the exact canonical response bytes")

    source = capture.get("sourceInteractionRef")
    if not isinstance(source, dict) or set(source) != {
            "channel", "interactionId", "presentationMessageId", "messageId",
            "transcriptArtifact"}:
        errors.append(f"{label}.sourceInteractionRef has unknown/missing fields")
        source = {}
    for key in ("channel", "interactionId", "presentationMessageId", "messageId"):
        if not isinstance(source.get(key), str) or not source[key].strip():
            errors.append(f"{label}.sourceInteractionRef.{key} must be non-empty")
    transcript_loaded = exact_artifact_ref(
        root, source.get("transcriptArtifact"), errors,
        f"{label}.sourceInteractionRef.transcriptArtifact")
    transcript: dict[str, Any] = transcript_loaded[1] if transcript_loaded else {}
    selected: list[dict[str, Any]] = []
    presented: list[dict[str, Any]] = []
    if transcript:
        if set(transcript) != {
                "schemaVersion", "id", "channel", "interactionId", "capturedAt", "messages"}:
            errors.append(f"{label}.transcript has unknown/missing fields")
        if transcript.get("schemaVersion") != "1.0.0" or not isinstance(
                transcript.get("id"), str) or re.fullmatch(
                    r"HIT-[A-Z0-9][A-Z0-9._-]*", str(transcript.get("id"))) is None:
            errors.append(f"{label}.transcript identity/schemaVersion is invalid")
        if transcript.get("channel") != source.get("channel") \
                or transcript.get("interactionId") != source.get("interactionId"):
            errors.append(f"{label}.transcript channel/interactionId mismatch")
        if not timezone_datetime(transcript.get("capturedAt")):
            errors.append(f"{label}.transcript.capturedAt must be a timezone timestamp")
        messages = transcript.get("messages")
        if not isinstance(messages, list) or not messages:
            errors.append(f"{label}.transcript.messages must be non-empty")
            messages = []
        message_ids: list[Any] = []
        for index, message in enumerate(messages):
            row_label = f"{label}.transcript.messages[{index}]"
            if not isinstance(message, dict) or set(message) != {
                    "messageId", "role", "actorId", "occurredAt", "content"}:
                errors.append(f"{row_label} has unknown/missing fields")
                continue
            message_ids.append(message.get("messageId"))
            if message.get("role") not in {"human", "assistant", "system", "tool"}:
                errors.append(f"{row_label}.role is invalid")
            if not timezone_datetime(message.get("occurredAt")):
                errors.append(f"{row_label}.occurredAt must be a timezone timestamp")
            if not isinstance(message.get("content"), str) or not message["content"]:
                errors.append(f"{row_label}.content must be non-empty")
            if message.get("messageId") == source.get("messageId"):
                selected.append(message)
            if message.get("messageId") == source.get("presentationMessageId"):
                presented.append(message)
        if len(message_ids) != len({identity_key(value) for value in message_ids}):
            errors.append(f"{label}.transcript message IDs must be unique")
    if len(selected) != 1 or selected[0].get("role") != "human":
        errors.append(f"{label}: source message must resolve to exactly one human record")
    else:
        message = selected[0]
        if message.get("actorId") != capture.get("approver"):
            errors.append(f"{label}: source human actorId must equal capture.approver")
        if message.get("occurredAt") != capture.get("occurredAt"):
            errors.append(f"{label}: source message occurredAt must equal capture.occurredAt")
        if message.get("content") != expected_response:
            errors.append(f"{label}: selected human message must equal canonicalResponse")
        if statement is not None and statement != str(message.get("content")).encode("utf-8"):
            errors.append(f"{label}: statement bytes must exactly equal selected message UTF-8")
        issued = parsed_timestamp(challenge.get("issuedAt"))
        occurred = parsed_timestamp(message.get("occurredAt"))
        captured = parsed_timestamp(transcript.get("capturedAt"))
        if issued is None or occurred is None or captured is None \
                or not (issued <= occurred <= captured):
            errors.append(
                f"{label}: challenge.issuedAt <= occurredAt <= transcript.capturedAt is required")
    if source.get("presentationMessageId") == source.get("messageId") \
            or len(presented) != 1 or presented[0].get("role") not in {"assistant", "system"}:
        errors.append(f"{label}: presentation must resolve to one prior assistant/system message")
    else:
        presentation_message = presented[0]
        if presentation_message.get("content") != presentation_bytes.decode("utf-8"):
            errors.append(f"{label}: presented message does not equal canonical presentation bytes")
        presented_at = parsed_timestamp(presentation_message.get("occurredAt"))
        response_at = parsed_timestamp(selected[0].get("occurredAt")) if len(selected) == 1 else None
        issued_at = parsed_timestamp(challenge.get("issuedAt"))
        if issued_at is None or presented_at is None or response_at is None \
                or not (issued_at <= presented_at < response_at):
            errors.append(
                f"{label}: challenge issue <= presentation < human response is required")
    selected_message = selected[0] if len(selected) == 1 else {}
    presentation_message = presented[0] if len(presented) == 1 else {}
    claims = {
        "kind": "human-approval-v1",
        "captureId": capture.get("id"),
        "gateType": expected_gate,
        "approver": capture.get("approver"),
        "challengeId": challenge.get("id"),
        "challengeIssuedAt": challenge.get("issuedAt"),
        "targetScopeSha256": expected_digest,
        "channel": source.get("channel"),
        "interactionId": source.get("interactionId"),
        "presentationMessageId": source.get("presentationMessageId"),
        "presentationRole": presentation_message.get("role"),
        "presentationSentAt": presentation_message.get("occurredAt"),
        "presentationContentSha256": hashlib.sha256(presentation_bytes).hexdigest(),
        "messageId": source.get("messageId"),
        "messageRole": selected_message.get("role"),
        "actorId": selected_message.get("actorId"),
        "sentAt": selected_message.get("occurredAt"),
        "messageContentSha256": hashlib.sha256(canonical_bytes).hexdigest(),
        "statementSha256": capture.get("statementSha256"),
    }
    return {
        "capture": capture, "challenge": challenge, "transcript": transcript,
        "claims": claims,
    }


def p0_contract_block(
        kind: str, approval_id: str, approver: str, approved_at: str,
        capture_path: str, start_id: str, inventory_id: str,
        closed_ids: list[str], management_wp: dict[str, Any], candidate_id: str,
        approved_digest: str, newline: str = "\n") -> str:
    closed = json.dumps(closed_ids, ensure_ascii=False, separators=(",", ":"))
    lines = [
        f"<!-- BEGIN P0 CONTRACT {kind} {approval_id} -->",
        f"- P0 contract approval ID: {approval_id}",
        "- Approval kind: human-direct",
        f"- Approver: {approver}",
        f"- Approved at: {approved_at}",
        f"- Human approval capture: {capture_path}",
        f"- P0 start approval ID: {start_id}",
        f"- Inventory ID: {inventory_id}",
        f"- Closed source item IDs: {closed}",
        f"- P0 management WP ID: {management_wp.get('id')}",
        f"- P0 management WP path: {management_wp.get('path')}",
        f"- Planned candidate ID: {candidate_id}",
        f"- Approved content fileSetSha256: {approved_digest}",
        "- Next authorized action: Run post-P0 D4 against frozen P0-CAND",
        f"<!-- END P0 CONTRACT {kind} {approval_id} -->",
    ]
    return newline.join(lines) + newline


def strip_p0_contract_block(
        rel: str, text: str, approval_id: str, expected_block: str,
        errors: list[str]) -> str:
    kind = Path(rel).stem.upper()
    begin = f"<!-- BEGIN P0 CONTRACT {kind} {approval_id} -->"
    end = f"<!-- END P0 CONTRACT {kind} {approval_id} -->"
    any_begin = re.findall(r"(?m)^<!-- BEGIN P0 CONTRACT [^\n]+ -->\s*$", text)
    any_end = re.findall(r"(?m)^<!-- END P0 CONTRACT [^\n]+ -->\s*$", text)
    if text.count(begin) != 1 or text.count(end) != 1 \
            or text.count(expected_block) != 1 or len(any_begin) != 1 or len(any_end) != 1:
        errors.append(
            f"{rel}: candidate must contain exactly one exact P0 CONTRACT {kind} block")
        return text
    index = text.index(expected_block)
    prefix, suffix = text[:index], text[index + len(expected_block):]
    # Canonical append grammar uses one blank line after a ledger ending in one LF.
    # Remove that added separator together with the block so pre/candidate modes hash alike.
    if suffix or not prefix.endswith("\n\n") or prefix.endswith("\n\n\n"):
        errors.append(f"{rel}: P0 CONTRACT block must have one canonical blank-line separator")
        return prefix + suffix
    return prefix[:-1] + suffix


def normalize_p0_candidate_wp(
        text: str, management_wp: dict[str, Any], approval_id: str,
        candidate_id: str, capture_path: str, errors: list[str]) -> str:
    wp_id = management_wp.get("id")
    if not isinstance(wp_id, str) or not wp_id:
        errors.append("P0 contract management WP ID is missing")
        return text
    lines = text.splitlines(keepends=True)
    in_target = False
    heading_hits = 0
    field_hits = {key: 0 for key in (
        "Status", "Authorized by", "Authorization baseline", "Authorization evidence")}
    expected = {
        "Status": "Verified", "Authorized by": approval_id,
        "Authorization baseline": candidate_id,
        "Authorization evidence": capture_path,
    }
    index_hits = 0
    output: list[str] = []
    for line in lines:
        body, ending = _line_parts(line)
        heading = re.match(r"^(#{2,6})\s+(.*?)\s*$", body)
        if heading:
            in_target = re.search(
                r"(?<![A-Za-z0-9._-])" + re.escape(wp_id) +
                r"(?![A-Za-z0-9._-])", heading.group(2)) is not None
            if in_target:
                heading_hits += 1
            output.append(line)
            continue
        matched_field = False
        if in_target:
            for name, exact in expected.items():
                match = re.match(
                    r"^(\s*[-*]\s*" + re.escape(name) + r"\s*[:：]\s*)(.*?)\s*$",
                    body, re.I)
                if match is None:
                    continue
                actual = match.group(2).strip().strip("`").replace("\\", "/")
                if actual != exact:
                    errors.append(
                        f"P0 contract management WP {wp_id} {name} must equal {exact!r}")
                field_hits[name] += 1
                output.append(match.group(1) + f"<P0-WP-{name.upper().replace(' ', '-')}>" + ending)
                matched_field = True
                break
        if matched_field:
            continue
        cells = gen_index.split_row(body)
        if cells and cells[0].strip().strip("`") == wp_id:
            verified = [index for index, cell in enumerate(cells)
                        if cell.strip().strip("`").casefold() == "verified"]
            if len(verified) != 1:
                errors.append(f"P0 contract management WP {wp_id} index Status must be Verified")
                output.append(line)
                continue
            replaced, count = re.subn(
                r"(?i)(?<![A-Za-z])Verified(?![A-Za-z])", "<P0-WP-STATUS>", body)
            if count != 1:
                errors.append(f"P0 contract management WP {wp_id} index row is ambiguous")
            index_hits += 1
            output.append(replaced + ending)
            continue
        output.append(line)
    if heading_hits != 1 or index_hits != 1 or any(count != 1 for count in field_hits.values()):
        errors.append(
            f"P0 contract management WP {wp_id} requires one detail, four fields, and one index row")
    return "".join(output)


def p0_approved_content_digest(
        content: dict[str, bytes], approval_id: str, approver: str,
        approved_at: str, capture_path: str, start_id: str,
        inventory_id: str, closed_ids: list[str], management_wp: dict[str, Any],
        candidate_id: str, expected_digest: str, errors: list[str]) -> str:
    normalized: dict[str, bytes] = {}
    wp_path = management_wp.get("path")
    for rel, payload in content.items():
        try:
            text = payload.decode("utf-8").replace("\r\n", "\n").replace("\r", "\n")
        except UnicodeDecodeError:
            normalized[rel] = payload
            continue
        if rel in {"DECISIONS.md", "PROGRESS.md", "CHANGELOG.md"}:
            block = p0_contract_block(
                Path(rel).stem.upper(), approval_id, approver, approved_at,
                capture_path, start_id, inventory_id, closed_ids, management_wp,
                candidate_id, expected_digest)
            text = strip_p0_contract_block(rel, text, approval_id, block, errors)
        if rel == wp_path:
            text = normalize_p0_candidate_wp(
                text, management_wp, approval_id, candidate_id, capture_path, errors)
        normalized[rel] = text.encode("utf-8")
    entries = [{
        "path": rel, "bytes": len(normalized[rel]),
        "sha256": hashlib.sha256(normalized[rel]).hexdigest(),
    } for rel in sorted(normalized)]
    encoded = json.dumps(entries, ensure_ascii=False, sort_keys=True,
                         separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def verified_gdd_target(
        documents: list[Any], b0_content: dict[str, bytes],
        b1_content: dict[str, bytes], errors: list[str]) -> dict[str, Any] | None:
    rows = [item for item in documents if isinstance(item, dict)
            and isinstance(item.get("path"), str)
            and item["path"].replace("\\", "/").endswith("_gdd.md")]
    if len(rows) != 1:
        errors.append("docs manifest must identify exactly one canonical *_gdd.md")
        return None
    row = rows[0]
    rel = row["path"].replace("\\", "/")
    if row.get("phase") != "D1" or row.get("domain") != "product intent" \
            or row.get("required") is not True:
        errors.append("canonical GDD manifest row must be required D1/product intent")
    old, new = b0_content.get(rel), b1_content.get(rel)
    if old is None or new is None:
        errors.append("canonical GDD must exist in both historical B0 and B1 file sets")
        return None
    if old != new:
        errors.append("Gate1-approved GDD bytes must remain immutable from B0 through B1")
    try:
        header = parse_header_text(new.decode("utf-8"))
    except UnicodeDecodeError:
        errors.append("canonical GDD must be strict UTF-8")
        return None
    revision = header.get("Version")
    if not isinstance(revision, str) or not revision.strip():
        errors.append("canonical GDD requires a machine-readable Version revision")
    return {"path": rel, "sha256": hashlib.sha256(new).hexdigest(), "revision": revision}


def validate_approval_record(
        root: Path, ref_path: Any, ref_hash: Any, expected_id: Any,
        expected_type: str, target_key: str, expected_target: Any,
        expected_scope: Any, expected_capture_ref: Any, expected_verification_ref: Any,
        errors: list[str], label: str, *, package_approver: Any = None,
        package_approved_at: Any = None, first_wp_id: Any = None,
        capture_result: dict[str, Any] | None = None) -> dict[str, Any] | None:
    loaded = verify_ref(root, {"path": ref_path, "sha256": ref_hash}, errors, label)
    if loaded is None:
        return None
    record = loaded[1]
    target_field = "targetArtifact" if target_key == "targetArtifact" else "baseline"
    allowed = {
        "schemaVersion", "id", "type", "approvalKind", "approver", "approvedAt",
        "scope", target_field, "firstAuthorizedWpId", "sourceEvidence",
        "sourceVerification",
    }
    if set(record) != allowed:
        errors.append(f"{label}: unknown/missing approval-record fields")
    if record.get("schemaVersion") != "1.0.0":
        errors.append(f"{label}.schemaVersion must be 1.0.0")
    if record.get("id") != expected_id:
        errors.append(f"{label}.id does not match W0 package")
    if record.get("type") != expected_type:
        errors.append(f"{label}.type must be {expected_type}")
    if record.get("approvalKind") != "human-direct":
        errors.append(f"{label}.approvalKind must be human-direct")
    if record.get("scope") != expected_scope:
        errors.append(f"{label}.scope must exactly equal the closed gate scope")
    if record.get(target_field) != expected_target:
        errors.append(f"{label}.{target_field} must exactly bind the verified target")
    if not timezone_datetime(record.get("approvedAt")):
        errors.append(f"{label}.approvedAt must be a timezone timestamp")
    if not isinstance(record.get("approver"), str) or not record["approver"].strip():
        errors.append(f"{label}.approver must be non-empty")
    expected_first_wp = first_wp_id if expected_type == "d5" else None
    if record.get("firstAuthorizedWpId") != expected_first_wp:
        errors.append(f"{label}.firstAuthorizedWpId mismatch")
    if expected_type == "d5":
        if record.get("approver") != package_approver:
            errors.append("D5 approval record approver does not match W0 package")
        if record.get("approvedAt") != package_approved_at:
            errors.append("D5 approval record approvedAt does not match W0 package")
    capture = capture_result.get("capture") if isinstance(capture_result, dict) else None
    if not isinstance(capture, dict):
        errors.append(f"{label}: matching human approval capture is unavailable")
    else:
        if record.get("approver") != capture.get("approver"):
            errors.append(f"{label}: approver differs from human capture")
        if record.get("approvedAt") != capture.get("occurredAt"):
            errors.append(f"{label}: approvedAt differs from human capture occurredAt")
    source = record.get("sourceEvidence")
    expected_source = ({"path": expected_capture_ref.get("path"),
                        "sha256": expected_capture_ref.get("sha256")}
                       if isinstance(expected_capture_ref, dict) else None)
    if source != expected_source:
        errors.append(f"{label}.sourceEvidence must exactly equal its W0 capture reference")
    if isinstance(source, dict):
        verify_file_hash(root, source.get("path"), source.get("sha256"), errors,
                         f"{label}.sourceEvidence")
        if identity_key(source.get("path")) == identity_key(ref_path):
            errors.append(f"{label}: approval record cannot cite itself as source evidence")
    if record.get("sourceVerification") != expected_verification_ref:
        errors.append(
            f"{label}.sourceVerification must exactly equal its W0 provenance reference")
    if isinstance(expected_verification_ref, dict):
        if identity_key(expected_verification_ref.get("path")) == identity_key(ref_path):
            errors.append(f"{label}: approval record cannot cite itself as sourceVerification")
    return record


def d5_history_block(
        kind: str, d5_id: str, approver: str, approved_at: str,
        record_path: str, b1_id: str, b1_file_set: str, b2_id: str,
        wp_id: str, wp_path: str, newline: str) -> str:
    lines = [
        f"<!-- BEGIN D5 {kind} {d5_id} -->",
        f"- D5 approval ID: {d5_id}",
        "- Approval kind: human-direct",
        f"- Approver: {approver}",
        f"- Approved at: {approved_at}",
        f"- D5 approval record: {record_path}",
        f"- B1 baseline ID: {b1_id}",
        f"- B1 fileSetSha256: {b1_file_set}",
        f"- B2 baseline ID: {b2_id}",
        f"- First authorized WP ID: {wp_id}",
        f"- First authorized WP path: {wp_path}",
        "- Next stage: W0",
        "- Next authorized action: Validate W0 handoff and reacquire runtime permissions",
        f"<!-- END D5 {kind} {d5_id} -->",
    ]
    return newline.join(lines) + newline


def append_separator(text: str, newline: str) -> str:
    if text.endswith(newline * 2):
        return ""
    if text.endswith(newline):
        return newline
    return newline * 2


def normalize_progress_fields(
        old: str, new: str, expected: dict[str, str], errors: list[str]) -> tuple[str, str]:
    normalized: list[str] = []
    pattern_template = r"(?m)^(\s*[-*]\s*{label}\s*[:：]\s*)(.*?)(\r?)$"
    for text, is_new in ((old, False), (new, True)):
        boundary = re.search(r"(?m)^##\s+", text)
        split_at = boundary.start() if boundary else len(text)
        value, tail = text[:split_at], text[split_at:]
        for label, exact in expected.items():
            pattern = re.compile(pattern_template.format(label=re.escape(label)), re.I)
            matches = list(pattern.finditer(value))
            if len(matches) != 1:
                errors.append(f"PROGRESS.md: field {label!r} must occur exactly once")
                continue
            if is_new and matches[0].group(2).strip().strip("`") != exact:
                errors.append(f"PROGRESS.md: field {label!r} must equal {exact!r}")
            value = pattern.sub(r"\1<D5-PROGRESS-FIELD>\3", value, count=1)
        normalized.append(value + tail)
    return normalized[0], normalized[1]


def validate_exact_d5_log_transition(
        rel: str, old_bytes: bytes, current_bytes: bytes, d5_id: str,
        approver: str, approved_at: str, record_path: str, b1_id: str,
        b1_file_set: str, b2_id: str, wp_id: str | None, wp_path: str | None,
        errors: list[str]) -> None:
    try:
        old, current = old_bytes.decode("utf-8"), current_bytes.decode("utf-8")
    except UnicodeDecodeError:
        errors.append(f"{rel}: D5 log transition must be strict UTF-8")
        return
    if not wp_id or not wp_path:
        errors.append(f"{rel}: first authorized WP ID/path missing for D5 block")
        return
    newline = "\r\n" if "\r\n" in old else "\n"
    kind = Path(rel).stem.upper()
    expected_block = d5_history_block(
        kind, d5_id, approver, approved_at, record_path, b1_id,
        b1_file_set, b2_id, wp_id, wp_path, newline)
    compare_old, compare_current = old, current
    if rel == "PROGRESS.md":
        sentinel = f"<!-- BEGIN D5 PROGRESS {d5_id} -->"
        marker_index = current.find(sentinel)
        current_prefix = current if marker_index < 0 else current[:marker_index]
        current_suffix = "" if marker_index < 0 else current[marker_index:]
        compare_old, normalized_prefix = normalize_progress_fields(
            old, current_prefix, {
                "Current phase": "W0",
                "Current Work Package": wp_id,
                "Status": "W0 handoff authorized",
                "Last known good baseline": b2_id,
                "Next authorized action": (
                    "Validate W0 handoff and reacquire runtime permissions"),
            }, errors)
        compare_current = normalized_prefix + current_suffix
    expected = compare_old + append_separator(compare_old, newline) + expected_block
    if compare_current != expected:
        errors.append(f"{rel}: D5 transition must equal the exact authorized sentinel block")


def verify_transition_diff(
        root: Path, b1_content: dict[str, bytes], b2_files: dict[str, dict[str, Any]],
        docs_manifest: dict[str, Any], formal: dict[str, tuple[dict[str, Any], dict[str, str]]],
        manifest_rel: str, b1_id: str, b1_file_set: str, b2_id: str,
        d5_id: str, approver: str, approved_at: str, d5_record_rel: str,
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
        if rel in append_only:
            validate_exact_d5_log_transition(
                rel, old_bytes, current_bytes, d5_id, approver, approved_at,
                d5_record_rel, b1_id, b1_file_set, b2_id, first_wp_id,
                first_wp_path, errors)
            continue
        if current_bytes == old_bytes:
            continue
        if rel == manifest_rel:
            validate_manifest_transition(old_bytes, docs_manifest, b2_id, formal, errors)
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


def transition_baseline_reference(
        ref: Any, baseline: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": ref.get("id") if isinstance(ref, dict) else None,
        "path": ref.get("path") if isinstance(ref, dict) else None,
        "sha256": ref.get("sha256") if isinstance(ref, dict) else None,
        "fileSetSha256": ref.get("fileSetSha256") if isinstance(ref, dict) else None,
        "revision": baseline.get("revision"),
    }


def transition_file_state(value: Any, errors: list[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != {"exists", "bytes", "sha256"}:
        errors.append(f"{label}: file state has unknown/missing fields")
        return {"exists": False, "bytes": None, "sha256": None}
    exists = value.get("exists")
    if not isinstance(exists, bool):
        errors.append(f"{label}.exists must be boolean")
    if exists is False:
        if value.get("bytes") is not None or value.get("sha256") is not None:
            errors.append(f"{label}: absent state requires null bytes/sha256")
    elif exists is True:
        if type(value.get("bytes")) is not int or value.get("bytes", -1) < 0:
            errors.append(f"{label}.bytes must be a non-negative integer")
        if not isinstance(value.get("sha256"), str) or SHA256_RE.fullmatch(
                value.get("sha256", "")) is None:
            errors.append(f"{label}.sha256 must be 64 lowercase hex characters")
    return value


def manifest_file_states(records: dict[str, dict[str, Any]]) -> dict[str, dict[str, Any]]:
    return {path: {
        "exists": True, "bytes": row.get("bytes"), "sha256": row.get("sha256"),
    } for path, row in records.items()}


def absent_file_state() -> dict[str, Any]:
    return {"exists": False, "bytes": None, "sha256": None}


def actual_file_state(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return absent_file_state()
    return {"exists": True, "bytes": path.stat().st_size, "sha256": sha256(path)}


def transition_source_tree_sha256(records: dict[str, dict[str, Any]]) -> str:
    entries = [{
        "path": path, "bytes": row.get("bytes"), "sha256": row.get("sha256"),
    } for path, row in sorted(records.items())]
    return canonical_json_sha256(entries)


def lifecycle_event_sequence_sha256(entries: list[dict[str, Any]]) -> str:
    projection = [{
        "sequence": item.get("sequence"), "eventId": item.get("eventId"),
        "operation": item.get("operation"), "path": item.get("path"),
        "rootRole": item.get("rootRole"),
        "beforeSha256": (item.get("before", {}).get("sha256")
                         if isinstance(item.get("before"), dict) else None),
        "afterSha256": (item.get("after", {}).get("sha256")
                        if isinstance(item.get("after"), dict) else None),
        "occurredAt": item.get("occurredAt"), "phase": item.get("phase"),
        "classification": item.get("classification"),
        "ruleId": item.get("ruleId"),
        "sourceInventoryId": item.get("sourceInventoryId"),
        "copySourceRootRole": (
            item.get("copySource", {}).get("rootRole")
            if isinstance(item.get("copySource"), dict) else None),
        "copySourcePath": (
            item.get("copySource", {}).get("path")
            if isinstance(item.get("copySource"), dict) else None),
        "copySourceSha256": (
            item.get("copySource", {}).get("sha256")
            if isinstance(item.get("copySource"), dict) else None),
    } for item in sorted(entries, key=lambda row: row.get("sequence", 0)
                         if isinstance(row, dict) else 0)]
    return canonical_json_sha256(projection)


def validate_transition_path(raw: Any, errors: list[str], label: str) -> str | None:
    if not isinstance(raw, str) or not raw or "\\" in raw or raw.startswith(("/", "./")):
        errors.append(f"{label}: path must be canonical project-relative POSIX")
        return None
    parts = raw.split("/")
    if any(part in {"", ".", ".."} for part in parts) or re.match(r"^[A-Za-z]:", raw):
        errors.append(f"{label}: path must not contain empty/dot/drive segments")
        return None
    return raw


def path_is_reparse(path: Path) -> bool:
    """Return true for a symlink or Windows junction/reparse point."""
    try:
        info = path.lstat()
    except OSError:
        return False
    return path.is_symlink() or bool(
        getattr(info, "st_file_attributes", 0)
        & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400))


def validate_transition_scope(
        root: Path, value: Any, expected_targets: list[dict[str, str]], errors: list[str],
        label: str) -> list[dict[str, str]]:
    expected_keys = {
        "kind", "coverage", "includeSetArtifact", "includeSetSha256",
        "evidenceAcquisitionPolicy", "postMonitorExclusions",
    }
    if not isinstance(value, dict) or set(value) != expected_keys:
        errors.append(f"{label}: monitoring scope has unknown/missing fields")
        return []
    if value.get("kind") != "in-scope-transition-mutations-v1" \
            or value.get("coverage") != "all-product-ledger-staging-and-result-mutations" \
            or value.get("evidenceAcquisitionPolicy") != \
            "approval-evidence-outside-transition-mutation-scope" \
            or value.get("postMonitorExclusions") != [
                "lifecycle-write-log", "lifecycle-transition-attestation",
                "lifecycle-transition-provenance", "w0-handoff-package"]:
        errors.append(f"{label}: monitoring scope constants are invalid")
    loaded = exact_artifact_ref(
        root, value.get("includeSetArtifact"), errors, f"{label}.includeSetArtifact")
    targets: Any = None
    if loaded is not None:
        data = loaded[1]
        if set(data) != {"targets"} or not isinstance(data.get("targets"), list):
            errors.append(f"{label}.includeSetArtifact must be a closed targets object")
        else:
            targets = data["targets"]
            normalized: list[dict[str, str]] = []
            for index, item in enumerate(targets):
                if not isinstance(item, dict) or set(item) != {"rootRole", "path"} \
                        or item.get("rootRole") not in {
                            "canonical-project", "private-staging", "result-artifacts"}:
                    errors.append(
                        f"{label}.includeSetArtifact.targets[{index}] is invalid")
                    continue
                path = validate_transition_path(
                    item.get("path"), errors,
                    f"{label}.includeSetArtifact.targets[{index}].path")
                if path is not None:
                    normalized.append({"rootRole": item["rootRole"], "path": path})
            expected_order = sorted(
                targets, key=lambda row: (row.get("rootRole", ""), row.get("path", ""))
                if isinstance(row, dict) else ("", ""))
            if targets != expected_order or len(normalized) != len(targets) \
                    or len({identity_key(item) for item in normalized}) != len(targets):
                errors.append(f"{label}.includeSetArtifact targets must be sorted/unique")
            if loaded[0].read_bytes() != canonical_json_bytes({"targets": targets}):
                errors.append(f"{label}.includeSetArtifact must be canonical JSON bytes")
    if targets != expected_targets:
        errors.append(f"{label}: monitoring include set does not exact-cover mutation targets")
    if value.get("includeSetSha256") != canonical_json_sha256(
            targets if isinstance(targets, list) else []):
        errors.append(f"{label}.includeSetSha256 mismatch")
    return targets if isinstance(targets, list) else []


def validate_lifecycle_write_log(
        root: Path, ref: Any, transition_type: str,
        source_records: dict[str, dict[str, Any]],
        result_records: dict[str, dict[str, Any]], seal_path: str,
        include_targets: list[dict[str, str]], target_roots: dict[str, Path],
        result_artifact_paths: set[str],
        errors: list[str], label: str
        ) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    """Validate the closed, authority-observed transition event stream.

    The log is intentionally stricter than a net diff.  Each public apply/sync
    path has one direct source-to-authorized-final event, snapshot copies bind
    their exact source hash, and logical seals cannot conceal a path mutation.
    """
    loaded = exact_artifact_ref(root, ref, errors, label)
    if loaded is None:
        return {}, []
    _, data = loaded
    expected_keys = {
        "schemaVersion", "id", "transitionType", "startedAt", "completedAt",
        "entries", "entrySetSha256", "eventSequenceSha256", "noUnloggedWrites",
    }
    if set(data) != expected_keys:
        errors.append(f"{label}: write log has unknown/missing fields")
    prefix = "P0" if transition_type == "p0" else "D5"
    if data.get("schemaVersion") != "1.0.0" or data.get("transitionType") != transition_type \
            or not isinstance(data.get("id"), str) or re.fullmatch(
                rf"LTWL-{prefix}-[A-Z0-9][A-Z0-9._-]*", data.get("id", "")) is None:
        errors.append(f"{label}: write log identity/type is invalid")
    started, completed = parsed_timestamp(data.get("startedAt")), parsed_timestamp(
        data.get("completedAt"))
    if started is None or completed is None or started > completed:
        errors.append(f"{label}: write-log startedAt/completedAt chronology is invalid")
    if data.get("noUnloggedWrites") is not True:
        errors.append(f"{label}.noUnloggedWrites must be true")
    entries = data.get("entries")
    if not isinstance(entries, list):
        errors.append(f"{label}.entries must be an array")
        entries = []
    d5_content_rules = {
        "d5-decisions-append-block-v1", "d5-progress-controlled-fields-v1",
        "d5-progress-history-block-v1", "d5-progress-composite-v1",
        "d5-changelog-append-block-v1", "d5-formal-document-promotion-v1",
        "d5-docs-index-sync-v1", "d5-docs-manifest-sync-v1",
        "d5-first-wp-handoff-metadata-v1",
    }
    phase_contracts: dict[str, tuple[str, set[str], set[str | None], str | None]] = {
        "p0-inventory-content": (
            "inventory-content", {"p0-inventory-row-affected-doc-v1"},
            {"private-staging"}, None),
        "p0-preapproval-procedure": (
            "preapproval-procedural", {"p0-fixed-preapproval-procedure-v1"},
            {"private-staging"}, None),
        "p0-postapproval-metadata": (
            "postapproval-metadata", {"p0-fixed-postapproval-metadata-v1"},
            {"private-staging"}, None),
        "p0-freeze-copy": (
            "snapshot-copy", {"p0-snapshot-file-copy-v1"},
            {"result-artifacts"}, "private-staging"),
        "p0-freeze-manifest": (
            "snapshot-manifest", {"p0-snapshot-manifest-v1"},
            {"result-artifacts"}, None),
        "p0-freeze": (
            "candidate-freeze", {"p0-candidate-freeze-v1"}, {None}, None),
        "p0-postfreeze-record": (
            "postfreeze-record", {"p0-contract-machine-record-v1"},
            {"result-artifacts"}, None),
        "p0-apply": (
            "canonical-apply", {"p0-candidate-exact-atomic-apply-v1"},
            {"canonical-project"}, "result-artifacts"),
        "p0-seal": (
            "transition-seal", {"p0-single-transition-seal-v1"}, {None}, None),
        "d5-staging": ("d5-staging", d5_content_rules, {"private-staging"}, None),
        "d5-sync": (
            "d5-allowed-sync", d5_content_rules | {
                "d5-post-sync-manifest-v1", "d5-b2-baseline-manifest-v1"},
            {"canonical-project"}, "private-staging"),
        "d5-allowed-diff": (
            "d5-result-artifact", {"d5-allowed-diff-artifact-v1"},
            {"result-artifacts"}, None),
        "d5-post-sync-manifest": (
            "d5-result-artifact", {"d5-post-sync-manifest-v1"},
            {"result-artifacts"}, None),
        "d5-snapshot-copy": (
            "snapshot-copy", {"d5-snapshot-file-copy-v1"},
            {"result-artifacts"}, "canonical-or-result"),
        "d5-snapshot-manifest": (
            "snapshot-manifest", {"d5-b2-baseline-manifest-v1"},
            {"result-artifacts"}, None),
        "d5-seal": (
            "transition-seal", {"d5-snapshot-immutability-seal-v1"},
            {None}, None),
    }
    allowed_phases = ({key for key in phase_contracts if key.startswith("p0-")}
                      if transition_type == "p0" else
                      {key for key in phase_contracts if key.startswith("d5-")})
    phase_order = ({
        "p0-inventory-content": 0, "p0-preapproval-procedure": 0,
        "p0-postapproval-metadata": 1, "p0-freeze-copy": 2,
        "p0-freeze-manifest": 3, "p0-freeze": 4,
        "p0-postfreeze-record": 5, "p0-apply": 6, "p0-seal": 7,
    } if transition_type == "p0" else {
        "d5-staging": 0, "d5-sync": 1, "d5-allowed-diff": 2,
        "d5-post-sync-manifest": 3, "d5-snapshot-copy": 4,
        "d5-snapshot-manifest": 5, "d5-seal": 6,
    })
    event_ids: list[Any] = []
    previous_time: dt.datetime | None = None
    previous_rank = -1
    by_path: dict[tuple[str, str], list[dict[str, Any]]] = {}
    include_keys = {(item["rootRole"], item["path"]) for item in include_targets}
    for index, item in enumerate(entries):
        row_label = f"{label}.entries[{index}]"
        if not isinstance(item, dict) or set(item) != {
                "sequence", "eventId", "operation", "rootRole", "path", "before", "after",
                "occurredAt", "phase", "classification", "ruleId",
                "sourceInventoryId", "copySource"}:
            errors.append(f"{row_label}: event has unknown/missing fields")
            continue
        if item.get("sequence") != index + 1:
            errors.append(f"{row_label}.sequence must be contiguous from one")
        event_id = item.get("eventId")
        if not isinstance(event_id, str) or not event_id.strip():
            errors.append(f"{row_label}.eventId must be non-empty")
        event_ids.append(event_id)
        phase = item.get("phase")
        if phase not in allowed_phases:
            errors.append(f"{row_label}.phase is invalid for {transition_type}")
            contract = None
        else:
            contract = phase_contracts[phase]
            rank = phase_order[phase]
            if rank < previous_rank:
                errors.append(f"{row_label}: phase order regressed")
            previous_rank = max(previous_rank, rank)
        is_seal = item.get("operation") == "monitor-seal"
        rel = (None if is_seal else validate_transition_path(
            item.get("path"), errors, f"{row_label}.path"))
        root_role = item.get("rootRole")
        if contract is not None:
            expected_class, rules, roles, copy_role = contract
            if item.get("classification") != expected_class:
                errors.append(f"{row_label}.classification does not match phase")
            if item.get("ruleId") not in rules:
                errors.append(f"{row_label}.ruleId does not match phase")
            if root_role not in roles:
                errors.append(f"{row_label}.rootRole does not match phase")
        else:
            copy_role = None
        if not is_seal and root_role not in target_roots:
            errors.append(f"{row_label}.rootRole is invalid")
        if is_seal:
            if any(item.get(key) is not None for key in (
                    "rootRole", "path", "before", "after", "copySource")):
                errors.append(f"{row_label}: logical seal must not name or mutate a path")
        elif item.get("operation") == "monitor-seal":
            errors.append(f"{row_label}: monitor-seal is reserved for logical seal phases")
        if rel is not None:
            by_path.setdefault((str(root_role), rel), []).append(item)
            if (root_role, rel) not in include_keys:
                errors.append(f"{row_label}.path is outside the complete monitor include set")
            target_root = target_roots.get(str(root_role))
            if target_root is not None:
                resolved = resolve_path(
                    target_root, rel, errors, f"{row_label}.resolvedPath")
                if resolved is not None and path_is_reparse(resolved):
                    errors.append(f"{row_label}.path resolves through a reparse point")
        before = ({} if is_seal else transition_file_state(
            item.get("before"), errors, f"{row_label}.before"))
        after = ({} if is_seal else transition_file_state(
            item.get("after"), errors, f"{row_label}.after"))
        operation = item.get("operation")
        operation_valid = is_seal or (
            operation == "create" and before.get("exists") is False
            and after.get("exists") is True
            or operation in {"replace", "append"} and before.get("exists") is True
            and after.get("exists") is True
            or operation == "delete" and before.get("exists") is True
            and after.get("exists") is False)
        if not operation_valid or not is_seal and before == after:
            errors.append(f"{row_label}: operation/before/after transition is invalid")
        needs_inventory = phase == "p0-inventory-content"
        inventory_id = item.get("sourceInventoryId")
        if needs_inventory != (isinstance(inventory_id, str) and bool(inventory_id)):
            errors.append(f"{row_label}.sourceInventoryId does not match phase semantics")
        copy_source = item.get("copySource")
        if copy_role is None:
            if copy_source is not None:
                errors.append(f"{row_label}.copySource must be null for this phase")
        elif not isinstance(copy_source, dict) or set(copy_source) != {
                "rootRole", "path", "sha256"}:
            errors.append(f"{row_label}.copySource is missing or not closed")
        else:
            source_role = copy_source.get("rootRole")
            if copy_role == "canonical-or-result":
                valid_source_role = source_role in {"canonical-project", "result-artifacts"}
            else:
                valid_source_role = source_role == copy_role
            source_rel = validate_transition_path(
                copy_source.get("path"), errors, f"{row_label}.copySource.path")
            source_hash = copy_source.get("sha256")
            if not valid_source_role:
                errors.append(f"{row_label}.copySource.rootRole does not match phase")
            if not isinstance(source_hash, str) or SHA256_RE.fullmatch(source_hash) is None:
                errors.append(f"{row_label}.copySource.sha256 is invalid")
            elif after.get("sha256") != source_hash:
                errors.append(f"{row_label}: copied bytes do not equal copySource hash")
            if source_rel is not None and source_role in target_roots:
                source_path = resolve_path(
                    target_roots[source_role], source_rel, errors,
                    f"{row_label}.copySource.resolvedPath")
                if source_path is not None and (not source_path.is_file()
                                                or sha256(source_path) != source_hash):
                    errors.append(f"{row_label}: copySource actual bytes/hash mismatch")
        occurred = parsed_timestamp(item.get("occurredAt"))
        if occurred is None or started is None or completed is None \
                or not (started <= occurred <= completed) \
                or previous_time is not None and occurred < previous_time:
            errors.append(f"{row_label}.occurredAt is outside ordered log chronology")
        if occurred is not None:
            previous_time = occurred
    if len(event_ids) != len({identity_key(value) for value in event_ids}):
        errors.append(f"{label}.entries eventId values must be unique")
    sorted_entries = sorted(entries, key=lambda row: row.get("sequence", 0)
                            if isinstance(row, dict) else 0)
    if data.get("entrySetSha256") != canonical_json_sha256(sorted_entries):
        errors.append(f"{label}.entrySetSha256 mismatch")
    sequence_hash = lifecycle_event_sequence_sha256(entries)
    if data.get("eventSequenceSha256") != sequence_hash:
        errors.append(f"{label}.eventSequenceSha256 mismatch")

    source_states = manifest_file_states(source_records)
    result_states = manifest_file_states(result_records)
    public_phase = "p0-apply" if transition_type == "p0" else "d5-sync"
    for rel in sorted(set(source_states) | set(result_states)):
        expected_before = source_states.get(rel, absent_file_state())
        expected_after = result_states.get(rel, absent_file_state())
        public_events = [item for item in by_path.get(("canonical-project", rel), [])
                         if item.get("phase") == public_phase]
        if expected_before == expected_after:
            if public_events:
                errors.append(f"{label}: net-zero/restored public write is forbidden: {rel}")
            continue
        if rel in result_artifact_paths:
            continue
        if len(public_events) != 1:
            errors.append(
                f"{label}: changed canonical path requires exactly one direct {public_phase} event: {rel}")
            continue
        event = public_events[0]
        if event.get("before") != expected_before or event.get("after") != expected_after:
            errors.append(f"{label}: {rel} public event is not source-to-authorized-final")

    for (root_role, rel), path_events in sorted(by_path.items()):
        if len(path_events) > 1 and any(item.get("phase") in {
                "p0-apply", "d5-sync"} for item in path_events):
            errors.append(f"{label}: public path has multiple/transient writes: {root_role}:{rel}")
        for left, right in zip(path_events, path_events[1:]):
            if left.get("after") != right.get("before"):
                errors.append(f"{label}: {rel} write-event state chain is broken")
        actual = (actual_file_state(target_roots[root_role] / rel)
                  if root_role in target_roots else absent_file_state())
        if root_role != "canonical-project" and path_events \
                and path_events[-1].get("after") != actual:
            errors.append(f"{label}: final event state differs from actual bytes: {root_role}:{rel}")

    phase_counts = {phase: sum(item.get("phase") == phase for item in entries
                               if isinstance(item, dict)) for phase in allowed_phases}
    exact_one = ({"p0-freeze-manifest", "p0-freeze", "p0-postfreeze-record", "p0-seal"}
                 if transition_type == "p0" else
                 {"d5-allowed-diff", "d5-post-sync-manifest",
                  "d5-snapshot-manifest", "d5-seal"})
    for phase in sorted(exact_one):
        if phase_counts.get(phase) != 1:
            errors.append(f"{label}: phase {phase} must occur exactly once")
    required_many = ({"p0-freeze-copy", "p0-apply"} if transition_type == "p0"
                     else {"d5-staging", "d5-sync", "d5-snapshot-copy"})
    for phase in sorted(required_many):
        if phase_counts.get(phase, 0) < 1:
            errors.append(f"{label}: phase {phase} requires at least one event")
    return data, entries


def transition_approval_binding(
        approval_id: Any, verification_ref: Any,
        capture_result: dict[str, Any] | None,
        approval_pv: dict[str, Any] | None) -> dict[str, Any]:
    claims = (capture_result.get("claims")
              if isinstance(capture_result, dict) else {})
    claims = claims if isinstance(claims, dict) else {}
    verification = ({"path": verification_ref.get("path"),
                     "sha256": verification_ref.get("sha256")}
                    if isinstance(verification_ref, dict) else {})
    return {
        "approvalId": approval_id,
        "verification": verification,
        "presentationAt": claims.get("presentationSentAt"),
        "humanResponseAt": claims.get("sentAt"),
        "verificationCompletedAt": (approval_pv.get("verifiedAt")
                                    if isinstance(approval_pv, dict) else None),
    }


def _transition_times(
        values: list[Any], errors: list[str], label: str) -> list[dt.datetime]:
    result: list[dt.datetime] = []
    for index, value in enumerate(values):
        parsed = parsed_timestamp(value)
        if parsed is None:
            errors.append(f"{label}[{index}] must be a timezone timestamp")
        else:
            result.append(parsed)
    return result


def _expected_d5_rule_id(
        path: str, manifest_rel: str, post_sync_rel: str,
        formal_paths: set[str], first_wp_path: str | None) -> str | None:
    if path == "DECISIONS.md":
        return "d5-decisions-append-block-v1"
    if path == "PROGRESS.md":
        return "d5-progress-composite-v1"
    if path == "CHANGELOG.md":
        return "d5-changelog-append-block-v1"
    if path == manifest_rel:
        return "d5-docs-manifest-sync-v1"
    if path == post_sync_rel:
        return "d5-post-sync-manifest-v1"
    if first_wp_path is not None and path == first_wp_path:
        return "d5-first-wp-handoff-metadata-v1"
    if path in formal_paths:
        return ("d5-docs-index-sync-v1" if path.endswith("_docs_index.md") else
                "d5-formal-document-promotion-v1")
    return None


def validate_snapshot_binding(
        root: Path, value: Any, result_ref: Any,
        result_baseline: dict[str, Any], result_records: dict[str, dict[str, Any]],
        entries: list[dict[str, Any]], transition_type: str,
        target_roots: dict[str, Path], errors: list[str], label: str) -> dict[str, Any]:
    """Reconstruct and validate one snapshot-only result from write events."""
    keys = {
        "sourceFileSetSha256", "snapshotRoot", "copiedFileCount", "copyMapSha256",
        "copyStartedAt", "copyCompletedAt", "manifestCreatedAt", "manifest",
        "sealEventId",
    }
    if not isinstance(value, dict) or set(value) != keys:
        errors.append(f"{label}: snapshot binding has unknown/missing fields")
        return {}
    revision = result_baseline.get("revision")
    if not isinstance(revision, dict) or revision.get("kind") != "snapshot":
        errors.append(f"{label}: lifecycle v1 result must be snapshot-backed")
        snapshot_root = None
    else:
        snapshot_root = revision.get("snapshotRoot")
    if value.get("sourceFileSetSha256") != result_baseline.get("fileSetSha256"):
        errors.append(f"{label}.sourceFileSetSha256 must equal result fileSetSha256")
    if value.get("snapshotRoot") != snapshot_root:
        errors.append(f"{label}.snapshotRoot must equal the result revision")

    copy_phase = "p0-freeze-copy" if transition_type == "p0" else "d5-snapshot-copy"
    manifest_phase = ("p0-freeze-manifest" if transition_type == "p0"
                      else "d5-snapshot-manifest")
    seal_phase = "p0-freeze" if transition_type == "p0" else "d5-seal"
    copies = [item for item in entries if item.get("phase") == copy_phase]
    manifest_events = [item for item in entries if item.get("phase") == manifest_phase]
    seal_events = [item for item in entries if item.get("phase") == seal_phase]
    expected_destinations = {
        f"{str(snapshot_root).rstrip('/')}/{path}": row
        for path, row in result_records.items()
    } if isinstance(snapshot_root, str) and snapshot_root else {}
    by_destination = {item.get("path"): item for item in copies}
    if len(by_destination) != len(copies) or set(by_destination) != set(expected_destinations):
        errors.append(f"{label}: snapshot copies must exact-cover every manifest file once")
    copy_map: list[dict[str, Any]] = []
    copy_times: list[dt.datetime] = []
    for destination, row in sorted(expected_destinations.items()):
        item = by_destination.get(destination)
        if not isinstance(item, dict):
            continue
        source = item.get("copySource")
        after = item.get("after")
        if not isinstance(source, dict):
            continue
        if not isinstance(after, dict) or after.get("sha256") != row.get("sha256") \
                or after.get("bytes") != row.get("bytes"):
            errors.append(f"{label}: snapshot destination differs from manifest: {destination}")
        if source.get("sha256") != row.get("sha256"):
            errors.append(f"{label}: snapshot source hash differs from manifest: {destination}")
        copy_map.append({
            "sourceRootRole": source.get("rootRole"),
            "sourcePath": source.get("path"),
            "sourceSha256": source.get("sha256"),
            "snapshotPath": destination,
            "snapshotSha256": after.get("sha256") if isinstance(after, dict) else None,
        })
        occurred = parsed_timestamp(item.get("occurredAt"))
        if occurred is not None:
            copy_times.append(occurred)
        snapshot_actual = actual_file_state(root / destination)
        if snapshot_actual != after:
            errors.append(f"{label}: snapshot copy actual bytes mismatch: {destination}")
    if value.get("copiedFileCount") != len(copy_map):
        errors.append(f"{label}.copiedFileCount mismatch")
    if value.get("copyMapSha256") != canonical_json_sha256(copy_map):
        errors.append(f"{label}.copyMapSha256 mismatch")
    if copy_times:
        if parsed_timestamp(value.get("copyStartedAt")) != min(copy_times) \
                or parsed_timestamp(value.get("copyCompletedAt")) != max(copy_times):
            errors.append(f"{label}: copy time bounds mismatch")
    else:
        errors.append(f"{label}: snapshot requires copy events")
    if len(manifest_events) != 1:
        errors.append(f"{label}: snapshot manifest event must occur exactly once")
    else:
        manifest_event = manifest_events[0]
        expected_manifest_ref = {
            "path": result_ref.get("path") if isinstance(result_ref, dict) else None,
            "sha256": result_ref.get("sha256") if isinstance(result_ref, dict) else None,
        }
        if value.get("manifest") != expected_manifest_ref \
                or manifest_event.get("path") != expected_manifest_ref["path"] \
                or manifest_event.get("after", {}).get("sha256") != expected_manifest_ref["sha256"]:
            errors.append(f"{label}: manifest event/reference mismatch")
        if parsed_timestamp(value.get("manifestCreatedAt")) != parsed_timestamp(
                manifest_event.get("occurredAt")):
            errors.append(f"{label}.manifestCreatedAt mismatch")
    if len(seal_events) != 1 or value.get("sealEventId") != (
            seal_events[0].get("eventId") if seal_events else None):
        errors.append(f"{label}.sealEventId must bind the unique logical snapshot seal")
    return value


def validate_lifecycle_transition(
        root: Path, proof: Any, transition_type: str,
        source_ref: Any, source_baseline: dict[str, Any],
        source_records: dict[str, dict[str, Any]],
        result_ref: Any, result_baseline: dict[str, Any],
        result_records: dict[str, dict[str, Any]],
        approval_bindings: dict[str, dict[str, Any]],
        provenance_runtime: dict[str, Any] | None,
        errors: list[str], label: str, *,
        approved_content_digest: str | None = None,
        manifest_rel: str = "", post_sync_ref: Any = None,
        formal_paths: set[str] | None = None,
        first_wp_path: str | None = None,
        p0_inventory: dict[str, Any] | None = None,
        p0_management_wp_path: str | None = None,
        immutable_paths: set[str] | None = None,
        result_artifact_paths: set[str] | None = None) -> dict[str, Any] | None:
    """Validate one externally observed, complete P0 or D5 mutation sequence."""
    expected_proof_keys = {
        "transitionType", "attestation", "provenanceVerification", "writeLog"}
    if not isinstance(proof, dict) or set(proof) != expected_proof_keys:
        errors.append(f"{label}: transition proof has unknown/missing fields")
        return None
    if proof.get("transitionType") != transition_type:
        errors.append(f"{label}.transitionType must be {transition_type}")
    prefix = "P0" if transition_type == "p0" else "D5"
    attestation_ref = proof.get("attestation")
    if not isinstance(attestation_ref, dict) or set(attestation_ref) != {
            "id", "path", "sha256"}:
        errors.append(f"{label}.attestation has unknown/missing fields")
        return None
    if not isinstance(attestation_ref.get("id"), str) or re.fullmatch(
            rf"LTA-{prefix}-[A-Z0-9][A-Z0-9._-]*",
            attestation_ref.get("id", "")) is None:
        errors.append(f"{label}.attestation.id is invalid")
    attestation_loaded = verify_ref(
        root, {"path": attestation_ref.get("path"),
               "sha256": attestation_ref.get("sha256")},
        errors, f"{label}.attestation")
    if attestation_loaded is None:
        return None
    _, attestation = attestation_loaded
    if set(attestation) != {
            "schemaVersion", "id", "transitionType", "createdAt", "claims"}:
        errors.append(f"{label}.attestation has unknown/missing fields")
    if attestation.get("schemaVersion") != "1.0.0" \
            or attestation.get("id") != attestation_ref.get("id") \
            or attestation.get("transitionType") != transition_type:
        errors.append(f"{label}.attestation identity/type mismatch")
    claims = attestation.get("claims")
    if not isinstance(claims, dict):
        errors.append(f"{label}.attestation.claims must be an object")
        claims = {}

    common_claim_keys = {
        "kind", "sourceBaseline", "monitoring", "writeLog", "noUnloggedWrites",
        "eventSequenceSha256", "completedAt",
    }
    if transition_type == "p0":
        expected_claim_keys = common_claim_keys | {
            "p0Start", "inventoryMutationCount", "firstInventoryMutationAt",
            "inventoryMutationCompletedAt", "preApprovalWriteCount",
            "firstPreApprovalWriteAt", "lastPreApprovalWriteAt",
            "approvedContentFileSetSha256", "normalizationRule",
            "approvalPayloadPreparedAt", "p0Contract", "fixedMetadataWriteAt",
            "candidateSnapshot", "freezeCompletedAt", "resultCandidate",
            "p0ContractRecord", "postFreezeRecordWriteAt",
            "firstApplyWriteAt", "lastApplyWriteAt", "sealCompletedAt",
        }
    else:
        expected_claim_keys = common_claim_keys | {
            "d5Approval", "firstSyncWriteAt", "lastSyncWriteAt",
            "allowedDiffRule", "allowedDiffArtifact", "allowedDiffSha256",
            "allowedDiffArtifactCreatedAt", "postSyncManifest",
            "postSyncManifestCreatedAt", "resultBaseline", "resultSnapshot",
            "sealCompletedAt",
        }
    if set(claims) != expected_claim_keys:
        errors.append(f"{label}.attestation.claims has unknown/missing fields")
    if claims.get("kind") != f"{transition_type}-transition-v1":
        errors.append(f"{label}.attestation.claims.kind is invalid")
    if claims.get("sourceBaseline") != transition_baseline_reference(
            source_ref, source_baseline):
        errors.append(f"{label}.sourceBaseline does not exactly bind the source")
    result_key = "resultCandidate" if transition_type == "p0" else "resultBaseline"
    if claims.get(result_key) != transition_baseline_reference(result_ref, result_baseline):
        errors.append(f"{label}.{result_key} does not exactly bind the result")
    if claims.get("noUnloggedWrites") is not True:
        errors.append(f"{label}.noUnloggedWrites must be true")

    result_artifact_paths = set(result_artifact_paths or set())
    if transition_type == "d5":
        for candidate_ref in (claims.get("allowedDiffArtifact"), claims.get("postSyncManifest")):
            if isinstance(candidate_ref, dict) and isinstance(candidate_ref.get("path"), str):
                result_artifact_paths.add(candidate_ref["path"])

    canonical_paths = sorted(
        (set(source_records) | set(result_records)) - result_artifact_paths)
    seal_path = result_ref.get("path") if isinstance(result_ref, dict) else ""
    monitoring = claims.get("monitoring")
    if not isinstance(monitoring, dict) or set(monitoring) != {
            "sessionId", "providerId", "startEventId", "startedAt", "targets",
            "startState", "scope"}:
        errors.append(f"{label}.monitoring has unknown/missing fields")
        monitoring = {}
    for field in ("sessionId", "providerId", "startEventId"):
        if not isinstance(monitoring.get(field), str) or not monitoring[field].strip():
            errors.append(f"{label}.monitoring.{field} must be non-empty")
    target_rows = monitoring.get("targets")
    if not isinstance(target_rows, list) or len(target_rows) != 3:
        errors.append(f"{label}.monitoring.targets must contain exactly three roles")
        target_rows = []
    target_roots: dict[str, Path] = {}
    expected_target_ids = {
        "canonical-project": str(source_baseline.get("baselineId") or ""),
        "private-staging": (
            f"{source_baseline.get('baselineId')}->{result_baseline.get('baselineId')}"
            ":private-staging"),
        "result-artifacts": str(result_baseline.get("baselineId") or ""),
    }
    seen_target_roles: set[str] = set()
    for index, target in enumerate(target_rows):
        target_label = f"{label}.monitoring.targets[{index}]"
        if not isinstance(target, dict) or set(target) != {
                "role", "resolvedRoot", "immutableTargetId"}:
            errors.append(f"{target_label} has unknown/missing fields")
            continue
        role = target.get("role")
        if role not in expected_target_ids or role in seen_target_roles:
            errors.append(f"{target_label}.role is invalid/duplicate")
            continue
        seen_target_roles.add(role)
        try:
            raw_root = Path(str(target.get("resolvedRoot")))
            bound_root = raw_root.resolve(strict=True)
        except OSError:
            bound_root = None
        if not raw_root.is_absolute() or bound_root is None or not bound_root.is_dir():
            errors.append(f"{target_label}.resolvedRoot must be an existing absolute directory")
            continue
        if role in {"canonical-project", "result-artifacts"} \
                and bound_root != root.resolve():
            errors.append(f"{target_label}.resolvedRoot must equal the project root")
        if role == "private-staging":
            try:
                bound_root.relative_to(root.resolve())
            except ValueError:
                errors.append(f"{target_label}.resolvedRoot must stay inside project root")
            if bound_root == root.resolve():
                errors.append(f"{target_label}.resolvedRoot must be a private child root")
        if path_is_reparse(raw_root) or path_is_reparse(bound_root):
            errors.append(f"{target_label}.resolvedRoot must not be a reparse point")
        if target.get("immutableTargetId") != expected_target_ids[role]:
            errors.append(f"{target_label}.immutableTargetId mismatch")
        target_roots[role] = bound_root
    if seen_target_roles != set(expected_target_ids):
        errors.append(f"{label}.monitoring.targets must exact-cover all three roles")

    scope = monitoring.get("scope") if isinstance(monitoring.get("scope"), dict) else {}
    include_ref = scope.get("includeSetArtifact") if isinstance(scope, dict) else None
    include_loaded = exact_artifact_ref(
        root, include_ref, errors, f"{label}.monitoring.scope.includeSetArtifact.preview")
    declared_targets = (include_loaded[1].get("targets", [])
                        if include_loaded is not None and isinstance(
                            include_loaded[1].get("targets"), list) else [])
    private_targets = [item for item in declared_targets if isinstance(item, dict)
                       and item.get("rootRole") == "private-staging"]
    revision = result_baseline.get("revision")
    snapshot_root = (revision.get("snapshotRoot")
                     if isinstance(revision, dict) else None)
    snapshot_paths = ({f"{snapshot_root}/{path}" for path in result_records}
                      if isinstance(snapshot_root, str) and snapshot_root else set())
    expected_targets = sorted(
        ([{"rootRole": "canonical-project", "path": path}
          for path in canonical_paths]
         + private_targets
         + [{"rootRole": "result-artifacts", "path": path}
            for path in sorted(({str(seal_path)} if isinstance(seal_path, str)
                                 and seal_path else set()) |
                               result_artifact_paths | snapshot_paths)]),
        key=lambda row: (row["rootRole"], row["path"]))
    if not private_targets:
        errors.append(f"{label}: monitored private-staging target set must be non-empty")
    if {item.get("rootRole") for item in declared_targets if isinstance(item, dict)} != {
            "canonical-project", "private-staging", "result-artifacts"}:
        errors.append(f"{label}: include set must exact-cover all three root roles")
    start_state = monitoring.get("startState")
    if not isinstance(start_state, dict) or set(start_state) != {
            "observedAt", "sourceBaselineTreeSha256", "fileSetSha256",
            "targetStartStates"}:
        errors.append(f"{label}.monitoring.startState has unknown/missing fields")
        start_state = {}
    if start_state.get("sourceBaselineTreeSha256") != transition_source_tree_sha256(
            source_records):
        errors.append(f"{label}.monitoring.startState sourceBaselineTreeSha256 mismatch")
    if start_state.get("fileSetSha256") != source_baseline.get("fileSetSha256"):
        errors.append(f"{label}.monitoring.startState fileSetSha256 mismatch")
    validate_transition_scope(
        root, monitoring.get("scope"), expected_targets, errors,
        f"{label}.monitoring.scope")

    write_log, entries = validate_lifecycle_write_log(
        root, proof.get("writeLog"), transition_type, source_records,
        result_records, str(seal_path), expected_targets, target_roots,
        result_artifact_paths, errors,
        f"{label}.writeLog")
    start_state_rows = start_state.get("targetStartStates")
    if not isinstance(start_state_rows, list) or len(start_state_rows) != 3:
        errors.append(f"{label}.monitoring.startState.targetStartStates requires 3 roles")
        start_state_rows = []
    expected_start_rows: list[dict[str, str]] = []
    source_states = manifest_file_states(source_records)
    for role in ("canonical-project", "private-staging", "result-artifacts"):
        role_targets = [item["path"] for item in expected_targets
                        if item["rootRole"] == role]
        states: list[dict[str, Any]] = []
        for path in role_targets:
            events_for_target = [item for item in entries if isinstance(item, dict)
                                 and item.get("rootRole") == role
                                 and item.get("path") == path]
            if events_for_target:
                state = events_for_target[0].get("before")
            elif role == "canonical-project":
                state = source_states.get(path, absent_file_state())
            else:
                state = absent_file_state()
            states.append({"path": path, **(state if isinstance(state, dict) else {})})
        expected_start_rows.append({
            "role": role, "stateSetSha256": canonical_json_sha256(states)})
    expected_start_rows.sort(key=lambda row: row["role"])
    if sorted(start_state_rows, key=lambda row: row.get("role", "")
              if isinstance(row, dict) else "") != expected_start_rows:
        errors.append(f"{label}.monitoring.startState.targetStartStates mismatch")
    expected_log_binding = {
        "path": proof.get("writeLog", {}).get("path")
        if isinstance(proof.get("writeLog"), dict) else None,
        "sha256": proof.get("writeLog", {}).get("sha256")
        if isinstance(proof.get("writeLog"), dict) else None,
        "entryCount": len(entries),
        "entrySetSha256": canonical_json_sha256(
            sorted(entries, key=lambda row: row.get("sequence", 0)
                   if isinstance(row, dict) else 0)),
        "eventSequenceSha256": lifecycle_event_sequence_sha256(entries),
        "complete": True,
    }
    if claims.get("writeLog") != expected_log_binding:
        errors.append(f"{label}.writeLog binding does not match parsed complete log")
    if claims.get("eventSequenceSha256") != lifecycle_event_sequence_sha256(entries):
        errors.append(f"{label}.eventSequenceSha256 mismatch")
    if write_log.get("noUnloggedWrites") is not True:
        errors.append(f"{label}: write log must independently assert noUnloggedWrites")

    started = parsed_timestamp(monitoring.get("startedAt"))
    observed = parsed_timestamp(start_state.get("observedAt"))
    completed = parsed_timestamp(claims.get("completedAt"))
    created = parsed_timestamp(attestation.get("createdAt"))
    log_started = parsed_timestamp(write_log.get("startedAt"))
    log_completed = parsed_timestamp(write_log.get("completedAt"))
    if None in {started, observed, completed, created, log_started, log_completed}:
        errors.append(f"{label}: transition timestamps must all include timezones")
    else:
        assert started is not None and observed is not None and completed is not None
        assert created is not None and log_started is not None and log_completed is not None
        if not (started <= observed <= completed <= created):
            errors.append(f"{label}: monitor/start-state/completion/attestation chronology invalid")
        if log_started != started or log_completed != completed:
            errors.append(f"{label}: write-log bounds must equal monitoring/completedAt")

    def approval(name: str) -> dict[str, Any]:
        expected = approval_bindings.get(name, {})
        actual = claims.get(name)
        if actual != expected:
            errors.append(f"{label}.{name} does not exactly bind approval provenance")
        return expected

    events_by_phase: dict[str, list[dict[str, Any]]] = {}
    times_by_phase: dict[str, list[dt.datetime]] = {}
    for index, entry in enumerate(entries):
        if not isinstance(entry, dict):
            continue
        phase = str(entry.get("phase"))
        events_by_phase.setdefault(phase, []).append(entry)
        occurred = parsed_timestamp(entry.get("occurredAt"))
        if occurred is not None:
            times_by_phase.setdefault(phase, []).append(occurred)
        event_label = f"{label}.writeLog.entries[{index}]"
        path, root_role = entry.get("path"), entry.get("rootRole")
        if root_role in {"canonical-project", "private-staging"} \
                and isinstance(path, str) and path in (immutable_paths or set()):
            errors.append(f"{event_label}: immutable Gate1/intake/registry path was mutated")
        if transition_type == "p0":
            affected = (p0_inventory.get("affectedBySource", {})
                        if isinstance(p0_inventory, dict) else {})
            if phase == "p0-inventory-content":
                source_id = entry.get("sourceInventoryId")
                if not isinstance(source_id, str) or path not in affected.get(source_id, []):
                    errors.append(f"{event_label}: inventory event is not bound to B0 scope")
            elif phase in {"p0-preapproval-procedure", "p0-postapproval-metadata"}:
                allowed = P0_PROCEDURAL_PATHS | ({p0_management_wp_path}
                                                 if p0_management_wp_path else set())
                if path not in allowed:
                    errors.append(f"{event_label}: P0 fixed-procedure path is unauthorized")
            elif phase == "p0-postfreeze-record" and path not in (
                    result_artifact_paths or set()):
                errors.append(f"{event_label}: post-freeze record path is unauthorized")
        elif phase in {"d5-staging", "d5-sync"}:
            expected_rule = _expected_d5_rule_id(
                str(path), manifest_rel,
                str(post_sync_ref.get("path") if isinstance(post_sync_ref, dict) else ""),
                formal_paths or set(), first_wp_path)
            if expected_rule is None or entry.get("ruleId") != expected_rule:
                errors.append(f"{event_label}: D5 content path/rule is unauthorized")

    if transition_type == "p0":
        start_binding, contract_binding = approval("p0Start"), approval("p0Contract")
        inventory_times = times_by_phase.get("p0-inventory-content", [])
        preapproval_times = sorted(
            inventory_times + times_by_phase.get("p0-preapproval-procedure", []))
        metadata_times = times_by_phase.get("p0-postapproval-metadata", [])
        freeze_times = times_by_phase.get("p0-freeze", [])
        record_times = times_by_phase.get("p0-postfreeze-record", [])
        apply_times = times_by_phase.get("p0-apply", [])
        seal_times = times_by_phase.get("p0-seal", [])
        expected_counts = {
            "inventoryMutationCount": len(inventory_times),
            "firstInventoryMutationAt": min(inventory_times).isoformat()
            if inventory_times else None,
            "inventoryMutationCompletedAt": max(inventory_times).isoformat()
            if inventory_times else None,
            "preApprovalWriteCount": len(preapproval_times),
            "firstPreApprovalWriteAt": min(preapproval_times).isoformat()
            if preapproval_times else None,
            "lastPreApprovalWriteAt": max(preapproval_times).isoformat()
            if preapproval_times else None,
        }
        for field, expected in expected_counts.items():
            actual = claims.get(field)
            if field.endswith("At") and expected is not None:
                if parsed_timestamp(actual) != parsed_timestamp(expected):
                    errors.append(f"{label}.{field} does not match write events")
            elif actual != expected:
                errors.append(f"{label}.{field} does not match write events")
        if claims.get("approvedContentFileSetSha256") != approved_content_digest:
            errors.append(f"{label}.approvedContentFileSetSha256 mismatch")
        if claims.get("normalizationRule") != "strip-fixed-p0-approval-procedure-v1":
            errors.append(f"{label}.normalizationRule is invalid")
        fixed_at = parsed_timestamp(claims.get("fixedMetadataWriteAt"))
        payload_at = parsed_timestamp(claims.get("approvalPayloadPreparedAt"))
        freeze_at = parsed_timestamp(claims.get("freezeCompletedAt"))
        record_at = parsed_timestamp(claims.get("postFreezeRecordWriteAt"))
        first_apply = parsed_timestamp(claims.get("firstApplyWriteAt"))
        last_apply = parsed_timestamp(claims.get("lastApplyWriteAt"))
        seal_at = parsed_timestamp(claims.get("sealCompletedAt"))
        if metadata_times and fixed_at != min(metadata_times):
            errors.append(f"{label}.fixedMetadataWriteAt must equal first metadata write")
        if freeze_times and freeze_at != freeze_times[0]:
            errors.append(f"{label}.freezeCompletedAt must equal candidate freeze event")
        if record_times and record_at != record_times[0]:
            errors.append(f"{label}.postFreezeRecordWriteAt mismatch")
        if apply_times and (first_apply != min(apply_times) or last_apply != max(apply_times)):
            errors.append(f"{label}: canonical apply time bounds mismatch")
        if seal_times and seal_at != seal_times[0]:
            errors.append(f"{label}.sealCompletedAt mismatch")
        start_presentation = parsed_timestamp(start_binding.get("presentationAt"))
        start_response = parsed_timestamp(start_binding.get("humanResponseAt"))
        start_verified = parsed_timestamp(start_binding.get("verificationCompletedAt"))
        contract_presentation = parsed_timestamp(contract_binding.get("presentationAt"))
        contract_response = parsed_timestamp(contract_binding.get("humanResponseAt"))
        contract_verified = parsed_timestamp(contract_binding.get("verificationCompletedAt"))
        chronology = [started, observed, start_presentation, start_response, start_verified]
        if any(value is None for value in chronology) or not (
                started <= observed <= start_presentation < start_response <= start_verified):
            errors.append(f"{label}: P0-start monitoring/approval chronology invalid")
        if preapproval_times and (start_verified is None or payload_at is None
                                  or min(preapproval_times) < start_verified
                                  or max(preapproval_times) > payload_at):
            errors.append(f"{label}: preapproval writes are outside authorized window")
        tail = [payload_at, contract_presentation, contract_response, contract_verified,
                fixed_at, freeze_at, record_at, first_apply, last_apply, seal_at, completed]
        if any(value is None for value in tail) or not (
                payload_at < contract_presentation < contract_response <= contract_verified
                <= fixed_at <= freeze_at <= record_at <= first_apply <= last_apply
                <= seal_at <= completed):
            errors.append(f"{label}: P0 contract/freeze/record/apply/seal chronology invalid")
        record_ref = claims.get("p0ContractRecord")
        record_events = events_by_phase.get("p0-postfreeze-record", [])
        if not isinstance(record_ref, dict) or set(record_ref) != {"path", "sha256"} \
                or len(record_events) != 1 or record_events[0].get("path") != record_ref.get("path") \
                or record_events[0].get("after", {}).get("sha256") != record_ref.get("sha256"):
            errors.append(f"{label}.p0ContractRecord does not bind the post-freeze event")
        validate_snapshot_binding(
            root, claims.get("candidateSnapshot"), result_ref, result_baseline,
            result_records, entries, "p0", target_roots, errors,
            f"{label}.candidateSnapshot")
    else:
        d5_binding = approval("d5Approval")
        staging_times = times_by_phase.get("d5-staging", [])
        sync_times = times_by_phase.get("d5-sync", [])
        allowed_times = times_by_phase.get("d5-allowed-diff", [])
        post_times = times_by_phase.get("d5-post-sync-manifest", [])
        seal_times = times_by_phase.get("d5-seal", [])
        first_sync = parsed_timestamp(claims.get("firstSyncWriteAt"))
        last_sync = parsed_timestamp(claims.get("lastSyncWriteAt"))
        allowed_at = parsed_timestamp(claims.get("allowedDiffArtifactCreatedAt"))
        post_at = parsed_timestamp(claims.get("postSyncManifestCreatedAt"))
        seal_at = parsed_timestamp(claims.get("sealCompletedAt"))
        if sync_times and (first_sync != min(sync_times) or last_sync != max(sync_times)):
            errors.append(f"{label}: D5 sync time bounds mismatch")
        if allowed_times and allowed_at != allowed_times[0]:
            errors.append(f"{label}.allowedDiffArtifactCreatedAt mismatch")
        if post_times and post_at != post_times[0]:
            errors.append(f"{label}.postSyncManifestCreatedAt mismatch")
        if seal_times and seal_at != seal_times[0]:
            errors.append(f"{label}.sealCompletedAt mismatch")
        d5_presentation = parsed_timestamp(d5_binding.get("presentationAt"))
        d5_response = parsed_timestamp(d5_binding.get("humanResponseAt"))
        d5_verified = parsed_timestamp(d5_binding.get("verificationCompletedAt"))
        tail_times = ([min(staging_times)] if staging_times else []) + [
            first_sync, last_sync, allowed_at, post_at, seal_at, completed]
        if any(value is None for value in (
                started, observed, d5_presentation, d5_response, d5_verified,
                *tail_times)) or not (
                    started <= observed <= d5_presentation < d5_response <= d5_verified
                    <= min(staging_times) <= first_sync <= last_sync <= allowed_at
                    <= post_at <= seal_at <= completed):
            errors.append(f"{label}: D5 monitoring/approval/sync/seal chronology invalid")
        if claims.get("allowedDiffRule") != "d5-fixed-allowlist-v1":
            errors.append(f"{label}.allowedDiffRule is invalid")
        allowed_loaded = exact_artifact_ref(
            root, claims.get("allowedDiffArtifact"), errors,
            f"{label}.allowedDiffArtifact")
        allowed_changes: Any = None
        if allowed_loaded is not None:
            allowed_data = allowed_loaded[1]
            if set(allowed_data) != {"changes"} or not isinstance(
                    allowed_data.get("changes"), list):
                errors.append(f"{label}.allowedDiffArtifact must be a closed changes object")
            else:
                allowed_changes = allowed_data["changes"]
                if allowed_loaded[0].read_bytes() != canonical_json_bytes(allowed_data):
                    errors.append(f"{label}.allowedDiffArtifact must use canonical JSON bytes")
                if allowed_loaded[0].read_bytes() != canonical_json_bytes(allowed_data):
                    errors.append(f"{label}.allowedDiffArtifact is not canonical")
        expected_changes: list[dict[str, Any]] = []
        source_states, result_states = (
            manifest_file_states(source_records), manifest_file_states(result_records))
        post_rel = str(post_sync_ref.get("path") if isinstance(post_sync_ref, dict) else "")
        for path in sorted(set(source_states) | set(result_states)):
            before = source_states.get(path, absent_file_state())
            after = result_states.get(path, absent_file_state())
            if before == after:
                continue
            rule_id = _expected_d5_rule_id(
                path, manifest_rel, post_rel, formal_paths or set(), first_wp_path)
            if rule_id is None:
                errors.append(f"{label}: changed path has no fixed D5 rule: {path}")
                rule_id = "<INVALID>"
            expected_changes.append({
                "path": path, "beforeSha256": before.get("sha256"),
                "afterSha256": after.get("sha256"), "ruleId": rule_id,
            })
        if allowed_changes != expected_changes:
            errors.append(f"{label}.allowedDiffArtifact does not exact-cover B1 -> B2")
        if claims.get("allowedDiffSha256") != canonical_json_sha256(
                allowed_changes if isinstance(allowed_changes, list) else []):
            errors.append(f"{label}.allowedDiffSha256 mismatch")
        if claims.get("postSyncManifest") != post_sync_ref:
            errors.append(f"{label}.postSyncManifest mismatch")
        validate_snapshot_binding(
            root, claims.get("resultSnapshot"), result_ref, result_baseline,
            result_records, entries, "d5", target_roots, errors,
            f"{label}.resultSnapshot")

    pv_ref = proof.get("provenanceVerification")
    if not isinstance(pv_ref, dict) or set(pv_ref) != {"id", "path", "sha256"}:
        errors.append(f"{label}.provenanceVerification has unknown/missing fields")
        return attestation
    expected_pv_id = rf"PV-{prefix}-TRANSITION-[A-Z0-9][A-Z0-9._-]*"
    if not isinstance(pv_ref.get("id"), str) or re.fullmatch(
            expected_pv_id, pv_ref.get("id", "")) is None:
        errors.append(f"{label}.provenanceVerification.id is invalid")
    expected_subject = {
        "id": attestation_ref.get("id"), "path": attestation_ref.get("path"),
        "sha256": attestation_ref.get("sha256"),
    }
    external_claims = {
        "kind": "lifecycle-transition-external-v1",
        "transitionType": transition_type,
        "attestationId": attestation_ref.get("id"),
        "attestationPath": attestation_ref.get("path"),
        "attestationSha256": attestation_ref.get("sha256"),
        "actual": claims,
    }
    pv = validate_provenance_verification(
        root, {"path": pv_ref.get("path"), "sha256": pv_ref.get("sha256")},
        "lifecycle-transition-attestation", expected_subject, external_claims,
        provenance_runtime, errors, f"{label}.provenanceVerification")
    if pv is not None and pv.get("id") != pv_ref.get("id"):
        errors.append(f"{label}.provenanceVerification.id does not match artifact")
    return attestation


def validate_p0_transition_capsule(
        root: Path, capsule_path: Path, provenance_config: Path,
        *, fresh_authenticate: bool = False) -> dict[str, Any]:
    """Standalone post-P0 D4 admission check for one sanitized capsule.

    This intentionally validates only the P0 lifecycle proof needed before a
    post-P0 lane may run.  The lane's policy/request/attestation is validated by
    the outer D4 admission path.  Keeping this boundary explicit avoids treating
    a self-authored capsule as transition authority.
    """
    del fresh_authenticate  # Signature verification below is always performed.
    errors: list[str] = []
    root = root.resolve()
    try:
        capsule_path = capsule_path.resolve(strict=True)
        capsule_rel = capsule_path.relative_to(root).as_posix()
    except (OSError, ValueError) as exc:
        return {"pass": False, "errors": [
            f"capsule must be an existing file inside project root: {exc}"]}
    capsule = load_json(capsule_path, errors, "D4 capsule") or {}
    scope = capsule.get("auditScope") if isinstance(capsule, dict) else None
    if not isinstance(scope, dict) or scope.get("kind") != "post-p0-d4-v1":
        errors.append("standalone lifecycle validation accepts only post-p0-d4-v1")
        return {"pass": False, "errors": errors, "capsule": capsule_rel}
    if scope.get("mode") not in {"full", "delta"}:
        errors.append("post-P0 D4 audit mode must be full or delta")
    candidate_ref = capsule.get("candidate")
    source_ref = scope.get("sourceBaseline")
    if not isinstance(candidate_ref, dict) or not isinstance(source_ref, dict):
        errors.append("post-P0 capsule requires candidate and sourceBaseline references")
        return {"pass": False, "errors": errors, "capsule": capsule_rel}
    if not str(candidate_ref.get("id", "")).startswith("P0-CAND-"):
        errors.append("post-P0 capsule candidate must be P0-CAND-*")
    if not str(source_ref.get("id", "")).startswith("B0-"):
        errors.append("post-P0 capsule sourceBaseline must be B0-*")

    # The operator config path and all runners are validated without applying
    # the separate W0 copied-entrypoint bootstrap contract.  This command runs
    # inside the D4 sanitized runtime, not inside the W0 receiver capsule.
    config_preview = strict_json_file(
        provenance_config, errors, "provenance verifier config")
    installed_raw = ((config_preview or {}).get("w0ValidatorRuntime") or {}).get(
        "installedSkillRoot") if isinstance((config_preview or {}).get(
            "w0ValidatorRuntime"), dict) else None
    try:
        configured_skill_root = Path(str(installed_raw)).resolve(strict=True)
    except OSError:
        configured_skill_root = root / "__invalid_installed_skill_root__"
        errors.append("provenance config installedSkillRoot cannot be resolved")
    runtime = load_provenance_runtime(
        provenance_config, root, configured_skill_root, errors,
        require_w0_execution=False)

    candidate_loaded = verify_ref(root, candidate_ref, errors, "P0 candidate")
    source_loaded = verify_ref(root, source_ref, errors, "B0 source baseline")
    if candidate_loaded is None or source_loaded is None:
        return {"pass": False, "errors": errors, "capsule": capsule_rel}
    candidate, source = candidate_loaded[1], source_loaded[1]
    for label, manifest, expected_stage, ref in (
            ("P0 candidate", candidate, "P0-CANDIDATE", candidate_ref),
            ("B0 source", source, "B0", source_ref)):
        if manifest.get("schemaVersion") != "1.0.0" \
                or manifest.get("stage") != expected_stage \
                or manifest.get("baselineId") != ref.get("id") \
                or manifest.get("fileSetSha256") != ref.get("fileSetSha256"):
            errors.append(f"{label}: identity/stage/fileSet binding mismatch")
        revision = manifest.get("revision")
        if not isinstance(revision, dict) or revision.get("kind") != "snapshot":
            errors.append(f"{label}: lifecycle v1 requires an immutable snapshot")
        if manifest.get("p0Transition") is not None:
            errors.append(f"{label}.p0Transition must be null before post-P0 D4")
    if candidate.get("parentBaselineId") != source.get("baselineId"):
        errors.append("P0 candidate.parentBaselineId must equal capsule B0 source")
    if candidate.get("project") != source.get("project") \
            or candidate.get("prefix") != source.get("prefix"):
        errors.append("P0 candidate/B0 source project identity mismatch")

    source_records = validate_file_records(
        root, source, errors, "B0 source", verify_current=False)
    candidate_records = validate_file_records(
        root, candidate, errors, "P0 candidate", verify_current=False)
    source_content = verify_historical_files(
        root, root, source, source_records, errors, "B0 source", None)
    candidate_content = verify_historical_files(
        root, root, candidate, candidate_records, errors, "P0 candidate", None)
    inventory = validate_p0_closure_transition(
        root, source_content, candidate_content, errors)

    proof_ref = capsule.get("p0LifecycleTransition")
    if not isinstance(proof_ref, dict) or set(proof_ref) != {
            "attestation", "writeLog", "provenanceVerification"}:
        errors.append("post-P0 capsule requires one closed p0LifecycleTransition proof")
        return {"pass": False, "errors": errors, "capsule": capsule_rel}
    att_ref = proof_ref.get("attestation")
    att_loaded = verify_ref(root, att_ref, errors, "P0 transition attestation")
    claims = (att_loaded[1].get("claims") if att_loaded is not None else None)
    if not isinstance(claims, dict) or claims.get("kind") != "p0-transition-v1":
        errors.append("P0 transition attestation claims are missing/invalid")
        claims = {}

    def capture_preview(binding_name: str) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
        binding = claims.get(binding_name)
        if not isinstance(binding, dict):
            errors.append(f"P0 transition {binding_name} binding is missing")
            return {}, {}, {}
        verification_ref = binding.get("verification")
        loaded_pv = verify_ref(
            root, verification_ref, errors, f"P0 transition {binding_name} PV")
        pv = loaded_pv[1] if loaded_pv is not None else {}
        subject = pv.get("subject") if isinstance(pv.get("subject"), dict) else {}
        loaded_capture = verify_ref(
            root, subject, errors, f"P0 transition {binding_name} capture")
        capture = loaded_capture[1] if loaded_capture is not None else {}
        return binding, pv, capture

    start_binding, start_pv_preview, start_capture_preview = capture_preview("p0Start")
    contract_binding, contract_pv_preview, contract_capture_preview = capture_preview(
        "p0Contract")
    management_wp = ((start_capture_preview.get("scope") or {}).get("p0ManagementWp")
                     if isinstance(start_capture_preview.get("scope"), dict) else None)
    start_scope = {
        "kind": "p0-start-v1",
        "inventory": {
            "path": "PROGRESS.md", "section": "Proposed P0 closure inventory",
            "fileSha256": inventory.get("progressSha256") if inventory else None,
            "inventoryId": inventory.get("inventoryId") if inventory else None,
            "sourceItemIds": inventory.get("sourceIds") if inventory else None,
        },
        "p0ManagementWp": management_wp,
        "productContentMutation": "inventory-rows-only",
        "fixedProcedure": "p0-standard-six-step-v1", "additionalScope": False,
    }
    contract_scope = {
        "kind": "p0-contract-v1",
        "p0StartApprovalId": start_binding.get("approvalId"),
        "inventoryId": inventory.get("inventoryId") if inventory else None,
        "closedSourceItemIds": inventory.get("sourceIds") if inventory else None,
        "p0ManagementWp": management_wp, "approvalOutcome": "contract-approved",
        "additionalScope": False,
    }
    contract_capture_ref = (contract_pv_preview.get("subject")
                            if isinstance(contract_pv_preview.get("subject"), dict)
                            else {})
    approved_digest_hint = ((contract_capture_preview.get("plannedCandidate") or {}).get(
        "approvedContentFileSetSha256")
        if isinstance(contract_capture_preview.get("plannedCandidate"), dict) else "")
    approved_digest = p0_approved_content_digest(
        candidate_content, str(contract_binding.get("approvalId") or ""),
        str(contract_capture_preview.get("approver") or ""),
        str(contract_capture_preview.get("occurredAt") or ""),
        str(contract_capture_ref.get("path") or ""),
        str(start_binding.get("approvalId") or ""),
        str(inventory.get("inventoryId") if inventory else ""),
        list(inventory.get("sourceIds") if inventory else []),
        management_wp if isinstance(management_wp, dict) else {},
        str(candidate.get("baselineId") or ""), str(approved_digest_hint or ""),
        errors)
    planned_candidate = {
        "id": candidate.get("baselineId"),
        "approvedContentFileSetSha256": approved_digest,
        "sourceBaselineRevision": source.get("revision"),
        "normalizationRule": "strip-fixed-p0-approval-procedure-v1",
    }

    capture_results: dict[str, dict[str, Any] | None] = {}
    approval_pvs: dict[str, dict[str, Any] | None] = {}
    for name, gate, target_key, target, expected_scope, preview_pv in (
            ("p0Start", "p0-start", "targetBaseline",
             baseline_approval_target(source_ref, source), start_scope,
             start_pv_preview),
            ("p0Contract", "p0-contract", "plannedCandidate",
             planned_candidate, contract_scope, contract_pv_preview)):
        subject = preview_pv.get("subject") if isinstance(
            preview_pv.get("subject"), dict) else {}
        result = validate_human_capture(
            root, subject, gate, target_key, target, expected_scope, errors,
            f"P0 transition {name} capture")
        capture_results[name] = result
        expected_claims = result.get("claims") if isinstance(result, dict) else {}
        binding = claims.get(name) if isinstance(claims.get(name), dict) else {}
        pv = validate_provenance_verification(
            root, binding.get("verification"), "human-approval-capture",
            subject, expected_claims, runtime, errors,
            f"P0 transition {name} provenance")
        approval_pvs[name] = pv
        expected_binding = transition_approval_binding(
            binding.get("approvalId"), binding.get("verification"), result, pv)
        if binding != expected_binding:
            errors.append(f"P0 transition {name} approval binding mismatch")

    validate_p0_management_transition(
        source_content, candidate_content, start_scope, inventory, errors,
        approval_id=str(contract_binding.get("approvalId") or ""),
        candidate_id=str(candidate.get("baselineId") or ""),
        capture_path=str(contract_capture_ref.get("path") or ""))
    contract_record_ref = claims.get("p0ContractRecord")
    if isinstance(contract_record_ref, dict):
        validate_approval_record(
            root, contract_record_ref.get("path"), contract_record_ref.get("sha256"),
            contract_binding.get("approvalId"), "p0-contract", "targetBaseline",
            baseline_approval_target(candidate_ref, candidate), contract_scope,
            contract_capture_ref, contract_binding.get("verification"), errors,
            "P0 transition contract record",
            capture_result=capture_results.get("p0Contract"))
    immutable_paths: set[str] = set()
    gate1_ref = source.get("gddGate1")
    gate1_loaded = verify_ref(root, gate1_ref, errors, "B0 Gate1 record") \
        if isinstance(gate1_ref, dict) else None
    if gate1_loaded is not None:
        target = gate1_loaded[1].get("targetArtifact")
        if isinstance(target, dict) and isinstance(target.get("path"), str):
            immutable_paths.add(target["path"])
    registry = ((source.get("admission") or {}).get("d15TriggerRegistry")
                if isinstance(source.get("admission"), dict) else None)
    if isinstance(registry, dict) and isinstance(registry.get("path"), str):
        immutable_paths.add(registry["path"])
    proof = {"transitionType": "p0", **proof_ref}
    validate_lifecycle_transition(
        root, proof, "p0", source_ref, source, source_records,
        candidate_ref, candidate, candidate_records, {
            "p0Start": transition_approval_binding(
                start_binding.get("approvalId"), start_binding.get("verification"),
                capture_results.get("p0Start"), approval_pvs.get("p0Start")),
            "p0Contract": transition_approval_binding(
                contract_binding.get("approvalId"),
                contract_binding.get("verification"),
                capture_results.get("p0Contract"), approval_pvs.get("p0Contract")),
        }, runtime, errors, "p0LifecycleTransition",
        approved_content_digest=approved_digest, p0_inventory=inventory,
        p0_management_wp_path=(management_wp.get("path")
                               if isinstance(management_wp, dict) else None),
        immutable_paths=immutable_paths,
        result_artifact_paths={str(contract_record_ref.get("path"))}
        if isinstance(contract_record_ref, dict) else set())
    return {"pass": not errors, "errors": errors, "capsule": capsule_rel,
            "transitionType": "p0"}


def validate(
        root: Path, prefix: str, package_path: Path,
        source_root: Path | None = None,
        provenance_config: Path | None = None,
        installed_skill_root_path: Path | None = None) -> dict[str, Any]:
    global INSTALLED_SKILL_ROOT
    errors: list[str] = []
    checked: list[str] = []
    root = root.resolve()
    source_root = (source_root or root).resolve()
    if installed_skill_root_path is None or not installed_skill_root_path.is_absolute():
        errors.append("--installed-skill-root must be an explicit absolute path")
        skill_root = Path(__file__).resolve().parent.parent
    else:
        try:
            skill_root = installed_skill_root_path.resolve(strict=True)
        except OSError as exc:
            errors.append(f"--installed-skill-root cannot be resolved: {exc}")
            skill_root = installed_skill_root_path.resolve()
        for rel in ("SKILL.md", "scripts/validate_d5_acceptance.py",
                    "scripts/gen_index.py", "scripts/state_readiness.py",
                    "scripts/strict_json.py"):
            if not (skill_root / rel).is_file():
                errors.append(f"--installed-skill-root missing canonical {rel}")
    INSTALLED_SKILL_ROOT = skill_root
    package = load_json(package_path, errors, "W0 package")
    if package is None:
        return {"pass": False, "errors": errors, "checked": checked}
    checked.append(str(package_path))
    # W0 v1 is deliberately offline.  Reject a reachable query-mode PV before
    # even parsing runtime configuration, probing a binary, or invoking a
    # verifier adapter.  This preserves the pre-permission no-network boundary.
    if prescan_forbidden_query_provenance(root, package, errors):
        return {"pass": False, "errors": errors, "checked": checked}
    provenance_runtime = load_provenance_runtime(
        provenance_config, root, skill_root, errors)

    if package.get("schemaVersion") != "1.0.0":
        errors.append("W0 package.schemaVersion must be 1.0.0")
    if package.get("acceptanceProvenanceMode") != \
            "offline-pinned-signature-only-v1":
        errors.append(
            "W0 package.acceptanceProvenanceMode must be "
            "offline-pinned-signature-only-v1")
    expected_package_keys = {
        "schemaVersion", "packageId", "project", "prefix", "createdAt",
        "acceptanceProvenanceMode",
        "gddGate1", "gddD5Transformation", "d15Measurements", "d5Approval", "p0", "approvalCaptures",
        "approvalVerifications", "lifecycleTransitions",
        "baselines", "postSyncManifest",
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

    gate1_package = package.get("gddGate1")
    gdd_transformation = package.get("gddD5Transformation")
    d5 = package.get("d5Approval")
    p0 = package.get("p0")
    capture_refs = package.get("approvalCaptures")
    verification_refs = package.get("approvalVerifications")
    lifecycle_transitions = package.get("lifecycleTransitions")
    d15_bindings = package.get("d15Measurements")
    if not isinstance(gate1_package, dict) or set(gate1_package) != {
            "id", "recordPath", "recordSha256"}:
        errors.append("gddGate1 has unknown/missing fields")
        gate1_package = {}
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
    if not isinstance(capture_refs, dict) or set(capture_refs) != {
            "gddGate1", "p0Start", "p0Contract", "d5"}:
        errors.append("approvalCaptures must contain exactly all four gate captures")
        capture_refs = {}
    if not isinstance(verification_refs, dict) or set(verification_refs) != {
            "gddGate1", "p0Start", "p0Contract", "d5"}:
        errors.append("approvalVerifications must contain exactly all four gate verifications")
        verification_refs = {}
    if not isinstance(lifecycle_transitions, dict) or set(lifecycle_transitions) != {
            "p0", "d5"}:
        errors.append("lifecycleTransitions must contain exactly p0/d5")
        lifecycle_transitions = {}
    for transition_name in ("p0", "d5"):
        transition_ref = lifecycle_transitions.get(transition_name)
        if not isinstance(transition_ref, dict) or set(transition_ref) != {
                "transitionType", "attestation", "provenanceVerification", "writeLog"}:
            errors.append(
                f"lifecycleTransitions.{transition_name} has unknown/missing fields")
            continue
        if transition_ref.get("transitionType") != transition_name:
            errors.append(
                f"lifecycleTransitions.{transition_name}.transitionType mismatch")
    if not isinstance(d15_bindings, list):
        errors.append("d15Measurements must be an array")
        d15_bindings = []
    d5_id = d5.get("id")
    ids = [gate1_package.get("id"), p0.get("startApprovalId"),
           p0.get("contractApprovalId"), d5_id]
    if any(not isinstance(value, str) or not value.strip() for value in ids):
        errors.append("Gate1, P0 start, P0 contract, and D5 approval IDs must be non-empty")
    elif len({identity_key(value) for value in ids}) != 4:
        errors.append("Gate1, P0 start, P0 contract, and D5 approval IDs must be distinct")
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
    capture_values: list[dict[str, Any]] = []
    for name in ("gddGate1", "p0Start", "p0Contract", "d5"):
        ref = capture_refs.get(name)
        if not isinstance(ref, dict) or set(ref) != {"id", "path", "sha256"}:
            errors.append(f"approvalCaptures.{name} has unknown/missing fields")
        else:
            capture_values.append(ref)
    for field in ("id", "path", "sha256"):
        values = [ref.get(field) for ref in capture_values]
        if len(values) != 4 or len({identity_key(value) for value in values}) != 4:
            errors.append(f"all four approval capture {field} values must be distinct")
    verification_values: list[dict[str, Any]] = []
    for name in ("gddGate1", "p0Start", "p0Contract", "d5"):
        ref = verification_refs.get(name)
        if not isinstance(ref, dict) or set(ref) != {"path", "sha256"}:
            errors.append(f"approvalVerifications.{name} has unknown/missing fields")
        else:
            verification_values.append(ref)
    for field in ("path", "sha256"):
        values = [ref.get(field) for ref in verification_values]
        if len(values) != 4 or len({identity_key(value) for value in values}) != 4:
            errors.append(f"all four approval verification {field} values must be distinct")
    gate_record_refs = [
        {"path": gate1_package.get("recordPath"),
         "sha256": gate1_package.get("recordSha256")},
        {"path": p0.get("startApprovalRecordPath"),
         "sha256": p0.get("startApprovalRecordSha256")},
        {"path": p0.get("contractApprovalRecordPath"),
         "sha256": p0.get("contractApprovalRecordSha256")},
        {"path": d5.get("recordPath"), "sha256": d5.get("recordSha256")},
    ]
    for field in ("path", "sha256"):
        values = [ref.get(field) for ref in gate_record_refs]
        if any(not isinstance(value, str) or not value for value in values) \
                or len({identity_key(value) for value in values}) != 4:
            errors.append(f"all four gate record {field} values must be distinct")

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
    expected_gate1_baseline_ref = {
        "id": gate1_package.get("id"), "path": gate1_package.get("recordPath"),
        "sha256": gate1_package.get("recordSha256"),
    }
    for name, baseline in (("B0", b0), ("B1", b1), ("B2", b2)):
        if baseline and baseline.get("gddGate1") != expected_gate1_baseline_ref:
            errors.append(f"{name}.gddGate1 must equal the package-pinned Gate1 record")
        if baseline and baseline.get("d15Measurements") != d15_bindings:
            errors.append(f"{name}.d15Measurements must equal the W0 package bindings")
    package_p0_transition = lifecycle_transitions.get("p0")
    expected_baseline_p0_transition = ({
        key: package_p0_transition.get(key)
        for key in ("attestation", "writeLog", "provenanceVerification")
    } if isinstance(package_p0_transition, dict) else None)
    for name, baseline in (("B1", b1), ("B2", b2)):
        if baseline and baseline.get("p0Transition") != expected_baseline_p0_transition:
            errors.append(f"{name}.p0Transition must equal the W0 P0 transition proof")
    b0_files: dict[str, dict[str, Any]] = {}
    b1_files: dict[str, dict[str, Any]] = {}
    b2_files: dict[str, dict[str, Any]] = {}
    b0_content: dict[str, bytes] = {}
    b1_content: dict[str, bytes] = {}
    if b0:
        b0_files = validate_baseline(
            root, source_root, b0, errors, "B0", "B0", (b0_ref or {}).get("id"),
            project, prefix, False, b0_content, provenance_runtime)
    if b1:
        b1_files = validate_baseline(
            root, source_root, b1, errors, "B1", "B1", (b1_ref or {}).get("id"), project, prefix,
            False, b1_content, provenance_runtime)
    if b2:
        b2_files = validate_baseline(
            root, source_root, b2, errors, "B2", "B2", (b2_ref or {}).get("id"),
            project, prefix, True, provenance_runtime=provenance_runtime)
    if b1 and b2:
        validate_promotion_chain(
            root, source_root, b0, b1, b2, errors, project, prefix,
            provenance_runtime)
    p0_inventory = (validate_p0_closure_transition(root, b0_content, b1_content, errors)
                    if b0 and b1 else None)
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
    capsule_refs: list[dict[str, Any]] = []
    package_attestation_refs: list[dict[str, Any]] = []
    package_attestation_ids: list[Any] = []
    package_request_refs: list[Any] = []
    package_provenance_refs: list[Any] = []
    package_lane_run_ids: list[Any] = []
    package_execution_ids: list[Any] = []
    package_session_ids: list[Any] = []
    package_modes: list[Any] = []
    capsule_p0_transition_refs: list[Any] = []
    if not isinstance(records, list) or len(records) != 3:
        errors.append("postP0D4Records requires exactly three records")
        records = []
    for index, record in enumerate(records):
        label = f"postP0D4Records[{index}]"
        if not isinstance(record, dict):
            errors.append(f"{label} must be an object")
            continue
        if set(record) != {
                "id", "auditTrack", "path", "sha256", "auditCapsule",
                "auditRequest", "auditorAttestation", "provenanceVerification",
                "candidateBaseline",
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
        if (type(record.get("criticalCount")) is not int
                or type(record.get("majorCount")) is not int
                or record.get("criticalCount") != 0
                or record.get("majorCount") != 0):
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
        capsule_ref = record.get("auditCapsule")
        if isinstance(capsule_ref, dict):
            capsule_refs.append(capsule_ref)
        capsule = (validate_d4_capsule(
            root, capsule_ref, candidate_ref, prefix, provenance_runtime,
            errors, f"{label}.auditCapsule")
            if isinstance(candidate_ref, dict) else None)
        if isinstance(capsule, dict):
            capsule_p0_transition_refs.append(capsule.get("p0LifecycleTransition"))
        request_ref = record.get("auditRequest")
        if isinstance(request_ref, dict):
            package_request_refs.append(request_ref)
        request = (validate_d4_request(
            root, request_ref, track, candidate_ref, capsule_ref, capsule,
            errors, f"{label}.auditRequest")
            if isinstance(candidate_ref, dict) else None)
        if request is not None:
            package_modes.append(request.get("_core", {}).get("mode"))
        attestation_ref = record.get("auditorAttestation")
        if isinstance(attestation_ref, dict):
            package_attestation_refs.append(attestation_ref)
        attestation = validate_d4_attestation(
            root, attestation_ref, track, capsule_ref, capsule,
            {"path": record.get("path"), "sha256": record.get("sha256")},
            request_ref, request, errors, f"{label}.auditorAttestation")
        if attestation is not None:
            package_attestation_ids.append(attestation.get("id"))
            package_lane_run_ids.append(attestation.get("laneRunId"))
            package_execution_ids.append(attestation.get("executionId"))
            package_session_ids.append(attestation.get("sessionId"))
        provenance_ref = record.get("provenanceVerification")
        if isinstance(provenance_ref, dict):
            package_provenance_refs.append(provenance_ref)
        loaded_pv = (verify_ref(root, provenance_ref, errors,
                                f"{label}.provenanceVerification")
                     if isinstance(provenance_ref, dict) else None)
        if loaded_pv is not None and isinstance(attestation, dict) \
                and isinstance(attestation.get("_claimsBase"), dict):
            provider_policy = loaded_pv[1].get("claims", {}).get("providerPolicy") \
                if isinstance(loaded_pv[1].get("claims"), dict) else None
            expected_claims = dict(attestation["_claimsBase"],
                                   providerPolicy=provider_policy)
            attestation["_providerPolicy"] = provider_policy
            validate_provenance_verification(
                root, provenance_ref, "d4-auditor-attestation",
                {"id": attestation.get("id"),
                 "path": attestation_ref.get("path")
                 if isinstance(attestation_ref, dict) else None,
                 "sha256": attestation_ref.get("sha256")
                 if isinstance(attestation_ref, dict) else None},
                expected_claims, provenance_runtime, errors,
                f"{label}.provenanceVerification")
        if raw_path is not None and isinstance(candidate_ref, dict):
            parse_d4_record(
                raw_path, record, candidate_ref, errors, label,
                capsule_ref=capsule_ref, attestation=attestation)
    if seen_tracks != required_tracks:
        errors.append("postP0D4Records must contain each audit track exactly once")
    if candidate_refs and any(ref != candidate_refs[0] for ref in candidate_refs[1:]):
        errors.append("postP0D4Records must all reference the same P0 candidate manifest")
    if capsule_refs and any(ref != capsule_refs[0] for ref in capsule_refs[1:]):
        errors.append("postP0D4Records must all reference the same D4 audit capsule")
    expected_capsule_p0_transition = None
    package_p0_transition = lifecycle_transitions.get("p0")
    if isinstance(package_p0_transition, dict):
        expected_capsule_p0_transition = {
            key: package_p0_transition.get(key)
            for key in ("attestation", "writeLog", "provenanceVerification")
        }
    if len(capsule_p0_transition_refs) != 3 or any(
            ref != expected_capsule_p0_transition
            for ref in capsule_p0_transition_refs):
        errors.append(
            "post-P0 D4 capsules must all bind the package P0 lifecycle transition")
    if len(package_modes) != 3 or len({identity_key(value) for value in package_modes}) != 1:
        errors.append("postP0D4Records must use one identical audit mode")
    for values, description in (
            (package_attestation_refs, "attestation refs"),
            (package_attestation_ids, "attestation IDs"),
            (package_request_refs, "request artifact refs"),
            (package_provenance_refs, "provenance verification refs"),
            (package_lane_run_ids, "lane run IDs"),
            (package_execution_ids, "execution IDs"),
            (package_session_ids, "session IDs")):
        if len(values) != 3 or len(values) != len(
                {identity_key(value) for value in values}):
            errors.append(f"postP0D4Records must use unique lane {description}")
    p0_candidate_ref = candidate_refs[0] if candidate_refs else {}
    p0_candidate_loaded = (verify_ref(root, p0_candidate_ref, errors, "P0 candidate reference")
                           if p0_candidate_ref else None)
    p0_candidate = p0_candidate_loaded[1] if p0_candidate_loaded else {}
    p0_content: dict[str, bytes] = {}
    p0_records: dict[str, dict[str, Any]] = {}
    if p0_candidate:
        p0_records = validate_file_records(
            root, p0_candidate, errors, "P0 candidate approval target", False)
        p0_content = verify_historical_files(
            root, source_root, p0_candidate, p0_records, errors,
            "P0 candidate approval target",
            ((provenance_runtime.get("w0ValidatorRuntime", {}).get(
                "_gitExecutable") or {}).get("_path")
             if isinstance(provenance_runtime, dict) else None))
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
    gdd_manifest_paths = {
        item.get("path", "").replace("\\", "/") for item in documents
        if isinstance(item, dict) and isinstance(item.get("path"), str)
        and item.get("path", "").replace("\\", "/").endswith("_gdd.md")}
    if len(gdd_manifest_paths) != 1:
        errors.append("docs manifest must identify exactly one immutable Gate1 GDD")
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
            for issue in scan_readiness_text(text, path.suffix):
                errors.append(
                    f"{rel}:{issue['line']}: unresolved D5 {issue['label']} {issue['token']}")
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

    last_approved = {
        header.get("Last approved") for _, header in formal.values()}
    if not formal:
        errors.append("no formal documents found in docs manifest")
    elif len(last_approved) != 1:
        errors.append("D5-promoted formal Last approved timestamps are not identical")

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
    first_wp_rel = (first_wp.get("path").replace("\\", "/")
                    if isinstance(first_wp.get("path"), str) else None)
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
                package_rel = package_path.relative_to(root).as_posix()
                wp_fields, wp_dupes = parse_named_bullets(section)
                expected_wp_fields = {
                    "Status": "Approved",
                    "Authorized by": str(d5_id or ""),
                    "Authorization baseline": str(b2.get("baselineId") or ""),
                    "Authorization evidence": package_rel,
                }
                for field, expected in expected_wp_fields.items():
                    actual = wp_fields.get(field, "").replace("\\", "/")
                    if field in wp_dupes or actual != expected:
                        errors.append(
                            f"first authorized WP {field} must uniquely equal {expected!r}")
                indexed = False
                for line in text.splitlines():
                    cells = gen_index.split_row(line)
                    if cells and wp_id in cells[0] and any(
                            cell.replace("`", "").strip().lower() == "approved" for cell in cells):
                        indexed = True
                        break
                if not indexed:
                    errors.append("first authorized WP package-index row must be Approved")

    # Approval IDs and local hashes are not approval by themselves. Reconstruct
    # all four closed targets/scopes, their challenge/statement/transcript chains,
    # and each machine record from independently hashed historical bytes.
    gdd_target = verified_gdd_target(documents, b0_content, b1_content, errors) or {}
    start_preview_loaded = verify_ref(
        root, {"path": p0.get("startApprovalRecordPath"),
               "sha256": p0.get("startApprovalRecordSha256")},
        errors, "P0 start approval preview")
    start_preview = start_preview_loaded[1] if start_preview_loaded else {}
    management_wp = (start_preview.get("scope", {}).get("p0ManagementWp", {})
                     if isinstance(start_preview.get("scope"), dict) else {})
    expected_inventory = ({
        "path": "PROGRESS.md", "section": "Proposed P0 closure inventory",
        "fileSha256": p0_inventory.get("progressSha256"),
        "inventoryId": p0_inventory.get("inventoryId"),
        "sourceItemIds": sorted(p0_inventory.get("sourceIds", [])),
    } if isinstance(p0_inventory, dict) else {})
    start_scope = {
        "kind": "p0-start-v1", "inventory": expected_inventory,
        "p0ManagementWp": management_wp,
        "productContentMutation": "inventory-rows-only",
        "fixedProcedure": "p0-standard-six-step-v1", "additionalScope": False,
    }
    closed_ids = sorted(p0_inventory.get("sourceIds", [])) \
        if isinstance(p0_inventory, dict) else []
    contract_scope = {
        "kind": "p0-contract-v1",
        "p0StartApprovalId": p0.get("startApprovalId"),
        "inventoryId": p0_inventory.get("inventoryId")
        if isinstance(p0_inventory, dict) else None,
        "closedSourceItemIds": closed_ids,
        "p0ManagementWp": management_wp,
        "approvalOutcome": "contract-approved", "additionalScope": False,
    }
    d5_scope = {
        "kind": "d5-v1", "firstWp": {"id": wp_id, "path": first_wp_rel},
        "authorization": "w0-handoff-only", "additionalScope": False,
    }
    gate1_preview_loaded = verify_ref(
        root, {"path": gate1_package.get("recordPath"),
               "sha256": gate1_package.get("recordSha256")},
        errors, "Gate1 approval preview")
    gate1_preview = gate1_preview_loaded[1] if gate1_preview_loaded else {}
    preview_scope = gate1_preview.get("scope") \
        if isinstance(gate1_preview.get("scope"), dict) else {}
    approved_intake_ref = preview_scope.get("approvedIntake")
    required_specs_ref = preview_scope.get("requiredSpecs")
    intake_loaded = (verify_ref(root, approved_intake_ref, errors, "Gate1 approved intake")
                     if isinstance(approved_intake_ref, dict) else None)
    required_specs_loaded = (verify_ref(
        root, required_specs_ref, errors, "Gate1 required specs")
        if isinstance(required_specs_ref, dict) else None)
    if intake_loaded is None:
        errors.append("Gate1 scope must bind an actual approved intake")
    if required_specs_loaded is None:
        errors.append("Gate1 scope must bind actual required_specs")
    if intake_loaded is not None and required_specs_loaded is not None:
        projection = derive_required_specs_projection(intake_loaded[1])
        if required_specs_loaded[1] != projection:
            errors.append("Gate1 required_specs is not the exact approved-intake projection")
    gdd_scope = {
        "kind": "gdd-gate1-v1", "decision": "approve-gdd-for-d1.5-and-d2",
        "approvedIntake": approved_intake_ref,
        "requiredSpecs": required_specs_ref,
        "additionalScope": False,
    }
    admission_registry = b0.get("admission", {}).get("d15TriggerRegistry") \
        if isinstance(b0.get("admission"), dict) else None
    if isinstance(admission_registry, dict) and isinstance(required_specs_ref, dict) \
            and {"path": admission_registry.get("path"),
                 "sha256": admission_registry.get("sha256")} != required_specs_ref:
        errors.append("Gate1 requiredSpecs must equal baseline admission registry")
    contract_preview_loaded = verify_ref(
        root, {"path": p0.get("contractApprovalRecordPath"),
               "sha256": p0.get("contractApprovalRecordSha256")},
        errors, "P0 contract approval preview")
    contract_preview = contract_preview_loaded[1] if contract_preview_loaded else {}
    contract_capture_ref = capture_refs.get("p0Contract")
    contract_capture_loaded = (verify_ref(
        root, {"path": contract_capture_ref.get("path"),
               "sha256": contract_capture_ref.get("sha256")},
        errors, "P0 contract capture preview")
        if isinstance(contract_capture_ref, dict) else None)
    contract_capture_preview = contract_capture_loaded[1] if contract_capture_loaded else {}
    planned_preview = contract_capture_preview.get("plannedCandidate")
    preview_digest = (planned_preview.get("approvedContentFileSetSha256")
                      if isinstance(planned_preview, dict) else "")
    calculated_digest = p0_approved_content_digest(
        p0_content, str(p0.get("contractApprovalId") or ""),
        str(contract_preview.get("approver") or ""),
        str(contract_preview.get("approvedAt") or ""),
        str(contract_capture_ref.get("path") if isinstance(contract_capture_ref, dict) else ""),
        str(p0.get("startApprovalId") or ""),
        str(p0_inventory.get("inventoryId") if isinstance(p0_inventory, dict) else ""),
        closed_ids, management_wp, str(p0_candidate.get("baselineId") or ""),
        str(preview_digest or ""), errors)
    planned_candidate = {
        "id": p0_candidate.get("baselineId"),
        "approvedContentFileSetSha256": calculated_digest,
        "sourceBaselineRevision": b0.get("revision"),
        "normalizationRule": "strip-fixed-p0-approval-procedure-v1",
    }
    capture_results = {
        "gddGate1": validate_human_capture(
            root, capture_refs.get("gddGate1"), "gdd-gate1", "targetArtifact",
            gdd_target, gdd_scope, errors, "Gate1 human approval capture"),
        "p0Start": validate_human_capture(
            root, capture_refs.get("p0Start"), "p0-start", "targetBaseline",
            baseline_approval_target(b0_ref, b0), start_scope, errors,
            "P0 start human approval capture"),
        "p0Contract": validate_human_capture(
            root, contract_capture_ref, "p0-contract", "plannedCandidate",
            planned_candidate, contract_scope, errors,
            "P0 contract human approval capture"),
        "d5": validate_human_capture(
            root, capture_refs.get("d5"), "d5", "targetBaseline",
            baseline_approval_target(b1_ref, b1), d5_scope, errors,
            "D5 human approval capture"),
    }
    for field, getter in (
            ("challenge IDs", lambda result: result.get("challenge", {}).get("id")),
            ("challenge refs", lambda result: result.get("capture", {}).get("challengeArtifact")),
            ("transcript IDs", lambda result: result.get("transcript", {}).get("id")),
            ("transcript refs", lambda result: result.get("capture", {}).get(
                "sourceInteractionRef", {}).get("transcriptArtifact")),
            ("interaction/message pairs", lambda result: [
                result.get("capture", {}).get("sourceInteractionRef", {}).get("interactionId"),
                result.get("capture", {}).get("sourceInteractionRef", {}).get("messageId")]),
            ("statement refs", lambda result: result.get("capture", {}).get("statementArtifact"))):
        values = [getter(result) for result in capture_results.values()
                  if isinstance(result, dict)]
        if len(values) != 4 or len({identity_key(value) for value in values}) != 4:
            errors.append(f"all four approval {field} must be distinct and non-reused")

    approval_pvs: dict[str, dict[str, Any] | None] = {}
    for name, result in capture_results.items():
        capture_ref = capture_refs.get(name)
        subject = ({"id": capture_ref.get("id"), "path": capture_ref.get("path"),
                    "sha256": capture_ref.get("sha256")}
                   if isinstance(capture_ref, dict) else {})
        claims = result.get("claims") if isinstance(result, dict) else {}
        approval_pvs[name] = validate_provenance_verification(
            root, verification_refs.get(name), "human-approval-capture",
            subject, claims if isinstance(claims, dict) else {}, provenance_runtime,
            errors, f"approvalVerifications.{name}")
    for field, getter in (
            ("IDs", lambda pv: pv.get("id")),
            ("source artifacts", lambda pv: pv.get("sourceArtifact"))):
        values = [getter(pv) for pv in approval_pvs.values() if isinstance(pv, dict)]
        if len(values) != 4 or len({identity_key(value) for value in values}) != 4:
            errors.append(f"all four approval provenance {field} must be distinct and non-reused")

    gate1_record = validate_approval_record(
        root, gate1_package.get("recordPath"), gate1_package.get("recordSha256"),
        gate1_package.get("id"), "gdd-gate1", "targetArtifact", gdd_target,
        gdd_scope, capture_refs.get("gddGate1"), verification_refs.get("gddGate1"),
        errors, "Gate1 approval record",
        capture_result=capture_results.get("gddGate1"))
    start_record = validate_approval_record(
        root, p0.get("startApprovalRecordPath"), p0.get("startApprovalRecordSha256"),
        p0.get("startApprovalId"), "p0-start", "targetBaseline",
        baseline_approval_target(b0_ref, b0), start_scope,
        capture_refs.get("p0Start"), verification_refs.get("p0Start"),
        errors, "P0 start approval record",
        capture_result=capture_results.get("p0Start"))
    contract_record = validate_approval_record(
        root, p0.get("contractApprovalRecordPath"),
        p0.get("contractApprovalRecordSha256"), p0.get("contractApprovalId"),
        "p0-contract", "targetBaseline",
        baseline_approval_target(p0_candidate_ref, p0_candidate), contract_scope,
        contract_capture_ref, verification_refs.get("p0Contract"),
        errors, "P0 contract approval record",
        capture_result=capture_results.get("p0Contract"))
    d5_record = validate_approval_record(
        root, d5.get("recordPath"), d5.get("recordSha256"), d5_id, "d5",
        "targetBaseline", baseline_approval_target(b1_ref, b1), d5_scope,
        capture_refs.get("d5"), verification_refs.get("d5"),
        errors, "D5 approval record",
        package_approver=d5.get("approver"), package_approved_at=approved_at,
        first_wp_id=wp_id, capture_result=capture_results.get("d5"))
    gdd_rel = gdd_target.get("path") if isinstance(gdd_target, dict) else None
    if isinstance(gdd_rel, str):
        b1_gdd = b1_content.get(gdd_rel)
        b2_row = b2_files.get(gdd_rel)
        current_path = root / gdd_rel
        current_bytes = current_path.read_bytes() if current_path.is_file() else None
        if b1_gdd is None or hashlib.sha256(b1_gdd).hexdigest() != gdd_target.get("sha256"):
            errors.append("Gate1 Draft GDD target must remain byte-identical through B1")
        if not isinstance(b2_row, dict) or current_bytes is None \
                or b2_row.get("sha256") != hashlib.sha256(current_bytes).hexdigest():
            errors.append("B2/current GDD bytes do not match the B2 manifest")
        expected_transform_keys = {
            "path", "gate1DraftSha256", "b1Sha256", "b2Sha256",
            "normalizedBodySha256", "rule", "d5ApprovedAt",
        }
        if not isinstance(gdd_transformation, dict) or set(
                gdd_transformation) != expected_transform_keys:
            errors.append("gddD5Transformation has unknown/missing fields")
        elif b1_gdd is not None and current_bytes is not None:
            try:
                old_text, new_text = b1_gdd.decode("utf-8"), current_bytes.decode("utf-8")
            except UnicodeDecodeError:
                errors.append("Gate1/B2 GDD must be strict UTF-8")
            else:
                try:
                    gate1_b1_status = gen_index.normalize_status(
                        parse_header_text(old_text).get("Status", ""), gdd_rel)
                except SystemExit:
                    gate1_b1_status = None
                if gate1_b1_status != "draft":
                    errors.append(
                        "Gate1 GDD historical B1 Status must be exactly Draft")
                old_version = parse_header_text(old_text).get("Version", "")
                draft_row = "| Status | Draft |"
                approved_row = "| Status | Approved |"
                unset_approval_row = "| Last approved | — |"
                approved_row_time = f"| Last approved | {approved_at} |"
                d5_history_row = (
                    f"| {old_version} | {approved_at} | D5 metadata promotion "
                    f"{d5_id} | {d5.get('approver')} |")
                exact_gdd_shape = (
                    old_text.endswith("\n")
                    and old_text.count(draft_row) == 1
                    and old_text.count(unset_approval_row) == 1
                    and approved_row not in old_text
                    and d5_history_row not in old_text)
                expected_new_gdd = ""
                if exact_gdd_shape:
                    expected_new_gdd = old_text.replace(
                        draft_row, approved_row, 1).replace(
                            unset_approval_row, approved_row_time, 1)
                    expected_new_gdd += d5_history_row + "\n"
                if not exact_gdd_shape or new_text != expected_new_gdd:
                    errors.append(
                        "GDD B1 -> B2 must be the exact Draft/Last-approved/D5-history transform")
                normalized_old, normalized_new = normalize_formal_transition(
                    old_text, new_text, gdd_rel, str(d5_id or ""),
                    str(approved_at or ""), errors, index=False, wp_id=None)
                normalized_digest = hashlib.sha256(b1_gdd).hexdigest()
                expected_transform = {
                    "path": gdd_rel,
                    "gate1DraftSha256": gdd_target.get("sha256"),
                    "b1Sha256": hashlib.sha256(b1_gdd).hexdigest(),
                    "b2Sha256": hashlib.sha256(current_bytes).hexdigest(),
                    "normalizedBodySha256": normalized_digest,
                    "rule": "d5-formal-metadata-only-v1",
                    "d5ApprovedAt": approved_at,
                }
                if normalized_old != normalized_new:
                    errors.append("GDD B1 -> B2 changed outside fixed D5 formal metadata")
                if gdd_transformation != expected_transform:
                    errors.append("gddD5Transformation does not exactly bind Draft/B1/B2 GDD")
    validate_p0_management_transition(
        b0_content, b1_content, start_scope, p0_inventory, errors,
        approval_id=str(p0.get("contractApprovalId") or ""),
        candidate_id=str(p0_candidate.get("baselineId") or ""),
        capture_path=str(contract_capture_ref.get("path")
                         if isinstance(contract_capture_ref, dict) else ""))

    transition_proof_values = [
        lifecycle_transitions.get(name) for name in ("p0", "d5")
        if isinstance(lifecycle_transitions.get(name), dict)]
    for field_path in (
            ("attestation", "id"), ("attestation", "path"),
            ("provenanceVerification", "id"),
            ("provenanceVerification", "path"), ("writeLog", "path")):
        values = []
        for proof in transition_proof_values:
            nested = proof.get(field_path[0])
            values.append(nested.get(field_path[1]) if isinstance(nested, dict) else None)
        if len(values) != 2 or any(not isinstance(value, str) or not value for value in values) \
                or len({identity_key(value) for value in values}) != 2:
            errors.append(
                "P0/D5 lifecycle transition proof artifacts and identities must be distinct")
            break

    p0_transition = validate_lifecycle_transition(
        root, lifecycle_transitions.get("p0"), "p0",
        b0_ref, b0, b0_files, p0_candidate_ref, p0_candidate, p0_records,
        {
            "p0Start": transition_approval_binding(
                p0.get("startApprovalId"), verification_refs.get("p0Start"),
                capture_results.get("p0Start"), approval_pvs.get("p0Start")),
            "p0Contract": transition_approval_binding(
                p0.get("contractApprovalId"), verification_refs.get("p0Contract"),
                capture_results.get("p0Contract"), approval_pvs.get("p0Contract")),
        }, provenance_runtime, errors, "lifecycleTransitions.p0",
        approved_content_digest=calculated_digest, p0_inventory=p0_inventory,
        p0_management_wp_path=(management_wp.get("path")
                               if isinstance(management_wp, dict) else None),
        immutable_paths={
            str(value) for value in (
                gdd_target.get("path"),
                approved_intake_ref.get("path")
                if isinstance(approved_intake_ref, dict) else None,
                required_specs_ref.get("path")
                if isinstance(required_specs_ref, dict) else None)
            if isinstance(value, str)},
        result_artifact_paths={str(p0.get("contractApprovalRecordPath"))}
        if isinstance(p0.get("contractApprovalRecordPath"), str) else set())
    d5_transition = validate_lifecycle_transition(
        root, lifecycle_transitions.get("d5"), "d5",
        b1_ref, b1, b1_files, b2_ref, b2, b2_files,
        {
            "d5Approval": transition_approval_binding(
                d5_id, verification_refs.get("d5"),
                capture_results.get("d5"), approval_pvs.get("d5")),
        }, provenance_runtime, errors, "lifecycleTransitions.d5",
        manifest_rel=manifest_rel, post_sync_ref=post_ref_value,
        formal_paths=set(formal), first_wp_path=first_wp_rel,
        immutable_paths={
            str(value) for value in (
                approved_intake_ref.get("path")
                if isinstance(approved_intake_ref, dict) else None,
                required_specs_ref.get("path")
                if isinstance(required_specs_ref, dict) else None)
            if isinstance(value, str)})
    del p0_transition, d5_transition
    temporal_checks = [
        (capture_results.get("gddGate1"), b0.get("createdAt"), "Gate1 before B0"),
        (capture_results.get("p0Start"), p0_candidate.get("createdAt"),
         "P0 start before candidate freeze"),
        (capture_results.get("p0Contract"), p0_candidate.get("createdAt"),
         "P0 contract before candidate freeze"),
        (capture_results.get("d5"), b2.get("createdAt"), "D5 before B2 sync"),
    ]
    for result, later, label in temporal_checks:
        capture_time = (result.get("capture", {}).get("occurredAt")
                        if isinstance(result, dict) else None)
        before, after = parsed_timestamp(capture_time), parsed_timestamp(later)
        if before is None or after is None or before >= after:
            errors.append(f"{label} requires strict timestamp ordering")
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
        str(d5.get("approver") or ""), str(approved_at or ""),
        str(d5.get("recordPath") or ""), first_wp_rel,
        wp_id if isinstance(wp_id, str) else None,
        post_rel if isinstance(post_rel, str) else None, errors)

    return {"pass": not errors, "errors": errors, "checked": checked,
            "formal_documents": len(formal), "post_sync_files": len(post_files),
            "d4_tracks": sorted(seen_tracks)}


RUN_AUTHORIZATION_KEYS = {
    "schemaVersion", "kind", "id", "scopeCoreSha256", "scopeCore",
    "authorizedAt", "human", "approvalEvidence",
}
RUN_ADMISSION_KEYS = {
    "schemaVersion", "kind", "id", "authoritySessionId", "monitorSessionId",
    "w0RunId", "operatorExpectedConfigSha256", "configSha256",
    "prelaunchAssertionSha256", "postexecutionAttestationSha256", "lock",
    "authorizationInputExtension", "currentState", "runAuthorization",
    "receiver", "authorizationChronology", "sideEffectsStarted",
    "oneTimeAdmission", "admitExecutionReceiptOutputs", "enforcement", "admissionLifetimeSeconds",
    "admissionExpiresAt", "verdict",
}
RUN_AUTH_DENIALS = [
    "unlisted-path-write", "frozen-path-write", "scope-expansion", "subdelegation",
    "commit", "push", "production-publish", "public-activation",
    "production-datastore-write", "commerce-production-change",
    "credential-secret-or-permission-change", "external-network-outside-allowlist",
]


def _closed(value: Any, keys: set[str], errors: list[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != keys:
        errors.append(f"{label} has unknown/missing fields")
        return value if isinstance(value, dict) else {}
    return value


def _external_input_path(
        raw: Any, protected: tuple[Path, ...], errors: list[str], label: str,
        *, within: Path | None = None) -> Path | None:
    path = external_path(raw, protected, errors, label, file=True)
    if path is None:
        return None
    # resolve(strict=True) hides aliases.  Reject every original-path symlink or
    # Windows reparse ancestor before accepting its resolved identity.
    try:
        raw_path = Path(str(raw)).absolute()
        cursor = raw_path
        while True:
            info = cursor.lstat()
            reparse = bool(getattr(info, "st_file_attributes", 0)
                           & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400))
            if stat.S_ISLNK(info.st_mode) or reparse:
                errors.append(f"{label}: symlink/junction/reparse path is forbidden")
                return None
            parent = cursor.parent
            if parent == cursor:
                break
            cursor = parent
    except OSError as exc:
        errors.append(f"{label}: cannot inspect path ancestry: {exc}")
        return None
    if within is not None:
        try:
            path.relative_to(within)
        except ValueError:
            errors.append(f"{label}: path must stay inside authorization evidence root")
            return None
    return path


def _external_output_path(
        raw: Any, protected: tuple[Path, ...], errors: list[str], label: str,
        *, within: Path) -> Path | None:
    """Validate a predeclared operator output that must not exist yet."""
    if not isinstance(raw, str) or not raw.strip():
        errors.append(f"{label}: absolute path is required")
        return None
    candidate = Path(raw)
    if not candidate.is_absolute():
        errors.append(f"{label}: path must be absolute")
        return None
    if candidate.exists():
        errors.append(f"{label}: receipt output must be absent before semantic ADMIT PASS")
        return None
    try:
        parent = candidate.parent.resolve(strict=True)
    except OSError as exc:
        errors.append(f"{label}: parent cannot be resolved: {exc}")
        return None
    candidate = parent / candidate.name
    if not outside_roots(candidate, protected):
        errors.append(f"{label}: output path overlaps a protected root")
        return None
    try:
        candidate.relative_to(within)
    except ValueError:
        errors.append(f"{label}: output path must stay inside authorization evidence root")
        return None
    try:
        cursor = parent
        while True:
            info = cursor.lstat()
            reparse = bool(getattr(info, "st_file_attributes", 0)
                           & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400))
            if stat.S_ISLNK(info.st_mode) or reparse:
                errors.append(f"{label}: symlink/junction/reparse ancestry is forbidden")
                return None
            if cursor.parent == cursor:
                break
            cursor = cursor.parent
    except OSError as exc:
        errors.append(f"{label}: cannot inspect path ancestry: {exc}")
        return None
    return candidate


def _absolute_record_path(path: Path) -> str:
    """Canonical absolute path spelling shared with the PowerShell receiver."""
    return path.resolve().as_posix()


def _same_absolute_record_path(raw: Any, expected: Path) -> bool:
    """Compare existing absolute paths by resolved identity spelling.

    W0 schemas permit both Windows separators, while canonical record writers
    use forward slashes.  Hash/identity checks provide the security binding;
    spelling alone must not make a valid signed record unreachable.
    """
    if not isinstance(raw, str) or not raw.strip() or not Path(raw).is_absolute():
        return False
    try:
        return Path(raw).resolve(strict=True) == expected.resolve(strict=True)
    except OSError:
        return False


def _timestamp_at_or_before(earlier: Any, later: Any) -> bool:
    left = parsed_timestamp(earlier)
    right = parsed_timestamp(later)
    return left is not None and right is not None and left <= right


def _framed_string(value: Any, minimum: int) -> bool:
    """Validate a variable field used inside a NUL-delimited hash preimage."""
    return isinstance(value, str) and len(value) >= minimum and "\0" not in value


def _absolute_ref_matches(value: Any, expected: dict[str, Any], path: Path) -> bool:
    return isinstance(value, dict) and set(value) == set(expected) \
        and _same_absolute_record_path(value.get("path"), path) \
        and all(value.get(key) == item for key, item in expected.items() if key != "path")


def _external_ref(
        value: Any, protected: tuple[Path, ...], errors: list[str], label: str,
        *, within: Path | None = None, identified: bool = False,
        with_id: bool = False) -> tuple[Path, dict[str, Any] | None] | None:
    keys = {"path", "sha256"}
    if identified:
        keys.add("fileIdentity")
    if with_id:
        keys.add("id")
    ref = _closed(value, keys, errors, label)
    path = _external_input_path(ref.get("path"), protected, errors, f"{label}.path",
                                within=within)
    expected = ref.get("sha256")
    if not isinstance(expected, str) or SHA256_RE.fullmatch(expected) is None:
        errors.append(f"{label}.sha256 must be 64 lowercase hex characters")
    elif path is not None and sha256(path) != expected:
        errors.append(f"{label}.sha256 mismatch")
    if identified and (not isinstance(ref.get("fileIdentity"), str)
                       or not ref["fileIdentity"].strip()):
        errors.append(f"{label}.fileIdentity must be non-empty")
    if with_id and (not isinstance(ref.get("id"), str) or not ref["id"].strip()):
        errors.append(f"{label}.id must be non-empty")
    if path is None:
        return None
    return path, strict_json_file(path, errors, label) if path.suffix.lower() == ".json" else None


def _current_project_tree_sha256(root: Path, errors: list[str]) -> str | None:
    records: list[dict[str, Any]] = []
    identities: set[tuple[int, int]] = set()
    try:
        for path in root.rglob("*"):
            info = path.lstat()
            reparse = bool(getattr(info, "st_file_attributes", 0)
                           & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400))
            if stat.S_ISLNK(info.st_mode) or reparse:
                errors.append(f"project tree contains symlink/junction/reparse: {path}")
                return None
            if path.is_dir():
                continue
            if not path.is_file():
                errors.append(f"project tree contains non-regular entry: {path}")
                return None
            if info.st_nlink != 1:
                errors.append(f"project tree contains a hardlinked file: {path}")
                return None
            identity = (info.st_dev, info.st_ino)
            if identity in identities:
                errors.append(f"project tree reuses one OS file identity: {path}")
                return None
            identities.add(identity)
            records.append({"path": path.relative_to(root).as_posix(),
                            "bytes": path.stat().st_size, "sha256": sha256(path)})
    except OSError as exc:
        errors.append(f"cannot enumerate current project tree: {exc}")
        return None
    records.sort(key=lambda item: item["path"])
    return canonical_json_sha256({"files": records})


def _closed_tree_sha256(root: Path, errors: list[str], label: str) -> str | None:
    """Hash a complete immutable tree and reject every alias/link/special entry."""
    records: list[dict[str, Any]] = []
    identities: set[tuple[int, int]] = set()
    try:
        root_info = root.lstat()
        root_reparse = bool(getattr(root_info, "st_file_attributes", 0)
                            & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400))
        if not root.is_dir() or stat.S_ISLNK(root_info.st_mode) or root_reparse:
            errors.append(f"{label}: root must be a real non-reparse directory")
            return None
        for path in root.rglob("*"):
            info = path.lstat()
            reparse = bool(getattr(info, "st_file_attributes", 0)
                           & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400))
            if stat.S_ISLNK(info.st_mode) or reparse:
                errors.append(f"{label}: contains symlink/junction/reparse: {path}")
                return None
            if path.is_dir():
                continue
            if not path.is_file():
                errors.append(f"{label}: contains non-regular entry: {path}")
                return None
            if info.st_nlink != 1:
                errors.append(f"{label}: contains a hardlinked file: {path}")
                return None
            identity = (info.st_dev, info.st_ino)
            if identity in identities:
                errors.append(f"{label}: reuses one OS file identity: {path}")
                return None
            identities.add(identity)
            records.append({"path": path.relative_to(root).as_posix(),
                            "bytes": info.st_size, "sha256": sha256(path)})
    except OSError as exc:
        errors.append(f"{label}: cannot enumerate tree: {exc}")
        return None
    records.sort(key=lambda item: item["path"])
    return canonical_json_sha256({"files": records})


def _project_file(
        root: Path, raw: Any, expected_hash: Any, errors: list[str], label: str) -> Path | None:
    path = resolve_path(root, raw, errors, label)
    if path is None or not path.is_file():
        if path is not None:
            errors.append(f"{label}: project file does not exist")
        return None
    if not isinstance(expected_hash, str) or SHA256_RE.fullmatch(expected_hash) is None \
            or sha256(path) != expected_hash:
        errors.append(f"{label}: project file sha256 mismatch")
    return path


def _canonical_project_file(
        root: Path, raw: Any, expected_hash: Any, errors: list[str], label: str,
        *, expected_bytes: Any = None) -> tuple[Path, str] | None:
    if not isinstance(raw, str) or not raw or "\\" in raw:
        errors.append(f"{label}: canonical project-relative POSIX path required")
        return None
    path = resolve_path(root, raw, errors, label)
    if path is None or not path.is_file():
        if path is not None:
            errors.append(f"{label}: referenced file does not exist")
        return None
    rel = path.relative_to(root).as_posix()
    if rel != raw:
        errors.append(f"{label}: non-canonical project path spelling")
    try:
        info = path.lstat()
    except OSError as exc:
        errors.append(f"{label}: cannot stat file: {exc}")
        return None
    reparse = bool(getattr(info, "st_file_attributes", 0)
                   & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400))
    if stat.S_ISLNK(info.st_mode) or reparse or not path.is_file() or info.st_nlink != 1:
        errors.append(f"{label}: links, reparses, special files, and hardlinks are forbidden")
    if not isinstance(expected_hash, str) or SHA256_RE.fullmatch(expected_hash) is None \
            or sha256(path) != expected_hash:
        errors.append(f"{label}: SHA-256 mismatch")
    if expected_bytes is not None and (type(expected_bytes) is not int
                                       or info.st_size != expected_bytes):
        errors.append(f"{label}: byte count mismatch")
    return path, rel


def _derive_w0_frozen_paths(
        root: Path, package_path: Path, package: dict[str, Any],
        errors: list[str]) -> list[str]:
    """Rederive the exact immutable project path set exposed to the human."""
    frozen: set[str] = {package_path.relative_to(root).as_posix()}
    seen_json: set[Path] = set()

    def add_ref(raw: Any, digest: Any, label: str) -> dict[str, Any] | None:
        if not isinstance(raw, str):
            return None
        candidate = Path(raw)
        if candidate.is_absolute():
            try:
                resolved = candidate.resolve(strict=True)
                resolved.relative_to(root)
            except (OSError, ValueError):
                return None
            raw = resolved.relative_to(root).as_posix()
        candidate = resolve_path(root, raw, [], label)
        if candidate is None or not candidate.is_file():
            return None
        rel = candidate.relative_to(root).as_posix()
        if rel != raw:
            errors.append(f"{label}: non-canonical project path spelling")
        try:
            info = candidate.lstat()
        except OSError as exc:
            errors.append(f"{label}: cannot stat reachable project artifact: {exc}")
            return None
        reparse = bool(getattr(info, "st_file_attributes", 0)
                       & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400))
        if stat.S_ISLNK(info.st_mode) or reparse or info.st_nlink != 1:
            errors.append(f"{label}: reachable project artifact is linked/reparse/aliased")
        frozen.add(rel)
        # A historical target reference (notably Gate1 Draft GDD) may validly
        # name a current B2 path with different D5 metadata bytes.  Other W0
        # validators prove that transform.  Recurse only through an exact-hash
        # JSON proof; this derivation still freezes every existing target path.
        if candidate.suffix.lower() != ".json" or candidate in seen_json \
                or not isinstance(digest, str) or sha256(candidate) != digest:
            return None
        seen_json.add(candidate)
        # Reachable raw-output JSON may validly have an array/scalar root.  It
        # is still frozen above, but only closed object records can contain
        # further typed references to traverse.
        try:
            nested = strict_json_module.load_path(candidate)
        except (OSError, UnicodeError, json.JSONDecodeError,
                strict_json_module.StrictJsonError, ValueError) as exc:
            errors.append(f"{label}: cannot read strict JSON {candidate}: {exc}")
            return None
        return nested if isinstance(nested, dict) else None

    def walk(value: Any, label: str, *, inventory_files: bool = False) -> None:
        if isinstance(value, list):
            for index, child in enumerate(value):
                walk(child, f"{label}[{index}]", inventory_files=inventory_files)
            return
        if not isinstance(value, dict):
            return
        loaded: dict[str, Any] | None = None
        if isinstance(value.get("path"), str) and isinstance(value.get("sha256"), str):
            loaded = add_ref(value.get("path"), value.get("sha256"), f"{label}.path")
        for key, raw in value.items():
            if not isinstance(key, str) or not key.endswith("Path") or not isinstance(raw, str):
                continue
            digest_key = key[:-4] + "Sha256"
            digest = value.get(digest_key)
            if isinstance(digest, str):
                nested = add_ref(raw, digest, f"{label}.{key}")
                if nested is not None:
                    walk(nested, f"{label}.{key}<json>",
                         inventory_files=bool(nested.get("baselineId") or
                                              nested.get("selfIncluded") is False))
        if isinstance(value.get("capsulePath"), str) and isinstance(value.get("sha256"), str):
            nested = add_ref(value["capsulePath"], value["sha256"],
                             f"{label}.capsulePath")
            if nested is not None:
                walk(nested, f"{label}.capsulePath<json>")
        if loaded is not None:
            walk(loaded, f"{label}.path<json>",
                 inventory_files=bool(loaded.get("baselineId") or
                                      loaded.get("selfIncluded") is False))
        for key, child in value.items():
            if inventory_files and key == "files":
                continue
            if key in {"path", "sha256", "capsulePath"} or key.endswith("Path") \
                    or key.endswith("Sha256"):
                continue
            walk(child, f"{label}.{key}", inventory_files=inventory_files)

    baselines = package.get("baselines") if isinstance(package.get("baselines"), dict) else {}
    for stage in ("b0", "b1", "b2"):
        ref = baselines.get(stage) if isinstance(baselines.get(stage), dict) else {}
        loaded = _canonical_project_file(root, ref.get("path"), ref.get("sha256"),
                                         errors, f"run authorization {stage} manifest")
        if loaded is None:
            continue
        manifest_path, manifest_rel = loaded
        frozen.add(manifest_rel)
        manifest = strict_json_file(manifest_path, errors,
                                    f"run authorization {stage} manifest") or {}
        seen_json.add(manifest_path)
        revision = manifest.get("revision") if isinstance(manifest.get("revision"), dict) else {}
        snapshot_root = revision.get("snapshotRoot")
        if revision.get("kind") != "snapshot" or not isinstance(snapshot_root, str):
            errors.append(f"run authorization {stage} must use a snapshot revision")
            continue
        snapshot = resolve_path(root, snapshot_root, errors,
                                f"run authorization {stage}.snapshotRoot")
        if snapshot is None or not snapshot.is_dir():
            errors.append(f"run authorization {stage}.snapshotRoot is not a directory")
            continue
        files = manifest.get("files") if isinstance(manifest.get("files"), list) else []
        for index, row in enumerate(files):
            if not isinstance(row, dict):
                errors.append(f"run authorization {stage}.files[{index}] is not an object")
                continue
            raw_member = row.get("path")
            if not isinstance(raw_member, str):
                errors.append(f"run authorization {stage}.files[{index}].path is invalid")
                continue
            physical = (Path(snapshot_root) / Path(raw_member)).as_posix()
            member = _canonical_project_file(
                root, physical, row.get("sha256"), errors,
                f"run authorization {stage} snapshot member[{index}]",
                expected_bytes=row.get("bytes"))
            if member is not None:
                frozen.add(member[1])
        walk(manifest, f"run authorization {stage} manifest", inventory_files=True)
    walk(package, "W0 package")
    return sorted(frozen)


def _path_sets_are_disjoint(
        root: Path, writes: list[str], frozen: list[str], errors: list[str]) -> None:
    frozen_keys = {value.casefold(): value for value in frozen}
    frozen_identities: set[tuple[int, int]] = set()
    for raw in frozen:
        path = resolve_path(root, raw, errors, "frozen path")
        if path is not None and path.exists():
            info = path.stat()
            frozen_identities.add((info.st_dev, info.st_ino))
    for raw in writes:
        key = raw.casefold()
        for frozen_key, frozen_raw in frozen_keys.items():
            if key == frozen_key or key.startswith(frozen_key + "/") \
                    or frozen_key.startswith(key + "/"):
                errors.append(
                    f"allowedWritePaths overlaps immutable path: {raw} vs {frozen_raw}")
        path = resolve_path(root, raw, errors, "allowed write")
        if path is not None and path.exists():
            info = path.stat()
            if (info.st_dev, info.st_ino) in frozen_identities:
                errors.append(f"allowedWritePaths aliases immutable file identity: {raw}")


def _run_auth_project_path(value: Any) -> bool:
    if not isinstance(value, str) or not value or "\\" in value \
            or value.startswith("/") or "//" in value:
        return False
    reserved = re.compile(r"(?i)^(?:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$")
    for segment in value.split("/"):
        if segment in {"", ".", ".."} or segment.endswith(".") \
                or re.fullmatch(r"[A-Za-z0-9._-]+", segment) is None \
                or reserved.fullmatch(segment.split(".", 1)[0]) is not None:
            return False
    return True


def _run_auth_target(authorization: dict[str, Any]) -> dict[str, Any]:
    scope = authorization.get("scopeCore") if isinstance(
        authorization.get("scopeCore"), dict) else {}
    bootstrap = scope.get("bootstrap") if isinstance(scope.get("bootstrap"), dict) else {}
    return {
        "kind": "w0-run-authorization-target-v1",
        "authorizationId": authorization.get("id"),
        "scopeCoreSha256": authorization.get("scopeCoreSha256"),
        "b2": scope.get("b2"), "w0Package": scope.get("w0Package"),
        "bootstrapRunId": bootstrap.get("runId"),
        "postexecutionAttestation": bootstrap.get("postexecutionAttestation"),
        "firstWp": scope.get("firstWp"),
    }


def _validate_external_run_pv(
        pv_path: Path, capture_path: Path, capture: dict[str, Any], claims: dict[str, Any],
        protected: tuple[Path, ...], auth_root: Path, runtime: dict[str, Any] | None,
        errors: list[str]) -> tuple[dict[str, Any], set[Path]]:
    label = "run authorization provenance"
    pv = strict_json_file(pv_path, errors, label) or {}
    _closed(pv, PROVENANCE_VERIFICATION_KEYS, errors, label)
    expected_subject = {"id": capture.get("id"), "path": _absolute_record_path(capture_path),
                        "sha256": sha256(capture_path)}
    if pv.get("schemaVersion") != "1.0.0" or pv.get("subjectType") != \
            "w0-run-authorization-capture" or not _absolute_ref_matches(
                pv.get("subject"), expected_subject, capture_path):
        errors.append(f"{label}: subject/schemaVersion mismatch")
    if pv.get("verificationMode") != "pinned-signature":
        errors.append(f"{label}: W0 accepts offline pinned-signature only")
        return pv, set()
    if pv.get("claims") != claims or pv.get("claimsSha256") != canonical_json_sha256(claims):
        errors.append(f"{label}: claims/claimsSha256 mismatch")
    if pv.get("verdict") != "verified" or not timezone_datetime(pv.get("verifiedAt")):
        errors.append(f"{label}: verdict/verifiedAt invalid")
    verifier = _closed(pv.get("verifier"), {"id", "authority", "adapter", "adapterVersion"},
                       errors, f"{label}.verifier")
    context = _closed(pv.get("verificationContext"),
                      {"kind", "algorithm", "keyId", "trustAnchorSha256"}, errors,
                      f"{label}.verificationContext")
    if context.get("kind") != "pinned-signature-v1":
        errors.append(f"{label}: verificationContext.kind mismatch")
    source_loaded = _external_ref(pv.get("sourceArtifact"), protected, errors,
                                  f"{label}.sourceArtifact", within=auth_root)
    source = source_loaded[1] if source_loaded and isinstance(source_loaded[1], dict) else {}
    _closed(source, PINNED_SIGNATURE_EVIDENCE_KEYS, errors, f"{label}.sourceArtifact")
    for key, expected in (("authority", verifier.get("authority")),
                          ("algorithm", context.get("algorithm")),
                          ("keyId", context.get("keyId")),
                          ("claimsSha256", canonical_json_sha256(claims))):
        if source.get(key) != expected:
            errors.append(f"{label}.sourceArtifact.{key} mismatch")
    source_time = parsed_timestamp(source.get("verifiedAt"))
    response_time = parsed_timestamp(capture.get("occurredAt"))
    pv_time = parsed_timestamp(pv.get("verifiedAt"))
    if source_time is None or response_time is None or pv_time is None \
            or not (response_time <= source_time <= pv_time):
        errors.append(f"{label}: response <= signature verifiedAt <= PV verifiedAt required")
    transitive: set[Path] = {pv_path}
    if source_loaded:
        transitive.add(source_loaded[0])
    configured_runner = None
    key = (verifier.get("authority"), context.get("algorithm"), context.get("keyId"))
    if runtime is not None:
        configured_runner = runtime.get("signatures", {}).get(key)
    if configured_runner is None:
        errors.append(f"{label}: no pinned signature verifier matches {key!r}")
    resolved: dict[str, Path] = {}
    for field in ("trustAnchorArtifact", "signedPayloadArtifact", "signatureArtifact"):
        within = None if field == "trustAnchorArtifact" else auth_root
        item = _external_ref(source.get(field), protected, errors,
                             f"{label}.sourceArtifact.{field}", within=within)
        if item:
            resolved[field] = item[0]
            if field != "trustAnchorArtifact":
                transitive.add(item[0])
    payload = resolved.get("signedPayloadArtifact")
    if payload is not None and payload.read_bytes() != canonical_json_bytes(claims):
        errors.append(f"{label}: signed payload bytes differ from canonical claims")
    configured_anchor = configured_runner.get("trustAnchor") if configured_runner else None
    if not isinstance(configured_anchor, dict) or source.get("trustAnchorArtifact") != {
            "path": configured_anchor.get("path"), "sha256": configured_anchor.get("sha256")} \
            or context.get("trustAnchorSha256") != configured_anchor.get("sha256"):
        errors.append(f"{label}: trust anchor does not equal externally pinned verifier")
    if configured_runner is not None and all(
            key_name in resolved for key_name in ("signedPayloadArtifact", "signatureArtifact")):
        request = {
            "schemaVersion": "1.0.0", "operation": "verify-pinned-signature-v1",
            "authority": verifier.get("authority"), "algorithm": context.get("algorithm"),
            "keyId": context.get("keyId"), "claimsSha256": canonical_json_sha256(claims),
            "trustAnchorPath": configured_anchor.get("path"),
            "signedPayloadPath": str(resolved["signedPayloadArtifact"]),
            "signaturePath": str(resolved["signatureArtifact"]),
        }
        verified = invoke_external_runner(configured_runner, request, errors,
                                          f"{label}.signature")
        expected = {"verified": True, "authority": verifier.get("authority"),
                    "algorithm": context.get("algorithm"), "keyId": context.get("keyId"),
                    "claimsSha256": canonical_json_sha256(claims)}
        if verified != expected:
            errors.append(f"{label}: pinned signature verifier rejected exact claims")
    return pv, transitive


def validate_run_authorization_admission(
        root: Path, package_path: Path, config_path: Path, expected_config_sha256: str,
        skill_root: Path, launch_challenge_path: Path, presentation_path: Path,
        challenge_path: Path, transcript_path: Path, statement_path: Path,
        capture_path: Path, capture_pv_path: Path, authorization_path: Path,
        admission_path: Path, admission_signature_path: Path) -> dict[str, Any]:
    """Validate the sealed VALIDATE→ADMIT human authority chain.

    Native bootstrap verifies the detached admission signature and actual Windows
    identities.  This pass independently rederives all content, scope, chronology,
    current-state, signature-verifier, and one-time-token bindings.
    """
    global INSTALLED_SKILL_ROOT
    errors: list[str] = []
    INSTALLED_SKILL_ROOT = skill_root.resolve()
    if not isinstance(expected_config_sha256, str) or SHA256_RE.fullmatch(
            expected_config_sha256) is None or sha256(config_path) != expected_config_sha256:
        errors.append("operator expected config SHA-256 mismatch before config parsing")
        return {"pass": False, "errors": errors, "mode": "run-authorization"}
    package = strict_json_file(package_path, errors, "W0 package") or {}
    challenge_runtime = strict_json_file(
        launch_challenge_path, errors, "runtime launch challenge") or {}
    auth_root_raw = challenge_runtime.get("resolvedAuthorizationEvidenceRoot")
    try:
        auth_root = Path(str(auth_root_raw)).resolve(strict=True)
    except OSError as exc:
        errors.append(f"authorization evidence root is invalid: {exc}")
        auth_root = authorization_path.parent.resolve()
    temp_raw = challenge_runtime.get("resolvedTempRoot")
    try:
        temp_root = Path(str(temp_raw)).resolve(strict=True)
    except OSError:
        temp_root = launch_challenge_path.parent / ".invalid-temp"
    protected = (root.resolve(), skill_root.resolve(), temp_root)

    supplied = [presentation_path, challenge_path, transcript_path, statement_path,
                capture_path, capture_pv_path, authorization_path, admission_path,
                admission_signature_path]
    resolved_supplied: list[Path] = []
    for index, path in enumerate(supplied):
        resolved = _external_input_path(str(path), protected, errors,
                                        f"authorization input[{index}]", within=auth_root)
        if resolved is not None:
            resolved_supplied.append(resolved)
    if len({os.path.normcase(str(path)) for path in resolved_supplied}) != len(supplied):
        errors.append("run authorization/admission input paths must be distinct")
    # The native bootstrap is the cryptographic verifier, but the Python ADMIT
    # semantic process must still actually consume every byte claimed in its
    # authority-observed read-input closure.  Hash the detached signature here
    # instead of merely stat'ing its path.
    try:
        admission_signature_bytes = admission_signature_path.read_bytes()
        if not admission_signature_bytes:
            errors.append("run admission detached signature must be non-empty")
        hashlib.sha256(admission_signature_bytes).hexdigest()
    except OSError as exc:
        errors.append(f"run admission detached signature cannot be read: {exc}")

    presentation = strict_json_file(presentation_path, errors, "run presentation") or {}
    human_challenge = strict_json_file(challenge_path, errors, "run challenge") or {}
    transcript = strict_json_file(transcript_path, errors, "run transcript") or {}
    capture = strict_json_file(capture_path, errors, "run capture") or {}
    authorization = strict_json_file(authorization_path, errors, "run authorization") or {}
    admission = strict_json_file(admission_path, errors, "run admission") or {}
    _closed(authorization, RUN_AUTHORIZATION_KEYS, errors, "run authorization")
    _closed(admission, RUN_ADMISSION_KEYS, errors, "run admission")
    if authorization.get("schemaVersion") != "1.0.0" or authorization.get("kind") != \
            "w0-run-authorization-v1" or re.fullmatch(
                r"W0-RUN-AUTH-[A-Z0-9][A-Z0-9._-]*", str(authorization.get("id", ""))) is None:
        errors.append("run authorization fixed identity fields are invalid")
    scope = _closed(authorization.get("scopeCore"), {
        "kind", "approvalChallenge", "b2", "w0Package", "bootstrap", "firstWp",
        "pathScope", "assignedReceiver", "transfer", "operations", "deniedOperations",
        "expiresAt", "additionalScope"}, errors, "run authorization.scopeCore")
    scope_hash = canonical_json_sha256(scope)
    if authorization.get("scopeCoreSha256") != scope_hash:
        errors.append("run authorization.scopeCoreSha256 mismatch")
    if scope.get("kind") != "w0-run-authorization-scope-v1" \
            or scope.get("additionalScope") is not False \
            or scope.get("deniedOperations") != RUN_AUTH_DENIALS:
        errors.append("run authorization closed scope fixed fields mismatch")
    target = _run_auth_target(authorization)
    target_scope_hash = canonical_json_sha256({
        "gateType": "w0-run-authorization", "target": target, "scope": scope})
    challenge_id = scope.get("approvalChallenge", {}).get("id") \
        if isinstance(scope.get("approvalChallenge"), dict) else None
    response = f"APPROVE {challenge_id} {target_scope_hash}"
    expected_presentation = {
        "schemaVersion": "1.0.0", "challengeId": challenge_id,
        "gateType": "w0-run-authorization", "issuedAt": human_challenge.get("issuedAt"),
        "target": target, "scope": scope, "targetScopeSha256": target_scope_hash,
        "canonicalResponse": response,
    }
    if presentation != expected_presentation or presentation_path.read_bytes() != \
            canonical_json_bytes(expected_presentation):
        errors.append("run authorization presentation is not exact canonical target/scope bytes")
    expected_challenge = {
        "schemaVersion": "1.0.0", "id": challenge_id,
        "gateType": "w0-run-authorization", "issuedAt": human_challenge.get("issuedAt"),
        "targetScopeSha256": target_scope_hash, "canonicalResponse": response,
        "presentationArtifact": {"path": _absolute_record_path(presentation_path),
                                 "sha256": sha256(presentation_path)},
    }
    challenge_compare = dict(human_challenge)
    if _absolute_ref_matches(
            challenge_compare.get("presentationArtifact"),
            expected_challenge["presentationArtifact"], presentation_path):
        challenge_compare["presentationArtifact"] = expected_challenge["presentationArtifact"]
    if challenge_compare != expected_challenge:
        errors.append("run authorization challenge does not exact-bind presentation/target/scope")
    if statement_path.read_bytes() != response.encode("utf-8"):
        errors.append("run authorization statement must be exact canonical response bytes")

    capture_keys = {"schemaVersion", "id", "gateType", "approvalMethod", "approved",
                    "approver", "occurredAt", "sourceInteractionRef", "runAuthorizationTarget",
                    "scope", "challengeArtifact", "statementArtifact", "statementSha256"}
    _closed(capture, capture_keys, errors, "run capture")
    if capture.get("schemaVersion") != "1.0.0" or capture.get("gateType") != \
            "w0-run-authorization" or capture.get("approvalMethod") != "human-direct" \
            or capture.get("approved") is not True or capture.get("runAuthorizationTarget") != target \
            or capture.get("scope") != scope:
        errors.append("run capture fixed target/scope/approval fields mismatch")
    expected_capture_challenge = {"path": _absolute_record_path(challenge_path),
                                  "sha256": sha256(challenge_path)}
    expected_capture_statement = {"path": _absolute_record_path(statement_path),
                                  "sha256": sha256(statement_path)}
    if not _absolute_ref_matches(
            capture.get("challengeArtifact"), expected_capture_challenge, challenge_path) \
            or not _absolute_ref_matches(
                capture.get("statementArtifact"), expected_capture_statement, statement_path) \
            or capture.get("statementSha256") != sha256(statement_path):
        errors.append("run capture challenge/statement references mismatch")
    source = _closed(capture.get("sourceInteractionRef"), {
        "channel", "interactionId", "presentationMessageId", "messageId",
        "transcriptArtifact"}, errors, "run capture.sourceInteractionRef")
    expected_transcript_ref = {"path": _absolute_record_path(transcript_path),
                               "sha256": sha256(transcript_path)}
    if not _absolute_ref_matches(
            source.get("transcriptArtifact"), expected_transcript_ref, transcript_path):
        errors.append("run capture transcript reference mismatch")
    _closed(transcript, {"schemaVersion", "id", "channel", "interactionId", "capturedAt",
                         "messages"}, errors, "run transcript")
    if transcript.get("schemaVersion") != "1.0.0" or transcript.get("channel") != \
            source.get("channel") or transcript.get("interactionId") != source.get("interactionId"):
        errors.append("run transcript channel/interaction mismatch")
    messages = transcript.get("messages") if isinstance(transcript.get("messages"), list) else []
    seen_ids: set[str] = set()
    presented: list[dict[str, Any]] = []
    responded: list[dict[str, Any]] = []
    for index, message in enumerate(messages):
        row = _closed(message, {"messageId", "role", "actorId", "occurredAt", "content"},
                      errors, f"run transcript.messages[{index}]")
        message_id = row.get("messageId")
        if not isinstance(message_id, str) or not message_id or message_id in seen_ids:
            errors.append("run transcript message IDs must be non-empty and unique")
        else:
            seen_ids.add(message_id)
        if message_id == source.get("presentationMessageId"):
            presented.append(row)
        if message_id == source.get("messageId"):
            responded.append(row)
    if len(presented) != 1 or presented[0].get("role") not in {"assistant", "system"} \
            or presented[0].get("content") != presentation_path.read_text(encoding="utf-8"):
        errors.append("run authorization presentation message is missing or not exact")
    if len(responded) != 1 or responded[0].get("role") != "human" \
            or responded[0].get("content") != response \
            or responded[0].get("actorId") != capture.get("approver") \
            or responded[0].get("occurredAt") != capture.get("occurredAt"):
        errors.append("run authorization human response is missing or not exact")
    issued_at = parsed_timestamp(human_challenge.get("issuedAt"))
    presentation_at = parsed_timestamp(presented[0].get("occurredAt")) \
        if len(presented) == 1 else None
    response_at = parsed_timestamp(responded[0].get("occurredAt")) if len(responded) == 1 else None
    captured_at = parsed_timestamp(transcript.get("capturedAt"))
    if None in (issued_at, presentation_at, response_at, captured_at) \
            or not (issued_at <= presentation_at < response_at <= captured_at):
        errors.append("run authorization requires issued <= presentation < response <= capture")
    human = _closed(authorization.get("human"), {"actor", "channel", "messageId"},
                    errors, "run authorization.human")
    if human != {"actor": capture.get("approver"), "channel": source.get("channel"),
                 "messageId": source.get("messageId")} \
            or authorization.get("authorizedAt") != capture.get("occurredAt"):
        errors.append("run authorization human/authorizedAt mismatch")

    approval = _closed(authorization.get("approvalEvidence"), {
        "presentation", "challenge", "transcript", "statement", "capture",
        "provenanceVerification"}, errors, "run authorization.approvalEvidence")
    expected_refs = {
        "presentation": {"path": _absolute_record_path(presentation_path), "sha256": sha256(presentation_path)},
        "challenge": {"path": _absolute_record_path(challenge_path), "sha256": sha256(challenge_path)},
        "transcript": {"path": _absolute_record_path(transcript_path), "sha256": sha256(transcript_path)},
        "statement": {"path": _absolute_record_path(statement_path), "sha256": sha256(statement_path)},
        "capture": {"id": capture.get("id"), "path": _absolute_record_path(capture_path),
                    "sha256": sha256(capture_path)},
        "provenanceVerification": {"id": None, "path": _absolute_record_path(capture_pv_path),
                                   "sha256": sha256(capture_pv_path),
                                   "verificationMode": "pinned-signature"},
    }
    pv_preview = strict_json_file(capture_pv_path, errors, "run authorization provenance") or {}
    expected_refs["provenanceVerification"]["id"] = pv_preview.get("id")
    approval_paths = {
        "presentation": presentation_path, "challenge": challenge_path,
        "transcript": transcript_path, "statement": statement_path,
        "capture": capture_path, "provenanceVerification": capture_pv_path,
    }
    if not isinstance(approval, dict) or set(approval) != set(expected_refs) or any(
            not _absolute_ref_matches(approval.get(key), expected, approval_paths[key])
            for key, expected in expected_refs.items()):
        errors.append("run authorization approvalEvidence does not match CLI-sealed files")

    consumption = pv_preview.get("claims", {}).get("consumption") \
        if isinstance(pv_preview.get("claims"), dict) else {}
    consumption = _closed(consumption, {
        "registryAuthority", "registryId", "eventId", "nonce", "consumedAt",
        "verdict", "globalNonreuse"}, errors, "run authorization consumption")
    if any(not isinstance(consumption.get(key), str) or not consumption[key].strip()
           for key in ("registryAuthority", "registryId", "eventId", "nonce")) \
            or consumption.get("verdict") != "consumed-once" \
            or consumption.get("globalNonreuse") is not True \
            or not timezone_datetime(consumption.get("consumedAt")):
        errors.append("run authorization consumption is not an externally bound one-time event")
    nonce = consumption.get("nonce") if isinstance(consumption, dict) else None
    approval_challenge = _closed(scope.get("approvalChallenge"), {"id", "nonceSha256"},
                                 errors, "run authorization.scope.approvalChallenge")
    if not isinstance(nonce, str) or len(nonce) < 32 \
            or approval_challenge.get("nonceSha256") != hashlib.sha256(
                str(nonce).encode("utf-8")).hexdigest():
        errors.append("run authorization challenge nonce digest mismatch")
    claims = {
        "kind": "w0-run-authorization-v1", "captureId": capture.get("id"),
        "authorizationId": authorization.get("id"), "scopeCoreSha256": scope_hash,
        "targetScopeSha256": target_scope_hash, "challengeId": challenge_id,
        "challengeNonceSha256": approval_challenge.get("nonceSha256"),
        "challengeIssuedAt": human_challenge.get("issuedAt"),
        "presentationMessageId": source.get("presentationMessageId"),
        "presentationRole": presented[0].get("role") if len(presented) == 1 else None,
        "presentationAt": presented[0].get("occurredAt") if len(presented) == 1 else None,
        "presentationContentSha256": sha256(presentation_path),
        "actor": capture.get("approver"), "channel": source.get("channel"),
        "messageId": source.get("messageId"),
        "messageRole": responded[0].get("role") if len(responded) == 1 else None,
        "sentAt": capture.get("occurredAt"), "contentSha256": sha256(statement_path),
        "consumption": consumption, "b2Sha256": scope.get("b2", {}).get("sha256"),
        "w0PackageSha256": scope.get("w0Package", {}).get("sha256"),
        "bootstrapRunId": scope.get("bootstrap", {}).get("runId"),
        "postexecutionAttestationSha256": scope.get("bootstrap", {}).get(
            "postexecutionAttestation", {}).get("sha256"),
        "firstWpId": scope.get("firstWp", {}).get("id"),
        "firstWpPath": scope.get("firstWp", {}).get("path"),
        "firstWpSha256": scope.get("firstWp", {}).get("sha256"),
        "authorizedAt": authorization.get("authorizedAt"), "expiresAt": scope.get("expiresAt"),
        "additionalScope": False,
    }
    # Query-mode is rejected before config runners are loaded or invoked.
    if pv_preview.get("verificationMode") != "pinned-signature":
        errors.append("run authorization provenance must be offline pinned-signature; no adapter invoked")
        return {"pass": False, "errors": errors, "mode": "run-authorization"}
    runtime = load_provenance_runtime(config_path, root, skill_root, errors)
    validated_run_pv, pv_transitive = _validate_external_run_pv(
        capture_pv_path, capture_path, capture, claims, protected, auth_root,
        runtime, errors)
    consumed_at = parsed_timestamp(consumption.get("consumedAt"))
    source_verified_at = parsed_timestamp(
        (strict_json_file(Path(str(pv_preview.get("sourceArtifact", {}).get("path", ""))),
                          [], "run signature source") or {}).get("verifiedAt"))
    if response_at is None or consumed_at is None or source_verified_at is None \
            or not (response_at <= consumed_at <= source_verified_at):
        errors.append("run authorization response <= nonce consumption <= signature verification required")

    b2_ref = scope.get("b2") if isinstance(scope.get("b2"), dict) else {}
    b2_loaded = verify_ref(root, {"path": b2_ref.get("path"), "sha256": b2_ref.get("sha256")},
                           errors, "run authorization B2")
    b2 = b2_loaded[1] if b2_loaded else {}
    if b2.get("baselineId") != b2_ref.get("id") or b2.get("fileSetSha256") != \
            b2_ref.get("fileSetSha256") or not str(b2.get("baselineId", "")).startswith("B2-"):
        errors.append("run authorization B2 reference does not bind current B2 manifest")
    package_ref = scope.get("w0Package") if isinstance(scope.get("w0Package"), dict) else {}
    package_rel = package_path.relative_to(root).as_posix()
    if package_ref != {"id": package.get("packageId"), "path": package_rel,
                       "sha256": sha256(package_path)}:
        errors.append("run authorization W0 package reference mismatch")
    first_wp = scope.get("firstWp") if isinstance(scope.get("firstWp"), dict) else {}
    _project_file(root, first_wp.get("path"), first_wp.get("sha256"), errors,
                  "run authorization first WP")
    packaged_wp = package.get("firstAuthorizedWp") if isinstance(
        package.get("firstAuthorizedWp"), dict) else {}
    if any(first_wp.get(key) != packaged_wp.get(key) for key in ("id", "path", "sha256")):
        errors.append("run authorization first WP differs from W0 package")
    bootstrap_scope = _closed(scope.get("bootstrap"), {
        "runId", "launchChallenge", "postexecutionAttestation"}, errors,
        "run authorization.scope.bootstrap")
    expected_launch_ref = {
        "path": _absolute_record_path(launch_challenge_path),
        "sha256": sha256(launch_challenge_path),
    }
    if bootstrap_scope.get("runId") != challenge_runtime.get("runId") \
            or not _absolute_ref_matches(
                bootstrap_scope.get("launchChallenge"), expected_launch_ref,
                launch_challenge_path):
        errors.append("run authorization bootstrap challenge/run binding mismatch")
    post_ref = bootstrap_scope.get("postexecutionAttestation")
    post_loaded = _external_ref(post_ref, protected, errors, "postexecution attestation")
    post = post_loaded[1] if post_loaded and isinstance(post_loaded[1], dict) else {}
    if post.get("kind") != "w0-runtime-postexecution-v1" or post.get("runId") != \
            challenge_runtime.get("runId") or post.get("admitPhaseReady") is not True:
        errors.append("run authorization does not bind a passing retained postexecution proof")
    if not _timestamp_at_or_before(post.get("attestedAt"), human_challenge.get("issuedAt")):
        errors.append(
            "retained postexecution attestedAt must precede run authorization challenge issuedAt")

    path_scope = _closed(scope.get("pathScope"), {
        "allowedReadPaths", "allowedWritePaths", "frozenPaths"}, errors,
        "run authorization.scope.pathScope")
    for key in ("allowedReadPaths", "allowedWritePaths", "frozenPaths"):
        rows = path_scope.get(key)
        if not isinstance(rows, list) or not rows \
                or len(rows) != len({row.casefold() for row in rows
                                     if isinstance(row, str)}) \
                or any(not _run_auth_project_path(row)
                       or resolve_path(root, row, errors, key) is None for row in rows):
            errors.append(f"run authorization.scope.pathScope.{key} is invalid")
    derived_frozen = _derive_w0_frozen_paths(root, package_path, package, errors)
    presented_frozen = path_scope.get("frozenPaths") \
        if isinstance(path_scope.get("frozenPaths"), list) else []
    if presented_frozen != derived_frozen:
        missing = sorted(set(derived_frozen) - set(presented_frozen))
        extra = sorted(set(presented_frozen) - set(derived_frozen))
        errors.append(
            f"run authorization frozenPaths is not the exact W0-derived set; "
            f"missing={missing}, extra={extra}")
    writes = path_scope.get("allowedWritePaths") \
        if isinstance(path_scope.get("allowedWritePaths"), list) else []
    _path_sets_are_disjoint(root, writes, derived_frozen, errors)
    operations = _closed(scope.get("operations"), {"code", "studio", "os", "network"},
                         errors, "run authorization.scope.operations")
    operation_enums = {
        "code": {"read-authorized-files", "write-authorized-files", "run-authorized-tests"},
        "studio": {"none", "inspect-authorized-place", "edit-authorized-place",
                   "playtest-authorized-place"},
        "os": {"read-authorized-files", "write-authorized-files",
               "spawn-authorized-local-tools"},
        "network": {"none", "localhost-rojo", "authorized-studio-mcp"},
    }
    for key, allowed in operation_enums.items():
        values = operations.get(key)
        if not isinstance(values, list) or not values \
                or any(not isinstance(item, str) or item not in allowed for item in values) \
                or len(values) != len(set(values)) \
                or (key in {"studio", "network"} and "none" in values and values != ["none"]):
            errors.append(f"run authorization operations.{key} violates closed enum/set grammar")
    receiver_scope = _closed(scope.get("assignedReceiver"), {
        "skill", "receiverSkillTreeSha256", "workerId", "requestedModel",
        "resolvedModel", "provider", "account", "tool",
        "expectedLoadedProcessClosureSha256", "authConstraints",
        "transferScopeSha256", "operationScopeSha256"},
        errors, "run authorization.scope.assignedReceiver")
    receiver_skill = _closed(receiver_scope.get("skill"), {
        "id", "version", "path", "sha256"}, errors,
        "run authorization.scope.assignedReceiver.skill")
    for key in ("id", "version", "path"):
        if not isinstance(receiver_skill.get(key), str) or not receiver_skill[key].strip():
            errors.append(f"assigned receiver skill.{key} must be non-empty")
    for key in ("workerId", "requestedModel", "resolvedModel", "provider", "account", "tool"):
        if not isinstance(receiver_scope.get(key), str) or not receiver_scope[key].strip():
            errors.append(f"assigned receiver {key} must be non-empty")
    for key in ("receiverSkillTreeSha256", "expectedLoadedProcessClosureSha256",
                "transferScopeSha256", "operationScopeSha256"):
        if not isinstance(receiver_scope.get(key), str) \
                or SHA256_RE.fullmatch(receiver_scope[key]) is None:
            errors.append(f"assigned receiver {key} must be SHA-256")
    if not isinstance(receiver_skill.get("sha256"), str) \
            or SHA256_RE.fullmatch(receiver_skill["sha256"]) is None:
        errors.append("assigned receiver skill.sha256 must be SHA-256")
    constraints = receiver_scope.get("authConstraints")
    if not isinstance(constraints, list) or not constraints \
            or len(constraints) != len(set(constraints)) \
            or any(not isinstance(item, str) or not item.strip() for item in constraints):
        errors.append("assigned receiver authConstraints must be unique non-empty strings")
    transfer = _closed(scope.get("transfer"), {
        "approval", "provider", "account", "model", "destination", "scope",
        "contentSha256", "maxCost", "expiresAt"}, errors,
        "run authorization.scope.transfer")
    for key in ("provider", "account", "model", "destination", "scope"):
        if not isinstance(transfer.get(key), str) or not transfer[key].strip():
            errors.append(f"run authorization transfer.{key} must be non-empty")
    if not isinstance(transfer.get("contentSha256"), str) \
            or SHA256_RE.fullmatch(transfer["contentSha256"]) is None:
        errors.append("run authorization transfer.contentSha256 must be SHA-256")
    max_cost = _closed(transfer.get("maxCost"), {"currency", "amount"}, errors,
                       "run authorization.scope.transfer.maxCost")
    amount = max_cost.get("amount")
    if not isinstance(max_cost.get("currency"), str) \
            or re.fullmatch(r"[A-Z]{3}", max_cost["currency"]) is None \
            or isinstance(amount, bool) or not isinstance(amount, (int, float)) \
            or not math.isfinite(amount) or amount < 0:
        errors.append("run authorization transfer.maxCost is invalid")
    if receiver_scope.get("transferScopeSha256") != canonical_json_sha256(transfer) \
            or receiver_scope.get("operationScopeSha256") != canonical_json_sha256(operations):
        errors.append("assigned receiver transfer/operation digests mismatch")
    transfer_approval = transfer.get("approval") if isinstance(transfer.get("approval"), dict) else {}
    transfer_loaded = _external_ref(transfer_approval, protected, errors,
                                    "run authorization transfer approval", within=auth_root,
                                    with_id=True)
    expires = parsed_timestamp(scope.get("expiresAt"))
    transfer_expires = parsed_timestamp(transfer.get("expiresAt"))
    authorized_at = parsed_timestamp(authorization.get("authorizedAt"))
    now = dt.datetime.now(dt.timezone.utc)
    if None in (authorized_at, expires, transfer_expires) or not (
            authorized_at < expires and authorized_at < transfer_expires and
            now <= expires and now <= transfer_expires):
        errors.append("run authorization/transfer approval is expired or chronological invalid")

    if admission.get("schemaVersion") != "1.0.0" or admission.get("kind") != \
            "w0-run-admission-v1" or admission.get("verdict") != \
            "ready-for-admit-semantic-pass-and-receipt" or admission.get("sideEffectsStarted") is not False \
            or not isinstance(admission.get("id"), str) \
            or re.fullmatch(r"W0-RUN-ADMISSION-[A-Z0-9][A-Z0-9._-]*", admission["id"]) is None:
        errors.append("run admission fixed fields are not ready")
    if admission.get("operatorExpectedConfigSha256") != expected_config_sha256 \
            or admission.get("configSha256") != expected_config_sha256:
        errors.append("run admission does not bind operator expected config SHA-256")
    post_hash = sha256(post_loaded[0]) if post_loaded else None
    if not _framed_string(admission.get("w0RunId"), 16) \
            or admission.get("w0RunId") != challenge_runtime.get("runId") \
            or admission.get("postexecutionAttestationSha256") != post_hash \
            or admission.get("prelaunchAssertionSha256") != post.get(
                "prelaunchAssertionSha256"):
        errors.append("run admission bootstrap/postexecution binding mismatch")
    lock = _closed(admission.get("lock"), {
        "noGapFrom", "through", "enforcementSessionId", "enforcementActive"}, errors,
        "run admission.lock")
    if lock.get("noGapFrom") != "prelaunch" or lock.get("through") != \
            "run-admission-and-first-effect-consumption" or lock.get("enforcementActive") is not True \
            or admission.get("authoritySessionId") != post.get("authoritySessionId") \
            or admission.get("monitorSessionId") != post.get("prepareMonitorSessionId") \
            or lock.get("enforcementSessionId") != admission.get("monitorSessionId"):
        errors.append("run admission continuous authority lock mismatch")
    extension = _closed(admission.get("authorizationInputExtension"), {
        "resolvedRoot", "rootIdentity", "artifactSetSha256", "artifactIdentitySetSha256",
        "proofSealingExclusions"}, errors, "run admission.authorizationInputExtension")
    if Path(str(extension.get("resolvedRoot", ""))).resolve() != auth_root \
            or extension.get("rootIdentity") != challenge_runtime.get(
                "authorizationEvidenceRootIdentity") \
            or extension.get("proofSealingExclusions") != [
                "w0-run-admission-attestation", "w0-run-admission-detached-signature",
                "w0-runtime-admit-execution-attestation",
                "w0-runtime-admit-execution-detached-signature"]:
        errors.append("run admission authorization input root/exclusions mismatch")

    transitive = {presentation_path.resolve(), challenge_path.resolve(), transcript_path.resolve(),
                  statement_path.resolve(), capture_path.resolve(), capture_pv_path.resolve(),
                  authorization_path.resolve()} | pv_transitive
    if transfer_loaded:
        transitive.add(transfer_loaded[0])
    actual_auth_files = {path.resolve() for path in auth_root.rglob("*") if path.is_file()} \
        - {admission_path.resolve(), admission_signature_path.resolve()}
    # The detached admission signature is supplied separately and deliberately
    # excluded by the signed record.  It may already exist beside admission.
    if actual_auth_files != transitive:
        errors.append("authorization evidence root is not the exact transitive input set")
    artifact_rows = [{"path": _absolute_record_path(path), "bytes": path.stat().st_size,
                      "sha256": sha256(path)}
                     for path in sorted(transitive, key=lambda item: str(item))]
    if extension.get("artifactSetSha256") != canonical_json_sha256(artifact_rows) \
            or not isinstance(extension.get("artifactIdentitySetSha256"), str) \
            or SHA256_RE.fullmatch(str(extension.get("artifactIdentitySetSha256"))) is None:
        errors.append("run admission authorization input set digest mismatch")

    current = _closed(admission.get("currentState"), {
        "resolvedProjectRoot", "projectRootIdentity", "projectInputTreeSha256", "b2",
        "w0Package", "firstWp"}, errors, "run admission.currentState")
    project_tree = _current_project_tree_sha256(root, errors)
    if Path(str(current.get("resolvedProjectRoot", ""))).resolve() != root \
            or current.get("projectInputTreeSha256") != project_tree \
            or current.get("projectInputTreeSha256") != challenge_runtime.get(
                "projectInputTreeSha256"):
        errors.append("run admission current project tree/root changed after PREPARE")
    expected_current_b2 = dict(b2_ref, fileIdentity=current.get("b2", {}).get("fileIdentity"))
    expected_current_package = {"id": package.get("packageId"), "path": package_rel,
                                "sha256": sha256(package_path),
                                "fileIdentity": current.get("w0Package", {}).get("fileIdentity")}
    expected_current_wp = dict(first_wp, fileIdentity=current.get("firstWp", {}).get("fileIdentity"))
    if current.get("b2") != expected_current_b2 or current.get("w0Package") != \
            expected_current_package or current.get("firstWp") != expected_current_wp:
        errors.append("run admission current B2/package/first-WP binding mismatch")

    admitted_auth = _closed(admission.get("runAuthorization"), {
        "id", "path", "sha256", "fileIdentity", "scopeCoreSha256", "humanChain",
        "capture", "provenanceVerification"}, errors, "run admission.runAuthorization")
    if any(admitted_auth.get(key) != expected for key, expected in (
            ("id", authorization.get("id")), ("sha256", sha256(authorization_path)),
            ("scopeCoreSha256", scope_hash))) or not _same_absolute_record_path(
                admitted_auth.get("path"), authorization_path):
        errors.append("run admission runAuthorization reference mismatch")
    human_chain = _closed(admitted_auth.get("humanChain"), {
        "presentation", "challenge", "transcript", "statement"}, errors,
        "run admission.runAuthorization.humanChain")
    for key, path in (("presentation", presentation_path), ("challenge", challenge_path),
                      ("transcript", transcript_path), ("statement", statement_path)):
        value = human_chain.get(key)
        if not isinstance(value, dict) or not _same_absolute_record_path(value.get("path"), path) \
                or value.get("sha256") != sha256(path) \
                or not isinstance(value.get("fileIdentity"), str) or not value["fileIdentity"]:
            errors.append(f"run admission humanChain.{key} mismatch")
    for key, path, expected_id in (("capture", capture_path, capture.get("id")),
                                   ("provenanceVerification", capture_pv_path,
                                    pv_preview.get("id"))):
        value = admitted_auth.get(key)
        if not isinstance(value, dict) or value.get("id") != expected_id \
                or not _same_absolute_record_path(value.get("path"), path) \
                or value.get("sha256") != sha256(path) \
                or not isinstance(value.get("fileIdentity"), str) or not value["fileIdentity"]:
            errors.append(f"run admission {key} mismatch")

    receiver = _closed(admission.get("receiver"), {
        "skillId", "skillVersion", "skillPath", "skillSha256",
        "receiverSkillTreeSha256", "workerId", "requestedModel", "resolvedModel",
        "provider", "account", "tool", "expectedLoadedProcessClosureSha256",
        "envelopeSha256", "authorityEnforcementReady", "workerLaunchPolicy"},
        errors, "run admission.receiver")
    skill = receiver_skill
    receiver_expected = {
        "skillId": skill.get("id"), "skillVersion": skill.get("version"),
        "skillPath": skill.get("path"), "skillSha256": skill.get("sha256"),
        **{key: receiver_scope.get(key) for key in (
            "receiverSkillTreeSha256", "workerId", "requestedModel", "resolvedModel",
            "provider", "account", "tool", "expectedLoadedProcessClosureSha256")}}
    if any(receiver.get(key) != value for key, value in receiver_expected.items()) \
            or receiver.get("envelopeSha256") != canonical_json_sha256(receiver_scope):
        errors.append("run admission receiver does not exact-bind assigned receiver envelope")
    receiver_protected = protected + (auth_root,)
    receiver_skill = _external_input_path(
        skill.get("path"), receiver_protected, errors, "assigned receiver skill")
    if receiver_skill is not None and sha256(receiver_skill) != skill.get("sha256"):
        errors.append("assigned receiver skill SHA-256 mismatch")
    if receiver_skill is not None:
        receiver_root = receiver_skill.parent.resolve()
        for protected_root in receiver_protected:
            try:
                receiver_root.relative_to(protected_root)
                overlap = True
            except ValueError:
                try:
                    protected_root.relative_to(receiver_root)
                    overlap = True
                except ValueError:
                    overlap = False
            if overlap:
                errors.append("assigned receiver Skill tree overlaps a protected root")
                break
        receiver_tree_hash = _closed_tree_sha256(
            receiver_root, errors, "assigned receiver Skill tree")
        if receiver_tree_hash != receiver_scope.get("receiverSkillTreeSha256"):
            errors.append("assigned receiver Skill tree digest mismatch")
    if receiver.get("authorityEnforcementReady") is not True or receiver.get(
            "workerLaunchPolicy") != \
            "after-admit-semantic-pass-suspended-pre-entry-under-scope-enforcement-v1":
        errors.append("run admission receiver enforcement/launch policy mismatch")

    chronology = _closed(admission.get("authorizationChronology"), {
        "authorizedAt", "admittedAt", "authorizationExpiresAt"}, errors,
        "run admission.authorizationChronology")
    admitted_at = parsed_timestamp(chronology.get("admittedAt"))
    admission_expires = parsed_timestamp(admission.get("admissionExpiresAt"))
    pv_verified_at = parsed_timestamp(validated_run_pv.get("verifiedAt"))
    if chronology.get("authorizedAt") != authorization.get("authorizedAt") \
            or chronology.get("authorizationExpiresAt") != scope.get("expiresAt") \
            or None in (authorized_at, admitted_at, expires, admission_expires) \
            or not (authorized_at <= admitted_at < expires and admitted_at < admission_expires):
        errors.append("run admission chronology mismatch")
    lifetime = admission.get("admissionLifetimeSeconds")
    max_lifetime = runtime.get("w0ValidatorRuntime", {}).get(
        "_immutableRuntimeAuthority", {}).get("maxAdmissionLifetimeSeconds") \
        if runtime else None
    max_skew = runtime.get("w0ValidatorRuntime", {}).get(
        "_immutableRuntimeAuthority", {}).get("maxClockSkewSeconds") \
        if runtime else None
    if type(lifetime) is not int or not isinstance(max_lifetime, int) or not 1 <= lifetime <= \
            max_lifetime or admitted_at is None or admission_expires is None \
            or (admission_expires - admitted_at).total_seconds() != lifetime \
            or now > admission_expires:
        errors.append("run admission lifetime/expiry mismatch")
    if pv_verified_at is None or admitted_at is None or type(max_skew) is not int \
            or not (pv_verified_at <= admitted_at <= now + dt.timedelta(seconds=max_skew)):
        errors.append("run admission requires PV.verifiedAt <= admittedAt <= current time+clock skew")
    one_time = _closed(admission.get("oneTimeAdmission"), {
        "registryAuthority", "registryId", "eventId", "nonce", "tokenSha256", "consumed",
        "consumptionPolicy"}, errors, "run admission.oneTimeAdmission")
    if any(not isinstance(one_time.get(key), str) or not one_time[key]
           for key in ("registryAuthority", "registryId", "eventId")) \
            or not _framed_string(one_time.get("nonce"), 32) \
            or one_time.get("nonce") == challenge_runtime.get("receiverNonce"):
        errors.append("run admission one-time registry/event/nonce is invalid or replayed")
    token_input = ("W0-ADMIT-v1\0" + str(admission.get("id")) + "\0" +
                   str(admission.get("w0RunId")) + "\0" + scope_hash + "\0" +
                   str(one_time.get("nonce"))).encode("utf-8")
    if one_time.get("tokenSha256") != hashlib.sha256(token_input).hexdigest() \
            or one_time.get("consumed") is not False or one_time.get("consumptionPolicy") != \
            "authority-atomic-consume-after-admit-semantic-pass-before-suspended-worker-launch-v1":
        errors.append("run admission one-time token binding mismatch")
    receipt_outputs = _closed(admission.get("admitExecutionReceiptOutputs"), {
        "attestationPath", "detachedSignaturePath"}, errors,
        "run admission.admitExecutionReceiptOutputs")
    receipt_paths: list[Path] = []
    for key in ("attestationPath", "detachedSignaturePath"):
        raw = receipt_outputs.get(key)
        path = _external_output_path(
            raw, protected, errors,
            f"run admission.admitExecutionReceiptOutputs.{key}", within=auth_root)
        if path is not None:
            receipt_paths.append(path)
    if len(receipt_paths) == 2 and receipt_paths[0] == receipt_paths[1]:
        errors.append("run admission receipt output paths must be distinct")
    enforcement = _closed(admission.get("enforcement"), {
        "pathScopeSha256", "operationScopeSha256", "transferScopeSha256",
        "exactAllowedReadPaths", "exactAllowedWritePaths", "exactFrozenPaths",
        "exactOperations", "exactDeniedOperations", "active"}, errors,
        "run admission.enforcement")
    expected_enforcement = {
        "pathScopeSha256": canonical_json_sha256(path_scope),
        "operationScopeSha256": canonical_json_sha256(operations),
        "transferScopeSha256": canonical_json_sha256(transfer),
        "exactAllowedReadPaths": path_scope.get("allowedReadPaths"),
        "exactAllowedWritePaths": path_scope.get("allowedWritePaths"),
        "exactFrozenPaths": path_scope.get("frozenPaths"), "exactOperations": operations,
        "exactDeniedOperations": RUN_AUTH_DENIALS, "active": True,
    }
    if enforcement != expected_enforcement:
        errors.append("run admission enforcement differs from exact human scope")
    return {"pass": not errors, "errors": errors, "mode": "run-authorization",
            "authorizationId": authorization.get("id"), "admissionId": admission.get("id"),
            "oneTimeTokenSha256": one_time.get("tokenSha256")}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, default=Path.cwd())
    parser.add_argument(
        "--source-project-root", type=Path, default=None,
        help="commit/snapshot historical evidence root; defaults to project-root")
    parser.add_argument("--prefix")
    parser.add_argument("--package", type=Path, required=True,
                        help="W0 handoff package path (project-root relative unless absolute)")
    parser.add_argument(
        "--provenance-config", type=Path, required=True,
        help="absolute operator-owned verifier config outside project and installed skill roots")
    parser.add_argument(
        "--installed-skill-root", type=Path, required=True,
        help="absolute canonical installed claude-roblox-dev-docs-creator root")
    parser.add_argument(
        "--run-authorization", action="store_true",
        help="validate the operator-external W0 run authorization/admission chain")
    parser.add_argument("--expected-config-sha256")
    parser.add_argument("--launch-challenge", type=Path)
    parser.add_argument("--run-presentation", type=Path)
    parser.add_argument("--run-human-challenge", type=Path)
    parser.add_argument("--run-transcript", type=Path)
    parser.add_argument("--run-statement", type=Path)
    parser.add_argument("--run-capture", type=Path)
    parser.add_argument("--run-capture-provenance", type=Path)
    parser.add_argument("--run-authorization-record", type=Path)
    parser.add_argument("--run-admission", type=Path)
    parser.add_argument("--run-admission-signature", type=Path)
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
    if args.run_authorization:
        required = {
            "--expected-config-sha256": args.expected_config_sha256,
            "--launch-challenge": args.launch_challenge,
            "--run-presentation": args.run_presentation,
            "--run-human-challenge": args.run_human_challenge,
            "--run-transcript": args.run_transcript,
            "--run-statement": args.run_statement,
            "--run-capture": args.run_capture,
            "--run-capture-provenance": args.run_capture_provenance,
            "--run-authorization-record": args.run_authorization_record,
            "--run-admission": args.run_admission,
            "--run-admission-signature": args.run_admission_signature,
        }
        missing = [name for name, value in required.items() if value is None]
        if missing:
            parser.error("run authorization mode requires " + ", ".join(missing))
        result = validate_run_authorization_admission(
            root, package_path, args.provenance_config.resolve(),
            str(args.expected_config_sha256), args.installed_skill_root.resolve(),
            args.launch_challenge.resolve(), args.run_presentation.resolve(),
            args.run_human_challenge.resolve(), args.run_transcript.resolve(),
            args.run_statement.resolve(), args.run_capture.resolve(),
            args.run_capture_provenance.resolve(), args.run_authorization_record.resolve(),
            args.run_admission.resolve(), args.run_admission_signature.resolve())
    else:
        if not args.prefix:
            parser.error("--prefix is required outside --run-authorization mode")
        result = validate(
            root, args.prefix, package_path, source_root, args.provenance_config,
            args.installed_skill_root)
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
