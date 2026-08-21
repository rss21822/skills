# Consistency Audit Checklist

## Canonicality

- [ ] Every mutable fact has one declared canonical source
- [ ] Duplicate mentions use references, not copied values
- [ ] Document Index matches actual files and statuses
- [ ] Temporary canonical sections have expiry and upstream target

## Decisions and states

- [ ] Every D-n has a corresponding F-n where risk warrants it
- [ ] Fallbacks have measurable switch conditions and approver
- [ ] No approved document contains `[PROPOSAL]`
- [ ] No approved document contains unresolved blocking `[OPEN]`
- [ ] Assumptions have tests or have been converted to facts/decisions

## Cross-document links

- [ ] GDD MVP matches Phase Plan and Work Packages
- [ ] Data values referenced by ID, not duplicated
- [ ] UI states map to runtime states
- [ ] Remote contracts match Detailed Design interfaces
- [ ] Save schema matches inventory/economy catalogs
- [ ] Tests reference canonical expected values
- [ ] Every requirement maps to design, WP, and test

## Revision control

- [ ] Every document has version/status/change history
- [ ] Superseded documents point to replacements
- [ ] CHANGELOG and DECISIONS include major changes
- [ ] Impact table completed for changed facts

## Residuals

- [ ] No legacy project names or obsolete IDs
- [ ] No broken relative links
- [ ] No unresolved template placeholders
- [ ] No references to nonexistent files or sections
