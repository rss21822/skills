# Lifecycle Completeness Checklist

## A. Pre-D4 candidate completeness

This section is input to each D4 lane. It must not require D4's own verdict, P0, D5, W0 implementation, or release rehearsal.

- [ ] D0 intake answers have item IDs, source classification, and human confirmation where required
- [ ] Repository Audit complete when brownfield
- [ ] Gate 1 human approval records the exact Draft GDD path/hash/revision through challenge/capture/operator-pinned external provenance/machine record; those bytes remain immutable through B1, and D5 changes only fixed formal metadata while preserving the normalized body digest
- [ ] Required D1.5 reports are PASS under the declared environment rule and each triggered raw measurement has operator-pinned external runtime provenance; device-dependent hypotheses are not PASS without priority-device evidence
- [ ] Trigger Matrix applied and all Required Specs generated
- [ ] Required machine-readable contract instances are non-empty and validate against their JSON Schemas with warning 0 / note 0
- [ ] Phase Plan, candidate Work Packages, Test Specification, Toolchain, Workflow, Runbook, and operating ledgers exist
- [ ] Every requirement maps to design, candidate WP, and test; traceability is 100%
- [ ] build/test/serve command contracts and planned entrypoint paths are explicit; pre-D4 documentation validators are executable, while product-code entrypoints and successful product runs are due in their assigned W0+ packages
- [ ] release/rollback contracts, owners, stop thresholds, and evidence obligations are defined
- [ ] first candidate Work Package can be handed to W0 after D5 without a new product decision; side effects still wait for monitored PREPARE→VALIDATE, closed human run authorization, expected-only signed ADMIT semantic PASS, atomic admission-token consumption, suspended/pre-entry actual-closure proof in a signed receipt, bootstrap PASS, and atomic worker-ready capability consumption
- [ ] every remaining proposal/blocking open/unverified assumption is uniquely registered in `PROGRESS.md` § Proposed P0 closure inventory with source ID/path, an exactly bounded closure question/scope, owner, closure evidence/pass rule, and affected canonical documents; no unregistered or W0-dependent unresolved item remains
- [ ] candidate manifest, canonical/evidence allowlist, hashes, validator outputs, and current installed-skill canonical D4 audit policy manifest are fixed

## B. D4 consolidation — orchestrator only

Do not place this section inside a lane's own pass prerequisites.

- [ ] consistency lane: Critical 0 / Major 0
- [ ] Roblox readiness lane: Critical 0 / Major 0
- [ ] clean-room lane: Critical 0 / Major 0
- [ ] all three lanes used the same candidate manifest/capsule/policy hash, unique canonical full prompts, and externally verified Class A runtime provenance
- [ ] successful `D4-CAND-n` promoted unchanged to B0; promotion record binds `promotedFrom`, candidate manifest hash, and equal file-set hash

## C. P0 and D5

Not part of initial D4.

- [ ] human P0-start approval targets B0; human P0-contract approval targets the planned candidate ID plus pre-freeze normalized digest and B0 source revision, then its machine record binds the once-frozen actual `P0-CAND-n`; no future candidate hash/revision is requested; Gate1 / P0-start / P0-contract / D5 IDs, captures, external provenance, and machine records are all distinct
- [ ] P0 checker/lint/validators: error 0 / warning 0 / note 0
- [ ] P0 lifecycle transition proof externally verifies the B0 monitoring start state and full target scope, all approval-ordered writes, every snapshot file, post-freeze machine record, one atomic frozen-byte apply per changed canonical path, final seal, zero unlogged/post-seal writes, and the resulting snapshot-only P0-CAND; every snapshot member has link count 1, a unique OS identity, and no identity overlap with canonical/staging source; post-P0 D4 capsule binds and validates that outer proof before B1 promotion
- [ ] post-P0 `P0-CAND-n` passed B0→candidate three-lane delta D4 or the required full escalation and was promoted unchanged to B1; raw reports still identify the candidate and all three lanes use the same mode
- [ ] blocking OQ 0, `[PROPOSAL]` 0, unverified `[ASSUMPTION]` 0; every B0 historical P0 inventory ID has one Completed record with actual evidence and affected-document post-change hashes; an exception/deviation record does not satisfy these conditions
- [ ] direct human D5 approval targets B1 and its external channel provenance was fixed as an offline `pinned-signature` proof before immutable binding; query-mode evidence is not accepted by the W0 route
- [ ] B1→B2 diff contains only allowed metadata, approval/operation ledger entries, first-WP authorization, and generated index/manifest changes; GDD body-normalized digest remains equal to Gate1-approved B1 bytes
- [ ] D5 lifecycle transition proof externally verifies the B1 monitoring start state and full sync/staging mutation scope, no B1→B2 sync or product-metadata write before D5 verification, exactly one atomic final write per changed canonical path, allowed-diff/post-sync creation, every B2 snapshot file, final seal, zero unlogged/post-seal writes, and the resulting snapshot-only B2; every snapshot member has link count 1, a unique OS identity, and no identity overlap with canonical/staging source; evidence-acquisition and fixed post-monitor proof-sealing exclusions are exact
- [ ] B2 lifecycle manifest and D5 Last Known Good recorded without self-inclusion; W0 package is outside the B2 file set

## D. W0–W2 / release verification

Never use these post-implementation checks to fail pre-implementation D4.

- [ ] product code and automated tests pass from a clean checkout
- [ ] W0 validates `docs/evidence/d5/<D5-ID>_w0_handoff_package.json` entirely offline under externally monitored PREPARE→VALIDATE; query-mode provenance/network adapters are rejected; it validates current installed-skill D4 policy/full prompts and both `lifecycleTransitions`, rejects commit-backed lifecycle revisions, and re-derives all B0/B1/B2 hashes from project-relative immutable snapshot roots while rejecting symlink/junction/reparse/hardlink members, link count other than 1, duplicate identities, identity overlap, and manifest/TREE extra or missing bytes
- [ ] VALIDATE retains the authority lock and temp closure; the operator-external human run-authorization chain exact-binds current B2/package/WP, machine-derived frozen/disjoint write paths, receiver Skill tree/expected process closure, worker, transfer, operations, denials, and expiry; expected-only signed ADMIT rechecks current identities/no-gap lock/no prior side effect, then semantic PASS precedes atomic admission-token consumption and suspended/pre-entry worker launch; signed receipt proves actual closure equality/zero effects and an unused short global-nonreuse worker-ready capability, bootstrap verifies it before PASS, and authority consumes that capability only immediately before the first scoped effect
- [ ] required Studio and priority-device evidence collected
- [ ] implemented Remote/save/commerce/analytics contracts validate against D2 instances
- [ ] performance/security/malicious-input tests pass
- [ ] release and rollback rehearsed in the authorized non-production environment
- [ ] each WP completion synchronized code, tests, evidence, detailed Status, mirrors, traceability, progress, and changelog
