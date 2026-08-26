# GDD 作成と intake（D0〜D1.5）

体系の起点。ここで作った歪みは下流の約30文書へ複製されるため、**巻き戻しコストが体系中で最も高い**。逆に、ここで数分かけて決めておけば消える欠陥がいくつもある。

**質問項目そのもの、GDD の必須構成、承認ゲートの条件、D1.5 の適用基準は `phase-definitions.md` と `quality-gates.md` が正本。** 本書はそれを**どう運べば手戻りが出ないか**だけを書く。

architect 側の該当箇所を作業前に読むこと。件数や条件を本書へ書き写さない——書き写した瞬間、architect が改訂されたときに黙ってずれる（実際に本書は初版で質問数を取り違えた）。

**自律実行の共通規約は `autonomous-execution.md` が正本。** 本書は D0〜D1.5 に固有の運び方だけを扱う。

## 1. intake は事前記入し、未回答を確認へ返す

GDD は体系の中で唯一、**内容が上流から導出できない**文書である。下流の Spec は上流から導出できるが、「何を作るか」「何を作らないか」は導出できない。

既存の会話・資料・外部仕様・実測から答えられる欄は指示役が先に埋める。そこから導出できない製品判断は選択肢と推奨を用意し、使用者へ確認する。**出所の記録は必須だが、承認の代わりではない。**

| 出所 | 意味 | 記録の形 |
|---|---|---|
| `U` | ユーザーが会話で述べた内容 | 該当発言の要旨と、述べられた時点 |
| `W` | 調査で得た外部事実 | URL と取得日、引用箇所 |
| `M` | Studio 実測 | 計測記録のパスと実測値 |
| `J` | 指示役の提案 | 判断理由と、採らなかった代替案。承認までは `[PROPOSAL]` |

**`J` を提案として使ってよい。決定として隠すのが問題。** 「なんとなくこうした」を `U` や `W` に見せかけると、後から根拠を辿った人が実在しない裏付けを探すことになる。

**`W` を取りに行けるものを `J` で済ませない。** Roblox の仕様・制限値・課金の仕組み・既存タイトルの実装は調べれば分かる。内蔵ブラウザで Creator Docs / DevForum を読む、Studio MCP の `http_get` で API 仕様を取る、`rbx-docs-search` を使う。調べずに判断すると、学習データの古さがそのまま製品方針の誤りになる。

**製品意図は `U`、外部仕様と実測事実は `W/M` が所有する。** `U` を調査や判断で勝手に変更せず、同時に `U` でプラットフォーム事実を上書きしない。両者が食い違う場合は、意図と制約を別々に記録し、実現不能・安全・規約に関わるなら `[OPEN blocking: yes]` として、成立する代替案を使用者へ返す。根拠なく `U` または `W/M` の片方を「最上位」にしない。

### `[PROPOSAL]` は未承認のまま扱う

`[PROPOSAL]` は architect の定義どおり**AI提案・未承認**を意味する。出所が確定しても自動昇格しない。

処理は次のように分ける。

1. `W/M` で確認した外部・実測事実は `[FACT]` / `[EXTERNAL]` と evidence にする
2. 製品へ反映する案は `[PROPOSAL]` とし、出所と代替案を付ける
3. 使用者が明示承認した案だけ `[DECISION]` へ昇格し、approver・revision・出所を付ける

**証拠と承認は両方要る。** `[PROPOSAL]` が残っている GDD を承認済み正本として扱わないという architect の絶対規則を維持する。0 にするには、使用者が各案を採用または却下する。

### 未回答を止めない運び方

自律モードでも「その場で決められない項目」は残る。実測待ち（`M`）と調査待ち（`W`）がそれ。

- **決められない理由を分類する。** 調査待ちはブラウザで取りに行く。製品判断なら `J` の提案を作り、使用者へ返す。D1.5 の実測待ちは Gate 1 承認後に閉じる
- 実測待ちの項目は `[OPEN blocking: yes]` として登録し、closure 条件を実体で書く
- **「後で決める」を理由にしない。** 何が揃えば決まるのかを書く

### D0 の成果物と停止条件

**intake は会話で終わらせない。** architect は D0 の成果物として intake の構造化ファイルと回答要約を要求し、特定項目が未確認なら停止させる。**停止条件と成果物の形式は architect の workflow が正本**なので、着手前にそこを読む。

運行上の要点は「**GDD handoff を出す前に、intake が出所つきの成果物になり、architect の D0 停止条件を使用者が確認していること**」。会話ログだけを根拠に GDD を書かせると、後から「どの回答に基づいた記述か」を復元できない。handoff の `requirements` に intake ファイルのパスと sha256 を書けるのが望ましい状態。

**intake ファイルには出所欄を持たせる。** 回答本文と出所が別ファイルに分かれると、必ず片方だけが更新される。

`product.top_risks` はfree-formの製品risk台帳であり、D1.5のmachine experimentへ自動変換しない。そこにStudioで実測すべきmechanic riskがあるのに、対応する `vehicle_or_custom_physics` / `high_npc_or_fx_load` / `free_text_or_ugc` / `high_frequency_projectiles_or_fast_pvp` / `multi_place` がfalseなら正規化矛盾である。D0独立reviewは承認せず、該当technical flagと回答出所を確認してから `required_specs` を再生成する。

### 空のリポジトリから始める場合

architect の scaffold で必要な骨組みを作る。ただし scaffold は下流テンプレートも一括生成しうるので、**生成物のうち D0/D1 で扱うのはどれかを handoff の inScope で限定する**。テンプレートが存在することと、それを埋めてよいことは別。

`HUMAN_ACTIONS.md` / `AI_ACTIONS.md` / `DECISIONS.md` / manifest といったルート運用文書は、GDD handoff が更新対象にする以上、**その時点で存在している必要がある**。validator も manifest とルート運用文書を要求する。scaffold で作るか、GDD handoff の inScope に「新規作成」として明示するかを、着手前に決めておく。

### 既存 GDD がある場合

ユーザーが GDD を持ってくることがある（本 Skill が最初に使われたプロジェクトがそうだった）。**intake 自体は飛ばさない。既存 GDD に対して intake を当て、答えられない項目を洗い出す。** 埋まっていない箇所を下流へ送るなら、必ず `[OPEN blocking: yes|no]` として極性・理由・Owner・closure evidence を付ける。

既存 GDD に書かれている内容の出所は原則 `U`（ユーザーが持ち込んだ製品判断）。**既存 GDD の用語・構成・判断を無断で置換しない。** 改善提案は `[PROPOSAL]` として別立てにし、使用者が採用した場合だけ出所 `J` と承認記録を添えて `[DECISION]` にする。

**既存のゲーム／リポジトリを伴う場合は分岐が増える。** architect は D1 の前に Repository Audit を要求する。既存構成・Place mapping・Remote・DataStore・Commerce・Analytics の棚卸しを済ませ、増補範囲を確定するまで既存正本を変更しない。「既存 GDD だけがある」のか「動いているゲームがある」のかで入口が違うので、最初に確認する。

**動いているゲームがある場合、棚卸しの一部は Studio MCP で直接取れる。** `search_game_tree` で構造、`script_grep` で Remote の使用箇所、`inspect_instance` で個別の設定。**production の DataStore と publish 設定には触れない**（`autonomous-execution.md` §7）。

## 2. 決定 ID の参照規約を GDD 発行時に確定する

**体系中で最も高くついた単一の欠陥がこれ。** 対処は5分、放置すると全文書の是正になる。

実際に起きたこと: `D-9` という ID が3つの別物を指していた。

| 出所 | 意味 |
|---|---|
| GDD `D-9` | 視認性のみで判定する |
| Feasibility `FR-2.6 D-9` | 早期確定する |
| gate 閾値提案の `D-1`〜`D-10` | 上記と無関係な独立採番 |

裸の `D-9` で参照している箇所が全文書に散在し、どれを指すのか読者にも AI にも判別できなくなった。最終的に33件の lint error として残った。

### 対処

**ID の形式は architect が正本**（`D-{NNN}` / `F-{NNN}`）。本 Skill が足すのは参照規約と登録手順だけで、ID 本体の形式を変えない。

GDD を書き始める前に、次を決めて GDD の冒頭へ書く。

- **どの文書が独自の `D-n` 系列を持つか**を列挙する。GDD、Feasibility Report、その他が独自採番を持つなら、その事実を先に宣言する
- **参照は常に完全修飾**する。裸の `D-9` を書かず、`GDD D-9` / `Feasibility FR-2.6 D-9` のように**所有文書（と必要なら節）を伴わせる**
- 名前空間が複数あること自体は問題ない。**裸で参照することが問題**。この区別を規約として書く

`.claude/doc-lint.json` の `decision_id_home_docs` へ各文書を登録すれば、`bare-decision-id` 規則が裸参照を機械検出する。**GDD 執筆の handoff に、この登録までを含める。**

`DECISIONS.md` には、**衝突している名前空間の一覧**を記録する。どの文書がどの範囲を使っているかが1箇所にないと、次に採番する人が同じ衝突を起こす。

未承認 draft 内だけの衝突は、旧 ID → 新 ID の対応表を先に作り、全参照を機械的に書き換えられる。承認済み ID または外部で参照済みの ID は監査識別子でもあるため、mapping と影響範囲を使用者へ提示し、承認後に改番する。**対応表なしの改番をしない**——過去の記録が指す先が消える。

## 3. 成功指標の可変閾値を GDD で確定しない

GDD には測定可能な成功指標が要る。architect も要求している。**ただしその数値正本は data_definition へ参照化する**（architect の GDD 必須条件）。

対象は**成功指標の可変閾値**であって、GDD が書く数値すべてではない。製品意図として GDD が持つべき記述（1ラウンドの想定時間、対象端末の優先度など）まで排除しない。判断基準は「**バランス調整で動く値か**」。動くなら data_definition、動かない製品意図なら GDD でよい。

| GDD が持つ | data_definition が持つ |
|---|---|
| 何を測るか（指標の定義） | 可変閾値の値 |
| 判定規則（どうなったら合格・不合格か） | 分母規則・計算式 |
| 不合格時の分岐（D/F 判断） | 単位・丸め |

なお data_definition は gameplay／経済の数値所有者であって、**全数値の所有者ではない**。Remote の rate semantics、性能上限、保存 lifecycle、UI 寸法などはそれぞれ別の Spec が所有し、Remote / Save 等の field-level 値は対応 machine-readable instance が所有する。所有マトリクスは [ordering.md](ordering.md)。

GDD 執筆時点では data_definition がまだ無い。そこで **GDD は指標の key と判定規則だけを書き、値は「data_definition の DATA ID を参照」と宣言する。** data_definition 執筆時にその key を実装する。

これを守らないと、実プロジェクトで起きたことが起きる。Feasibility の性能値が physics・detailed_design・network の3文書へ**逐語で複製され、DATA ID 参照が1件も無い**状態が最終監査まで生存した。

**実測値も同じ扱い。** D1.5 で計測した値を GDD 本文へリテラルで書かない。実測値は evidence が正本であり、製品の可変閾値になるなら data_definition が所有する。GDD は「FR-n の実測に依存する」という関係だけを書く。

## 4. Feasibility trigger を GDD 時点で洗い出し、Studio で実測する

architect skill の D1.5 は、高リスク機能について**設計文書一式より先に**小さな技術検証を作れと定めている。

**時系列は Gate 1 の人間承認 → D1.5 → D2。** trigger は GDD 起草中に列挙するが、製品方針が未承認のまま検証実装へ進まない。D1.5 を Gate 1 の前提にすると循環する。

**GDD を書く時点で、どの機能が trigger を踏むかを列挙する。** 後から気づくと、既に書いた下流文書が「検証されていない前提」の上に立っている。

実プロジェクト（人間承認モード）の例: モバイル騎乗操作・サーバー権威の高速 PvP・Multi-Place / Teleport の3つが trigger を踏み、FR-1 / FR-2 / FR-3 として立てられた。**3つのうち PASS したのは1つだけで、残り2つは計測リソースが確保できず未計測のままD5のW0引渡しゲートを止めた。** D5だけでは実装side effectを許可せず、受領側W0検証とrun固有承認が別途必要である。

**自律モードはこの失敗の直接の対処である。** Studio MCP があれば、計測に必要な人・端末・期間の制約の大半が消える。**したがって「未計測のまま下流へ進む」という選択肢は無い。**

### 手順

1. **閾値と測定条件を計測前に固定する。** 端末（または Studio 条件）、試行数、warmup の破棄数、分母規則、外れ値規則、合格判定、再実験の上限回数。**ファイルとして保存し、タイムスタンプで計測より前だと分かる形にする**
2. 最小実装を Studio へ入れる（製品コードではなく検証用）
3. 指定条件で計測し、**生の出力を** evidence として保存する
4. **PASS / FAIL / INCONCLUSIVE を判定する**
5. FAIL なら**上流 GDD を改訂して再承認する**。失敗した前提のまま下流を量産しない

具体的なツールの使い方、計測の妥当性規則（warmup・外れ値・Studio と実機の差）、INCONCLUSIVE の扱いは `autonomous-execution.md` §4。

**閾値をデータ取得後に変えない。** 実行が速くなったぶん、「とりあえず測ってから閾値を決める」への誘惑が強くなる。データを見てから閾値を決めるのは判定ではなく後付けの正当化。実プロジェクトでは事後変更を2回行い、inconclusive の再実験枠を使い切った。

**まだ一度も計測していない実験なら、閾値や条件の見直しは事後変更にあたらない。** 正当な計画改訂として処理できる。**計測前なら直せる**という一点が、順序を守る価値のすべて。

### 実測できない場合

Studio MCP が使えない、または production 環境でしか確かめられない項目（実回線 RTT、実機の発熱、publish 後の Teleport）は残る。

- 端末固有の性能・発熱・実指入力・実回線が仮説なら、priority device 実機なしでは `INCONCLUSIVE`。PASS にしない
- 端末固有差へ依存しない仮説だけ、代替環境と限定範囲を計測前に固定して `PASS (Studio scope)` 等を記録できる。priority-device PASS と書かない
- 結果に依存する判断を `[OPEN blocking: yes]` として登録する
- publish等の人間専権は`HUMAN_ACTIONS.md`へ`exec: human-only`、AI停止理由`blocked-safety`として送る。実行面不足は`AI_ACTIONS.md`へ`exec: blocked-capability`と再開条件を記録する
- FAIL 時に是正対象となる文書の範囲を、この時点で列挙する

理由句の書き方が本質的に効く。

- 悪い: 「FR-3 が未実施のため保留」→ FR-3 を実施した瞬間に嘘になる
- 良い: 「FR-3.9 Result が未確定のため配信単位を確定しない（closure: FR-3.9 に Result が記録されたとき）」→ 条件が実体を指す

## 5. Human ActionsとAI ActionsをGDD時点から分離する

Group作成、production publish、商品ID、Secrets、Dashboard権限、規約・権利処理などarchitectが`[HUMAN]`とした作業は、`HUMAN_ACTIONS.md`へ`exec: human-only`で登録する。AIが同じ行を実行済みにしない。

Studio実測、browser調査、許可済みOS操作、承認済みLLM送信は`[AI-ACTION]`として`AI_ACTIONS.md`へ別登録する。分類は`autonomous-execution.md` §6。

**GDD で製品方針が決まった時点で、必要になる作業が既に見えている。** その時点から `HUMAN_ACTIONS.md` へ積み始める。

実プロジェクトでは台帳を D3 で作り始めた結果、各 Spec に散在する gate を取りこぼし、**16件 → 104 → 112 → 113 → 最終119** と照合のたびに増えた。毎回「全文走査した」と報告された後に漏れが出た。

対処は3つ。

- GDD／各Spec handoffに「`[HUMAN]`と`[AI-ACTION]`を別台帳へ登録するところまで」を含める
- 台帳の照合依頼では**サンプル検査を許さず**、照合者自身に全文走査させる
- `AI_ACTIONS.md`はapproval/evidence/closureを同じentryへ書く。分類だけで実行済みにしない

**`blocked-safety` を過小に見積もらない。** 自律モードの目的が「人間を挟まないこと」だと誤解すると、blocked を失敗とみなす圧力が生まれる。これはAI停止理由。対象作業は`HUMAN_ACTIONS.md`へ`exec: human-only`で置き、`AI_ACTIONS.md`へ混在させない。

## 6. 承認準備と人間承認ゲート

**承認条件は architect の Gate 1（`references/quality-gates.md`）と workflow D1 が正本。** 残っていてはいけないタグの種類も、承認前に下流をどこまで進めてよいかも、そちらが定める。**ここへ書き写さない**——書き写すと architect の改訂で黙ってずれる。作業前に architect 側を読むこと。

指示役は次を全部満たしたときに限り、**承認準備完了**として使用者へ提示する。

1. 機械検査 PASS（lint + validator + sha256 + scope）
2. 独立照合（別セッション・読み取り専用）で Critical 0 / Major 0
3. `[PROPOSAL]` 残数 0。各 `[DECISION]` に出所（§1 の4分類）が付いている
4. architect の Gate 1 が要求する条件を、条件文ごとに充足を確認した記録がある
この4条件は人間承認の代替ではない。exact Draft GDD path/hash/revisionとclosed scopeからhuman challengeを作り、使用者が返したexact canonical responseをtrusted transcript/statement artifactへ保存する。captureをoperator-pinned external channel queryまたはsignatureの`provenance_verification`へ束縛し、そのproofを参照するtype `gdd-gate1` machine recordを検証して、`DECISIONS.md`へ同じID・approver・対象revision・authority時刻・証拠を記録する。沈黙、照合の「承認可」、指示役の品質判定、局所生成したID/hashだけを承認に数えない。GDD formal headerはB1まで `Status: Draft`。D5 external verification後のfixed metadata-only transformationだけが `Approved` / `Last approved` / historyを設定し、normalized body digestを変えない。

**本 Skill が運行として上乗せするのは1点**——D2/D3 の執筆自体を、Gate 1 の人間承認と必要な D1.5 PASS の後まで待つ。理由は、承認または実測で方針が変わったとき、書いてしまった下流が全部是正対象になるから。

`DECISIONS.md` への記録形式は `autonomous-execution.md` §5。人間承認前は `承認準備完了` と書き、`承認済み` と書かない。

## 7. GDD 段階の handoff で必ず入れる制約

`templates/gdd_handoff.md` を使う。個別に書き起こさない。要点だけ挙げると:

- **製品判断に出所と人間承認記録を付す。** `J` は承認済み提案だけ。どちらか欠けるなら `[PROPOSAL]`
- **`W` で取れるものを `J` で済ませない。** Roblox の仕様・制限は調査で確定する
- **成功指標の可変閾値を GDD に確定しない。** 指標 key と判定規則のみ。値は data_definition へ送る
- **他文書の決定 ID を参照するときは完全修飾する**（ID 本体の形式は architect が正本）
- **Non-Goals の必要件数と GDD 必須構成は architect の GDD template を参照する。** 件数を handoff へ書き写さない
- **裸 `[OPEN]` 禁止**（`blocking: yes|no` 併記）
- 既存資料がある場合、**用語・構成・判断を無断で置換しない**
- 本文で新設した`[HUMAN]`と`[AI-ACTION]`を別台帳へ登録するところまでを範囲に含める

## 8. GDD 承認後にやること

人間承認後、Tier 0 へ進む前に次を済ませる。順序を守ると後の巡数が減る。

1. Gate 1 challenge/capture/external provenance/machine recordを検証し、`DECISIONS.md`へ同一IDの人間承認を記録。GDD headerは `Status: Draft` を維持し、exact bytesをB1まで変えない
2. **D1.5 trigger の実測**。該当があれば Feasibility を先に通す（§4）。FAIL で GDD を改訂した場合は再承認を得て、その記録も更新
3. lint 設定の見直し（`decision_id_home_docs` への GDD 登録は起草の handoff で済んでいるはず。漏れていればここで補う。段階は §9）
4. `HUMAN_ACTIONS.md`（human-only）と`AI_ACTIONS.md`（機械作業）を更新。approved AI actionだけ実行しevidenceを付ける
5. 開始時に commit 許可を得ている場合だけ commit。許可が無ければ sha256 と snapshot で baseline を固定

そのうえで `ordering.md` の Tier 0 へ進む。

## 9. lint 設定をいつ作るか

**最小構成は GDD handoff を出す前**に用意する。GDD の機械検査（`bare-open`、`stale-premise`、`unsourced-decision` 等）は承認判定より前に行うので、承認後に作るのでは間に合わない。

- **GDD handoff より前**: `doc_globs` / `exclude_globs` / `report_globs`、`bare_open_exempt_docs`、`decision_source_pattern`、`human_action_ledgers`、`ai_action_ledgers`。複数形と実装keyをそのまま使う
- **GDD 起草と同時**: `decision_id_home_docs` への GDD の登録（handoff の inScope に含める）
- **Tier 0 以降**: `value_owner_docs`、`contracts`、`forward_refs`、`status_consistency`。所有文書や契約が存在してから足す

`value_owner_docs` や `contracts` が空のまま規則を実行すると、lint は未検査 note と終了コード1を返す。まだ適用できない stage では `rules` で明示的に無効化し、対象文書ができた時点で設定を追加して再有効化する。warning / note がある状態を PASS として扱わない。
