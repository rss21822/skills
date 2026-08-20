#!/usr/bin/env python3
"""P0 状態の跨文書検査。

文書内の整合は既存 lint が見る。本 script が見るのは**文書をまたぐ**不整合で、
実プロジェクトで独立照合が2巡かけて発見した型を機械化したもの。

  wp-status-cross-doc  Work Package の Status が正本と運行記録で食い違う
  git-current-facts    現況として宣言された commit hash・未 push 件数が実測と違う
  open-evidence        [OPEN] に closure evidence と Owner が揃っていない
  decision-ref         参照された決定 ID が決定記録に存在しない

設定が無い項目は検査せず、その旨を note で知らせる。**note が出ている観点は
「検査して問題なし」ではなく「検査していない」。** PASS を全件確認と誤読しない。
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

from strict_json import loads as strict_json_loads

DEFAULT_CONFIG = {
    # Status の正本（索引表と詳細節を持つ文書）
    "wp_status_source": "docs/{PREFIX}_work_packages.md",
    # Status を写している運行記録。ここが正本とずれるのが検出対象
    "wp_status_mirrors": ["PROGRESS.md"],
    "wp_id_pattern": r"WP-[A-Z0-9]+-\d+[A-Z]?",
    "status_field": "Status",
    # architect の Work Package template が定める語彙。勝手に増減しない
    "status_vocabulary": ["Proposed", "Approved", "In progress", "Verified", "Superseded"],
    # 履歴として時制限定された行は現況の宣言ではないので除外する
    "history_markers": ["記録時点", "時点では", "時点の", "当時", "だった", "であった", "旧値"],
    # 現況の git 値を宣言している文書
    "git_fact_docs": ["PROGRESS.md"],
    "git_remote_ref": "origin/main",
    # open を収録する文書
    "open_docs": [],
    "open_pattern": r"\[OPEN blocking:\s*(yes|no)\]",
    "open_required_terms": ["closure evidence", "Owner"],
    # 決定 ID
    "decision_record": "DECISIONS.md",
    "decision_heading_pattern": r"^#{2,4}\s+(.*?D-\d+)\s*[:：]",
    "decision_ref_pattern": r"(?<![A-Za-z0-9-])`?((?:[A-Za-z0-9 ]+ )?D-\d+)`?",
    "decision_ref_docs": [],
    # Gate use is fail-closed: warnings and unconfigured observations also fail.
    "strict": False,
    "rules": {},
}

SEVERITY_ORDER = {"error": 0, "warn": 1}


class ConfigError(Exception):
    pass


class Finding:
    __slots__ = ("rule", "severity", "path", "line", "message", "excerpt")

    def __init__(self, rule, severity, path, line, message, excerpt=""):
        self.rule, self.severity, self.path = rule, severity, path
        self.line, self.message = line, message
        self.excerpt = excerpt.strip()[:160]

    def as_dict(self):
        return {"rule": self.rule, "severity": self.severity, "path": self.path,
                "line": self.line, "message": self.message, "excerpt": self.excerpt}


def read(root: Path, rel: str) -> list[str] | None:
    p = root / rel
    if not p.is_file():
        return None
    return p.read_text(encoding="utf-8", errors="ignore").splitlines()


def first_token(raw: str) -> str:
    """`In progress（理由…）` から `In progress` を取る。注記は状態値ではない。"""
    for sep in ("（", "(", "。", "、", ",", "<!--"):
        raw = raw.split(sep)[0]
    return raw.replace("`", "").replace("*", "").strip()


def table_cells(line: str):
    if not line.lstrip().startswith("|"):
        return None
    return [c.strip() for c in re.split(r"(?<!\\)\|", line.strip().strip("|"))]


def canonical_status(root, cfg, out) -> dict:
    """正本文書から WP ID → (行番号, Status) を作る。索引と詳細節の両方を見る。"""
    rel = cfg["wp_status_source"]
    lines = read(root, rel)
    if lines is None:
        out.append(Finding("wp-status-cross-doc", "error", rel, 1,
                           "Status の正本文書が存在しない。wp_status_source の指定を確認する"))
        return {}
    try:
        id_re = re.compile(cfg["wp_id_pattern"])
    except re.error as exc:
        out.append(Finding("wp-status-cross-doc", "error", rel, 1,
                           f"wp_id_pattern が不正: {exc}"))
        return {}

    field = cfg["status_field"]
    field_re = re.compile(rf"^\s*[-*]\s*{re.escape(field)}\s*[:：]\s*(.+)$")
    detail, cur = {}, None
    for i, line in enumerate(lines, 1):
        if line.lstrip().startswith("#"):
            m = id_re.search(line)
            cur = m.group(0) if m else None
            continue
        if cur and cur not in detail:
            m = field_re.match(line)
            if m:
                detail[cur] = (i, first_token(m.group(1)))

    if not detail:
        out.append(Finding("wp-status-cross-doc", "error", rel, 1,
                           f"詳細節に `- {field}:` が1件も無い。"
                           f"wp_id_pattern または status_field が実際の書式と合っていない"))
    return detail


def rule_wp_status_cross_doc(root, cfg, out):
    """正本の Status と、それを写した運行記録が食い違う。

    文書内 lint では検出できない。正本の索引と詳細節が「どちらも旧値で一致」して
    いると 0 件を返すためで、実際にそれで Major を見逃した。
    """
    canon = canonical_status(root, cfg, out)
    if not canon:
        return
    id_re = re.compile(cfg["wp_id_pattern"])
    vocab = cfg["status_vocabulary"]
    markers = cfg["history_markers"]
    field = re.escape(cfg["status_field"])
    alt = "|".join(re.escape(v) for v in sorted(vocab, key=len, reverse=True))
    prose_re = re.compile(rf"{field}\s*(?:は|が|:|：|=|＝)\s*`?({alt})`?")

    for rel in cfg["wp_status_mirrors"]:
        lines = read(root, rel)
        if lines is None:
            out.append(Finding("wp-status-cross-doc", "error", rel, 1,
                               "wp_status_mirrors の文書が存在しない"))
            continue
        col = None
        for i, line in enumerate(lines, 1):
            if any(mk in line for mk in markers):
                col = None
                continue  # 履歴として時制限定された行は現況の宣言ではない
            claimed, wid = None, None
            cells = table_cells(line)
            if cells:
                # 表の Status 列だけを見る。散文は対象にしない（下記の理由）
                if col is None:
                    if cfg["status_field"] in cells:
                        col = cells.index(cfg["status_field"])
                    continue
                if col < len(cells) and not set(cells[col]) <= set("-: "):
                    # ID は先頭セルにあるものだけを対象にする。説明セルに ID を含む
                    # 別種の表（phase 進捗表など）を WP 行と誤認しないため
                    m = id_re.search(cells[0]) if cells else None
                    if m:
                        wid, claimed = m.group(0), first_token(cells[col])
            else:
                col = None
                # 散文は「Status は `X`」という明示形だけを見る。状態語が出るだけの
                # 説明文を拾うと、状態遷移を記述した履歴で大量に誤検出する。
                m = prose_re.search(line)
                if m:
                    # 「Status は X」の直前に現れる ID へ帰属させる。1行に複数の WP が
                    # 出るのは普通なので、全 ID へ配ると誤検出になる
                    prior = [k for k in id_re.finditer(line) if k.start() < m.start()]
                    if prior:
                        wid, claimed = prior[-1].group(0), first_token(m.group(1))
            if not wid or wid not in canon or claimed not in vocab:
                continue
            cline, cstatus = canon[wid]
            if claimed != cstatus:
                out.append(Finding(
                    "wp-status-cross-doc", "error", rel, i,
                    f"{wid} の {cfg['status_field']} を `{claimed}` と述べているが、"
                    f"正本（{cfg['wp_status_source']}:{cline}）は `{cstatus}`。"
                    f"履歴なら時制を限定し、現況なら正本へ同期する", line))


def git(root: Path, executable: Path, *args) -> str | None:
    try:
        r = subprocess.run([str(executable), "-C", str(root), *args],
                           capture_output=True, text=True, encoding="utf-8",
                           errors="replace", timeout=20, shell=False)
    except (OSError, subprocess.SubprocessError):
        return None
    return r.stdout.strip() if r.returncode == 0 else None


def rule_git_current_facts(root, cfg, out):
    """現況として宣言された commit hash・未 push 件数が実測と違う。

    「未 push N commit」型は commit のたびに失効する。実プロジェクトでは3回連続で
    再発した。件数を保持しない書き方（実測コマンドを正とする）へ移すのが本筋で、
    本規則はその移行が済むまでの検出網。

    走査は**現況が宣言されるヘッダ区間**（最初の `##` 見出しより前）に限る。
    それ以降は履歴節であり、旧値が残っているのが正しい。
    """
    executable = cfg.get("_git_executable")
    if not isinstance(executable, Path):
        out.append(Finding(
            "git-current-facts", "error", "<git>", 1,
            "git-current-facts requires explicit --git-executable; ambient PATH lookup is forbidden"))
        return
    head = git(root, executable, "rev-parse", "HEAD")
    if head is None:
        out.append(Finding("git-current-facts", "error", "<git>", 1,
                           "git が実行できない、または repository ではない"))
        return
    remote_ref = cfg["git_remote_ref"]
    remote = git(root, executable, "rev-parse", remote_ref)
    if remote is None:
        out.append(Finding("git-current-facts", "error", "<git>", 1,
                           f"git_remote_ref `{remote_ref}` を解決できない。"
                           f"remote 側の比較が成立しないので設定を確認する"))
        return
    ahead = git(root, executable, "rev-list", "--count", f"{remote_ref}..HEAD")
    markers = cfg["history_markers"]
    count_re = re.compile(r"未\s*push\s*(?:が|は)?\s*(\d+)\s*(?:件|commit)")
    ref_re = re.compile(re.escape(remote_ref) + r"\s*(?:=|は|:)\s*`?([0-9a-f]{7,40})`?")
    head_re = re.compile(r"HEAD\s*(?:=|は|:)\s*`?([0-9a-f]{7,40})`?")

    for rel in cfg["git_fact_docs"]:
        lines = read(root, rel)
        if lines is None:
            out.append(Finding("git-current-facts", "error", rel, 1,
                               "git_fact_docs の文書が存在しない"))
            continue
        for i, line in enumerate(lines, 1):
            if line.startswith("## "):
                break  # ここから先は履歴節
            if any(mk in line for mk in markers):
                continue
            m = count_re.search(line)
            if m and ahead is not None and m.group(1) != ahead:
                out.append(Finding(
                    "git-current-facts", "error", rel, i,
                    f"未 push 件数を {m.group(1)} と宣言しているが実測は {ahead}。"
                    f"件数を保持せず `git rev-list --count {remote_ref}..HEAD` の実測を"
                    f"正とする書き方へ改めると再発しない", line))
            m = ref_re.search(line)
            if m and remote and not remote.startswith(m.group(1)):
                out.append(Finding(
                    "git-current-facts", "error", rel, i,
                    f"{remote_ref} を `{m.group(1)}` と宣言しているが実測は "
                    f"`{remote[:len(m.group(1))]}`。remote が進んでいる", line))
            m = head_re.search(line)
            if m and not head.startswith(m.group(1)):
                out.append(Finding(
                    "git-current-facts", "error", rel, i,
                    f"HEAD を `{m.group(1)}` と宣言しているが実測は "
                    f"`{head[:len(m.group(1))]}`", line))


def rule_open_evidence(root, cfg, out):
    """[OPEN] に closure evidence・Owner・理由が揃っていない。

    揃っていない open は「いつ閉じられるか」が誰にも分からず、放置される。
    """
    try:
        open_re = re.compile(cfg["open_pattern"])
    except re.error as exc:
        out.append(Finding("open-evidence", "error", "<config>", 1,
                           f"open_pattern が不正: {exc}"))
        return
    terms = cfg["open_required_terms"]
    for rel in cfg["open_docs"]:
        lines = read(root, rel)
        if lines is None:
            out.append(Finding("open-evidence", "error", rel, 1,
                               "open_docs の文書が存在しない"))
            continue
        for i, line in enumerate(lines, 1):
            if not open_re.search(line):
                continue
            # 生きた open だけを対象にする。closure record や履歴行が open marker に
            # 言及しているだけのものを拾うと、閉じた open を毎回鳴らすことになる
            cells = table_cells(line)
            heads = [c.strip().strip("`*") for c in cells] if cells else [line.strip()]
            if not any(h.startswith("[OPEN") for h in heads):
                continue
            missing = [t for t in terms if t not in line]
            if not missing:
                continue
            # 散文形式の open は書ける余地があるので error、表のセルに収めた open は
            # 記法が限られるので warn。どちらも「閉じる条件が読めない」点は同じだが、
            # 表形式まで error にすると既存文書で鳴り続けて無視されるようになる
            sev = "warn" if cells else "error"
            out.append(Finding(
                "open-evidence", sev, rel, i,
                f"open に {'・'.join(missing)} が無い。"
                f"閉じる条件と担当が読めない open は放置される", line))


def rule_decision_ref(root, cfg, out):
    """参照された決定 ID が決定記録に存在しない。"""
    rel = cfg["decision_record"]
    lines = read(root, rel)
    if lines is None:
        out.append(Finding("decision-ref", "error", rel, 1,
                           "decision_record が存在しない"))
        return
    try:
        head_re = re.compile(cfg["decision_heading_pattern"])
    except re.error as exc:
        out.append(Finding("decision-ref", "error", "<config>", 1,
                           f"decision_heading_pattern が不正: {exc}"))
        return
    defined = set()
    for line in lines:
        m = head_re.match(line)
        if m:
            defined.add(m.group(1).strip().strip("`"))
    if not defined:
        out.append(Finding("decision-ref", "error", rel, 1,
                           "決定記録から決定 ID を1件も抽出できない。"
                           "decision_heading_pattern が実際の見出し書式と合っていない"))
        return

    # 末尾番号だけの一致を「解決した」と扱うと、完全修飾を要求する規約が空文になる。
    # 番号は合うが修飾が違う参照は、名前空間衝突の兆候そのものなので別扱いで拾う。
    bare = {}
    for d in defined:
        bare.setdefault(d.split()[-1], []).append(d)
    try:
        ref_re = re.compile(cfg["decision_ref_pattern"])
    except re.error as exc:
        out.append(Finding("decision-ref", "error", "<config>", 1,
                           f"decision_ref_pattern が不正: {exc}"))
        return
    for r in cfg["decision_ref_docs"]:
        rlines = read(root, r)
        if rlines is None:
            out.append(Finding("decision-ref", "error", r, 1,
                               "decision_ref_docs の文書が存在しない"))
            continue
        for i, line in enumerate(rlines, 1):
            for m in ref_re.finditer(line):
                ref = m.group(1).strip()
                if ref in defined:
                    continue
                if " " not in ref:
                    # 修飾のない裸参照は docs-creator の lint 規則 bare-decision-id が
                    # 担当する。ここで二重に鳴らすと本規則の信号が埋もれる
                    continue
                same_num = bare.get(ref.split()[-1])
                if same_num:
                    out.append(Finding(
                        "decision-ref", "warn", r, i,
                        f"決定 `{ref}` は番号だけ一致し、修飾が {rel} の定義"
                        f"（{'／'.join(same_num)}）と違う。完全修飾で参照する", line))
                else:
                    out.append(Finding(
                        "decision-ref", "warn", r, i,
                        f"決定 `{ref}` が {rel} に見つからない。"
                        f"採番予約だけで起票していないか、参照の綴りを確認する", line))


DOC_RULES = [rule_wp_status_cross_doc, rule_git_current_facts,
             rule_open_evidence, rule_decision_ref]


def rule_name(fn) -> str:
    return fn.__name__[len("rule_"):].replace("_", "-")


KNOWN_RULES = [rule_name(f) for f in DOC_RULES]


def validate_keys(user: dict, known_rules) -> None:
    """未知の設定キー・rule 名を拒否する。

    打ち間違いが黙って既定値へ落ちると、PASS を信用できなくなる。
    """
    unknown = sorted(k for k in user if not k.startswith("_") and k not in DEFAULT_CONFIG)
    if unknown:
        raise ConfigError(f"未知の設定キー: {', '.join(unknown)}\n"
                          f"       使えるのは: {', '.join(sorted(DEFAULT_CONFIG))}")
    bad = sorted(r for r in (user.get("rules") or {})
                 if not r.startswith("_") and r not in known_rules)
    if bad:
        raise ConfigError(f"rules に未知の rule 名: {', '.join(bad)}\n"
                          f"       使えるのは: {', '.join(known_rules)}")


def load_config(path: Path | None, explicit: bool, prefix: str) -> dict:
    cfg = dict(DEFAULT_CONFIG)
    if path is not None and path.is_file():
        try:
            user = strict_json_loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            raise ConfigError(f"設定 JSON を解析できない: {path}: {exc}") from exc
        if not isinstance(user, dict):
            raise ConfigError(f"設定は object でなければならない: {path}")
        validate_keys(user, KNOWN_RULES)
        cfg.update({k: v for k, v in user.items() if not k.startswith("_")})
    elif explicit:
        raise ConfigError(f"--config が指す設定が存在しない: {path}")

    def expand(v):
        if isinstance(v, str):
            return v.replace("{PREFIX}", prefix)
        if isinstance(v, list):
            return [expand(x) for x in v]
        return v

    return {k: expand(v) for k, v in cfg.items()}


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--project-root", type=Path, default=Path.cwd())
    ap.add_argument("--prefix", default="", help="文書名の PREFIX（{PREFIX} を置換）")
    ap.add_argument("--config", type=Path, default=None)
    ap.add_argument(
        "--git-executable", type=Path, default=None,
        help="absolute pinned Git executable; required when git-current-facts is enabled")
    ap.add_argument("--only", nargs="+", default=None,
                    help=f"実行する rule 名。選べるのは: {', '.join(KNOWN_RULES)}")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--strict", action="store_true",
                    help="warning または未検査 note が1件でもあれば gate を失敗させる")
    ap.add_argument("--list-rules", action="store_true")
    args = ap.parse_args()

    if args.list_rules:
        print("\n".join(KNOWN_RULES))
        return 0

    root = args.project_root.resolve()
    if not root.is_dir():
        print(f"ERROR: --project-root が存在しない: {root}", file=sys.stderr)
        return 2

    explicit = args.config is not None
    cfg_path = (args.config if args.config is None or args.config.is_absolute()
                else root / args.config)
    if cfg_path is None:
        cfg_path = root / ".claude" / "p0-check.json"
    try:
        cfg = load_config(cfg_path, explicit, args.prefix)
    except ConfigError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    if not isinstance(cfg.get("strict"), bool):
        print("ERROR: strict は boolean でなければならない", file=sys.stderr)
        return 2
    strict = args.strict or cfg["strict"]

    if args.only:
        unknown = [r for r in args.only if r not in KNOWN_RULES]
        if unknown:
            print(f"ERROR: 未知の rule 名: {', '.join(unknown)}\n"
                  f"       選べるのは: {', '.join(KNOWN_RULES)}", file=sys.stderr)
            return 2

    # 走査対象や語彙を空にすると、ループが0回で回り「検査したが問題なし」と
    # 見分けが付かない PASS になる。空にできる設定と、空だと検査が成立しない設定を
    # 分けて、後者は設定不備として落とす（fail-closed）
    disabled = {k for k, v in cfg["rules"].items() if v is False}
    git_enabled = "git-current-facts" not in disabled \
        and (not args.only or "git-current-facts" in args.only)
    if git_enabled:
        if args.git_executable is None or not args.git_executable.is_absolute():
            print("ERROR: git-current-facts requires absolute --git-executable; "
                  "ambient PATH lookup is forbidden", file=sys.stderr)
            return 2
        try:
            git_executable = args.git_executable.resolve(strict=True)
        except OSError as exc:
            print(f"ERROR: --git-executable cannot be resolved: {exc}", file=sys.stderr)
            return 2
        if not git_executable.is_file():
            print("ERROR: --git-executable must resolve to a file", file=sys.stderr)
            return 2
        cfg["_git_executable"] = git_executable
    required_nonempty = {
        "wp_status_mirrors": ("wp-status-cross-doc", "突合先が無い"),
        "status_vocabulary": ("wp-status-cross-doc",
                              "Status の語彙が無く、どの値も照合対象にならない"),
        "git_fact_docs": ("git-current-facts", "走査先が無い"),
    }
    for key, (owner_rule, why) in required_nonempty.items():
        # 明示的に無効化した rule の設定までは求めない。無効化は意図の表明であり、
        # そこまで拒否すると「検査しない」という選択が取れなくなる
        if owner_rule in disabled or (args.only and owner_rule not in args.only):
            continue
        if not cfg[key]:
            print(f"ERROR: {key} が空だが {owner_rule} は有効。{why}。"
                  f"検査しないなら rules で {owner_rule} を明示的に false にする",
                  file=sys.stderr)
            return 2

    notes = []
    if ("open-evidence" not in disabled
            and (not args.only or "open-evidence" in args.only)
            and not cfg["open_docs"]):
        notes.append("open_docs が未設定のため open-evidence は無効")
    if ("decision-ref" not in disabled
            and (not args.only or "decision-ref" in args.only)
            and not cfg["decision_ref_docs"]):
        notes.append("decision_ref_docs が未設定のため decision-ref は無効")

    findings: list[Finding] = []
    executed = []
    for fn in DOC_RULES:
        name = rule_name(fn)
        if name in disabled or (args.only and name not in args.only):
            continue
        executed.append(name)
        fn(root, cfg, findings)

    if not executed:
        print("ERROR: 実行された rule が0件。--only または rules 設定を確認する",
              file=sys.stderr)
        return 2

    findings.sort(key=lambda f: (SEVERITY_ORDER[f.severity], f.path, f.line))
    errors = sum(1 for f in findings if f.severity == "error")
    warns = len(findings) - errors
    gate_pass = errors == 0 and (not strict or (warns == 0 and not notes))

    if args.json:
        print(json.dumps({"pass": gate_pass, "strict": strict,
                          "rules": executed, "notes": notes,
                          "error": errors, "warn": warns,
                          "findings": [f.as_dict() for f in findings]},
                         ensure_ascii=False, indent=2))
    else:
        for f in findings:
            print(f"{f.severity.upper():5} [{f.rule}] {f.path}:{f.line}  {f.message}")
            if f.excerpt:
                print(f"        | {f.excerpt}")
        for n in notes:
            print(f"note  {n}")
        head = "PASS" if gate_pass else "FAIL"
        print(f"\n{head}  rule {len(executed)} / error {errors} / warn {warns}")

    return 0 if gate_pass else 1


if __name__ == "__main__":
    sys.exit(main())
