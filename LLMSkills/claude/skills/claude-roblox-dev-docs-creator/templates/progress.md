# {{PROJECT}} — Progress

- Current phase: D0
- Current Work Package: None
- Status: Awaiting intake
- Last known good commit: None
- Next authorized action: Complete D0

## Proposed P0 closure inventory

- Inventory ID: `{P0-CLOSURE-INVENTORY-ID}`
- Canonical owner: this `PROGRESS.md` section only。handoff、audit、DECISIONSへ行を複製せず、path/section/file SHA-256/inventory IDで参照する
- Initial D4 rule: D4 candidate固定前に、P0で閉じる全proposal、blocking open、unverified assumptionを完全列挙する。inventory外の未決、曖昧scope、owner/pass rule/affected-doc不足はD4不合格

| Source item ID | Source path / section | Type (proposal/open/assumption) | Exact bounded P0 closure question / scope | Owner | Required closure evidence / pass rule | Affected canonical docs |
|---|---|---|---|---|---|---|
| `{qualified ID}` | `{path} §{section}` | `{proposal|open|assumption}` | `{one bounded question or verification scope}` | `{owner}` | `{actual evidence type and objective pass rule}` | `{all canonical paths}` |

P0 startはB0 historical bytes内の本sectionを承認scopeとして固定する。P0で代替案を作成・評価し、決定と根拠は`DECISIONS.md`へ記録する。各項目がpassしたら、本表からその行を除き、同じSource item ID・actual closure evidence・affected-doc hashesを`Completed`へ追記する。`P0-CAND-*` はその反映後の`PROGRESS.md`を含む。post-P0 D4開始時は本表のdata rowが0で、B0 historical inventory全IDが`Completed`およびaffected canonical docsで閉じていなければならない。新規項目・scope拡張はP0へ足さず、owning D0-D3→新initial D4→新B0→新P0 start承認へ戻す。

## Completed

### P0 closure records

| Source item ID | Inventory ID / B0 historical PROGRESS.md SHA-256 | Decision ID | Actual closure evidence / pass result | Affected canonical docs / post-change hashes | Completed at |
|---|---|---|---|---|---|

行はclosure成功時だけ追記する。B0 inventoryのscopeをここへ再記述せず、ID/hashで参照する。`Completed at` はtimezone付きtimestamp必須。

## In progress

### AI actions

- `[AI-ACTION]` {action} — authority/evidence: {reference}

## Blocked

## Human action required

## Test status

## Document status

## Next authorized action
