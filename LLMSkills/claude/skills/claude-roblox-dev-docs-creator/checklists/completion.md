# Lifecycle Completeness Checklist

## A. Pre-D4 candidate completeness

This section is input to each D4 lane. It must not require D4's own verdict, P0, D5, W0 implementation, or release rehearsal.

- [ ] D0 intake answers have item IDs, source classification, and human confirmation where required
- [ ] Repository Audit complete when brownfield
- [ ] Gate 1 human approval records the GDD revision; formal header remains `Status: Draft`
- [ ] Required D1.5 reports are PASS under the declared environment rule; device-dependent hypotheses are not PASS without priority-device evidence
- [ ] Trigger Matrix applied and all Required Specs generated
- [ ] Required machine-readable contract instances are non-empty and validate against their JSON Schemas with warning 0 / note 0
- [ ] Phase Plan, candidate Work Packages, Test Specification, Toolchain, Workflow, Runbook, and operating ledgers exist
- [ ] Every requirement maps to design, candidate WP, and test; traceability is 100%
- [ ] build/test/serve command contracts and planned entrypoint paths are explicit; pre-D4 documentation validators are executable, while product-code entrypoints and successful product runs are due in their assigned W0+ packages
- [ ] release/rollback contracts, owners, stop thresholds, and evidence obligations are defined
- [ ] first candidate Work Package can start after D5 authorization without a new product decision
- [ ] every remaining proposal/blocking open/unverified assumption is uniquely registered in `PROGRESS.md` § Proposed P0 closure inventory with source ID/path, an exactly bounded closure question/scope, owner, closure evidence/pass rule, and affected canonical documents; no unregistered or W0-dependent unresolved item remains
- [ ] candidate manifest, canonical/evidence allowlist, hashes, and validator outputs are fixed

## B. D4 consolidation — orchestrator only

Do not place this section inside a lane's own pass prerequisites.

- [ ] consistency lane: Critical 0 / Major 0
- [ ] Roblox readiness lane: Critical 0 / Major 0
- [ ] clean-room lane: Critical 0 / Major 0
- [ ] all three lanes used the same candidate manifest and capsule hash
- [ ] successful `D4-CAND-n` promoted unchanged to B0; promotion record binds `promotedFrom`, candidate manifest hash, and equal file-set hash

## C. P0 and D5

Not part of initial D4.

- [ ] human P0-start approval targets B0; P0-contract approval targets the final `P0-CAND-n`; P0-start / P0-contract / D5 IDs and machine records are all distinct
- [ ] P0 checker/lint/validators: error 0 / warning 0 / note 0
- [ ] post-P0 `P0-CAND-n` passed B0→candidate three-lane delta D4 and was promoted unchanged to B1; raw reports still identify the candidate
- [ ] blocking OQ 0, `[PROPOSAL]` 0, unverified `[ASSUMPTION]` 0; every B0 historical P0 inventory ID has one Completed record with actual evidence and affected-document post-change hashes; an exception/deviation record does not satisfy these conditions
- [ ] direct human D5 approval targets B1
- [ ] B1→B2 diff contains only allowed metadata, approval/operation ledger entries, first-WP authorization, and generated index/manifest changes
- [ ] B2 lifecycle manifest and D5 Last Known Good recorded without self-inclusion; W0 package is outside the B2 file set

## D. W0–W2 / release verification

Never use these post-implementation checks to fail pre-implementation D4.

- [ ] product code and automated tests pass from a clean checkout
- [ ] W0 validates `docs/evidence/d5/<D5-ID>_w0_handoff_package.json` and re-derives B0/B1/B2 hashes from exact commit blobs or project-relative immutable snapshot roots
- [ ] required Studio and priority-device evidence collected
- [ ] implemented Remote/save/commerce/analytics contracts validate against D2 instances
- [ ] performance/security/malicious-input tests pass
- [ ] release and rollback rehearsed in the authorized non-production environment
- [ ] each WP completion synchronized code, tests, evidence, detailed Status, mirrors, traceability, progress, and changelog
