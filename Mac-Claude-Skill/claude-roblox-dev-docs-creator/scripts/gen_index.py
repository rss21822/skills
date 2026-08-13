#!/usr/bin/env python3
"""
文書ヘッダから索引表と manifest を生成する。

索引と manifest を手書きすると、ヘッダの部分転記漏れ（Status の括弧内を落とす等）が
起き、文書が増えるたび再同期が要る。生成すればどちらも起きない。

  python3 gen_index.py --project-root . --config .claude/doc-lint.json
  python3 gen_index.py --project-root . --emit manifest --output docs/CAV_docs_manifest.json
  python3 gen_index.py --project-root . --emit index    # 索引表を stdout へ

manifest は validate_docs.py が読む形式（documents[].path / .required）に合わせる。
既存 manifest がある場合、required と phase の指定は引き継ぐ（--reset で破棄）。
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

FIELDS = ["Document ID", "Version", "Status", "Canonical domain", "Owner",
          "Inputs", "Downstream", "Last approved"]

DEFAULT_GLOBS = ["docs/*.md", "docs/specs/*.md"]


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
        rel = p.relative_to(root)
        lines.append(
            f"| {cell(h.get('Document ID'))} | `{rel}` | {cell(h.get('Version'))} "
            f"| {cell(h.get('Status'))} | {cell(h.get('Canonical domain'))} |")
    return "\n".join(lines)


def make_manifest(root: Path, docs: list[tuple[Path, dict]], existing: dict | None, reset: bool) -> dict:
    prior = {}
    if existing and not reset:
        for d in existing.get("documents", []):
            if d.get("path"):
                key = norm(root, d["path"])
                if key in prior:
                    raise SystemExit(f"ERROR: manifest に正規化後の path 重複がある: {key}")
                prior[key] = dict(d, path=key)
    documents = []
    for p, h in docs:
        rel = norm(root, p.relative_to(root))
        old = prior.get(rel, {})
        documents.append({
            "id": h.get("Document ID") or old.get("id") or rel,
            "path": rel,
            "required": old.get("required", True),
            "status": (h.get("Status") or old.get("status") or "draft").split("（")[0].strip().lower(),
            "phase": old.get("phase", "D2"),
        })
    known = {d["path"] for d in documents}
    for path, d in prior.items():
        if path not in known:
            documents.append(d)  # 生成対象外（記録類など）は既存指定を保持
    documents.sort(key=lambda d: (d.get("phase", ""), d["path"]))
    return {"documents": documents}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--project-root", type=Path, default=Path.cwd())
    ap.add_argument("--config", type=Path, default=None, help="doc_globs を読む（任意）")
    ap.add_argument("--globs", nargs="*", default=None)
    ap.add_argument("--emit", choices=["index", "manifest", "both"], default="both")
    ap.add_argument("--output", type=Path, default=None, help="manifest の書き出し先")
    ap.add_argument("--reset", action="store_true", help="既存 manifest の required/phase を引き継がない")
    args = ap.parse_args()

    root = args.project_root.resolve()

    def under_root(path):
        # 相対パスは呼び出し時 CWD ではなく project-root 基準で解決する。
        return path if path is None or path.is_absolute() else (root / path)

    cfg_path, out_path = under_root(args.config), under_root(args.output)
    globs = args.globs or DEFAULT_GLOBS
    excludes = []
    if cfg_path is not None:
        if not cfg_path.is_file():
            print(f"ERROR: --config が存在しない: {cfg_path}", file=sys.stderr)
            return 2
        cfg = json.loads(cfg_path.read_text(encoding="utf-8"))
        globs = args.globs or cfg.get("index_globs") or cfg.get("doc_globs") or DEFAULT_GLOBS
        excludes = cfg.get("exclude_globs", [])

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

    if args.emit in ("index", "both"):
        print(make_index(root, docs))
        if args.emit == "both":
            print()

    if args.emit in ("manifest", "both"):
        existing = None
        target = out_path
        if target and target.exists():
            try:
                existing = json.loads(target.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                existing = None
        manifest = make_manifest(root, docs, existing, args.reset)
        text = json.dumps(manifest, ensure_ascii=False, indent=2) + "\n"
        if target:
            target.write_text(text, encoding="utf-8")
            print(f"manifest を書き出した: {target}  ({len(manifest['documents'])} 件)", file=sys.stderr)
        else:
            print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
