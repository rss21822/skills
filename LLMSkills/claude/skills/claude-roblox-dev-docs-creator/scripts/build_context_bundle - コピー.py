#!/usr/bin/env python
"""Build a bounded, hash-attested inline context bundle for text-only workers."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath


DEFAULT_DENY = (
    r"(^|/)\.env($|\.)",
    r"(^|/).ssh(/|$)",
    r"(^|/).aws(/|$)",
    r"(^|/).azure(/|$)",
    r"(^|/).config/gcloud(/|$)",
    r"\.(pem|pfx|p12|key)$",
    r"(^|/)(id_rsa|id_ed25519)$",
)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def resolve_inside(root: Path, raw: str, *, must_exist: bool) -> tuple[Path, str]:
    if not raw or Path(raw).is_absolute() or re.search(r"[*?[]]", raw):
        raise ValueError(f"explicit project-relative path required: {raw!r}")
    rel = PurePosixPath(raw.replace("\\", "/"))
    if ".." in rel.parts or rel.as_posix() in {".", ""}:
        raise ValueError(f"path traversal or empty path rejected: {raw!r}")
    candidate = root.joinpath(*rel.parts)
    cursor = root
    for part in rel.parts:
        cursor = cursor / part
        if cursor.is_symlink():
            raise ValueError(f"symlink path rejected: {raw!r}")
    resolved = candidate.resolve(strict=must_exist)
    try:
        resolved.relative_to(root)
    except ValueError as exc:
        raise ValueError(f"path escapes project root: {raw!r}") from exc
    return resolved, rel.as_posix()


def atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(
        prefix=path.name + ".", suffix=".tmp", dir=path.parent
    )
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp_name, path)
    finally:
        if os.path.exists(temp_name):
            os.unlink(temp_name)


def build_bundle(
    project_root: Path,
    includes: list[str],
    output: str,
    max_bytes: int,
    deny_patterns: list[str],
) -> dict[str, object]:
    root = project_root.resolve(strict=True)
    if not root.is_dir():
        raise ValueError(f"project root is not a directory: {root}")
    if not includes:
        raise ValueError("at least one --include is required")
    if max_bytes <= 0:
        raise ValueError("--max-bytes must be positive")

    deny = [re.compile(pattern, re.IGNORECASE) for pattern in deny_patterns]
    output_path, output_rel = resolve_inside(root, output, must_exist=False)
    sidecar_path = output_path.with_name(output_path.name + ".attestation.json")

    entries: list[tuple[str, bytes, str]] = []
    seen: set[str] = set()
    source_bytes = 0
    for raw in includes:
        path, rel = resolve_inside(root, raw, must_exist=True)
        if rel in seen:
            raise ValueError(f"duplicate include: {rel}")
        seen.add(rel)
        if rel == output_rel or path == sidecar_path:
            raise ValueError("output and attestation cannot be included as source")
        if any(pattern.search(rel) for pattern in deny):
            raise ValueError(f"denied path: {rel}")
        if path.is_symlink() or not path.is_file():
            raise ValueError(f"regular non-symlink file required: {rel}")
        data = path.read_bytes()
        try:
            data.decode("utf-8", errors="strict")
        except UnicodeDecodeError as exc:
            raise ValueError(f"UTF-8 text required: {rel}") from exc
        source_bytes += len(data)
        if source_bytes > max_bytes:
            raise ValueError(
                f"source bytes exceed approved limit: {source_bytes} > {max_bytes}"
            )
        entries.append((rel, data, sha256(data)))

    manifest = {
        "schema": 1,
        "projectRootName": root.name,
        "sourceBytes": source_bytes,
        "maxBytes": max_bytes,
        "files": [
            {"path": rel, "bytes": len(data), "sha256": digest}
            for rel, data, digest in entries
        ],
    }
    chunks = [
        b"# Inline context bundle\n\n",
        b"Manifest (JSON):\n",
        json.dumps(manifest, ensure_ascii=False, sort_keys=True, indent=2).encode("utf-8"),
        b"\n\n",
    ]
    for rel, data, digest in entries:
        header = (
            f'<<<FILE path="{rel}" bytes="{len(data)}" sha256="{digest}">>>\n'
        ).encode("utf-8")
        chunks.extend((header, data, b"\n<<<END_FILE>>>\n\n"))
    bundle = b"".join(chunks)
    if len(bundle) > max_bytes:
        raise ValueError(
            f"bundle bytes exceed approved limit: {len(bundle)} > {max_bytes}"
        )

    atomic_write(output_path, bundle)

    attestation = {
        "schema": 1,
        "createdAt": datetime.now(timezone.utc).isoformat(),
        "output": output_rel,
        "bundleBytes": len(bundle),
        "bundleSha256": sha256(bundle),
        "manifest": manifest,
    }
    atomic_write(
        sidecar_path,
        (json.dumps(attestation, ensure_ascii=False, sort_keys=True, indent=2)
         + "\n").encode("utf-8"),
    )
    return attestation


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--include", action="append", default=[])
    parser.add_argument("--max-bytes", type=int, required=True)
    parser.add_argument("--deny-regex", action="append", default=[])
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        result = build_bundle(
            Path(args.project_root),
            args.include,
            args.output,
            args.max_bytes,
            [*DEFAULT_DENY, *args.deny_regex],
        )
    except (OSError, ValueError, re.error) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
