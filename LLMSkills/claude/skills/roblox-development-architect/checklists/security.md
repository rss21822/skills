# Security Audit Checklist

- [ ] Enumerate all RemoteEvents, RemoteFunctions, and UnreliableRemoteEvents
- [ ] Validate type, range, state, ownership, distance, cooldown, and sequence
- [ ] Rate-limit by player and action class
- [ ] Reject duplicate receipt/reward/request IDs
- [ ] Keep authoritative time and random outcomes on server
- [ ] Do not trust client position for final competitive hit without validation
- [ ] Define network ownership for every player-controlled physics assembly
- [ ] Detect impossible state transitions rather than only impossible values
- [ ] Log evidence with bounded volume and no secrets/PII
- [ ] Separate exploit detection from punishment; document false-positive review
- [ ] Inspect third-party models/modules for scripts and require provenance
- [ ] Store secrets outside repository and never expose them to clients
- [ ] Validate TeleportData and server join records
- [ ] Use idempotent DataStore/MemoryStore/receipt operations
- [ ] Test malicious payloads, replay, spam, stale state, disconnect, and race conditions
