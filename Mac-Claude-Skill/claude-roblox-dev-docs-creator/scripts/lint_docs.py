#!/usr/bin/env python3
"""
LLM 生成ドキュメント体系の機械検査。

LLM 照合が見つける指摘のうち、正規表現で検出できる定型欠陥を先に潰すためのもの。
照合へ出す前に必ず走らせる。標準ライブラリのみを使用し、元ファイルを変更しない。

  python3 lint_docs.py --project-root . --config .claude/doc-lint.json
  python3 lint_docs.py --project-root . --config .claude/doc-lint.json --files docs/specs/new_spec.md
  python3 lint_docs.py --project-root . --config .claude/doc-lint.json --json

終了コード: 0 = error なし / 1 = error あり / 2 = 入力・設定の誤り

設計方針: **fail-closed**。指定した設定ファイルが無い、ルール名を打ち間違えた、
対象ファイルが存在しない——このいずれでも「PASS」を返さない。品質ゲートが
入力ミスを黙って通すと、通ったことに意味が無くなる。

行単位の抑制:  <!-- doc-lint-ignore-line: rule-name[,rule-name] -->
ファイル単位:  <!-- doc-lint-ignore-file: rule-name[,rule-name] -->
規約を説明する散文など、正しいのに検出される行はこれで明示的に抑制する。
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

DEFAULT_CONFIG = {
    "doc_globs": ["docs/**/*.md", "*.md"],
    "exclude_globs": ["docs/handoffs/**", "**/node_modules/**"],
    "report_globs": ["docs/handoffs/out/*_last-message.md"],
    "index_globs": [],          # gen_index.py が使う。設定ファイルを共有するため既知キーに含める
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
        "読み取り専用レビュー", "別エージェント",
    ],
    "contracts": [],
    "forward_refs": [],
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
            if is_home and re.search(r"^\s*\|?\s*`?[DF]-\d+`?\s*\|", line):
                continue  # home 文書の定義行（表の先頭セルが ID そのもの）
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


DOC_RULES = [
    rule_bare_open, rule_blocking_polarity, rule_stale_premise, rule_bare_decision_id,
    rule_unreferenced_value, rule_line_ref_out_of_range, rule_template_placeholder,
    rule_contract_consumer, rule_forward_ref_resolved,
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
    reports = [Doc(root, p) for p in collect(root, cfg["report_globs"], [])]
    universe: dict = {}
    for p in collect(root, cfg["doc_globs"], cfg["exclude_globs"]):
        universe.setdefault(p.name, []).append(rel(root, p))
    cfg["_universe"] = universe

    disabled = {k for k, v in cfg["rules"].items() if v is False}
    selected = set(args.only) if args.only else None
    notes = []
    if not cfg["value_owner_docs"]:
        notes.append("value_owner_docs が未設定のため unreferenced-value は無効")
    if not cfg["contracts"]:
        notes.append("contracts が未設定のため contract-consumer は実質無効")

    findings: list = []
    executed = []
    for fn in DOC_RULES + REPORT_RULES:
        name = rule_name(fn)
        if name in disabled or (selected is not None and name not in selected):
            continue
        executed.append(name)
        fn(root, reports if fn in REPORT_RULES else docs, cfg, findings)

    findings.sort(key=lambda f: (SEVERITY_ORDER.get(f.severity, 9), f.path, f.line))
    errors = sum(1 for f in findings if f.severity == "error")
    warns = len(findings) - errors

    if args.json:
        print(json.dumps({
            "pass": errors == 0,
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
        print(f"\n{'FAIL' if errors else 'PASS'}  文書 {len(docs)} / "
              f"rule {len(executed)} / error {errors} / warn {warns}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
