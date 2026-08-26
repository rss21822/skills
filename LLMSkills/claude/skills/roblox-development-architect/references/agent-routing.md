# Agent Routing

## Named roles and worker selection

以下の名前は固定プラグインや特定モデルの識別子ではなく、owner／orchestrator が選定した worker に delegation packet で明示的に assume させる責務名である。

| Named role | Primary role | Must not do |
|---|---|---|
| `product-gdd-writer` | GDD from approved intake | approve own proposals, define implementation internals |
| `repository-auditor` | read-only brownfield audit | edit source or refactor |
| `system-architect` | modules, state, interfaces, topology | own balance or product intent |
| `data-economy-writer` | balance, economy, formulas, Config validation | design UI or network trust |
| `ui-input-writer` | UI states, flows, device input, accessibility | invent server authority rules |
| `platform-security-writer` | network, persistence, commerce, policy, analytics foundation | modify GDD decisions |
| `dev-process-writer` | phase plan, WPs, tests, workflow, runbook | change gameplay scope silently |
| `sub-spec-writer` | one triggered domain specification or change request | create a second canonical source |
| `consistency-auditor` | cross-document contradictions | edit documents |
| `roblox-readiness-auditor` | production/platform completeness | edit documents |
| `clean-room-auditor` | handoff test with no conversation assumptions | fill missing decisions |

## Parallelization

Safe parallel set after GDD approval:

- system-architect
- data-economy-writer
- ui-input-writer
- platform-security-writer

The orchestrator must then perform an interface reconciliation pass before D3.

Unsafe parallelization:

- GDD and architecture before product approval
- architecture and feasibility on the same unresolved risk
- writer and auditor editing the same file
- multiple agents owning the same canonical numeric table

## Delegation packet

Every delegation includes:

1. mode and current phase
2. approved inputs and revision IDs
3. exact output files
4. canonical boundary
5. state tags allowed
6. do-not-change list
7. required checks
8. return format: changes, decisions requested, blocking issues, downstream impact

The orchestrator records the selected worker for each named role before work starts. A worker may assume a role only after receiving this packet. Auditors must be distinct from the writer whose output they inspect and remain read-only.

If no eligible worker is available for a canonical writing or audit role, record a blocker and ask the owner for a worker or revised route. The orchestrator/main context must not become a canonical writer fallback, and a writer self-audit must not substitute for an independent auditor.
