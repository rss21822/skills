# {{PROJECT}} — Documentation Index

| Field | Value |
|---|---|
| Document ID | {{PREFIX}}-DOC-INDEX |
| Version | 0.1.0 |
| Status | Draft |
| Canonical domain | navigation and canonical boundaries |
| Owner | [HUMAN] Project owner |
| Inputs | {{INPUTS}} |
| Downstream | {{DOWNSTREAM}} |
| Last approved | — |

## Change history

| Version | Date | Change | Approver |
|---|---|---|---|
| 0.1.0 | {{DATE}} | Initial draft | — |

## 1. Canonical state pointers

このindexはnavigation mirrorであり、phase、Last Known Good、next action、approval stateの正本ではない。値をここへ複製しない。

| State | Canonical source |
|---|---|
| Current phase / current handoff / Last Known Good / next authorized action / sole Proposed P0 closure inventory | `PROGRESS.md` |
| Human and delegated decisions / stage transitions | `DECISIONS.md` |
| GDD Gate 1 / P0 start / P0 contract / D5 approval facts | `evidence/approvals/*.json`; each record binds presentation/challenge/capture bytes plus operator-external provider query/signature verification |
| B0/B1/B2 lineage | `evidence/baselines/<baseline-id>/*.json` plus immutable `snapshot/`, validated by `schemas/baseline_manifest.schema.json` |

## 2. Canonical boundary map

`gen_index.py --index-output`だけが次のmarker内を置換する。marker外を生成処理で変更しない。

<!-- BEGIN GENERATED DOCUMENT INDEX -->
| Document ID | Path | Version | Status | Canonical domain |
|---|---|---|---|---|
<!-- END GENERATED DOCUMENT INDEX -->

## 3. Conditional specifications

| Trigger | Required specification | Status | Canonical domain |
|---|---|---|---|
| `{required_specs id}` | `{generated path}` | Draft / Review / Approved / Superseded | `{canonical domain}` |

Conditional SpecのDocument IDは各domain template内の固定suffixを使う。未置換の可変ID token、手採番、同一ID再利用を禁止する。

## 4. Machine-readable artifacts

| Artifact | Purpose | Validator |
|---|---|---|
| `{{PREFIX}}_docs_manifest.json` | required file/status registry | `validate_docs.py` |
| `{{PREFIX}}_required_specs.json` | closed trigger projection; feasibility is zero or one fixed combined D1.5 suite | `schemas/required_specs.schema.json` + `detect_triggers.py` + `validate_docs.py` |
| `traceability/{{PREFIX}}_requirements.csv` | requirement → design → WP → test | `validate_traceability.py` |
| `schemas/{{PREFIX}}_remote_contracts.json` | Remote dictionary | `schemas/remote_contract.schema.json` |
| `schemas/{{PREFIX}}_save_schema.json` | save/migration contract | `schemas/save_schema.schema.json` |
| `schemas/{{PREFIX}}_analytics_events.json` | analytics event dictionary | `schemas/analytics_event.schema.json` |
| `schemas/{{PREFIX}}_asset_ledger.json` | asset/rights ledger | `schemas/asset_ledger.schema.json` |
| `schemas/{{PREFIX}}_commerce_ledger.json` | product/entitlement ledger | `schemas/commerce_ledger.schema.json` |
| `evidence/baselines/<baseline-id>/*.json` | snapshot-only D4/P0 candidates and B0/B1/B2 lineage; sibling `snapshot/` stores the externally proven complete immutable file copy | `schemas/baseline_manifest.schema.json` |
| `evidence/approvals/*.json` | distinct Gate 1 (D1 earliest), P0 start, P0 contract, and D5 machine records | `schemas/gate_approval_record.schema.json` |
| `evidence/approvals/captures/*.json` | D1-earliest offline human statement/transcript byte binding, target, and closed scope; not an authenticity root | `schemas/human_approval_capture.schema.json` |
| `evidence/approvals/presentations/*.json` | D1-earliest full typed target/scope/digest/response bytes shown before approval | `schemas/human_approval_presentation.schema.json` |
| `evidence/approvals/challenges/*.json` | D1-earliest deterministic target+scope digest, canonical response, and presentation ref | `schemas/human_approval_challenge.schema.json` |
| `evidence/approvals/transcripts/*.json` | D1-earliest structured offline interaction bytes selected by each capture | `schemas/human_interaction_transcript.schema.json` |
| `evidence/approvals/verifications/*.json` | D1-earliest outer operator-pinned provider-query/signature verification of each capture | `schemas/provenance_verification.schema.json` |
| `docs/audits/policies/<policy-id>.json` | installed-source-rederived D4 policy/checklist/fixed argv manifest | `schemas/d4_audit_policy_manifest.schema.json` + installed-skill rederivation |
| `docs/audits/runtime/<runtime-id>.json` | `_policy_runtime` copy plus externally pinned complete Python/Git runtime and exact verifier-config closure | `schemas/d4_runtime_allowlist.schema.json` |
| `docs/audits/assemblies/<assembly-id>.json` | cycle-free candidate revision/full-tree/fixed-preflight assembly facts | `schemas/d4_capsule_assembly_attestation.schema.json` |
| `docs/audits/assemblies/<assembly-id>_provenance.json` | operator-pinned external proof of actual SOURCE-STATE/REVISION/TREE enumeration and outputs | `schemas/provenance_verification.schema.json` |
| `docs/audits/capsules/<capsule-id>.json` | immutable sanitized input map and preflight evidence shared by all three D4 lanes | `schemas/d4_audit_capsule.schema.json` |
| `docs/audits/prompts/<request-id>.payload` | exact orchestrator-submitted role text and attachment-descriptor payload; excludes provider-internal implicit frames | policy `promptCompilation` + SHA-256 |
| `docs/audits/requests/<request-id>.json` | cycle-free requestCore digest, exact submitted-payload ref, and candidate-derived check IDs | `schemas/d4_audit_request.schema.json` |
| `docs/audits/attestations/<attestation-id>.json` | per-lane Class A clean/read-only execution provenance | `schemas/d4_auditor_attestation.schema.json` |
| `docs/audits/verifications/<verification-id>.json` | outer trusted-runtime-query or pinned-signature verification of each attestation | `schemas/provenance_verification.schema.json` |
| `evidence/provenance/runtime-queries/*.json` | closed pinned-adapter query result plus raw provider response ref | `schemas/trusted_runtime_query_result.schema.json` |
| `evidence/provenance/signatures/*.json` | signed payload/signature/pinned trust-anchor refs | `schemas/pinned_signature_evidence.schema.json` |
| `evidence/d1.5/*` | closed trigger/experiment measurement bytes plus outer runtime/signature verification | `schemas/d15_measurement_evidence.schema.json` + baseline/W0 `d15Measurements` + `schemas/provenance_verification.schema.json` |
| `evidence/transitions/<transition-id>_write_log.json` | complete closed P0/D5 event log, including exact source→snapshot/publish mappings and logical seals; local evidence, not trust root | `schemas/lifecycle_write_log.schema.json` |
| `evidence/transitions/<transition-id>_attestation.json` | cycle-free P0/D5 chronology, monitor scope/start state, digests, and result binding | `schemas/lifecycle_transition_attestation.schema.json` |
| `evidence/transitions/<transition-id>_provenance.json` | operator-pinned external actual-operation proof; post-P0 D4 uses P0 proof and W0 uses P0+D5 | `schemas/provenance_verification.schema.json` |
| `docs/audits/{{PREFIX}}_d4_<lane>_<candidate-id>_r<N>.md` | initial and post-P0 raw three-lane audit records | `d4_findings.md` template + recorded SHA-256 |
| `evidence/d5/<D5-ID>_post_sync_manifest.json` | independent D5 transaction hashes | `schemas/post_sync_manifest.schema.json` |
| `evidence/d5/<D5-ID>_w0_handoff_package.json` | required W0 receiver handoff; runtime permissions must be reacquired after validation | `schemas/w0_handoff_package.schema.json` |
The installed-skill resources `schemas/provenance_verifier_config.schema.json`, `schemas/w0_runtime_launch_challenge.schema.json`, `schemas/w0_runtime_prepare_execution_attestation.schema.json`, `schemas/w0_runtime_prelaunch_assertion.schema.json`, `schemas/w0_runtime_postexecution_attestation.schema.json`, `schemas/w0_run_authorization.schema.json`, `schemas/w0_run_admission_attestation.schema.json`, and `schemas/w0_runtime_admit_execution_attestation.schema.json` validate operator-external trust inputs. **No W0 run-authorization, admission, or admit-execution receipt artifact is a project artifact and no path is registered in this index.** Presentation, challenge, transcript, statement, capture, capture-PV/signature evidence, run authorization, admission attestation, ADMIT execution/worker-ready receipt, and detached signatures all live at predeclared absolute operator-external paths, outside the locked project/package/baseline/Skill trees.

The config pins `scripts/w0_receiver_bootstrap.ps1`, its PowerShell/OS host/full runtime, external signature verifiers, snapshot-only D4/W0 runtimes, the full installed creator/validator Skill read closure, and validator sources. The separately selected assigned receiver entrypoint is legal only inside its own exact installed receiver Skill tree, outside and identity-disjoint from project/B0-B2/W0/creator-validator/runtime-temp/authorization roots. Before reading/parsing config in **each** phase, the operator launcher supplies `-ExpectedConfigSha256 <LOWER64HEX>` from an out-of-band operator/user authorization root; bootstrap rehashes raw ConfigPath and rejects mismatch. Config/project/package/assertions cannot supply this scalar, so a substituted config cannot self-authorize an attacker key. Authority monitoring/enforcement starts before PREPARE process creation; raw PowerShell is forbidden. The only valid protocol is `PREPARE → VALIDATE → ADMIT → signed receipt → bootstrap PASS`: PREPARE may write only fresh temp plus the external launch challenge and exits before Python; signed PREPARE+prelaunch authorizes one pinned Python validation; VALIDATE verifies postexecution PASS while retaining temp and continuous source/project lock, machine-derives the exact immutable frozen path set from W0 package/B0-B2 manifests and snapshots plus all recursively reachable project-local handoff/proof evidence, and proves the write set disjoint. The standard external human chain then binds that full path set, `receiverSkillTreeSha256`, and `expectedLoadedProcessClosureSha256`; pre-ADMIT admission binds only these expected facts, active enforcement, and two absent receipt-output paths. ADMIT extends the locked read set, rederives current paths/tree and current B2/package/WP/project identities, and runs the second pinned validator. Only after semantic PASS may authority consume the unexpired admission token and launch the worker suspended/pre-entry; actual closure equality, zero effects, second-process facts, continuous lock, and a fresh unused short global-nonreuse worker-ready capability are signed in the receipt. Its effective expiry is the minimum of run-authorization, transfer, and admission expiry; semantic PASS, token consumption, launch, observation, signing, bootstrap PASS, and first-effect consumption all remain inside their applicable deadlines. Bootstrap verifies receipt/signature before PASS, and authority consumes the worker-ready capability only immediately before the one scoped first effect. `*_0001` frozen-path rows in JSON templates are expansion slots: replace/repeat and Unicode-ordinal-sort them until the complete machine-derived set is represented; a literal partial template is invalid. Cleanup occurs only after receipt-gated worker-ready or fail-closed abort. VALIDATE receives challenge plus six out-of-band prepare/pre/post paths; ADMIT fixes one exact eleven-path set, including the two predeclared receipt output paths. Placeholder assertion/receipt templates are not signed bytes; generated fixed-order/minified UTF-8 has no terminal LF. W0 lifecycle v1 accepts only offline `pinned-signature` provenance; query-only evidence forces owning-stage rebuild. Commit-backed lifecycle v1 is `STOP/HUMAN`.

## 5. Approval and audit record locations

ここへgate状態・日時・承認者を複製しない。次の正本を直接読む。

| Event | Canonical record |
|---|---|
| GDD and stage decisions | `DECISIONS.md` |
| GDD Gate 1 | one record binding target GDD + scope-approved intake/required_specs, plus presentation/challenge/capture/transcript/statement and outer provider-query/signature verification |
| Initial/post-P0 D4 | one installed-source policy, pinned runtime, policy-fixed preflight assembly attestation+outer proof, one capsule, three unique requestCore/payload/attestation/proof/raw-response chains, plus baseline hash bindings |
| P0 start / P0 contract / D5 | `evidence/approvals/*.json` |
| D5 W0 receiver handoff | `evidence/d5/<D5-ID>_w0_handoff_package.json` |
