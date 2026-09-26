# Roblox Production Readiness

## Platform architecture

- Universe and every Place have explicit purpose
- dev/staging/production IDs are separated
- Teleport and Reserved Server failures have recovery
- Group ownership and contributor permissions are documented
- no legacy Place/Product/DataStore IDs are reused without approval

## Client/server security

- client never authoritatively sets currency, ownership, damage, rewards, rank, cooldown, or progression
- every Remote has typed payload, validation, rate limit, idempotency/replay policy, logging
- network ownership is deliberate for vehicles and physics objects
- exploit evidence does not depend on client-only telemetry

## Persistence

- versioned save schema
- default creation and migration
- session locking/concurrency strategy
- retry/backoff and budget handling
- corruption and partial-write recovery
- Studio does not touch production stores
- receipt processing is idempotent

## UI and devices

- mobile-first interaction budget
- safe areas and touch occlusion
- controller focus/navigation
- PC bindings
- device-specific assistance measured for fairness
- color, motion, audio, text-size accessibility
- all critical states work without voice chat

## Performance

- target device tiers and budgets
- StreamingEnabled strategy
- NPC, projectile, FX, Instance, memory, and network ceilings
- LOD/degradation presets
- profiler evidence at worst-case scenarios
- frame stability during first session and peak combat

## Commerce and policy

- products and entitlements separated by environment
- random-item disclosures and regional restrictions when applicable
- no hidden P2W path contradicting GDD
- moderation, content maturity, age/region implications recorded
- store copy matches actual behavior

## Assets and rights

- provenance and license recorded
- imported scripts inspected
- collision, LOD, texture, animation, audio budgets
- real-world insignia, brands, and historical assets reviewed
- replacement/fallback assets available for blocking risk

## Analytics and operations

- each KPI maps to implemented events
- event volume and field privacy controlled
- dashboards and alert owners named
- release health and rollback thresholds defined
- feature flags/emergency disable for risky systems
- player support and incident records defined
