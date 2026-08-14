# Handoff {ID} — {契約} の承認と {WP} の Verified 遷移

> **これは差分雛形。** 基本の必須項目（`objective`／`dataIds`／`acceptance`／`commands`／`execution`／`rollback` と常設条項）は `claude-roblox-dev-docs-creator` の `templates/handoff.md` が正本。そちらを土台にして本書の P0 固有部分を重ねる。本書だけで発行すると必須項目が欠ける。

| 項目 | 値 |
|---|---|
| handoffId | `{ID}` |
| baseline | commit `{hash}` |
| 承認 | **{承認者。`[HUMAN]` Project Owner が直接承認した場合はその旨。委任下なら「{委任決定 ID} の委任に基づき AI が承認した」}。{日付}。** 前提: {対象 open} はすべて closure 済み（{どの便で}）。照合記録 {path} が前提成立を確認済み |

## 1. 指示

1. **判断材料を実測で検証してから承認を記録する。** {正本の節} が定める判断材料を**自分で再計算**し、**1つでも不成立なら承認を記録せず BLOCKED で止まる**
2. 成立した場合、{正本} へ承認を記録する:
   - 承認記録表へ 承認日／承認者（「{委任決定 ID} に基づき委任された AI（{新決定 ID} 参照）」）／対象 version
   - ヘッダの `Last approved` を更新
   - **{範囲} の該当項目の `[PROPOSAL]` を `[DECISION]` へ改める**（範囲外は `[PROPOSAL]` のまま）
   - {閉じてはならない open} は維持
3. **`DECISIONS.md`**: 決定を追加。**判断材料の検証結果（実測値）**、承認者、対象範囲・version を記載
4. **{WP} の Verified 遷移**: 遷移条件を1件ずつ検証する
   - {条件1} → {既に成立している根拠}
   - {条件2} → 本便で成立
   - {条件3: Done definition} → **実測する**。validator を実行し、build を含むなら**追跡ファイルを上書きしない一時出力先**で走らせる
   - 全件成立したら Status を index・詳細節とも遷移させる。**1件でも不成立なら Status を変えず内訳を報告して BLOCKED**
5. **記録同期**: `PROGRESS.md`（Current handoff、`[FACT]`、Next authorized action）／`CHANGELOG.md`

## 2. 制約

- **検証を省略して承認・遷移を記録しない。** 実測がすべて先
- {不変対象} を変更しない（sha256 で証明）
- `src/` 等を作成しない。dry run の出力は一時領域のみ
- 裸 `[OPEN]` 禁止。決定 ID 完全修飾。決定内容を他文書へ複製しない
- **「照合の承認可」「WP の Verified」「承認」を別の事象として書き分ける**
- 実施していない検証を書かない。commit・push 禁止

## 3. 報告

判断材料と遷移条件の**実測結果（実行 command と出力）**、変更前後 sha256、`git status --short`、validator と lint の実出力（baseline 悪化不可）、遷移後の index・詳細節の行。
