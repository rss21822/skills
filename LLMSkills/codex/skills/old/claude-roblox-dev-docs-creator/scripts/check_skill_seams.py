#!/usr/bin/env python3
"""Fail-closed checks for the Codex Roblox documentation skill contracts."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Callable


SKILLS_ROOT = Path(__file__).resolve().parents[2]
CREATOR = "claude-roblox-dev-docs-creator"


class SeamFailure(RuntimeError):
    pass


def read(relative: str) -> str:
    path = SKILLS_ROOT / relative
    if not path.is_file():
        raise SeamFailure(f"missing file: {relative}")
    return path.read_text(encoding="utf-8", errors="strict")


def require(relative: str, *needles: str) -> None:
    text = read(relative)
    for needle in needles:
        if needle not in text:
            raise SeamFailure(f"{relative}: missing contract marker: {needle}")


def forbid(relative: str, *needles: str) -> None:
    text = read(relative)
    for needle in needles:
        if needle in text:
            raise SeamFailure(f"{relative}: forbidden stale contract: {needle}")


def run_checks() -> list[str]:
    checks: list[tuple[str, Callable[[], None]]] = [
        ("codex-entrypoint", lambda: require(
            f"{CREATOR}/SKILL.md",
            "実行runtimeはCodex", "AGENTS.md", ".codex/roblox-docs")),
        ("codex-stage-router", lambda: require(
            f"{CREATOR}/SKILL.md",
            "collaboration.spawn_agent", 'fork_turns: "none"',
            "create_thread", "roblox-dev-skill")),
        ("no-claude-skill-tool", lambda: forbid(
            f"{CREATOR}/SKILL.md", "を `Skill` ツールで呼ぶ")),
        ("codex-runtime-tools", lambda: require(
            f"{CREATOR}/references/autonomous-execution.md",
            "exec_command", "apply_patch", "mcp__Roblox_Studio__*",
            "`web` tool", "`computer-use` Skill")),
        ("no-claude-browser-runtime", lambda: forbid(
            f"{CREATOR}/references/autonomous-execution.md",
            "mcp__Claude_Browser__", "preview_start")),
        ("internal-agent-contract", lambda: require(
            f"{CREATOR}/references/worker-registry.md",
            "Codex内部agent", "collaboration.spawn_agent",
            'fork_turns: "none"', "transferApproval`を作らない")),
        ("internal-envelope-boundary", lambda: require(
            f"{CREATOR}/references/execution-envelope.md",
            "Codex内部collaboration agent", "第三者送信・Class B envelopeの対象外",
            "create_thread`は内部worker代替に使わない")),
        ("no-missing-worker-route", lambda: forbid(
            f"{CREATOR}/references/worker-registry.md",
            "codex-run", "Claude subagent", "claude-roblox-mvp-buildout")),
        ("w0-codex-handoff", lambda: require(
            f"{CREATOR}/references/orchestration.md",
            "roblox-dev-skill", "使用者が実装開始も依頼した場合",
            "receiver契約を満たすことを推測せず")),
        ("roblox-dev-skill-present", lambda: require(
            "roblox-dev-skill/SKILL.md",
            "do not use for concept-only game design or documentation",
            "External-change boundary")),
        ("agents-template", lambda: require(
            f"{CREATOR}/templates/agents_md.md",
            "Codex Implementation Rules", "docs/{{PREFIX}}_docs_index.md")),
        ("scaffold-codex-layout", lambda: require(
            f"{CREATOR}/scripts/scaffold_project.py",
            'OPS_CONFIG_DIR = Path(".codex") / "roblox-docs"',
            '("agents_md.md", "AGENTS.md")')),
        ("validator-agents-root", lambda: require(
            f"{CREATOR}/scripts/validate_docs.py", '"AGENTS.md"')),
        ("no-legacy-scaffold-layout", lambda: forbid(
            f"{CREATOR}/scripts/scaffold_project.py",
            '"claude_md.md"', '"CLAUDE.md"', 'project_root / ".claude"')),
        ("d4-policy-codex-config", lambda: require(
            f"{CREATOR}/templates/d4_audit_policy_manifest.json",
            ".codex/roblox-docs/doc-lint.json",
            ".codex/roblox-docs/p0-check.json")),
        ("no-d4-policy-legacy-config", lambda: forbid(
            f"{CREATOR}/templates/d4_audit_policy_manifest.json", ".claude/")),
        ("openai-ui-metadata", lambda: require(
            f"{CREATOR}/agents/openai.yaml",
            'display_name: "Roblox Dev Docs Creator"',
            "Use $claude-roblox-dev-docs-creator")),
        ("full-stage-route", lambda: require(
            f"{CREATOR}/references/orchestration.md",
            "D4 → P0 → post-P0 D4 → D5 → W0", "P0  契約確定", "D5  人間承認")),
        ("d5-atomic-sync", lambda: require(
            f"{CREATOR}/templates/d5_approval_handoff.md",
            "Status", "Last approved", "docs index", "manifest", "DECISIONS")),
        ("d4-findings-only", lambda: require(
            f"{CREATOR}/references/audit-d4.md",
            "findings-only", "read-only",
            "D4合格 / P0着手資格あり（人間P0開始承認待ち）",
            "post-P0 D4合格 / B1昇格可 / D5提示可能")),
        ("d4-three-lanes", lambda: require(
            f"{CREATOR}/references/phase-definitions.md",
            "consistency-auditor", "roblox-readiness-auditor", "clean-room-auditor",
            "3系統すべてが必要")),
        ("p0-before-d5", lambda: require(
            f"{CREATOR}/references/phase-definitions.md",
            "D5 の前提工程であり、D5 承認そのものではない",
            "formal document の `Status` / `Last approved` を変更しない")),
        ("absolute-rules", lambda: require(
            f"{CREATOR}/references/absolute-rules.md",
            "二重正本を禁止", "D5 の全ゲートに合格", "blocked-safety")),
        ("approved-transfer", lambda: require(
            f"{CREATOR}/references/execution-envelope.md",
            "approved-transfer", "transferApproval", "allowedContentSha256")),
        ("class-b-json-envelope", lambda: require(
            f"{CREATOR}/references/execution-envelope.md",
            '"schema_version": 1', '"artifact"', '"report"')),
    ]

    passed: list[str] = []
    for name, check in checks:
        check()
        passed.append(name)
    return passed


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    try:
        passed = run_checks()
    except (OSError, UnicodeError, SeamFailure) as exc:
        if args.json:
            print(json.dumps({"pass": False, "error": str(exc)}, ensure_ascii=False))
        else:
            print(f"FAIL: {exc}")
        return 1
    payload = {"pass": True, "checks": passed, "count": len(passed)}
    print(json.dumps(payload, ensure_ascii=False) if args.json
          else f"PASS: {len(passed)} Codex skill seam checks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
