# D0–D7 Workflow Details

## D0 — Intake

Outputs:

- `{PREFIX}_intake.json`
- D0 answer summary
- initial state tags
- BROWNFIELD repository-audit request when applicable

Stop if the owner has not confirmed the product thesis, primary risk, MVP questions, and device priority.

## D0-R — Repository Audit (BROWNFIELD only)

Read-only pass first. Record:

- tree and source mapping
- current Universe/Place topology
- actual build/test/publish commands
- package/tool versions
- current remotes, persistence, monetization, analytics
- legacy and production coupling
- documentation gaps and confidence level

Do not refactor while auditing.

## D1 — GDD

The GDD writer may propose but not approve. A human must explicitly approve the GDD. “Looks good” or equivalent is acceptable; silence is not.

Gate 1 rejects:

- undefined primary player action
- MVP mixed with future backlog
- fewer than six reasoned Non-Goals
- no measurable core hypothesis
- P2W/RNG/IP policy left ambiguous
- unresolved blocking product question

## D1.5 — Feasibility

Use the smallest prototype that can falsify the riskiest assumption. It is not a vertical slice and must not contain economy, cosmetic store, content catalog, or polished art unless they are the risk under test.

Required report:

- hypothesis
- prototype scope
- test devices and network conditions
- metrics and human observations
- evidence location
- result
- D/F recommendation
- GDD impact

## D2 — Architecture

Generate the baseline architecture and all Trigger Specs. Parallel work is allowed only if agents share the approved GDD and Repository Audit, and the orchestrator resolves interface conflicts afterward.

Required machine-readable artifacts:

- docs manifest
- requirements traceability CSV
- remote contracts when triggered
- save schema and migrations when triggered
- analytics events when triggered
- asset ledger when triggered
- commerce ledger when triggered

## D3 — Process and implementation planning

A Phase is a management boundary. A Work Package is the unit the coding AI may execute.

A Work Package must:

- fit one focused coding session
- have explicit file scope
- name prohibited changes
- state public interfaces
- name exact tests and evidence
- provide rollback
- update documents as part of Done

## D4 — Audits

Run three independent audits:

1. Consistency
2. Roblox production readiness
3. Clean-room handoff

Auditors produce findings only. Writers fix findings. Repeat until no major finding remains.

## D5 — Final human approval

If the project uses P0 contracts/bootstrap, run P0 after D4 and before D5. P0 produces the D5 input packet; it does not satisfy D5 and must leave formal-document `Status` and `Last approved` unchanged.

Present:

- final file tree
- canonical boundaries
- triggered specs
- high-risk decisions and fallbacks
- remaining Human Actions
- first authorized Work Package
- validation output

No “implementation ready” claim before direct, explicit human approval. Delegated `[AI-APPROVED]`, blanket delegation, or silence cannot satisfy D5.

In the same change unit as direct D5 approval, update each affected formal document's `Status: Approved`, `Last approved`, and change history; record the human `[DECISION]`; then regenerate the docs index and manifest. Do not perform this promotion during P0.

## D6 — Implementation synchronization

For every WP:

1. verify scope and current revision
2. implement contract-first or test-first
3. run automatic tests
4. run required Studio verification
5. collect evidence
6. update progress, traceability, changelog, and affected specifications
7. record last known good commit
8. stop before the next WP unless authorized

## D7 — Change and sub-spec lifecycle

Any new feature, platform change, or discovered omission creates a Change Request. Determine whether it is:

- clarification: no product behavior change
- minor: local behavior and tests
- major: architecture, economy, policy, compatibility, or product scope

Major changes return to the applicable human approval gate.
