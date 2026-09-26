# {{PROJECT}} — AI Actions

`[AI-ACTION]` の機械作業だけを記録する。人間専権は `[HUMAN]` として `HUMAN_ACTIONS.md` へ分離する。

| ID | Action | Exec | Approval / authority | Input hashes | Status | Evidence | Closed at |
|---|---|---|---|---|---|---|---|
| AI-001 | [AI-ACTION] `<bounded action>` | `blocked-permission` | `<approval ID or inherited authority>` | `<sha256 list>` | Blocked | `<raw evidence path / tool result ID>` | - |

Rules:

- `approved-transfer` requires the approved transfer envelope, context-bundle hashes, and execution attestation.
- `blocked-permission` and `blocked-capability` are not executed; never mark them `Done`.
- Do not register `H-*`, `human-only`, or the human approval act itself.
- On completion, retain raw evidence, measured results, and cleanup state.
