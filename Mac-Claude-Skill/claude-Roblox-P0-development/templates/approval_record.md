# Handoff {ID} — {CR-ID} 承認の記録（記録のみ）

> **これは差分雛形。** 基本の必須項目（`objective`／`dataIds`／`acceptance`／`commands`／`execution`／`rollback` と常設条項）は `claude-roblox-dev-docs-creator` の `templates/handoff.md` が正本。そちらを土台にして本書の P0 固有部分を重ねる。本書だけで発行すると必須項目が欠ける。

| 項目 | 値 |
|---|---|
| handoffId | `{ID}` |
| baseline | commit `{hash}`（作業ツリー clean） |
| 承認 | {誰が・いつ。委任なら「{委任決定 ID} に基づき委任された AI が {日付} に承認した」} |

## 0. 反映する事実（すべて実測・記録済み）

1. {承認の事実。チャット承認なら発言の要旨、委任承認なら判断根拠}
2. **採択した選択の内訳**（CR の各論点について何を選んだか。**ここが唯一の記載箇所**）
3. {commit や計測など、同時に記録すべき実測値}

## 1. 指示

1. **`DECISIONS.md`**: 決定を1件追加する。既存採番と衝突しない次番。本文に**選択内訳を全件**記載し、「**選択内訳の正本は本決定である**」と書く。承認者・承認日・対象を明記。同番 fallback は未指示なら作らない
2. **人間作業台帳**: 該当行を `Completed` へ。**closure evidence 欄も現況へ同期**する（成立分と未成立分を分けて書く）。承認内容は決定 ID を参照し、**複製しない**。他の行は変更しない
3. **CR ヘッダ**: Status を `Approved` へ（承認日・決定 ID 参照）。**§本文は変更しない**（承認内容の複製先を作らない）
4. **`PROGRESS.md`**: Current handoff、`[FACT]` 行、**Next authorized action の更新**
5. **`CHANGELOG.md`**: 行を時系列順で追加

## 2. 委任を新たに記録する場合（該当時のみ）

委任そのものを決定として記録し、**対象範囲と対象外**を明記する。対象外は少なくとも: production の Universe／Place・ID・DataStore・Open Cloud・商品・Secrets・権限・binding・publish settings への接触、全環境の publish、production activation。

**さらに、その委任が適用される工程の正本を全文検索し、承認者を `[HUMAN]` に限定している記述へ委任経路を併記する。** これを飛ばすと権限主体が二通りになり、authorized path が止まる。既存記述は削除せず、委任の内容は複製せず参照で表す。

## 3. inScope / outOfScope

inScope: `DECISIONS.md`／人間作業台帳（該当行のみ）／CR ヘッダ（ヘッダのみ）／`PROGRESS.md`／`CHANGELOG.md`
outOfScope: 他すべて。**特に正本の実改訂は次便**（承認と改訂は別の事象）

## 4. 制約

新規数値・hash・ID の創作禁止。裸 `[OPEN]` 禁止。決定 ID 完全修飾。**承認内容の正本は決定1箇所**——他からは参照のみ。過去の記録を改変しない（時制限定で扱う）。実施していない検証を書かない。commit・push 禁止。

## 5. 報告

変更前後の該当箇所、実測 sha256、`git status --short`、validator と lint の実出力（baseline 悪化不可）。
