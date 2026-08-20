#!/usr/bin/env python3
"""
LLM 生成ドキュメント体系の機械検査。

LLM 照合が見つける指摘のうち、正規表現で検出できる定型欠陥を先に潰すためのもの。
照合へ出す前に必ず走らせる。標準ライブラリのみを使用し、元ファイルを変更しない。

  python3 lint_docs.py --project-root . --config .claude/doc-lint.json
  python3 lint_docs.py --project-root . --config .claude/doc-lint.json --files docs/specs/new_spec.md
  python3 lint_docs.py --project-root . --config .claude/doc-lint.json --json

終了コード: 0 = finding・未検査観点なし / 1 = error・warning・未検査観点あり /
2 = 入力・設定の誤り

設計方針: **fail-closed**。指定した設定ファイルが無い、ルール名を打ち間違えた、
対象ファイルが存在しない——このいずれでも「PASS」を返さない。品質ゲートが
入力ミスを黙って通すと、通ったことに意味が無くなる。

行単位の抑制:  <!-- doc-lint-ignore-line: rule-name[,rule-name] -->
ファイル単位:  <!-- doc-lint-ignore-file: rule-name[,rule-name] -->
規約を説明する散文など、正しいのに検出される行はこれで明示的に抑制する。
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import sys
from pathlib import Path

DEFAULT_CONFIG = {
    "doc_globs": ["docs/**/*.md", "*.md"],
    "exclude_globs": ["docs/handoffs/**", "**/node_modules/**"],
    "report_globs": ["docs/handoffs/out/*_last-message.md"],
    "index_globs": [],          # gen_index.py が使う。設定ファイルを共有するため既知キーに含める
    "manifest_project": None,    # gen_index.py が使う
    "manifest_prefix": None,     # gen_index.py が使う
    "decision_qualifiers": ["GDD", "Feasibility", "gate-threshold", "D0-B"],
    "decision_id_pattern": r"\b[DF]-\d+\b",
    "decision_id_home_docs": [],
    "gate_id_pattern": r"\b[A-Z][A-Z0-9]*-(?:GATE|OQ|DEP)-[A-Z0-9-]+\b",
    "stale_premise_phrases": ["未作成", "作成予定", "将来の", "未整備のため"],
    "stale_premise_window": 60,
    "value_units": ["frames/s", "studs", "stud", "fps", "ms", "MB", "GB", "KB", "s"],
    "value_id_patterns": [r"\bDATA-[A-Z]+-\d+\b"],
    "value_owner_docs": [],
    "value_exempt_markers": ["正本は", "転記", "出所", "canonical"],
    "bare_open_exempt_docs": [],
    "self_verification_terms": [
        "独立照合", "別セッション", "サブエージェントレビュー", "受入照合",
        "読み取り専用レビュー", "別エージェント", "構造検査",
    ],
    # 決定の出所、人間専権、AI action の実行分類を検査する。
    "decision_source_pattern": r"(?:src|source|出所)\s*[:=]\s*`?[UWMJ]\b|evidence\s*[:=]\s*\S",
    "decision_source_exempt_docs": [],
    "decision_source_window": 2,
    "decision_approval_pattern": (
        r"(?:approver|approved[-_ ]?by|approval(?:_record|Ref)?|承認者|承認記録)"
        r"\s*[:=]\s*\S"),
    "decision_approval_exempt_docs": [],
    "decision_approval_window": 3,
    "human_action_ledgers": [],
    "human_action_id_pattern": r"H-[A-Z0-9]+(?:-[A-Z0-9]+)*",
    "human_exec_pattern": r"exec\s*[:=]\s*`?human-only\b",
    "human_exec_values": ["human-only"],
    "human_exec_window": 4,
    "ai_action_ledgers": [],
    "ai_action_id_pattern": r"AI-[A-Z0-9]+(?:-[A-Z0-9]+)*",
    "ai_exec_pattern": (
        r"exec\s*[:=]\s*`?(?:ai-studio|ai-browser|ai-computer|approved-transfer"
        r"|blocked-permission|blocked-capability)\b"),
    "ai_exec_values": [
        "ai-studio", "ai-browser", "ai-computer", "approved-transfer",
        "blocked-permission", "blocked-capability"],
    "ai_exec_window": 4,
    "contracts": [],
    "forward_refs": [],
    "status_consistency": [],
    "rules": {},
}

SEVERITY_ORDER = {"error": 0, "warn": 1}
IGNORE_LINE = re.compile(r"<!--\s*doc-lint-ignore-line:\s*([a-z0-9,\- ]+?)\s*-->")
IGNORE_FILE = re.compile(r"<!--\s*doc-lint-ignore-file:\s*([a-z0-9,\- ]+?)\s*-->")


class ConfigError(Exception):
    pass


class Finding:
    __slots__ = ("rule", "severity", "path", "line", "message", "excerpt")

    def __init__(self, rule, severity, path, line, message, excerpt=""):
        self.rule = rule
        self.severity = severity
        self.path = path
        self.line = line
        self.message = message
        self.excerpt = excerpt.strip()[:160]

    def as_dict(self):
        return {
            "rule": self.rule, "severity": self.severity, "path": self.path,
            "line": self.line, "message": self.message, "excerpt": self.excerpt,
        }


class Doc:
    """1文書分の本文と抑制指定。各 rule が同じ前処理を繰り返さないためのもの。"""

    def __init__(self, root: Path, path: Path):
        self.path = path
        self.rel = rel(root, path)
        text = path.read_text(encoding="utf-8", errors="ignore")
        self.lines = text.splitlines()
        self.file_ignores = {
            r.strip() for m in IGNORE_FILE.finditer(text) for r in m.group(1).split(",")
        }
        self.line_ignores: dict[int, set] = {}
        self.in_code: set = set()
        fence = False
        for i, line in enumerate(self.lines, 1):
            if line.lstrip().startswith("```"):
                fence = not fence
                self.in_code.add(i)
                continue
            if fence:
                self.in_code.add(i)
            m = IGNORE_LINE.search(line)
            if m:
                self.line_ignores[i] = {r.strip() for r in m.group(1).split(",")}

    def active(self, rule: str, lineno: int) -> bool:
        if rule in self.file_ignores:
            return False
        return rule not in self.line_ignores.get(lineno, ())

    def enumerate(self, rule: str, skip_code: bool = False):
        for i, line in enumerate(self.lines, 1):
            if skip_code and i in self.in_code:
                continue
            if self.active(rule, i):
                yield i, line


def rel(root: Path, p: Path) -> str:
    try:
        return p.resolve().relative_to(root).as_posix()
    except ValueError:
        return p.as_posix()


def validate_keys(user: dict, known_rules) -> None:
    """未知の設定キー・ルール名を拒否する。

    CLI の指定ミスだけ弾いても、設定ファイルの打ち間違いが黙って既定値へ落ちるなら
    「PASS を信用できない」問題は残る。doc_globz と書いた設定で PASS が出るのが最悪。
    """
    unknown = sorted(k for k in user if not k.startswith("_") and k not in DEFAULT_CONFIG)
    if unknown:
        raise ConfigError(
            f"未知の設定キー: {', '.join(unknown)}\n"
            f"       使えるのは: {', '.join(sorted(DEFAULT_CONFIG))}")
    bad = sorted(r for r in (user.get("rules") or {}) if not r.startswith("_")
                 and r not in known_rules)
    if bad:
        raise ConfigError(
            f"rules に未知の rule 名: {', '.join(bad)}\n"
            f"       使えるのは: {', '.join(known_rules)}")


def load_config(config_path: Path | None, explicit: bool, known_rules=()) -> dict:
    cfg = dict(DEFAULT_CONFIG)
    if config_path is None:
        return cfg
    if not config_path.is_file():
        if explicit:
            raise ConfigError(f"--config で指定された設定が存在しない: {config_path}")
        return cfg
    try:
        user = json.loads(config_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ConfigError(f"設定 JSON を解析できない: {config_path}: {exc}")
    validate_keys(user, known_rules)
    cfg.update({k: v for k, v in user.items() if not k.startswith("_")})
    return cfg


def collect(root: Path, globs, excludes) -> list[Path]:
    ex_set = {p.resolve() for pattern in excludes for p in root.glob(pattern)}
    seen, out = set(), []
    for pattern in globs:
        for p in sorted(root.glob(pattern)):
            if not p.is_file():
                continue
            rp = p.resolve()
            if rp in seen or any(rp == e or e in rp.parents for e in ex_set):
                continue
            seen.add(rp)
            out.append(p)
    return out


def linked(line: str, a_end: int, b_start: int, seps: str) -> bool:
    """2つの位置が同じ節に属するか。間に文の区切りがあれば別の話題とみなす。

    距離だけでは「A.md を参照。別件だが機能Xは未作成」のような行を分離できない。
    逆に「GDD D-9 と、別体系の D-9」では、先頭の修飾が後続の裸参照まで及ばない。
    """
    if a_end > b_start:
        a_end, b_start = b_start, a_end
    return not any(c in line[a_end:b_start] for c in seps)


def split_cells(line: str) -> list:
    """Markdown 表の1行をセルへ分解する。`\\|` は区切りではなくセル内の文字。"""
    if "|" not in line:
        return [line]
    cells, cur, esc = [], [], False
    for ch in line:
        if esc:
            cur.append(ch)
            esc = False
        elif ch == "\\":
            esc = True
        elif ch == "|":
            cells.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    cells.append("".join(cur))
    return cells


def units_regex(units) -> re.Pattern:
    ordered = sorted({u for u in units}, key=len, reverse=True)
    body = "|".join(re.escape(u) for u in ordered)
    # 末尾を \b にすると「220ms以下」のように日本語が直結した表記で成立しない。
    # 英数字が続かないことだけを条件にする。
    return re.compile(r"\d[\d.,]*\s*(?:" + body + r")(?![A-Za-z0-9])")


# --------------------------------------------------------------------------
# rules
# --------------------------------------------------------------------------

def rule_bare_open(root, docs, cfg, out):
    """[OPEN] に blocking 併記がない。未決事項が作業を止めるか機械判定できない。"""
    pat = re.compile(r"\[OPEN\](?!\s*(?:blocking|\(\s*blocking))")
    tag_pat = re.compile(r"\[(?:FACT|DECISION|PROPOSAL|ASSUMPTION|OPEN|HUMAN|EXTERNAL)[^\]]*\]")
    exempt = {Path(x).as_posix() for x in cfg["bare_open_exempt_docs"]}
    for d in docs:
        if d.rel in exempt:
            continue  # 規約成立前に承認された文書。改訂は人間判断
        for i, line in d.enumerate("bare-open"):
            if len({m.group(0) for m in tag_pat.finditer(line)}) >= 3:
                continue  # タグ凡例
            if pat.search(line):
                out.append(Finding(
                    "bare-open", "error", d.rel, i,
                    "裸の [OPEN]。blocking: yes|no を併記する"
                    "（規約を説明する散文なら doc-lint-ignore-line で抑制する）", line))


def rule_blocking_polarity(root, docs, cfg, out):
    """同一 gate ID が blocking: yes と no の両方で結び付けられている。

    1行に複数の marker が並ぶ書き分け（「登録は no、実行は yes」）があるため、
    gate ID は直前の marker へ帰属させる。同一行に同じ gate が両極性で現れる
    ケースもあるので、行内の出現を間引かない。
    """
    gate_pat = re.compile(cfg["gate_id_pattern"])
    blk_pat = re.compile(r"blocking:\s*(yes|no)\b")
    polarity: dict = {}
    for d in docs:
        for i, line in d.enumerate("blocking-polarity"):
            marks = [(m.start(), m.group(1)) for m in blk_pat.finditer(line)]
            if not marks:
                continue
            for gm in gate_pat.finditer(line):
                before = [mk for mk in marks if mk[0] < gm.start()]
                pol = before[-1][1] if before else marks[0][1]
                slot = polarity.setdefault(gm.group(0), {"yes": [], "no": []})
                slot[pol].append((d.rel, i))
    for gid, sides in sorted(polarity.items()):
        if sides["yes"] and sides["no"]:
            where = ", ".join(f"{f}:{l}" for f, l in (sides["yes"][:2] + sides["no"][:2]))
            path, line = sides["yes"][0]
            # 「他 gate への言及」と「その gate の極性宣言」は行の意味を読まないと分離できない。
            # 誤検出しうるので warn に留め、人間が真偽を判定する候補として出す。
            out.append(Finding(
                "blocking-polarity", "warn", path, line,
                f"gate {gid} が yes と no の両方で出現（{where}）。"
                f"実際の矛盾なら極性規則を1箇所で定義して統一する。他 gate への言及なら無視してよい"))


def rule_stale_premise(root, docs, cfg, out):
    """「未作成」等を理由にしているが、参照先文書が既に実在する。"""
    # 参照先の実在は「検査対象」ではなく「プロジェクト全体」で判定する。
    # --files で1文書だけ検査したとき、参照先が対象外だと陳腐化を見逃してしまう。
    existing = cfg.get("_universe")
    if existing is None:
        existing = {}
        for d in docs:
            existing.setdefault(d.path.name, []).append(d.rel)
    phrases = cfg["stale_premise_phrases"]
    window = int(cfg["stale_premise_window"])
    name_pat = re.compile(r"[A-Za-z0-9_.\-]+\.(?:md|json|csv)")
    for d in docs:
        for i, line in d.enumerate("stale-premise"):
            spans = [(m.start(), m.end()) for ph in phrases
                     for m in re.finditer(re.escape(ph), line)]
            if not spans:
                continue
            for nm in name_pat.finditer(line):
                targets = existing.get(nm.group(0))
                if not targets or targets == [d.rel]:
                    continue
                # 句とファイル名が離れていれば別の話題。近接している場合だけ指摘する。
                near = any(min(abs(nm.start() - e), abs(s - nm.end())) <= window
                           and linked(line, e, nm.start(), "。;")
                           for s, e in spans)
                if not near:
                    continue
                note = "" if len(targets) == 1 else f"（同名が複数: {', '.join(targets)}）"
                out.append(Finding(
                    "stale-premise", "error", d.rel, i,
                    f"{nm.group(0)} は実在するのに未作成前提で理由が書かれている{note}。"
                    f"理由を実体条件（値・runner・evidence の未登録など）へ書き換える", line))
                break


def rule_bare_decision_id(root, docs, cfg, out):
    """修飾のない D-n / F-n。別文書が同じ番号体系を持つと誤解決する。

    同一行で一度修飾されていても、後続の裸参照は免除しない。名前空間の衝突は
    まさに「GDD D-9 と、別体系の D-9」のような行で起きるため。
    """
    id_pat = re.compile(cfg["decision_id_pattern"])
    quals = cfg["decision_qualifiers"]
    home = {Path(x).as_posix() for x in cfg["decision_id_home_docs"]}
    for d in docs:
        is_home = d.rel in home
        for i, line in d.enumerate("bare-decision-id"):
            table_definition = re.search(r"^\s*\|?\s*`?[DF]-\d+`?\s*\|", line)
            heading_definition = re.search(
                r"^\s*#{1,6}\s+`?[DF]-\d+`?\s*(?::|：|—|-|$)", line)
            if is_home and (table_definition or heading_definition):
                continue  # home 文書の定義行（表の先頭セル、または決定見出し）
            for m in id_pat.finditer(line):
                head = max(0, m.start() - 48)
                window = line[head:m.start()]
                # 修飾子が窓内にあっても、間に区切りがあれば別の参照。
                if any(q in window and linked(line, head + window.rindex(q) + len(q),
                                              m.start(), "、。,;・")
                       for q in quals):
                    continue
                out.append(Finding(
                    "bare-decision-id", "error", d.rel, i,
                    f"裸の {m.group(0)}。完全修飾する"
                    f"（例: GDD {m.group(0)} / Feasibility <節> {m.group(0)}）", line))
                break


def rule_unreferenced_value(root, docs, cfg, out):
    """非所有文書に単位つき数値があり、ID 参照も出所注記もない（二重正本の芽）。"""
    owners = {Path(o).as_posix() for o in cfg["value_owner_docs"]}
    if not owners:
        return  # 所有文書の指定が無い状態では判定できない（main で設定漏れを警告する）
    unit_pat = units_regex(cfg["value_units"])
    id_pats = [re.compile(x) for x in cfg["value_id_patterns"]]
    exempt = cfg["value_exempt_markers"]
    sourced = re.compile(r"\.(?:md|json|csv)\b")
    for d in docs:
        if d.rel in owners:
            continue
        for i, line in d.enumerate("unreferenced-value", skip_code=True):
            if not unit_pat.search(line):
                continue
            # 表のセル単位で見る。行のどこかに出所があるだけで全数値を免除しない。
            cells = split_cells(line)
            for cell in cells:
                if not unit_pat.search(cell):
                    continue
                if any(ip.search(cell) for ip in id_pats):
                    continue
                if any(k in cell for k in exempt) or sourced.search(cell):
                    continue
                out.append(Finding(
                    "unreferenced-value", "warn", d.rel, i,
                    "単位つき数値が ID 参照も出所注記もなく置かれている。"
                    "正本 ID を併記するか「転記。正本は参照先」と明記する", cell))
                break


def rule_line_ref_out_of_range(root, docs, cfg, out):
    """行番号参照が参照先の範囲外を指している。

    行がずれて『別の内容』を指す失効までは検出できない（内容照合が要る）。
    この rule が保証するのは範囲外・不正値・参照先不在の検出まで。
    """
    link_pat = re.compile(r"\(([^()\s]+?\.(?:md|json|csv))#L(\d+)(?:-L?(\d+))?\)")
    plain_pat = re.compile(r"`([A-Za-z0-9_./\-]+\.(?:md|json|csv)):(\d+)")
    cache: dict = {}

    def count(target: Path):
        key = target.as_posix()
        if key not in cache:
            cache[key] = (sum(1 for _ in target.open(encoding="utf-8", errors="ignore"))
                          if target.is_file() else None)
        return cache[key]

    for d in docs:
        for i, line in d.enumerate("line-ref-out-of-range"):
            for pat, base in ((link_pat, d.path.parent), (plain_pat, root)):
                for m in pat.finditer(line):
                    target = (base / m.group(1)).resolve()
                    n = count(target)
                    if n is None:
                        out.append(Finding(
                            "line-ref-out-of-range", "error", d.rel, i,
                            f"参照先 {m.group(1)} が存在しない", line))
                        continue
                    nums = [int(g) for g in m.groups()[1:] if g]
                    if any(v < 1 for v in nums):
                        out.append(Finding(
                            "line-ref-out-of-range", "error", d.rel, i,
                            f"{m.group(1)} の行番号が不正（1未満）", line))
                    elif len(nums) == 2 and nums[0] > nums[1]:
                        out.append(Finding(
                            "line-ref-out-of-range", "error", d.rel, i,
                            f"{m.group(1)} の行範囲が逆転している", line))
                    elif any(v > n for v in nums):
                        out.append(Finding(
                            "line-ref-out-of-range", "error", d.rel, i,
                            f"{m.group(1)}:{max(nums)} は参照先の行数({n})を超えている。"
                            f"節アンカー参照へ変えるか行番号を更新する", line))


def rule_template_placeholder(root, docs, cfg, out):
    """テンプレートのプレースホルダが残っている。

    ID の書式説明（`DATA-{DOMAIN}-{NNN}`）は未解決ではない。ただし免除するのは
    **有効な placeholder 同士**がハイフンで連なる場合だけ。`{1}-{path}.md` の
    ように隣が placeholder でないものを免除すると、本物の取り残しを見逃す。
    """
    token_pat = re.compile(r"\{\{[^{}\n]{1,60}\}\}|\{[^{}\n]{0,60}\}")
    has_word = re.compile(r"[A-Za-z_぀-ヿ一-鿿]")

    def qualified(tok: str) -> bool:
        if tok.startswith("{{"):
            return True
        body = tok[1:-1]
        if not 1 <= len(body) <= 40:
            return False
        if any(c in body for c in ',/"\':'):
            return False          # 集合・範囲記法（{0, 14}、{32/80}、{hit,miss}）
        return bool(has_word.search(body))

    for d in docs:
        for i, line in d.enumerate("template-placeholder", skip_code=True):
            toks = [(m.start(), m.end(), qualified(m.group(0)), m.group(0))
                    for m in token_pat.finditer(line)]
            for idx, (st, en, ok, tok) in enumerate(toks):
                if not ok:
                    continue
                # 直前・直後に「ハイフン1文字だけ」を挟んで別の有効 placeholder があるか
                fmt = any(
                    o_ok and ((o_en == st - 1 and line[st - 1] == "-")
                              or (o_st == en + 1 and line[en] == "-"))
                    for j, (o_st, o_en, o_ok, _) in enumerate(toks) if j != idx)
                if fmt:
                    continue
                out.append(Finding(
                    "template-placeholder", "error", d.rel, i,
                    f"未解決のプレースホルダ {tok}", line))
                break


def rule_contract_consumer(root, docs, cfg, out):
    """契約の consumer 側に受信 marker がない（受け口なき契約）。"""
    for c in cfg["contracts"]:
        cid = c.get("id", "<id 未設定>")
        marker = c.get("marker")
        owner_rel = c.get("owner", "")
        if not marker or not owner_rel:
            out.append(Finding("contract-consumer", "error", owner_rel or "<config>", 1,
                               f"契約 {cid} に owner または marker が設定されていない"))
            continue
        owner = root / owner_rel
        if not owner.is_file():
            out.append(Finding("contract-consumer", "error", owner_rel, 1,
                               f"契約 {cid} の owner 文書が存在しない"))
        elif marker not in owner.read_text(encoding="utf-8", errors="ignore"):
            out.append(Finding("contract-consumer", "error", owner_rel, 1,
                               f"契約 {cid} の marker '{marker}' が owner 文書に存在しない"))
        for cons in c.get("consumers", []):
            cp = root / cons
            if not cp.is_file():
                out.append(Finding("contract-consumer", "error", cons, 1,
                                   f"契約 {cid} の consumer 文書が存在しない"))
            elif marker not in cp.read_text(encoding="utf-8", errors="ignore"):
                out.append(Finding(
                    "contract-consumer", "error", cons, 1,
                    f"契約 {cid} の受信契約がない（marker '{marker}' 不在）。"
                    f"owner {owner_rel} が通知を定義しているのに受け取る側が閉じていない"))


def rule_forward_ref_resolved(root, docs, cfg, out):
    """登録済み前方参照の参照先が実在するようになった。理由句の書き換え時期。"""
    for f in cfg["forward_refs"]:
        to, frm = f.get("to", ""), f.get("from", "")
        if (root / to).is_file() and (root / frm).is_file():
            out.append(Finding(
                "forward-ref-resolved", "warn", frm, 1,
                f"前方参照先 {to} が実在するようになった。"
                f"理由句『{f.get('reason_marker', '')}』を実体条件へ書き換え、"
                f"解決したら forward_refs から削除する"))


def _detail_states(doc, id_re, field):
    """見出しごとの `- <field>: <値>` を集める。ID → (行番号, 値)。

    同じ ID の見出しが複数あれば最初のものを採る。索引と詳細が食い違うとき
    どちらが正本かは文書側の規約が決めるので、ここでは詳細節を基準に置く。
    """
    field_re = re.compile(rf"^\s*[-*]\s*{re.escape(field)}\s*[:：]\s*(.+)$")
    states, cur, cur_line = {}, None, 0
    for i, line in enumerate(doc.lines, 1):
        if line.lstrip().startswith("#"):
            m = id_re.search(line)
            cur, cur_line = (m.group(0), i) if m else (None, 0)
            continue
        if cur is None or cur in states or i in doc.in_code:
            continue
        m = field_re.match(line)
        if m:
            states[cur] = (cur_line, _first_token(m.group(1)))
    return states


def _first_token(raw: str) -> str:
    """`In progress（理由…）` から `In progress` を取る。注記は状態値ではない。"""
    for sep in ("（", "(", "。", "、", ",", "<!--"):
        raw = raw.split(sep)[0]
    return raw.replace("`", "").replace("*", "").strip()


def _table_cells(line: str):
    if not line.lstrip().startswith("|"):
        return None
    row = line.strip().strip("|")
    return [c.strip() for c in re.split(r"(?<!\\)\|", row)]


def rule_status_index_drift(root, docs, cfg, out):
    """索引表の状態値が詳細節と食い違う（片側更新で失効した状態値）。

    実運用で3回再発した型。詳細節だけ直して索引や総則を直し忘れると、
    索引しか読まない人が着手済みの項目を未着手と誤認する。
    人手の全文走査では毎回取り零したので機械検査へ移す。
    """
    by_rel = {d.rel: d for d in docs}
    for spec in cfg["status_consistency"]:
        target = spec.get("file", "")
        field = spec.get("field", "Status")
        doc = by_rel.get(target)
        if doc is None:
            if cfg.get("_files_explicit"):
                # --files は明示した文書だけを検査する。設定にある別文書を
                # 「存在しない」と誤判定しない。
                continue
            out.append(Finding("status-index-drift", "error", target or "<config>", 1,
                               "status_consistency の file が対象文書に含まれていない"))
            continue
        try:
            id_re = re.compile(spec["id_pattern"])
        except (KeyError, re.error) as exc:
            out.append(Finding("status-index-drift", "error", target, 1,
                               f"status_consistency の id_pattern が不正: {exc}"))
            continue

        states = _detail_states(doc, id_re, field)
        if not states:
            out.append(Finding("status-index-drift", "error", target, 1,
                               f"詳細節に `- {field}:` が1件も見つからない。"
                               f"id_pattern または field の指定が実際の書式と合っていない"))
            continue

        col, header_found, compared, indexed = None, False, 0, set()
        for i, line in doc.enumerate("status-index-drift"):
            if i in doc.in_code:
                continue
            cells = _table_cells(line)
            if not cells:
                col = None
                continue
            if col is None:
                if field in cells:
                    col, header_found = cells.index(field), True
                continue
            if col >= len(cells) or set(cells[col]) <= set("-: "):
                continue
            m = next((id_re.search(c) for c in cells if id_re.search(c)), None)
            if m is None:
                continue
            wid = m.group(0)
            indexed.add(wid)
            if wid not in states:
                continue
            compared += 1
            detail_line, detail_val = states[wid]
            if _first_token(cells[col]) != detail_val:
                out.append(Finding(
                    "status-index-drift", "error", target, i,
                    f"{wid} の {field} が索引 `{_first_token(cells[col])}`、"
                    f"詳細節（:{detail_line}）`{detail_val}` で食い違う。"
                    f"詳細節が正本なら索引を同期する", line))

        # 突合が0件で PASS すると「検査した」と誤解される。検査対象が無いことと
        # 検査して問題が無いことは違うので、前者は設定不備として落とす。
        if not header_found:
            out.append(Finding("status-index-drift", "error", target, 1,
                               f"`{field}` を列に持つ索引表が見つからない。"
                               f"field の指定が実際の表見出しと合っていない"))
        elif compared == 0:
            out.append(Finding("status-index-drift", "error", target, 1,
                               f"索引表と詳細節で突合できた {field} が0件。"
                               f"id_pattern が索引行の ID 表記と合っていない可能性がある"))

        # 片方にしか無い ID は、綴り違いや登録漏れで黙って検査から外れた候補。
        # 意図的な索引専用行は index_only_ids で宣言させる。宣言を求めるのは、
        # 「詳細節が無いのは仕様」と「綴り違いで取れなかった」が外形上は同じだから。
        declared = set(spec.get("index_only_ids", []))
        for wid in sorted(declared - indexed):
            out.append(Finding("status-index-drift", "warn", target, 1,
                               f"index_only_ids の {wid} が索引に存在しない。"
                               f"宣言が古い可能性がある"))
        for wid in sorted(indexed - set(states) - declared):
            out.append(Finding("status-index-drift", "warn", target, 1,
                               f"{wid} は索引にあるが詳細節の `- {field}:` が取れない。"
                               f"意図的な索引専用行でないなら、綴り違いか記載漏れ"))
        for wid in sorted(set(states) - indexed):
            out.append(Finding("status-index-drift", "warn", target, 1,
                               f"{wid} は詳細節にあるが索引に現れない。索引の登録漏れ"))

        distinct = {v for _, v in states.values()}
        for phrase in spec.get("blanket_phrases", []):
            if len(distinct) <= 1:
                break
            for i, line in doc.enumerate("status-index-drift"):
                if i not in doc.in_code and phrase in line:
                    out.append(Finding(
                        "status-index-drift", "error", target, i,
                        f"『{phrase}』と一律に述べているが、詳細節の {field} は"
                        f"{len(distinct)}種類（{'、'.join(sorted(distinct))}）ある", line))


def rule_self_verification_claim(root, reports, cfg, out):
    """執筆モデルの報告に、発注していない検証の主張がある。"""
    for d in reports:
        for i, line in d.enumerate("self-verification-claim"):
            for t in cfg["self_verification_terms"]:
                if t in line:
                    out.append(Finding(
                        "self-verification-claim", "warn", d.rel, i,
                        f"報告に検証語彙『{t}』。発注していない検証の主張なら"
                        f"記録して不採用にする（争わない）", line))
                    break


def entry_scope(d, lineno: int, window: int, stop: re.Pattern) -> str:
    """エントリ行と、それに属する続き行。次のエントリが現れた時点で打ち切る。

    打ち切らないと、出所を書き忘れた決定が「隣の決定の出所」を拾って通ってしまう。
    """
    body = [d.lines[lineno - 1]]
    for j in range(lineno, min(lineno + window, len(d.lines))):
        if stop.search(d.lines[j]):
            break
        body.append(d.lines[j])
    return "\n".join(body)


def rule_unsourced_decision(root, docs, cfg, out):
    """[DECISION] に出所（U/W/M/J または evidence 参照）がない。

    出所は「何を根拠にしたか」を示し、承認記録は「誰が確定したか」を示す。両者は
    代替関係ではない。この規則は前者の欠落だけを検出する。
    """
    src_pat = re.compile(cfg["decision_source_pattern"])
    dec_pat = re.compile(r"\[DECISION\b[^\]]*\]")
    tag_pat = re.compile(r"\[(?:FACT|DECISION|PROPOSAL|ASSUMPTION|OPEN|HUMAN|EXTERNAL)[^\]]*\]")
    exempt = {Path(x).as_posix() for x in cfg["decision_source_exempt_docs"]}
    window = max(0, int(cfg["decision_source_window"]))
    for d in docs:
        if d.rel in exempt:
            continue
        for i, line in d.enumerate("unsourced-decision", skip_code=True):
            if not dec_pat.search(line):
                continue
            if len({m.group(0) for m in tag_pat.finditer(line)}) >= 3:
                continue  # タグ凡例
            # 出所は同一行のほか、直後の数行（表の続き・箇条書きの子項目）にも置ける。
            if src_pat.search(entry_scope(d, i, window, dec_pat)):
                continue
            out.append(Finding(
                "unsourced-decision", "error", d.rel, i,
                f"[DECISION] に出所がない。src: U|W|M|J または evidence: を同じ行"
                f"（または直後 {window} 行）へ書く。"
                f"U=ユーザー発言 / W=調査 / M=実測 / J=指示役提案", line))


def rule_decision_approval_record(root, docs, cfg, out):
    """[DECISION] に人間承認記録またはその参照がない。"""
    approval_pat = re.compile(cfg["decision_approval_pattern"], re.IGNORECASE)
    dec_pat = re.compile(r"\[DECISION\b[^\]]*\]")
    tag_pat = re.compile(
        r"\[(?:FACT|DECISION|PROPOSAL|ASSUMPTION|OPEN|HUMAN|EXTERNAL)[^\]]*\]")
    exempt = {Path(x).as_posix() for x in cfg["decision_approval_exempt_docs"]}
    window = max(0, int(cfg["decision_approval_window"]))
    for d in docs:
        if d.rel in exempt:
            continue
        for i, line in d.enumerate("decision-approval-record", skip_code=True):
            if not dec_pat.search(line):
                continue
            if len({m.group(0) for m in tag_pat.finditer(line)}) >= 3:
                continue  # タグ凡例
            if approval_pat.search(entry_scope(d, i, window, dec_pat)):
                continue
            out.append(Finding(
                "decision-approval-record", "error", d.rel, i,
                f"[DECISION] に人間承認記録がない。approver:/承認者: と "
                f"approval_record:/承認記録: のいずれかを同じ行（または直後 {window} 行）へ書く。"
                "出所は承認の代替ではない", line))


def rule_human_action_exec_class(root, docs, cfg, out):
    """Human Action が human-only と明示されていない。

    canonical template のように行内へ [HUMAN] を繰り返さず、H-001 の ID だけを持つ表も
    対象にする。[HUMAN] を ai-* として完了扱いにしない。
    """
    ledgers = {Path(x).as_posix() for x in cfg["human_action_ledgers"]}
    if not ledgers:
        return  # 台帳の指定が無い状態では判定できない（main で設定漏れを警告する）
    exec_pat = re.compile(cfg["human_exec_pattern"])
    exec_values = {str(v).lower() for v in cfg["human_exec_values"]}
    id_pat = re.compile(cfg["human_action_id_pattern"], re.IGNORECASE)
    window = max(0, int(cfg["human_exec_window"]))

    def table_entry(line):
        cells = _table_cells(line)
        if not cells:
            return False
        first = cells[0].replace("`", "").replace("*", "").strip()
        return bool(id_pat.fullmatch(first))

    def table_has_exec(line):
        cells = _table_cells(line) or []
        normalized = {
            c.replace("`", "").replace("*", "").strip().lower() for c in cells
        }
        return bool(normalized & exec_values)

    for d in docs:
        if d.rel not in ledgers:
            continue
        table_columns = None
        for i, line in d.enumerate("human-action-exec-class", skip_code=True):
            cells = _table_cells(line)
            if cells and "Status" in cells:
                table_columns = {name.strip(): index for index, name in enumerate(cells)}
                continue
            tabular = table_entry(line)
            identified = bool(id_pat.search(line))
            if not identified and not tabular:
                continue
            body = [line]
            for j in range(i, min(i + window, len(d.lines))):
                if id_pat.search(d.lines[j]) or table_entry(d.lines[j]):
                    break
                body.append(d.lines[j])
            if tabular and cells:
                status_index = table_columns.get("Status") if table_columns else None
                status = (cells[status_index].strip().lower()
                          if status_index is not None and status_index < len(cells) else "")
                if status in {"completed", "done", "closed"}:
                    evidence_index = (table_columns.get("Actual evidence")
                                      if table_columns else None)
                    completed_index = (table_columns.get("Completed at")
                                       if table_columns else None)
                    evidence = (cells[evidence_index].strip()
                                if evidence_index is not None and evidence_index < len(cells) else "")
                    completed_at = (cells[completed_index].strip()
                                    if completed_index is not None and completed_index < len(cells) else "")
                    if evidence in {"", "-", "—"}:
                        out.append(Finding(
                            "human-action-exec-class", "error", d.rel, i,
                            "Completed Human Action requires non-placeholder Actual evidence", line))
                    try:
                        raw = completed_at[:-1] + "+00:00" if completed_at.endswith("Z") else completed_at
                        parsed = dt.datetime.fromisoformat(raw)
                        if parsed.tzinfo is None or parsed.utcoffset() is None:
                            raise ValueError
                    except ValueError:
                        out.append(Finding(
                            "human-action-exec-class", "error", d.rel, i,
                            "Completed Human Action requires timezone ISO-8601 Completed at", line))
            if exec_pat.search("\n".join(body)) or any(table_has_exec(x) for x in body):
                continue
            out.append(Finding(
                "human-action-exec-class", "error", d.rel, i,
                f"Human Action は人間専権。同じ行（または直後 {window} 行）へ "
                f"exec: human-only と書く。AI実行可能なら [AI-ACTION] と AI_ACTIONS.md "
                f"へ別actionとして分離する", line))


def rule_ai_action_exec_class(root, docs, cfg, out):
    """AI Action 台帳のエントリに許可された実行分類がない。"""
    ledgers = {Path(x).as_posix() for x in cfg["ai_action_ledgers"]}
    if not ledgers:
        return
    exec_pat = re.compile(cfg["ai_exec_pattern"])
    exec_values = {str(v).lower() for v in cfg["ai_exec_values"]}
    action_pat = re.compile(r"\[AI-ACTION\b[^\]]*\]", re.IGNORECASE)
    id_pat = re.compile(cfg["ai_action_id_pattern"], re.IGNORECASE)
    window = max(0, int(cfg["ai_exec_window"]))

    def table_entry(line):
        cells = _table_cells(line)
        if not cells:
            return False
        first = cells[0].replace("`", "").replace("*", "").strip()
        return bool(id_pat.fullmatch(first))

    def table_has_exec(line):
        cells = _table_cells(line) or []
        normalized = {
            c.replace("`", "").replace("*", "").strip().lower() for c in cells
        }
        return bool(normalized & exec_values)

    def has_id(line):
        # The default ID grammar also matches the tag text "AI-ACTION".
        # Remove tags before looking for an actual ledger entry ID.
        return bool(id_pat.search(action_pat.sub("", line)))

    for d in docs:
        if d.rel not in ledgers:
            continue
        for i, line in d.enumerate("ai-action-exec-class", skip_code=True):
            if not has_id(line) and not table_entry(line):
                continue
            body = [line]
            for j in range(i, min(i + window, len(d.lines))):
                if has_id(d.lines[j]) or table_entry(d.lines[j]):
                    break
                body.append(d.lines[j])
            if exec_pat.search("\n".join(body)) or any(table_has_exec(x) for x in body):
                continue
            out.append(Finding(
                "ai-action-exec-class", "error", d.rel, i,
                f"AI Action に exec 分類がない。同じ行（または直後 {window} 行）へ "
                f"exec: {'|'.join(sorted(exec_values))} のいずれかを書く", line))


DOC_RULES = [
    rule_bare_open, rule_blocking_polarity, rule_stale_premise, rule_bare_decision_id,
    rule_unreferenced_value, rule_line_ref_out_of_range, rule_template_placeholder,
    rule_contract_consumer, rule_forward_ref_resolved, rule_status_index_drift,
    rule_unsourced_decision, rule_decision_approval_record, rule_human_action_exec_class,
    rule_ai_action_exec_class,
]
REPORT_RULES = [rule_self_verification_claim]


def rule_name(fn) -> str:
    return fn.__name__[len("rule_"):].replace("_", "-")


KNOWN_RULES = [rule_name(f) for f in DOC_RULES + REPORT_RULES]


def resolve(path: Path | None, root: Path) -> Path | None:
    """相対パスは呼び出し時 CWD ではなく project-root 基準で解決する。"""
    if path is None:
        return None
    return path if path.is_absolute() else (root / path)


def main() -> int:
    # Windows Claude sessions may inherit cp932; keep Unicode help/output
    # printable without requiring caller-specific environment flags.
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="backslashreplace")
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--project-root", type=Path, default=Path.cwd())
    ap.add_argument("--config", type=Path, default=None)
    ap.add_argument("--files", nargs="+", default=None, help="対象を限定（既定は config の doc_globs）")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--only", nargs="+", default=None,
                    help=f"実行する rule 名。選べるのは: {', '.join(KNOWN_RULES)}")
    ap.add_argument("--list-rules", action="store_true")
    args = ap.parse_args()

    if args.list_rules:
        print("\n".join(KNOWN_RULES))
        return 0

    root = args.project_root.resolve()
    if not root.is_dir():
        print(f"ERROR: --project-root が存在しない: {root}", file=sys.stderr)
        return 2

    explicit_cfg = args.config is not None
    cfg_path = resolve(args.config, root) if explicit_cfg else (root / ".claude" / "doc-lint.json")
    try:
        cfg = load_config(cfg_path, explicit_cfg, KNOWN_RULES)
    except ConfigError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    if args.only:
        unknown = [r for r in args.only if r not in KNOWN_RULES]
        if unknown:
            print(f"ERROR: 未知の rule 名: {', '.join(unknown)}\n"
                  f"       選べるのは: {', '.join(KNOWN_RULES)}", file=sys.stderr)
            return 2

    if args.files:
        paths, missing = [], []
        for f in args.files:
            p = resolve(Path(f), root)
            (paths if p.is_file() else missing).append(p)
        if missing:
            print("ERROR: --files に存在しないパスがある:\n  "
                  + "\n  ".join(str(m) for m in missing), file=sys.stderr)
            return 2
    else:
        paths = collect(root, cfg["doc_globs"], cfg["exclude_globs"])
        if not paths:
            print("ERROR: doc_globs が1件も一致しない。設定の doc_globs / project-root を確認する",
                  file=sys.stderr)
            return 2

    docs = [Doc(root, p) for p in paths]
    cfg["_files_explicit"] = bool(args.files)
    reports = [Doc(root, p) for p in collect(root, cfg["report_globs"], [])]
    universe: dict = {}
    for p in collect(root, cfg["doc_globs"], cfg["exclude_globs"]):
        universe.setdefault(p.name, []).append(rel(root, p))
    cfg["_universe"] = universe

    disabled = {k for k, v in cfg["rules"].items() if v is False}
    selected = set(args.only) if args.only else None
    findings: list = []
    executed = []
    for fn in DOC_RULES + REPORT_RULES:
        name = rule_name(fn)
        if name in disabled or (selected is not None and name not in selected):
            continue
        executed.append(name)
        fn(root, reports if fn in REPORT_RULES else docs, cfg, findings)

    executed_set = set(executed)
    notes = []
    if "unreferenced-value" in executed_set and not cfg["value_owner_docs"]:
        notes.append("value_owner_docs が未設定のため unreferenced-value は未検査")
    if "contract-consumer" in executed_set and not cfg["contracts"]:
        notes.append("contracts が未設定のため contract-consumer は未検査")
    if "status-index-drift" in executed_set and not cfg["status_consistency"]:
        notes.append("status_consistency が未設定のため status-index-drift は未検査")
    if "human-action-exec-class" in executed_set and not cfg["human_action_ledgers"]:
        notes.append("human_action_ledgers が未設定のため human-action-exec-class は未検査")
    if "ai-action-exec-class" in executed_set and not cfg["ai_action_ledgers"]:
        notes.append("ai_action_ledgers が未設定のため ai-action-exec-class は未検査")

    findings.sort(key=lambda f: (SEVERITY_ORDER.get(f.severity, 9), f.path, f.line))
    errors = sum(1 for f in findings if f.severity == "error")
    warns = len(findings) - errors
    gate_pass = errors == 0 and warns == 0 and not notes

    if args.json:
        print(json.dumps({
            "pass": gate_pass,
            "errors": errors, "warnings": warns,
            "documents_scanned": len(docs), "reports_scanned": len(reports),
            "config": str(cfg_path) if cfg_path and cfg_path.is_file() else None,
            "rules_executed": executed, "configuration_notes": notes,
            "findings": [f.as_dict() for f in findings],
        }, ensure_ascii=False, indent=2))
    else:
        for f in findings:
            tag = "ERROR" if f.severity == "error" else "warn "
            print(f"{tag} [{f.rule}] {f.path}:{f.line}  {f.message}")
            if f.excerpt:
                print(f"        | {f.excerpt}")
        for n in notes:
            print(f"note  {n}")
        print(f"\n{'PASS' if gate_pass else 'FAIL'}  文書 {len(docs)} / "
              f"rule {len(executed)} / error {errors} / warn {warns} / "
              f"unverified {len(notes)}")
    return 0 if gate_pass else 1


if __name__ == "__main__":
    sys.exit(main())
