# 自律実行 — 機械作業を自律化し、承認権限を守る

本 Skill は、調査・D1.5 実測・lint・照合起動・ローカル検証など、**機械的に完結できる作業を人間へ送り返さない**。指示役が実行面を使い、証拠を残して判定する。

**ただし権限は自律化しない。** `absolute-rules.md` は D0 の確認、GDD/D5 の明示承認、`[DECISION]` の意味を人間に置いている。未回答の製品判断、AI提案の決定昇格、未許可 commit、production・課金・権限・認証操作は人間へ残す。

実測値・照合記録・出所参照は、品質を検証し承認判断を支える。**いずれも人間承認の代替ではない。** 出所は「何を根拠にしたか」、承認記録は「誰が何を確定したか」であり、両方を残す。

---

## 1. 実行面と選択順

4つの実行面がある。**上から順に試し、下位へ落ちるのは上位で不可能なときだけ。**

| 実行面 | 使うもの | 何ができるか |
|---|---|---|
| Studio MCP | `mcp__Roblox_Studio__*` | Luau 実行・スクリプト作成・Play 起動・console 取得・画面取得・Studio計測・API docs 取得 |
| 内蔵ブラウザ | `mcp__Claude_Browser__*` | Creator Docs / DevForum / 実在ゲームの調査、ページ本文取得 |
| Computer Use | `mcp__computer-use__*` | Studio GUI 操作（MCP で届かない設定パネル等）、他アプリ |
| ローカル | Bash / Read / Write | git・lint・validator・文書執筆 |

**選択順を守る理由**: 下位ほど遅く、失敗が見えにくい。Studio の状態を知りたいときに Computer Use でスクリーンショットを撮って目視するより、`execute_luau` で値を返させるほうが速く、証拠としても強い（数値が残る）。

### Studio MCP の主要ツール

| 目的 | ツール |
|---|---|
| 接続確認・studio_id 取得 | `list_roblox_studios` |
| Edit/Play の別と利用可能 datamodel | `get_studio_state` |
| 任意Luau実行 | `execute_luau {studio_id, datamodel_type, code}`。値は必ず明示的`return {...}` |
| Play 開始・停止 | `start_stop_play` |
| 出力ログ取得 | `get_console_output` |
| 画面取得（カメラ位置指定可） | `screen_capture {studio_id, capture_id, ...}` |
| 構造探索・インスタンス詳細 | `search_game_tree` / `inspect_instance` |
| スクリプト作成・編集 | `multi_edit`（存在しなければ `className` 指定で新規作成） |
| 入力再現（Client） | `user_keyboard_input` / `user_mouse_input` / `character_navigation` |
| Creator Docs / API 参照 | `http_get`（許可 URL パターンのみ） |
| 内蔵スキル | `skill`（`rbx-perf-profiling` / `rbx-scene-analysis` / `rbx-device-simulator-lua` / `rbx-docs-search`） |

内蔵Skillは実行前に取得し、全文、取得時刻、sha256をevidenceへ保存する。MCP配信内容は動的でversionを持たないため、**実行時tool schemaが最優先**。不存在tool、必須引数欠落、本文内矛盾をそのまま実行しない。

既知compatibility guard:

- `set_active_studio`を使わない。全callへ選択済み`studio_id`を渡す
- `rbx-perf-profiling`を`execute_luau`から使う場合、`OpenFromLiveData`例を採用しない。capture→snapshot buffer→open→disposeへ統一
- Device Simulatorの「screenshotだけで十分」は採用しない。数値検証script/consoleを主証拠にし、画像だけなら定性的所見または`INCONCLUSIVE`

---

## 2. E0 capability preflight（着手前に1回だけ）

**何が使えるかを確認してから運行計画を立てる。** Studio が繋がらないのに「D1.5 は実測する」と書いた計画は、実測の段で止まる。

```
1. list_roblox_studios
2. name/Place/idを照合し、対象studio_idを1つに束縛
3. get_studio_state {studio_id}
4. execute_luau {studio_id, datamodel_type:"Edit", code:"return {probe = 2}"}
5. http_get でCreator Docsの既知.md URLを取得
6. browserが必要なら現行tool一覧からnavigate/read schemaを確認して最小閲覧
7. approved-transfer取得後、project内容なしの固定worker probe
```

`preview_start`はdev serverを`name`指定で起動するtool。URL閲覧に使わない。worker probeの外部送信契約は`execution-envelope.md`に従う。

結果を `docs/handoffs/out/E0_capability_probe.md` へ保存する。**E0 は D0 より前の preflight であり、project 内容なしの固定 worker probe を D0 worker 起動として数えない。** 各段の記録には実際の出力を貼る（「疎通した」という要約ではなく、返ってきた studio_id と state）。プローブ後、使用者へ執筆役・照合役と到達点を確認する（`worker-registry.md` §6、`orchestration.md` §2）。

### 使えない実行面があった場合

- **Studio MCP が無い**: Roblox Studio を起動する（Computer Use の `open_application` で `Roblox Studio`）。それでも MCP が繋がらないなら、D1.5 の実測が不可能になる。**この事実を運行計画の先頭に書き、trigger 該当機能を `[OPEN blocking: yes]` として登録する。** 実測できないまま PASS 判定を書かない
- **ブラウザが無い**: Studio MCP の `http_get` が Creator Docs を取れる。調査対象が Roblox 公式ドキュメントに限られるなら代替になる
- **Computer Use の許可が下りない**: Studio 操作は MCP で大半が届く。届かない設定パネルに触る必要が出たら、`AI_ACTIONS.md`へ`exec: blocked-permission`として送り、必要権限と再開条件を記録する。tool自体が無い場合だけ`blocked-capability`にする（安全境界による`blocked-safety`とは別。§7）

---

## 3. intake を事前記入し、未回答を確認へ返す

**質問項目・GDD 必須構成は `phase-definitions.md` が正本。** 本節が決めるのは、回答を誰がどう作るかだけ。

既存の会話・資料・調査・実測から埋められる欄は指示役が事前記入する。埋められない製品判断は提案と選択肢を用意して使用者へ返す。**回答の出所を4分類で必ず記録する**が、出所は承認を意味しない。

| 出所 | 意味 | 記録の形 |
|---|---|---|
| `U` | ユーザーが会話で述べた内容 | 該当発言の要旨と、それが述べられた時点 |
| `W` | 調査で得た外部事実（Creator Docs・DevForum・実在タイトル） | URL と取得日、引用箇所 |
| `M` | Studio 実測 | 計測記録のパスと実測値 |
| `J` | 指示役の提案（上記いずれでもない） | 判断理由と、採らなかった代替案。人間承認まで `[PROPOSAL]` |

`J` は**提案として使ってよいが、決定として隠さない**。「なんとなくこうした」を `U` や `W` に見せかけると、後から根拠を辿った人が実在しない裏付けを探すことになる。architect の D0 停止条件にある製品 thesis・主要リスク・MVP の問い・端末優先度は、使用者の確認を得る。

### `[PROPOSAL]` は未承認のまま扱う

`[PROPOSAL]` は architect の定義どおり、**AI提案・未承認**を意味する。出所が確定しても自動昇格しない。

処理は次のように分ける。

1. `W` / `M` で確認した外部・実測事実 → `[FACT]` / `[EXTERNAL]` と evidence を記録する
2. その事実を製品へどう反映するか → `[PROPOSAL]` として使用者へ提示する
3. 使用者が明示承認した製品判断 → `[DECISION]` へ昇格し、approver・revision・出所を記録する

**証拠と承認は両方要る。** `J` に理由・代替案があっても、使用者承認までは `[PROPOSAL]` のまま。Gate 1 で `[PROPOSAL]` を 0 にするには、採用・却下を使用者が明示する。

`W` を取りに行けるものを `J` で済ませない。Roblox の仕様・制限値・既存タイトルの実装は**調べれば分かる**。調べずに判断すると、学習データの古さがそのまま製品方針の誤りになる（`EditableImage`・`buffer`・`UnreliableRemoteEvent` のような比較的新しい API は特に危険）。

---

## 4. D1.5 Feasibility を実測する

**自律モードで最も価値が上がる箇所。** 人間承認モードでは、実測に人・端末・期間の制約があるため「未計測のまま下流へ進む」逸脱が実際に起きた（実プロジェクトでは3つの FR のうち2つが未計測のまま実装開始ゲートを止めた）。Studio MCP があれば、その制約の大半が消える。

**D1.5 は GDD の人間承認後、D2 の前に行う。** trigger を踏んだら計測する。計測できない事情があるなら、それは `[OPEN blocking: yes]` として登録し、下流を書かない。D1.5 を Gate 1 の前提にして循環させない。

### 手順

```
1. 閾値と測定条件を固定する      ← 計測前。ここを飛ばすと事後の閾値変更が起きる
2. 対象studio_idとpre-stateを記録
3. 最小実装をStudioへ入れる       multi_edit / execute_luau
4. Play開始後、get_studio_stateを期限付きpollしてClient/Server準備を確認
5. 計測する                      入力再現 → console/structured result
6. 判定する                      PASS / FAIL / INCONCLUSIVE
7. finally cleanup               stop / temporary Instance削除 / Simulator復元 / session dispose
8. post-stateを記録し、pre-stateとの差を検査
9. FAILならGDD改訂・人間再承認
```

**1 を飛ばさない。** 実行が速くなったぶん、「とりあえず測ってから閾値を決める」への誘惑が強くなる。データを見てから閾値を決めるのは判定ではなく後付けの正当化。閾値・試行数・分母規則・外れ値規則・合格判定を、**計測を1回も回す前に**書いて保存する。

まだ一度も計測していない実験なら、閾値の見直しは事後変更にあたらない。**計測前なら直せる**という一点が、順序を守る価値のすべて。

### 計測の妥当性規則

自動化すると試行数を増やせるが、増やしても妥当でない計測は妥当にならない。

- **warmup を捨てる。** 最初の数試行はアセットロード・JIT・キャッシュの影響を受ける。捨てる試行数を事前に決める
- **1試行の定義を書く。** 「1ラウンド」なのか「1入力から1描画まで」なのかで数字が変わる
- **外れ値規則を事前に決める。** 「上下 5% を除く」等。計測後に「この1件は明らかにおかしいので除く」をやらない
- **Studio Play は実機ではない。** サーバー・クライアントが同一マシンで動くため、ネットワーク遅延・端末性能・入力遅延が実機と違う。**Studio 計測で PASS しても、それは「Studio 環境で PASS」でしかない。** 記録にその限定を書く
- **端末差が効く項目は device simulator を併用する。** モバイル UI・入力・セーフエリアは `rbx-device-simulator-lua` で形状別に確認する。それでも実機の指の太さや発熱は再現できない。再現できない差は記録へ書く
- **サーバー権威・ネットワーク項目は Studio の複数クライアントで確認する。** それでも RTT は実回線と違う

### priority device 実機が無い場合の判定

- 性能、発熱、実指入力、実回線など**端末固有差が仮説の成否を左右する**なら `INCONCLUSIVE`。Studio / simulator 結果だけで PASS にしない
- API挙動、状態遷移、権威境界など端末固有差へ依存しない仮説は、計測前の条件に「代替環境」「除外する端末差」「限定 PASS の適用範囲」を固定した場合だけ PASS 可
- 結果名は `PASS (Studio scope)` 等にし、priority-device PASS と書かない。残る実機確認は owner と due production gate を持つ非blocking実装後検証として登録できるが、未計測の端末固有仮説を非blockingへ変換しない

### INCONCLUSIVE の扱い

自律モードでは再実験を自分で回せる。**だからこそ上限を先に決める。** 「PASS が出るまで回す」は判定ではない。

- 再実験の上限回数を、閾値と同時に固定する（例: 2回）
- 上限に達しても INCONCLUSIVE なら、**計測条件の問題ではなく設計の問題**として扱い、GDD の改訂（機能の縮小・代替手段）へ倒す
- 「条件を変えたらもう1回」は条件変更の理由を書いた場合に限り、変更後の計測は**別の実験として採番する**（前の結果を上書きしない）

### 記録

evidence は `docs/evidence/` 配下へ、計測ごとに1ディレクトリ。最低限:

- 固定した閾値・条件（計測前に書いたもの。タイムスタンプで前後が分かる形）
- 実行した Luau のコード全文
- 生の出力（`get_console_output` の内容。要約しない）
- target studio name/id、datamodel、pre/post state、poll回数と期限
- 使用した内蔵Skill本文の取得時刻・sha256
- `screen_capture`を使った場合は一意な`capture_id`、保存画像または取得payloadのsha256。画像を保存できなければ定性的所見に限定
- finally cleanup（Play停止、一時Instance削除、Simulator復元、session dispose）の各結果
- 集計と判定
- Studio 環境と実機の差のうち、この計測で再現できていないもの

---

## 5. 承認準備を完了し、人間承認へ渡す

**承認条件と承認者は architect の Gate 1 と workflow が正本。** 指示役は条件の逐条確認と証拠作成を担い、承認者を置き換えない。

### 承認提示の条件

次を**すべて**満たしたときに限り、使用者へ承認を求める。ひとつでも欠けたら「承認準備完了」と報告しない。

1. 機械検査 PASS（lint + validator + sha256 + scope）
2. 独立照合（別セッション・読み取り専用）で Critical 0 / Major 0
3. `[PROPOSAL]` 残数 0。各 `[DECISION]` に出所（§3 の4分類）が付いている
4. architect の該当 gate が要求する条件を、条件文ごとに充足を確認した記録がある

Gate 1 の承認後も GDD formal header は `Status: Draft` のまま。該当する D1.5 を実測する。D1.5 FAIL は GDD 改訂と人間の再承認へ戻し、PASS のみ D2 へ進める。

### `DECISIONS.md` の記入形式

承認記録は、**誰が何をどの証拠で承認したかを機械的に辿れる形**にする。

```markdown
## {日付} {対象文書} {version} 承認

- 判定: 承認済み
- 承認者: {使用者を識別できる役割名}
- 承認記録: {明示承認が含まれる会話・記録への参照}
- 機械検査: lint {規則数} PASS / validator {gate} PASS / sha256 `{実測値}`
- 独立照合: `docs/handoffs/out/{id}_review{N}.md`（{N}巡・Critical 0 / Major 0）
- formal header: `Status: Draft`（D5まで維持）
- PROPOSAL 残数: 0
- 実測依存: {FR-n の evidence パス、または「なし」}
- 出所内訳: U {n} / W {n} / M {n} / J {n}
```

指示役の逐条確認だけなら `判定: 承認準備完了` と記録し、`承認済み` と書かない。沈黙、照合の「承認可」、AIの品質判定は明示承認に数えない。

### 独立照合でも代替できないもの

独立照合は品質検査であり、製品判断の権限を持たない。次で品質上の盲点を減らしても、人間承認を代替したとは記録しない。

- 独立照合を**別セッション・読み取り専用**で必ず回す（同一セッションの自己レビューは検証にならない）
- 監査フェーズでは**モデル系統を変える**（`review-protocol.md` の監査設計）
- `J` 出所の承認済み決定と未承認提案を集計し、多いところを重点的に照合へ回す。各 `J` 決定が人間承認へ遡れるか確認する

---

## 6. Human ActionsとAI Actionsを分離

`[HUMAN]`と`HUMAN_ACTIONS.md`はarchitect定義どおり**人間のみ実行可能**。AIが実行・完了扱いにしない。

機械的に実行可能な作業は別タグ`[AI-ACTION]`、別台帳`AI_ACTIONS.md`へ置く。

| AI action class | 要件 |
|---|---|
| `ai-studio` | studio_id、承認済み操作範囲、pre/post state、evidence |
| `ai-browser` | URL/domain、取得時刻、response hash |
| `ai-computer` | 個別操作承認、window/process identity再確認、evidence |
| `approved-transfer` | provider/account/path/hash/costの送信承認とattestation |
| `blocked-capability` | 不足tool/schema/versionと再開条件 |
| `blocked-permission` | install、送信、OS入力、commit等の承認待ち |

`HUMAN_ACTIONS.md`からAI実行可能項目を見つけても、その行を完了せず、canonical文書の意味を保ったまま`AI_ACTIONS.md`へ別actionとして参照登録する。human actionのclosure条件がAI evidenceで満たせるかはarchitect/使用者が決める。

---

## 7. 安全境界 — 自律化しない線

**機械作業を自律化することと、安全規則を外すことは別。** 次はAIが実行しない。ユーザーの明示的な指示があっても、この線は動かない。

### 実行しない

- **認証情報の入力**: Roblox アカウントのパスワード・2FA・Open Cloud API キー・`.env` の secret。値を見ることも入力することもしない
- **アカウント作成**: Roblox アカウント、Group への加入申請を含む
- **production への publish**: `File > Publish to Roblox`、既存 Place の上書き公開、Game Settings の公開範囲変更
- **課金・実費が動く操作**: Developer Product / Gamepass の作成と価格設定、Robux 消費、広告出稿
- **production データへの書き込み**: 本番 DataStore、production の Universe / Place 設定
- **規約・ライセンスの承諾**: Creator Dashboard の同意画面、サードパーティ素材の利用規約承諾
- **法的効力を持つ権利処理**: 許諾取得の連絡、ライセンス契約の締結

これはプロジェクト `CLAUDE.md` の標準規則（production ID・DataStore・製品・secret・publish 設定に触れない）と一致しており、**自律モードはこの規則を緩めない**。

### 代わりにやること

線を越えないまま作業を進める方法は、ほぼ常にある。

- publish が要る検証 → ローカル `.rbxl` と Studio Play で可能な範囲まで検証し、publish後にしか確かめられない項目を`HUMAN_ACTIONS.md`へ`exec: human-only`、AI停止理由`blocked-safety`として切り出す
- production DataStore が要る検証 → Studio の DataStore はサンドボックス側で扱い、production 依存の項目を切り出す
- 商品 ID が要る記述 → ID を確定させず、`[OPEN blocking: yes]` で key と確定プロセスだけ書く
- 権利判断 → 調査（`W`）と整理は AI が行い、**法的効力を持つ最終処理だけ**を台帳へ

**切り出した項目には、何が確認できていないかを具体的に書く。** 「publish が必要」ではなく「publish 後の Universe 間 Teleport の実 RTT が未計測（closure: 実 Place で計測し evidence が登録されたとき）」。

### 判断に迷ったとき

「これは実行してよいか」で迷ったら次を問う。

1. secret値、production設定/data、課金、規約承諾、法的効力、一般公開か → `blocked-safety`
2. bounded LLM送信か → `execution-envelope.md`の`transferApproval`があれば`approved-transfer`、無ければ`blocked-permission`
3. install、OS入力、capture、commit等の可逆だが未承認操作か → `blocked-permission`
4. tool/schema不足か → `blocked-capability`
5. それ以外のapproved local read/mechanical verificationか → 実行しevidence保存

**「第三者への送信」を一律`blocked-safety`にしない。** 承認済みLLM送信と、公開・法的連絡・production作用を区別する。

---

## 8. 自律モード固有の欠陥

機械作業を自律化すると、従来と別の欠陥が出る。`defect-catalog.md` の A〜F に対する追加。

### G-1. 出所または承認記録なき決定 ★本モードの最大リスク

- **症状**: 製品判断が `[DECISION]` だが、出所（`U`/`W`/`M`/`J`）または人間の承認記録が無い
- **なぜ起きるか**: 調査・実測・照合までAIが連続実行すると、証拠が揃った瞬間を承認と取り違えやすい
- **なぜ被害が大きいか**: 出所があっても、誰が製品判断を確定したか不明なまま下流へ複製される
- **検出**: lint 規則 `unsourced-decision`
- **修正型**: `[DECISION]` の全出現へ出所と承認記録を付す。人間承認が無ければ `[PROPOSAL]` へ戻す。`W` を取りに行けるものを `J` で済ませない

### G-2. 計測の自己都合な解釈

- **症状**: 実測はしたが、判定が甘い。閾値を跨いだ値を「概ね達成」と書く、外れ値を後から除く、試行数を PASS が出るまで増やす
- **なぜ起きるか**: 計測者と判定者と、FAIL のときに困る人が同一。人間承認モードでは判定の甘さを人間が見ていた
- **検出**: 機械検出は困難。**閾値・条件を計測前に保存し、判定時にそのファイルを引用する**運用で予防する。照合依頼で「閾値ファイルのタイムスタンプが計測より前か」を確認させる
- **修正型**: PASS / FAIL / INCONCLUSIVE の3値に限り、中間表現（「概ね」「実用上問題ない」）を使わない。FAIL は FAIL と書いて GDD 改訂へ回す

### G-3. 実行面の取り違え

- **症状**: Studio MCP で数値を取れる確認を、Computer Use のスクリーンショット目視で済ませる。逆に、GUI でしか触れない設定を Luau で書き換えようとして失敗する
- **なぜ問題か**: 目視は証拠として弱い（後から検算できない）。速度も落ちる
- **検出**: evidence に数値ではなく画像しか無い項目を探す
- **修正型**: §1 の選択順に戻る。**画像は補助であって、判定根拠は数値**

### G-4. `blocked` の過小分類

- **症状**: `blocked-safety`を`[AI-ACTION]`へ分類する、または承認のないLLM送信を`approved-transfer`扱いする
- **なぜ起きるか**: 自律モードの目的が「人間を挟まないこと」だと誤解すると、`blocked` を失敗とみなす圧力が生まれる
- **検出**: `AI_ACTIONS.md`と`HUMAN_ACTIONS.md`を§7の判断順で再判定する
- **修正型**: `blocked-safety`対象を`HUMAN_ACTIONS.md`へ`exec: human-only`として分離する。`blocked-safety`はAI停止理由であり、AI action classではない

### G-5. 「実行できる」を「実行した」と書く

- **症状**: Studio MCP で計測可能だと確認しただけで、実測値のない記録が書かれる
- **関連**: A-4（検証語彙の自己使用）の指示役版。執筆モデルの捏造報告を検査する構造は持っているのに、**自分の報告を同じ基準で検査していない**状態
- **検出**: evidence パスの実在確認。計測記録に生出力が含まれているか
- **修正型**: 記録には必ず生の出力を貼る。要約だけの記録を evidence として採用しない
