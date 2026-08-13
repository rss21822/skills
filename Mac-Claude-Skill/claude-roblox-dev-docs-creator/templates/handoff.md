# Handoff {ID} — {対象ファイル} の新規作成

| 項目 | 値 |
|---|---|
| handoffId | `{ID}` |
| phase | {D2/D3 等}。{直前までの承認状況と照合巡数} |
| baseline | commit `{hash}` ＋ 承認済み文書（{名前} `{sha256 先頭8}` / …） |
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

**新規数値の創作は全面禁止。** 記載可能な実値は {承認済み値のリスト、または「なし」}。それ以外は key ＋ 確定プロセス（実測 → Owner 承認 → 当該 Spec 改訂）で構造化する。

## 重要な区別（常設）

- **配達先 ≠ 数値所有先 ≠ 判断所有先。** 値を届ける先と、値を決める文書は別
- `[DECISION]` は人間承認記録のみ。上流の `[PROPOSAL]` を昇格しない
- 決定 ID は完全修飾（裸の `D-n` 禁止。`GDD D-9` と `Feasibility FR-2.6 D-9` は別物）
- 裸 `[OPEN]` 禁止（`blocking: yes|no` 併記が必須）
- 陳腐化する前提句を使わない。「{文書} が未作成のため」ではなく実体条件（値・runner・evidence の未登録）で理由を書く
- 前方参照する場合は `.claude/doc-lint.json` の `forward_refs` へ登録する
- 通知・イベント・gate を定義したら、consumer 側の受信契約まで同じ handoff で書く

## 報告の誠実性（必須）

実施していない検証を報告に書かない。「独立照合」「別セッション」等の語（変形を含む）を自己検証の名称に使わない。sha256 は実際に計算した値のみ記載する。

## acceptance

1. objective 充足
2. 指示側の機械検査（lint_docs.py ＋ validator ＋ sha256 ＋ scope）
3. 別セッション独立照合 1 巡以上で Major 0

## commands

読み取り系すべて / `python3 {validator} --project-root . --prefix {PREFIX} --gate {gate}`

## execution

model `{model}` / reasoningEffort `high` / sandbox `workspace-write` / approvalPolicy `never` / network `false`

## evidence

作成パス / タグ集計 / 記載数値一覧 / validator 出力 / 自己実行検証のみ

## rollback

inScope に列挙したものをすべて戻す。主対象の削除だけでは、契約登録や consumer 側の
更新が残留する。

- `{path}` を削除
- `.claude/doc-lint.json` へ追加したエントリを削除
- `{consumer 文書}` は事前スナップショットから復元
