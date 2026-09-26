# 出力契約

## 1. 既定の成果物

```text
research/<market-slug>/<実行日>/
├── market-analysis.md
├── evidence-ledger.json
├── research-log.md
└── CHANGELOG.md
```

単なるランキング依頼ではなく3段階の分析を行うSkillなので、統合レポートには3問すべてへの回答または未判定理由を含める。
別々の巨大レポート、HTML、グラフ、スライドを既定では増やさない。ユーザーの明示指定があれば追加する。
更新時は既存ファイルを確認し、新規実行なら別フォルダー、既存結果の更新依頼なら差分と以前の観測を保持する。

## 2. 統合レポートの順序

1. **結論**：市場史の大きな変化、現在の集中先、現在の偏り、持続的ニーズ。信頼度と範囲。
2. **対象と方法**：市場境界、地域、期間、時代区分、選定方法、成功と集中の定義、未取得範囲。
3. **20〜30年の市場史**：時代表、転換の根拠、前史・隣接市場の別表、異なる流れ。
4. **歴史的な重要作品一覧**：当時のヒットと影響を区別する。
5. **現在の集中タイトル一覧**：比較可能群、指標、期間、出典。直接未検証の候補は別表。
6. **共通要素の比較表**：分類基準、作品別判定、数と分母、不明、共起、系列・期間の感度。
7. **主流と偏り**：Bカード、比較対象、反例、需要・供給の別解、複数主流、持続性。
8. **持続的ニーズ**：Nカード、時代別の異なる満たし方、反証、対象者、限界。
9. **現在の主流と持続的ニーズの対応表**：B-N-E-Wを結び、充足状況は根拠の範囲で示す。
10. **限界と未解決点**：未取得指標、弱い年代、対立仮説、何が分かれば結論が変わるか。

重要な事実・数値のすぐ近くに出典IDとリンクを記載する。リンク先のどこが根拠か、節・表・ページ・動画時刻を残す。
外部テキストを大量に転載せず、要約を中心にし、直接引用は必要最小限にする。

## 3. 表の最低列

### 時代表

`E-ID / 期間 / 代表W-ID / 当時の主流 / 当時の人気・影響の根拠 / 普及条件 / 後退・変化 / 残った価値の仮説 / 出典`

### 歴史作品表

`W-ID / 作品・版 / 市場区分 / 発売・サービス期間 / 対象時代 / 役割 / 当時の成果の指標・期間 / 特徴 / 出典 / 未確認点`

### 現在作品表

`W-ID / 作品・版 / 地域・端末 / 現況 / 指標・値 / 実測・推計・代理 / 対象期間・時刻 / 比較群 / 一時要因 / S-ID / 限界`

非比較の値には順位を付けない。現在作品が不明なら、その不明を独立した結果として示す。

### 特徴表

`W-ID / F-ID / 判定 / 確認した版・範囲 / 観察根拠C-ID / 判定理由`

### 偏り表

`B-ID / 解釈 / 支持作品と共通性 / 比較基準 / 例外 / 別解 / 対象者・期間 / 信頼度 / C-ID`

### 持続的ニーズ表

`N-ID / 対象者と望む結果 / 初期の実現例 / 中期の実現例 / 現在の実現例 / 異なる形式 / 反証 / 持続性の種類 / 信頼度 / C-ID`

時代の数は実際の史料に合わせる。3列を埋めるための架空例を作らない。

## 4. JSONの構造

同梱の空テンプレートは調査結果ではない。実行中に観測したレコードを追加する。
以下のフィールド規約に沿う。有効なJSONを作り、日付不明は `null`、欠測は理由を付ける。数値0を欠測の代用にしない。

### 最上位

`schema_version / meta / sources / claims / works / metrics / eras / features / codings / mainstream_biases / durable_needs`

### meta

- `market_original`：ユーザーが指定した市場の原文。
- `market_scope`：`core / lineage / adjacent / geography / platforms / exclusions / assumptions`。
- `analysis_as_of`：実際の分析基準日時。未実行の空テンプレートは `null`。
- `timezone`：ユーザー指定または `Asia/Tokyo`。
- `history_window`：要求年数、希望開始・終了、実際の中核市場の確認範囲、前史の範囲。
- `current_window`：現在の集中を調べた実際の開始・終了・指標の範囲。
- `trend_window`：構造的な主流を確認した期間。
- `mode / depth / status`：設定値と `not_started / in_progress / complete / partial / sources_only`。
- `selection_method / capabilities / limitations / unresolved`：選定・能力制約・空白。
- `complete` は依頼範囲の手順を終えた意味であり、市場全体を網羅した意味ではない。

### sources[] : S-ID

`id / title / publisher / url_or_path / published_at / retrieved_at / locator / source_kind / access_status / origin_group / notes`

`access_status` は `verified / snippet_only / unavailable`。出典の存在だけで全主張を保証しない。
`origin_group` は同じ発表・調査を元にする転載を束ねる。URLのない実資料は実在のパスを使う。

### claims[] : C-ID

`id / type / text / scope / source_ids / supporting_claim_ids / counterevidence / alternatives / confidence / confidence_reason`

`type` は `fact / interpretation / hypothesis`。
`fact` は実際に確認した元資料を必須にする。解釈・仮説は支持するC-IDまたはS-IDへつなぐ。
根拠不足の仮説を残す場合は、confidenceを `low / unknown` にし、不足内容を明記する。
主張間の循環参照で根拠を作らない。

### works[] : W-ID

`id / title / aliases / identity / series_or_family / scope_class / roles / release_claim_ids / era_ids / metric_ids / claim_ids`

`identity` はURL、プラットフォームのID、版、サービス地域など、同名作品を識別できるもの。
`scope_class` は `core / lineage / adjacent`。現在の中核市場集計に後二者を含めない。
`roles` は研究プロトコルにある役割の配列。

### metrics[] : M-ID

`id / work_id / metric / definition / value / unit / estimate_kind / window_start / window_end / observed_at / retrieved_at / geography / platform / population / method / comparability_group / source_ids / missing_reason / event_note`

`estimate_kind` は `reported / estimated / proxy / unknown`。
`value` は数値または `null`。元資料の「以上」「約」などは、追加の `qualifier` と `raw_value` に保持する。
原文が順位しかないなら人数を作らず、指標名を順位にする。範囲値がある場合は追加の `lower / upper` を使う。

### eras[] : E-ID

`id / label / start / end / scope_class / work_ids / transition_claim_ids / summary / limitations`

### features[] : F-ID

`id / label / layer / definition / coding_rule / comparison_unit`

`layer` は `theme / mechanism / value / supply_condition`。

### codings[]

`work_id / feature_id / status / version_or_context / claim_ids / reason`

`status` は `present / partial / absent / unknown / not_applicable`。
同じ作品と特徴でも時代・版が違えば別レコードにする。根拠のない `present / absent` を作らない。

### mainstream_biases[] : B-ID

`id / statement / scope / feature_ids / supporting_work_ids / reference_group / counterexample_work_ids / claim_ids / counts / alternatives / persistence / confidence / confidence_reason`

`counts` は集計した場合のみ入れる。母集団、全件数、確認可能数、採用・部分・不明・非該当、算出法を持たせる。
未集計なら `null`。全市場のシェアや因果効果へ読み替えない。

### durable_needs[] : N-ID

`id / statement / audience / situation / desired_outcome / manifestations / bias_ids / counterevidence / alternatives / persistence_type / scope_limits / confidence / confidence_reason / open_questions`

`manifestations[]` は `era_id / work_ids / changing_form / mechanism / value_claim_ids`。
市場史に足りない時代を、この配列に架空で足さない。

## 5. 手動・プログラムで確認する項目

1. JSON構文。
2. 各IDの一意性と正しい型。
3. 全参照が存在し、出典までたどれるか。
4. 事実の出典の確認状態。
5. 数値の単位、期間、版、比較群、欠測理由。
6. 分母と対象群が文章・表で一致するか。
7. 源流・隣接作品の混入がないか。
8. MarkdownとJSONで、主張・数値・信頼度が一致するか。
9. 日付の逆転、固定作成日を実行日に使っていないか。
10. 単なるスキーマ適合を、内容の正しさやCodex実行成功の証明にしていないか。

自動検証ツールは同梱しない。利用できるJSON処理・コード実行で検査するか、手動で確認した範囲を記載する。

## 6. ログと更新

`research-log.md`：日時／検索語／読んだ資料／得た証拠／棄却・除外理由／未取得／次の論点／終了理由。
`CHANGELOG.md`：実行日時／変更前後のB・N／追加・訂正したC・M／結論が変わる理由／未解決点。

同じ作品の新しい指標は、新規M-IDにする。古い数値を消さない。誤りを訂正する場合も、訂正理由を履歴へ残す。
