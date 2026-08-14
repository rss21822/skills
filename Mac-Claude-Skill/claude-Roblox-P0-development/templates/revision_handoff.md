# Handoff {ID} — {CR-ID} 承認内容の実改訂（{open closure まで／改訂のみ}）

> **これは差分雛形。** 基本の必須項目（`objective`／`dataIds`／`acceptance`／`commands`／`execution`／`rollback` と常設条項）は `claude-roblox-dev-docs-creator` の `templates/handoff.md` が正本。そちらを土台にして本書の P0 固有部分を重ねる。本書だけで発行すると必須項目が欠ける。

| 項目 | 値 |
|---|---|
| handoffId | `{ID}` |
| baseline | commit `{hash}` |
| baseline sha256 | {改訂対象と**不変対象**の sha256 を列挙} |
| 承認根拠 | `DECISIONS.md` の {決定 ID}。**選択内訳を本 handoff へ複製しない。** 作業前に決定と CR §{改訂 inventory の節} を読む |

## 0. 目的

{決定} に基づき {正本} を実改訂し、{対象 open} を closure evidence どおりに閉じる。**{閉じてはならない open} は閉じない**（理由: {条件が未成立の内訳}）。

## 1. 正本の改訂

CR §{inventory の節} どおりに実施する。**`Create` の追加だけでなく、inventory が挙げる全欄**（`Objective`／`Public interfaces`／`Automatic tests` 等）を同時に改訂する。

1. {WP と欄}
2. …
3. **索引と詳細節を同時に更新する**（片側更新は跨文書不一致の原因）
4. version と Change history を更新する

## 2. open の closure

**一致確認（§3）が成立した後に**閉じる。closure evidence の項番ごとに、何がどこで成立したかを record へ書く（日付・決定 ID・実測値）。**この closure が何を意味しないか**も併記する。

## 3. 一致確認（実施して報告に含める）

1. {論理側と物理側の全件対応。差集合 0 を自分で再計算}
2. {担当欄との一致}
3. 索引と詳細節の一致（`check_p0_state.py` と lint が 0 件）

## 4. してはならないこと

- {不変対象の文書} を**1バイトも変更しない**（sha256 で証明）
- `src/`・`projects/`・`config/`・`contracts/`・`tests/` を作成しない
- 新規の値を創作しない。値は所有 Spec の ID 参照のみ
- **inventory 外の改善を実装しない**（別 CR へ送る）
- 裸 `[OPEN]` 禁止。決定 ID 完全修飾。**承認内訳を正本へ複製しない**（決定への参照で表す）
- {閉じてはならない open} を閉じない
- {状態遷移は次便} — 本便で Status を変えない

## 5. inScope

{**変更対象の値の正本ファイルをすべて列挙する。** 「Status を更新せよ」と書いたなら Status の正本を必ず含める}

## 6. 報告

変更前後 sha256（**不変対象を含む**）、`git status --short`・`git diff --stat`、一致確認の実測結果、validator と lint の実出力（baseline 悪化不可）。BLOCKED 時は理由を書いて止まる。
