# Quality Gates

## Gate 1 — GDD approval

- Product statement and primary action are unambiguous
- Target player and value are specific
- References include take/reject table
- MVP boundary is explicit
- Non-Goals >= 6 with reasons
- D/F pairs cover highest risks
- Success criteria are measurable
- Revenue, RNG, P2W, IP, maturity policy are decided
- No blocking product OQ

## Feasibility gate

- Prototype tests one risky assumption
- Measured on priority device
- Evidence is stored
- Pass/fail rule was set before test
- Failure activates a documented fallback or stops the project

## Gate 2 — Architecture completeness

- Module ownership and dependency direction defined
- Server authority matrix defined
- All Trigger Specs generated
- Machine-readable schemas exist where applicable
- No duplicate source of truth
- Every requirement has a design reference

## Gate 3 — Implementation planning

- Every Phase has entry/exit criteria
- Every WP fits a focused session
- File scope and do-not-touch scope exist
- Tests and evidence are named
- Rollback exists
- Human-only work has owner and due gate

## Gate 4 — Audit

Major findings = 0 for:

- consistency
- Roblox readiness
- clean-room handoff

## Gate 5 — Implementation ready

- Direct, explicit human D5 approval is recorded; `[AI-APPROVED]` is not a substitute
- P0 contracts/bootstrap is complete when the project uses it, and is recorded as a prerequisite rather than D5 itself
- Blocking OQ = 0
- Unapproved proposals = 0
- Unverified assumptions = 0
- Traceability = 100%
- Required files = 100%
- Build/test/serve commands confirmed
- Release/rollback confirmed
- First WP can start without a new product question
- Formal-document Status, Last approved, change history, decision log, docs index, and manifest were synchronized only after that human approval

## Never use as a quality gate

- total line count
- number of documents alone
- “looks comprehensive”
- model confidence
- successful generation without validation
