# Output Layout and Naming

## Project output

```text
project-root/
├── CLAUDE.md
├── PROGRESS.md
├── ASSET_TODO.md
├── HUMAN_ACTIONS.md
├── AI_ACTIONS.md
├── CHANGELOG.md
├── DECISIONS.md
└── docs/
    ├── {PREFIX}_docs_index.md
    ├── {PREFIX}_docs_manifest.json
    ├── {PREFIX}_intake.json
    ├── {PREFIX}_required_specs.json
    ├── {PREFIX}_gdd.md
    ├── {PREFIX}_detailed_design.md
    ├── {PREFIX}_data_definition.md
    ├── {PREFIX}_ui_ux_input_spec.md
    ├── {PREFIX}_toolchain_spec.md
    ├── {PREFIX}_phase_plan.md
    ├── {PREFIX}_work_packages.md
    ├── {PREFIX}_test_spec.md
    ├── {PREFIX}_workflow.md
    ├── {PREFIX}_release_rollback_runbook.md
    ├── specs/
    ├── schemas/
    │   ├── *.schema.json
    │   ├── {PREFIX}_remote_contracts.json
    │   ├── {PREFIX}_save_schema.json
    │   ├── {PREFIX}_analytics_events.json
    │   ├── {PREFIX}_asset_ledger.json
    │   └── {PREFIX}_commerce_ledger.json
    ├── traceability/
    │   └── {PREFIX}_requirements.csv
    ├── audits/
    │   └── {PREFIX}_d4_{lane}_{candidate-id}_r{N}.md
    └── evidence/
        ├── baselines/<baseline-id>/
        ├── d4/<candidate-id>/
        │   ├── d4_audit_capsule.json
        │   ├── requests/
        │   ├── attestations/
        │   ├── preflight/
        │   └── sanitized/
        ├── approvals/<gate-id>/
        │   ├── challenge.json
        │   ├── presentation.json
        │   ├── transcript.json
        │   ├── statement.txt
        │   ├── capture.json
        │   ├── provenance_verification.json
        │   ├── pinned_signature_evidence.json
        │   └── gate_record.json
        └── d5/
```

Conditional reports:

- `{PREFIX}_repository_audit.md`
- `{PREFIX}_feasibility_report.md`
- `specs/{PREFIX}_network_security_spec.md`, etc.

## Naming

- Prefix: 2–6 uppercase ASCII letters/numbers, stable for project lifetime
- Markdown headings: stable section IDs where downstream links exist
- Requirement IDs: `REQ-{DOMAIN}-{NNN}`
- Decision IDs: `D-{NNN}` / `F-{NNN}`
- Work Package IDs: `WP-{DOMAIN}-{NNN}`
- Test IDs: `T-{DOMAIN}-{NNN}`, `SV-{DOMAIN}-{NNN}`, `M-{DOMAIN}-{NNN}`
- Remote contracts: `NET-{DOMAIN}-{NNN}`
- Analytics events: `AN-{DOMAIN}-{NNN}`

## Document header

Every formal document contains:

- document ID
- project
- version
- status: Draft / Review / Approved / Superseded
- canonical domain
- owner
- inputs
- downstream dependents
- last approved date
- change history

Gate 1 approval binds the exact Draft GDD path/hash/revision used through B1. Only direct-human D5 external verification may apply the fixed metadata-only `Approved` / `Last approved` / history transformation in B2; W0 rechecks the B1/B2 normalized body digest is identical. P0 and delegated `[AI-APPROVED]` leave all formal metadata unchanged.

Machine-readable instance paths and their Markdown ownership boundaries are defined in `document-system.md` §Machine-readable contracts. Do not create a second instance path for the same domain.

## Evidence

Do not embed large logs in specifications. Store them under `docs/evidence/` and link by relative path.

Immutable snapshot baselines use `docs/evidence/baselines/<baseline-id>/snapshot/`. D4 uses one schema-valid capsule per candidate/run and one structured request/post-run attestation plus operator-pinned external runtime provenance per lane under `docs/evidence/d4/<candidate-id>/`; baseline `auditRecords` bind their paths/hashes together with each unedited raw report. Triggered D1.5 experiments have one external runtime provenance artifact per raw measurement. Human gates use a challenge → exact presentation → trusted transcript/exact statement → capture → external channel query/signature provenance → machine record chain under `docs/evidence/approvals/<gate-id>/`; the exact project-relative paths may vary but presentation, capture, provenance, machine-record W0 refs and hashes are mandatory. W0-bound provenance is fixed as offline `pinned-signature` evidence before immutable binding. W0 handoff uses `docs/evidence/d5/<D5-ID>_w0_handoff_package.json`. A candidate/baseline lifecycle manifest does not list itself in its file set or contain its own hash; the outer audit/promotion/transition/handoff record binds that manifest sha256. The W0 package is outside the B2 file set.

W0 receiver trust inputs are a separate operator-external chain and are never project artifacts: verifier config/trust anchor; launch challenge; authority-signed PREPARE execution attestation; prelaunch assertion; postexecution attestation; their detached signatures; closed run-authorization challenge/presentation/transcript/statement/capture/provenance/authorization; signed expected-only run-admission attestation; signed ADMIT execution/worker-ready receipt; and their detached signatures. The authority monitors PREPARE from process creation, locks the complete source+temp read set without a gap through VALIDATE, ADMIT semantic PASS, token consumption, suspended/pre-entry worker observation, receipt verification, bootstrap PASS, and first-effect capability consumption, and binds current project/B2/package/WP identities. Paths are supplied out of band and may not resolve below the project, creator/receiver Skill trees, prepared temp tree, or W0 package. Admission/receipt attestations plus their signatures are the exact four cycle-breaking proof-sealing exclusions; their predeclared raw paths, identities, hashes when available, signatures, and session/run/nonce links remain mandatory.
