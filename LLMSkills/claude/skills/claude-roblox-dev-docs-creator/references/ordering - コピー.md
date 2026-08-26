# 執筆順序と所有境界

## なぜ順序が最重要か

文書体系の手戻りは、内容の質より**依存の向きに逆らって書いたこと**から生まれる。まだ存在しない文書を前提に語った一文は、その文書ができた瞬間に嘘になり、書いた本人は次の文書へ移っているので誰も直しに戻らない。

実プロジェクトでの被害:

- rights ledger を最後に書いた → asset・localization・liveops・commerce が「rights は未作成」を前提に受け口なしで完成 → 4文書横断の是正を3巡（うち1件は監査で Critical 判定）
- data_definition を4番目に書いた → 先行した physics・network に「data_definition 未作成のため」が埋め込まれ、最終監査まで15箇所以上生存
- traceability を骨格→後追記の2段で書いた → 242行を2回触った

いずれも**順序を変えるだけで消える**。内容の品質とは無関係のコスト。

## 標準順序

```
E0      能力プローブ             実行面・worker確認。project内容なし。結果で運行計画が変わる
D0      intake                   指示役が事前記入。未回答は使用者確認、全回答に出所を記録
D1      gdd                      製品判断の所有者。**人間承認ゲート**
D1.5    feasibility_report       高リスク機能を Studio MCP で実測。trigger は D1 で洗い出す

Tier 0  判断・数値の所有者
        data_definition          gameplay/経済の可変数値（全数値ではない。所有は下表）
        rights_provenance_ledger 権利・史実・文化の判断

Tier 1  構造
        detailed_design          モジュール境界・状態所有・信頼境界

Tier 2  Tier0-1 の消費者
        physics_control          movement/camera/ownership
        network_security         Remote 契約・権威・rate/retry の所有
        persistence_migration    保存 schema・migration・冪等性
        ui_ux_input              画面・入力予算・UI 寸法

Tier 3  Tier2 の消費者
        multi_place_matchmaking  topology・部分到達・Party 整合
        commerce_policy          catalog・receipt・entitlement
        analytics_observability  event 辞書・計測方法・privacy
        performance_budget       性能上限・degradation
        asset_content_pipeline   asset 台帳・命名・import・moderation
        ugc_moderation           自由入力の filtering
        localization_accessibility  locale・翻訳 lifecycle
        liveops_content          Season・activation・kill switch

Tier 4  生成物
        docs_index / docs_manifest.json    ← gen_index.py で生成

D3      phase_plan
        → work_packages
        → test_spec
        → toolchain_spec
        → traceability CSV（design/wp/test 参照まで一度に記入）
        → CLAUDE.md / workflow
        → release_rollback_runbook
        → 記録類（PROGRESS / DECISIONS / CHANGELOG / HUMAN_ACTIONS / ASSET_TODO）
```

`trigger-matrix.md` が発動を決めた仕様書のうち、上に無いもの（external_services_secrets 等）は依存関係を見て挿入する。判断基準は「他文書の判断・数値を消費するか、他文書へ供給するか」。供給側が先。

### E0〜D1.5 の順序の理由

- **E0 能力プローブが最初**: 何が使えるかで運行計画が変わる。Studio MCP が無ければ D1.5 の実測が不可能になり、trigger 該当機能の扱いが「実測して判定する」から「`[OPEN blocking: yes]` として登録し下流を止める」へ変わる。**計画を書いてからプローブすると、計画の前提が崩れる**
- **GDD より上に文書を置かない**: GDD は製品判断の所有者であり、他文書から導出できない唯一の文書。人間承認と必要な D1.5 PASS の前に下流を書くと、方針が変わったとき全下流が是正対象になる
- **Feasibility trigger は GDD 時点で洗い出す**: 後から気づくと、既に書いた Tier 2-3 が検証されていない前提の上に立つ。**自律モードでは実測が運行に組み込まれているので、「trigger を踏んだのに測らないまま Tier 0 へ進む」は起こしてはならない**。実測できない事情がある項目だけを `[OPEN blocking: yes]` として登録する
- **決定 ID の参照規約は GDD 冒頭で確定する**: ID 本体の形式は architect が正本なので変えない。決めるのは「独自採番を持つ文書の列挙」と「参照の完全修飾」。後から変えると参照している全文書の是正になる。詳細は [gdd-and-intake.md](gdd-and-intake.md) §2

### D3 内の順序の理由

- **phase_plan が先**: gate 構造（どの承認で何が始まるか）が決まらないと、WP の `Authorized by` が書けない。ここを飛ばすと循環 gate が生まれる
- **work_packages → test_spec**: テストは WP の Automatic/Studio/Performance 欄を解決する存在。逆順だとテストが宙に浮く
- **traceability は最後**: 要件→設計→WP→テストの4段が揃ってから一度に書く。骨格を先に作っても、結局 wp/test 参照で全行を触り直すことになる
- **記録類は最後**: PROGRESS も CHANGELOG も、記録すべき実績が確定してから書く。**ただし `HUMAN_ACTIONS.md` と `DECISIONS.md` は例外で、初版を D1 で作る**。GDD 時点で台帳対象の作業と承認記録が既に発生しているため。D3 でやるのは最終整備（全 Spec 由来の gate を全文走査で収集し、exec 分類を揃え、`ai-*` の未実行を潰す）

## 所有境界（配達先 ≠ 所有先）

handoff で最も間違えやすい箇所。「その値を使う文書」と「その値を決める文書」は違う。

| 対象 | 唯一の所有先 |
|---|---|
| gameplay・経済の可変数値 | data_definition |
| Remote の authority / validation / rate / retry / 帯域 semantics | network_security |
| Remote の ID / payload field / type / enum | remote contracts instance |
| 性能上限・degradation 閾値 | performance_budget |
| event の purpose / sampling / retention / privacy | analytics_observability |
| Analytics event ID / field / type | analytics events instance |
| 保存 lifecycle / migration / recovery / 冪等性 semantics | persistence_migration |
| 保存 field / type / version / default | save schema instance |
| receipt / policy / grant-revoke semantics | commerce_policy |
| commerce key / product mapping / entitlement | commerce ledger instance |
| asset production / rights decisions | asset_content_pipeline / rights_provenance_ledger |
| asset ID / provenance / status | asset ledger instance |
| 権利・史実・文化の判断 | rights_provenance_ledger |
| UI 寸法 / breakpoint / 入力割当 | ui_ux_input |
| 実行環境・pin・bootstrap | toolchain_spec |
| テスト手順・fixture・evidence 形式 | test_spec |
| 人間承認の記録と、承認前の品質判定 | DECISIONS.md |
| 実測の生データと判定 | evidence（`docs/evidence/` 配下） |

機械可読 contract instance の field/type/ID/enum は instance が唯一正本、意味・failure policy は対応 Markdown Spec が唯一正本。path と対応表は `document-system.md` §Machine-readable contracts。schema は検証規則であり project 値の正本ではない。

**「所有する」は「未承認値を創作してよい」ではない。** 所有とは確定済み値を保持する権限であって、根拠なく決める権限ではない。確定していない値は key と確定プロセス（実測 → 判定 → 当該 Spec 改訂）だけを書く。

**実測値の正本は evidence 側にある。** Spec が実測由来の値を持つときは、evidence パスを添える。値だけを転記して出所を書かないと、再計測したときにどちらが新しいか分からなくなる。

下流文書がやってよいのは3つだけ:

1. ID で参照する
2. 読解のために値を転記し、「転記。正本は参照先」と明記する
3. 自分が所有する構造（適用 mapping・検査規則）を書く

## 順序を崩す場合の手続き

現実には、上流の未確定を待てず下流を先に書くことがある。その場合は**前方参照を登録する**。

`.claude/doc-lint.json` の `forward_refs` へ:

```json
{
  "forward_refs": [
    {
      "from": "docs/specs/CAV_physics_control_spec.md",
      "to": "docs/CAV_data_definition.md",
      "reason_marker": "data_definition の canonical 値が未登録",
      "note": "to が実在したら reason を実体条件へ書き換える"
    }
  ]
}
```

lint は `to` が実在するようになった時点で警告を出す。登録しない前方参照は禁止する——検出できないものは必ず放置されるため。

**理由句の書き方**が本質的に重要:

- 悪い: 「`X.md` が未作成のため保留」→ X ができた瞬間に嘘
- 良い: 「X の canonical 値が未登録のため保留（closure: X へ値が登録されたとき）」→ 条件が実体を指しており、勝手に嘘にならない

**実測待ちを理由にする場合も同じ。** 「FR-2 が未実施のため」ではなく「FR-2.4 の実測値が未登録のため（closure: evidence へ結果が記録されたとき）」。自律モードでは実測が近い将来に必ず起きるので、陳腐化までの時間が短い。

## 横断契約の同時執筆

文書 A が通知・イベント・gate を定義するなら、**同じ handoff の中で consumer 側の受信契約まで書く**。後から足すと4文書横断の是正になる。

`.claude/doc-lint.json` の `contracts` へ登録すると、consumer に受信 marker があるか lint が確認する:

```json
{
  "contracts": [
    {
      "id": "rights-status-change-notification",
      "owner": "docs/specs/CAV_rights_provenance_ledger.md",
      "consumers": [
        "docs/specs/CAV_asset_content_pipeline_spec.md",
        "docs/specs/CAV_liveops_content_spec.md",
        "docs/specs/CAV_commerce_policy_spec.md"
      ],
      "marker": "previousRightsDecisionRef"
    }
  ]
}
```

marker は payload の**正式 field 名**にする。言い換え表現（「affected refs」等）を許すと、文字列が一致せず結局どの field を見ればよいか実装者が決められない。
