# Clean-Room Handoff Audit — D4 lane

Scope: initial full D4 or post-P0 D4 delta. The auditor reads only the hash-pinned audit capsule from `references/audit-d4.md`; prior conversation, findings, handoffs, expected verdict, and repository-wide search are prohibited.

At D4 the first Work Package is a **candidate**, not yet authorized. Initial D4 is followed by the separately recorded human P0-start and P0-contract gates; post-P0 D4 is followed by D5 human approval and B1→B2 metadata sync. Do not fail D4 merely because a declared later gate has not yet occurred.

1. What is the product and its primary action?
2. What is in Launch MVP and explicitly out?
3. Which document or machine-readable instance uniquely owns each mutable domain?
4. Which candidate Work Package becomes first after D5 authorization?
5. Which files may it create/modify, and which are prohibited?
6. What public interfaces and machine-readable contracts must it implement?
7. What exact build/test/serve commands and named tests must run?
8. What Studio/manual evidence must W0 produce at Done?
9. What performance/security limits and pass/fail rules apply?
10. How is the change rolled back?
11. Which code, evidence, Status mirror, traceability, and documents must update atomically at Done?
12. Is any new product/human decision required before the first WP can start outside the stage-allowed set: for initial D4, the exact `PROGRESS.md` P0 closure inventory plus the P0-start, P0-contract, and D5 gates; for post-P0 D4, D5 only?

Pass only when question 12 is “No,” every allowed future decision is fully bounded by the candidate rather than newly invented later, all other answers are concrete and internally consistent, and Critical = 0 / Major = 0. Missing implementation or post-W0 evidence is not a D4 defect when its contract, owner, test, evidence path, and due gate are defined.
