#!/usr/bin/env python3
"""Fail-closed checks for contracts shared by the Roblox Claude skills."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


SKILLS_ROOT = Path(__file__).resolve().parents[2]
CLAUDE_ROOT = SKILLS_ROOT.parent


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


def forbid_in_tree(relative_dir: str, *needles: str) -> None:
    """統合済み skill への参照が tree 内へ残っていないことを確認する。"""
    root = SKILLS_ROOT / relative_dir
    if not root.is_dir():
        raise SeamFailure(f"missing dir: {relative_dir}")
    hits: list[str] = []
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.suffix not in {".md", ".py", ".json"}:
            continue
        if "__pycache__" in path.parts or path.name.startswith("_merge_"):
            continue
        # 本 checker 自身は needle を文字列として保持するので対象外
        if path.resolve() == Path(__file__).resolve():
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        for needle in needles:
            if needle in text:
                hits.append(f"{path.relative_to(SKILLS_ROOT).as_posix()}: {needle}")
    if hits:
        raise SeamFailure("merged-skill reference remains: " + "; ".join(hits[:8]))


def run_checks() -> list[str]:
    checks: list[tuple[str, callable]] = [
        # --- 統合 skill 内部の契約 ---
        ("full-stage-route", lambda: require(
            "claude-roblox-dev-docs-creator/references/orchestration.md",
            "D4 → P0 → post-P0 D4 → D5 → W0", "P0  契約確定", "D5  人間承認")),
        ("stage-router-mechanism", lambda: require(
            "claude-roblox-dev-docs-creator/SKILL.md",
            "stage router",
            "subagent または新規セッション。同一セッションで実行しない",
            "を `Skill` ツールで呼ぶ")),
        ("d5-atomic-sync", lambda: require(
            "claude-roblox-dev-docs-creator/templates/d5_approval_handoff.md",
            "Status", "Last approved", "docs index", "manifest", "DECISIONS")),
        ("d4-findings-only", lambda: require(
            "claude-roblox-dev-docs-creator/references/audit-d4.md",
            "findings-only", "read-only",
            "D4合格 / P0着手資格あり（人間P0開始承認待ち）",
            "post-P0 D4合格 / B1昇格可 / D5提示可能")),
        ("d4-clean-independence", lambda: require(
            "claude-roblox-dev-docs-creator/references/audit-d4.md",
            "他監査者の出力を**渡さず**")),
        ("d4-three-lanes", lambda: require(
            "claude-roblox-dev-docs-creator/references/phase-definitions.md",
            "consistency-auditor", "roblox-readiness-auditor", "clean-room-auditor",
            "3系統すべてが必要")),
        ("p0-before-d5", lambda: require(
            "claude-roblox-dev-docs-creator/references/phase-definitions.md",
            "D5 の前提工程であり、D5 承認そのものではない",
            "formal document の `Status` / `Last approved` を変更しない")),
        ("p0-work-units", lambda: require(
            "claude-roblox-dev-docs-creator/references/p0-work-units.md",
            "承認記録", "open closure")),
        ("p0-state-checker", lambda: require(
            "claude-roblox-dev-docs-creator/references/p0-approval-and-state.md",
            "check_p0_state.py", "wp-status-cross-doc")),
        ("absolute-rules", lambda: require(
            "claude-roblox-dev-docs-creator/references/absolute-rules.md",
            "二重正本を禁止", "D5 の全ゲートに合格", "blocked-safety")),
        ("state-tags-single-owner", lambda: require(
            "claude-roblox-dev-docs-creator/references/quality-gates.md",
            "[AI-APPROVED]", "人間のみ。委任 AI は作成できない", "Gate 5")),
        ("named-role-assumed", lambda: require(
            "claude-roblox-dev-docs-creator/references/worker-registry.md",
            "責務名は固定プラグイン名でも特定モデルの識別子でもない",
            "指示役を正本執筆の fallback にしない")),
        ("ownership-table", lambda: require(
            "claude-roblox-dev-docs-creator/SKILL.md",
            "正本の所有表", "references/audit-d4.md")),
        ("human-ai-ledgers", lambda: require(
            "claude-roblox-dev-docs-creator/templates/human_actions.md",
            "`human-only`", "AI_ACTIONS.md")),
        ("ai-ledger-template", lambda: require(
            "claude-roblox-dev-docs-creator/templates/ai_actions.md",
            "approved-transfer", "blocked-permission", "blocked-capability")),
        ("lint-ledger-keys", lambda: require(
            "claude-roblox-dev-docs-creator/templates/doc-lint.json",
            '"human_action_ledgers"', '"ai_action_ledgers"', '"decision_source_pattern"')),
        ("class-a-gate", lambda: require(
            "claude-roblox-dev-docs-creator/references/worker-registry.md",
            "Class B", "gate照合", "不可。supplemental semantic reviewのみ")),
        ("approved-transfer", lambda: require(
            "claude-roblox-dev-docs-creator/references/execution-envelope.md",
            "approved-transfer", "transferApproval", "allowedContentSha256")),
        ("class-b-json-envelope", lambda: require(
            "claude-roblox-dev-docs-creator/references/execution-envelope.md",
            '"schema_version": 1', '"artifact"', '"report"')),
        ("no-preview-url-probe", lambda: forbid(
            "claude-roblox-dev-docs-creator/SKILL.md", "preview_start {url")),
        ("no-merged-skill-refs", lambda: forbid_in_tree(
            "claude-roblox-dev-docs-creator",
            "roblox-development-architect/",
            "claude-roblox-initial-document-check/",
            "claude-Roblox-P0-development/")),

        # --- 残る2 skill との接続 ---
        ("routing-mvp-full", lambda: require(
            "claude-roblox-mvp-buildout/SKILL.md", "完成までの一連の作業", "単発診断や1つのWP")),
        ("routing-delivery-single", lambda: require(
            "claude-roblox-development-delivery/SKILL.md", "一度に1 WP", "複数WP")),
        ("d6-d7-mvp", lambda: require(
            "claude-roblox-mvp-buildout/SKILL.md",
            "D6 — WP完了時の同期", "D7 — 契約競合とChange Request")),
        ("d6-d7-delivery", lambda: require(
            "claude-roblox-development-delivery/SKILL.md",
            "D6 — WP完了同期", "D7 — 契約競合とChange Request")),
        ("os-action-double-gate", lambda: require(
            "claude-roblox-mvp-buildout/SKILL.md", "個別明示承認", "直前identity一致")),
        ("studio-runtime-schema", lambda: require(
            "claude-roblox-development-delivery/references/studio-mcp.md",
            "studio_id", "datamodel_type", "capture_id", "明示的 `return`")),
        ("studio-no-old-selector", lambda: forbid(
            "claude-roblox-development-delivery/references/studio-mcp.md",
            "set_active_studio", "mcp__roblox-built-in")),
        ("delivery-upstream-skill", lambda: require(
            "claude-roblox-development-delivery/SKILL.md", "claude-roblox-dev-docs-creator")),

        # --- worker skill ---
        ("deepseek-cli-canonical", lambda: require(
            "deepseek-api/SKILL.md", "ds_ask.py` v2.0.0のみ正本", "MCP互換adapter")),
        ("deepseek-json-envelope", lambda: require(
            "deepseek-api/SKILL.md", '"schema_version": 1', "finish_reason != stop")),
        ("cursor-inline-context", lambda: require(
            "cursor-grok/SKILL.md", "Class B inline context bundle", '"schema_version": 1')),
        ("codex-stage-route", lambda: require(
            "codex-run/SKILL.md", "T1製品実装は対象外", "companion runtime")),
    ]

    mcp_server = CLAUDE_ROOT / "mcp-servers" / "deepseek" / "server.mjs"
    if not mcp_server.is_file():
        raise SeamFailure(f"missing file: {mcp_server}")
    mcp_text = mcp_server.read_text(encoding="utf-8", errors="strict")
    for marker in ("schema_version", "finish_reason", "structuredContent", "auth_source"):
        if marker not in mcp_text:
            raise SeamFailure(f"{mcp_server}: missing contract marker: {marker}")

    passed: list[str] = ["deepseek-mcp-structured"]
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
          else f"PASS: {len(passed)} cross-skill seam checks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
