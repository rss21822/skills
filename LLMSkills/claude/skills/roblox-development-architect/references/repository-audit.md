# Repository Audit Procedure

## Read-only discovery

Collect evidence, do not infer from names alone.

1. `git status`, branch, recent commits
2. directory tree and source mapping
3. Rojo/project files or Studio-only workflow
4. package manifests and locked versions
5. CLAUDE.md hierarchy and project rules
6. build, serve, test, lint, type-check commands
7. Universe/Place IDs and environment mapping
8. remotes and authority boundaries
9. save data and migrations
10. commerce products/receipts
11. analytics events
12. UI/input architecture
13. assets, model scripts, third-party modules
14. tests and current pass rate
15. deployment/publish scripts and production safeguards

## Confidence labels

- Confirmed: observed in code/config/output
- Reported: stated in docs but not verified
- Inferred: likely from evidence, needs validation
- Missing: expected but absent
- Conflicting: multiple sources disagree

## Deliverables

- repository audit report
- architecture map
- existing canonical source map
- trust and risk table
- documentation gap map
- isolation/migration plan
- prohibited legacy reuse list
- required human actions

## Brownfield rule

Preserve current behavior until a Change Request approves modification. A documentation improvement is not permission to refactor code.
