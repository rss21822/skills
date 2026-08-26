# Consistency Audit Checklist

Scope: D4 candidate documents and machine-readable instances. Formal documents, including the Gate1-approved GDD, remain `Draft` through B1; D5 alone applies fixed approval metadata.

## Canonicality

- [ ] Every mutable fact has one declared canonical source
- [ ] Duplicate mentions use references, not copied values
- [ ] Document Index matches actual files and statuses
- [ ] Temporary canonical sections have expiry and upstream target
- [ ] Machine-readable instance owns field/type/ID/enum; Markdown owns semantics/failure policy; neither redefines the other
- [ ] Work Package detailed section is the sole Status source; index and PROGRESS are synchronized mirrors

## Decisions and states

- [ ] Every D-n has a corresponding F-n where risk warrants it
- [ ] Fallbacks have measurable switch conditions and approver
- [ ] Initial D4: every proposal, blocking open, or unverified assumption is uniquely registered in `PROGRESS.md` § Proposed P0 closure inventory with source ID/path, an exactly bounded closure question/scope, owner, closure evidence/pass rule, and affected documents; post-P0 D4: all three counts are 0 and every B0 historical inventory ID maps one-to-one to a Completed record, actual evidence, and affected-document post-change hashes
- [ ] Post-P0 D4 only: the capsule binds the outer P0 lifecycle transition attestation, complete write log, and external provenance; fixed policy validation proves B0 start state/full target scope, approval chronology, exact allowed writes, zero unlogged writes, and the candidate result before B1 promotion
- [ ] No P0 inventory row or P0 candidate changes the Gate 1-approved intake, rederived required specs, GDD bytes/path/revision, or Gate 1 chain; any required change restarted at D0/D1 with a unique new Gate 1 and new initial D4/B0

## Cross-document links

- [ ] GDD MVP matches Phase Plan and Work Packages
- [ ] Data values referenced by ID, not duplicated
- [ ] UI states map to runtime states
- [ ] Remote contracts match Detailed Design interfaces
- [ ] Save schema matches inventory/economy catalogs
- [ ] Tests reference canonical expected values
- [ ] Every requirement maps to design, WP, and test
- [ ] Each required machine-readable instance is non-empty and schema-valid with warning 0 / note 0

## Revision control

- [ ] Every formal document has version/status/change history; the Gate1-approved exact Draft GDD remains byte-identical through B1, and D5 changes only its fixed formal metadata while preserving normalized body content
- [ ] Superseded documents point to replacements
- [ ] CHANGELOG and DECISIONS include major changes
- [ ] Impact table completed for changed facts

## Residuals

- [ ] No legacy project names or obsolete IDs
- [ ] No broken relative links
- [ ] No unresolved template placeholders
- [ ] No broken references to required D4 documents, instances, sections, or evidence; planned W0+ code paths are allowed when their owner and due WP are explicit

D4 lane pass requires Critical 0 / Major 0. Missing code or post-W0 evidence is not a consistency defect when the implementation obligation is fully defined.
