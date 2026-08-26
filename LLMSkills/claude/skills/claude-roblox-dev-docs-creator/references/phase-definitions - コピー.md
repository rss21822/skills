# E0・D0〜D7 の定義 — 各 phase が何を作り、何で閉じるか

本書は **phase の定義**（何を作るか・何を満たせば閉じるか）の正本。**運び方**（執筆順序・handoff・照合スコープ）は SKILL.md と `ordering.md` / `review-protocol.md` が所有する。両者を混ぜない。

`workflow.md` として別置きされていた D0〜D7 の詳細も本書へ統合済み。

## E0 — capability preflight

D0 より前に、実行面と候補 worker の能力を固定 probe で確認する。**project 内容を含まない worker probe は E0 の外部送信であり、D0 の文書制作ではない。** provider・account・model・cost・送信内容の承認を先に得る。D5/W0 full routeには、後続の全W0-bound proofを生成時点からoffline `pinned-signature` modeで発行できるoperator管理authority／trust anchorを既知test claimで検証する。query-only adapterは限定到達点には使えてもW0証拠へ後変換できないため、signature probeが失敗したらD0前にfull routeを停止する。project内の自己申告設定、local ID/hashだけでは合格にしない。

結果は `docs/handoffs/out/E0_capability_probe.md` へ生出力つきで保存し、使用者が執筆役・照合役・到達点を選ぶ材料にする。E0 は製品判断を作らず、intake を承認せず、失敗した候補を自動 install しない。詳細は `autonomous-execution.md` §2 と `worker-registry.md` §3。

## 0. モード判定

着手時に4つのどれかを確定する。不明なら質問する。ユーザーが既存ファイルを示した場合は BROWNFIELD または AUDIT を優先する。

| モード | 内容 |
|---|---|
| GREENFIELD | 新規ゲーム。コンセプトから文書体系を作る |
| BROWNFIELD | 既存ゲーム／既存リポジトリへ文書や機能を増補する |
| AUDIT | 既存文書体系が AI 実装可能か監査する（→ `audit-d4.md`） |
| SUB-SPEC | 承認済み体系へ領域特化仕様書だけ追加する（→ D7） |

## 1. D0 — コンセプト／技術ヒアリング

**D0 では外部 worker を起動しない。** E0 の固定 worker probe は既に終了している。D0 ではユーザーへ製品質問と技術質問をまとめて提示する。既に回答済みの項目は再質問しない。

事前記入と出所分類（`U` / `W` / `M` / `J`）の運び方は `gdd-and-intake.md` が所有する。本節は**質問項目そのもの**を所有する。

### D0-A 製品質問

1. 一言コンセプトと一動詞
2. 参照ゲーム2〜3本、取る点／捨てる点
3. 独自軸3点以内
4. 1ラウンド／1セッション時間
5. キャラ・機体・クラス等の枠とカスタムスロット
6. ラン内ループ、メタループ、収集対象
7. 収益方針、P2W、RNG、Trading
8. IP・実在物・政治・史実リスク
9. 最大の操作・物理・ネットワーク・供給リスク
10. MVP で検証する問い3つ
11. 端末優先度、モバイル操作予算、最低性能
12. Non-Goals 候補

### D0-B 技術・運用質問

1. Greenfield か既存リポジトリか
2. Studio 中心、Rojo、その他の Toolchain
3. Universe／Place 構成
4. Group 所有、dev／staging／production の分離
5. 対応端末、最低 FPS・Memory 目標
6. 永続化するデータ
7. PvP、通貨、取引、課金、ランダム報酬
8. Teleport、Reserved Server、Matchmaking
9. 外部 API、Open Cloud、Secrets
10. UI、入力、Localization、Accessibility
11. 既存アセットと権利状態
12. 人間しか行えない Dashboard／Studio 作業
13. Release 頻度、LiveOps
14. 障害時の停止・Rollback 要件
15. 既存コード・文書・テストの信頼度

未回答には `[PROPOSAL]` を付けた提案値を出し、確認を得る。確認後に `intake.json` へ `[DECISION]` として固定する。**確認なしに `[DECISION]` へ昇格しない。**

### D0 停止条件

製品 thesis・主要リスク・MVP の問い・端末優先度は、使用者の確認なしに確定しない。

## 2. BROWNFIELD 追加手順

既存プロジェクトでは D1 の前に Repository Audit を行う。詳細は `repository-audit.md`。

1. Repository tree、Place mapping、依存関係、Build/Test コマンドを確認する
2. 既存 CLAUDE.md、設計書、Config、Remote、DataStore、Commerce、Analytics を棚卸しする
3. 事実・推測・欠落を分離する
4. Legacy 名、宙に浮いた参照、Production 接触経路を記録する
5. `repository_audit.md` と Gap Map を人間へ提示する
6. **増補範囲を承認されるまで既存正本を変更しない**

## 3. D1 — GDD 生成と人間承認ゲート①

選定 worker へ責務名 `product-gdd-writer` を割り当て、D0 回答と GDD テンプレート（`templates/gdd.md`）を渡す。

**責務名は固定プラグイン名ではない。** 使用者が指定した worker がその責務を assume する。担い手の決め方は `worker-registry.md` が所有する。**執筆 worker を確保できない場合は blocker として停止し、指示役を正本執筆の fallback にしない。**

必須条件:

- 一言、対象、Visceral Core、一動詞
- 取捨表、独自軸、コアループ、メタループ
- MVP と将来機能の境界
- Non-Goals 6件以上、理由つき
- `D-n`／`F-n`、切替条件、決定権者
- 測定可能な成功指標。ただし**数値正本はデータ定義書へ参照化**
- OQ とブロッキング有無
- 収益・権利・年齢表現の方針

exact Draft GDD の path/hash/revision と、同じ時点のapproved intake path/hash、intakeから再導出したrequired specs path/hashをclosed `gdd-gate1-v1` scopeへ固定して提示し、人間本人から challenge の canonical response による明示承認を得る。trusted interaction transcript、exact statement artifact、`human_approval_capture.json`、operator-pinned external query/signature `provenance_verification`、type `gdd-gate1` の machine gate recordを順に作り、相互hashと内容を検証する。required specsはapproved intake bytesからreceiverが再生成してexact一致させる。外部proofを作れなければ承認未確認として停止し、D1.5 / D2 へ進まない。

Gate 1 承認は「このapproved intake／required-specs projection／exact Draft GDD revisionを D1.5 / D2 の入力にしてよい」という工程承認。`DECISIONS.md` の人間向け正本記録とmachine gate recordは同じID・対象・approver・authority timestampへ解決し、gate recordの`sourceEvidence`はcapture、`sourceVerification`は外部proofのpath/hashと一致する。local hashはbyte bindingに限り、人間真正性はoperator外部configへpinしたchannel queryまたは署名trust anchorで検証する。GDD headerはB1まで `Status: Draft` のままbyte-immutable。D5 external verification後のfixed metadata-only transformationだけがB2で `Approved` / `Last approved` / exact historyを設定し、receiverはB1/B2 normalized body digest一致を再計算する。

## 4. D1.5 — Feasibility Gate

次のいずれかを含む場合、設計文書一式より先に小さな技術検証を作る。

- 新規モバイル騎乗・飛行・船舶操作
- 大量破壊、大量 NPC、大規模物理同期
- EditableImage、自由描画 UGC、4D 生成
- 複数乗員 Vehicle、複雑な Network Ownership
- 高頻度 Projectile、サーバー権威の高速 PvP
- 未検証の Multi-Place／Teleport 構成

Feasibility Report には、仮説・最小実装・測定条件・端末・**合格閾値**・結果・D/F 判断を記す。machine-generated required specs は、approved intake でtrueの5 technical flag（custom physics、high load、free text/UGC、high-frequency projectile/fast PvP、multi-place）だけから、source/value hash付きのsorted `requiredSubchecks` とそのdigestを導出する。free-form `product.top_risks` はD3/D4のrisk registryで扱い、D1.5 machine subcheckへ自動変換しない。D0独立reviewは、measurable mechanic riskに対応するtechnical flagがtrueでなければintakeへ差し戻す。GDDが新しいhigh-risk仮説を追加するなら、先にintake/GDDを更新してGate 1を取り直し、inventory外の仮説を黙って除外しない。現schema versionでは、`feasibility_report` trigger があれば、このexpected setを1つのcombined gate experimentとしてexactly 1件作る。bindingは `triggerId: feasibility_report`、`experimentId: feasibility_report-combined-v1` に固定する。evidenceのsubcheck IDはrequired setを重複・欠落・余分0でexact-coverし、各rowが固有のtrial／pre-fixed threshold／raw-output artifact path・実SHA-256、個別result、canonical row digestを持つ。top-level bundleだけで個別証拠を代替しない。combined resultは全必須subcheckがPASSの場合だけPASS。operator管理の外部configへpinされたruntime queryまたは署名で、その1 evidenceに対する `provenance_verification` を作る。proofはtarget Studio/Place/session/datamodel、experiment/trigger ID、subcheck-set digest、各subcheck evidence digest集合、request/command hash、result、tool/runtime IDs、開始/完了時刻を束縛する。trigger が無ければbinding/proofは0件。別々のexperimentへ拡張する場合はschema versionを上げ、required experiment registryを追加するまで現gateへ混在させない。外部proofを作れない実測をPASSにしない。

**閾値は計測前に固定する。** 事後変更を禁じる。判定は PASS / FAIL / INCONCLUSIVE の3値。不合格なら上流 GDD を改訂し、再承認する。**失敗した前提のまま下流文書を量産しない。**

実測手順は `autonomous-execution.md` §4 が所有する。

priority device の実機が無い場合、端末固有の性能・発熱・入力・実回線を問う仮説は `INCONCLUSIVE` とし、PASS にしない。仮説が端末固有差へ依存しないことと代替環境を**計測前に**記録した場合だけ、その限定範囲で PASS を出せる。記録は「Studio／simulator 範囲の PASS」とし、実機 PASS と表現しない。

## 5. D2 — 技術体系生成

承認済み GDD、Repository Audit、Feasibility 結果を入力にする。独立可能な領域は並行化してよい。

責務名の割り当て（いずれも使用者指定 worker が assume する）:

| 責務名 | 対象 |
|---|---|
| `system-architect` | 詳細設計、モジュール境界、依存方向、Place topology |
| `data-economy-writer` | 数値、経済、Config、検算表 |
| `ui-input-writer` | UI、画面遷移、入力、端末、Accessibility |
| `platform-security-writer` | Remote、権威、保存、課金、Policy、Analytics 基盤 |

**`trigger-matrix.md` を必ず適用し、該当補助仕様書を生成する。条件を満たした仕様書を「任意」として省略しない。**

文章だけでなく、該当する機械可読**instance**を作る: Remote contracts / Save schema・Migration table / Analytics event dictionary / Asset ledger / Commerce ledger。各 instance を対応する JSON Schema で検証し、空 instance や schema ファイルだけを「契約生成済み」と数えない。Document manifest は D2 本文を手書きせず generator で作る。

Markdown Spec は意味・所有者・failure policy、機械可読 instance は field / type / ID / enum の実装入力を所有する。同じ値を双方に持つ場合、Markdown は instance の ID を参照する。標準 path と境界は `document-system.md` §Machine-readable contracts が正本。

執筆順序（所有者を先に、消費者を後に）は SKILL.md §6 と `ordering.md` が所有する。

## 6. D3 — 実装・テスト・運用文書

選定 worker へ責務名 `dev-process-writer` を割り当て、D1〜D2 の全文書を渡して次を生成する。

1. 実装フェーズ計画
2. Work Package 仕様
3. テスト仕様
4. Toolchain／Repository 仕様
5. CLAUDE.md
6. WORKFLOW.md
7. Release／Rollback Runbook
8. PROGRESS.md
9. ASSET_TODO.md
10. HUMAN_ACTIONS.md
11. AI_ACTIONS.md
12. CHANGELOG.md
13. DECISIONS.md
14. Traceability Matrix
15. 設計フィードバックリスト

各 Work Package は**1セッションで完了可能な大きさ**にし、対象ファイル・変更禁止範囲・入力・出力・公開 Interface・自動テスト・Studio 検証・性能確認・Rollback・Done 条件を持たせる。

設計フィードバックは該当執筆者へ戻す。同一問題カテゴリの2回目、または承認済み製品方針を変える問題は人間へエスカレーションする。別カテゴリの新問題は、承認範囲内なら追加修正できる。

## 7. D4 — 3系統監査

**本節は D4 の定義（誰が何を見て、何で合格とするか）を所有する。実行手順は `audit-d4.md` が所有する。**

監査者は修正しない。指摘を元執筆者へ差し戻す。

| # | 責務名 | 見る対象 |
|---|---|---|
| 1 | `consistency-auditor` | 二重正本、参照切れ、矛盾、未解決状態、変更伝播 |
| 2 | `roblox-readiness-auditor` | Remote、保存、性能、UI/Input、課金、Policy、権利、公開、安全 |
| 3 | `clean-room-auditor` | 過去会話を知らない AI が D5 authorization 後に最初の candidate WP を追加製品判断なしで W0 へ渡し、W0 provenance/permission gate後だけ開始できるか |

**3系統すべてが必要。** 1系統だけで全体の Critical 0 / Major 0 や D4 合格を宣言しない。

合格条件は3系統すべてで **Critical = 0 かつ Major = 0**。そこへ至るまで再監査する。軽微修正も変更履歴へ記録する。

initial D4 は immutable `D4-CAND-n` を監査し、3系統合格後に**同じ file-set hash のまま** B0 へ昇格する。監査 raw report は候補 ID を指したまま無編集保存し、B0 へ書き換えない。

initial candidate に残せる未決は、canonical operating file `PROGRESS.md` § Proposed P0 closure inventory へ完全列挙され、source ID/path・正確に境界づけた P0 closure question/scope・owner・closure evidence/pass rule・影響正本が明確な項目だけ。この台帳は candidate と同じ file set で B0 に固定し、代替案は P0 の CR 起草で作る。未決が実際に無い場合は inventory 0 行でもよいが、初回 D4 が未決 0 を一律要求して P0 closure を先取りしない。0 行でも P0 の既存契約検証・契約承認記録・管理WP遷移・candidate固定は実行する。post-P0 candidate では blocking open・proposal・未検証 assumption を 0 にし、B0 historical inventory の全 ID を Completed record・actual evidence・影響正本の post-change hash へ一対一で解決する。

出口語彙は `D4合格 / P0着手資格あり（人間P0開始承認待ち）`。これはP0開始承認を求められる資格判定であり、P0作業のauthorizationではない。**`実装に入れる` / `implementation ready` は使わない**（D5 前のため）。

各監査は clean context で起動する。起動機構は SKILL.md §4 の stage router が所有する。

## 8. P0 — contracts / bootstrap

**D4 合格後、D5 の前に実行する。** P0 は D5 の前提工程であり、D5 承認そのものではない。P0 内の `[AI-APPROVED]` は D5 を満たさない。**P0 は formal document の `Status` / `Last approved` を変更しない。**

開始前に、D4 合格済み **B0** を対象とする人間の P0 開始承認を得る。`templates/p0_start_handoff.md` で B0 ID/hash と許可 scope を提示・記録する。operator-pinned external authorityの監視をpresentation前に開始し、canonical source-baseline projection/file-setがB0と一致すること、canonical-project／private-staging／result-artifactsの3対象のinclude set上actual before-state、全in-scope mutation scopeを証明する。製品内容の変更は B0 historical closure inventory 行だけ、常に許可する手続は既存契約の検証・承認記録・P0管理WP遷移・candidate固定だけと分離する。ただし Gate 1 承認済み intake、そこから再導出したrequired specs、GDD、Gate 1 chain は inventory の対象外かつ immutable。変更が必要なら P0 で閉じず、D0/D1 → unique new Gate 1 → D1.5/D2/D3 → new initial D4/B0へ戻す。inventory 0 行なら製品内容の変更を0件のまま、規定済みP0手続だけを実行する。P0 開始承認 ID は P0 契約承認・D5 承認 ID と分ける。

作業単位・gate 設計・承認記録・状態検査は `p0-work-units.md` / `p0-gate-design.md` / `p0-approval-and-state.md` が所有する。P0 改訂後はsnapshot-only `P0-CAND-n` を固定し、candidate/B1外の lifecycle transition attestationと外部provenanceで、P0-start verification後の全pre-approval write、approval payload作成、P0-contract verification後の固定metadata、snapshot全file freeze、actual-candidate machine record、exact frozen-byte canonical apply、final seal、未記録書込み0、seal後書込み0、実結果hashをauthority側actual eventsから証明する。B0→candidate の D4 差分再監査で Critical = 0 / Major = 0 を確認し、両方を満たす candidate だけ同じ file-set hash のまま **B1** へ昇格してD5へ提示する。

P0 core の出口は `post-P0 D4待ち`。post-P0 D4 合格と B1 昇格までを含む P0 route 完了時点の結論は `D5提示可能` まで。

## 9. D5 — 人間承認ゲート②

### 汎用の成立条件

次をすべて満たしたときだけ「W0引渡し可能 / 実装契約承認済み」とする。これは code／Studio／OS／外部送信の side effect を許可しない。

- ブロッキング OQ 0
- `[PROPOSAL]` 0、未検証 `[ASSUMPTION]` 0
- 要件トレース率100%
- Required Spec 欠落 0
- Remote／Save／Commerce／Analytics 未定義 0
- test / evidence / pass-fail rule が未割当の Work Package 0（製品テスト実行は W0 以降）
- Human owner 不明 0
- Build／Test／Serve コマンド確定
- B0→post-P0 candidate の3系統同一mode D4（delta、該当時full escalation）がすべて合格し、そのcandidateと同一file-set hashのB1が成立
- Release／Rollback 確定
- 最初の Work Package が新しい製品・契約判断なしに W0 へ引き渡せる
- P0 actual-event transition proofがB0開始状態からsnapshot-only P0-CAND/B1まで、全書込み、snapshot全file、P0-start/P0-contract、post-freeze record、canonical apply、final sealの順序を外部authorityで証明済み

### プロジェクト側 gate registry

プロジェクトの `phase_plan` は D5 条件を追加・強化できるが、上の汎用条件を削除・緩和できない。production release 側へ送れるのは、正本で D5 非 blocking と定義された実装後検証だけ。

`blocking: yes` の OQ に逸脱記録を付けても closure にはならず、D5 は不合格のまま。逸脱記録は owner・期限・production gate・許可範囲を追跡するために使えるが、W0 の authorization を作らない。blocking 分類を変える場合は、人間 `[DECISION]`、影響正本改訂、D4 再監査が必要。

### 承認と同期

ユーザーへ、B0→`P0-CAND-n` 差分監査の合格 candidate から同一 hash で昇格した **B1**、生成ファイル・主要判断・P0 結果・残る Human Actions・最初の Work Package を提示し、**人間本人から直接の明示承認**を得る。委任 AI の `[AI-APPROVED]`、過去の包括委任、無応答は D5 を満たさない。

operator-pinned external authorityの監視をD5 presentation前に開始し、canonical source-baseline projection/file-setがB1と一致すること、canonical-project／private-staging／result-artifactsの3対象のinclude set上actual before-stateと全in-scope sync scopeを固定する。直接承認のexternal verification完了後だけ、**同じ変更単位で**対象 formal document の `Status: Approved`・`Last approved`・change history・`DECISIONS.md` を同期し、docs index／manifest を再生成する。GDDはGate1が承認したB1 Draft bytesからfixed metadataだけを変え、normalized body digestを維持する。手順は `templates/d5_approval_handoff.md`。B1→B2 は許可済み metadata・承認記録・最初の WP authorization だけの差分でなければならない。同期、allowed-diff/post-sync生成、B2 snapshot全file copyを全てmonitor内で記録し、B2 manifestをfinal sealとして1回だけ作る。同期後はB2外のlifecycle transition attestation／外部provenanceで全in-scope actual event・未記録書込み0・許可差分・snapshot完全性・seal後書込み0・B2結果を証明する。**この D5 verification より前に formal document を Approved へ昇格させない。外部operation proofが無ければW0へ進まない。**

## 10. D6 — 実装 Bootstrap と継続同期

承認後、ユーザーが実装開始を依頼した場合のみ受領 skill を起動する。実装そのものは `claude-roblox-mvp-buildout`（通し実装）または `claude-roblox-development-delivery`（単発 WP）が担う。受領側はoperator外部authorityがprocess生成前から監視するPREPAREの署名proofとprelaunch assertionを検証してからだけVALIDATEを行い、W0 packageの全provenanceをoffline pinned-signature modeで検証する。query-mode/network adapterは送信権限取得前なのでSTOP。同じrunのsigned postexecution後もproject/source/temp lockを解放せず、current B2/package/WP、machine-derived frozen/disjoint write paths、receiver Skill tree、expected process closure、worker、transfer、operation、denial、expiryをexact提示した人間run authorizationをoperator-external証拠として作る。pre-ADMIT signed admissionはexpected factsとactive enforcementだけを束縛する。2回目のsemantic validator PASS後、authorityがtokenを期限内に原子的消費してworkerをsuspended/pre-entry起動し、actual closure一致・zero effect・continuous lock・未使用の短期worker-ready capabilityをsigned receiptへ束縛する。bootstrapがreceipt/signatureを検証してPASSし、authorityがcapabilityを最初のeffect直前に原子的消費するまでside effectを始めない。

1. 一度に1 Work Package だけ着手する
2. 変更前に対象ファイルと禁止範囲を再確認する
3. Test-first または契約-first で実装する
4. 完了時にコード・テスト・PROGRESS・CHANGELOG・Traceability・影響仕様書を**同時更新**する
5. Last Known Good Commit を記録する
6. **WP 外の改善を発見しても実装せず**、DECISIONS／Backlog へ記録する
7. Production 公開や Dashboard 操作は HUMAN_ACTIONS へ送る

## 11. D7 — 補助仕様・変更要求

承認済み体系への追加は、選定 worker へ責務名 `sub-spec-writer` を割り当てる。

1. Change Request を作る
2. 影響文書一覧を出す
3. 暫定正本が必要なら期限・取込先を宣言する
4. 上流正本へ取り込んだ後、暫定節を取込済み記録へ変える
5. 影響するテスト、Work Package、Traceability を更新する
6. **D4 監査を再実行する**

## 12. 各 phase の報告

各 phase 完了時に次を1段落で報告する。

- 作成・改訂ファイル
- 確定した重要判断
- 発動した Trigger Spec
- 重大リスクと D/F
- Human Action
- 次の承認または次の phase

**行数は参考情報に留め、品質合格の根拠にしない。**
