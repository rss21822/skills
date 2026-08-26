# Security Audit Checklist — phase-separated

## A. D4 contract audit

- [ ] Enumerate every planned RemoteEvent, RemoteFunction, and UnreliableRemoteEvent in the non-empty machine-readable instance
- [ ] Define type, range, state, ownership, distance, cooldown, sequence, and rate-limit rules per action class
- [ ] Define duplicate receipt/reward/request ID rejection and idempotent DataStore/MemoryStore/receipt behavior
- [ ] Keep authoritative time, random outcomes, currency, inventory, rewards, rank, and competitive results on server by contract
- [ ] Define competitive hit validation and network ownership for every player-controlled physics assembly
- [ ] Define impossible transition detection, bounded secret/PII-safe evidence, false-positive review, and enforcement separation
- [ ] Define third-party script inspection/provenance and secret storage/client-exposure boundaries
- [ ] Define TeleportData and server join validation
- [ ] Name malicious payload, replay, spam, stale state, disconnect, and race tests with pass/fail rules and evidence paths

D4 does not require these tests to have run against nonexistent W0 code. Pass requires Critical 0 / Major 0 in the contract.

## B. W0–W2 implementation verification — not D4

- [ ] Enumerate actual runtime remotes and diff them against the D2 instance
- [ ] Execute all validation/rate/idempotency/authority tests
- [ ] Execute malicious payload, replay, spam, stale state, disconnect, and race tests
- [ ] Inspect imported third-party model/module scripts and record provenance evidence
- [ ] Confirm logs are bounded and contain no secrets/PII
