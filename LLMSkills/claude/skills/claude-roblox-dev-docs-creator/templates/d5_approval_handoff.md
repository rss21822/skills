# D5 Approval Sync {D5_APPROVAL_ID} — atomic metadata transition

> 人間本人がB1内容を直接・明示承認した後だけ実行する。P0開始承認、P0契約承認、D5承認は別事象・別ID。承認前の品質判定や `[AI-APPROVED]` をD5承認へ流用しない。

## 1. Approval and lineage

- D5 approval ID: `{D5_APPROVAL_ID}`
- human approver: `{HUMAN_IDENTITY}`
- approved at: `{ISO-8601_WITH_TIMEZONE}`
- approval evidence: `{PATH}` / sha256 `{SHA256}`
- D5 machine approval record: `{PATH}` / sha256 `{SHA256}`
- P0 start approval ID: `{P0_START_APPROVAL_ID}` / record `{PATH}` / sha256 `{SHA256}`
- P0 contract approval ID: `{P0_CONTRACT_APPROVAL_ID}` / record `{PATH}` / sha256 `{SHA256}`
- B0 pre-P0 accepted baseline: `{B0_ID}` / manifest `{PATH}` / sha256 `{SHA256}`
- B1 human-approved content baseline: `{B1_ID}` / manifest `{PATH}` / sha256 `{SHA256}`
- B2 post-sync baseline to create: `{B2_ID}` / manifest `{PATH}`
- first authorized WP: `{WP_ID}` / `{PATH}` / pre-sync sha256 `{SHA256}`
- W0 handoff package: `{PATH}`

D5 machine approval recordは人間承認を受けた時点で `gate_approval_record.json` から作るapproval-capture入力。同期workerが承認を創作・補完しない。欠落時はpreflightで停止する。

ID distinctness: `{P0_START_APPROVAL_ID}` ≠ `{P0_CONTRACT_APPROVAL_ID}` ≠ `{D5_APPROVAL_ID}`。

Baseline lineage:

1. `D4-CAND-*` passes all three D4 tracks with the same `fileSetSha256`; promotion creates B0 with `promotedFrom` pointing to that candidate.
2. P0 changes produce `P0-CAND-*`; post-P0 D4 reruns all three tracks against that exact candidate. Promotion creates B1, retains identical `fileSetSha256`, and sets parent B0.
3. Human D5 approval targets immutable B1 content. Metadata sync creates B2 with parent B1. B1 formal headers remain Draft/Review until this transaction commits.

## 2. Preflight — no writes

Fail closed before editing unless every item passes:

1. Recompute B0 and B1 manifest file bytes/SHA-256 and canonical `files` payload hash. All values match; B1 parent is B0.
2. Validate all three records with `gate_approval_record.schema.json`. P0 start is bound to B0, P0 contract to `P0-CAND-*`, D5 is `human-direct` and bound to B1 ID/manifest hash/`fileSetSha256`/revision and the first WP. IDs and record hashes match §1.
3. Verify three post-P0 D4 records exist: `consistency`, `roblox-readiness`, `clean-room`. Each raw record points to the same `P0-CAND-*` manifest, has Critical `0`, Major `0`, verdict `pass`, and its file hash matches. That candidate is B1 `promotedFrom`; candidate and B1 `fileSetSha256` are identical.
4. Verify human approval evidence identifies B1 ID and B1 `fileSetSha256`, approver, timestamp with timezone, and the first WP.
5. Verify blocking open `0`, `[PROPOSAL]` `0`, unverified `[ASSUMPTION]` `0`, required validators PASS, and the first WP has complete scope/tests/rollback.
6. Verify every file to mutate is listed in B1. Any preflight mismatch: write nothing and report `BLOCKED`.

## 3. Sole allowed B1 → B2 diff

The transaction may change only:

- each formal document header: `Status` → `Approved`; `Last approved` → the single D5 timestamp
- each formal document change history: append one D5 metadata-promotion row; no prior row rewrite
- docs index header metadata and the generated region delimited by `BEGIN/END GENERATED DOCUMENT INDEX`
- docs manifest generated metadata and document `id/path/version/domain/required/status/phase/trigger`; `baselineId` → B2 ID
- `DECISIONS.md`: append one D5 stage-transition record using the template in `decisions.md`
- `PROGRESS.md`: append D5 completion and set next authorized action to the first WP
- `CHANGELOG.md`: append one D5 metadata-sync entry
- first authorized WP only: detail `Status` → `Approved`, matching package-index status, `Authorized by` → D5 approval ID, `Authorization baseline` → B2 ID, `Authorization evidence` → W0 package path
- new sealing artifacts: independent post-sync hash manifest, B2 baseline manifest, W0 handoff package

Product intent, requirements, numeric values, interfaces, contracts, tests, scope, acceptance, rollback behavior, and every non-first WP are immutable. The append-only records and first-WP authorization above are allowed content diffs; therefore the acceptance test is **“no diff outside this allowlist”**, not “status-only diff”.

## 4. Transaction

1. Create a private staging directory outside canonical paths as a complete audit capsule. Copy every canonical file plus all project-relative dependencies read by validators: B0/B1/candidate manifests, immutable snapshot roots, D4 records, gate approval records, configs, schemas, DECISIONS/PROGRESS/CHANGELOG, and their hash inventory. For commit-backed baselines, record the original repository as a read-only Git object source; do not pretend the staging directory owns those blobs. Do not change originals.
2. Apply the §3 allowlist to staged copies using the one D5 timestamp and IDs above.
3. Regenerate the docs-index marker region and docs manifest into staging. Never hand-edit generated rows.
4. Create an independent post-sync manifest containing `path`, `bytes`, and `sha256` for every mutated canonical target. It does not list or hash itself.
5. Create B2 baseline manifest. B2 parent is B1; `promotedFrom` is null; `approvalId` is the D5 ID; `auditRecords` retains B1's three post-P0 records. B2 `files` and `fileSetSha256` cover the post-sync canonical set plus the independent post-sync manifest, but never the B2 manifest itself.
6. Create the W0 handoff package from `w0_handoff_package.json`. It records P0 start/contract IDs and record paths/hashes; D5 ID/time/approver and gate-record path/hash; B0/B1/B2 manifest paths and outer hashes; all three post-P0 D4 records; post-sync manifest path/hash; and first-WP ID/path/hash. Human source evidence remains inside each gate record's `sourceEvidence`; W0 does not relabel that record as the source evidence itself.
7. On staging, run schema validation, docs lint, traceability, P0 state in strict mode, index/manifest parity, baseline lineage/hash checks, D5 allowlist diff, and W0 package validation. Any failure: discard staging; canonical files remain B1.
8. Save a rollback journal mapping every target to its B1 bytes/hash. Replace the complete canonical target set as one controlled commit unit. Do not publish a partial success.
9. Recompute canonical hashes and rerun every §5 acceptance check. If any post-write check fails, restore **all** targets from the rollback journal, remove incomplete B2/W0 sealing artifacts, verify B1 hashes, and report `ROLLED BACK`.
10. Only after post-write PASS, seal the W0 package and record B2 as Last Known Good. Commit/push only with separate user authorization.

## 5. Acceptance

- all formal documents: `Status: Approved`; identical `Last approved` timestamp matching D5 approval
- docs index generated region and docs manifest file set/status/version match headers and B2
- B0 ← D4 candidate, B1 ← post-P0 candidate with parent B0, B2 parent B1; candidate-to-B0/B1 `fileSetSha256` equality proven
- post-P0 D4 three-track records point to B1's `P0-CAND-*` source; candidate manifest/hash and B1 `promotedFrom`/`fileSetSha256` agree; Critical `0`, Major `0`
- P0 start, P0 contract, D5 approval IDs all present and distinct
- post-sync manifest actual path/bytes/SHA-256 match; no self-hash
- first WP authorization fields and W0 package agree; all other WP content unchanged
- allowlist diff validator reports no out-of-scope change
- W0 handoff package schema and semantic validator PASS
- rollback journal can restore exact B1 bytes

## 6. Failure result

Any unmet item means no `Approved` partial state and no W0 authorization. Preserve or restore B1, report failed checks and evidence, then return to the owning phase. Never reuse a human approval for a different B1 hash.
