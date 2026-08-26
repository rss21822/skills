# stage 連携 — 本 skill の内部 stage と、外部 skill への引き渡し

本書は **stage 間の前進条件と、外部 skill への引き渡し契約**を所有する。**stage router（どの機構で起動するか）は SKILL.md §4 が所有する。** 本書で再定義しない。

体系定義（各 phase が何を作るか）は `phase-definitions.md`。

## 1. stage 地図

```
   E0  capability preflight        本 skill 内（製品内容なしの固定 probe）
                                │
   D0 ─ D1 ─ D1.5 ─ D2 ─ D3      本 skill 内（文書制作）
                                │
   D4  3系統受入監査             本 skill 内。ただし clean context で起動
                                │
   P0  契約確定 → post-P0 D4     本 skill 内。delta/full escalation後のB1成立がD5の前提
                                │
   D5  人間承認 + 状態の原子的同期  人間本人の明示承認が必須
                                │
   W0 ─ W1 ─ W2                 claude-roblox-mvp-buildout（別 skill）
        （単発 WP・局所修正だけ claude-roblox-development-delivery）
```

**full route は必ず E0 → D0→…→D3 → D4 → P0 → post-P0 D4 → D5 → W0 PREPARE→VALIDATE→run authorization→ADMIT semantic PASS→signed admit-execution/worker-ready receipt→bootstrap PASS。** post-P0 D4 は B0→candidate の3系統差分再監査で、影響範囲を限定できない場合は full D4 へ昇格する。P0 の契約承認、WP の `Verified`、AI による品質判定を **D5 の人間承認として扱わない**。D5 前に「W0引渡し可能」と書かない。D5 後も実 side effect はoperator外部監視下のpackage再検証、closed run固有権限、expected-only signed ADMIT、token消費後のsuspended/pre-entry actual-closure照合、signed receipt検証、bootstrap PASS、短期worker-ready capabilityの原子的消費まで始めない。

**W0 以降の実装 skill は `claude-roblox-mvp-buildout` だけ。** `claude-roblox-development-delivery` は、依頼自体が単発 WP・局所修正・不具合診断の場合だけ選ぶ。full 実装と同時発火させない。MVP 実行中に局所作業へ委譲する場合も、MVP の権限・worker・送信・baseline 契約を上位契約として明示継承する。

## 2. 到達点を最初に宣言する

E0 probe 後に使用者へ確認し、`docs/handoffs/out/E0_capability_probe.md` へ記録する。D5→W0 full routeを選ぶなら、後続の全W0-bound provenanceを生成時点からoffline `pinned-signature` modeで固定できるoperator外部authority／trust anchorをE0で実probeする。query-only構成は後でimmutable baseline内のproofを変換できないため、D0へ入る前に限定到達点へ変更するか停止する。

| 宣言 | 終点 | W0引渡し | 実 side effect |
|---|---|---|---|
| `docs` | D3 完了 | 不可 | 不可 |
| `audit` | D4 合格 | 不可 | 不可 |
| `contracts` | P0 core完了 + post-P0 D4合格 + B1成立 | 不可 | 不可 |
| `ready` | D5 完了（明示承認＋状態同期） | 可 | W0 PREPARE→VALIDATE・closed run authorization・signed ADMIT/receipt・bootstrap PASS待ち |
| `full` | W2 完了 | D5完了後に実施済み | 各WPのW0/W1 gate後だけ |

未指定時は `audit` を提案する。延ばすときは使用者の指示と変更時点を `DECISIONS.md` へ追加する。**黙って延長しない。**

## 3. 入口判定

| 現状 | 入口 |
|---|---|
| 何も無い | D0（GREENFIELD） |
| GDD だけある | D0 差分を先に取る |
| 動くゲーム／repo がある | Repository Audit を D1 前に（BROWNFIELD） |
| **他者作成の文書群がある** | **D4 監査から。正本を先に書き換えない** |
| B0 成立、P0 未着手 | P0開始承認 → P0 |
| P0 core完了、B1 未成立 | post-P0 D4（delta / 必要時full escalation） |
| B1 成立、D5 未承認 | D5 |
| D5 承認・状態同期済み | `claude-roblox-mvp-buildout` へ |

入口判定は**実ファイル・承認記録・baseline・`git log`／snapshot manifest** で行う。ファイル名や会話上の申告だけで stage を飛ばさない。

## 4. baseline lineage

baseline 名は工程の意味を固定する。候補を合格前に B0/B1/B2 と呼ばない。

| 名称 | 内容 | 昇格条件 | 次の用途 |
|---|---|---|---|
| `D4-CAND-n` | D3 完了後、full D4 に出す immutable file set | なし。監査候補 | 3系統 full D4 |
| **B0** | 最後の `D4-CAND-n` と同一 hash の pre-P0 file set | 3系統 full D4 で Critical 0 / Major 0 | P0 開始承認の対象・P0 parent |
| `P0-CAND-n` | B0 を parent とする P0 改訂後 file set | なし。監査候補 | B0→候補の3系統 delta D4、または該当時full escalation |
| **B1** | 最後の `P0-CAND-n` と同一 hash の post-P0 file set | P0 actual-event transition attestation／外部provenanceがB0開始状態・全書込み・承認順序・candidate結果を証明し、B0→候補の3系統同一mode D4で Critical 0 / Major 0 | 人間 D5 承認の対象 |
| **B2** | D5 承認後の原子的同期済み file set | D5 actual-event transition attestation／外部provenanceがB1開始状態・全同期書込み・承認順序・許可差分・B2結果を証明し、validator PASS | W0 handoff / D5 Last Known Good |

各 candidate / baseline lifecycle manifest は baseline ID、parent ID、file allowlist、各 sha256、生成時刻、immutable snapshot ID/root を持つ。W0 handoff lifecycle v1 は全段階で `revision.kind: snapshot` のみを受理し、commit-backed candidate/baselineは外部VCS operation proofを定義する将来versionまで停止する。過去候補を上書きしない。`B0` は `D4-CAND-n`、`B1` は `P0-CAND-n` と**同じ file-set hash**を参照し、監査後の内容変更を混ぜない。

### Historical bytes の再現性

B0/B1 は後続同期で working tree が変わっても、W0 側が全 bytes を再計算できなければならない。

- snapshot baseline: project 内 `docs/evidence/baselines/<id>/snapshot/` のような immutable `snapshotRoot` に対象 bytes を**独立fileとしてコピー**し、全 path は project-relative にする。symlink／junction／reparse point／hardlinkは禁止し、各snapshot fileはlink count 1・相互にdistinctなOS file identity・canonical/staging sourceと別identityでなければならない。元 working pathだけ、alias、Git blob、manifest自己申告値を代用しない
- candidate freeze/B2 sealでは、snapshot rootに作成した全fileをsource/result path・bytes/hash・event IDでwrite logへ一対一に記録し、外部actual-operation claimsとmanifest inventoryが重複・欠落・余分0でexact-coverする。manifestだけを1件記録してsnapshot作成を省略しない
- candidate / baseline lifecycle manifest は source revision / snapshotRoot、各 file bytes/hash、file-set hash を記録する。自身を `files` / file-set hash に含めず、その manifest sha256 は外側の audit report・promotion/transition record・handoff package が束縛する
- W0 handoff 時、manifest の自己申告値を信用せず source blob / snapshot bytes から全 hash と file-set hash を再導出する。1件でも欠落・不一致なら停止する

candidate raw report と昇格記録は historical source を参照し、昇格後に raw report を編集しない。

## 5. 前進条件

前進条件の一覧は **SKILL.md §4** が所有する。本節はそこに書ききれない補足だけを置く。

### D3 → D4

D3 完了内容を immutable snapshot `D4-CAND-n` として固定し、manifest・snapshot全file・対象 hash を3監査系統で共用する。W0 lifecycle v1でcommit-backed candidateは受理しない。GREENFIELD/DOCS routeでは、approved intake・そこから再導出したrequired specs・最終GDD revisionへ解決するGate1 challenge→trusted presentation/response transcript/statement→human capture→external provenance→type `gdd-gate1` machine recordと、該当D1.5 raw evidence→external runtime provenanceも入場証拠として固定する。AUDIT admissionで欠ける場合は合格条件を緩めずfindingにする。

### D4 → P0

出口語彙は **`D4合格 / P0着手資格あり（人間P0開始承認待ち）`**。これはB0を対象にP0開始承認を求められる資格判定で、P0作業のauthorizationではない。`実装に入れる`・`implementation ready` は禁止（D5 前のため）。

D4 は findings-only・read-only。Critical/Major があれば執筆役へ `templates/correction_handoff.md` を発行する。**監査者は正本を修正しない。initial D4の修正後は新しい `D4-CAND-(n+1)` を作り、過去所見を渡さないfresh clean contextで3系統full D4をやり直す。post-P0の修正後は新しい `P0-CAND-(n+1)` を作り、§6のcandidate-derived delta／full escalationをfresh 3系統でやり直す。** 文書単位照合の residual-only 規則を D4 gate 再監査へ流用しない。

3系統すべて Critical 0 / Major 0 の候補だけ、内容を変えず B0 へ昇格する。3 lane は schema-valid な同一 audit capsule を共有し、各 raw response、lane 固有の Class A attestation、operator-pinned external runtime provenance の実 hash を B0 `auditRecords` が束縛する。summary count だけでなく raw findings の Severity／Status、capsule coverage、command evidence、request／response artifact、外部authority claimsを専用 validator が再検査する。

### P0 → post-P0 D4 → D5

P0 開始前に、`templates/p0_start_handoff.md` で B0 とclosed許可scopeのhuman challengeを提示し、人間本人のcanonical responseからtrusted transcript/statement、capture、external provenance、P0-start machine recordを固定する。Gate1／P0-contract／D5と別ID・別message・別proof。外部proofが無ければ開始しない。さらに operator-pinned external authority の監視を presentation より前に開始し、canonical source-baseline projection／file-setがB0と一致すること、canonical-project／private-staging／result-artifactsの3対象についてinclude set上のactual before-state digestを固定すること、session/event IDとscopeが全in-scope transition mutationを覆うことを証明する。別root、部分監視、local write-logの再署名は証拠にならない。P0 は formal document を `Approved` へ昇格せず、Gate 1 が承認した intake bytes、そこから再導出したrequired specs、GDD bytes/path/revision、Gate 1 chainを変更しない。必要なら現 P0 を停止し、D0/D1 → unique new Gate 1 → D1.5/D2/D3 → new initial D4/B0へ戻す。

P0 の外部 lifecycle transition attestation は、P0-start の presentation／response／verification、全 pre-approval write、approval payload digest の実作成、P0-contract の presentation／response／verification、固定 metadata write、`p0-freeze`でのP0-CAND snapshot全file copy、actual-candidate machine record、`p0-apply`でのexact frozen-byte canonical publish、final `p0-seal`を authority 側 actual events の一方向時系列で証明する。candidate bytesはfreeze後immutableだが、machine recordとcanonical applyはfinal seal前の別phaseとして必ず記録する。write log は closed row grammar で全操作の source/result path・before/after hash・rule/source inventory ID・phase・event ID・時刻を持ち、B0 inventory mutation件数と手続書込み件数を分離する。inventory 0行でも手続書込みを隠さない。未記録書込み0、許可scope外0、seal後書込み0を外部claimsから検証できない場合は停止する。

この attestation／外部provenanceを candidate/B1 の外側で固定してから、P0 完了内容を `P0-CAND-n` として検証し、B0→候補の3系統 D4差分再監査を行う。changed file と canonical dependency closure を検査し、影響範囲を限定できなければ full D4 へ昇格する。Critical 0 / Major 0 の候補だけ同一 hash で B1 へ昇格する。**B1 成立後の結論だけが `D5提示可能`。**

### D5

手順は `phase-definitions.md` §9 と `templates/d5_approval_handoff.md` が所有する。要点だけ再掲する。

1. D5 の全条件を実測し、B1 の file tree・canonical 境界・triggered specs・残る Human Actions・最初の WP・validator 出力を使用者へ提示する。blocking OQ は 0 必須。operator-pinned external authority の監視を承認 presentation より前に開始し、canonical source-baseline projection／file-setがB1と一致すること、canonical-project／private-staging／result-artifactsの3対象のinclude set上actual before-state、対象scope／sessionを固定する
2. B1＋first WP＋`w0-handoff-only` scopeのhuman challengeを作り、**canonical responseによるB1を特定した明示承認**を得る。trusted transcript/statement、capture、operator-pinned external provenance、D5 gate recordを順にhash固定し、沈黙・AI 判断・P0 委任・過去の GDD 承認・local self-attestationで代替しない
3. D5 external verification 完了後だけ `templates/d5_approval_handoff.md` を**1便で**実行し、header Status・`Last approved`・change history、docs index・manifest・`DECISIONS.md`・`PROGRESS.md`・`CHANGELOG.md`・最初の authorized WP を**同時同期**する。GDDはGate1が承認したB1 Draft bytesからfixed metadataだけを変更し、normalized body digestを維持する。3 ledger は同 template の固定 sentinel block grammar から機械生成し、自由文を混ぜない。`PROGRESS.md` は履歴 block の追記に加え、既存の一意な current-state fields だけを規定値へ置換する
4. generator・lint・validator・manifest 再生成・全 sha256 を再検査する。B1→同期後差分が次の allowlist だけか専用 validator で確認する。その他 content 差分があれば承認は無効
   - formal header の `Status` / `Last approved`（GDDを含む。ただしGate1-approved B1 bodyはnormalized digestで不変）
   - formal change history の D5 承認行1件
   - `DECISIONS.md` の exact D5 decision block 1件
   - `PROGRESS.md` の exact current-state field replacements と exact D5 history block 1件、`CHANGELOG.md` の exact D5 block 1件
   - 最初の WP 詳細節の Status / `Authorized by` / baseline / evidence と index / PROGRESS mirror（各 field value は exact。D5 ID を部分文字列で含むだけでは不可）
   - generator 出力の docs index / manifest
   - monitor内で作成してeventとして記録する independent post-sync hash manifest、allowed-diff artifact、B2 snapshot全fileとB2 lifecycle manifest。W0 handoff packageはmonitor close後のproof-sealing artifact
5. 合格した同期後 file set をsnapshot-only B2として全file copy eventから固定し、B2 manifestをfinal sealとして1回だけ作る。B2外の lifecycle transition attestation／外部provenanceへ、D5 verification後だけ行われた全actual sync event、allowed-diff/post-sync生成、B2 snapshot全file copy、未記録書込み0、exact allowlist diff、B2 hash、seal後書込み0を固定する。authorityが操作事実を直接証明できなければW0へ進まない

B2 の file set は同期後 canonical set と independent post-sync hash manifest を対象にし、B2 lifecycle manifest 自身と W0 handoff package は含めない。B2 manifest は外側の transition / handoff record、W0 package はその schema validation と package 外の記録で束縛し、自己参照を作らない。

以上が揃った時だけ `W0引渡し可能 / 実装契約承認済み` と宣言する。これは実 side effect の開始承認ではない。受領側ではoperator外部authorityがPowerShell/bootstrap process生成前から監視し、signed PREPARE proofとprelaunch assertionの下でW0 packageとB0/B1/B2 bytesをVALIDATEする。同じrunのactual loaded bytes／argv／exitをsigned postexecutionで確認してもlockとtempを解放しない。run authorizationの`frozenPaths`は人間が選ばず、検証済みW0 packageとpackage自身から、B0/B1/B2 manifest、各`revision.snapshotRoot/files[].path`の物理snapshot member、package、packageから再帰到達する全project-local handoff/proof JSON artifactを受領側が正規化・Unicode ordinal sortしてexact導出する。欠落・余分・Windows alias/casefold/予約名・identity差異は不合格とし、`allowedWritePaths`はその集合とexact/祖先/子孫/file identityのどれでも交差させない。さらにassigned receiverのentrypoint bytesだけでなくinstalled receiver Skill全treeの`receiverSkillTreeSha256`とauthority予定process closureの`expectedLoadedProcessClosureSha256`を、current B2/package/WP、worker、transfer、operation、denial、expiryとともにhuman challenge/presentation/capture/offline signatureへexact提示する。pre-ADMIT signed admissionはexpected scopeとauthority readinessだけを束縛し、worker actual loadを主張しない。2回目のpinned Pythonがsemantic PASS/exit 0した後、authorityがadmission tokenを期限内に一度だけ原子的消費し、workerをscope enforcement下のsuspended/pre-entryで起動する。actual Skill tree/process closure/identityがapproved expected値へ一致し、product side effect 0、continuous lock、ADMIT host/Python actual invocation/read set/result、未使用・短期・global-nonreuse worker-ready capabilityを外部authorityが新しい`w0-runtime-admit-execution-v1` receiptへ署名する。bootstrapはpredeclared receipt/signatureをnative検証してからだけPASSを出し、authorityはその後もexpiry前の最初のeffect直前にworker-ready capabilityを原子的消費してworkerをresumeする。receiver Skill pathはその承認済みreceiver tree内に置くが、project/B0-B2/W0/creator-validator Skill/runtime temp/auth evidence rootsとはidentityまで分離する。proof不足、期限切れ、再利用、direct/early launch、途中cleanupはW0から再実行／停止とする。

host側の`argvSha256`は.NETの`GetCommandLineArgs()`（Windowsのpwshではargv[0]が`pwsh.dll`）やraw slash/caseを使わず、pin済みhost・fixed args・bootstrap script・固定phase tailの全pathをOS identityで解決したcanonical protocol vectorから再導出する。外部authorityはactual OS invocationがそのvectorへ解決したことを別claimで署名する。

## 6. D5 → 外部 skill（W0 以降）

`claude-roblox-mvp-buildout` へ次を渡す。

- Gate1／P0-start／P0-contract／D5の4 machine recordと、相互distinctなchallenge／trusted transcript／statement／capture／external provenance chain
- P0とD5の lifecycle transition attestation／外部provenance。各々が監視開始時のB0/B1実測状態、対象root／全域scope、authority session/event、完全write log、承認前後の順序、結果candidate/B2を束縛する
- D5 承認記録（`DECISIONS.md` の決定 ID）
- Approved 文書の version / hash（post-sync hash manifest）
- D5 baseline B2 と、再計算可能な B0/B1 historical source
- 最初の authorized WP

**MVP 側の immutable validator runtime、worker・送信先・OS 入力・capture・commit 等の証明／承認は W0 開始時に取り直す。本 skill の承認を継承しない。**

引き渡しパッケージを `docs/evidence/d5/<D5-ID>_w0_handoff_package.json` として作り、4 gate chain、D1.5/D4 external provenance、P0/D5 actual-event transition proof、B2 と再計算済み B0/B1 historical evidence を機械検査可能な形で渡す。package 自身は B2 file set に含めず、W0 はpackage記載値だけでなく、各challenge/capture/transcript/statement/provenance/gate record/transition attestationのactual bytes、operator-pinned offline signatures、全baselineのproject-relative immutable snapshot bytesから承認内容・操作順序・B0/B1/B2を再計算してから受理する。W0 v1はvalidator前の外部送信権限を持たないためquery-mode provenance/network adapterを起動せずSTOPする。commit-backed baseline、project内のlocal hash/authority文字列、自己作成write logを真正性証明として信用しない。

### W0 以降（D6/D7）

- WP 完了ごとに code・tests・evidence・`PROGRESS.md`・`CHANGELOG.md`・Traceability・影響 Spec・WP status を**同一完了単位で**同期する。commit 未許可時は snapshot/hash を Last Known Good にする
- 承認済み契約との衝突、新ルール、新 Tier 0 値、scope 変更を検出したら **WP を停止する**。D7 Change Request → 影響文書/test/traceability 更新 → D4 再監査 → 必要な P0 → 新 D5 承認を経るまで実装再開禁止
- 単なる実装欠陥で契約変更が無い場合だけ、同じ authorized WP 内で是正・再試験できる

## 7. worker と外部送信

worker 指定は stage 間で**自動継承しない**。各 stage 開始時に、能力・class・exact version・resolved model・送信先・auth/account・許可 path・secret 除外・cost cap を再確認する。共通形式は `worker-registry.md`。

**D4 は、file・validator・evidence を自身で検査できる Class A だけを gate 判定者に使う。** Class B は補助的 semantic review に使えるが、Critical 0 / Major 0、D4 合格判定を単独で出せない。

## 8. stage 遷移記録

各遷移を `DECISIONS.md` へ**追記**する（上書きしない）。

- source / target stage
- entry / exit verdict
- candidate ID / baseline ID / parent ID / manifest hash / immutable snapshot ID/root（W0 lifecycle v1でcommit-backed revisionは禁止）
- validator / audit / approval evidence
- 人間 gate なら承認者・日時・対象 revision
- worker 実行 attestation
- 未完了 Human Actions

## 9. 停止条件

- 宣言した到達点へ到達
- Critical > 0 または Major > 0
- 必須 validator 未解決
- D5 明示承認なし
- worker・送信承認・Class A 監査者を用意不能
- contract 変更を伴う D7 未完了
- 認証・production publish/data・課金・規約・権利処理等の human-only 境界

**停止は失敗扱いにせず、再開条件と必要 evidence を記録する。**
