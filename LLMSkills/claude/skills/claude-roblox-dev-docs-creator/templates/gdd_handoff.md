# Handoff {ID} — GDD の新規作成（D1）

通常の文書 handoff（`handoff.md`）との違いは、**内容が上流から導出できない**こと。執筆モデルは intake の回答を構成するだけで、製品判断を作らない。この境界が崩れると、誰も根拠を持たない方針が正本になり、下流の約30文書がそれを前提に完成した後で発覚する。

**指示役は intake を事前記入する。** 回答には出所（`U`/`W`/`M`/`J`）が付き、architect の D0 停止条件は使用者が確認済みであること。執筆モデルは**出所と承認状態を保ったまま構成する**のであって、出所のない判断を足したり、未承認案を決定へ昇格したりしない。

| 項目 | 値 |
|---|---|
| handoffId | `{ID}` |
| phase | D1（GDD 起草）。D0 intake は {日付} に使用者確認済み。出所内訳 U {n} / W {n} / M {n} / J {n} |
| baseline | commit `{hash}`、または commit 未許可時の snapshot `{path}` と sha256。既存資料（{ファイル名} `{sha256 先頭8}` / …） |
| 執筆言語 | 通常の日本語。状態タグ・ID・schema キーは英語 |

## objective

1. `docs/{PREFIX}_gdd.md` が新規作成されている
2. ヘッダ完備（`{DOC-ID}` / 0.1.0 / **Draft**）
3. **architect skill の GDD テンプレートと D1 必須条件をすべて充足している**（条件の内容は architect が正本。本 handoff へ書き写さない。執筆前に architect の GDD template・`quality-gates.md` の Gate 1・`workflow.md` の D1 を読むこと）
4. **決定 ID の参照規約が冒頭に明記されている**（下記「決定 ID の参照規約」参照）
5. **各 `[DECISION]` に出所と人間承認記録が付いている**（下記「製品判断の扱い」参照）
6. **成功指標の可変閾値を本文に確定していない**（key と判定規則のみ。製品意図としての記述は対象外）
7. D1.5 Feasibility trigger に該当する機能が列挙され、各々が踏む trigger 名が書かれている
8. 本文で新設した`[HUMAN]`がhuman-onlyとして`HUMAN_ACTIONS.md`へ、機械作業が`[AI-ACTION]`として`AI_ACTIONS.md`へ分離登録されている
9. `.claude/doc-lint.json` の `decision_id_home_docs` へ本書が登録されている
10. `validate_docs.py --gate D1` 出力添付

## 決定 ID の参照規約（最優先。ここを外すと全文書の是正になる）

**ID の形式は architect skill が正本**（`D-{NNN}` / `F-{NNN}`）。本 handoff は形式を変えず、**参照の書き方**だけを規約化する。

- 本書が採番する決定は `D-{NNN}` / `F-{NNN}`
- **他文書の決定を参照するときは完全修飾する。** 裸の `D-9` を書かず `GDD D-9` / `Feasibility FR-2.6 D-9` のように所有文書（必要なら節）を伴わせる
- **独自の `D-n` 系列を持つ文書を GDD 冒頭で列挙する。** 名前空間が複数あること自体は問題なく、裸参照が問題である
- 実プロジェクトで `D-9` が GDD・Feasibility・gate 閾値提案の3つの別物を指し、裸参照33件が最終監査まで残った

## inScope

- `docs/{PREFIX}_gdd.md`（新規作成）
- `HUMAN_ACTIONS.md`（human-only作業のみ）
- `AI_ACTIONS.md`（AI実行可能な機械作業のみ）
- `.claude/doc-lint.json`（`decision_id_home_docs` への本書の登録のみ）
- `DECISIONS.md`（intake で使用者が確認した `[DECISION]` の記録。承認者・出所つき）

## outOfScope

- 上に列挙していないすべて
- **下流文書（detailed_design、各 Spec、data_definition、work_packages 等）**。architect の絶対規則は「承認前に下流仕様を**確定しない**」。本 handoff はそれに加えて、運行判断として**執筆自体を承認後まで待つ**（承認判定で方針が変われば書いた分が全部是正対象になるため）
- scope 判定は「執筆モデルが変更したか」のみ。ユーザーの並行編集は報告のみで BLOCKED にしない

## requirements（この順で読む）

1. D0 intake の成果物（`{intake ファイルのパス}` sha256 `{先頭8}`）。**会話ログだけを根拠にしない。** どの回答に基づく記述かを後から復元できなくなる
2. 出所記録（intake ファイル内、または `{出所ファイルのパス}`）
3. 既存資料（{あれば列挙}）
4. 規約: architect skill の GDD テンプレート、`document-system.md`、`trigger-matrix.md`
5. 本 Skill の `references/gdd-and-intake.md`、`references/autonomous-execution.md`
6. Class Bの場合、上記1〜5の全文を含むhash付き`contextBundle`。local path参照だけは禁止

## 製品判断の扱い（本 handoff の中核）

**intake の回答にない製品判断を作らない。** 判断が必要な箇所に遭遇したら、次のいずれかにする。

1. intake の回答から導出できるなら導出し、導出の根拠を書く
2. 導出できないなら `[PROPOSAL]` marker つきで書き、**未承認であることが読んで分かる形にする**
3. 提案すら根拠がないなら `[OPEN blocking: yes|no]` として理由・closure evidence を書く

**執筆モデルも指示役も `[PROPOSAL]` を独断で `[DECISION]` へ昇格しない。** 使用者が明示承認したときだけ昇格する。

### 出所の記録形式

各 `[DECISION]` に、intake で記録された出所を保って書く。

| 出所 | 書き方 |
|---|---|
| `U` | ユーザー発言由来。intake の該当項目 ID を添える |
| `W` | 調査由来。URL と取得日を添える |
| `M` | 実測由来。evidence パスと実測値を添える |
| `J` | 指示役の提案。判断理由と、採らなかった代替案を添える。承認までは `[PROPOSAL]` |

**出所を推測で書かない。** intake に出所または人間承認が無い項目は、`[DECISION]` にせず `[PROPOSAL]` のまま残し、報告で列挙する。使用者が明示承認してから昇格する。

既存資料がある場合、**用語・構成・判断を無断で置換しない**。改善提案は本文へ混ぜず、別立ての `[PROPOSAL]` 節にする。

## 数値の扱い（通常 handoff の `dataIds` に相当）

data_definition がまだ存在しないため、参照すべき DATA ID の一覧を渡せない。代わりに本節が数値の扱いを規定する。

**成功指標の可変閾値を GDD に確定しない。** GDD が持つのは「何を測るか」と「どうなったら合格・不合格か」まで。バランス調整で動く値・分母規則・計算式・単位は data_definition が所有する。

対象は**可変閾値**であり、GDD が書く数値すべてではない。製品意図としての記述（想定ラウンド時間、対象端末の優先度など）は GDD が持ってよい。判断基準は「バランス調整で動く値か」。

**実測値も本文へリテラルで書かない。** D1.5 の計測結果は evidence が正本であり、製品の可変閾値になるなら data_definition が所有する。GDD は「FR-n の実測に依存する」という関係だけを書く。

data_definition はこの時点で存在しないので、GDD には**指標の key と、値は data_definition の DATA ID を参照する旨**を書く。

理由句は実体条件で書く。「data_definition が未作成のため」は data_definition ができた瞬間に嘘になる。「当該指標の canonical 値が未登録のため（closure: data_definition へ登録されたとき）」と書く。

## 重要な区別（常設）

- **配達先 ≠ 数値所有先 ≠ 判断所有先**
- **`[DECISION]` には出所と人間承認記録が要る**。どちらか一方だけの決定を書かない
- 他文書の決定 ID を参照するときは完全修飾（上記「決定 ID の参照規約」）
- 裸 `[OPEN]` 禁止（`blocking: yes|no` 併記が必須）
- 陳腐化する前提句を使わない。実体条件で理由を書く
- `[HUMAN]`はhuman-only。`[AI-ACTION]`と台帳を分離する

## 報告の誠実性（必須）

実施していない検証を報告に書かない。「独立照合」「別セッション」等の語（変形を含む）を自己検証の名称に使わない。sha256 は実際に計算した値のみ記載する。

## acceptance

1. objective 充足
2. 指示側の機械検査（lint_docs.py ＋ validator ＋ sha256 ＋ scope）
3. Class Aの別セッション独立照合 1巡以上でCritical 0 / Major 0
4. **`[PROPOSAL]` の残数と位置が一覧化されている**（使用者が採用・却下を決める対象になるため）
5. **出所または人間承認記録のない `[DECISION]` が 0 件**（出所は `unsourced-decision`、承認記録は `decision-approval-record` で検査し、独立照合でもトレース）

## commands

読み取り系すべて / `{PYTHON_EXE} "{VALIDATOR_ABS}" --project-root . --prefix {PREFIX} --gate D1`。Windowsは`python`、fallback `py -3`を実在確認して固定

## execution

通常handoffの`execution`、`transferApproval`、`executionAttestation`を全て含める。

- Class A: approved root/inScope、sandbox、exact model/versionを起動引数へ拘束
- Class B: hash付きcontext bundle全文inline、artifact/report response envelope、raw response保存、`finishReason == stop`
- artifact pathは`docs/{PREFIX}_gdd.md` 1件。telemetry/footerをartifactへ混ぜない

## evidence

作成パス / タグ集計（特に `[PROPOSAL]` と `[OPEN blocking: yes|no]` の極性別件数・位置）/ **出所内訳（U/W/M/J の件数、出所または人間承認記録がない `[DECISION]` の位置）** / Non-Goals の件数と各々の理由の有無 / 記載数値一覧（各々について、可変閾値か製品意図かの区別を付す。可変閾値は原則ゼロ件）/ validator 出力 / 自己実行検証のみ

## rollback

- `docs/{PREFIX}_gdd.md` を削除
- `HUMAN_ACTIONS.md`／`AI_ACTIONS.md`へ追加した行を削除
- `.claude/doc-lint.json` へ追加したエントリを削除
- `DECISIONS.md` へ追加した行を削除

## 承認準備と人間承認ゲート（この handoff の完了後）

**GDD は独立照合の承認可でも、指示役の品質判定でも確定しない。** 指示役が次を全部確認して承認材料を提示し、使用者の明示承認を得る。**承認条件と承認者は architect の Gate 1 と workflow D1 が正本**であり、ここへ書き写さない。判定の前に architect 側を読むこと。

1. 機械検査 PASS（lint + validator + sha256 + scope）
2. 独立照合 Critical 0 / Major 0
3. `[PROPOSAL]` 残数 0。各 `[DECISION]` に出所が付いている
4. Gate 1 の条件を条件文ごとに充足確認した記録がある
使用者の明示承認後に、次を順番どおり記録してから D1.5 を実測する。D1.5 は Gate 1 の前提ではない。FAIL なら GDD を改訂し、人間の再承認へ戻る。

1. approved intakeからclosed `required_specs.schema.json` projectionを`detect_triggers.py`で先に生成・検証する。承認対象GDDを`targetArtifact`、scopeをclosed `{kind:"gdd-gate1-v1", decision:"approve-gdd-for-d1.5-and-d2", approvedIntake:{path,sha256}, requiredSpecs:{path,sha256}, additionalScope:false}`として決定論digestを作る。unique challenge IDを先に割り当て、full target/scope/digest/canonical responseを含む`human_approval_presentation` canonical bytesを生成・hashし、それを指すchallengeを発行する
2. presentation canonical bytesをassistant/system messageとして人間へ提示した後だけcanonical responseを受け取る。両messageを同一structured transcriptへ保存し、human response exact bytesをstatement artifactへ保存する。`human_approval_capture.schema.json` の`gateType:gdd-gate1`を作り、target/scope/challenge/presentation message ID/human message ID/statementをexact一致させる。順序はchallenge issued <= presentation < human response <= capture。local bytes/ID/hash自体を真正性rootにしない
3. captureのpresentation role/time/content、human actor/role/time/content、channel/message/gate target claimsを、operator管理の外部configでpinしたprovider adapterによるfresh query（nonce＋raw response）またはprovider署名＋pinned trust anchorで検証し、outer `provenance_verification`を作る。claimsはpresentation hash、canonical response hash、GDD＋approved intake＋required_specs scope digestを含み、verifiedAtはcapture以後。この外部query/署名だけがmachine gateの真正性root。adapter/署名検証不能なら`STOP/HUMAN`
4. `gate_approval_record.schema.json` でtype `gdd-gate1` machine recordを作る。`targetArtifact` とscopeはcaptureへexact一致し、`sourceEvidence`はcapture JSON path/hash、`sourceVerification`は手順3のouter verification path/hashを指す。Gate 1時点で存在しないbaselineを捏造しない
5. `DECISIONS.md` へ承認者・GDD revision・approved intake/required_specs hashes・日時・Gate 1 record ID/path/hashを追記する。D1.5/D2 entry、initial D4/B0、P0/D5/W0は同じrecordと3 artifact bindingsを不変継承し、別の承認へ置換しない

人間承認前は `承認準備完了` とし、`承認済み` と書かない。capture/provider verification/recordのschema・bytes・相互一致が未検証ならD1.5/D2へ進まない。

Gate 1固定済`required_specs`にfeasibility row無し→D1.5 evidence/proof 0件。rowあり→combined suite 1件。`requiredSubchecks`はapproved intakeでtrueの5 technical flags（vehicle/custom physics、high NPC/FX load、高頻度projectile／高速PvP、free text/UGC、Multi-Place）だけをID/source/value hash固定し、free-form `product.top_risks`はD3/D4 risk registryで扱う。通常PvPだけではtriggerしない。D0独立reviewはGDD/answerが高頻度projectileまたは高速PvPを述べるのに`high_frequency_projectiles_or_fast_pvp=false`、または他のmeasurable mechanic riskに対応flagがfalseなら再intake。各subcheckはtrial/threshold/raw-output artifact refsと個別evidence digestを持ち、outer claimsのset digestがexact-coverする。top-level bundleだけ、欠落/重複、fail→inconclusive弱化、2件分割、外部検証不能はPASS不可。GDD追加riskはintake/Gate1へ戻す。E0非流用。以後Gate1 intake/required_specs refsとzero/one proofを不変継承。
