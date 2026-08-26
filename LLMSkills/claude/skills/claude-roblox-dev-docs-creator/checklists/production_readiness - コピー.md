# Roblox Readiness — phase-separated checklist

## A. D4 design readiness

Use this section for the D4 Roblox-readiness lane. It checks contracts, not nonexistent W0 code.

### Architecture
- [ ] Universe/Place topology and dependency direction are complete
- [ ] dev/staging/production separation and production-touch boundaries are explicit
- [ ] source mapping, package pins, build/test/serve entrypoints, and clean-checkout procedure are defined

### Security
- [ ] authority matrix and all planned Remote contracts exist
- [ ] validation/rate/sequence/ownership and anti-abuse rules have named tests and evidence paths
- [ ] currency, damage, inventory, rank, rewards, receipts, and random outcomes are server-owned by contract
- [ ] false-positive review and enforcement ownership are defined

### Persistence
- [ ] non-empty versioned save instance, defaults, migration table, locking/retry/idempotency contracts exist
- [ ] fixtures, corruption recovery, and Studio/test isolation have named verification procedures

### UI/device
- [ ] mobile first-session, controller focus, PC input, safe area, touch occlusion, text expansion, accessibility behavior are specified
- [ ] priority-device hypotheses follow the actual-device rule; missing device-specific evidence is `INCONCLUSIVE`, not PASS
- [ ] later physical-device checks have owner, evidence format, and due gate

### Performance
- [ ] device-tier budgets, worst-case scene, measurement method, degradation presets, and stop thresholds are defined
- [ ] D1.5 evidence exists where a pre-design high-risk hypothesis required it

### Commerce/policy/assets
- [ ] non-empty commerce and asset ledger instances exist when triggered
- [ ] environment key separation, receipt idempotency contract, random-item policy, maturity/region, provenance, third-party inspection, budgets, and IP fallback are defined

### Operations
- [ ] analytics instance, alert/dashboard owners, emergency disable, release/rollback procedures, and Human Actions are defined
- [ ] Initial D4 has no unresolved item outside `PROGRESS.md` § Proposed P0 closure inventory and no item whose closure depends on W0 implementation; post-P0 D4 has blocking OQ/proposal/unverified assumption 0 and independently verifies each B0 inventory ID's Completed evidence and affected-document hashes
- [ ] Post-P0 D4 only: operator-pinned external provenance verifies the P0 transition's B0 start state, full monitored mutation scope, approval-ordered complete write log, snapshot full-file freeze, post-freeze record, one atomic apply per changed canonical path, final seal, zero unlogged/post-seal writes, and exact P0-CAND result

Pass: Critical 0 / Major 0.

## B. W0–W2 / release verification — not a D4 prerequisite

- [ ] clean checkout product build and automated tests pass
- [ ] implemented Remotes pass validation, abuse, replay, spam, stale-state, disconnect, and race tests
- [ ] save migrations/recovery and receipt idempotency pass in an authorized isolated environment
- [ ] mobile/controller/PC flows and required priority devices are physically verified
- [ ] worst-case profiler evidence meets budgets; degradation and stop thresholds activate correctly
- [ ] assets meet LOD/collision/texture/audio budgets and third-party scripts are inspected
- [ ] analytics implementation, dashboards, alerts, emergency disable, release, and rollback are exercised

Unchecked B items before W0 are expected and must not be reported as D4 Critical/Major solely because implementation does not yet exist.
