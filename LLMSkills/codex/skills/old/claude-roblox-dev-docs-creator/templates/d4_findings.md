# {{PROJECT}} — D4 Findings Record

| Field | Value |
|---|---|
| Record ID | {{PREFIX}}-D4-{TRACK}-{CANDIDATE_ID}-R{ROUND} |
| Audit track | consistency / roblox-readiness / clean-room |
| Candidate baseline ID | D4-CAND-* / P0-CAND-* |
| Candidate manifest | {path} |
| Candidate manifest SHA-256 | {sha256} |
| Candidate fileSetSha256 | {sha256} |
| Audit capsule path | {path} |
| Audit capsule SHA-256 | {sha256} |
| Capsule assembly attestation ID / path / SHA-256 | {D4-CAPSULE-ASSEMBLY-* / path / sha256} |
| Capsule assembly provenance path / SHA-256 | {path / sha256} |
| Installed-policy manifest path / SHA-256 / compiledPolicySha256 | {path / sha256 / sha256} |
| Runtime allowlist path / SHA-256 / digestSha256 | {path / sha256 / sha256} |
| P0 lifecycle transition (post-P0 only) | {LTA-P0 ID/path/sha256 + lifecycle write-log path/sha256 + PV-P0-TRANSITION ID/path/sha256, or `not-applicable`} |
| Audit request ID | {D4-REQUEST-*} |
| Audit request artifact path | {path} |
| Audit request artifact SHA-256 | {sha256} |
| Canonical requestCore SHA-256 | {sha256} |
| Exact orchestrator-submitted payload path / SHA-256 | {path / sha256} |
| Lane run ID | {D4-RUN-*} |
| Storage path | docs/audits/{{PREFIX}}_d4_{TRACK}_{CANDIDATE_ID}_r{ROUND}.md |
| Position | Unedited worker response; post-run attestation is a separate JSON artifact and is not referenced here |
| Verdict | pass / fail |

`Severity`、`Confidence`、`State tag`、`Status` は別軸。混ぜない。D4監査者はfindings-only/read-onlyで、正本文書を変更しない。すべてのField/Coverage/Execution factsを非空で埋め、該当しない値は明示的に`none`または`not-applicable`とする。Commands tableは実行したargvをminified JSON arrayで最低1行記録する。

## Summary

- Critical: {n}
- Major: {n}
- Minor: {n}
- Observation: {n}
- Verdict rule: Critical `0` and Major `0` only → `pass`
- Route: initial `pass` → `D4合格 / P0着手資格あり（人間P0開始承認待ち）` → B0昇格; post-P0 `pass` → `post-P0 D4合格 / B1昇格可 / D5提示可能`; initial `fail` → `D4不合格 / D0〜D3是正へ`; post-P0 `fail` → `post-P0 D4不合格 / P0是正へ`

## Findings

### D4-{TRACK}-{NNN}: {title}

- Finding ID: D4-{TRACK}-{NNN}
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

- Canonical allowlist received: {path / sha256}
- Sanitized evidence manifest received: {path / sha256}
- Target-revision preflight checked: {policy-fixed SOURCE-STATE/REVISION/TREE argv + raw output hashes + full tree entries digest; assembly attestation/provenance exact, or `missing`}
- GDD Gate 1 chain checked: {gate record ID/path/hash → target GDD + scope-approved intake/required_specs path/hash → presentation/challenge/transcript/statement/capture/provenance actual hashes and message chronology; all exact/immutable, or `missing`}
- Initial-D4 inventory source: candidate `PROGRESS.md` / `## Proposed P0 closure inventory` / inventory ID / file SHA-256: {values or `not-applicable`}
- post-P0 inventory source: B0 historical `PROGRESS.md` / section / inventory ID / file SHA-256: {values or `not-applicable`}
- post-P0 candidate state: P0-CAND `PROGRESS.md` file SHA-256 / proposed inventory data-row count: {sha256 / `0`, or `not-applicable`}
- Remaining proposal/open/assumption IDs found: {complete qualified IDs or `none`}
- Inventory coverage verdict: complete / incomplete / post-P0-not-applicable
- post-P0 closure evidence checked: {all B0 historical inventory IDs → P0-CAND `PROGRESS.md` Completed evidence/affected-doc hashes; candidate inventory data rows must be 0, or `not-applicable`}
- post-P0 lifecycle proof checked: {capsule/request exact-equal one `p0LifecycleTransition`; parsed closed write log count/set/sequence digests; B0 monitor start state/full target scope; P0-start and P0-contract presentation/response/PV-before-write chronology; zero-row inventory count; normalized digest; freeze/result candidate; no unlogged writes; fresh operator-pinned authority authentication, or `not-applicable`}
- Files inspected: {complete capsule-relative path / sha256 list}
- Required files not received: {complete path list or `none`}

## Commands run and outputs

| Argv (exact minified JSON array; shell=false) | CWD | Exit code | Output path | Output SHA-256 |
|---|---|---:|---|---|
| `["{absolute executable}","{arg1}"]` | `{sanitized-root cwd}` | `{integer}` | `{path}` | `{sha256}` |

## Execution facts in this worker response

- lane run / execution / session IDs: {three nonempty runtime IDs}
- worker / class: {worker / A}
- requested and resolved model/version: {requested / resolved}
- tool version: {version}
- context mode: clean
- filesystem access: read-only-sanitized-root-plus-pinned-runtime-and-verifier
- provider policy ID / SHA-256: {trusted authority values}
- capsule path / SHA-256: {path / sha256}
- installed-policy manifest path / SHA-256 / compiledPolicySha256: {path / sha256 / sha256}
- runtime allowlist path / SHA-256 / digestSha256: {path / sha256 / sha256}
- inspected input paths / SHA-256: {complete capsulePath / sha256 list}
- request artifact path / SHA-256 / requestCore SHA-256: {path / sha256 / sha256}
- exact orchestrator-submitted payload path / SHA-256: {path / sha256}
- raw response output path: {this file path; do not include a self-hash}
- read-only sandbox / network: {values}
- finish reason / exit code: {values}
- started at / completed at: {timezone timestamps}

指示役はworker完了後に別の`d4_auditor_attestation.json`を作り、policy/runtime allowlist、requestCore、exact submitted payload、request artifactとこのraw responseの実hashを束縛する。さらにoperator外部configでpinしたprovider/runtime queryまたは署名検証からouter `provenance_verification`を作る。このresponseへattestation/verification path/hashを後書きしない。baseline/W0 `auditRecords`だけがraw response、capsule、request、attestation、outer verificationを同時に束縛する。installed skillをauditorへ直接公開しない。外部照会/署名検証不能ならD4 passへ昇格しない。
