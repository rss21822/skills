# Handoff {ID} — {対象ファイル} の新規作成

| 項目 | 値 |
|---|---|
| handoffId | `{ID}` |
| phase | {D2/D3 等}。{直前までの承認状況と照合巡数} |
| baseline | commit `{hash}`、または commit 未許可時の snapshot `{path}` と sha256 ＋ 承認済み文書（{名前} `{sha256 先頭8}` / …） |
| 執筆言語 | 通常の日本語。状態タグ・ID・schema キーは英語 |

## objective

観測可能な形で列挙する。「〜を考慮する」ではなく「〜が記載されている」「〜が実行できる」。

1. `{path}` が新規作成されている
2. ヘッダ完備（`{DOC-ID}` / 0.1.0 / **Draft**）
3. テンプレート `{template}` 全セクション充足または `[OPEN]`
4. トリガ行最小内容: {trigger-matrix が要求する項目を列挙}
5. {所有境界の宣言。この文書が所有するもの／参照に留めるものを明示}
6. {上流の消費者契約。昇格禁止を明記}
7. 新規数値なし（または採用可の承認済み値を明示列挙）
8. `validate_docs.py --gate {gate}` 出力添付

## inScope

主対象と、常設条項が必要とする付随更新を**明示列挙**する。列挙しないと「他はすべて
outOfScope」と「前方参照を登録せよ／consumer 側の受信契約も書け」が両立せず、
執筆モデルはどちらを守っても違反する。

- `{path}`（新規作成のみ）
- `.claude/doc-lint.json`（前方参照・契約の登録が生じた場合の当該エントリのみ）
- `{consumer 文書があれば列挙}`（通知・イベント・gate を定義する場合の受信契約）

付随更新が不要と分かっているなら、その行を削って「主対象のみ」と明記する。
横断更新が大きくなるなら、本 handoff は主対象に絞り、別 handoff として発行する。

## outOfScope

- 上に列挙していないすべて。scope 判定は「執筆モデルが変更したか」のみ。ユーザーの並行編集は報告のみで BLOCKED にしない

## requirements（この順で読む）

1. {上流正本と該当節。読む順序が意味を持つので番号を振る}
2. …
3. 規約: {template}、document-system.md、trigger-matrix.md

## dataIds

**新規数値の創作は全面禁止。** 記載可能な実値は {確定済み値のリスト、または「なし」}。それ以外は key ＋ 確定プロセス（実測 → 判定 → 当該 Spec 改訂）で構造化する。

実測由来の値を書く場合は **evidence パスを添える**。値だけを転記して出所を書かないと、再計測したときにどちらが新しいか分からなくなる。

## 重要な区別（常設）

- **配達先 ≠ 数値所有先 ≠ 判断所有先。** 値を届ける先と、値を決める文書は別
- **`[DECISION]` には出所と人間承認記録が要る**（`J` は承認済みの指示役提案）。出所か承認記録が無ければ `[PROPOSAL]`。上流の `[PROPOSAL]` を昇格しない
- 決定 ID は完全修飾（裸の `D-n` 禁止。`GDD D-9` と `Feasibility FR-2.6 D-9` は別物）
- 裸 `[OPEN]` 禁止（`blocking: yes|no` 併記が必須）
- 陳腐化する前提句を使わない。「{文書} が未作成のため」ではなく実体条件（値・runner・evidence の未登録）で理由を書く
- 前方参照する場合は `.claude/doc-lint.json` の `forward_refs` へ登録する
- 通知・イベント・gate を定義したら、consumer 側の受信契約まで同じ handoff で書く
- **`[HUMAN]`はhuman-only。** `HUMAN_ACTIONS.md`へclosure evidenceつきで登録する。AI実行可能な機械作業は`[AI-ACTION]`として`AI_ACTIONS.md`へ分離する

## 報告の誠実性（必須）

実施していない検証を報告に書かない。「独立照合」「別セッション」等の語（変形を含む）を自己検証の名称に使わない。sha256 は実際に計算した値のみ記載する。

## acceptance

1. objective 充足
2. 指示側の機械検査（lint_docs.py ＋ validator ＋ sha256 ＋ scope）
3. Class Aの別セッション独立照合 1巡以上でCritical 0 / Major 0。Class B supplemental reviewは代替不可

## commands

読み取り系すべて。project cwdから、実在確認済みinterpreter（Windows: `python`、fallback `py -3`）とvalidatorの解決済み絶対pathを使う:
`{PYTHON_EXE} "{VALIDATOR_ABS}" --project-root . --prefix {PREFIX} --gate {gate}`

## execution

worker `{worker}` / class `{A|B}` / role `{architect named role}`

- requested: model `{model}` / effort `{effort}` / version `{exact version}` / sandbox `{mode}` / network `{bool}`
- `transferApproval`: approvalId / provider / endpoint / account / authChannel / allowedPaths+sha256 / deniedPatterns / request+response byte limits / cost cap
- class B: `contextBundle` path+bytes+sha256、rawOutput、expected artifact path/count、`responseEnvelope`必須
- completion: `executionAttestation`にresolved model/version/effort/sandbox/network、request/context/response hash、finish reason、usage、exit code

詳細は`references/execution-envelope.md`。requested値だけ、暗黙default、finish reason欠落はhandoff不合格。

## evidence

作成パス / artifact hash / execution attestation / タグ集計 / **出所内訳（U/W/M/J、未承認`[DECISION]`位置）** / 記載数値一覧 / 新設`[HUMAN]`と`[AI-ACTION]`の別台帳 / validator生出力 / 自己実行検証のみ

## rollback

inScope に列挙したものをすべて戻す。主対象の削除だけでは、契約登録や consumer 側の
更新が残留する。

- `{path}` を削除
- `.claude/doc-lint.json` へ追加したエントリを削除
- `{consumer 文書}` は事前スナップショットから復元
