# Trigger Matrix

Apply every row whose condition is true. Multiple rows may trigger together.

| Detected condition | Required output | Minimum contents |
|---|---|---|
| Any multiplayer, RemoteEvent/Function, PvP, economy mutation | Network & Security Spec + Remote contracts instance | instance: Remote ID/payload field/type/enum; Spec: authority, validation/failure, rate, replay/idempotency, ownership, abuse logs |
| DataStore, inventory, progression, settings, entitlement cache | Persistence & Migration Spec + Save instance | instance: field/type/version/default; Spec: lifecycle, session locking, migration, retry, corruption recovery, test/prod separation |
| Pass, Developer Product, subscription, purchasable currency | Commerce & Policy Spec + Commerce ledger instance | instance: key/product mapping/entitlement; Spec: receipt, grant/revoke, duplicate prevention, refunds, environment policy |
| Robux-linked RNG, purchasable keys/tickets, trading of random items | Paid Random Items Annex | actual odds, disclosure, restrictions, alternatives, pity/luck recalculation, trade eligibility |
| Any GDD KPI or release metric | Analytics & Observability Spec + Analytics events instance | instance: event ID/field/type; Spec: purpose, source, sampling/volume, retention, dashboards, alerts, privacy, test method |
| Mobile target, many NPCs, destruction, vehicles, dense FX, streaming | Performance Budget Spec | device tiers, FPS/memory/instance/network budgets, profiler procedure, degradation presets |
| Any external/imported/AI-generated asset | Asset & Content Pipeline Spec + Asset ledger instance | instance: asset ID/provenance/status; Spec: production rules, rights decisions, naming, LOD, collision, moderation, fallback, ownership |
| More than one Place, Teleport, Reserved Server, queue | Multi-Place & Matchmaking Spec | topology, records, join/rejoin, partial arrival, failure recovery, party integrity |
| Vehicle, horse, aircraft, ship, custom controller, ragdoll combat | Physics & Control Spec | state model, camera, input, network ownership, reconciliation, hit validation, accessibility |
| Free text, drawing, decals, player-published UGC, generative output | UGC & Moderation Spec | generation/input limits, moderation, reporting, blocking, storage, appeals, audit, fallback |
| More than one locale or global launch | Localization & Accessibility Spec | source strings, text expansion, fonts, RTL policy, input alternatives, color/audio accessibility |
| Seasons, weekly updates, events, daily seeds, admin events | LiveOps Content Spec | calendar, config activation, rollback, compatibility, content validation, emergency disable |
| Open Cloud, web APIs, MCP, webhooks, secrets | External Services & Secrets Spec | boundaries, secrets ownership, rotation, timeout, retry, outage mode, data policy |
| Real brands, historical insignia, military equipment, licenses, third-party IP | Rights & Provenance Ledger | source, license, permitted use, region, evidence, expiry, replacement path |
| Existing repository | Repository Audit | actual state, trust/confidence, gap map, migration and isolation plan |
| High-risk unproven mechanic | Feasibility Report | hypothesis, minimum prototype, evidence, result, D/F impact |

## Baseline requirements even without a separate spec

Every Roblox project still requires:

- server authority declaration
- client/server dependency direction
- no trust in client currency, damage, ownership, or rewards
- mobile input and UI states
- test and production environment separation
- release and rollback procedure
- asset provenance

If a condition is ambiguous, treat the spec as required until the owner explicitly removes it.
