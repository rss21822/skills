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
    ├── traceability/
    │   └── {PREFIX}_requirements.csv
    └── evidence/
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

`Approved` and `last approved date` are written only in the direct-human D5 transition. P0 or delegated `[AI-APPROVED]` must leave these formal-document fields unchanged.

## Evidence

Do not embed large logs in specifications. Store them under `docs/evidence/` and link by relative path.
