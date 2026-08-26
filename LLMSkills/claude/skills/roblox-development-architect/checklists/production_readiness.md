# Roblox Production Readiness Audit

## Architecture
- [ ] Universe/Place topology is complete
- [ ] dev/staging/production separation is explicit
- [ ] source mapping and package versions are locked
- [ ] clean checkout build/test instructions work

## Security
- [ ] authority matrix exists
- [ ] all client→server remotes are validated and rate-limited
- [ ] currency, damage, inventory, rank, rewards, and receipts are server-owned
- [ ] vehicle/network ownership has an anti-abuse plan
- [ ] false-positive and enforcement handling exists

## Persistence
- [ ] versioned schema and defaults
- [ ] session locking and retries
- [ ] migrations and fixtures
- [ ] corruption recovery
- [ ] Studio/test stores isolated from production

## UI/device
- [ ] mobile first-session flow verified
- [ ] controller focus and PC input defined
- [ ] safe areas, touch occlusion, text expansion considered
- [ ] critical information is color/audio independent
- [ ] motion/camera reduction available where needed

## Performance
- [ ] device-tier budgets exist
- [ ] worst-case test scene defined
- [ ] profiler evidence collected
- [ ] degradation presets are deterministic
- [ ] release stop thresholds defined

## Commerce/policy
- [ ] environment product IDs separated
- [ ] receipt idempotency tested
- [ ] random item policy handled if applicable
- [ ] store copy matches functionality
- [ ] content maturity and regional restrictions reviewed

## Assets/rights
- [ ] provenance ledger complete
- [ ] third-party scripts inspected
- [ ] LOD/collision/texture/audio budgets met
- [ ] IP fallbacks ready

## Operations
- [ ] analytics events implemented and tested
- [ ] dashboards/alerts have owners
- [ ] release and rollback rehearsed
- [ ] emergency feature disable exists
- [ ] human actions resolved or scheduled
