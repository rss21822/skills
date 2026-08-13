# lint 設定の記入例

`templates/doc-lint.json` は空の雛形。ここは実プロジェクト（PREFIX=CAV）で実際に
使った設定を、どう決めたかの理由つきで示す。**そのままコピーせず**、自分の
プロジェクトの文書名・所有関係に置き換える。

## value_owner_docs — 数値の所有文書

```json
"value_owner_docs": [
  "docs/CAV_data_definition.md",
  "docs/specs/CAV_network_security_spec.md",
  "docs/specs/CAV_performance_budget_spec.md",
  "docs/CAV_feasibility_report.md",
  "docs/CAV_gdd.md",
  "docs/CAV_intake.json"
]
```

所有文書では `unreferenced-value` を出さない。所有していない文書に単位つき数値が
ID 参照なしで現れたときだけ、二重正本の芽として警告する。上流の入力（GDD・intake・
Feasibility）も、値の出所そのものなので所有側に入れる。

## decision_id_home_docs — 決定 ID を定義している文書

```json
"decision_id_home_docs": ["docs/CAV_gdd.md", "DECISIONS.md"]
```

定義行（表の先頭セルが ID そのものの行）だけ免除される。home 文書の中でも、外部の
名前空間を参照する行は検査対象のまま。

## bare_open_exempt_docs — 規約成立前の承認済み文書

```json
"bare_open_exempt_docs": ["docs/CAV_feasibility_report.md"]
```

タグ規約が固まる前に人間承認された文書は、遡って直すかどうかが人間判断。lint で
毎回鳴らしても仕方がないので外す。**新規文書には使わない。**

## contracts — 通知・イベントの受け口

```json
"contracts": [{
  "id": "rights-status-change-notification",
  "owner": "docs/specs/CAV_rights_provenance_ledger.md",
  "consumers": [
    "docs/specs/CAV_asset_content_pipeline_spec.md",
    "docs/specs/CAV_liveops_content_spec.md",
    "docs/specs/CAV_commerce_policy_spec.md",
    "docs/specs/CAV_localization_accessibility_spec.md"
  ],
  "marker": "previousRightsDecisionRef"
}]
```

`marker` は payload の**正式 field 名**にする。言い換え表現を許すと、consumer が
「それらしいこと」を書いただけで通ってしまう。

この設定が実際に効いた例: 上の4 consumer のうち localization だけが正式 field 名を
参照しておらず、体系監査を通過した後に lint が検出した。owner 側は consumer として
登録済みだったのに、受信側の文言だけが古い是正から取り残されていた。

## forward_refs — 順序を崩したときの登録

```json
"forward_refs": [{
  "from": "docs/specs/CAV_physics_control_spec.md",
  "to": "docs/CAV_data_definition.md",
  "reason_marker": "canonical 値が未登録",
  "note": "to が実在したら理由を実体条件へ書き換え、この行を削除する"
}]
```

参照先が実在するようになった時点で warn が出る。理由句を実体条件へ書き換えたら
エントリを消す。登録しない前方参照は禁止——検出できないものは必ず放置される。
