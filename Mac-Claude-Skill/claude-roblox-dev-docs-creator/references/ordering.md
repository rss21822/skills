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
Tier 0  判断・数値の所有者
        data_definition          gameplay/経済の全数値
        rights_provenance_ledger 権利・史実・文化の判断（判断自体は人間専権）

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

`roblox-development-architect` の trigger-matrix が発動を決めた仕様書のうち、上に無いもの（external_services_secrets 等）は依存関係を見て挿入する。判断基準は「他文書の判断・数値を消費するか、他文書へ供給するか」。供給側が先。

### D3 内の順序の理由

- **phase_plan が先**: gate 構造（どの承認で何が始まるか）が決まらないと、WP の `Authorized by` が書けない。ここを飛ばすと循環 gate が生まれる
- **work_packages → test_spec**: テストは WP の Automatic/Studio/Performance 欄を解決する存在。逆順だとテストが宙に浮く
- **traceability は最後**: 要件→設計→WP→テストの4段が揃ってから一度に書く。骨格を先に作っても、結局 wp/test 参照で全行を触り直すことになる
- **記録類は最後**: PROGRESS も CHANGELOG も、記録すべき実績が確定してから書く

## 所有境界（配達先 ≠ 所有先）

handoff で最も間違えやすい箇所。「その値を使う文書」と「その値を決める文書」は違う。

| 対象 | 唯一の所有先 |
|---|---|
| gameplay・経済の可変数値 | data_definition |
| Remote の rate / payload / retry / 帯域 | network_security |
| 性能上限・degradation 閾値 | performance_budget |
| event 名 / field / sampling / retention / privacy | analytics_observability |
| 保存 schema・migration・冪等性契約 | persistence_migration |
| catalog / receipt / entitlement | commerce_policy |
| 権利・史実・文化の判断 | rights_provenance_ledger |
| UI 寸法 / breakpoint / 入力割当 | ui_ux_input |
| 実行環境・pin・bootstrap | toolchain_spec |
| テスト手順・fixture・evidence 形式 | test_spec |
| 人間承認記録 | DECISIONS.md |

**「所有する」は「未承認値を創作してよい」ではない。** 所有とは承認済み値を保持する権限であって、決める権限ではない。未承認の値は key と確定プロセス（実測 → Owner 承認 → 当該 Spec 改訂）だけを書く。

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
- 良い: 「X の canonical 値が未登録のため保留（closure: X へ値が登録され Owner 承認されたとき）」→ 条件が実体を指しており、勝手に嘘にならない

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
