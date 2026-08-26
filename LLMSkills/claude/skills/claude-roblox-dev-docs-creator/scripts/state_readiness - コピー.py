#!/usr/bin/env python3
"""Shared state-aware D5 unresolved-token scanner."""
from __future__ import annotations

import re
from pathlib import Path
from typing import Any


STATE_PATTERNS = [
    (re.compile(r"\[\s*proposal\s*\]", re.I), "[PROPOSAL]", "unapproved proposal"),
    (re.compile(r"\[\s*assumption\s*\]", re.I), "[ASSUMPTION]", "unverified assumption"),
    (re.compile(r"\[\s*open\s+blocking\s*:\s*yes\s*\]", re.I),
     "[OPEN blocking: yes]", "blocking open question"),
]
PLACEHOLDER_TOKEN_RE = re.compile(r"\{\{[^{}\n]{1,60}\}\}|\{[^{}\n]{0,60}\}")
PLACEHOLDER_WORD_RE = re.compile(r"[A-Za-z_぀-ヿ一-鿿]")
KNOWN_FORMAT_RE = re.compile(
    r"(?<![A-Za-z0-9_])(?:[A-Z][A-Z0-9]*"
    r"(?:-\{(?:DOMAIN|NNN|ID|PREFIX|YYYY|MM|DD)\})+"
    r"|\{YYYY\}-\{MM\}-\{DD\})(?![A-Za-z0-9_])")


def _fixed_legend_definition(line: str, token: str) -> bool:
    return re.fullmatch(
        r"\s*[-*]\s*`?" + re.escape(token) +
        r"`?\s*(?:means|=|:|：|—)\s+[^|\[\]]+\s*", line, re.I) is not None


def _active_placeholders(line: str) -> list[str]:
    tokens: list[tuple[int, int, bool, str]] = []
    for match in PLACEHOLDER_TOKEN_RE.finditer(line):
        token = match.group(0)
        if token.startswith("{{"):
            qualified = True
        else:
            body = token[1:-1]
            qualified = (1 <= len(body) <= 40
                         and not any(char in body for char in ',/"\':')
                         and PLACEHOLDER_WORD_RE.search(body) is not None)
        tokens.append((match.start(), match.end(), qualified, token))
    format_spans = [(match.start(), match.end()) for match in KNOWN_FORMAT_RE.finditer(line)]
    active: list[str] = []
    for start, end, qualified, token in tokens:
        if not qualified:
            continue
        if not any(span_start <= start and end <= span_end
                   for span_start, span_end in format_spans):
            active.append(token)
    if "TODO-UNRESOLVED" in line:
        active.append("TODO-UNRESOLVED")
    return active


def scan_readiness_text(text: str, suffix: str | Path) -> list[dict[str, Any]]:
    """Return active unresolved state tokens/placeholders with line numbers.

    Markdown code fences and exact dedicated state-tag legend definitions are
    explanatory. Literal active-state tags remain active everywhere else,
    including history and Completed closure rows.
    """
    markdown = str(suffix).lower().endswith(".md")
    issues: list[dict[str, Any]] = []
    headings: list[tuple[int, str]] = []
    fence: str | None = None
    for number, line in enumerate(text.splitlines(), 1):
        stripped = line.lstrip()
        if markdown:
            fence_match = re.match(r"^(```+|~~~+)", stripped)
            if fence_match:
                marker = fence_match.group(1)[0]
                fence = None if fence == marker else marker if fence is None else fence
                continue
            if fence is not None:
                continue
            heading = re.match(r"^(#{1,6})\s+(.*?)\s*$", line)
            if heading:
                level = len(heading.group(1))
                headings = [(prior, title) for prior, title in headings if prior < level]
                headings.append((level, heading.group(2).strip().casefold()))
        section_titles = [title for _, title in headings]
        in_legend = markdown and any(
            "tag legend" in title or "state tag" in title and "legend" in title
            for title in section_titles)
        for pattern, canonical, label in STATE_PATTERNS:
            matches = list(pattern.finditer(line))
            if not matches:
                continue
            token = matches[0].group(0)
            # Literal active-state tags never belong in history rows; their
            # terminal status is expressed by the structured history fields.
            exempt = in_legend and _fixed_legend_definition(line, token)
            if not exempt:
                issues.append({
                    "kind": "state", "token": token, "canonical": canonical,
                    "label": label,
                    "line": number,
                })
        for placeholder in _active_placeholders(line):
            issues.append({
                "kind": "placeholder", "token": placeholder,
                "label": "unresolved template placeholder", "line": number,
            })
    return issues
