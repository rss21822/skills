# P0 Start {P0_START_APPROVAL_ID} — authorize contract work only

> `D4合格 / P0着手資格あり（人間P0開始承認待ち）` とB0昇格の後、人間本人の直接承認で初めてP0作業だけを許可する。委任承認不可。P0契約承認、D5承認、製品実装開始の代替ではない。

## Inputs

- P0 start approval ID: `{P0_START_APPROVAL_ID}`
- approval kind: `human-direct`
- approver: `{IDENTITY}`
- approved at: `{ISO-8601_WITH_TIMEZONE}`
- human approval presentation/challenge/capture/outer verification: presentation `{PATH}` / sha256 `{SHA256}` / message `{ID}`; challenge `{HCH_ID}` / `{PATH}`; capture `{HAC_ID}` / `{PATH}` / sha256 `{SHA256}`; human message `{ID}`; `{PV_ID}` / `{PATH}` / sha256 `{SHA256}`. Transcript/statement required; provider query/signature verifies both messages and target
- GDD Gate 1: `{GDD_GATE1_APPROVAL_ID}` / record `{PATH}` / sha256 `{SHA256}` / distinct capture `{HAC_ID}`; target GDD plus scope-approved intake `{PATH}/{SHA256}` and required_specs `{PATH}/{SHA256}` inherited unchanged from D1.5/D2/D4
- B0: `{B0_ID}` / manifest `{PATH}` / sha256 `{SHA256}` / fileSetSha256 `{SHA256}`
- promoted from: `{D4_CANDIDATE_ID}` / manifest `{PATH}` / sha256 `{SHA256}`
- three D4 records: `{consistency}`, `{roblox-readiness}`, `{clean-room}`
- B0-fixed P0 closure inventory: `PROGRESS.md` / `## Proposed P0 closure inventory` / B0 historical file sha256 `{SHA256}` / inventory ID `{ID}`
- explicit P0 management WP: `{WP-P0-001}` / `docs/{PREFIX}_work_packages.md`
- machine approval record output: `{PATH}`
- P0 lifecycle outputs: complete write log `{PATH}`; transition attestation `{LTA-P0-*}` / `{PATH}`; outer actual-operation provenance `{PV-P0-TRANSITION-*}` / `{PATH}`（all created outside P0-CAND after its freeze）

The machine record `scope` is not free text. Populate this exact closed shape; `sourceItemIds` is the complete unique ID set from the B0 historical table, and is explicitly `[]` for zero rows:

```json
{
  "kind": "p0-start-v1",
  "inventory": {
    "path": "PROGRESS.md",
    "section": "Proposed P0 closure inventory",
    "fileSha256": "{B0_HISTORICAL_PROGRESS_SHA256}",
    "inventoryId": "{P0_CLOSURE_INVENTORY_ID}",
    "sourceItemIds": []
  },
  "p0ManagementWp": {
    "id": "{WP-P0-001}",
    "path": "docs/{PREFIX}_work_packages.md"
  },
  "productContentMutation": "inventory-rows-only",
  "fixedProcedure": "p0-standard-six-step-v1",
  "additionalScope": false
}
```

## Preconditions

1. All three raw D4 responses target one candidate and pass. The full W0 lifecycle v1 is snapshot-only at D4-CAND/B0/P0-CAND/B1/B2: installed policy exact-compiles SOURCE-STATE/REVISION/TREE preflight, pinned Python enumerates the exact immutable `snapshotRoot`, and any commit revision is `STOP/HUMAN`. Pinned Git may support non-lifecycle repository facts but cannot authorize this route. One cycle-free assembly attestation plus outer authority proof binds actual argv/exits/raw outputs/tree/input digests, then one capsule references both. B0 binds that shared capsule plus three unique lane request/payload/attestation/proof chains. Caller-defined preflight/PATH Git/local self-report are invalid.
2. B0 `promotedFrom` equals that candidate and both `fileSetSha256` values match。B0はimmutableで `approvalId` はnull。P0 start recordがB0 outer hashを後から束縛する。
3. Recompute the B0 historical `PROGRESS.md` bytes from its immutable snapshot; its file SHA-256, section heading, inventory ID, rows, and B0 manifest entry all match the Inputs. Live `PROGRESS.md`やhandoff内の複製値を承認対象にしない。
4. Before sending the P0-start presentation, start the operator-pinned transition monitor over exactly three roles: canonical project, every private staging root, and result-artifact root, each with resolved root/immutable target ID. Fix the complete `{rootRole,path}` include set for all product/ledger/staging/result mutations. Authority start state binds the B0 manifest projection/fileSet and one actual include-set before-state digest for each role; empty staging/result roots are explicit, not omitted. Approval evidence acquisition is outside mutation scope; only log/LTA/PV/W0 proof-sealing after monitor close is excluded. Partial scope, another root/session, or replay is invalid.
5. Create a deterministic presentation containing gate type, exact B0 target, closed scope, digest, and canonical response; then create its challenge. Send the exact presentation as assistant/system before accepting one human message equal to `APPROVE <challenge-id> <targetScopeSha256>`. Presentation/challenge/transcript/statement/capture bytes and selected message IDs must agree.
6. Independently verify presentation role/time/content and human actor/role/time/content plus channel/target using an externally pinned provider adapter fresh query or provider signature/trust anchor. Enforce monitor start <= challenge issued <= presentation < response <= capture <= verification. No P0 write may precede completed P0-start provenance. Unavailable verification means `STOP/HUMAN`.
7. The capture approves the byte-equivalent closed scope above: inventory ID/file hash and complete `sourceItemIds` bind **(A)**; `p0ManagementWp` binds the only WP detail/index mirror that B may transition; fixed enum binds **(B)**; `additionalScope:false` rejects optional authority. If `sourceItemIds` is empty, (A) authorizes zero D2/D3 content mutations while B remains executable only for that WP.
8. GDD Gate 1 record/capture/presentation/verification still rehash and bind the exact GDD path/hash/revision, approved intake path/hash, and required_specs path/hash present in B0; no inventory row authorizes any of those mutations. `{P0_START_APPROVAL_ID}` and this presentation/challenge/capture/messages are unused and distinct from Gate 1 and planned P0 contract/D5 chains.

## Authorized scope split

### A. Inventory-bound D2/D3 content closure

- D2/D3 specification/contract content may change only to answer or verify an exact bounded row in the B0 historical inventory
- every changed canonical path must appear in that row's `Affected canonical docs`; every closure must satisfy its recorded pass rule
- approved intake/GDD, trigger-derived required_specs, and all inherited Gate 1 target/scope path/hash/revision bindings are immutable. Any closure requiring change returns to D0/D1→new required_specs→unique new Gate 1→D1.5/D2/D3→new initial D4/B0
- zero inventory rows means zero D2/D3 content closure mutations
- a new question, path, or wider scope is never inferred; return to owning D0-D3→new initial D4→new B0→new P0-start approval

### B. Fixed standard P0 procedure

The following six ordered steps are the sole meaning of `p0-standard-six-step-v1`, whether A has rows or is empty. They cannot be reordered, merged to skip a gate, or partially executed:

1. Under the already-active in-scope transition monitor and only after P0-start outer provenance completes, verify the existing contract/acceptance inputs, execute and evidence every authorized inventory closure, and prepare the fixed CR/closure records without expanding product intent.
2. Build preapproval staging with no P0-contract block/metadata, verify exactly `scope.p0ManagementWp` Done definition, compute `strip-fixed-p0-approval-procedure-v1` normalized `approvedContentFileSetSha256`, and have the external operation authority observe `approvalPayloadPreparedAt` plus that digest.
3. Only then send the unique P0-contract full presentation; obtain the canonical human response, capture, and outer provider verification. Do not freeze or apply contract metadata first.
4. Only after P0-contract provenance completes, append the fixed `DECISIONS.md` / `PROGRESS.md` / `CHANGELOG.md` blocks and transition only the scoped P0 management-WP detail/index mirror to `Verified` with fixed metadata.
5. Copy every private-staging candidate file to the predeclared result-artifacts snapshot root with one logged source path/hash → snapshot path/hash mapping per file; each destination must be a link-count-1 independent regular file with a unique OS identity disjoint from all canonical/staging sources—symlink, junction, reparse point, or hardlink is forbidden. Write the final snapshot manifest only after exact full-file coverage, then emit the one candidate immutability freeze event. Compute outer hash/fileSet/revision, create exactly one distinct machine `p0-contract` gate record bound to that actual snapshot candidate, atomically apply each changed canonical path exactly once from its frozen snapshot source, then emit exactly one logical transition seal. Candidate/staging mutation or refreeze after the freeze, hidden Git/VCS writes, transient/multiple canonical writes to one path, non-candidate apply bytes, and any mutation after seal are forbidden.
6. After seal, close and parse the complete write log; verify inventory-content versus preapproval-procedural counts (zero rows means inventory count 0, not necessarily procedural count 0), the ordered freeze → postfreeze record → apply → seal phases, no unlogged writes, chronology, and hashes. Create the cycle-free P0 lifecycle attestation and external actual-operation provenance outside P0-CAND. Post-P0 D4 capsule/request must exact-bind this one LTA/write-log/PV chain.

B permits no content mutation beyond A. A and B together are the entire P0-start authority.

## Transaction

1. Persist and schema-validate the unique presentation, challenge, structured transcript, exact statement artifact, `human_approval_capture`, trusted query/signature source evidence, and outer `provenance_verification`; rehash them and verify B0 target/scope/approver/message chronology/provider claims. Verify the complete monitor started on B0 before presentation and remains active. Never synthesize a presentation delivery, human response, provider result, or monitor event.
2. Create a `gate_approval_record.schema.json` record with type `p0-start`, bound to B0 ID/path/hash/`fileSetSha256`/revision. `sourceEvidence` exactly references the capture and `sourceVerification` its outer verification. Validate the closed scope object; recompute that `sourceItemIds` exactly equals the B0 historical inventory IDs (or `[]`), verify `p0ManagementWp.id/path` resolves to one B0 work-package detail/index pair, and reject unknown properties or `additionalScope` other than false.
3. Only after the P0-start outer verification time, append a P0-start stage record to `DECISIONS.md`; append current authorization and next action to `PROGRESS.md`; append one `CHANGELOG.md` entry. Every write is recorded in the closed lifecycle write log.
4. Do not edit the inventory rows during this authorization transaction. P0 work subsequently creates alternatives and closes only approved rows; it reflects each closure in live `PROGRESS.md`, and the final `P0-CAND-*` includes those bytes.
5. Do not alter formal document Status/Last approved, product contracts, any product implementation WP, or any WP other than `scope.p0ManagementWp`.
6. Rehash the machine record and append-only files. On failure restore their pre-transaction bytes and report `ROLLED BACK`; retain the immutable human interaction evidence but do not treat it as authority for another target/scope.

## Exit

- Allowed next action: execute A rows, if any, then all six ordered B steps against only `scope.p0ManagementWp`. With zero A rows, prove inventoryMutationCount `0` while still performing preapproval digest → human P0-contract presentation/response/capture/PV → fixed metadata → complete snapshot copy/manifest/freeze → actual-candidate machine record → one exact frozen-source canonical event per changed path → single seal → outer lifecycle proof
- Not allowed: D5 sync, W0/product implementation, commit/push, production/external-state changes without separate authority
