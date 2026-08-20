# {{PROJECT}} — D4 Findings Record

| Field | Value |
|---|---|
| Record ID | {{PREFIX}}-D4-{TRACK}-{CANDIDATE_ID}-R{ROUND} |
| Audit track | consistency / roblox-readiness / clean-room |
| Candidate baseline ID | D4-CAND-* / P0-CAND-* |
| Candidate manifest | {path} |
| Candidate manifest SHA-256 | {sha256} |
| Candidate fileSetSha256 | {sha256} |
| Storage path | docs/audits/{{PREFIX}}_d4_{TRACK}_{CANDIDATE_ID}_r{ROUND}.md |
| Auditor attestation | {path} / sha256 {sha256} |
| Position | State record, not a canonical product/design document |
| Verdict | pass / fail |

`Severity`、`Confidence`、`State tag` は別軸。混ぜない。D4監査者はfindings-only/read-onlyで、正本文書を変更しない。

## Summary

- Critical: {n}
- Major: {n}
- Minor: {n}
- Observation: {n}
- Verdict rule: Critical `0` and Major `0` only → `pass`
- Route: initial `pass` → `D4合格 / P0着手資格あり（人間P0開始承認待ち）` → B0昇格; post-P0 `pass` → `post-P0 D4合格 / B1昇格可 / D5提示可能`; initial `fail` → `D4不合格 / D0〜D3是正へ`; post-P0 `fail` → `post-P0 D4不合格 / P0是正へ`

## Findings

### D4-{TRACK}-{NNN}: {title}

- Severity: Critical / Major / Minor / Observation
- Confidence: Confirmed / Reported / Inferred / Missing / Conflicting
- State tag: `[FACT]` / `[PROPOSAL]` / `[OPEN blocking: yes|no]`
- Category:
- Canonical evidence: `{path} §{section}`
- Candidate evidence: `{path}` / sha256 `{sha256}`
- Impact:
- Required correction direction:
- Owning D0-D3 document/role:
- Status: Open / Resolved / Accepted observation
- Resolution evidence: {path or `none`}

## Coverage

- Canonical allowlist received:
- Sanitized evidence manifest received:
- Initial-D4 inventory source: candidate `PROGRESS.md` / `## Proposed P0 closure inventory` / inventory ID / file SHA-256: {values or `not-applicable`}
- post-P0 inventory source: B0 historical `PROGRESS.md` / section / inventory ID / file SHA-256: {values or `not-applicable`}
- post-P0 candidate state: P0-CAND `PROGRESS.md` file SHA-256 / proposed inventory data-row count: {sha256 / `0`, or `not-applicable`}
- Remaining proposal/open/assumption IDs found: {complete qualified IDs or `none`}
- Inventory coverage verdict: complete / incomplete / post-P0-not-applicable
- post-P0 closure evidence checked: {all B0 historical inventory IDs → P0-CAND `PROGRESS.md` Completed evidence/affected-doc hashes; candidate inventory data rows must be 0, or `not-applicable`}
- Files inspected:
- Required files not received:
- Commands run and outputs:

## Execution attestation

- worker / class:
- requested and resolved model/version:
- read-only sandbox / network:
- request/response hashes:
- finish reason / exit code:
