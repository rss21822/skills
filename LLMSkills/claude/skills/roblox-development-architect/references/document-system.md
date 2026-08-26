# Document System and Canonical Boundaries

## Core principle

A fact may be summarized in multiple documents, but only one document is authoritative. Every duplicate mention must link back to the canonical source rather than restating mutable details.

## Always-generated documents

| Domain | Canonical document | Owns |
|---|---|---|
| Document navigation | `{PREFIX}_docs_index.md` | Document list, status, canonical boundaries, link map |
| Product intent | `{PREFIX}_gdd.md` | What, why, target, scope, loops, MVP, Non-Goals, decisions |
| System structure | `{PREFIX}_detailed_design.md` | Modules, interfaces, runtime logic, state machines, dependency direction |
| Balance values | `{PREFIX}_data_definition.md` | Tunable numbers, formulae, tables, validation examples |
| UI and control | `{PREFIX}_ui_ux_input_spec.md` | Screens, states, flows, input budgets, device behavior, accessibility |
| Repository and tools | `{PREFIX}_toolchain_spec.md` | Repo tree, source mapping, versions, build/test/serve commands, environments |
| Execution order | `{PREFIX}_phase_plan.md` | Phases, gates, dependencies, stop conditions |
| AI implementation units | `{PREFIX}_work_packages.md` | File-level scope, do-not-touch, tests, rollback, Done definition |
| Verification | `{PREFIX}_test_spec.md` | Test cases, fixtures, runner, evidence, pass/fail rules |
| Human+AI operation | `{PREFIX}_workflow.md` | Roles, approvals, escalation, document maintenance |
| Release safety | `{PREFIX}_release_rollback_runbook.md` | dev/staging/prod, publish, canary, stop, rollback, recovery |
| Implementation rules | root `CLAUDE.md` | Coding constraints, commands, canonical references, prohibited actions |

## Always-generated operating files

| File | Owns |
|---|---|
| `PROGRESS.md` | Current phase/WP, blockers, tests, last known good commit, next authorized action |
| `ASSET_TODO.md` | Asset requirements, owner, rights, status, blocking WP |
| `HUMAN_ACTIONS.md` | Dashboard, Studio, credentials, moderation, IDs, production-only operations |
| `AI_ACTIONS.md` | Approved bounded machine actions, authority, input hashes, evidence, cleanup |
| `CHANGELOG.md` | Versioned project/document changes |
| `DECISIONS.md` | D-n/F-n decisions, evidence, approver, activation records |

## Conditional specifications

Each triggered document becomes authoritative only for its domain. The detailed design references it.

- Network & Security
- Persistence & Migration
- Commerce & Policy
- Paid Random Items Annex
- Analytics & Observability
- Performance Budget
- Asset & Content Pipeline
- Multi-Place & Matchmaking
- Physics & Control
- UGC & Moderation
- Localization & Accessibility
- LiveOps Content
- External Services & Secrets
- Rights & Provenance

## Precedence when conflict exists

1. Human-approved decision record
2. Canonical document for the domain
3. Approved conditional specification
4. Work Package
5. Test specification
6. Implementation code comments

Code is not permitted to silently redefine product intent, balance, policy, or interface contracts. A discovered conflict stops the Work Package and opens a Change Request.

## Numeric ownership

- Gameplay and economy numbers: Data Definition
- Performance ceilings: Performance Budget Spec
- Retry/backoff/storage limits: Persistence or Network Spec
- UI dimensions and breakpoints: UI/UX/Input Spec
- Test expected values: copied by reference from the owning specification; do not recalculate independently
- Product IDs and entitlement mapping: Commerce Ledger

## Temporary canonical source

A downstream specification may temporarily resolve an upstream omission only when it declares:

- exact temporary rule
- reason
- upstream destination
- expiry condition
- owner

After upstream incorporation, replace the temporary section with an incorporation record. Never leave two live sources.
