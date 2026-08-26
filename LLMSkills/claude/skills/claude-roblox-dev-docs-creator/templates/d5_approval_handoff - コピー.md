# D5 Approval Sync {D5_APPROVAL_ID} — atomic metadata transition

> 人間本人がB1内容を直接・明示承認した後だけ実行する。P0開始承認、P0契約承認、D5承認は別事象・別ID。承認前の品質判定や `[AI-APPROVED]` をD5承認へ流用しない。

## 1. Approval and lineage

- D5 approval ID: `{D5_APPROVAL_ID}`
- human approver: `{HUMAN_IDENTITY}`
- approved at: `{ISO-8601_WITH_TIMEZONE}`
- D5 human approval presentation/capture/outer verification: presentation `{PATH}` / sha256 `{SHA256}` / message `{ID}`; challenge `{HCH_ID}` / `{PATH}`; capture `{D5_CAPTURE_ID}` / `{PATH}` / sha256 `{SHA256}`; human message `{ID}`; transcript `{PATH}` / statement `{PATH}`; `{PV_ID}` / `{PATH}` / sha256 `{SHA256}`
- D5 machine approval record: `{PATH}` / sha256 `{SHA256}`
- GDD Gate 1 approval ID: `{GDD_GATE1_APPROVAL_ID}` / record `{PATH}` / sha256 `{SHA256}` / capture `{GDD_GATE1_CAPTURE_ID}` / `{PATH}` / sha256 `{SHA256}` / target GDD + scope-approved intake/required_specs refs
- P0 start approval ID: `{P0_START_APPROVAL_ID}` / record `{PATH}` / sha256 `{SHA256}`
- P0 start capture: `{P0_START_CAPTURE_ID}` / `{PATH}` / sha256 `{SHA256}`
- P0 contract approval ID: `{P0_CONTRACT_APPROVAL_ID}` / record `{PATH}` / sha256 `{SHA256}`
- P0 contract capture: `{P0_CONTRACT_CAPTURE_ID}` / `{PATH}` / sha256 `{SHA256}`
- B0 pre-P0 accepted baseline: `{B0_ID}` / manifest `{PATH}` / sha256 `{SHA256}`
- B1 human-approved content baseline: `{B1_ID}` / manifest `{PATH}` / sha256 `{SHA256}`
- B2 post-sync baseline to create: `{B2_ID}` / manifest `{PATH}`
- first W0 handoff-target WP transaction input: `{WP_ID}` / `{PATH}` / `firstWpPreSyncSha256` `{SHA256}`. This hash binds the B1/pre-sync bytes only; it is not the W0 package `firstAuthorizedWp.sha256` and grants no runtime execution or side-effect authority
- D5 in-scope transition monitor: session/provider/start event; exactly three target roles `canonical-project` / `private-staging` / `result-artifacts` with resolved root+immutable ID; B1 manifest projection/fileSet plus one actual include-set before-state digest per role; full `{rootRole,path}` include-set artifact+digest fixed before monitor start; started before D5 presentation
- D5 lifecycle outputs: closed write log `{PATH}`; transition attestation `{LTA-D5-*}` / `{PATH}`; outer actual-operation provenance `{PV-D5-TRANSITION-*}` / `{PATH}`（all outside B2）
- W0 handoff package: `{PATH}`

D5ではpresentation送信前にoperator-pinned monitorを開始し、B1 manifest projection/fileSet、3 target rootsのactual include-set before states、全product/ledger/staging/result mutation include setをauthorityで固定する。その後、不変B1とclosed `d5-v1` scopeをfull表示しhuman canonical responseだけからcaptureを作る。approval presentation/challenge/transcript/capture/PVのevidence acquisition writeは別phaseでmonitor対象外。禁止する「承認前write」はB1→B2 sync/product-metadata/result mutationである。proof-sealing log/LTA/PV/W0だけはmonitor close後の固定除外。部分監視、別root/replay、local logだけ、創作・照会不能は`STOP/HUMAN`。

Gate ID distinctness: `{GDD_GATE1_APPROVAL_ID}` ≠ `{P0_START_APPROVAL_ID}` ≠ `{P0_CONTRACT_APPROVAL_ID}` ≠ `{D5_APPROVAL_ID}`。4 presentation/challenge/captureのID/path、presentation/human message ID、interaction ID、statement pathも相互distinct、再利用不可。

D5 captureとgate recordのscopeは次のclosed objectへbyte-equivalentで一致させる。free textや追加fieldを許可しない。

```json
{
  "kind": "d5-v1",
  "firstWp": { "id": "{WP_ID}", "path": "{PROJECT_RELATIVE_PATH}" },
  "authorization": "w0-handoff-only",
  "additionalScope": false
}
```

Baseline lineage:

1. `D4-CAND-*` passes all three D4 tracks with the same `fileSetSha256`; promotion creates B0 with `promotedFrom` pointing to that candidate.
2. P0 changes produce `P0-CAND-*`; post-P0 D4 reruns all three tracks against that exact candidate. Promotion creates B1, retains identical `fileSetSha256`, and sets parent B0.
3. Human D5 approval targets immutable B1 content. Metadata sync creates B2 with parent B1. B1 formal headers remain Draft/Review until this transaction commits.

## 2. Preflight — no writes

Fail closed before editing unless every item passes:

1. Perform a read-only availability/static-contract check only: the separately supplied operator config schema, independently authorized out-of-band expected config SHA-256 input, pinned `w0_receiver_bootstrap.ps1`, pinned PowerShell/OS host/full runtime closure, full installed Skill read closure, pinned Python, validator, and exact `gen_index.py`/`state_readiness.py`/`strict_json.py` support set are all declared and rehashable in principle. The expected hash must not come from config/project/package. Do **not** invoke PREPARE, VALIDATE, or ADMIT here: the W0 package, B2, and transition proofs do not exist yet. Lifecycle v1 permits snapshot revisions only; any commit/Git-dependent acceptance or missing declared pin is `STOP/HUMAN`. Recompute B0/B1 snapshot bytes and hashes. D4/P0 candidates and B0/B1 inherit one Gate 1 record whose target Draft GDD and scope-approved intake/required_specs path/hash bindings are exact and immutable. D1.5 zero/one evidence exact-covers Gate1 required_specs.
2. Validate all four gate records and all distinct presentation/challenge/capture/transcript/statement/provider-verification chains. Gate 1 binds GDD plus approved intake/required_specs and D1.5+D2. Other gates bind their closed scopes. Enforce issued <= presentation < human response <= capture <= verification. Every gate source ref matches. W0 v1 accepts only offline `pinned-signature` provenance. Each final PV must already be signed **before the first candidate/baseline/audit record that binds its hash**. A query-mode or unsigned bound PV cannot be converted or replaced at D5; `STOP/HUMAN` and rebuild from its owning stage/new candidate. Receiver network query/send is forbidden. IDs/paths/hashes/messages are pairwise distinct.
3. Verify three post-P0 D4 records. Installed policy exact-covers all references/checklists and fixed SOURCE-STATE/REVISION/TREE preflight. Shared capsule references a cycle-free assembly attestation and externally signed proof of complete target-revision enumeration plus one exact `p0LifecycleTransition` LTA/write-log/PV chain. The fixed lifecycle command parses it and offline-verifies every actual-operation signature through the external pinned verifier config; initial D4 has no such input. Then verify three unique lane request/payload/Class-A attestation/signed-proof/raw-response chains. Caller mode/commands, project config, PATH Git, receiver network calls, and local self-report are invalid. Candidate equals B1 `promotedFrom` and fileSet hash.
4. Recompute D5 monitor start evidence, presentation bytes, challenge `targetScopeSha256`, and canonical response. Verify B1 start state/full target coverage; selected presentation follows monitor start and precedes exactly one human response; statement bytes equal response. External claims bind both content hashes/times and B1/scope/first WP exactly.
5. Verify blocking open `0`, `[PROPOSAL]` `0`, unverified `[ASSUMPTION]` `0`, required validators PASS, and the first WP has complete scope/tests/rollback.
6. Verify every file to mutate is listed in B1. Any preflight mismatch: write nothing and report `BLOCKED`.

## 3. Sole allowed B1 → B2 diff

The transaction may change only:

- each formal document header: `Status` → `Approved`; `Last approved` → the single D5 timestamp
- each formal document change history: append one D5 metadata-promotion row; no prior row rewrite. For GDD the exact row is `| {unchanged B1 Version} | {D5_APPROVED_AT} | D5 metadata promotion {D5_APPROVAL_ID} | {HUMAN_IDENTITY} |`; its unique Draft/Last-approved rows transform exactly as the W0 schema states, and inverse transformation must reproduce raw B1 GDD bytes
- docs index header metadata and the generated region delimited by `BEGIN/END GENERATED DOCUMENT INDEX`
- docs manifest generated metadata and document `id/path/version/domain/required/status/phase/trigger`; `baselineId` → B2 ID
- `DECISIONS.md`: append exactly one machine-generated D5 DECISIONS block using §3.1; no bytes outside that block
- `PROGRESS.md`: perform only the five unique current-state replacements in §3.2, then append exactly one machine-generated D5 PROGRESS history block; no other bytes
- `CHANGELOG.md`: append exactly one machine-generated D5 CHANGELOG block using §3.3; no bytes outside that block
- first W0 handoff-target WP only: document detail `Status` → `Approved`, matching package-index status, `Authorized by` → D5 approval ID, `Authorization baseline` → B2 ID, `Authorization evidence` → W0 package path. These are handoff metadata, not runtime authority
- monitored result artifacts: exact allowed-diff artifact, independent post-sync hash manifest, and B2 baseline manifest. W0 is created only after monitor close and is not part of B2

Product intent, requirements, numeric values, interfaces, contracts, tests, scope, acceptance, rollback behavior, and every non-first WP are immutable. The fixed append blocks, five controlled PROGRESS replacements, and first-WP handoff metadata above are allowed content diffs; therefore the acceptance test is **“no diff outside this allowlist”**, not “status-only diff”.

### 3.1 Exact DECISIONS append block

Replace every `{...}` token with one scalar value. Keep field order, labels, spacing, and sentinels exact. Add no prose, Evidence, or Reason field.

```text
<!-- BEGIN D5 DECISIONS {D5_APPROVAL_ID} -->
- D5 approval ID: {D5_APPROVAL_ID}
- Approval kind: human-direct
- Approver: {HUMAN_IDENTITY}
- Approved at: {ISO-8601_WITH_TIMEZONE}
- D5 approval record: {PROJECT_RELATIVE_PATH}
- B1 baseline ID: {B1_ID}
- B1 fileSetSha256: {SHA256}
- B2 baseline ID: {B2_ID}
- First authorized WP ID: {WP_ID}
- First authorized WP path: {PROJECT_RELATIVE_PATH}
- Next stage: W0
- Next authorized action: Validate W0 handoff and reacquire runtime permissions
<!-- END D5 DECISIONS {D5_APPROVAL_ID} -->
```

### 3.2 Exact PROGRESS replacements and history block

Each current-state field must occur exactly once before mutation. Replace only its value:

```text
- Current phase: W0
- Current Work Package: {WP_ID}
- Status: W0 handoff authorized
- Last known good baseline: {B2_ID}
- Next authorized action: Validate W0 handoff and reacquire runtime permissions
```

Then append exactly this history block, with no free prose:

```text
<!-- BEGIN D5 PROGRESS {D5_APPROVAL_ID} -->
- D5 approval ID: {D5_APPROVAL_ID}
- Approval kind: human-direct
- Approver: {HUMAN_IDENTITY}
- Approved at: {ISO-8601_WITH_TIMEZONE}
- D5 approval record: {PROJECT_RELATIVE_PATH}
- B1 baseline ID: {B1_ID}
- B1 fileSetSha256: {SHA256}
- B2 baseline ID: {B2_ID}
- First authorized WP ID: {WP_ID}
- First authorized WP path: {PROJECT_RELATIVE_PATH}
- Next stage: W0
- Next authorized action: Validate W0 handoff and reacquire runtime permissions
<!-- END D5 PROGRESS {D5_APPROVAL_ID} -->
```

### 3.3 Exact CHANGELOG append block

```text
<!-- BEGIN D5 CHANGELOG {D5_APPROVAL_ID} -->
- D5 approval ID: {D5_APPROVAL_ID}
- Approval kind: human-direct
- Approver: {HUMAN_IDENTITY}
- Approved at: {ISO-8601_WITH_TIMEZONE}
- D5 approval record: {PROJECT_RELATIVE_PATH}
- B1 baseline ID: {B1_ID}
- B1 fileSetSha256: {SHA256}
- B2 baseline ID: {B2_ID}
- First authorized WP ID: {WP_ID}
- First authorized WP path: {PROJECT_RELATIVE_PATH}
- Next stage: W0
- Next authorized action: Validate W0 handoff and reacquire runtime permissions
<!-- END D5 CHANGELOG {D5_APPROVAL_ID} -->
```

## 4. Transaction

1. Using the include-set artifact fixed before monitor start, create a private staging directory outside canonical paths as a complete audit capsule. Copy every canonical file plus all project-relative dependencies read by validators: B0/B1/candidate manifests, immutable snapshot roots, D4 records, gate approval records, configs, schemas, DECISIONS/PROGRESS/CHANGELOG, and their hash inventory. B0/B1 are snapshot revisions only; any commit-backed or alternate source is `STOP/HUMAN`. Log every private preparation event as `d5-staging` under its exact fixed rule; it is never a canonical `d5-sync` event.
2. Apply the §3 allowlist and exact §3.1–3.3 grammar to staged copies using the one D5 timestamp and IDs above. Reject duplicate sentinels, pre-existing same-ID blocks, missing unique PROGRESS current fields, unknown fields, or any free prose inside a block.
3. Regenerate the docs-index marker region and docs manifest into staging. Never hand-edit generated rows.
4. Validate the staged candidate with schema validation, docs lint, traceability, P0 state strict, index/manifest parity, baseline lineage/hash checks, and the exact D5 event-level allowlist. Compute prospective allowed-diff/post-sync/B2 bytes in memory only; do not create their final result-artifact paths yet. W0/transition proof do not exist. Any failure discards staging and preserves B1.
5. Save a rollback journal mapping every canonical target to B1 bytes/hash. Only after D5 outer verification completes, replace the complete canonical target set from staged bytes as one controlled unit. Log every staging/canonical event and its exact allowlist `ruleId`; a later net-zero restore cannot legalize an unauthorized event. Approval evidence is outside mutation scope; no other exclusion exists before monitor close.
6. Recompute canonical hashes and rerun every non-W0 acceptance check. If any fails, restore all targets under the same monitor, remove incomplete result artifacts, verify B1, and report `ROLLED BACK`; do not create a B2 seal.
7. After all `d5-sync` events succeed, create the exact allowed-diff artifact once at its predeclared `result-artifacts` include-set path and log `d5-allowed-diff-artifact-v1`. It covers the final canonical diff and may not omit a rule or add free-form changes.
8. Next create the independent post-sync manifest once at its predeclared result path and log `d5-post-sync-manifest-v1`. It contains `path`, `bytes`, and `sha256` for every mutated canonical target and does not list or hash itself.
9. Copy every B2 file-set member from its final canonical/result source into the predeclared B2 snapshot root, logging one source path/hash → snapshot path/hash event per file. Every destination must be a link-count-1 independent regular file with a unique OS identity disjoint from all canonical/staging sources—symlink, junction, reparse point, or hardlink is forbidden. Exact-cover the post-sync canonical set plus independent post-sync manifest. Only after every copy rehashes equal, create the B2 baseline manifest once, then emit the one logical snapshot immutability seal. B2 parent is B1; `promotedFrom` is null; `approvalId` is the D5 ID; `auditRecords` retains B1's three post-P0 records. The B2 manifest never lists itself. Hidden Git/VCS writes, omitted/duplicate copies, and mutation after seal are forbidden.
10. Close and parse the schema-valid lifecycle write log. Recompute entry count/set/sequence/copy-map digests; verify start-state/full include set, D5 presentation/response/PV before every staging/sync event, one atomic private-staging-source event per changed canonical path with no transient write, and ordered final-sync → allowed-diff → post-sync-manifest → full snapshot copies → B2 manifest → seal. Verify result hashes and no unlogged/post-seal mutation against authority actual events. Create `LTA-D5-*` and its outer `PV-D5-TRANSITION-*` outside B2. A local log hash or caller-authored signature is invalid; failed external proof rolls back to B1.
11. Create and seal the W0 package only after both P0 and D5 transition proofs exist. It records `acceptanceProvenanceMode=offline-pinned-signature-only-v1` and `lifecycleTransitions.p0|d5` each with `{transitionType,attestation,provenanceVerification,writeLog}`, plus Gate 1/GDD/intake/required_specs, D1.5, gates/captures, snapshot-only B0/B1/B2, D4, post-sync, and first WP. Set `firstAuthorizedWp.sha256` from current post-sync B2 bytes, never pre-sync hash. Creator performs only local schema/semantic assembly validation and rehashes every packaged reference; this is not W0 receiver acceptance and does not invoke the signed bootstrap. Record B2 as Last Known Good and `W0 handoff authorized`. Only after handoff plus a user implementation request may the receiver enter the pinned `PREPARE → VALIDATE → ADMIT` protocol. VALIDATE retains temp and the authority lock after post-signature PASS. Before the human response, derive `pathScope.frozenPaths` exactly from the validated package: all B0/B1/B2 manifests and physical snapshot members, the package, and every transitively reachable project-local handoff/proof artifact; sort the normalized paths and reject any missing/extra member or resolved/case-insensitive/ancestor/descendant/file-identity overlap with `allowedWritePaths`. Present and capture that full set together with the exact installed receiver Skill-tree digest and expected loaded-process-closure digest. Authorization presentation/challenge/transcript/statement/capture/PV and the expected-only run admission/signature are created only at predeclared operator-external paths; admission predeclares two absent receipt paths and excludes exactly admission/receipt plus their signatures from the authorization input-set cycle. ADMIT rederives the frozen set/Skill tree/current B2/package/WP and runs the second pinned semantic validator, but does not launch the worker before PASS. After PASS/exit 0, authority atomically consumes the unexpired admission token, launches the worker suspended/pre-entry, verifies actual closure equals expected, and signs the `w0_runtime_admit_execution_attestation` receipt with continuous lock, zero product effects, and an unused short global-nonreuse worker-ready capability. Bootstrap waits for and verifies the receipt/signature before PASS; the authority consumes the worker-ready capability only immediately before one scoped first effect. The receiver Skill entrypoint lives inside its separately bound receiver tree, disjoint from project/B0-B2/W0/creator-validator Skill/runtime temp/auth roots. Runtime/run-auth/admission/receipt artifacts, signatures, anchor, and config remain outside project/B2/package. Commit/push requires separate authorization.

## 5. Acceptance

- all formal documents: `Status: Approved`; identical `Last approved` timestamp matching D5 approval
- docs index generated region and docs manifest file set/status/version match headers and B2
- B0 ← D4 candidate, B1 ← post-P0 candidate with parent B0, B2 parent B1; candidate-to-B0/B1 `fileSetSha256` equality proven
- post-P0 D4 three-track records point to B1's `P0-CAND-*` source; candidate manifest/hash and B1 `promotedFrom`/`fileSetSha256` agree; Critical `0`, Major `0`; installed policy/runtime allowlist and one actual capsule plus three requestCore/submitted-payload/attestation/response/provenance chains rederive and rehash successfully
- post-P0 capsule/request exact-bind one valid P0 lifecycle LTA/write-log/PV chain; D5 produces a distinct valid D5 chain. Both authority proofs bind monitor target/start state/full scope, presentation/response/PV-before-write chronology, parsed event hashes/result, and no unlogged writes; receiver offline-verifies distinct pinned signatures for both and performs no query/send
- GDD Gate 1, P0 start, P0 contract, D5 IDs distinct; four presentation/challenge/capture/two-message/statement/provenance chains schema-valid, chronological, pairwise distinct, and non-reused. Gate 1 GDD/intake/required_specs bindings remain exact
- post-sync manifest actual path/bytes/SHA-256 match; no self-hash
- first-WP handoff metadata and W0 package agree; all other WP content unchanged. This is not runtime or side-effect authority: the receiver must validate W0 and reacquire current WP/path/worker/transfer/operation permissions before work
- applicable D1.5 evidence/provenance array matches trigger registry and every result is externally verified `pass`; E0 is not reused. Receiver reacquires current runtime capability and permission rather than trusting the historical measurement session
- allowlist diff validator reports no out-of-scope change
- DECISIONS/PROGRESS/CHANGELOG each contain exactly one matching-ID D5 block with the fixed field set/order and no free prose; PROGRESS has exactly the five authorized unique current-state replacements
- creator-side W0 package schema/semantic assembly validation PASS, with all lifecycle revisions complete externally proven snapshots and no Git/VCS write. This grants handoff eligibility only; monitored receiver bootstrap, W0 acceptance, exact machine-derived frozen-path and receiver-closure human run-authorization chain, expected-only continuous-lock signed run admission, post-semantic signed ADMIT execution/worker-ready receipt, bootstrap PASS, and atomic consumption of the fresh worker-ready capability immediately before the one scoped first effect remain pending
- rollback journal can restore exact B1 bytes

## 6. Failure result

Any unmet item means no `Approved` partial state and no W0 handoff authorization. Preserve or restore B1, report failed checks and evidence, then return to the owning phase. Never reuse a human approval for a different B1 hash.
