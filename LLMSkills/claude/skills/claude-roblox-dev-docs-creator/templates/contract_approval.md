# Handoff {ID} — {P0契約} の承認と {P0管理WP} の Verified 遷移

> **これは差分雛形。** 基本の必須項目（`objective`／`dataIds`／`acceptance`／`commands`／`execution`／`rollback` と常設条項）は `claude-roblox-dev-docs-creator` の `templates/handoff.md` が正本。そちらを土台にして本書の P0 固有部分を重ねる。本書だけで発行すると必須項目が欠ける。

| 項目 | 値 |
|---|---|
| handoffId | `{ID}` |
| P0 start approval | `{P0_START_APPROVAL_ID}` / machine record `{path}` / sha256 `{hash}` |
| P0 contract approval | `{P0_CONTRACT_APPROVAL_ID}`（本便。P0 start ID、D5 IDと別） |
| approved P0 closure inventory | B0 historical `PROGRESS.md` / `## Proposed P0 closure inventory` / `{inventory ID}` / file sha256 `{hash}`（P0 start scopeとexact一致） |
| input baseline | `B0-{ID}` / manifest `{path}` / sha256 `{hash}` / fileSetSha256 `{hash}` |
| candidate output target | preallocated `P0-CAND-{ID}` / manifest `{path}`（outer sha256 / fileSetSha256はstep 5の出力。入力として要求しない） |
| machine approval record output | `{path}`（`gate_approval_record.schema.json`, type `p0-contract`） |
| rollback/source revision | commit `{hash}`（今回のcommit許可あり）／snapshot `{manifest path}`・manifest sha256 `{hash}`・raw git status `{path}`（commit未許可） |
| 承認 | **{人間本人の直接承認 `[DECISION]`／{委任決定 ID}に基づくAIの `[AI-APPROVED]`}。{日付}。** 前提: {対象 open} はすべてclosure済み（{どの便で}）。照合記録 {path} が前提成立を確認済み |

## 1. 指示

1. **判断材料を実測で検証してから承認を記録する。** B0 historical `PROGRESS.md` inventory全IDと、P0-CAND用staging `PROGRESS.md`の`Completed` closure evidence/affected canonical docsを**自分で再計算**する。stagingの`## Proposed P0 closure inventory` data row、inventory外のproposal/blocking open/unverified assumptionがともに0で、全B0 item IDが閉じたことを確認する。**1つでも不成立なら承認を記録せず BLOCKED で止まる**
2. 成立した場合、既存の承認入力（人間の直接承認、または委任元 `[DECISION]` と委任範囲）を検証し、private stagingへ次の最終metadataだけを適用する。machine recordの予定pathを先に固定し、`DECISIONS.md` にはpathだけを書く（record hashやcandidate manifest hashを相互参照させない）:
   - 人間本人の直接承認なら `[DECISION]`、委任AIなら `[AI-APPROVED]` とし委任元の人間 `[DECISION]` を参照する
   - 承認記録表へ承認日／承認種別／実行者／対象versionを記録する
   - 人間直接承認だけ、{範囲} の該当項目を `[PROPOSAL]` から `[DECISION]` へ改める。委任AIは `[AI-APPROVED]` とし `[DECISION]` へ改めない
   - formal documentヘッダの `Status`／`Last approved` は変更しない。D5でだけ遷移する
   - {閉じてはならない open} は維持
3. **{WP-P0-* または明示されたP0管理WP} の Verified 遷移**: 製品実装WPではないことを確認し、staging上で遷移条件を1件ずつ検証する
   - {条件1} → {既に成立している根拠}
   - {条件2} → 本便で成立
   - {条件3: Done definition} → **実測する**。validator を実行し、build を含むなら**追跡ファイルを上書きしない一時出力先**で走らせる
   - 全件成立したら Status を index・詳細節とも遷移させる。**1件でも不成立なら Status を変えず内訳を報告して BLOCKED**
4. **記録同期**: P0作業中に作成・評価した代替案と決定を`DECISIONS.md`へ、B0 inventory各IDのactual closure evidence/affected-doc hashesをstaging `PROGRESS.md`の`Completed`へ反映し、inventory data rowを0にする。さらにCurrent handoff、`[FACT]`、Next authorized actionと`CHANGELOG.md`を同期する。B0 historical bytesは変更しない
5. stagingの最終canonical file setをimmutable `P0-CAND-*` snapshot/commitとして固定し、manifest outer hashと`fileSetSha256`を計算する。candidate manifest自身とgate recordはcandidate `files`へ含めない
6. `gate_approval_record.schema.json` に従うtype `p0-contract` machine recordを作り、手順5のcandidate ID/path/outer hash/`fileSetSha256`/revisionへ束縛する。schema・hash・allowlistを再検証してから、candidate snapshot/manifest、machine record、canonical metadataをrollback可能な一単位で反映する。失敗時は全対象を反映前bytesへ戻す
7. Next authorized actionを `post-P0 D4 3系統再監査` とする。3系統Critical 0 / Major 0、candidateからB1への同一fileSet昇格が完了するまで `D5承認準備完了` と書かない。実装開始可能とは書かない

## 2. 制約

- **検証を省略して承認・遷移を記録しない。** 実測がすべて先
- {不変対象} を変更しない（sha256 で証明）
- `src/` 等を作成しない。dry run の出力は一時領域のみ
- 裸 `[OPEN]` 禁止。決定 ID 完全修飾。決定内容を他文書へ複製しない
- `[HUMAN]` をAI実行候補にせず、AI実行可能なものは `[AI-ACTION]` とする
- **「照合の承認可」「P0管理WPのVerified」「P0契約承認」「人間D5承認」を別の事象として書き分ける**
- P0開始・P0契約・D5の各approval IDとmachine recordを別々に保持する。ID再利用禁止
- 実施していない検証を書かない。handoff workerによるcommit・push禁止

## 3. 報告

判断材料と遷移条件の**実測結果（実行 command と出力）**、変更前後 sha256、`git status --short`、validator と lint の実出力（baseline 悪化不可）、遷移後の index・詳細節の行。
