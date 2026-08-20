# {{PROJECT}} — Work Package Specification

| Field | Value |
|---|---|
| Document ID | {{PREFIX}}-WP-001 |
| Version | 0.1.0 |
| Status | Draft |
| Canonical domain | file-level AI implementation contracts |
| Owner | [HUMAN] Project owner |
| Inputs | {{INPUTS}} |
| Downstream | {{DOWNSTREAM}} |
| Last approved | — |

## Change history

| Version | Date | Change | Approver |
|---|---|---|---|
| 0.1.0 | {{DATE}} | Initial draft | — |

## Work Package template

### WP-{DOMAIN}-{NNN}: {Title}

- Status: Proposed / Approved / In progress / Verified / Superseded
- Objective:
- Requirement IDs:
- Prerequisites:
- Read:
- Create:
- Modify:
- Do not touch:
- Public interfaces:
- Implementation steps:
- Automatic tests:
- Studio verification:
- Performance verification:
- Evidence output:
- Rollback:
- Documentation updates:
- Human actions:
- Done definition:
- Authorized by:
- Authorization baseline:
- Authorization evidence:

`Approved` / `Authorized by` / `Authorization baseline` / `Authorization evidence` は文書とW0引渡し対象を示すmetadataであり、runtime execution・外部送信・side effectの権限ではない。receiverはexternally monitored PREPARE→VALIDATE後もlockを維持し、current B2/package/WP、machine-derived frozen/disjoint write paths、receiver Skill tree/expected closure、worker/transfer/operationをclosed human run authorizationへ固定する。expected-only signed ADMITのsemantic PASS後だけadmission tokenを消費し、workerをsuspended/pre-entry起動してactual closure一致をsigned receiptへ束縛する。bootstrap receipt検証PASS後も、未使用の短期worker-ready capabilityを最初のeffect直前に原子的消費してからだけ進む。

## Package index

| WP | Phase | Requirements | Status | Blocking dependency | Tests |
|---|---|---|---|---|---|
