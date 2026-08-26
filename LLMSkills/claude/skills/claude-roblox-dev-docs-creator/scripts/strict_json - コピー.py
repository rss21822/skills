#!/usr/bin/env python3
"""Small standard-library JSON decoder that rejects ambiguous input."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any


class StrictJsonError(ValueError):
    pass


def _closed_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise StrictJsonError(f"duplicate key {key!r}")
        result[key] = value
    return result


def _reject_constant(token: str) -> Any:
    raise StrictJsonError(f"non-finite JSON constant {token!r}")


def loads(text: str) -> Any:
    return json.loads(
        text, object_pairs_hook=_closed_pairs, parse_constant=_reject_constant)


def load_path(path: Path, *, encoding: str = "utf-8-sig") -> Any:
    return loads(path.read_text(encoding=encoding))
