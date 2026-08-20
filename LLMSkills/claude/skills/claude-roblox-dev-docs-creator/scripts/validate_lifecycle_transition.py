#!/usr/bin/env python3
"""Validate the externally authenticated lifecycle proof used by post-P0 D4.

The fixed D4 policy invokes this entrypoint from the sanitized `_policy_runtime`
copy.  It accepts no package-wide shortcuts: initial D4 is rejected, the capsule
must bind a B0 -> P0-CAND snapshot transition, and all referenced approval,
write-log, snapshot, and provenance bytes are revalidated by the shared semantic
implementation.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from validate_d5_acceptance import validate_p0_transition_capsule


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--capsule", type=Path, required=True)
    parser.add_argument("--transition-type", choices=("p0",), required=True)
    parser.add_argument("--provenance-config", type=Path, required=True)
    parser.add_argument(
        "--fresh-authenticate", action="store_true", required=True,
        help="require the pinned external verifier to authenticate every bound PV")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    root = args.project_root.resolve()
    if not root.is_dir():
        parser.error(f"project root does not exist: {root}")
    if not args.provenance_config.is_absolute():
        parser.error("--provenance-config must be absolute; auto-discovery is forbidden")
    capsule = args.capsule if args.capsule.is_absolute() else root / args.capsule
    result = validate_p0_transition_capsule(
        root, capsule, args.provenance_config,
        fresh_authenticate=args.fresh_authenticate)
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print("PASS" if result["pass"] else "FAIL")
        for error in result["errors"]:
            print(f"ERROR: {error}")
    return 0 if result["pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
