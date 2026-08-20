#!/usr/bin/env python3
"""Emit deterministic D4 capsule preflight facts without ambient executables.

The caller supplies an exact candidate manifest, target-revision source root,
and either an absolute pinned Git executable or the literal ``disabled``. Output is
one canonical JSON value on stdout; diagnostics go to stderr.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import stat
import subprocess
import sys
from pathlib import Path
from typing import Any

from strict_json import loads as strict_json_loads


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def strict_json(path: Path) -> dict[str, Any]:
    value = strict_json_loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError("candidate manifest must contain exactly one JSON object")
    return value


def snapshot_entries(root: Path) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    identities: set[tuple[int, int]] = set()
    for current, dirs, files in os.walk(root, topdown=True, followlinks=False):
        base = Path(current)
        dirs[:] = sorted(dirs)
        for name in [*dirs, *sorted(files)]:
            path = base / name
            info = path.lstat()
            mode = info.st_mode
            reparse = bool(getattr(info, "st_file_attributes", 0)
                           & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400))
            if stat.S_ISLNK(mode) or reparse:
                raise ValueError(f"source tree contains symlink/reparse point: {path}")
            if name in dirs:
                if not stat.S_ISDIR(mode):
                    raise ValueError(f"source tree contains special entry: {path}")
                continue
            if not stat.S_ISREG(mode):
                raise ValueError(f"source tree contains special file: {path}")
            if info.st_nlink != 1:
                raise ValueError(f"source tree contains a hardlinked file: {path}")
            identity = (info.st_dev, info.st_ino)
            if identity in identities:
                raise ValueError(f"source tree reuses one OS file identity: {path}")
            identities.add(identity)
            rel = path.relative_to(root).as_posix()
            payload = path.read_bytes()
            entries.append({
                "path": rel, "bytes": len(payload), "sha256": sha256_bytes(payload),
            })
    entries.sort(key=lambda item: item["path"])
    return entries


def run_git(git: Path, root: Path, args: list[str]) -> bytes:
    clean_env = {
        "SYSTEMROOT": os.environ.get("SYSTEMROOT", ""),
        "WINDIR": os.environ.get("WINDIR", ""),
    }
    result = subprocess.run(
        [str(git), "-C", str(root), *args], shell=False, env=clean_env,
        stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        timeout=60, check=False)
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace")[:1000]
        raise ValueError(f"pinned Git failed ({result.returncode}): {detail}")
    return result.stdout


def commit_entries(git: Path, root: Path, revision: str) -> list[dict[str, Any]]:
    raw = run_git(git, root, ["ls-tree", "-r", "-z", "--full-tree", revision])
    entries: list[dict[str, Any]] = []
    for record in raw.split(b"\0"):
        if not record:
            continue
        header, raw_path = record.split(b"\t", 1)
        mode, kind, object_id = header.decode("ascii").split(" ", 2)
        if kind != "blob" or mode == "120000":
            raise ValueError("commit tree contains non-regular or symlink entry")
        path = raw_path.decode("utf-8")
        payload = run_git(git, root, ["cat-file", "blob", object_id])
        entries.append({
            "path": path, "bytes": len(payload), "sha256": sha256_bytes(payload),
        })
    entries.sort(key=lambda item: item["path"])
    return entries


def candidate_revision(manifest: dict[str, Any]) -> dict[str, Any]:
    revision = manifest.get("revision")
    if not isinstance(revision, dict) or set(revision) != {
            "kind", "value", "snapshotRoot", "gitStatusEvidence"}:
        raise ValueError("candidate revision is missing or not closed")
    return revision


def find_project_root(manifest_path: Path, revision: dict[str, Any], source: Path) -> Path:
    snapshot = revision.get("snapshotRoot")
    if revision.get("kind") == "snapshot" and isinstance(snapshot, str):
        for parent in manifest_path.parents:
            try:
                if (parent / snapshot).resolve(strict=True) == source:
                    return parent
            except OSError:
                continue
        raise ValueError("source root does not resolve exactly to revision.snapshotRoot")
    if revision.get("kind") == "commit":
        if not (source / ".git").exists():
            raise ValueError("commit source root is not a repository root")
        return source
    raise ValueError("unsupported revision kind")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--operation", required=True,
                        choices=("source-state", "revision", "tree"))
    parser.add_argument("--source-root", required=True, type=Path)
    parser.add_argument("--candidate-manifest", required=True, type=Path)
    parser.add_argument("--git-executable", required=True)
    args = parser.parse_args()
    try:
        source = args.source_root.resolve(strict=True)
        manifest_path = args.candidate_manifest.resolve(strict=True)
        if not source.is_dir() or not manifest_path.is_file():
            raise ValueError("source root/candidate manifest type mismatch")
        manifest = strict_json(manifest_path)
        revision = candidate_revision(manifest)
        project_root = find_project_root(manifest_path, revision, source)
        git: Path | None = None
        if args.git_executable.casefold() != "disabled":
            git = Path(args.git_executable).resolve(strict=True)
            if not git.is_file() or not git.is_absolute():
                raise ValueError("Git pin must resolve to an absolute file")
        if revision.get("kind") == "commit" and git is None:
            raise ValueError("commit revision requires an explicit pinned Git executable")
        entries = (commit_entries(git, source, str(revision.get("value")))
                   if revision.get("kind") == "commit" and git is not None
                   else snapshot_entries(source))
        files = manifest.get("files")
        if not isinstance(files, list) or not files:
            raise ValueError("candidate manifest files must be non-empty")
        projected = [{"path": item.get("path"), "bytes": item.get("bytes"),
                      "sha256": item.get("sha256")} for item in files
                     if isinstance(item, dict)]
        projected.sort(key=lambda item: str(item.get("path")))
        if len(projected) != len(files) or projected != entries:
            raise ValueError("candidate manifest must exact-cover the complete source tree")
        if args.operation == "tree":
            value: Any = entries
        elif args.operation == "revision":
            value = {
                "candidateId": manifest.get("baselineId"), "revision": revision,
                "candidateManifestSha256": sha256_bytes(manifest_path.read_bytes()),
            }
        else:
            evidence = revision.get("gitStatusEvidence")
            evidence_ref: dict[str, Any] | None = None
            if isinstance(evidence, str):
                evidence_path = (project_root / evidence).resolve(strict=True)
                try:
                    evidence_path.relative_to(project_root)
                except ValueError as exc:
                    raise ValueError("gitStatusEvidence escapes project root") from exc
                if not evidence_path.is_file():
                    raise ValueError("gitStatusEvidence is not a file")
                evidence_ref = {
                    "path": evidence,
                    "sha256": sha256_bytes(evidence_path.read_bytes()),
                }
            value = {
                "candidateId": manifest.get("baselineId"), "revisionKind": revision.get("kind"),
                "sourceTreeEntriesSha256": sha256_bytes(canonical_bytes(entries)),
                "sourceStateEvidence": evidence_ref,
            }
        sys.stdout.buffer.write(canonical_bytes(value) + b"\n")
        return 0
    except (OSError, UnicodeError, ValueError, subprocess.SubprocessError) as exc:
        print(f"D4 preflight failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
