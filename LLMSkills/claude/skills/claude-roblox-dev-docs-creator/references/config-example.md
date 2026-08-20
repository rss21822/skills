# lint 設定の記入例

`templates/doc-lint.json` は記入例つきの雛形。ここは実プロジェクト（PREFIX=CAV）で実際に
使った設定を、どう決めたかの理由つきで示す。**そのままコピーせず**、自分の
プロジェクトの文書名・所有関係に置き換える。

## manifest_project / manifest_prefix — manifest の必須メタデータ

```json
"manifest_project": "Cavalry Arena",
"manifest_prefix": "CAV"
```

`gen_index.py` は architect の `docs_manifest.schema.json` に合わせ、`project` と `prefix` を
必須にする。既存 manifest に値があれば保持する。新規生成時に既存値も設定値も無ければ、
schema 不適合の manifest を出さず停止する。`prefix` は英大文字・数字2〜6文字。

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

## decision_source_* — 決定に出所があるか

```json
"decision_source_pattern": "(?:src|source|出所)\\s*[:=]\\s*`?[UWMJ]\\b|evidence\\s*[:=]\\s*\\S",
"decision_source_exempt_docs": ["docs/CAV_feasibility_report.md"],
"decision_source_window": 2
```

`[DECISION]` に出所（`U` ユーザー発言 / `W` 調査 / `M` 実測 / `J` 指示役提案、または
evidence 参照）が付いているかを見る。**出所は判断根拠であり、人間承認記録の代替ではない。**
詳細は
[autonomous-execution.md](autonomous-execution.md) §3。

出所は同一行のほか、直後 `decision_source_window` 行（表の続き・箇条書きの子項目）に
置ける。**次の `[DECISION]` が現れた時点で打ち切る**ので、出所を書き忘れた決定が隣の
決定の出所を拾って通ることはない。窓を広げるほど誤って通る余地が増えるので、既定の 2 を
安易に大きくしない。

`decision_source_exempt_docs` は、規約成立前に書かれ、遡って出所を付けないと人間が決めた
文書を外す。**新規文書には使わない**。

## decision_approval_* — 決定に人間承認記録があるか

```json
"decision_approval_pattern": "(?:approver|approved[-_ ]?by|approval(?:_record|Ref)?|承認者|承認記録)\\s*[:=]\\s*\\S",
"decision_approval_exempt_docs": [],
"decision_approval_window": 3
```

`decision-approval-record` は、各 `[DECISION]` に承認者または承認記録への参照があるかを
検査する。`unsourced-decision` とは別規則であり、片方だけでは通らない。規約成立前の既存文書を
除外する場合も人間が範囲を決め、新規文書は除外しない。

## Human Actions / AI Actions — 主体を分離

```json
"human_action_ledgers": ["HUMAN_ACTIONS.md"],
"human_action_id_pattern": "H-[A-Z0-9]+(?:-[A-Z0-9]+)*",
"human_exec_pattern": "exec\\s*[:=]\\s*`?human-only\\b",
"human_exec_values": ["human-only"],
"human_exec_window": 4,

"ai_action_ledgers": ["AI_ACTIONS.md"],
"ai_action_id_pattern": "AI-[A-Z0-9]+(?:-[A-Z0-9]+)*",
"ai_exec_pattern": "exec\\s*[:=]\\s*`?(?:ai-studio|ai-browser|ai-computer|approved-transfer|blocked-permission|blocked-capability)\\b",
"ai_exec_values": ["ai-studio", "ai-browser", "ai-computer", "approved-transfer", "blocked-permission", "blocked-capability"],
"ai_exec_window": 4
```

`[HUMAN]`／`H-...`は`exec: human-only`だけ許可する。AI実行可能なら元のHuman Actionを
AI完了扱いにせず、`[AI-ACTION]`／`AI-...`として別台帳へ登録する。AI actionは
`autonomous-execution.md` §6の6分類だけを使い、approval/evidenceを同じentryへ付ける。

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

## status_consistency — 索引表と詳細節の状態値

```json
"status_consistency": [{
  "file": "docs/CAV_work_packages.md",
  "id_pattern": "WP-[A-Z0-9]+-\\d+[A-Z]?",
  "field": "Status",
  "blanket_phrases": ["全 Work Package の Status は"],
  "index_only_ids": ["WP-W1-001", "WP-W2-001", "WP-LAUNCH-001", "WP-POST-001"]
}]
```

`id_pattern` は詳細節の見出しと索引行の両方に現れる ID にマッチさせる。詳細節側は
見出し直下の `- Status: <値>` を拾い、`（…）` 以降の注記は値に含めない。索引側は
`Status` という見出しを持つ列を自動で特定する。

`blanket_phrases` は「全 Work Package の Status は `Proposed` である」型の一律断定を
拾う。**詳細節の値が2種類以上あるときだけ発火する**ので、着手前の一律状態では鳴らない。

この設定が効いた例: 詳細節を `In progress` へ是正した後、索引表と総則の断定が
`Proposed` のまま残った。**3巡連続で「全文走査した」と報告されながら取り零された型**で、
人手の走査を当てにせず機械検査へ載せるべき代表例。詳細は
[defect-catalog.md](defect-catalog.md) E-3。

`index_only_ids` は「ID 予約だけで詳細節を持たない索引行」を宣言する。宣言しないと
warn が出る。**沈黙を宣言させる**のが要点で、「詳細節が無いのは仕様」と「綴り違いで
取れなかった」は外形上そっくりだから、意図があるなら書かせる。宣言した ID が索引から
消えた場合も warn が出るので、宣言が古びたままにならない。

なお、**履歴行に旧値が残っているのは正しい**。この規則は索引表と一律断定だけを見る。
履歴の失効値は「〜時点の記録である」という時制限定で扱う問題であり、機械では判定できない。

## stage ごとの未適用規則と PASS

warning または未検査 note が1件でもあれば、lint は `FAIL` と終了コード1を返す。GDD 段階で
まだ所有文書・契約・状態索引が存在しない場合は、空設定のまま「検査済み」にせず、次のように
未適用規則を明示的に無効化する。

```json
"rules": {
  "unreferenced-value": false,
  "contract-consumer": false,
  "status-index-drift": false
}
```

対象文書ができた stage で設定値を追加し、対応する `false` を削除して再有効化する。
`--files` で単一文書を検査するときは、範囲外の `status_consistency.file` を欠落扱いにしない。
