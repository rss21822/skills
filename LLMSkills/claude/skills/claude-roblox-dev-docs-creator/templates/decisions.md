# {{PROJECT}} — Decisions

## Decision template

`[DECISION]` は人間本人が直接承認した記録だけに使う。委任範囲内のAI承認は `[AI-APPROVED]` とし、委任元の人間 `[DECISION]`、適用範囲、根拠を参照する。`[AI-APPROVED]` はGate 1、D5、formal documentのApproved昇格を満たさない。

### D-{NNN}: {Title}

- Status: Proposed / Approved / Activated / Superseded
- Decision:
- Reason:
- Evidence:
- Approver:
- Approved revision:
- Affected documents:

## Stage transition template

遷移記録は追記専用。既存記録を上書きしない。人間 gate は承認者・時刻・対象revision・承認証拠を必須とする。

### STAGE-{NNN}: {SOURCE_STAGE} → {TARGET_STAGE}

- Status: Recorded / Superseded
- Source stage:
- Target stage:
- Entry verdict:
- Exit verdict:
- Source baseline ID / manifest / sha256:
- Target baseline ID / manifest / sha256:
- Evidence:
- Approval kind: human-direct / delegated-process / none
- Approver:
- Approved at: {ISO-8601 with timezone}
- Approval record:
- Machine approval record: `{path}`（outer SHA-256は後続transition/W0 packageに記録。承認対象baselineが本記録を含む場合、循環参照になるため本行へrecord hashを埋め込まない）
- Approved revision:
- Worker execution attestation:
- Incomplete Human Actions: {IDs or `none`}
- Next authorized action:

## AI approval template

### AI-{NNN}: {Title} `[AI-APPROVED]`

- Status: Active / Superseded
- Delegation decision: D-{NNN}
- Scope exercised:
- Evidence:
- Exercised by:
- Affected P0/stage artifacts:
- Explicitly not authorized: Gate 1 / D5 / formal document promotion / human-only or external-state action

### F-{NNN}: {Fallback}

- Fallback:
- Switch condition:
- Decision authority:
- Test/evidence:
- Activation record:
