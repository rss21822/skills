---
name: claude-roblox-mvp-buildout
description: 承認済みのRoblox仕様・データ定義・Work Packageから、MVPの通し実装、決定論ビルド、Studioの実機マルチクライアント検証、証跡作成までを行う。**1回の起動で「実際に遊べる状態」まで到達しきる**のが本skillの目的であり、所有者の判断を待って途中で止まらない。値・規則・範囲が未確定なら指示役が暫定決定し`DECISIONS.md`へ記録して続行する。Roblox Studio MCP・Computer Use・内蔵ブラウザ・ローカルシェルで到達できる作業は自律実行し、実測値で自己判定する。ただしpublish・外部配布・push・課金・権限・認証・production書込は自律化しない（MVP完成に不要）。OS入力注入とStudioプロセス終了は操作ごとの所有者明示承認と直前identity再検証を要し、placeのローカル保存だけ恒常許可。実装を委譲する作業実施LLM（Codex CLI / Claudeサブエージェント / Cursor CLI経由のGrok・Kimi・GLM・Gemini / DeepSeek）は所有者が起動時に指定でき、指定が無ければ既定で進めて記録する。ユーザーが「MVPまで作る」「通しで実装して実機検証する」など、完成までの一連の作業を明示的に依頼した場合だけ使う。単発の不具合診断、HUDだけの修正、1つのWork Packageだけの実装には使わない。
---

# Roblox MVP 通し運行

承認済み仕様から、同一性を証明できる「実際に遊べるMVP」を作る。速さより、権限境界、再現性、実測証拠を優先する。

## 00. 最優先原則 — 1回の起動で遊べるMVPまで到達しきる

**この節は本skill内の他のどの記述よりも優先する。** 以降の節や同梱reference、上流ドキュメント（GDD・data definition・WP・test spec）に「所有者が決める」「承認を待つ」「未承認なら未完了」と書かれていても、下記の停止禁止と暫定決定権が上書きする。矛盾を見つけたら本節に従い、矛盾の事実を`DECISIONS.md`へ記録して続行する。

### 00.1 停止禁止

**所有者の判断を待って止まらない。** 1回の起動で、開始→主要操作→決着→終了→次ラウンド成立の全サイクルが**実際に遊べる**状態まで到達させる。

次を理由に止めることを禁じる。止まった時点で本skillは失敗している。

- Tier 0数値・ゲーム規則・balance値が未確定（値なし key、`WITHHELD`、`[OPEN blocking: yes]`）
- MVP範囲の線引き、既知欠陥の受け入れ可否、優先順位
- worker指定が無い、または指定workerが落ちた
- 構造・契約・テストは揃ったが「遊べる実体」が無い
- 上流ドキュメントが「所有者専権」と書いている（**製品判断は §00.2 の暫定決定権で代行する**）

「選択肢を提示して指示を仰ぐ」「どちらにしますか」「承認が要る」で応答を終えない。**判断が必要なら自分で決めて、決めた事実と根拠を記録して、次の作業へ進む。**

### 00.2 暫定決定権 — 決めて、記録して、進む

未確定に当たったら、次の順で処理する。

1. **正本を探す。** canonical文書に値・規則があるならそれを使う。捏造しない。
2. **無ければ暫定決定する。** GDDの意図、既存の型・単位・enum、実測値から矛盾しない最小の値・規則を選ぶ。
3. **`DECISIONS.md`へ記録する。** 決定ID、暫定である旨、採用値・規則、根拠、影響範囲、正式化条件（例: playtest後の所有者承認）、適用範囲（Studioローカル限定など）を書く。
4. **canonical文書へ注記する。** 該当行へ「暫定値（D-NNN）」と併記し、gateは`open`のまま残す。gateを勝手に閉じない。
5. **実装して実測する。** 暫定値でも動作は実測で確認する。値の出所が暫定であることと、実測したことは別問題である。

**暫定値は「創作した製品値」ではない。** 記録され、正式化条件を持ち、gateを閉じない値である。この2つを混同して止まらない。

fail-closedの原則は維持する。暫定値を入れた key は`READY`になるが、**入れていない key は従来どおり fail-closed**であり、そこを推測で埋めない。

### 00.3 「構造が完成した」を完成と呼ばない

契約層・adapter・composition・自動テストが全部PASSしていても、Playして遊べないなら未完成である。過去の実行で、fail-closedを守った結果「テストは全部通るが Workspace が空でRemoteが0個」という状態を完成として報告した失敗がある。繰り返さない。

完成の実測は§7による。最低限、**Playを起動して1ラウンド以上を通し、server権威状態とclient UIの両方から遊べたことを実測**する。

### 00.4 それでも自律化しないもの

停止禁止は**製品判断**に対するものであり、外部影響を持つ操作には及ばない。次は従来どおり所有者専権であり、**いずれもMVP完成には不要**である（これらが無くても§7は満たせる）。

- publish / 外部配布 / push
- 課金・権限（Developer Product、Gamepass、Group権限、Secrets、API key）
- production DataStoreへの書込
- 認証情報の入力、アカウント作成、規約承諾
- 未承認のOS入力注入（place保存を除く。§4.1）、Studioプロセス終了、全画面キャプチャ、デスクトップセッション切替、他者のプロセス操作

これらに突き当たったら、**その1点だけを`HUMAN_ACTIONS.md`へ記録して、残りの作業は止めずに完遂する。** 1点の未実施を理由に全体を止めない。

## 0. 適用範囲

- 明示的に承認された通し実装・ビルド・実機検証にだけ使う。
- 単発診断や1つのWPは `claude-roblox-development-delivery` へ回す。
- **設計文書の骨格（詳細設計・WP・受け入れテスト）が無い**場合だけ `claude-roblox-dev-docs-creator` へ戻す。骨格があって**数値・規則だけが未確定**なら戻さない——§00.2 の暫定決定で埋めて進む。
- 本skillは公開を許可しない。Publish、外部配布、pushは所有者の別承認が必要。**ただしこれらはMVP完成の要件ではない**（§00.4）。

## 1. 先に固定する権限

開始時に、実行IDと次の承認状態を証跡へ記録する。**曖昧なのが「外部影響を持つ操作」（§00.4）なら、その操作だけを止めて他は進める。曖昧なのが「製品判断」なら §00.2 で暫定決定して進む。**run全体を止めない。

- 編集してよいリポジトリ、Worktree、パス、WP。
- OS入力注入、全画面キャプチャ、Studioプロセス終了、強制終了、デスクトップセッション切替、commit、push、publishの各可否。OS入力とStudio終了は包括承認を使わず、今回のrunの当該操作ごとに承認ID・対象・時刻・範囲を記録する。**例外は place のローカル保存（§4.1）だけ**——所有者が2026-08-21に恒常許可した File → ファイルに保存の経路であり、この許可を他のOS入力へ広げない。
- **実施workerの指定**（Codex CLI / Claudeサブエージェント / Cursor CLI経由 / DeepSeek 等）と、その階層。所有者の指定があればそれに従う。**指定が無ければ訊かずに、指示役自身が実施workerとなって進める**（最も強制機構が確実で、送信先も増えない）。この既定採用を証跡へ記録する。階層ごとに強制機構と適用範囲が違い、無人で`workspace-write`を与えてよいのは同梱helper経由のCodex（T1）だけである。判定表と各階層の条件は [委譲契約](references/delegation-contract.md) §0。
- **指定workerが落ちた場合も止まらない。** 疎通失敗（認証切れ・残高不足・model ID廃止）を実測して記録し、**指示役自身の実施へ切り替えて完遂する**。勝手に別の外部workerを代役に立てることだけは禁じる（送信先が変わり承認が引き継がれないため）。
- **指定workerの送信先**へ送信してよいprompt・repository・path範囲、除外するsecret、model、認証channel、account/billing identity。**送信先はworkerごとに違い、承認は引き継がれない**（§0.4）。Windowsの`read-only`/`workspace-write`は書込権限の差であり、同じOS accountで読めるローカルfileの読取・model送信範囲を狭めない。自動委譲は無関係なsecretを持たない専用OS account/VMで行う。共有accountしか使えない場合は、読取可能な全local dataの理論上の開示を所有者が今回明示承認しなければ`BLOCKED`とする。ambient `CODEX_API_KEY`は今回のjobへの所有者承認なしに採用しない（他workerのambient認証情報も同様に扱う）。
- 全画面キャプチャ前は、機密ウィンドウを隠したことと今回の明示同意を確認する。
- `tscon` 等のセッション切替は自動実行しない。必要性だけ報告し、個別承認を待つ。
- 既知欠陥の受け入れ、MVP範囲からの除外、新しいゲーム規則、新しいTier 0数値は、**所有者の指定があればそれに従い、無ければ §00.2 に従って指示役が暫定決定する**。決定は`DECISIONS.md`へ暫定として記録し、正式化条件とgateのopen状態を明記する。**暫定決定を理由にWPを未完了扱いにしない**——未完了にすると§00.1に反して運行が止まるためである。

### 1.1 自律実行の既定 — 人手を待たずに自分で実行する

**実行できる作業を人へ送らない。** Studio MCP・Computer Use・内蔵ブラウザ・ローカルシェルは本セッションに接続されている。これらで到達できる操作は、所有者の手を止めずに自分で実行し、証拠を残し、自分で結果を判定する。

**変えるのは「誰がやるか」だけであり、「何を満たすか」ではない。** §5の証拠要件、§7の完了条件、§2.3の決定論ビルド、§3の依頼側再検査——一つも緩めない。緩めれば「人を外したから通った」だけのMVPになる。人という参照点を外す以上、**代わりの参照点を必ず置く**——実測値、独立照会、SHA-256、PID/role対応表。

#### 自分で実行する

| 面 | 具体 |
|---|---|
| Studio MCP | セッション列挙、`execute_luau`、コンソール取得、権威状態・UI実体の照会、節目テストの駆動 |
| Studio 入力 | `StudioTestService` / `VirtualInput`（§4-1）。OS入力fallbackは**当該操作の所有者明示承認**と直前identity一致を両方満たす場合だけ |
| place 保存 | File → ファイルに保存を Computer Use で実行し、file の bytes / mtime / SHA-256 で成立を実測する（§4.1。恒常許可済み） |
| 画面 | **対象ウィンドウ**のcapture。座標証拠のrefresh |
| プロセス | **自分が起動した**Studioでも、終了操作ごとの所有者明示承認と直前identity一致を両方満たす場合だけ終了・後始末 |
| 内蔵ブラウザ | Creator Docs の参照、Creator Dashboard の**読取**（設定値・place ID・版の確認） |
| ローカル | build / parser / linter / diff / テスト / **今回承認済みの場合だけ**ローカルcommit（所有パスを明示列挙） |

判断も自分で下す。§6の診断ループ、smoke manifestの合否、節目テストのPASS/FAIL、2回buildの一致判定——所有者へ「どうしますか」と投げず、実測して判定し、記録する。**製品判断（値・規則・範囲）も同様に自分で決める**（§00.2）。所有者へ投げてよいのは §00.4 の外部影響操作だけであり、それも当該1点を記録して他は進める。

#### 動かさない線

**次は自律化しない。** 人間専権は`HUMAN_ACTIONS.md`へ`exec: human-only`、AI停止理由`blocked-safety`として記録する。可逆なAI操作の承認待ちは`AI_ACTIONS.md`へ`exec: blocked-permission`として分離する。両者を同じ分類へ潰さない。

- **外部公開** — Publish、外部配布、push（§0で既定。ここでも変えない）
- **課金・権限** — Developer Product / Gamepass の作成・価格変更、Group権限変更、Secrets・API key の設定
- **production データ** — production DataStore への書込
- **認証・契約** — 認証情報の入力、アカウント作成、規約・利用条件の承諾
- **全画面キャプチャ** — 他ウィンドウの内容が写る。対象ウィンドウcaptureで足りるなら常にそちら。全画面が要るなら`blocked-permission`で止めて個別同意を待つ
- **他者のプロセス** — 自分が起動していないStudio、他アプリの終了・最小化
- **未承認のOS入力・Studio終了** — `blocked-permission`。ownership、PID、role/place、foreground、署名等のidentity検査に合格しても承認の代わりにはならない。各操作の個別承認が無ければ実行しない
- **デスクトップセッション切替** — `tscon` 等
- **worker への露出** — 未承認なら`blocked-permission`。指定workerの送信先・path範囲・secret除外を承認後だけ送る（§1、[委譲契約](references/delegation-contract.md) §0.4）。**露出できない場合は指示役自身の実施へ切り替えて進む**

**製品判断（Tier 0数値、ゲーム規則、既知欠陥の受け入れ、MVP範囲）はここに含めない。** §00.2 の暫定決定権で指示役が決め、記録して進む。かつてここに置いていたため「値が無いので止まる」が起き、遊べないMVPを完成と呼ぶ失敗につながった。

**`blocked-safety` が並ぶのは失敗ではない。線を正しく引いた記録である。** ただしこれはAI停止理由でありAI action classではない。**該当しないWPは止めずに進める。1点の`blocked`を理由にrun全体を終えない**（§00.4）。

#### 自律ゆえの固有リスク

実行が速くなると、**「実行できる」と「実行した」を取り違える**圧力が生まれる。Studio MCP で計測可能だと確認しただけで、実測値のない合格を書く型がこれにあたる。

防ぐには、証跡に**生の出力を貼る**。「疎通した」「PASSした」という要約を証拠として採用しない。§5の相関要件（実行ID・テストID・build SHA-256・HEAD・Studio版・timestamp・event ID・PID/role/player対応表）は自律モードでこそ効く——後から誰も口頭で補えないためである。

## 2. 開始ゲート

### 2.1 仕様とGitの基準点

次を取得し、[証跡テンプレート](references/evidence-template.md)へ記録する。

1. 数値所有文書、詳細設計、実装計画、WP、テストIDのパス・版・承認者。
2. `git rev-parse --show-toplevel`、branch、HEAD。
3. `git status --porcelain=v1 -z` の原文保存先と、開始前からある変更の台帳。
4. 今回所有するパスと、凍結するパス。

既存変更を上書き、整形、stageしない。commitが承認されても、所有パスだけを明示列挙してstageする。

### 2.2 能力のプリフライト

副作用を起こす前に、次を読み取り専用で確認する。

- OS、対話デスクトップ、PowerShell版、デスクトップセッションID。
- `RobloxStudioBeta.exe` の正規パスとStudio版。
- Studio MCPの列挙、Luau実行、コンソール取得。
- `StudioTestService` と `UserInputService:CreateVirtualInput()` の利用可否。
- 内蔵ブラウザの疎通（Creator Docs へ到達するか）と、Computer Use の可用性・許可済みアプリ。**自律実行（§1.1）で使う面なので、使えないなら計画側を先に直す**——実測できないまま「実施予定」と書かない。
- Git、pinされたビルダ、Luau parser/linter の版。
- **指定worker候補の疎通**。版が出るだけでは足りない——実際に短い応答を取り、認証切れ・残高不足・model ID廃止を検出する。候補ごとの叩き方は [委譲契約](references/delegation-contract.md) §0。

不足を勝手にインストール、再接続、セッション切替して直さない。利用不能な検証は「未検証」に落とし、**その項目だけを完了範囲から外して残りを完遂する**（§7の末尾に未検証として列挙する）。**worker候補が落ちても外部の代役を勝手に立てない**——落ちた事実と理由を記録し、§1のとおり指示役自身の実施へ切り替えて進む。

同梱security helperは、OS system directoryのMicrosoft署名Windows PowerShell 5.1 exact hostだけを許可する。`PSModulePath`をsystem built-in modulesだけへ固定し、1回のpublic helper invocationごとに別の新しい`-NoProfile -NonInteractive` processを使う。PowerShell 7、portable/copy host、同一processでの2回目呼び出しは副作用前にfail-closedする。

### 2.3 決定論ビルド

ビルダと依存版をpinする。同じHEAD・同じ入力から別の一時パスへ2回ビルドし、SHA-256とサイズが一致することを確認する。不一致なら実機検証へ進まない。

ビルド成功は梱包成功だけを示す。Luau構文、`require`、サーバー/クライアント実行は別に検証する。

## 3. WP運行

各WPを次の順で閉じる。

1. WPの許可パス、凍結領域、正本の数値ID、受け入れテスト、必要ログを固定する。
2. 委譲する場合は [委譲契約](references/delegation-contract.md) を使う。実装者の報告を証拠にしない。
3. 自分で開始前台帳との差分、許可外変更、数値の出所、構造変更を検査する。
4. pinしたparser/linterで静的検査する。
5. 2回ビルドのSHA-256一致を取り直す。
6. 明示したserver/client/sharedのsmoke manifestだけを、使い捨てStudioセッションでtimeout付きロードする。全ModuleScriptの無差別`require`は禁止する。
7. smokeセッションを終了し、新しい受け入れセッションを作る。module cacheや副作用を引き継がない。
8. 節目の実機テストを行い、独立した権威状態照会とクライアントUI照会をログへ対応付ける。
9. D6同期として、コード、テスト、`PROGRESS`、`CHANGELOG`、`Traceability`、影響仕様書を同じWP内で更新し、証跡を保存する。
10. Last Known Goodを確定する。commitは所有者が今回明示承認した場合だけ所有パスを列挙して行う。未承認なら、HEAD、開始前台帳、所有差分、未追跡物、各SHA-256を束縛したimmutable snapshotを保存し、LKG snapshot IDを記録する。

節目は少なくとも、最初の入力→権威状態、最初の複数プレイヤー経路、最終統合の3点とする。

### 3.1 D6 — WP完了時の同期

WPはコードだけでは完了しない。自動テストと必要なStudio検証が合格した同じrevisionで、次を一括して閉じる。

1. コードとテスト。
2. `PROGRESS` と `CHANGELOG`。
3. 要件・WP・テスト・証拠を結ぶ `Traceability`。
4. 実装で具体化または影響を受けた仕様書。
5. 所有者承認済みLKG commit、またはcommit未承認時のimmutable LKG snapshot。

どれかが未同期ならWPを完了扱いにせず、次WPへ進まない。snapshotはcommit許可ではなくrollback基準であり、無断stage・commitを正当化しない。

### 3.2 D7 — 契約競合とChange Request

実装・テスト・Studio実測が承認済み契約と競合したら、**その競合点の扱いを決めるまで**そのWPの当該部分を進めない。コード側で仕様を黙って再定義しない——記録せずに変えることだけが禁止であり、記録して変えるのは§00.2の権限内である。

1. Change Request（CR）を作り、競合、観測事実、選択肢、影響範囲を記録する。
2. **CRの採否を指示役が暫定決定する**（§00.2）。選択した案・根拠・正式化条件を`DECISIONS.md`へ書く。所有者の判断を待たない。
3. 影響する仕様書、WP、テスト、`Traceability`、`PROGRESS`、`CHANGELOG`を列挙して同期する。
4. 影響範囲に対する自己監査（D4相当の再検査）を実行し、結果を証跡へ残す。
5. 同期と再検査が済んだら実装を再開する。**所有者のgate再取得を待って止まらない**——再取得が要る事項は`HUMAN_ACTIONS.md`へ記録し、runは進める。

**例外**: 競合の解消が §00.4 の外部影響操作（publish・課金・production書込・認証）を必要とする場合だけ、その1点を`blocked-safety`として残し、他は完遂する。

## 4. 実機検証

詳細は、実行前に [Studio自動化](references/studio-automation.md) を読む。

入力手段は次の順で選ぶ。

1. 現行Studioで利用可能なら `StudioTestService` と `VirtualInput` を使う。
2. それで対象経路を再現できない場合だけ `scripts/studio_session.ps1 -Action Input` を使う。`studio_input.ps1`を直接呼ばない。**当該入力操作について所有者の個別明示承認を取得・記録した後**、確認済みclient role/place evidenceを直前に再検証する。承認とidentity再検証は独立した必須gateであり、一方を他方の代替にしない。
3. OS入力は、個別承認が有効で、かつ対象PID・開始時刻・実行ファイル・署名・セッション・role/place・exact main HWND・foreground HWNDを送信直前に再照合して一致したときだけ送る。同一PIDのmodalへ送らない。同時操作を検証したことにしない。

Studioプロセスは、`scripts/studio_session.ps1` が候補として獲得し、独立handshake証拠でroleとartifactを確認した所有PIDだけを扱う。終了は、対象PID一覧を示した当該Cleanupへの所有者個別明示承認を取得したうえで、PID・開始時刻・実行ファイル・署名・セッション・role/place・HWND ownershipを送信直前に再検証した場合だけ行う。launch intentや過去の承認だけでrole、place、終了権限を確定しない。他のStudioや他アプリを最小化・終了しない。

Studioのmanifest、handshake、coordinate/capture証拠、test artifactは、repository、Git administration directory、OS TEMPから物理的に分離したowner管理のlocal fixed `TrustedEvidenceRoot`へ置く。全actionへcaller-supplied exact Git root、trusted root、owner-approved signed Studio executable pathを渡す。同じSessionFileのactionはcross-session bounded interprocess lockで直列化し、timeout/abandoned lockは再試行せず停止する。外部副作用前のdurable pending-action journalが残った異常runも、自動再試行せずPID・manifest・outputを手動照合する。role/place evidenceは最大10分、coordinate evidenceはcaptureから最大5分で、期限切れなら新しいimmutable file・event/probeでrefreshする。同じOS userの別writerがStudio installation、同梱script、trusted evidenceを変更できる状態では実行しない。

画面取得は`scripts/studio_session.ps1 -Action Capture`だけを使い、対象ウィンドウを基本とする。low-level capture helperをpath実行しない。全画面は明示同意後だけ使い、仮想スクリーン原点を記録する。画像座標とOS座標を混同しない。

### 4.1 place のローカル保存（File → ファイルに保存）

**運行中に place の保存が必要になったら、Studio の File メニューを Computer Use で操作して保存する。** これはローカルfileへの書込であり、Publish・外部配布ではない。§1の外部公開禁止には当たらない。所有者は本手順を **place のローカル保存に限って** 恒常的に許可している（2026-08-21）。この許可を他のOS入力（gameplay操作、設定変更、ダイアログ応答）へ広げない——それらは従来どおり当該操作ごとの個別明示承認を要する。

保存が要る場面を先に見積もる。**未保存placeはStudio終了で全消失する。** DataModelだけに存在する成果（適用済みmodule、生成したworld、fixture instance）を持ったまま長時間走るrun、Studio再起動を伴う検証、runの区切りでは保存する。

**Studio内部からは保存できない。** `game:Save()` はDataModelに存在せず、MCPの`execute_luau`はpluginコンテキストではないため`plugin`グローバルも無い。実測で両方とも不可を確認済み。よってGUI経路が唯一の手段である。

手順は次の順で、各段の実測値を証跡へ残す。

1. **セッションが対話可能か確認する。** `quser` の `STATE` が `Active` でなければ実行しない。`Disc`（リモート接続切断）では画面自体が存在せず、captureは `desktopCapturer returned no screen sources` で失敗し、入力も届かない。この場合は保存を`blocked-capability`として記録し、所有者へ再接続を依頼する。勝手にセッション切替（`tscon`等）をしない。

   ```powershell
   quser
   Get-Process -Name RobloxStudioBeta | Select-Object Id, SessionId, MainWindowTitle
   ```

2. **等倍screenshotを撮り、そこから座標を読む。** 縮尺付きcaptureの座標系と実座標系は一致しないことがあるため、クリック用の座標は必ず**スケール指定なしのscreenshot**から取る。**固定座標を手順へ焼き込まない**——Studio版、ウィンドウ位置、DPI、言語で毎回変わる。タイトルバーで対象placeのpathを読み、操作対象が意図したwindowであることを確認する。

3. **「ファイル」メニューをクリックし、開いたメニューを screenshot で確認してから「ファイルに保存」をクリックする。** メニュー項目の位置は開いてみるまで確定しない。1回のbatchでメニュークリック→wait→screenshotまで進め、**項目座標は開いた後のscreenshotから取り直す**。英語UIなら `File` → `Save to File`。`Roblox に保存` / `Save to Roblox` は publish 系なので**押さない**（隣接しているため誤クリックに注意）。

4. **保存の成立をファイル側で実測する。** メニューが閉じただけでは証拠にならない。保存先pathの `bytes` / `LastWriteTime` / `SHA-256` を取得し、mtimeが今回の操作時刻であることを確認して証跡へ記録する。

   ```powershell
   $p = '<place path>'
   $f = Get-Item $p
   "bytes: $($f.Length)"; "mtime: $($f.LastWriteTime)"
   "sha256: " + (Get-FileHash -Path $p -Algorithm SHA256).Hash
   "age_seconds: " + [math]::Round(((Get-Date) - $f.LastWriteTime).TotalSeconds, 1)
   ```

5. 初回保存や別名保存でダイアログが出た場合は、path入力と確定も同じ要領（screenshot→座標確定→クリック）で行い、確定後に4を実測する。上書き確認が出たら、対象pathが意図したものであることをscreenshotで確認してから応答する。

失敗時の切り分けは症状で決める。推測で再試行しない。

| 症状（実測文言） | 意味 | 対応 |
|---|---|---|
| `desktopCapturer returned no screen sources` / `Screenshot capture failed` | セッションが`Disc`。画面が無い | `blocked-capability`として記録し再接続を依頼。保存は保留 |
| `blocked by UIPI` | Studioが昇格プロセスで、非昇格のComputer Useから入力が届かない | `blocked-permission`として記録。所有者へ手動`Ctrl+S`を依頼。**Studioの終了・再起動で解決しようとしない**（DataModelが消える） |
| メニューは開くが項目が違う | 座標を使い回した | 開いた状態のscreenshotから取り直す |
| mtimeが更新されない | 保存が実行されていない | 4の実測を根拠に失敗と判定し、2からやり直す。「押したから保存された」と書かない |

**保存できたことを、DataModel復元の代わりにしない。** place保存は利便であり、正本は依然としてrepositoryのsource evidenceと復元手順である。保存の成否にかかわらず、run終了時にはmodule sourceのreadback照合（byte + ClassName）と復元artifactの整合を維持する。

## 5. 証拠の作り方

構造化イベントログだけで合格にしない。各重要な主張を、次の独立した観測と組にする。

- サーバーの権威状態を直接読む。
- 対象クライアントのPlayer/UI実体を直接読む。
- 必要な場合だけ、対象ウィンドウ画像または録画を残す。

すべてを実行ID、テストID、build SHA-256、HEAD、Studio版、timestamp、event ID、PID/role/player対応表で相関させる。エラー0件や棄却0件は、検索範囲と件数を実際に数えた場合だけ証拠にする。

最終検証では、完成ビルドを複製した専用のテストartifactを保持し、可能ならread-only化する。canonical artifactをStudioで直接開かない。起動前後のSHA-256を比較し、変化したartifactの結果は無効にする。

## 6. 予想外の挙動

推測で直さない。

1. 無条件probeを出し、正しいserver/client出力を見ていることを証明する。
2. 症状を実測値とテストIDだけで書く。
3. 走行中セッションの権威状態、入力受理、wire上の値と型、UI実体を読み取る。
4. まだ一意に決まらない値だけ、一時診断ログで測る。
5. 原因が決まってから最小修正し、影響する出口条件を再実測する。

同じ症状で診断→修正→再実測を2巡して値が動かなければ、その修正方針を止める。**そこで所有者へ選択を投げない。** §00.2 に従い、指示役が「範囲除外 / 既知欠陥として受け入れ / 別方針で再挑戦」のいずれかを決め、根拠と影響を`DECISIONS.md`へ記録して**残りの作業を完遂する**。除外・受け入れを選んだ項目は§7の未検証・既知欠陥として列挙する。

既知の候補は [Roblox実行時pitfalls](references/roblox-pitfalls.md) を参照する。各項目を現在版で再現せず、恒久仕様として断定しない。

## 7. 完了条件

次がすべて揃った場合だけ「MVP完成」と言う。**構造・契約・自動テストだけでは完成ではない**（§00.3）。

**遊べることの実測（最優先。ここが欠けたら他が全部揃っても未完成）**

- Playを起動し、プレイヤーが**操作入力を出して**世界が応答している（server権威状態で速度・位置・進行が変化していることを実測）。
- 開始→主要操作→決着→終了→**次ラウンド成立**まで、少なくとも連続2周を通している。
- 決着が canonical path（result確定→報酬/成績→client配信）を通っており、client側UIにも反映されている。
- Playログのエラー件数と入力棄却件数を数え、値を記録している（0なら「検索範囲と件数」も示す）。
- Workspace / Remote / UI が実体として存在する（空のWorkspace、Remote 0個、空のUI rootを「完成」と呼ばない）。

**運行・証跡**

- 承認済み全WPとテストIDが合格している。暫定決定で進めたWPは、暫定である旨と正式化条件を併記したうえで合格として扱う。
- 主要規則を、構造化ログと独立した権威状態/UI照会の両方で確認している。
- 最終2回ビルドが一致し、そのSHA-256と同じ専用artifactを検証した。
- テストartifactの起動前後SHA-256が一致している。
- 実測したエラー件数、棄却件数、再試行回数を記録している。
- 暫定値、運行判断、観察事項、未検証事項、所有者承認を列挙している。
- 各WPでコード、テスト、`PROGRESS`、`CHANGELOG`、`Traceability`、影響仕様書が同じrevisionへ同期している。
- Last Known Goodが、所有者承認済みcommitまたはimmutable snapshot IDとして記録されている。
- 開始前の既存変更を混ぜていない。
- place を保存した場合、その path・bytes・SHA-256・保存時刻を記録している。保存できなかった場合は理由（`blocked-capability` / `blocked-permission`）と、source evidence から復元可能であることを記録している。
- **§00.2 で暫定決定した値・規則を一覧化し、各々の正式化条件と、gateが`open`のままであることを明記している。**
- **`blocked-safety` / `blocked-permission` で残した項目を列挙し、それらがMVP完成の要件でないことを示している**（要件なら未完成である）。

ローカル同一PCの検証だけでは、実端末のタッチ、実ネットワーク、性能、同時入力、公開環境を保証しない。実施していない検証は明示して完了範囲から外す。

**報告の書き方。** 完成報告には「今すぐ遊ぶ手順」（どのplaceを開き、何を押し、何を操作するか）を最初に書く。次に実測値、暫定決定一覧、未検証事項の順で書く。**所有者への質問で報告を終えない**——判断が要ることは既に決めて記録してあるはずである。

## 8. 同梱資材

- [委譲契約](references/delegation-contract.md): worker階層と指定、Codex CLI起動（T1専用）、実装契約、smoke manifest。
- [Studio自動化](references/studio-automation.md): 能力確認、セッションmanifest、入力、捕捉、**place のローカル保存（§6.1）**、後始末。
- [Roblox実行時pitfalls](references/roblox-pitfalls.md): version付き再現候補。
- [証跡テンプレート](references/evidence-template.md): 実行ごとの必須記録。

Claude Codeがこの本文へ展開した絶対path `${CLAUDE_SKILL_DIR}` を覚え、同梱scriptを呼ぶ各shell blockの先頭でshell文法に合うliteralとして `$skillDir` へ再設定する。これは環境変数ではないため、`$env:CLAUDE_SKILL_DIR` を参照しない。supporting referenceには置換されないので、reference中の `$skillDir` は必ずこの展開済み値から設定してから使う。公開起動経路はOS system Windows PowerShell 5.1 exact hostの新しい`-NoProfile -NonInteractive -ExecutionPolicy Bypass` processだけとし、`PSModulePath`をsystem built-in module directoryへ固定する。DryRunとactual、Listと次actionを含め、同梱helperの各invocationを別processへ分ける。profile/function/aliasを持つ既存shellからscriptを直接`&`実行しない。最初に `-DryRun` で引数と実行planを確認し、実操作は必要な個別承認後だけ行う。`-DryRun` がlive targetやgameplayを検証したとはみなさない。
