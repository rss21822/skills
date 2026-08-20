# Handoff {ID} — {P0契約} の承認と {P0管理WP} の Verified 遷移

> **これは差分雛形。** 基本の必須項目（`objective`／`dataIds`／`acceptance`／`commands`／`execution`／`rollback` と常設条項）は `claude-roblox-dev-docs-creator` の `templates/handoff.md` が正本。そちらを土台にして本書の P0 固有部分を重ねる。本書だけで発行すると必須項目が欠ける。

| 項目 | 値 |
|---|---|
| handoffId | `{ID}` |
| GDD Gate 1 | `{GDD_GATE1_APPROVAL_ID}` / machine record `{path}` / sha256 `{hash}` / distinct capture `{HAC_ID}`; target GDD + scope-approved intake/required_specs hashes |
| P0 start approval | `{P0_START_APPROVAL_ID}` / machine record `{path}` / sha256 `{hash}` / closed scope kind `p0-start-v1`; inventory IDs exact; `inventory-rows-only`; `p0-standard-six-step-v1`; `additionalScope:false` |
| P0 contract approval | `{P0_CONTRACT_APPROVAL_ID}`（本便。human-directのみ。Gate 1、P0 start、D5 IDと別） |
| approval presentation/challenge/capture | presentation `{path}` / sha256 `{hash}` / message `{ID}`; `{HCH_ID}` / `{path}` / sha256 `{hash}`; `{HAC_ID}` / `{path}` / sha256 `{hash}`; transcript `{path}`; human message `{ID}`; statement `{path}` |
| approved P0 closure inventory | B0 historical `PROGRESS.md` / `## Proposed P0 closure inventory` / `{inventory ID}` / file sha256 `{hash}`（P0 start scopeとexact一致） |
| approved P0 management WP | `{WP-P0-001}` / `docs/{PREFIX}_work_packages.md`（p0-start closed scopeとexact一致） |
| input baseline | `B0-{ID}` / manifest `{path}` / sha256 `{hash}` / fileSetSha256 `{hash}` |
| human-approved content target | planned `P0-CAND-{ID}` / `approvedContentFileSetSha256 {hash}` / `sourceBaselineRevision` = exact B0 revision / normalization `strip-fixed-p0-approval-procedure-v1` |
| candidate output target | preallocated `P0-CAND-{ID}` / manifest `{path}`（outer sha256 / raw fileSetSha256はfreeze後の出力。人間承認の未来入力にしない） |
| machine approval record output | `{path}`（`gate_approval_record.schema.json`, type `p0-contract`） |
| rollback/source revision | commit `{hash}`（今回のcommit許可あり）／snapshot `{manifest path}`・manifest sha256 `{hash}`・raw git status `{path}`（commit未許可） |
| P0 in-scope transition monitor | session/provider/start event; exactly three target roles `canonical-project` / `private-staging` / `result-artifacts`; B0 manifest projection/fileSet plus one actual include-set before-state digest per role; full `{rootRole,path}` include-set; started before P0-start presentation |
| P0 lifecycle outputs | closed write log `{path}`; `LTA-P0-*` `{path}`; `PV-P0-TRANSITION-*` `{path}`（all outside P0-CAND） |
| 承認 | **人間本人のtrusted interactionにあるcanonical challenge responseのみ。{承認者}・{timezone日時}。** captureとstatement/transcript/challengeの実hashを添付 |

## 1. 指示

1. **既存monitor下で承認前stagingを実測する。** P0-start前にauthorityがB0 manifest projection/fileSet、3 roleのinclude-set before-state digest、全mutation target scopeを観測した同じsessionを使う。P0-start PV完了前のwrite、別root、部分監視、replay、unlogged writeは即`STOP/HUMAN`。AはB0 historical inventory全IDの`evidence path / sha256 / PASS`とaffected-doc hashesを再hashし、0行なら`inventoryMutationCount:0`を証明する。Bのprocedural writesは別分類・別countで残す。approved intake/GDD/required_specsは不変であり、net-zero restoreを含むeventも禁止する。
2. **未来candidate hash/revisionを人間へ要求しない。** planned IDを割り当て、P0 CONTRACT block/固定metadata未適用の承認前stagingを§2でnormalizeする。authorityがnormalized `approvedContentFileSetSha256`と`approvalPayloadPreparedAt`を実イベントとして観測する。target `plannedCandidate.sourceBaselineRevision`は既存B0.revision exact。freeze後revisionではない。
3. `approvalPayloadPreparedAt`後だけ、target+scope digestとcanonical responseをfull表示するunique presentationを送る。human canonical response、capture、outer query/signature verificationを順に完了する。monitor start <= P0-start presentation/response/PV <= all preapproval writes <= payload prepared < P0-contract presentation < response <= capture <= PVを検証する。委任/AI承認、local recordだけ、照会不能は`STOP/HUMAN`。
4. P0-contract outer verification完了後だけ、private stagingへ§3のexact P0 CONTRACT blockを3正本へ各1件追加し、scopeのP0管理WP detail/index mirrorだけへ§2の固定metadataを適用する。formal document header、製品実装WP、product contentは変更しない。未知field/free prose/重複は拒否し、全in-scope canonical/staging/result writeをclosed logへ記録する。
5. private stagingの最終candidate contentを**一度だけ**snapshot-only `P0-CAND-*`へ固定する。全fileをresult-artifacts snapshot rootへsource path/hash→snapshot path/hash付きでexact 1回copyし、全manifest fileをcover後だけsnapshot manifestを書いてimmutability freezeを記録する。各snapshot memberはsymlink／junction／reparse point／hardlink不可、link count 1、相互にuniqueなOS identity、canonical/staging sourceとのidentity交差0とする。manifest outer hash/raw `fileSetSha256`/revisionを計算する。candidate manifest自身とapproval/transition artifactsはcandidate `files`へ含めない。candidate bytesから§2だけをnormalizeし、capture digestへexact一致させる。未知diffはnormalizeしない。commit/hidden VCS write、欠落copy、freeze後candidate/staging mutation/refreezeは禁止。
6. freeze後、`gate_approval_record.schema.json` type `p0-contract` recordをresult-artifacts rootへexact 1件作る。closed scopeとactual candidate ID/path/outer hash/raw fileSet/revisionを束縛し、sourceEvidence/sourceVerificationをcapture/PVへexact一致させる。未来record hashをcandidateへ書かない。その後、changed canonical pathごとexact 1回、対応snapshot sourceの同一hash bytesだけをatomic applyする。transient/複数writeは禁止。全apply完了後にlogical monitor sealをexact 1回記録し、seal後mutationを0にする。
7. seal後monitorを閉じ、schema-valid `lifecycle_write_log`をparse/recomputeする。entry全件をinventory-content / preapproval-procedural / postapproval-metadata / snapshot-copy / snapshot-manifest / candidate-freeze / postfreeze-record / canonical-apply / transition-sealへ1:1分類し、include-set exact coverage、full copy map、event-level rule、before/after hashes、count/set/sequence digest、no-unlogged-writesをauthority actual eventsと照合する。P0-CAND外に`lifecycle_transition_attestation`を作り、その全claimsをoperator-pinned authorityがactual operation sequenceから返すouter PVで検証する。local log再署名だけは不可。
8. post-P0 D4の共通capsule/requestへ同一`p0LifecycleTransition {attestation,writeLog,provenanceVerification}`をexact 1件入れる。policy固定lifecycle validatorと3系統監査がPASSし、candidateからB1への同一fileSet昇格が完了するまで `D5承認準備完了` と書かない。実装開始可能とは書かない。失敗時はcanonical bytesを全復元しpartial candidate/gate/transition artifactを破棄する。

Capture/gateのscopeは次のclosed shapeへexact一致させる。

```json
{
  "kind": "p0-contract-v1",
  "p0StartApprovalId": "{P0_START_APPROVAL_ID}",
  "inventoryId": "{P0_CLOSURE_INVENTORY_ID}",
  "closedSourceItemIds": [],
  "p0ManagementWp": { "id": "{WP-P0-001}", "path": "docs/{PREFIX}_work_packages.md" },
  "approvalOutcome": "contract-approved",
  "additionalScope": false
}
```

## 2. approved-content normalization contract

`strip-fixed-p0-approval-procedure-v1` はpre-approval modeとcandidate modeを明示的に分け、次だけを正規化する。

1. UTF-8 textはBOM無しでdecodeし、改行をLFへ正規化する。pre-approval modeは§3 blockが3 ledgerすべて0件かつ各file末尾がexact 1 LFであることを要求する。candidateへのappend unitは、既存terminal LFに続く追加LF + BEGIN行からEND行 + terminal LF、すなわちfile suffix `\n\n<!-- BEGIN P0 CONTRACT ... -->...<!-- END ... -->\n`。candidate modeはmatching approval ID suffixが各ledgerちょうど1件であることを要求し、そのsuffix全体を除外して結果をexact 1 terminal LFへ戻す。preでblockあり、candidateでmissing/duplicate/malformed/unknown/non-suffix sentinel、余分なseparator改行は失敗。
2. scopeのP0管理WP detailにある`Status`、`Authorized by`、`Authorization baseline`、`Authorization evidence`の値と、同じfileのindex mirror Statusだけを固定tokenへ置換する。別WP・別field・free proseは置換しない。
3. 各normalized canonical fileから`{path,bytes,sha256}`を作りpath昇順へsortし、Python `json.dumps(entries, ensure_ascii=False, sort_keys=True, separators=(',', ':'))` のUTF-8 SHA-256を`approvedContentFileSetSha256`とする。pre/candidateのnormalized path setとdigestはexact一致必須。raw baseline `fileSetSha256`とは別digest。

固定P0管理WP metadataは `Status: Verified`（detail/index）、`Authorized by: {P0_CONTRACT_APPROVAL_ID}`、`Authorization baseline: {PLANNED_P0_CANDIDATE_ID}`、`Authorization evidence: {HUMAN_APPROVAL_CAPTURE_PATH}`。Done definitionの実測前に適用しない。

## 3. Exact P0 CONTRACT ledger blocks

各blockはfield order/spacing/sentinelをexactに保ち、`{...}`を1 scalarへ置換する。`Closed source item IDs`は空白無しJSON array（0行なら`[]`）。Evidence/Reason/free proseを足さない。

```text
<!-- BEGIN P0 CONTRACT DECISIONS {P0_CONTRACT_APPROVAL_ID} -->
- P0 contract approval ID: {P0_CONTRACT_APPROVAL_ID}
- Approval kind: human-direct
- Approver: {HUMAN_IDENTITY}
- Approved at: {ISO-8601_WITH_TIMEZONE}
- Human approval capture: {PROJECT_RELATIVE_PATH}
- P0 start approval ID: {P0_START_APPROVAL_ID}
- Inventory ID: {P0_CLOSURE_INVENTORY_ID}
- Closed source item IDs: {MINIFIED_JSON_ARRAY}
- P0 management WP ID: {WP_ID}
- P0 management WP path: {PROJECT_RELATIVE_PATH}
- Planned candidate ID: {P0_CANDIDATE_ID}
- Approved content fileSetSha256: {SHA256}
- Next authorized action: Run post-P0 D4 against frozen P0-CAND
<!-- END P0 CONTRACT DECISIONS {P0_CONTRACT_APPROVAL_ID} -->
```

`PROGRESS`と`CHANGELOG`も上のblockをbyte-identical field set/orderで使い、両sentinelの`DECISIONS` tokenだけをそれぞれ`PROGRESS` / `CHANGELOG`へ置換する。

## 4. 制約

- **検証を省略して承認・遷移を記録しない。** 実測がすべて先
- {不変対象} を変更しない（sha256 で証明）
- `src/` 等を作成しない。dry run の出力は一時領域のみ
- 裸 `[OPEN]` 禁止。決定 ID 完全修飾。決定内容を他文書へ複製しない
- `[HUMAN]` をAI実行候補にせず、AI実行可能なものは `[AI-ACTION]` とする
- **「照合の承認可」「P0管理WPのVerified」「P0契約承認」「人間D5承認」を別の事象として書き分ける**
- P0-start (A)がemptyでも(B)のfixed procedureとP0-contractは省略しない。(B)を根拠にproduct contentを変更しない
- P0 contractはhuman-directのみ。delegated-process/`[AI-APPROVED]`を使わない。将来の委任再導入にはhuman-rooted active scope/expiry/revocation/exclusions/useを持つ別schemaと検証が必要
- P0開始・P0契約・D5の各approval IDとmachine recordを別々に保持する。ID再利用禁止
- 実施していない検証を書かない。handoff workerによるcommit・push禁止

## 5. 報告

判断材料と遷移条件の**実測結果（実行 command と出力）**、変更前後 sha256、`git status --short`、validator と lint の実出力（baseline 悪化不可）、遷移後の index・詳細節の行。
