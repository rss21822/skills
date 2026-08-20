---
name: claude-roblox-dev-docs-creator
description: >
  Roblox 開発を**企画からW0引渡し承認まで一本で通す** skill。体系定義（何を作るか）と運行規約（どう作れば手戻りが出ないか）の両方を持つ。
  E0 能力・権限プリフライト → D0 聞き取り → D1 GDD → D1.5 Feasibility 実測 → D2 設計・仕様 → D3 実装計画・テスト・運用文書 → **D4 3系統受入監査** → **P0 契約確定** → **P0 後 D4（delta／必要時full）** → **D5 人間承認と Status 同期**まで。
  文書テンプレート、JSON schema、監査 checklist、validator、lint を同梱する。製品実装（W0 以降）だけ `claude-roblox-mvp-buildout`、単発 WP は `claude-roblox-development-delivery` へ渡す。
  「ゲームを作りたい」「企画から開発ドキュメントを作って」「GDD を書いて」「開発ドキュメント群を作成」「設計書・仕様書を書いて」「D2 を進めて」「文書から実装まで通して」のほか、
  「設計書レビューして」「この文書で実装できる？」「実装前チェック」「文書整えて」「引き継いだ文書が使えるか見て」（→ D4 監査）、
  「P0 を進めて」「Change Request を起草／承認」「open を閉じて」「契約を確定して」「Verified へ遷移」（→ P0）、
  「D5 承認」「実装契約を承認して W0 へ渡していい？」（→ D5）でも使う。実 side effect の開始可否は受領側 W0 gate。
  Roblox プロジェクトで企画書・GDD・下流仕様を新規作成／改訂するとき、二重正本・陳腐化参照・タグ不整合・決定 ID 衝突を点検するとき、handoff で文書を量産するとき、D1.5 を Studio で実測するときは必ず使う。
  **使用者は E0 で worker 候補と probe の送信先を承認し、probe 後に正本を書く執筆役・照合役を指定する**——Codex CLI / Cursor CLI 経由の Grok・Kimi・GLM・Gemini / Claude サブエージェント / DeepSeek のいずれでも可。
  誤字修正・文言の微修正・単発の質問回答・README 程度の更新には適用しない（重すぎる）。
---

# Roblox 開発 — 文書体系の制作から D5 承認まで

## 0. この Skill が扱う範囲

**名前は「docs-creator」だが、射程は文書制作より広い。**

| stage | 内容 | 本 skill が持つか |
|---|---|---|
| **E0** | 能力・権限・worker 候補・到達点のプリフライト | ✅ |
| D0〜D3 | intake → GDD → Feasibility → 設計・仕様 → 実装計画 | ✅ |
| **D4** | 3系統受入監査（`D4合格 / P0着手資格あり（人間P0開始承認待ち）` の判定） | ✅ |
| **P0** | 契約確定（D5 の前提工程） | ✅ |
| **D5** | 人間承認と Status の原子的同期 | ✅ |
| W0〜W2 | 製品実装 | ❌ `claude-roblox-mvp-buildout` |
| 単発 WP・不具合 | 局所実装 | ❌ `claude-roblox-development-delivery` |

**入口は現状で変わる。**

| 現状 | 入口 |
|---|---|
| 何も無い | D0（GREENFIELD） |
| GDD だけある | D0 差分を先に取る |
| 動くゲーム／repo がある | Repository Audit を D1 前に（BROWNFIELD） |
| **他者作成の文書群がある** | **D4 admission preflight から。執筆せず、既に在る正本を書き換えない** |
| D4 合格済み、P0 未完了 | P0 開始承認 gate → P0 |
| P0 完了、P0 後 D4 未実施 | P0 後 D4（delta／必要時full escalation） |
| P0 後 D4 合格、D5 未承認 | D5 |

**到達点を着手前に宣言する**（`docs` / `audit` / `contracts` / `ready` / `full`）。未指定なら `audit` を提案する。延ばすときは使用者の指示と変更時点を `DECISIONS.md` へ追加する。黙って延長しない。

## 1. 絶対規則

**正本は `references/absolute-rules.md`。** 以下は入口としての再掲であり、食い違ったら reference を正とする。

1. ユーザー提供資料を一次入力とする。用語・構成・判断を無断で置換しない
2. 外部知識での拡張・検証は `[EXTERNAL]` または `[PROPOSAL]` と明示する
3. 同じ事実の二重正本を禁止する（境界は `references/document-system.md`）
4. active な `[PROPOSAL]`・未検証 `[ASSUMPTION]`・`[OPEN blocking: yes]` が残る文書を承認済み正本にしない（active／history の判定は `references/quality-gates.md`）
5. GDD の人間承認前に下流仕様を確定しない
6. 高リスク機能は全文書生成前に D1.5 Feasibility Gate を通し、triggered raw measurementをoperator-pinned external runtime provenanceへ束縛する
7. `[HUMAN]` は人間だけが実行する。AI 実行可能な作業は `[AI-ACTION]` として `AI_ACTIONS.md` へ分離する
8. 既存プロジェクトでは Repository Audit 前に構成を変更しない
9. **W0 引渡し可能と宣言できるのは D5 の全ゲートに合格した場合だけ。実装 side effect は受領側で、外部authorityがprocess生成前から監視したPREPARE、signed prelaunch下のpackage validation、同run signed postexecution、W0 packageから機械導出した全immutable project pathとwrite pathの非交差・receiver Skill全tree・expected loaded process closureを人間へ事前提示したclosed run authorization、expected-only signed ADMITのsemantic PASS、admission token原子的消費、scope enforcement下のsuspended/pre-entry worker launch、actual closure一致を束縛したsigned admit-execution receipt、bootstrap PASS、未使用で短期のworker-ready capabilityをすべて検証し、そのcapabilityを最初のeffect直前に原子的消費した後だけ**
10. 実装中も文書を凍結しない。WP 完了ごとに D6 同期を行う

## 2. 三点構造 — 担い手は指定制

**指示役・執筆役・照合役を分ける。分けること自体は固定であり、途中で崩さない。使用者は E0 の固定 probe 前に候補と送信を承認し、probe 結果を見て担い手を指定する。**

| 役割 | 担い手 | やること |
|---|---|---|
| 指示役 | 本セッション（Claude） | 計画・handoff 発行・機械検査・実測（Studio MCP／ブラウザ／Computer Use）・承認準備判定・承認提示・記録・許可済み commit |
| 執筆役 | **使用者が指定した worker** | 文書の新規作成・是正。handoff の inScope だけを変更する |
| 照合役 | **使用者が指定した別 worker**（read-only） | 独立照合。作成に関与していないセッションで発注する |

**なぜ三点に分けるか。** 好みではなく構造の問題。

1. **実行面は指示役にしかない。** Studio MCP・内蔵ブラウザ・Computer Use は本セッションに接続されている。外部 worker はサンドボックス内のファイルとコマンド、あるいはテキスト応答しか持たない。実測を worker へ依頼しても実行できず、**実行できない検証を「実施した」と書く圧力**になる（§11 の捏造報告7件はこの構造で生まれた）
2. **執筆と検査を同じ主体にしない。** 指示役が書いて指示役が検査すると盲点を共有する。3点が互いの申告を検算する形が、単一モデルの自己完結より欠陥検出率が高かった（62巡の実測）。**執筆役と照合役に別系統のモデルを充てると、モデル固有の盲点まで外から見える**
3. **コンテキストの分離。** 指示役は体系全体を保持する。執筆役は1 handoff 分だけを見る。全体を持たせると handoff に無い「気を利かせた」変更が inScope の外へ漏れる

**指示役が自分で書いてよいもの** — handoff・照合依頼・note・`DECISIONS.md`／`HUMAN_ACTIONS.md`／`AI_ACTIONS.md` などの記録類・lint 設定・閾値ファイル・実測 evidence。D5 承認後の header／index／manifest 同期は `templates/d5_approval_handoff.md` どおりの機械的 metadata 更新に限る。**正本文書の本文（GDD・Spec・Work Package 等）を指示役が直接書かない。**

**テキストしか返せない worker**（Cursor 経由の Grok 等）を執筆役にする場合、指示役がバイト列を書き込むことになる。生出力を先に保存して sha256 で挟む（`references/worker-registry.md` §5）。**この手順を踏まない転記は執筆役の成果物として扱わない。**

指定 worker が全滅した場合も**正本執筆を指示役へ fallback しない**。機械検査・handoff 準備・実測だけ進め、`blocked-capability` として記録し、使用者へ worker 再指定を求める。代役を黙って立てない。

責務名（`product-gdd-writer`、`system-architect` 等）と worker の関係、delegation packet の必須項目は `references/worker-registry.md` §0。worker 別の起動要領は `codex-run` / `cursor-grok` / `deepseek-api` の各 skill。

## 3. 自律実行モードと安全境界

**自律化するのは、機械的に検証できる作業だけ。** 調査、D1.5 実測、機械検査、照合の起動、`AI_ACTIONS.md` の実行、許可済みローカル操作は指示役が行い、証拠を残す。

**自律化しないもの** — 未回答の製品判断、GDD と D5 の明示承認、`J` 提案の `[DECISION]` 昇格、未許可の commit、production・課金・権限・認証操作。`[DECISION]` は人間承認済みと定義されるため、実測値・照合記録・出所は**承認材料であって人間承認の代替ではない**。

**自律化しない線**（使用者が許可しても AI は実行しない）: 認証情報の入力 / アカウント作成 / production publish / 課金製品の作成 / production データ書き込み / 規約承諾 / 法的効力を持つ権利処理。該当作業は `HUMAN_ACTIONS.md` へ `exec: human-only`、AI 停止理由 `blocked-safety` として残す。

**blocked が並ぶのは失敗ではなく、線を正しく引いた記録。**

実行面は4つ（Studio MCP / 内蔵ブラウザ / Computer Use / ローカル）。使い分け・実測手順・承認準備・exec 分類は `references/autonomous-execution.md` が正本。**着手前にそれを読む。**

## 4. stage router — どの stage を、どの機構で起動するか

**stage ごとに正しい起動機構が違う。** ここを取り違えると clean context 要件を破る。

| stage | 内容 | 起動機構 | 理由 |
|---|---|---|---|
| **E0** | 能力・権限プリフライト | **本 skill 内。正本文書を執筆しない** | 実行可能性と送信境界を計画より先に固定する |
| D0〜D3 | 文書制作 | **本 skill 内で実行** | 指示役が体系全体を保持する必要がある |
| **D4** | 3系統受入監査 | **subagent または新規セッション。同一セッションで実行しない** | 会話履歴・迷った経緯・期待判定を渡さないため |
| **P0** | 契約確定 | **本 skill 内で実行** | 指示役が体系全体を保持したまま契約を確定する |
| **D5** | 人間承認 + 状態同期 | **本 skill 内。`templates/d5_approval_handoff.md` を実行** | 承認は人間、同期は機械的 metadata 更新 |
| W0〜 | 製品実装 | **MVP全体は `claude-roblox-mvp-buildout`、単一WPは `claude-roblox-development-delivery` を `Skill` ツールで呼ぶ** | 別 skill。両方ともPREPARE→VALIDATE→ADMIT→signed receiptをfail-closed実行する。machine-derived frozen path set、disjoint write set、receiver Skill tree、expected loaded process closure、worker・送信・operationをhuman authorizationへ固定し、semantic PASS後だけtoken消費→worker suspended/pre-entry launch→actual closure照合→receipt検証→bootstrap PASSとする。未使用worker-ready capabilityを最初のeffect直前に原子的消費するまでside effectは禁止 |

### D4 の clean context 要件

指示役が先に project root を read-only 探索する。同時に、実際にinstalledされた本skillのD4節・audit手順/観点・3 checklist・findings template・required validator scriptsと全local importsをrehashし、built-in lane command compilerの出力と合わせてschema-valid **D4 audit policy manifest**を固定する。project側policy copyはtrust sourceにしない。実行code/schema/configはsanitized root内`_policy_runtime/`へhash同一copyし、監査者はinstalled skill rootを読まない。外部はoperator-pinned Python executable/stdlibだけをclosed read-only runtime allowlistへ固定する。そのうえで`git status` / `git log` / actual tree / deleted path / validator 出力を schema-valid な **D4 audit capsule** へ固定する。各入力は元の `sourcePath`、sanitized root 内の immutable `capsulePath`、bytes、sha256、role を持ち、preflight は argv・cwd・exit code・生出力 path/hash を持つ。capsuleのpolicy/check/command setはinstalled policyとcandidate stageからexact導出し、会話情報を混ぜない。

監査者へ**渡すもの**: allowlist だけを収めた sanitized audit root / installed sourceから再導出したpolicy manifest / `schemas/d4_audit_capsule.schema.json` で検証・hash固定した共通 capsule / lane固有のhash-pinned outer request artifact / immutable candidate baseline manifest（initial は `D4-CAND-n`、P0 後は `P0-CAND-n`）/ `findings-only, read-only` という目的。まずouter wrapperとは独立したclosed `requestCore`をcanonical JSONとして固定する。installed policy/checklistとそのrequestCoreを固定順で結合してskill-controlled submitted prompt bytesを作り、そのhashを最後にouter wrapperの`fullPromptArtifact`へ入れる。promptにouter wrapper/hashを含めずself-referenceしない。Class A監査者は sanitized root 内で validator と evidence hash を再検査する。

**渡さないもの**: 会話履歴 / worker 名 / 迷った経緯 / 期待判定 / `E0_capability_probe.md` / handoff 会話 / 過去の自己評価。

監査者は元 project root を検索しない。追加ファイルが必要なら指示役へ path と理由を返し、指示役が新しい sanitized root / capsule を作る。暗黙に範囲を広げない。返答原文を `docs/audits/<PREFIX>_d4_<lane>_<candidate-id>_r<N>.md` へ**無編集保存**する。その後だけ指示役が lane ごとの `d4_auditor_attestation.json` を作り、request artifact・raw response の実 hash・共通 capsule・検査入力・commands を束縛する。さらにoperator管理の外部configへpinされたruntime queryまたは署名でexecution/session/model/clean/read-only/input/command/output/timeを `provenance_verification` に束縛する。raw response へ後続artifact hashを後書きしない。外部proofを作れないlaneはD4未実施として停止する。

**Class A の clean context を用意できない場合、D4 未実施として停止する。** Class B で実施済みに見せない。

### 前進条件

| 遷移 | 必要条件 |
|---|---|
| D3 → D4 | approved intake＋そこから再導出したrequired specs＋GDD revisionを束縛するGate 1のhuman challenge→trusted presentation/response transcript/statement→capture→external provenance→machine recordと`DECISIONS.md`同一ID記録 / 該当 D1.5 combined suite の PASSとraw evidence/external runtime provenance（trigger 0ならproof 0） / D3 までの正本 / lint・validator・独立照合が warning・note 0 で PASS / 全 `[PROPOSAL]`・未検証 `[ASSUMPTION]`・blocking open を source ID/path で一意に収録した `PROGRESS.md` § Proposed P0 closure inventory / immutable `D4-CAND-n` manifest |
| AUDIT admission → D4 | 指示役の read-only inventory / sanitized audit root / immutable `D4-CAND-n` manifest。GDD 承認・D1.5・必須文書が無い場合も入場可だが、欠落は findings とし合格条件を緩めない |
| D4 → P0 | 3系統すべて **Critical 0 かつ Major 0** / 同じ schema-valid capsule、3 raw response、lane別 Class A attestation と外部runtime provenance の実hashを束縛した `auditRecords` / 合格した `D4-CAND-n` と同一 file-set hash を `promotedFrom` で結び、`PROGRESS.md` closure inventory も不変固定した **B0** / external provenance付きhuman captureをsourceとする **P0 開始承認 ID** を別 gate で取得。承認 scope は B0 historical inventory の全行に限定した製品内容 closure と、規定済み P0 検証・記録・管理WP・candidate固定手続だけ。Gate 1承認済みintake／required specs／GDDとGate 1 chainはP0でimmutableで、変更が必要ならD0/D1からunique new Gate 1 routeへ戻る。Critical/Major があれば候補を履歴保存して執筆役へ `templates/correction_handoff.md` を発行し、全3系統を新しい clean context で全面再監査 |
| P0 → P0 後 D4 | P0 契約検査が warning・note 0 で PASS / P0 管理 WP の `Verified` 遷移 / B0 inventory 全 ID の Completed evidence・影響正本 hash と candidate inventory data row 0 / approved content digestを人間がchallenge responseで直接承認し、外部provenance付きcaptureと固定procedure正規化でcandidateへ結ぶ P0契約record / parent B0 の snapshot-only immutable `P0-CAND-n` manifest / P0-start verification後から pre-approval write、P0-contract verification、固定metadata、全snapshot copy、actual-candidate machine record、exact frozen-byte canonical apply、final sealまでの全in-scope transition mutation eventsをauthority側で証明した外部provenance付き lifecycle transition attestation。0件のinventory mutationも明示し、seal後writeは0 |
| P0 後 D4 → D5 | B0→`P0-CAND-n` の変更と全影響文書を、全3系統の新しい clean context・同一mode（delta／該当時full）で監査 / Critical 0 かつ Major 0 / 共通 capsule、3 raw response、lane別 attestationと外部runtime provenanceを `auditRecords` へ束縛 / 合格候補と同一 file-set hash を `promotedFrom` で結んだ **B1** 固定 / P0 開始承認・P0 契約承認が別 ID |
| D5 → W0 | B1とfirst WPをclosed scopeで特定したhuman challenge/capture/external provenance/record / Gate1・P0-start・P0-contract・D5の4鎖が相互distinct / D5 verification完了後のactual sync events、allowed-diff生成、B2 snapshot全file copy、final seal、完全write log・許可差分・B2 hashをauthority側で証明した外部provenance付き lifecycle transition attestation / 全provenanceがW0でoffline検証できる pinned-signature mode / crash-safe 状態同期 / snapshot-only **B2** post-sync manifest / 必須 W0 handoff package。query-modeはW0前の送信権限が無いため不合格。詳細は `references/phase-definitions.md` §9 |

### stage 遷移の記録

各遷移を `DECISIONS.md` の Stage Transition Record へ**追記**する（上書きしない）。transition ID・source/target stage・entry/exit verdict・B0/B1/B2 の役割と親 baseline・evidence・人間 gate なら承認 ID/承認者/日時/対象 revisionとchallenge/capture/external provenance/record参照・P0/D5ならcandidate/B2外の lifecycle transition attestationとauthority側actual-event provenance・worker 実行 attestationと外部runtime provenance・未完了 Human Actions。

### 停止条件

宣言した到達点へ到達 / Critical・Major 未解消 / 必須 validator 未解決 / D5 明示承認なし / worker・送信承認・Class A 監査者を用意不能 / contract 変更を伴う D7 未完了 / 認証・production publish・課金・規約・権利処理の human-only 境界。

**停止は失敗扱いにせず、再開条件と必要 evidence を記録する。**

## 5. E0 開始ゲート — 能力・権限プリフライト

**E0 は D0 より前。正本文書の執筆 job ではない。** 空 project では `docs/handoffs/out` と `.claude` の運行用 directory だけ作成してよい。何が使えるか、どの候補へ固定 probe を送ってよいかを確認してから運行計画を立てる。

```
実行面
1. list_roblox_studios
2. Studio名・Place・studio_idを照合し、対象を1つに束縛
3. get_studio_state {studio_id}
4. execute_luau {studio_id, datamodel_type, code="return {probe = 2}"}
5. http_get で Creator Docs の既知 .md URL を取得
6. browser が必要なら、現行 tool schema の navigate/read を列挙してから最小閲覧

worker
7. 使用者が候補 provider/account/model/cost と固定 probe 送信を承認
8. project 内容を含まない固定 probe を承認済み候補だけへ送る

provenance
9. user/operator 管理の外部 verifier config に pin された runtime adapter／署名 trust anchor を、既知test claim・fresh nonceで検証
10. D5/W0到達を選ぶ場合、3つのD4実行、D1.5、4 human gate、P0/D5 transitionの各proofを**生成時点からoffline pinned-signature mode**で発行でき、W0 receiverが同じ外部trust anchorだけで検証できることを実probeする。query-onlyならfull routeを選ばない
```

`preview_start` は `.claude/launch.json` の dev server を `name` で起動する tool。URL 閲覧 probe に使わない。Studio call は実行時 schema を優先し、全 call へ `studio_id`、`execute_luau` へ `datamodel_type`、`screen_capture` へ `capture_id` を付ける。

**worker probe も第三者送信。** provider・account/billing identity・auth channel・model・cost 上限の使用者承認を先に記録する。probe に project 文書・path・secret を含めない。

結果を `docs/handoffs/out/E0_capability_probe.md` へ、**実際の出力を貼って**保存する（「疎通した」という要約ではなく、返ってきた値）。provenance verifierのpinはproject/candidate内の自己申告設定を信用せず、operator管理の外部configから読む。E0のtest結果を後続artifactへ流用せず、各D4 lane・各human gateでfresh proofを検証する。**D5→W0までを到達点に選ぶなら、後続の全W0-bound provenanceをその場でoffline検証できるpinned-signatureとして発行できるauthority／trust anchorをE0で実probeし、成功しなければD0前に停止する。** query-only adapterはDraft等の限定到達点には使えても、後でbaseline内のimmutable query-mode proofを署名modeへ読み替えられない。必要なsignature authority／anchorが無ければ到達点を限定するか停止して使用者へ報告する。

プローブ後、**使用者へ執筆役・照合役を訊く**。落ちた候補は理由つきで外す。同時に到達点・commit範囲・外部送信範囲を確認する。次を宣言・記録する。

- **指示役の宣言**: 本セッションのモデル。自己モデルの検証手段はないので「宣言」であって「検証」ではない
- **執筆役・照合役の実行 attestation**: worker/class・requested/resolved model・CLI/server version・effort・sandbox・network・auth channel/account・finish reason。**宣言だけでは合格しない**
- **選択の出所**: 使用者指定か指示役判断か（判断なら理由も）

worker が未導入・版違いなら**自動 install しない**。`blocked-permission` として必要版・install 先・rollback を提示し、使用者の許可を待つ。

`.claude/doc-lint.json` は**最初の handoff を出す前**に最小構成を用意する。まだ適用できない規則は `rules` で明示的に無効化し、対象作成時に**再有効化する**。雛形は `templates/doc-lint.json`、記入例は `references/config-example.md`。

**未設定の項目は lint が note で知らせ、終了コード1を返す。warning または note が1件でもあれば PASS ではない。**

## 6. 執筆順序 — 手戻りの最大要因

**所有者を先に、消費者を後に書く。** 本 skill で最も効果が大きい規則。

```
E0      プリフライト       能力・権限・worker候補・到達点
D0-D1   起点               intake（事前記入＋確認）→ scaffold/reconcile → GDD → 人間承認ゲート
D1.5    実証               承認済み GDD の Feasibility を Studio MCP で実測
Tier 0  判断・数値の所有者   data_definition / rights_provenance_ledger
Tier 1  構造                 detailed_design
Tier 2  Tier0-1 の消費者     physics / network / persistence / ui_ux
Tier 3  Tier2 の消費者       multi_place / commerce / analytics / performance /
                             asset / ugc / localization / liveops
Tier 4  生成物               docs_index / manifest（手書きせずスクリプトで生成）

D3      phase_plan → work_packages → test_spec → toolchain
        → traceability（wp/test 参照まで一括記入）
        → CLAUDE.md / workflow → release runbook → 記録類
```

**なぜ**: 順序を守らないと、先に書いた文書が「まだ無い文書」を前提に語り出す。「`X.md` は未作成のため保留」という一文は、書いた瞬間は正しく、`X.md` ができた瞬間に嘘になる。誰も直しに戻らない。実プロジェクトではこの陳腐化前提句が15箇所以上残り、最終監査まで生き延びた。

**順序を崩す場合**: 前方参照を `.claude/doc-lint.json` の `forward_refs` へ登録する。lint が「参照先が実在するようになったら理由句を書き換えよ」と警告する。**登録しない前方参照は禁止。**

**traceability CSV は work_packages と test_spec の後に一度だけ書く。** 骨格を先に作って後から参照列を埋めると242行を2回触ることになる（実際にそうなった）。

各 phase が何を作り何で閉じるかは `references/phase-definitions.md`、所有境界の全体設計は `references/ordering.md`。

## 7. 1文書のサイクル

```
handoff 発行（指示役）
  → 執筆役が作成                       ← クラス B なら生出力を保存してから転記
  → 指示役が機械検査（lint + validator + sha256 + scope）   ← 照合より先
  → 独立照合（照合役・読み取り専用）1巡目=全面
  → 是正 handoff（指示役）→ 執筆役が是正 → 照合 N 巡目=残存点のみ
  → 照合合格 → 品質判定（指示役）→ 必要な人間承認 → 許可済みなら commit
```

これは **D0〜D3 の1文書サイクル**。D4 gate は別規則で、是正後も全3系統を fresh context で全面再監査する。D4 に残存点限定 review を流用しない。

GDD は**人間承認後に D1.5 実測ゲート**を通す。Gate 1の人間向け意味の正本は`DECISIONS.md`の記録、機械証跡はapproved intake／再導出required specs／exact Draft GDD path/hash/revisionを同じscopeへ入れたchallenge/capture/external provenance/type `gdd-gate1` recordで、同一ID・対象へ解決する。GDD bytesはB1まで不変。D5外部監視下のfixed metadata-only transformationだけがB2で `Approved` / `Last approved` / historyを更新でき、receiverはB1/B2のnormalized body digest一致を再計算する。local transcript/ID/hashだけではhuman-direct証明にならない。**照合の「承認可」は品質所見であって人間承認ではない。**

## 8. handoff の書き方

新規作成・全面改訂で必須の項目（欠けると執筆モデルが埋め合わせに創作を始める）:

`handoffId` / `phase` / `baseline` / `objective` / `inScope` / `outOfScope` / `requirements` / `dataIds` / `acceptance` / `commands` / `execution` / `transferApproval` / Class B なら `contextBundle` と `responseEnvelope` / `rollback`

**是正便はこの集合に従わない。** 照合記録という参照点があるので `templates/correction_handoff.md` の項目集合で足りる。巡が進むほど小さくしていく。

雛形をそのまま使う（`templates/handoff.md`、GDD は `templates/gdd_handoff.md`、P0 は `templates/cr_draft.md` / `approval_record.md` / `revision_handoff.md` / `contract_approval.md`）。常設条項の要点:

- 数値創作の全面禁止（DATA ID または承認済み値・実測値の参照のみ）
- **配達先 ≠ 数値所有先 ≠ 判断所有先**
- `[DECISION]` には出所と人間承認記録を付す。未承認なら `[PROPOSAL]`
- 決定 ID の完全修飾（裸の `D-9` を禁止）
- 裸 `[OPEN]` 禁止（`blocking: yes|no` 併記が必須）
- 陳腐化前提句の禁止（「未作成のため」で理由を書かない）
- 上流の `[PROPOSAL]` を `[FACT]`／`[DECISION]` へ昇格しない
- 前方参照は `forward_refs` へ登録
- `[HUMAN]` は人間のみ。AI 実行分は `[AI-ACTION]` として `AI_ACTIONS.md` へ
- **報告の誠実性**: 実施していない検証を書かない。検証語彙を自己検証の名称に使わない。sha256 は実測値のみ

### inScope に状態の正本を必ず含める

**「Status を X へ更新せよ」と指示するなら、Status の正本ファイルを inScope に入れる。** 当たり前に見えるが実際に事故った。

Work Package の Status は `work_packages.md` の index と詳細節が正本で、`PROGRESS.md` はその写し。inScope に `work_packages.md` を入れ忘れたまま「Status を `In progress` へ」と指示した結果、実装モデルは inScope 内の `PROGRESS.md` だけを更新し、**正本と運行記録が二分した**。照合で Major になった。

一般化: **objective に書いた変更対象すべてについて、その値の正本がどのファイルかを確認し、inScope に含まれているかを発行前に検算する。**

### handoff 自体の誤りは handoff を直す

指示が間違っていた場合（範囲指定ミス、存在しない値の要求）、**成果物を歪めて辻褄を合わせず、契約側を訂正して記録する**。是正 handoff の冒頭に「§0 発注側の誤りの記録」を置くのが定型。曖昧にすると誤った指示が正本に固定される。

## 9. 機械検査を照合より先に

**lint を必ず先に走らせる。** LLM 照合が見つけた指摘の相当割合は正規表現で検出できる。裸 `[OPEN]`、blocking の極性矛盾、陳腐化前提句、裸の決定 ID、行番号参照の範囲外、未解決 placeholder、値の二重正本、索引と詳細節の食い違い、検証語彙の自己使用。

**証拠追跡に固有の4規則**（いずれも人間承認を代替せず、記録の欠落を検出する）:

- `unsourced-decision` — `[DECISION]` に出所が無い。**自律モードの最大リスク**
- `decision-approval-record` — `[DECISION]` に人間承認者または承認記録の参照が無い
- `human-action-exec-class` — `HUMAN_ACTIONS.md` に `exec:` 分類が無い
- `ai-action-exec-class` — `AI_ACTIONS.md` に許可済み実行分類が無い

全 rule 名は `--list-rules`。

**スクリプトは本 Skill のディレクトリ側にある。** `--project-root` が指すのは検査対象のプロジェクトなので取り違えない。Claude Code は SKILL 本文の `C:/Users/ryufu/.claude/skills/claude-roblox-dev-docs-creator` だけを絶対 path へ展開する。OS 環境変数ではないため `$env:CLAUDE_SKILL_DIR` を参照しない。

```powershell
$skillDir = (Resolve-Path -LiteralPath 'C:/Users/ryufu/.claude/skills/claude-roblox-dev-docs-creator').Path
if (Get-Command python -ErrorAction SilentlyContinue) { $pythonExe='python'; $pythonPrefix=@() }
elseif (Get-Command py -ErrorAction SilentlyContinue) { $pythonExe='py'; $pythonPrefix=@('-3') }
else { throw 'Python interpreter not found' }
$projectRoot = (Get-Location).Path

# 文書 lint（照合より先）
& $pythonExe @pythonPrefix (Join-Path $skillDir 'scripts\lint_docs.py') --project-root $projectRoot --config '.claude\doc-lint.json'
# 体系 validator
& $pythonExe @pythonPrefix (Join-Path $skillDir 'scripts\validate_docs.py') --project-root $projectRoot --prefix '<PREFIX>' --gate '<D0|D1|D2|D3|D5>'
& $pythonExe @pythonPrefix (Join-Path $skillDir 'scripts\validate_traceability.py') 'docs\traceability\<PREFIX>_requirements.csv' --gate D3
# P0 の跨文書検査。gate では warning / 未検査 note も失敗
& $pythonExe @pythonPrefix (Join-Path $skillDir 'scripts\check_p0_state.py') --project-root $projectRoot --prefix '<PREFIX>' --config '.claude\p0-check.json' --strict
# 新規プロジェクトの scaffold / trigger 判定
& $pythonExe @pythonPrefix (Join-Path $skillDir 'scripts\scaffold_project.py') --project-name '<Name>' --prefix '<PREFIX>' --project-root $projectRoot
& $pythonExe @pythonPrefix (Join-Path $skillDir 'scripts\detect_triggers.py') --intake 'docs\<PREFIX>_intake.json'
# index / manifest を同じinventoryから再生成（通常）
& $pythonExe @pythonPrefix (Join-Path $skillDir 'scripts\gen_index.py') --project-root $projectRoot --config '.claude\doc-lint.json' --emit both --output 'docs\<PREFIX>_docs_manifest.json' --index-output 'docs\<PREFIX>_docs_index.md' --index-mode markers --project '<Name>' --prefix '<PREFIX>'
# D5同期時だけ、B2と人間D5承認IDを明示してnon-formal inventoryも昇格
& $pythonExe @pythonPrefix (Join-Path $skillDir 'scripts\gen_index.py') --project-root $projectRoot --config '.claude\doc-lint.json' --emit both --output 'docs\<PREFIX>_docs_manifest.json' --index-output 'docs\<PREFIX>_docs_index.md' --index-mode markers --project '<Name>' --prefix '<PREFIX>' --baseline-id '<B2-ID>' --approve-non-formal --d5-approval-id '<D5-ID>'
# D5 transaction後のcreator-side package assembly検査。これはreceiver W0 acceptance／side-effect権限ではない
$provenanceConfig = (Resolve-Path -LiteralPath '<OPERATOR_CONTROLLED_EXTERNAL_PROVENANCE_CONFIG>').Path
& $pythonExe @pythonPrefix (Join-Path $skillDir 'scripts\validate_d5_acceptance.py') --installed-skill-root $skillDir --project-root $projectRoot --source-project-root $projectRoot --prefix '<PREFIX>' --package 'docs\evidence\d5\<D5-ID>_w0_handoff_package.json' --provenance-config $provenanceConfig --json
```

自分でも必ず走らせる検査（**執筆モデルの報告は証拠にならない**）:

```powershell
git status --short
git diff --check
Get-FileHash -Algorithm SHA256 -LiteralPath '<対象>'
```

**実測に依存する記述は Studio で検算する。** 性能値・挙動・API の存在を `execute_luau` や `http_get`（Creator Docs）で確かめられるなら確かめる。**画像は補助であって、判定根拠は数値。**

lint と validator が warning・未検査 note なしで通ってから照合へ出す。通らないものを照合に出すのは、高コストな検査を機械で足りることに使わせる浪費。

**index と manifest は手で書かない。** `scripts/gen_index.py` がヘッダから生成する。手書きすると転記漏れが発生し、文書が増えるたびに再同期が要る。

## 10. 独立照合のプロトコル

照合は**別セッション・読み取り専用**で発注する。同じセッションの自己レビューは構造上ここでは検証にならない。**自律モードでは唯一残る外部の目**なので省略しない。

**D0〜D3 の通常文書照合は巡ごとにスコープを変える。**

- **1巡目**: 全面。観点を明示列挙する（正本準拠・独立再計算・決定の出所トレース・トリガ行の実質・上流整合・実装可能性）
- **2巡目以降**: 残存指摘＋差分の回帰のみ。解消済み観点は「再精読不要」と明記する

通常文書照合では残存点限定で収束させる。

**D4 は例外。** Critical/Major 是正後は run ID を更新し、前巡 findings・期待判定を渡さない新しい clean context で consistency / Roblox readiness / clean-room の3系統を全面再監査する。指示役は3出力を無編集保存した後にだけ、前巡との差分を回帰分類する。

**是正の方針を照合依頼へ書く。** 「確定可能な構造は閉じる／確定不能は gate 付きレジスタへ変換する」のような方針を判定基準として渡すと、照合者が未確定事項の推測 closure を要求しなくなる。

**gate 照合は Class A に限定し、自身で実行させる。** validator・test・タグ集計・evidence 実在を照合者自身が検算する。Class B は hash 付き bundle への semantic review だけを担当でき、**単独で Critical 0 / Major 0・D4 合格を出せない**。

**収束させる巡では、収束が目的だと書く。** 「指摘を作るために基準を上げない」「承認可と判定できるならそう書く」を明示する。

発散したときの判断基準は `references/review-protocol.md`、D4 での発散対処は `references/audit-d4.md` §7。

## 11. 報告を信用しない — 自分の報告も

執筆モデルは、実施していない検証を報告に書くことがある。実プロジェクトでは1セッション中に7件発生し、禁止語を追加するたびに表現が変形した（「独立照合」→「別セッション」→「サブエージェントレビュー」→「受入照合」→ 最終的に指示役の検査結果を騙る「Fable構造検査」まで）。sha256 の誤報告も起きた。

**対処は構造的に行う。争わない。**

- 執筆モデルの報告は要約であって証拠ではない。検証は必ず自分のツール実行で行う
- **執筆役の最終報告は `docs/handoffs/out/<id>_last-message.md` として保存する**。lint の `report_globs` 既定がこの名前を見ており、`self-verification-claim` はここへしか当たらない
- 未発注の検証を騙る行は `docs/handoffs/out/<id>_note.md` へ「不採用」として残すだけにする。訂正を求めるやり取りは費用に見合わない
- 禁止語の列挙は抑止として書くが、効果は限定的と理解しておく

**同じ基準を自分へ適用する。** 特に**「実行できる」を「実行した」と書く**型 —— 計測可能だと確認しただけで実測値のない記録を書く。防ぐには**記録に生の出力を貼る**。要約だけの記録を evidence として採用しない。

**記録に「変わる値」を保持しない。** 現在形で残した commit hash・Status・件数は、変更のたびに失効する。実プロジェクトで3回連続で再発した。「未 push 3 commit（hash 列挙）」ではなく「`git rev-list --count origin/main..HEAD` の実測を正とする」と書けば二度と失効しない。保持してよいのは**意図的なスナップショット**（Last Known Good のように「その時点で検証した」という宣言）だけ。履歴行に旧値が残るのは正しく、**現況値へ上書きするのは過去の改変**。

## 12. commit と baseline

**commit を暗黙の権限にしない。** 開始時に許可範囲を確認して記録する。許可があれば品質合格した作業単位ごとに commit し、溜めない。無ければ commit せず sha256 pin とスナップショットで baseline を固定する。これは一般の作業履歴規則であり、D4-CAND/B0/P0-CAND/B1/B2 の W0 handoff lifecycle v1 は、外部VCS operation proofをまだ定義しないため**人間がcommitを許可していても snapshot-only**。`revision.kind: commit` はW0対象にせず停止する。

実プロジェクトでは許可確認を先送りしたまま変更を溜め、最終監査で Last Known Good Commit が空文になった。

未 commit 期間の代替: 是正前に必ずスナップショットを取る（`docs/handoffs/out/<id>_pre_correction_*`。**untracked ファイルには `git checkout` が効かない**）。baseline は `schemas/baseline_manifest.schema.json` に従う manifest 全体 hash で pin する。

baseline は lineage を持つ。**同じ ID の bytes を変更しない。**

- **D4-CAND-n**: initial D4 へ渡す候補。失敗候補も immutable 履歴として残し、B0 と呼ばない
- **B0**: full initial D4 に合格した pre-P0 content baseline。合格候補と同一 file-set hash を持ち、`promotedFrom` と3件の完全な audit provenance で結ぶ
- **P0-CAND-n**: P0 改訂後に P0 後 D4 へ渡す候補。parent は B0。失敗候補を B1 と呼ばない
- **B1**: P0 後の全3系統 D4 に合格し、人間が D5 で承認する content baseline。合格候補と同一 file-set hash、parent は B0、3件の完全な audit provenance を保持
- **B2**: D5 metadata・記録同期後の W0 引渡し baseline。parent は B1。製品仕様bodyはB1と同一で、差分は formal header/change-history、運行記録の追記、最初のWP authorization、生成物という明示allowlistだけ

P0 では、編集前の B0 と編集後候補をそれぞれ `docs/evidence/baselines/<baseline-id>/` 配下の別 manifest／snapshot rootとして保存する。対象・不変対象の path/version/status/bytes/sha256、source snapshot ID、parent baseline ID を記録する。W0 lifecycle v1 の全 candidate/baseline は project-relative `snapshotRoot` 配下の全bytesを receiver が再計算できる snapshot-only 契約とし、commit blobへfallbackしない。snapshot memberは独立fileでなければならず、symlink／junction／reparse point／hardlinkを禁止し、link count 1・snapshot内identity重複0・canonical/staging sourceとのOS file identity交差0を外部claimsとreceiverが検証する。freeze/seal時はsnapshot root全fileのsource/result path・before/after hashをcomplete write logと外部actual-operation claimsがexact-coverする。manifest file 自身の SHA-256 は自己参照 field にせず、Stage Transition Record と後続 handoff package から外側で束縛する。P0 後 D4 合格後だけ候補を B1 へ昇格する。

D5 は B1 全体を rollback可能な immutable snapshot として保持し、全出力を staging で生成・検証してから crash journal 付きで置換する。許可差分は formal header metadata、template が規定する DECISIONS/CHANGELOG の exact sentinel block、PROGRESS の exact current-state replacement＋history block、first WP の exact authorization fields、生成 index/manifest/hash packageだけ。GDDもGate1対象のDraft bytesからfixed metadataだけを更新し、normalized body digestは不変。自由文や同じ block 内の追加 field は不可。失敗時は B1 へ全件復元し、部分 `Approved` を残さない。D5 verification後に全sync write、allowed-diff/post-sync artifact、B2 snapshot全file copyを記録し、B2 manifestを1回sealする。成功後、B2外にD5 lifecycle transition attestationと外部actual-event provenanceを固定し、verification前write 0、event-level allowlist、snapshot完全性、seal後write 0、post-sync/B2 hashを再検証してから必須 W0 handoff packageを生成する。challenge/capture/PVのevidence取得writeはmutation scope外、LTA/writeLog/PV/W0 packageだけがmonitor close後の固定proof-sealing除外であり、他の除外は許さない。外部authorityがactual operation eventsを証明できなければW0へ進まない。

許可済み commit のメッセージには変更内容に加えて**独立照合の結果**（巡数と記録パス）と、人間承認が必要な gate ならその決定 ID を書く。**照合合格だけを「承認済み」と表現しない。**

**push は commit と別権限。** remote と branch を示して明示承認を得る。production へ連動する CI を持つ branch や公開リポジトリは安全境界として台帳へ送る。

**rollback の到達点を1つだと思わない。** local の検証済み commit / remote の published ref / 製品 rollback の対象（Place・DataStore）/ 文書 rollback の基準（直前の承認済み revision）は**別物**。混同した記述が Major 指摘になった。

## 13. 正本の所有表

**同じ話題を2箇所に書かない。** 迷ったらこの表で所有先を決める。

| 話題 | 正本 |
|---|---|
| 絶対規則・自律化しない線・承認主体 | `references/absolute-rules.md` |
| 各 phase の定義・D0 質問・D5 成立条件・release 側へ送る非blocking条件 | `references/phase-definitions.md` |
| 正本境界（どの文書が何を所有するか） | `references/document-system.md` |
| 機能 → 必須仕様書 | `references/trigger-matrix.md` |
| 承認ゲートの逐条・**状態タグの定義**・変更伝播 | `references/quality-gates.md` |
| 出力配置・命名 | `references/output-layout.md` |
| Roblox 固有の完備性 | `references/roblox-readiness.md` |
| BROWNFIELD 監査 | `references/repository-audit.md` |
| **D4 監査の実行手順** | `references/audit-d4.md`（観点は `audit-dimensions.md`、書式は `findings-report.md`） |
| **P0 の作業単位** | `references/p0-work-units.md` |
| **P0 の gate 設計** | `references/p0-gate-design.md` |
| **P0 の承認記録・状態検査** | `references/p0-approval-and-state.md` |
| **P0 の手戻り14種** | `references/p0-rework-catalog.md` |
| worker のクラス判定・責務名・転記プロトコル | `references/worker-registry.md` |
| 外部送信承認・context bundle・attestation | `references/execution-envelope.md` |
| 実行面の使い分け・実測・exec 分類 | `references/autonomous-execution.md` |
| D0 intake と GDD の運び方 | `references/gdd-and-intake.md` |
| 執筆順序と所有境界の詳細 | `references/ordering.md` |
| 巡ごとのスコープ・発散判定 | `references/review-protocol.md` |
| 再発欠陥28種 | `references/defect-catalog.md` |
| lint 設定の記入例 | `references/config-example.md` |

**stage router（§4）・handoff 必須項目（§8）・機械検査コマンド（§9）は SKILL.md が所有する。** reference 側で再定義しない。

## 14. 参照ファイル

### references/（24本）

**体系**: `absolute-rules` / `phase-definitions` / `orchestration` / `document-system` / `trigger-matrix` / `quality-gates` / `output-layout` / `roblox-readiness` / `repository-audit`

**D4 監査**: `audit-d4` / `audit-dimensions` / `findings-report`

**P0**: `p0-work-units` / `p0-gate-design` / `p0-approval-and-state` / `p0-rework-catalog`

**運行**: `worker-registry` / `execution-envelope` / `autonomous-execution` / `gdd-and-intake` / `ordering` / `review-protocol` / `defect-catalog` / `config-example`

### templates/（90本）

- **handoff / audit 系**: `handoff.md` / `correction_handoff.md` / `gdd_handoff.md` / `d4_audit_policy_manifest.json` / `d4_runtime_allowlist.json` / `d4_capsule_assembly_attestation.json` / `d4_audit_capsule.json` / `d4_audit_request.json` / `d4_auditor_attestation.json` / `d4_findings.md` / `d5_approval_handoff.md` / `review_round1.md` / `review_roundN.md`
- **P0 系**: `p0_start_handoff.md` / `cr_draft.md` / `approval_record.md` / `revision_handoff.md` / `contract_approval.md`
- **文書テンプレート**: `gdd.md` / `detailed_design.md` / `data_definition.md` / `ui_ux_input_spec.md` / `phase_plan.md` / `work_packages.md` / `test_spec.md` / `toolchain_spec.md` / `workflow.md` / `release_rollback_runbook.md` / 各 Spec / 記録類（`decisions.md` / `human_actions.md` / `ai_actions.md` / `progress.md` / `changelog.md` / `asset_todo.md` / `claude_md.md` / `docs_index.md`）
- **機械運行**: `baseline_manifest.json` / `gate_approval_record.json` / 共通 `human_approval_{challenge,presentation,capture}.json`・`human_interaction_transcript.json` / `required_specs.json` / `d15_measurement_evidence.json` / 各 `provenance_verification*.json` / `provenance_verifier_config.json` / `trusted_runtime_query_result.json` / `pinned_signature_evidence.json` / P0・D5の `lifecycle_transition_attestation_*.json`・`lifecycle_write_log_*.json` / `post_sync_manifest.json` / `w0_handoff_package.json` / W0の `w0_runtime_{launch_challenge,prepare_execution_attestation,prelaunch_assertion,postexecution_attestation,admit_execution_attestation}.json` / `w0_run_authorization_{challenge,presentation,capture}.json` / `w0_run_authorization.json` / `w0_run_admission_attestation.json`
- **設定・intake**: `doc-lint.json` / `p0-check.json` / `intake.json`

### schemas/（43ファイル）

37 schema: `docs_manifest` / `intake` / `required_specs` / `work_package`、baseline／approval／D4 policy・runtime・capsule・request・attestation、D1.5、external provenance／operator config、P0・D5 lifecycle transition／write log、post-sync／W0 package、W0 runtime launch／PREPARE／prelaunch／postexecution／run authorization／run admission／ADMIT execution-worker-ready receipt、D2用 `remote_contract` / `save_schema` / `analytics_event` / `asset_ledger` / `commerce_ledger`。これにD2の5 starter instanceと `requirements.csv` を加えた43ファイル。starterが空の間はD2成果物として合格しない。

### checklists/（5本）

`consistency` / `production_readiness` / `clean_room` のD4節と `security` のcontract節を3 laneで使う。`completion` は pre-D4、指示役の3 lane集約、P0/D5、W0以降を節分離しており、後工程の証拠をD4合格条件へ逆流させない。

### scripts/（18本）

| script | 用途 |
|---|---|
| `lint_docs.py` | 文書 lint（照合より先に実行） |
| `gen_index.py` | docs index / manifest の生成 |
| `validate_docs.py` | 体系 validator（gate 指定） |
| `validate_traceability.py` | traceability CSV 検査 |
| `check_p0_state.py` | P0 の跨文書状態検査 |
| `validate_d5_acceptance.py` | B0/B1/B2・D5承認・許可差分・W0 package のfail-closed検査 |
| `validate_lifecycle_transition.py` | post-P0 D4用P0 outer transitionの固定検査entrypoint |
| `state_readiness.py` | active state tag／placeholder の共有fail-closed parser |
| `strict_json.py` | security-sensitive JSONのduplicate key／NaN／Infinity拒否共有loader |
| `d4_preflight.py` | D4 capsule用の固定 SOURCE-STATE／REVISION／TREE preflight |
| `w0_receiver_bootstrap.ps1` | operator外部authority監視下のW0 PREPARE→VALIDATE→ADMIT bootstrap |
| `scaffold_project.py` | 新規プロジェクトの雛形生成 |
| `detect_triggers.py` | intake から必須 Spec を判定 |
| `grep_residuals.py` | 残留プレースホルダの検出 |
| `build_context_bundle.py` | Class B 向け context bundle 生成 |
| `check_skill_seams.py` | 本 skill 内の契約と、残る2 skill との接続の検査 |
| `test_regressions.py` | lint / manifest の回帰テスト |
| `test_context_bundle.py` | context bundle の回帰テスト |
