# Source of Truth, State Tags, and Change Propagation

## State tags

Use tags on any statement that is not plainly approved product text.

- `[FACT]` source-confirmed
- `[DECISION]` directly approved by a human owner; a delegated AI cannot create this tag
- `[AI-APPROVED]` stage-local AI approval exercised under a referenced human `[DECISION]`; it is not human approval and cannot satisfy Gate 1, D5, or formal-document promotion
- `[PROPOSAL]` AI suggestion awaiting decision
- `[ASSUMPTION]` testable premise awaiting evidence
- `[OPEN blocking: yes|no]` unresolved question
- `[HUMAN]` operation requiring a person; never an AI execution candidate
- `[AI-ACTION]` action executable by AI within current authority and capability; track in `AI_ACTIONS.md`, never `HUMAN_ACTIONS.md`
- `[EXTERNAL]` external dependency or researched input

A document cannot change from Draft to Approved while it contains `[PROPOSAL]`, blocking `[OPEN]`, or unverified `[ASSUMPTION]`. Only direct human D5 approval can promote a formal document to Approved; `[AI-APPROVED]` cannot.

## Decision format

```text
D-12 [DECISION] Server owns hit confirmation.
Reason: competitive PvP and client tampering risk.
Evidence: NET test SV-14.
F-12: server validates a client-predicted candidate hit.
Switch condition: mobile latency P95 exceeds approved threshold after compensation test.
Approver: project owner.
Revision: 1.2.0.
```

Each fallback has a switch condition, approver, and affected documents.

## Change propagation

For any change, create an impact table:

| Changed fact | Canonical source | Downstream references | Tests | WPs | Migration/compatibility |
|---|---|---|---|---|---|

Update in this order:

1. approved decision
2. canonical source
3. machine-readable schema
4. downstream references
5. tests
6. work packages
7. progress/changelog

## Temporary source rule

Temporary downstream authority is permitted only when the upstream document cannot yet be edited and the temporary section names:

- upstream target
- exact rule
- expiration event
- owner
- status

After incorporation, replace it with a record such as “Incorporated into Data Definition v1.3 §4.2 on YYYY-MM-DD.”
