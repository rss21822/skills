# P0 Start {P0_START_APPROVAL_ID} — authorize contract work only

> `D4合格 / P0着手資格あり（人間P0開始承認待ち）` とB0昇格の後、人間本人の直接承認で初めてP0作業だけを許可する。委任承認不可。P0契約承認、D5承認、製品実装開始の代替ではない。

## Inputs

- P0 start approval ID: `{P0_START_APPROVAL_ID}`
- approval kind: `human-direct`
- approver and scope: `{IDENTITY}` / `{EXACT_SCOPE}`
- approved at: `{ISO-8601_WITH_TIMEZONE}`
- source evidence: `{PATH}` / sha256 `{SHA256}`
- B0: `{B0_ID}` / manifest `{PATH}` / sha256 `{SHA256}` / fileSetSha256 `{SHA256}`
- promoted from: `{D4_CANDIDATE_ID}` / manifest `{PATH}` / sha256 `{SHA256}`
- three D4 records: `{consistency}`, `{roblox-readiness}`, `{clean-room}`
- B0-fixed P0 closure inventory: `PROGRESS.md` / `## Proposed P0 closure inventory` / B0 historical file sha256 `{SHA256}` / inventory ID `{ID}`
- machine approval record output: `{PATH}`

## Preconditions

1. All three raw D4 records point to the same `D4-CAND-*`; each Critical `0`, Major `0`, verdict `pass`, and attests that every remaining proposal/open/assumption is covered by the one `PROGRESS.md` inventory section.
2. B0 `promotedFrom` equals that candidate and both `fileSetSha256` values match。B0はimmutableで `approvalId` はnull。P0 start recordがB0 outer hashを後から束縛する。
3. Recompute the B0 historical `PROGRESS.md` bytes from its commit/snapshot; its file SHA-256, section heading, inventory ID, rows, and B0 manifest entry all match the Inputs. Live `PROGRESS.md`やhandoff内の複製値を承認対象にしない。
4. Human approval evidence names that exact B0 historical inventory ID/file hash and every bounded row scope; no extra item or authority is implied.
5. `{P0_START_APPROVAL_ID}` is unused and differs from planned P0 contract/D5 IDs.

## Transaction

1. Create a `gate_approval_record.schema.json` record with type `p0-start`, bound to B0 ID/path/hash/`fileSetSha256`/revision; its `scope` must name the exact B0 historical `PROGRESS.md` inventory ID/file hash and bounded rows.
2. Append a P0-start stage record to `DECISIONS.md`; append current authorization and next action to `PROGRESS.md`; append one `CHANGELOG.md` entry.
3. Do not edit the inventory rows during this authorization transaction. P0 work subsequently creates alternatives and closes only approved rows; it reflects each closure in live `PROGRESS.md`, and the final `P0-CAND-*` includes those bytes.
4. Do not alter formal document Status/Last approved, product contracts, or any product implementation WP.
5. Rehash the machine record and append-only files. On failure restore their pre-transaction bytes and report `ROLLED BACK`.

## Exit

- Allowed next action: first explicit P0 contract work unit from the approved closure inventory only
- Not allowed: D5 sync, W0/product implementation, commit/push, production/external-state changes without separate authority
