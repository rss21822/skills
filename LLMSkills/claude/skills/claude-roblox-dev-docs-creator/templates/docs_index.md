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
| P0 start / P0 contract / D5 approval facts | `evidence/approvals/*.json` validated by `gate_approval_record.schema.json` |
| B0/B1/B2 lineage | `evidence/baselines/<baseline-id>/*.json` plus immutable `snapshot/`, validated by `baseline_manifest.schema.json` |

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
| `{{PREFIX}}_required_specs.json` | trigger-derived required-spec projection from approved intake | `detect_triggers.py` + `validate_docs.py` |
| `traceability/{{PREFIX}}_requirements.csv` | requirement → design → WP → test | `validate_traceability.py` |
| `schemas/{{PREFIX}}_remote_contracts.json` | Remote dictionary | `remote_contract.schema.json` |
| `schemas/{{PREFIX}}_save_schema.json` | save/migration contract | `save_schema.schema.json` |
| `schemas/{{PREFIX}}_analytics_events.json` | analytics event dictionary | `analytics_event.schema.json` |
| `schemas/{{PREFIX}}_asset_ledger.json` | asset/rights ledger | `asset_ledger.schema.json` |
| `schemas/{{PREFIX}}_commerce_ledger.json` | product/entitlement ledger | `commerce_ledger.schema.json` |
| `evidence/baselines/<baseline-id>/*.json` | D4/P0 candidates and B0/B1/B2 lineage; sibling `snapshot/` stores immutable bytes | `baseline_manifest.schema.json` |
| `evidence/approvals/*.json` | distinct P0 start, P0 contract, and D5 approval capture records | `gate_approval_record.schema.json` |
| `docs/audits/{{PREFIX}}_d4_<lane>_<candidate-id>_r<N>.md` | initial and post-P0 raw three-lane audit records | `d4_findings.md` template + recorded SHA-256 |
| `evidence/d5/<D5-ID>_post_sync_manifest.json` | independent D5 transaction hashes | `post_sync_manifest.schema.json` |
| `evidence/d5/<D5-ID>_w0_handoff_package.json` | required W0 implementation handoff | `w0_handoff_package.schema.json` |

## 5. Approval and audit record locations

ここへgate状態・日時・承認者を複製しない。次の正本を直接読む。

| Event | Canonical record |
|---|---|
| GDD and stage decisions | `DECISIONS.md` |
| Initial/post-P0 D4 | `docs/audits/{{PREFIX}}_d4_<lane>_<candidate-id>_r<N>.md` plus baseline `auditRecords` |
| P0 start / P0 contract / D5 | `evidence/approvals/*.json` |
| D5 implementation handoff | `evidence/d5/<D5-ID>_w0_handoff_package.json` |
