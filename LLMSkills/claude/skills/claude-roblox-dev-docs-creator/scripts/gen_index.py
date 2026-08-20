#!/usr/bin/env python3
"""
文書ヘッダから索引表と manifest を生成する。

索引と manifest を手書きすると、ヘッダの部分転記漏れ（Status の括弧内を落とす等）が
起き、文書が増えるたび再同期が要る。生成すればどちらも起きない。

  python3 gen_index.py --project-root . --config .claude/doc-lint.json
  python3 gen_index.py --project-root . --emit manifest --output docs/CAV_docs_manifest.json \
    --project "My Game" --prefix CAV
  python3 gen_index.py --project-root . --emit index    # 索引表を stdout へ

manifest は architect の docs_manifest.schema.json に合わせ、閉じた既知 field だけを
出す。既存 manifest がある場合、project / prefix / required / phase / trigger など
schema が定義する運用メタデータを引き継ぐ（--reset では文書ごとの運用メタデータを
初期化する）。
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
import tempfile
from pathlib import Path

from strict_json import loads as strict_json_loads

FIELDS = ["Document ID", "Version", "Status", "Canonical domain", "Owner",
          "Inputs", "Downstream", "Last approved"]

DEFAULT_GLOBS = ["docs/*.md", "docs/specs/*.md"]
STATUS_ALIASES = {
    "draft": "draft",
    "review": "review",
    "in review": "review",
    "approved": "approved",
    "superseded": "superseded",
}
PREFIX_RE = re.compile(r"^[A-Z0-9]{2,6}$")
MANIFEST_VERSION = "1.0.0"
INDEX_BEGIN = "<!-- BEGIN GENERATED DOCUMENT INDEX -->"
INDEX_END = "<!-- END GENERATED DOCUMENT INDEX -->"
BASELINE_UNSET = object()


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
                mode="w", encoding="utf-8", newline="", delete=False,
                dir=path.parent, prefix=f".{path.name}.", suffix=".tmp") as fh:
            fh.write(text)
            fh.flush()
            os.fsync(fh.fileno())
            temporary = Path(fh.name)
        os.replace(temporary, path)
        temporary = None
    finally:
        if temporary is not None:
            try:
                temporary.unlink()
            except FileNotFoundError:
                pass


def write_index(path: Path, table: str, mode: str) -> None:
    """Write a generated index without silently destroying authored sections."""
    if mode == "full":
        atomic_write(path, table.rstrip() + "\n")
        return
    block = f"{INDEX_BEGIN}\n{table.rstrip()}\n{INDEX_END}"
    if not path.exists():
        atomic_write(path, block + "\n")
        return
    current = path.read_text(encoding="utf-8")
    begin_count, end_count = current.count(INDEX_BEGIN), current.count(INDEX_END)
    if begin_count != 1 or end_count != 1:
        raise ValueError(
            f"{path}: marker mode requires exactly one {INDEX_BEGIN!r} and {INDEX_END!r}; "
            "use --index-mode full only for a generated-only index file")
    before, tail = current.split(INDEX_BEGIN, 1)
    _, after = tail.split(INDEX_END, 1)
    atomic_write(path, before + block + after)


def split_row(line: str):
    """Markdown の表 1行をセルへ分解する。`\|` のエスケープを尊重する。"""
    if not line.lstrip().startswith("|"):
        return None
    body = line.strip()
    body = body[1:] if body.startswith("|") else body
    body = body[:-1] if body.endswith("|") and not body.endswith("\\|") else body
    cells, cur, esc = [], [], False
    for ch in body:
        if esc:
            cur.append(ch)
            esc = False
        elif ch == "\\":
            esc = True
        elif ch == "|":
            cells.append("".join(cur).strip())
            cur = []
        else:
            cur.append(ch)
    cells.append("".join(cur).strip())
    return cells


def parse_header(path: Path) -> tuple:
    """先頭の | Field | Value | 表**ひとつだけ**からヘッダ項目を取り出す。

    「最初の H2 までの全2セル行」を読むと、後続の別表（| Version | Date | のような
    2列表）が同名キーを上書きしてしまう。表の開始を捉えたら、その表が終わった
    時点で読み取りを止める。同じ field の重複は上書きせず異常として返す。
    """
    out: dict = {}
    dupes = []
    in_table = False
    for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        cells = split_row(line)
        if cells is None or len(cells) < 2:
            if in_table:
                break          # 表の終わり。以降の表は読まない
            if line.startswith("## "):
                break
            continue
        if set("".join(cells[:2])) <= set("-: "):
            in_table = True    # 区切り行
            continue
        key, val = cells[0], cells[1]
        if len(cells) > 2 and key not in FIELDS:
            if in_table:
                break          # 3列以上の別表に入った
            continue
        if key in FIELDS:
            in_table = True
            if key in out and out[key] != val.strip("`"):
                dupes.append(key)
            else:
                out[key] = val.strip("`")
    return out, dupes


def collect(root: Path, globs: list[str], excludes: list[str]) -> list[Path]:
    ex_set = {p.resolve() for g in excludes for p in root.glob(g)}
    seen, out = set(), []
    for g in globs:
        for p in sorted(root.glob(g)):
            rp = p.resolve()
            if not p.is_file() or rp in seen:
                continue
            if any(rp == e or e in rp.parents for e in ex_set):
                continue
            seen.add(rp)
            out.append(p)
    return out


def norm(root: Path, p) -> str:
    """manifest の path を POSIX 相対表記へ正規化する。`./docs/a.md` と
    `docs/a.md` が別レコードとして重複するのを防ぐ。"""
    q = Path(p)
    if q.is_absolute():
        try:
            return q.resolve().relative_to(root).as_posix()
        except ValueError:
            return q.as_posix()
    return Path(*[part for part in q.parts if part != "."]).as_posix()


def make_index(root: Path, docs: list[tuple[Path, dict]]) -> str:
    lines = ["| Document ID | Path | Version | Status | Canonical domain |",
             "|---|---|---|---|---|"]
    def cell(v):
        return (v or "—").replace("|", "\\|")   # 値に含まれる | は表を壊すので再エスケープ
    for p, h in docs:
        rel = p.relative_to(root).as_posix()
        lines.append(
            f"| {cell(h.get('Document ID'))} | `{rel}` | {cell(h.get('Version'))} "
            f"| {cell(h.get('Status'))} | {cell(h.get('Canonical domain'))} |")
    return "\n".join(lines)


def make_index_from_manifest(manifest: dict) -> str:
    """Render the complete inventory, including non-Markdown machine artifacts."""
    lines = ["| Document ID | Path | Version | Status | Canonical domain |",
             "|---|---|---|---|---|"]

    def cell(value):
        return str(value if value not in (None, "") else "—").replace("|", "\\|")

    for item in sorted(manifest.get("documents", []), key=lambda row: row.get("path", "")):
        lines.append(
            f"| {cell(item.get('id'))} | `{cell(item.get('path'))}` | "
            f"{cell(item.get('version'))} | {cell(item.get('status'))} | "
            f"{cell(item.get('domain'))} |")
    return "\n".join(lines)


def normalize_status(raw: str, path: str) -> str:
    """ヘッダの表示用注記を除き、schema が許す状態値へ正規化する。"""
    value = raw
    for sep in ("（", "(", "。", "、", ",", "<!--"):
        value = value.split(sep)[0]
    value = value.replace("`", "").replace("*", "").strip().lower()
    status = STATUS_ALIASES.get(value)
    if status is None:
        allowed = ", ".join(sorted(set(STATUS_ALIASES.values())))
        raise SystemExit(
            f"ERROR: {path}: manifest status に変換できない値 {raw!r}。"
            f"許可値は {allowed}")
    return status


def validate_manifest_shape(manifest: dict) -> None:
    """schema 必須部を標準ライブラリだけで検査し、不正な manifest を出力させない。"""
    project = manifest.get("project")
    prefix = manifest.get("prefix")
    documents = manifest.get("documents")
    if manifest.get("schemaVersion") != MANIFEST_VERSION:
        raise SystemExit(f"ERROR: manifest.schemaVersion は {MANIFEST_VERSION} でなければならない")
    generated_at = manifest.get("generatedAt")
    if not isinstance(generated_at, str) or not generated_at.strip():
        raise SystemExit("ERROR: manifest.generatedAt は空でない文字列でなければならない")
    if manifest.get("baselineId") is not None \
            and (not isinstance(manifest.get("baselineId"), str)
                 or not manifest["baselineId"].strip()):
        raise SystemExit("ERROR: manifest.baselineId は空でない string または null でなければならない")
    if not isinstance(project, str) or not project.strip():
        raise SystemExit("ERROR: manifest.project は空でない文字列でなければならない")
    if not isinstance(prefix, str) or not PREFIX_RE.fullmatch(prefix):
        raise SystemExit("ERROR: manifest.prefix は2〜6文字の英大文字・数字でなければならない")
    if not isinstance(documents, list):
        raise SystemExit("ERROR: manifest.documents は配列でなければならない")

    seen = set()
    allowed_statuses = set(STATUS_ALIASES.values())
    for index, item in enumerate(documents):
        label = f"manifest.documents[{index}]"
        if not isinstance(item, dict):
            raise SystemExit(f"ERROR: {label} は object でなければならない")
        path = item.get("path")
        domain = item.get("domain")
        for field in ("id", "version", "phase"):
            if not isinstance(item.get(field), str) or not item[field].strip():
                raise SystemExit(f"ERROR: {label}.{field} は空でない文字列でなければならない")
        if not isinstance(path, str) or not path.strip():
            raise SystemExit(f"ERROR: {label}.path は空でない文字列でなければならない")
        if path in seen:
            raise SystemExit(f"ERROR: manifest に path 重複がある: {path}")
        seen.add(path)
        if not isinstance(domain, str) or not domain.strip():
            raise SystemExit(f"ERROR: {path}: domain は空でない文字列でなければならない")
        if not isinstance(item.get("required"), bool):
            raise SystemExit(f"ERROR: {path}: required は boolean でなければならない")
        if item.get("status") not in allowed_statuses:
            allowed = ", ".join(sorted(allowed_statuses))
            raise SystemExit(f"ERROR: {path}: status は {allowed} のいずれかでなければならない")
        if "trigger" in item and item["trigger"] is not None \
                and not isinstance(item["trigger"], str):
            raise SystemExit(f"ERROR: {path}: trigger は string または null でなければならない")


def make_manifest(
        root: Path, docs: list[tuple[Path, dict]], existing: dict | None,
        reset: bool, project: str | None, prefix: str | None,
        baseline_id: str | None | object = BASELINE_UNSET,
        approve_non_formal: bool = False) -> dict:
    prior = {}
    if existing:
        existing_documents = existing.get("documents")
        if not isinstance(existing_documents, list):
            raise SystemExit("ERROR: existing manifest.documents は配列でなければならない")
        for index, d in enumerate(existing_documents):
            if not isinstance(d, dict) or not isinstance(d.get("path"), str) \
                    or not d["path"].strip():
                raise SystemExit(f"ERROR: existing manifest.documents[{index}] の path が不正")
            raw_path = Path(d["path"])
            key = norm(root, raw_path)
            candidate = (root / key).resolve()
            try:
                candidate.relative_to(root)
            except ValueError:
                raise SystemExit(
                    f"ERROR: manifest inventory path が project-root 外を指す: {d['path']}")
            if not candidate.is_file():
                raise SystemExit(
                    f"ERROR: manifest inventory の file が存在しない: {key}")
            if key in prior:
                raise SystemExit(f"ERROR: manifest に正規化後の path 重複がある: {key}")
            prior[key] = dict(d, path=key)
    manifest_project = project or (existing or {}).get("project")
    manifest_prefix = prefix or (existing or {}).get("prefix")
    if not isinstance(manifest_project, str) or not manifest_project.strip():
        raise SystemExit(
            "ERROR: manifest の project が無い。既存 manifest、--project、または "
            "config の manifest_project で指定する")
    if not isinstance(manifest_prefix, str) or not PREFIX_RE.fullmatch(manifest_prefix):
        raise SystemExit(
            "ERROR: manifest の prefix が無いか不正。2〜6文字の英大文字・数字を、"
            "既存 manifest、--prefix、または config の manifest_prefix で指定する")

    documents = []
    for p, h in docs:
        rel = norm(root, p.relative_to(root))
        old = prior.get(rel, {}) if not reset else {}
        domain = h.get("Canonical domain") or old.get("domain")
        if not isinstance(domain, str) or not domain.strip():
            raise SystemExit(
                f"ERROR: {rel}: Canonical domain が無く、既存 manifest にも domain が無い")
        status_raw = h.get("Status") or old.get("status") or "draft"
        # docs_manifest.schema.json の閉じた形だけを出力する。
        item = {
            "id": h.get("Document ID") or old.get("id") or rel,
            "path": rel,
            "domain": domain.strip(),
            "required": old.get("required", True),
            "status": normalize_status(status_raw, rel),
            "version": h.get("Version") or old.get("version") or "0.1.0",
            "phase": old.get("phase", "D2"),
            "trigger": old.get("trigger"),
        }
        documents.append(item)
    known = {d["path"] for d in documents}
    for path, d in prior.items():
        if path not in known:
            prior_status = d.get("status", "draft")
            promoted_status = (
                "approved" if approve_non_formal and prior_status in {"draft", "review"}
                else prior_status
            )
            documents.append({
                "id": d.get("id") or path,
                "path": path,
                "domain": d.get("domain") or "user-managed artifact",
                "required": d.get("required", True),
                "status": promoted_status,
                "version": d.get("version") or "0.1.0",
                "phase": d.get("phase") or "D2",
                "trigger": d.get("trigger") if isinstance(d.get("trigger"), str) else None,
            })  # 生成対象外（記録類など）は既存指定を保持
    documents.sort(key=lambda d: (d.get("phase", ""), d["path"]))
    result = {
        "schemaVersion": MANIFEST_VERSION,
        "generatedAt": utc_now(),
        "baselineId": ((existing or {}).get("baselineId")
                       if baseline_id is BASELINE_UNSET else baseline_id),
        "project": manifest_project.strip(),
        "prefix": manifest_prefix,
        "documents": documents,
    }
    validate_manifest_shape(result)
    return result


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--project-root", type=Path, default=Path.cwd())
    ap.add_argument("--config", type=Path, default=None, help="doc_globs を読む（任意）")
    ap.add_argument("--globs", nargs="*", default=None)
    ap.add_argument("--emit", choices=["index", "manifest", "both"], default="both")
    ap.add_argument("--output", type=Path, default=None, help="manifest の書き出し先")
    ap.add_argument("--index-output", type=Path, default=None,
                    help="index の安全な書き出し先（既定は stdout）")
    ap.add_argument("--index-mode", choices=["markers", "full"], default="markers",
                    help="marker 区間だけ更新するか、生成専用ファイル全体を置換するか")
    ap.add_argument("--project", default=None, help="manifest の project（既存値より優先）")
    ap.add_argument("--prefix", default=None, help="manifest の prefix（既存値より優先）")
    ap.add_argument("--baseline-id", default=None,
                    help="manifest baselineId（D5同期ではB2 ID。省略時は既存値を保持）")
    ap.add_argument("--approve-non-formal", action="store_true",
                    help="D5同期時、headerを持たないregistry行もapprovedへ昇格")
    ap.add_argument("--d5-approval-id", default=None,
                    help="--approve-non-formal の明示的人間D5承認ID")
    ap.add_argument(
        "--reset", action="store_true",
        help=("headerを持つMarkdownの運用メタデータを再計算する。"
              "既存の非header machine inventory行は保持する"))
    args = ap.parse_args()

    root = args.project_root.resolve()

    def under_root(path):
        # 相対パスは呼び出し時 CWD ではなく project-root 基準で解決する。
        return path if path is None or path.is_absolute() else (root / path)

    cfg_path, out_path = under_root(args.config), under_root(args.output)
    index_out_path = under_root(args.index_output)
    if index_out_path is not None and args.emit not in ("index", "both"):
        ap.error("--index-output requires --emit index or --emit both")
    if args.approve_non_formal:
        if not args.d5_approval_id:
            ap.error("--approve-non-formal requires --d5-approval-id")
        if not args.baseline_id or re.fullmatch(r"B2-[A-Z0-9][A-Z0-9._-]*", args.baseline_id) is None:
            ap.error("--approve-non-formal requires --baseline-id B2-...")
    globs = args.globs or DEFAULT_GLOBS
    excludes = []
    config_project = None
    config_prefix = None
    if cfg_path is not None:
        if not cfg_path.is_file():
            print(f"ERROR: --config が存在しない: {cfg_path}", file=sys.stderr)
            return 2
        cfg = strict_json_loads(cfg_path.read_text(encoding="utf-8"))
        globs = args.globs or cfg.get("index_globs") or cfg.get("doc_globs") or DEFAULT_GLOBS
        excludes = cfg.get("exclude_globs", [])
        config_project = cfg.get("manifest_project")
        config_prefix = cfg.get("manifest_prefix")

    docs, problems = [], []
    for p in collect(root, globs, excludes):
        h, dupes = parse_header(p)
        if dupes:
            problems.append(f"{p.relative_to(root)}: ヘッダ項目の重複 {', '.join(dupes)}")
        if h.get("Document ID"):
            docs.append((p, h))

    if problems:
        print("ERROR: ヘッダを一意に解釈できない文書がある:\n  " + "\n  ".join(problems),
              file=sys.stderr)
        return 2
    if not docs:
        print("ERROR: ヘッダ表を持つ文書が見つからない。--globs / --project-root を確認する",
              file=sys.stderr)
        return 2

    # The human index is a projection of the complete manifest inventory.  Load
    # the explicit output target, or the sole scaffold manifest when --output is
    # omitted, so machine artifacts are never dropped from either projection.
    target = out_path
    existing_path = target if target is not None and target.exists() else None
    if existing_path is None and target is None:
        candidates = sorted((root / "docs").glob("*_docs_manifest.json"))
        if len(candidates) == 1:
            existing_path = candidates[0]
        elif len(candidates) > 1:
            print("ERROR: 複数の docs manifest がある。--output で正本を指定する",
                  file=sys.stderr)
            return 2
    existing = None
    if existing_path is not None:
        try:
            existing = strict_json_loads(existing_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            print(f"ERROR: 既存 manifest が不正: {existing_path}: {exc}", file=sys.stderr)
            return 2
    manifest = make_manifest(
        root, docs, existing, args.reset,
        args.project or config_project, args.prefix or config_prefix,
        args.baseline_id if args.baseline_id is not None else BASELINE_UNSET,
        args.approve_non_formal)
    if target is not None and args.emit in ("manifest", "both"):
        try:
            manifest_rel = target.resolve().relative_to(root).as_posix()
        except ValueError:
            manifest_rel = None
        if manifest_rel is not None and all(
                item["path"] != manifest_rel for item in manifest["documents"]):
            manifest["documents"].append({
                "id": f"{manifest['prefix']}-DOCS-MANIFEST",
                "path": manifest_rel,
                "domain": "machine-readable document inventory",
                "required": True,
                "status": "approved" if args.approve_non_formal else "draft",
                "version": "1.0.0",
                "phase": "D0",
                "trigger": None,
            })
            manifest["documents"].sort(
                key=lambda item: (item.get("phase", ""), item["path"]))
            validate_manifest_shape(manifest)

    if args.emit in ("index", "both"):
        index_text = make_index_from_manifest(manifest)
        if index_out_path is not None:
            try:
                write_index(index_out_path, index_text, args.index_mode)
            except (OSError, ValueError) as exc:
                print(f"ERROR: index を安全に更新できない: {exc}", file=sys.stderr)
                return 2
            print(f"index を書き出した: {index_out_path}  ({len(manifest['documents'])} 件)", file=sys.stderr)
        else:
            print(index_text)
            if args.emit == "both":
                print()

    if args.emit in ("manifest", "both"):
        text = json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"
        if target:
            atomic_write(target, text)
            print(f"manifest を書き出した: {target}  ({len(manifest['documents'])} 件)", file=sys.stderr)
        else:
            print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
