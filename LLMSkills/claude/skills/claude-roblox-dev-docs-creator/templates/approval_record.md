# Handoff {ID} — {CR-ID} 承認の記録（記録のみ）

> **これは差分雛形。** 基本の必須項目（`objective`／`dataIds`／`acceptance`／`commands`／`execution`／`rollback` と常設条項）は `claude-roblox-dev-docs-creator` の `templates/handoff.md` が正本。そちらを土台にして本書の P0 固有部分を重ねる。本書だけで発行すると必須項目が欠ける。

| 項目 | 値 |
|---|---|
| handoffId | `{ID}` |
| baseline | commit `{hash}`（今回のcommit許可あり）／snapshot `{manifest path}`・manifest sha256 `{hash}`・raw git status `{path}`（commit未許可） |
| 承認 | {人間本人の直接承認 `[DECISION]`／{委任決定 ID}に基づくAIの `[AI-APPROVED]`}・{実行者}・{日付} |

## 0. 反映する事実（すべて実測・記録済み）

1. {承認の事実。人間直接承認なら発言の要旨、AI承認なら委任決定ID・範囲・判断根拠}
2. **採択した選択の内訳**（CR の各論点について何を選んだか。**ここが唯一の記載箇所**）
3. {commit や計測など、同時に記録すべき実測値}

## 1. 指示

1. **`DECISIONS.md`**: 記録を1件追加する。人間本人の直接承認だけ `[DECISION]`、委任AIは `[AI-APPROVED]` として委任元の人間 `[DECISION]` を参照する。本文に**選択内訳を全件**記載し、「**選択内訳の正本は本記録である**」と書く。実行者・日付・対象を明記。同番fallbackは未指示なら作らない
2. **人間作業台帳**: 人間本人が実行した該当行だけを `Completed` へし、closure evidence欄も同期する。委任AIの `[AI-APPROVED]` では人間作業行を変更しない。承認内容は記録IDを参照し、複製しない
3. **CR ヘッダ**: P0内のCR lifecycle Statusを `Approved` へし、承認種別と記録IDを参照する。これはformal documentの `Status: Approved` やD5ではない。§本文は変更しない
4. **`PROGRESS.md`**: Current handoff、`[FACT]` 行、**Next authorized action の更新**
5. **`CHANGELOG.md`**: 行を時系列順で追加

## 2. 委任を新たに記録する場合（該当時のみ）

委任そのものを人間の `[DECISION]` として記録し、**対象範囲・期限・取消条件・対象外**を明記する。対象外は少なくとも: productionのUniverse／Place・ID・DataStore・Open Cloud・商品・Secrets・権限・binding・publish settingsへの接触、全環境のpublish、production activation、commit／push、Gate 1、D5、formal document昇格。

`[HUMAN]` は人間専権のまま維持し、「またはAI」を足さない。AI行使は `[AI-APPROVED]` 記録側から委任 `[DECISION]` を参照する。全文検索でAIの `[DECISION]`、AI完了可能な `[HUMAN]`、D5代替経路がないことを確認する。

## 3. inScope / outOfScope

inScope: `DECISIONS.md`／人間作業台帳（該当行のみ）／CR ヘッダ（ヘッダのみ）／`PROGRESS.md`／`CHANGELOG.md`
outOfScope: 他すべて。**特に正本の実改訂は次便**（承認と改訂は別の事象）

## 4. 制約

新規数値・hash・ID の創作禁止。裸 `[OPEN]` 禁止。記録ID完全修飾。**承認内容の正本は記録1箇所**——他からは参照のみ。formal documentのStatus／Last approvedは変更しない。`[AI-APPROVED]` を `[DECISION]`、D5、`[HUMAN]` 完了へ読み替えない。過去の記録を改変しない。実施していない検証を書かない。handoff workerによるcommit・push禁止。

## 5. 報告

変更前後の該当箇所、実測 sha256、`git status --short`、validator と lint の実出力（baseline 悪化不可）。
