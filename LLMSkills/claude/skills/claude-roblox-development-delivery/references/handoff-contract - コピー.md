# Handoff契約

所有者が指定したworkerは、必須項目が欠けたhandoffを受理しない。これは推測実装を防ぐ契約である。worker固有の起動契約は上位contractと `claude-roblox-mvp-buildout/references/delegation-contract.md` を継承し、この文書で弱めない。

## 必須項目

| 項目 | 内容 | 欠けるとどうなるか |
|---|---|---|
| `handoffId` | 一意なID（`P0-001` 等） | 進捗記録と紐付かない |
| `phase` / `baseline` | 現Phaseと開始commit、またはimmutable snapshot ID | どの状態からの差分か不明 |
| `objective` | 完了時に**観測できる**状態 | 「いい感じに作る」になり検証不能 |
| `inScope` / `outOfScope` | 変更してよい/絶対に変更しないファイル | スコープ逸脱を検出できない |
| `requirements` | 対応する要件ID | トレースが切れる |
| `dataIds` | 使用を許可するデータID。使わないなら `[]` | 値の創作が起きる |
| `acceptance` | 完了判定に使うテスト/レビューID | 主観判定になる |
| `commands` | 実行してよいコマンド | 想定外の副作用 |
| `execution` | owner指定worker / model / reasoningEffort / sandbox / approvalPolicy / network / exact tool pin / helper | pin・強制機構違反が検出できない |
| `authority` | 送信先、prompt/path/secret範囲、認証channel/account、job承認ID、commit方針 | 無承認送信・無断commitが起きる |
| `decisions` | 承認済み決定と未決事項 | 未承認の判断が紛れ込む |
| `evidence` | 報告に含める証拠 | 検証不能な自己申告 |
| `rollback` | 失敗時に戻す単位 | 復旧できない |
| `completionSync` | code / tests / PROGRESS / CHANGELOG / Traceability / affected specs / LKG | コードだけ完了してD6同期が切れる |

`approvalPolicy` はworkerに対応する実値で書く。ただしhandoffへの記載は強制機構ではない。Codex T1なら上位契約のexact-pinned helperだけで強制し、helperを迂回したCLI直接起動へ弱めない。別workerでは存在しない保証を主張しない。

## objectiveの書き方

観測可能な完了状態を書く。

良い例: 「`lune run scripts/ci.luau` がexit 0で、T-0とT-15がACTIVEかつPASS、Evidence 4 schemaが検証を通る」

悪い例: 「CIを整備する」

## dataIdsの使い方

数値・ID・列挙を扱う実装では、使ってよいIDを明示的に列挙する。列挙にないIDが必要になったらworkerは止まる。追加のIDを許可するhandoffを再発行する。

値そのものを handoff に書き写すのは避ける。「registry から実行時に読む」形にすれば、値の二重管理が起きない。

## BLOCKEDへの対処

workerが `BLOCKED` を返したら、それは**情報・権限・能力のいずれかが足りないという報告**であり、失敗ではない。実運用のパターン:

| workerの報告 | 対処 |
|---|---|
| 必須項目が欠けている | 欠けた項目を補って再発行 |
| 正本の記述が曖昧で複数解釈できる | どちらを採るかを決めて明示（決定はユーザーへ確認が必要な場合がある） |
| 権限外のIDが必要 | `dataIds` へ追加して再発行 |
| 変更禁止ファイルを変更しないと完了条件を満たせない | acceptanceの定義が間違っている。修正して再発行 |
| 実測していない値が必要 | 実測してFACTとして渡す。取得できないなら `[OPEN]` として次段階へ送る |

**やってはいけないこと**: BLOCKEDを回避するために検査を緩める、値を推測で埋める、outOfScopeをこっそり広げる。

## FACT節

実測値をhandoffへ渡すときは、出所を明記した節を作る。

```markdown
## 実測FACT（<日付>、<誰が><どうやって>測定）

- <値の名前>: `<実測値>`（測定方法）
- ...

これ以外の値を書かない。
```

workerはこの節にない値を書かない。測定漏れがあれば止まる。

## スコープ判定

`inScope` / `outOfScope` は「workerが変更してよいか」で判定する。ユーザーが並行して編集したファイルは外部イベントであり、workerの違反ではない。handoffに次を書く。

> scope検証はworkerが変更したかで判定する。ユーザーの並行編集による差分は外部イベントとして分離・報告し、勝手にstage/commitしない。安全に分離不能ならBLOCKEDとする。

## 契約競合

実装中に正本、test、現行挙動の競合を発見した場合、workerはコードで解釈を確定せず `BLOCKED_CONTRACT_CONFLICT` を返す。依頼側はCRを作り、影響仕様書・test・WP・Traceabilityを同期し、D4/P0/D5の影響gateを再承認してから新handoffを発行する。
