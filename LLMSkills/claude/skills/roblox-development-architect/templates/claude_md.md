# {{PROJECT}} — AI Implementation Rules

Read `docs/{{PREFIX}}_docs_index.md` first.

## Canonical sources

- Intent: `docs/{{PREFIX}}_gdd.md`
- Structure: `docs/{{PREFIX}}_detailed_design.md`
- Balance: `docs/{{PREFIX}}_data_definition.md`
- UI/input: `docs/{{PREFIX}}_ui_ux_input_spec.md`
- Toolchain: `docs/{{PREFIX}}_toolchain_spec.md`
- Sequence: `docs/{{PREFIX}}_phase_plan.md`
- Authorized file scope: `docs/{{PREFIX}}_work_packages.md`
- Tests: `docs/{{PREFIX}}_test_spec.md`
- Release: `docs/{{PREFIX}}_release_rollback_runbook.md`

## Standing rules

1. Work on one approved WP at a time.
2. Do not change files outside the WP scope.
3. Do not invent product behavior or balance values.
4. Client does not own damage, currency, rewards, inventory, rank, or entitlement.
5. Do not touch production IDs, DataStores, products, secrets, or publish settings.
6. New scope goes to `DECISIONS.md`; do not implement it.
7. Run the WP tests and record evidence before Done.
8. Update PROGRESS, CHANGELOG, traceability, and affected docs with code changes.
9. Stop on canonical conflict or blocking ambiguity.
10. Never claim completion without the specified evidence.

## Commands

See `docs/{{PREFIX}}_toolchain_spec.md`.

## Current authorized work

See `PROGRESS.md`.
