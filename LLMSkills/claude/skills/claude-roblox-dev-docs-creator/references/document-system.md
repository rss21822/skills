# Document System and Canonical Boundaries

## Core principle

A fact may be summarized in multiple documents, but only one document is authoritative. Every duplicate mention must link back to the canonical source rather than restating mutable details.

## Always-generated documents

| Domain | Canonical document | Owns |
|---|---|---|
| Human document navigation | `{PREFIX}_docs_index.md` | Manifest 登録済み canonical / operating file の link map と人間向け再掲。Markdown version/status は header mirror、non-Markdown metadata は manifest mirror |
| Machine document inventory | `{PREFIX}_docs_manifest.json` | D0〜D5 の canonical / operating Markdown と machine-readable contract instance の file set・canonical-domain mapping。Markdown version/status は generated header mirrors |
| Trigger projection | `{PREFIX}_required_specs.json` | approved intake と `trigger-matrix.md` から `detect_triggers.py` が決定論的に生成する必須Spec一覧。手編集しない |
| Product intent | `{PREFIX}_gdd.md` | What, why, target, scope, loops, MVP, Non-Goals, decisions |
| System structure | `{PREFIX}_detailed_design.md` | Modules, interfaces, runtime logic, state machines, dependency direction |
| Balance values | `{PREFIX}_data_definition.md` | Tunable numbers, formulae, tables, validation examples |
| UI and control | `{PREFIX}_ui_ux_input_spec.md` | Screens, states, flows, input budgets, device behavior, accessibility |
| Repository and tools | `{PREFIX}_toolchain_spec.md` | Repo tree, source mapping, versions, build/test/serve commands, environments |
| Execution order | `{PREFIX}_phase_plan.md` | Phases, gates, dependencies, stop conditions |
| AI implementation units | `{PREFIX}_work_packages.md` | File-level scope, do-not-touch, tests, rollback, Done definition |
| Verification | `{PREFIX}_test_spec.md` | Test cases, fixtures, runner, evidence, pass/fail rules |
| Human+AI operation | `{PREFIX}_workflow.md` | Roles, approvals, escalation, document maintenance |
| Release safety | `{PREFIX}_release_rollback_runbook.md` | dev/staging/prod, publish, canary, stop, rollback, recovery |
| Implementation rules | root `CLAUDE.md` | Coding constraints, commands, canonical references, prohibited actions |

## Machine-readable contracts

D2 の機械可読成果物は、**JSON Schema（型を検査する規則）**と**instance（プロジェクトの実値）**を分ける。Schema ファイルだけ、または空 instance は契約完成ではない。

| Domain | Canonical instance | Markdown owner |
|---|---|---|
| Remote field/type/ID/enum | `docs/schemas/{PREFIX}_remote_contracts.json` | Network & Security Spec: semantics, authority, validation/failure policy |
| Save field/type/version/default | `docs/schemas/{PREFIX}_save_schema.json` | Persistence & Migration Spec: lifecycle, migration, recovery |
| Analytics event/field/type | `docs/schemas/{PREFIX}_analytics_events.json` | Analytics & Observability Spec: purpose, sampling, retention, privacy |
| Asset ID/provenance/status | `docs/schemas/{PREFIX}_asset_ledger.json` | Asset/Content and Rights Specs: production rules, rights decisions |
| Commerce key/product mapping/entitlement | `docs/schemas/{PREFIX}_commerce_ledger.json` | Commerce & Policy Spec: receipt, policy, grant/revoke semantics |

Instance が field-level 実装契約の唯一正本。Markdown は instance ID を参照し、同じ mutable payload・enum・mapping を再定義しない。意味・failure policy は Markdown の唯一正本で、instance の説明欄へ複製しない。schema version と formal document version は別軸なので、対応 revision を manifest に記録する。

formal Markdown document の version / Status の唯一正本は**各文書自身の header**。`{PREFIX}_docs_manifest.json` は generator が header から version / status を転記し、D0〜D5 の canonical / operating Markdown と machine-readable contract instance の file inventory・canonical-domain mapping を持つ。non-Markdown file の inventory metadata は manifest が正本。`{PREFIX}_docs_index.md` は manifest 全件の人間向け再掲で、Markdown version/status は header、non-Markdown metadata は manifest を参照する。index と manifest は手編集禁止。header / manifest / index が食い違えば生成失敗として再生成する。

handoff、raw D4 report、preflight log、approval source evidence、candidate/baseline manifest、snapshot bytes、post-sync manifest、W0 package は**製品正本inventoryの外**。それぞれ transition/audit/package の外側hashで束縛し、docs manifestへ混ぜない。baseline/post-sync の file bytes・sha256・file-set hash は lifecycle manifest / transition evidence が所有し、docs manifest に二重保持しない。

## Always-generated operating files

| File | Owns |
|---|---|
| `PROGRESS.md` | Current phase/WP, blockers, tests, last known good baseline, next authorized action、initial D4 で B0 に固定する Proposed P0 closure inventory。WP Status は再掲。closure inventory は未決の source と境界を所有し、P0 で作る選択内訳は所有しない |
| `ASSET_TODO.md` | Asset requirements, owner, rights, status, blocking WP |
| `HUMAN_ACTIONS.md` | Dashboard, Studio, credentials, moderation, IDs, production-only operations |
| `AI_ACTIONS.md` | Approved bounded machine actions, authority, input hashes, evidence, cleanup |
| `CHANGELOG.md` | Versioned project/document changes |
| `DECISIONS.md` | D-n/F-n decisions, evidence, approver, activation records |

Work Package Status の唯一正本は `{PREFIX}_work_packages.md` の**各 WP 詳細節**。同文書の index と `PROGRESS.md` は再掲であり、食い違えば詳細節を正として機械検査を失敗させる。index と詳細節を二重正本と呼ばない。

## Conditional specifications

Each triggered document becomes authoritative only for its domain. The detailed design references it.

- Network & Security
- Persistence & Migration
- Commerce & Policy
- Paid Random Items Annex
- Analytics & Observability
- Performance Budget
- Asset & Content Pipeline
- Multi-Place & Matchmaking
- Physics & Control
- UGC & Moderation
- Localization & Accessibility
- LiveOps Content
- External Services & Secrets
- Rights & Provenance

## Precedence when conflict exists

1. Human-approved decision record
2. Canonical document for the domain
3. Approved conditional specification
4. Work Package
5. Test specification
6. Implementation code comments

Code is not permitted to silently redefine product intent, balance, policy, or interface contracts. A discovered conflict stops the Work Package and opens a Change Request.

## Numeric ownership

- Gameplay and economy numbers: Data Definition
- Performance ceilings: Performance Budget Spec
- Retry/backoff/storage limits: Persistence or Network Spec
- UI dimensions and breakpoints: UI/UX/Input Spec
- Test expected values: copied by reference from the owning specification; do not recalculate independently
- Product IDs and entitlement mapping: machine-readable Commerce ledger instance

## Temporary canonical source

A downstream specification may temporarily resolve an upstream omission only when it declares:

- exact temporary rule
- reason
- upstream destination
- expiry condition
- owner

After upstream incorporation, replace the temporary section with an incorporation record. Never leave two live sources.
