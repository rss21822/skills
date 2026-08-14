# Handoff {ID} — GDD の新規作成（D1）

通常の文書 handoff（`handoff.md`）との違いは、**内容の所有者が人間である**こと。執筆モデルは intake の回答を構成するだけで、製品判断を作らない。この境界が崩れると、人間が一度も決めていない方針が正本になり、下流の約30文書がそれを前提に完成した後で発覚する。

| 項目 | 値 |
|---|---|
| handoffId | `{ID}` |
| phase | D1（GDD 起草）。D0 intake は {日付} に完了。未回答項目は `[PROPOSAL]` として提示済み |
| baseline | commit `{hash}`。既存資料（{ファイル名} `{sha256 先頭8}` / …） |
| 執筆言語 | 通常の日本語。状態タグ・ID・schema キーは英語 |

## objective

1. `docs/{PREFIX}_gdd.md` が新規作成されている
2. ヘッダ完備（`{DOC-ID}` / 0.1.0 / **Draft**）
3. **architect skill の GDD テンプレートと D1 必須条件をすべて充足している**（条件の内容は architect が正本。本 handoff へ書き写さない。執筆前に architect の GDD template・`quality-gates.md` の Gate 1・`workflow.md` の D1 を読むこと）
4. **決定 ID の参照規約が冒頭に明記されている**（下記「決定 ID の参照規約」参照）
5. **成功指標の可変閾値を本文に確定していない**（key と判定規則のみ。製品意図としての記述は対象外）
6. D1.5 Feasibility trigger に該当する機能が列挙され、各々が踏む trigger 名が書かれている
7. 本文で新設した `[HUMAN]` 専権作業が `HUMAN_ACTIONS.md` へ登録されている
8. `.claude/doc-lint.json` の `decision_id_home_docs` へ本書が登録されている
9. `validate_docs.py --gate D1` 出力添付

## 決定 ID の参照規約（最優先。ここを外すと全文書の是正になる）

**ID の形式は architect skill が正本**（`D-{NNN}` / `F-{NNN}`）。本 handoff は形式を変えず、**参照の書き方**だけを規約化する。

- 本書が採番する決定は `D-{NNN}` / `F-{NNN}`
- **他文書の決定を参照するときは完全修飾する。** 裸の `D-9` を書かず `GDD D-9` / `Feasibility FR-2.6 D-9` のように所有文書（必要なら節）を伴わせる
- **独自の `D-n` 系列を持つ文書を GDD 冒頭で列挙する。** 名前空間が複数あること自体は問題なく、裸参照が問題である
- 実プロジェクトで `D-9` が GDD・Feasibility・gate 閾値提案の3つの別物を指し、裸参照33件が最終監査まで残って人間の決裁事項へ回った

## inScope

- `docs/{PREFIX}_gdd.md`（新規作成）
- `HUMAN_ACTIONS.md`（本文で新設した `[HUMAN]` 作業の登録のみ）
- `.claude/doc-lint.json`（`decision_id_home_docs` への本書の登録のみ）
- `DECISIONS.md`（intake で確定した `[DECISION]` の記録）

## outOfScope

- 上に列挙していないすべて
- **下流文書（detailed_design、各 Spec、data_definition、work_packages 等）**。architect の絶対規則は「人間承認前に下流仕様を**確定しない**」。本 handoff はそれに加えて、運行判断として**執筆自体を承認後まで待つ**（承認で方針が変われば書いた分が全部是正対象になるため）
- scope 判定は「執筆モデルが変更したか」のみ。ユーザーの並行編集は報告のみで BLOCKED にしない

## requirements（この順で読む）

1. D0 intake の成果物（`{intake ファイルのパス}` sha256 `{先頭8}`）。**会話ログだけを根拠にしない。** どの回答に基づく記述かを後から復元できなくなる
2. 既存資料（{あれば列挙}）
3. 規約: architect skill の GDD テンプレート、`document-system.md`、`trigger-matrix.md`
4. 本 Skill の `references/gdd-and-intake.md`

## 製品判断の扱い（本 handoff の中核）

**intake の回答にない製品判断を作らない。** 判断が必要な箇所に遭遇したら、次のいずれかにする。

1. intake の回答から導出できるなら導出し、導出の根拠を書く
2. 導出できないなら `[PROPOSAL]` marker つきで提案を書き、**未確認であることが読んで分かる形にする**
3. 提案すら根拠がないなら `[OPEN blocking: yes|no]` として理由・closure evidence・Owner を書く

**`[PROPOSAL]` を `[DECISION]` へ昇格しない。** 昇格は人間承認の記録があるものだけ。

既存資料がある場合、**用語・構成・判断を無断で置換しない**。改善提案は本文へ混ぜず、別立ての `[PROPOSAL]` 節にする。

## 数値の扱い（通常 handoff の `dataIds` に相当）

data_definition がまだ存在しないため、参照すべき DATA ID の一覧を渡せない。代わりに本節が数値の扱いを規定する。

**成功指標の可変閾値を GDD に確定しない。** GDD が持つのは「何を測るか」と「どうなったら合格・不合格か」まで。バランス調整で動く値・分母規則・計算式・単位は data_definition が所有する。

対象は**可変閾値**であり、GDD が書く数値すべてではない。製品意図としての記述（想定ラウンド時間、対象端末の優先度など）は GDD が持ってよい。判断基準は「バランス調整で動く値か」。

data_definition はこの時点で存在しないので、GDD には**指標の key と、値は data_definition の DATA ID を参照する旨**を書く。

理由句は実体条件で書く。「data_definition が未作成のため」は data_definition ができた瞬間に嘘になる。「当該指標の canonical 値が未登録のため（closure: data_definition へ登録され Owner 承認されたとき）」と書く。

## 重要な区別（常設）

- **配達先 ≠ 数値所有先 ≠ 判断所有先**
- `[DECISION]` は人間承認記録のみ
- 他文書の決定 ID を参照するときは完全修飾（上記「決定 ID の参照規約」）
- 裸 `[OPEN]` 禁止（`blocking: yes|no` 併記が必須）
- 陳腐化する前提句を使わない。実体条件で理由を書く
- 本文で `[HUMAN]` 専権作業を新設したら、同じ handoff で台帳へ登録する

## 報告の誠実性（必須）

実施していない検証を報告に書かない。「独立照合」「別セッション」等の語（変形を含む）を自己検証の名称に使わない。sha256 は実際に計算した値のみ記載する。

## acceptance

1. objective 充足
2. 指示側の機械検査（lint_docs.py ＋ validator ＋ sha256 ＋ scope）
3. 別セッション独立照合 1 巡以上で Major 0
4. **`[PROPOSAL]` の残数と位置が一覧化されている**（人間承認ゲートで潰す対象になるため）

## commands

読み取り系すべて / `python3 {validator} --project-root . --prefix {PREFIX} --gate D1`

## execution

model `{model}` / reasoningEffort `high` / sandbox `workspace-write` / approvalPolicy `never` / network `false`

## evidence

作成パス / タグ集計（特に `[PROPOSAL]` と `[OPEN]` の件数と位置）/ Non-Goals の件数と各々の理由の有無 / 記載数値一覧（各々について、可変閾値か製品意図かの区別を付す。可変閾値は原則ゼロ件）/ validator 出力 / 自己実行検証のみ

## rollback

- `docs/{PREFIX}_gdd.md` を削除
- `HUMAN_ACTIONS.md` へ追加した行を削除
- `.claude/doc-lint.json` へ追加したエントリを削除
- `DECISIONS.md` へ追加した行を削除

## 承認ゲート（この handoff の完了後）

**GDD は独立照合の承認可では確定しない。** `[HUMAN]` Project Owner のチャットでの明示承認が要る。**承認条件は architect の Gate 1 と workflow D1 が正本**であり、ここへ書き写さない。承認判断の前に architect 側を読むこと。

承認を得たら `DECISIONS.md` へ日付つきで記録する。**「異論が出なかったので承認とみなす」をやらない。**
