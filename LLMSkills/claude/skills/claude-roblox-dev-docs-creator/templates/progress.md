# {{PROJECT}} — Progress

- Current phase: D0
- Current Work Package: None
- Status: Awaiting intake
- Last known good baseline: None
- Next authorized action: Complete D0

## Proposed P0 closure inventory

- Inventory ID: `{P0-CLOSURE-INVENTORY-ID}`
- Canonical owner: this `PROGRESS.md` section only。handoff、audit、DECISIONSへ行を複製せず、path/section/file SHA-256/inventory IDで参照する
- Initial D4 rule: D4 candidate固定前に、P0で閉じる全proposal、blocking open、unverified assumptionを完全列挙する。inventory外の未決、曖昧scope、owner/pass rule/affected-doc不足はD4不合格。Gate 1承認済intake/GDD/required_specsを変更する項目は入れず、D0/D1→new required_specs→unique新Gate1→D1.5/D2/D3→new initial D4へ戻す

| Source item ID | Source path / section | Type (proposal/open/assumption) | Exact bounded P0 closure question / scope | Owner | Required closure evidence / pass rule | Affected canonical docs |
|---|---|---|---|---|---|---|
| `{qualified ID}` | `{path} §{section}` | `{proposal|open|assumption}` | `{one bounded question or verification scope}` | `{owner}` | `{actual evidence type and objective pass rule}` | `{all canonical paths}` |

P0 startはB0 historical bytes内の本sectionを、唯一のD2/D3 content mutation scopeとして固定する。Gate 1が承認したintake/GDD/required_specs path/hash/revisionはP0でimmutable。変更時D0/D1→new required_specs/Gate1→D1.5/D2/D3→new initial D4/B0へ戻る。別枠で既存contract検証、必要CR/approval/closure records、P0管理WP Verified、P0-CAND freeze、p0-contract recordというfixed procedureだけを許可する。本表0行ならcontent mutation 0のままprocedure実施可。各項目pass時、本表から行を除き、同じSource item ID・exact evidence path/hash/PASS・affected-doc hashesを`Completed`へ追記する。post-P0 D4開始時はdata row 0、B0全ID closure必須。新scopeはP0へ足さずowning D0-D3へ戻す。

## Completed

### P0 closure records

| Source item ID | Inventory ID / B0 historical PROGRESS.md SHA-256 | Decision ID | Actual closure evidence path / SHA-256 / result | Affected canonical docs / post-change hashes | Completed at |
|---|---|---|---|---|---|

行はclosure成功時だけ追記する。evidence欄の文法はexact ``{project-relative path} / {64 lowercase hex SHA-256} / PASS``。`PASS`以外、active tag、free prose、missing/未再hash pathは不可。validatorがproject rootから実bytesを再hashする。B0 inventory scopeは再記述せずID/hash参照。`Completed at` はtimezone付きtimestamp必須。

## In progress

### AI actions

- `[AI-ACTION]` {action} — authority/evidence: {reference}

## Blocked

## Human action required

## Test status

## Document status

## Next authorized action
