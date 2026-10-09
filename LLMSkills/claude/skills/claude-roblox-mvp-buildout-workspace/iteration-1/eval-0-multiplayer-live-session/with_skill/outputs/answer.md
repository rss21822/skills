# SpinOut MVP — Studio 4人マルチプレイ実機検証 手順書

対象リポジトリ: `C:\Users\Administrator\Documents\GitHub\SpinOut`
対象ビルド: `artifacts\build\MVP.rbxlx`（`mvp.project.json` / Rojo 7.7.0 pin）
想定人数: 4（`DATA-MATCH-001`）

---

## 0. 先に確認しておくこと（前提のずれを防ぐ）

**この手順が確かめるもの**: 4人が参加した状態で、キー操作がサーバーの権威状態を動かし、試合が「開始 → 攻防 → 得点 → 決着 → 再戦」まで一周するか。判定はすべて**サーバーの構造化ログの実値**で行う。

**この手順が確かめないもの**: 面白さ・操作感・学習曲線。人間参加者の計測（`HA-005`）は代替不可。タッチ操作も対象外（テストセッションでは Device Emulation が無効。`docs/HANDOVER.md` §6 経路 C の実測）。

**既存の証跡との関係**: `docs/evidence/SPINOUT-MVP-WP10.md` には 2026-08-16 の 4P E2E 実測が既に記録されている（最終ビルド sha256 `ED584DBC...`）。今回やるのが「人が実際にキーを触るところを自分の目で見る」ことなら、この手順は**同じ経路の再走**になる。ログの再現を確認する意味はあるが、「未検証だった項目を新たに検証する」わけではない点は最初に握っておく。

**操作の入れ方について（重要）**: Roblox の `UserInputService` / `ContextActionService` は MCP の合成キー入力を受け取らない。SpinOut の操作系は `InputController.luau` で `ContextActionService:BindAction` に載っているので、**MCP の `user_keyboard_input` では一切操作できない**。実操作の再現は OS レベルの入力注入（`studio_input.ps1` / SendInput）で行う。したがって「人が手で触る」か「OS 入力注入」かの二択で、中間は無い。以下は OS 入力注入で組んである。手で触る場合も、観測（§4）と判定表（§5）はそのまま使える。

---

## 1. 使う道具（パスは実在確認済み）

```powershell
$SKILL = "C:\Users\Administrator\.claude\skills\claude-roblox-mvp-buildout\scripts"
$PROJ  = "C:\Users\Administrator\Documents\GitHub\SpinOut"
$ROJO  = "C:\Users\Administrator\tools\rojo\rojo.exe"   # rokit 未導入環境の実体
$SHOT  = "$PROJ\artifacts\recordings"                    # .gitignore 済み。捕捉画像はここへ
```

| 用途 | 手段 |
|---|---|
| 状態の読み取り・世界の問い合わせ | Studio MCP `execute_luau`（`datamodel_type: Server`） |
| ログ回収 | Studio MCP `get_console_output` ＋ `%LOCALAPPDATA%\Roblox\logs\*.log` |
| **プレイヤー操作の再現** | **`studio_input.ps1`（OS 入力注入）** |
| セッション構築（サーバー＋4クライアント） | `studio_session.ps1` |
| メニュー・ダイアログ位置の確認 | `studio_capture.ps1 -FullScreen` |

キー割当（`src/mvp/client/InputController.luau` から確認済み）:

| 操作 | キー | `studio_input.ps1` の書き方 |
|---|---|---|
| 移動 | W / A / S / D | `down:W` … `up:W` |
| 加速（crossover） | Space | `press:SPACE:200` |
| スピン | E | `press:E:150` |
| ブレーキ | LeftShift | `press:SHIFT:300`（vkMap の `SHIFT`=0xA0 が LeftShift） |

`studio_input.ps1` の vkMap に無いキーは**明示エラー**になる。上記4種はすべて表に載っている。

---

## 2. Phase 0 — 疎通確認（ここが通らないなら先へ進まない）

実装が積み上がってから実機が動かないと切り分け不能になるので、必ず最初に3点通す。

**(1) MCP がインスタンスを列挙するか**
MCP ツール `list_roblox_studios` を呼び、対象が返るまで待つ（5秒間隔・最大7回）。返った `studio_id` を以後ほぼ全ツールで使う。

**(2) Luau 実行が返るか**
`execute_luau { code = 'return "ok"', datamodel_type = "Server" }`。Edit 中に `Client` を指定するとエラーになるのは正常。

**(3) OS 入力が届くか**

```powershell
& "$SKILL\studio_input.ps1" -ProcId <任意のStudioPID> -Actions "press:ESC:80"
```

戻り値の **`fg=True` を必ず確認**。`fg=False` の実行結果は「操作した」と扱わない。`fg=False` かつ SendInput が 0 を返すなら入力デスクトップが外れている:

```powershell
tscon 1 /dest:console
```

を実行してから再確認する（リモートセッション経由だと高確率で刺さる。知らずに始めると無反応の原因が分からないまま時間を溶かす）。

---

## 3. Phase 1 — 検証対象ビルドを確定してセッションを立てる

### 3.1 ビルド決定論（Studio を閉じた状態で）

Studio は place を開いている間にファイルへ書き戻す。**再ビルドは必ず Studio を全部閉じてから。**

```powershell
Set-Location $PROJ
git status --short          # dirty なら作業対象と重なっていないか確認
git rev-parse HEAD          # baseline commit を控える

& $ROJO build mvp.project.json --output artifacts\build\MVP.rbxlx
(Get-FileHash artifacts\build\MVP.rbxlx -Algorithm SHA256).Hash    # 1回目

& $ROJO build mvp.project.json --output artifacts\build\MVP.rbxlx
(Get-FileHash artifacts\build\MVP.rbxlx -Algorithm SHA256).Hash    # 2回目
```

2つが一致しなければ生成に時刻や順序が混ざっている。一致しないまま先へ進むと「このビルドで検証した」という主張が成立しない。**一致した sha256 を控える**（これが検証対象の同一性の根拠になる）。

### 3.2 place を開く

```powershell
& "$SKILL\studio_session.ps1" -Action Open -PlacePath "$PROJ\artifacts\build\MVP.rbxlx"
# → opened pid=<editPid> が出る
& "$SKILL\studio_capture.ps1" -FullScreen -OutFile "$SHOT\00_after_open.png"
```

全画面捕捉を必ず見る。**自動復元ダイアログはウィンドウ捕捉に写らない**（前回 Studio を強制終了していると出る）。出ていたら「無視」を**絶対座標クリック**で押す。キーでは閉じない。ダイアログが前面にある間はキーもメニューも一切届かない。

### 3.3 サーバー起動

```powershell
& "$SKILL\studio_session.ps1" -Action Start -EditPid <editPid>
# → server pid=<serverPid>
```

成立判定はプロセス数（`RobloxStudioBeta` が +1）。F7 で立たない場合の疑い順は (a) ダイアログが前面、(b) 3Dビューポートにフォーカスが無い、(c) 入力デスクトップ。それでも駄目ならメニュー経路（`テスト > テストセッションを開始 > サーバーとクライアント`、**プレイヤー数 0 で開始**）へ切り替える。座標は `-FullScreen` でメニューを開いた状態を撮って実測する。

### 3.4 クライアントを4台追加

```powershell
& "$SKILL\studio_session.ps1" -Action AddClients -ServerPid <serverPid> -Clients 4
& "$SKILL\studio_session.ps1" -Action List
```

- 1台ずつ成立を待つ（連続クリックは取りこぼす）。スクリプトが各ラウンドで他ウィンドウを最小化してから送る。前面の奪い合いを放置すると、メニュークリックが**黙って失敗する**。
- 目標プロセス数 = `1(編集) + 1(サーバー) + 4(クライアント) = 6`。
- メニュー既定座標は日本語UI・1280x720 実測値（`テスト`=(246,43)、`クライアントを追加`=(290,290)）。**解像度・言語・Studio 版で変わる**ので、増えなければ `-FullScreen` で実位置を読んで `-TestMenuX/-TestMenuY/-AddClientX/-AddClientY` に渡す。
- `List` の出力で PID とウィンドウを控える。**どれがサーバーでどれがクライアントかはタイトルでなくコンソール内容で判別する**（タイトルは言語で変わる）。

### 3.5 「プロセスが立った」と「ゲームに参加した」は別物

サーバーコンソールで参加を確認する（MCP `get_console_output`、または §4.3 のログファイル）。

```
MVP_FSM_DIAG event=PlayerAdded roster=4 eligible=[-4,-3,-2,-1] phase=WaitingForPlayers
```

`roster=4` が出るまでは操作を始めない。**Studio のテストプレイヤー UserId は負数**（-1〜-4）で正常。

---

## 4. Phase 2 — 操作の入れ方と観測の取り方

### 4.1 操作（1ウィンドウずつ）

OS 入力は**前面ウィンドウにしか届かない**。つまり4人を同時に操作することはできない。1クライアントずつ前面を取って撃ち、次へ移る。

```powershell
# 発進確認（クライアント1）
& "$SKILL\studio_input.ps1" -ProcId <client1Pid> -Actions "click:640:400,wait:400,down:W,wait:2500,up:W"

# スピン攻撃（速度を乗せてから E）
& "$SKILL\studio_input.ps1" -ProcId <client1Pid> `
  -Actions "click:640:400,wait:400,down:W,wait:3000,press:E:150,wait:1200,up:W"
```

守るべき点:

- **操作の前に必ずビューポートをクリックしてフォーカスを取る**。省くと最初のキーが捨てられる。クリック座標はウィンドウ相対。クライアントウィンドウのサイズが違うなら `studio_capture.ps1 -ProcId <pid>` で中身を撮って実座標を決める。
- **`down:` と `up:` を1回の呼び出しの中で閉じる**。キーを保持したまま別ウィンドウを前面にすると、解放が別のウィンドウへ飛ぶ。押しっぱなしのまま迷子になったキーは、症状が「勝手に場外へ出る」形で現れる（WP-10 で実際にこの形の誤診があった）。
- 毎回 `fg=True` を確認する。`fg=False` の実行は結果を採用しない。
- 当たり判定は時間で組む。「W 保持 → 3000ms 後に E」のように書いておくと、同じ結果が繰り返し得られる。距離が合わなければ保持時間だけを補正する。

### 4.2 サーバー状態の読み取り（MCP `execute_luau` / `datamodel_type: Server`）

スポーン配置（`DATA-ARENA-007`: 半径26の円周上に90°間隔）の確認例:

```lua
local Players = game:GetService("Players")
local out = {}
for _, p in Players:GetPlayers() do
    local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
    if hrp then
        local pos = hrp.Position
        table.insert(out, string.format("%s uid=%d pos=(%.1f,%.1f,%.1f) r=%.1f",
            p.Name, p.UserId, pos.X, pos.Y, pos.Z, math.sqrt(pos.X^2 + pos.Z^2)))
    end
end
return table.concat(out, "\n")
```

`r` が4人とも 26 付近で、角度が 90° 間隔に散っていれば配置規則どおり。全員 `(0, 3.2, 0)` に重なるのは WP-10 で潰した既知欠陥の再発を意味する。

### 4.3 クライアント側（HUD）の読み取り

**マルチクライアント中は MCP の `execute_luau { datamodel_type = "Client" }` が「Target is not reachable」になる**（`docs/HANDOVER.md` §6 経路 C の実測）。各クライアントウィンドウのコマンドバーへ入れて **Ctrl+Enter** で実行する。長いコードは手打ちせずクリップボード経由が速い:

```powershell
$code = @'
local gui = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("SpinOutUI")
local hud = gui and gui:FindFirstChild("MatchHUD")
if not hud then return "no MatchHUD" end
local out = {"visible=" .. tostring(hud.Visible)}
for _, c in hud:GetChildren() do
    if c:IsA("TextLabel") then table.insert(out, c.Name .. " = [" .. c.Text .. "]") end
end
return table.concat(out, "\n")
'@
Set-Clipboard -Value $code
& "$SKILL\studio_input.ps1" -ProcId <clientPid> `
  -Actions "click:<コマンドバーX>:<コマンドバーY>,wait:300,down:CTRL,press:V:80,up:CTRL,wait:300,down:CTRL,press:ENTER:80,up:CTRL"
```

読むべきラベルは `Scores` / `Balances` / `RemainingTime` / `Phase` / `LocalInput` / `ResyncWaiting`（`src/mvp/client/UIController.luau`）。決着後は `ResultScreen` の `Winner` / `FinalScores`。画面キャプチャは「何かおかしい」までしか言えないので、値の判定はこのGUIツリー読み取りで行う。

### 4.4 ログの回収

MCP `get_console_output` は起動以降の蓄積を毎回全文返すので**差分は末尾を見る**。長いと truncate されるため、大量ログはファイルから読むほうが確実:

```powershell
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$logs = Get-ChildItem "$env:LOCALAPPDATA\Roblox\logs\*.log" |
        Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-30) }
Select-String -Path $logs.FullName -Encoding utf8 `
  -Pattern "MVP_FSM|MVP_SCORE|MVP_COMBAT|MVP_RESPAWN|MVP_NETWORK|MVP_MOVE server_state"
```

- クライアントごとに別ログが生成される。`*_last.log` を1本だけ読まない。
- `print` は `[FLog::CreatorOutput]`、スクリプトエラーは `[FLog::CreatorError]` と `Stack Begin` で現れる。
- UTF8 指定を忘れると日本語が化ける。

---

## 5. Phase 3 — 試合1周の通し（これが本体）

順に操作を入れ、右列のログ行が**実値で**出ることを確認する。1つでも欠けたら §6 の手順へ。

| # | 操作 / 契機 | 実測すべきログ・値 | 根拠 |
|---|---|---|---|
| 1 | セッション起動 | `MVP_BOOTSTRAP` 各サービス起動が並ぶ | — |
| 2 | 4台参加 | `MVP_FSM_DIAG event=PlayerAdded roster=4 eligible=[-4,-3,-2,-1]` | `DATA-MATCH-001` |
| 3 | 自動開始 | `MVP_FSM ... event=RosterReady guard=eligible=4 result=committed to=Starting` → `StartCommitted ... to=Active` | — |
| 4 | 開始直後の配置 | §4.2 で4名が半径26の円周上・90°間隔 | `DATA-ARENA-007` |
| 5 | ラウンド進行 | round FSM `Dormant→Preparing→InPlay` | — |
| 6 | W 保持 | `MVP_MOVE server_state player=-1 ... speed=` が 0 から上昇（発進する） | `DATA-MOVE-010` 関連 |
| 7 | HUD 実値 | `Phase=[PHASE Active / InPlay]` / `RemainingTime` がカウントダウン / `Balances` が全員 100 | `DATA-DMG-001`, `DATA-MATCH-002` |
| 8 | 速度を乗せて E | `MVP_COMBAT spin_start ... eligible=true speed_ratio=` が 0.33 以上、`speed_after ≈ speed_before × 0.4` | `DATA-SPIN-001`, `DATA-SPIN-002` |
| 9 | 低速で E | `spin_start ... eligible=false speed_ratio=... threshold=0.330`（拒否される） | `DATA-SPIN-001` |
| 10 | スピン後 | `MVP_COMBAT recovery=start ... duration=0.900 input_rule=...` → `recovery=end` | `DATA-SPIN-004/005` |
| 11 | 他プレイヤーへ命中 | `MVP_COMBAT spin_hit source=-1 actor=-3 speed_ratio=... balance_before=100 balance_after=83`。減少量 = `floor(40 × speed_ratio)`、最低10 | `DATA-DMG-002` |
| 12 | 削り切る | `MVP_COMBAT outcome=ko player=-3 state=Eliminated` → `MVP_SCORE data=DATA-MATCH-004 player=-1 score=1` | `DATA-DMG-003`, `DATA-MATCH-004` |
| 13 | 場外へ出す | `MVP_COMBAT outcome=course_out ...` → `MVP_SCORE data=DATA-MATCH-005` | `DATA-MATCH-005` |
| 14 | 復帰 | `MVP_RESPAWN player=-3 state=Respawning wait=3.000 data=DATA-RESPAWN-001` → `state=Alive location=...` | `DATA-RESPAWN-001/002` |
| 15 | 決着（どちらか） | (a) 5点先取で `MVP_SCORE winner=...` → `to=Finished` / (b) 3分で `RegulationExpiredTied → SuddenDeath` | `DATA-MATCH-003`, `DATA-MATCH-002/008` |
| 16 | 残60秒 | `EndgameShrinkDue` committed、playable 半径 64→26 | `DATA-ARENA-004/005/006` |
| 17 | 全クライアント表示 | 4台すべての `ResultScreen.Winner` がサーバーの winner と一致 | `MVP-WP10-E2E-001` Pass 条件 |
| 18 | 再戦 | `Finished → ResetCommitted → WaitingForPlayers` → 接続維持の4名で `RosterReady → Starting → Active`（**2試合目成立**、match identity が更新される） | `MVP-WP10-E2E-001` |

15 で (a) 5点先取まで通すには KO/場外を5回作る必要がある。時間がかかるなら (b) の時間切れ経路でも E2E の決着条件は満たすが、**両方を1回は通しておくと後で悩まない**（得点上限と時間上限は別経路）。

**#17 は4台すべて見る。** 1台だけ見て「表示された」と書くと、E2E の Pass 条件（全 client の表示が server projection と一致）を満たしていない。

---

## 6. 予想と違ったときの手順（当て推量で直さない）

1. **症状を実測値だけで書く。** 「FSM が壊れている」ではなく「roster=4 なのに `to=Starting` が1行も出ない」。推測を症状に混ぜると、その推測を前提に修正されてしまう。
2. **コードだけで根本原因が一意に決まるか、読み取り専用で分析する。** 決まらないなら「決まらない」で止める。
3. **決まらない症状には診断ログを入れる。** 抑制なしで1行、**判定に使った値そのもの**（座標・半径・閾値）を出す。`MVP_COMBAT_DIAG` / `MVP_FSM_DIAG` が既にこの形。
4. **再実測してログの値を読む。**
5. **そこで初めて修正する。** 修正後は §3.1 のビルド決定論からやり直す。

### このプロジェクトで既知の「欠陥ではない挙動」（追いかけない）

- **`Starting` 直後の `rolled_back_effect_failed → StartRejected → WaitingForPlayers` 再試行が3〜4回**出てから `Active` になる。クライアントのキャラクタロード待ちによる起動遅延で、設計どおりの回復経路で自己収束する。ただし**再試行回数はログに残して観察事項として引き渡す**。
- **テストプレイヤーの UserId が負数**（-1〜-4）。`Protocol.playerId()` は「有限な非ゼロ整数」で通す修正済み。`> 0` 前提のコードを新たに書かない。
- **スポーン円周（半径26）＝ endgame shrink 後の境界（26）**。境界含みなので配置直後は場内だが余裕ゼロ。ライブ調整候補として引き渡し済み。
- **W を保持したままリンクを横断すると正当に場外判定される。** 「不可解な course_out」に見えた症状の実体はこれだった。座標と半径を診断ログで見てから判断する。

### 症状別のあたり

| 症状 | まず疑うこと |
|---|---|
| キーが効かない / `fg=False` | 入力デスクトップ（`tscon 1 /dest:console`）→ 前面ダイアログ → ビューポートのフォーカス |
| メニューを押しても何も起きない | `-FullScreen` で実際の展開位置を確認。座標が環境でずれている |
| クライアントが増えない | 前面の奪い合い。他ウィンドウ最小化 → 再試行 → 待ち時間を伸ばす |
| プロセスはあるが参加していない | `roster=` のログを確認。ロード待ちのことがある |
| 操作しても状態が変わらない | サーバー側 `MVP_MOVE client_intent` / `server_state` が出ているか。出ていなければ入力が届いていない（fg を疑う）、出ていれば権威側の処理経路 |
| サーバーは送るがクライアントに出ない | クライアントに一時リスナーを張って**受信生データの型**を見る。Roblox のリモート直列化は**数値キー辞書のキーを文字列へ変換する**（`ReplicationController` の decode 層で吸収済み。ここを壊すと HUD が丸ごと止まる） |

---

## 7. Phase 4 — 後始末と同一性の再確認

```powershell
# 編集ウィンドウだけ残して閉じる
& "$SKILL\studio_session.ps1" -Action Cleanup -KeepPid <editPid>
& "$SKILL\studio_session.ps1" -Action List     # 残骸ゼロを確認
```

- テストセッションのウィンドウを残すと、次回の疎通確認で**別の place を操作してしまう**。
- 編集ウィンドウを強制終了すると次回起動時に自動復元ダイアログが出る。そこまで手順に織り込む。
- **Studio を全部閉じてから再ビルドし、§3.1 で控えた sha256 が再現することを確認する。** Studio は開いている間に place へ書き戻すので、検証前後で sha が変わることがある。再ビルドで元の sha が出れば同一性は証明できる。

---

## 8. 「動作確認できた」と言うために揃っているべきもの

以下が**実測で**揃ったときだけ「4人実機で通った」と書ける。1つでも推定なら、その項目は推定と明記する。

### A. 検証対象の同一性
- [ ] 検証に使ったビルドの sha256（2回ビルド一致）と、対応する commit hash
- [ ] 検証後に再ビルドして同じ sha256 が再現すること
- [ ] `git status --short` で作業樹の状態を記録（dirty なら何が dirty か）

### B. セッションが実在したこと
- [ ] プロセス構成 6（編集1 + サーバー1 + クライアント4）と各 PID
- [ ] サーバーログの `roster=4 eligible=[-4,-3,-2,-1]`（プロセス数だけでは不十分）

### C. 操作が実際に届いたこと
- [ ] `studio_input.ps1` の戻り値が `fg=True`
- [ ] それに対応する `MVP_MOVE client_intent` / `MVP_MOVE server_state speed=` の実ログ（合成入力では届かない経路なので、「届いた証拠」が必要）

### D. 試合の全サイクル（§5 の18項目）
- [ ] 開始（`WaitingForPlayers → Starting → Active`）
- [ ] 主要な遊びの操作（発進・加速・スピン発動・命中・ブレーキ）が**サーバー側の実値**で確認できた
- [ ] 決着条件（5点先取 または 3分＋SuddenDeath）で `Finished` に到達
- [ ] 終了表示が**4クライアントすべて**でサーバーの winner と一致
- [ ] `Finished → ResetCommitted → WaitingForPlayers` から**2試合目が成立**（単発の確認では循環の欠陥が残る）

### E. 数値規則が仕様どおりに効いていること
- [ ] ダメージ = `floor(40 × speed_ratio)`、最低10（`DATA-DMG-002`）がログの数値で一致
- [ ] スピン発動ゲート 0.33（`DATA-SPIN-001`）、速度消費60%（`DATA-SPIN-002`）、リカバリ 0.9s（`DATA-SPIN-004`）
- [ ] リスポーン待ち 3.000s（`DATA-RESPAWN-001`）
- [ ] 残60秒で shrink 64→26（`DATA-ARENA-005/006`）

### F. 証跡
- [ ] `docs/evidence/SPINOUT-MVP-WP10.md`（または新規 evidence ファイル）に、実測ログ行の**実値**・ビルド sha256・実施時刻・PID 構成・Test ID（`MVP-WP10-E2E-001` / `MVP-WP10-DET-001`）の判定を記録
- [ ] **実測していない項目を Pass と書かない**（PROGRESS.md の禁止事項）

### G. 引き渡し（判断が要る項目をまとめて出す）
- [ ] 計測の裏づけが無い暫定値の一覧（データ定義書 0.2.1 の `unvalidated-initial` 群。ダメージ式・スピンゲート・リカバリ時間など、実機で触った所感が付くならそれも添える）
- [ ] 今回の運行判断（DECISIONS へ記録）
- [ ] 観察事項: `StartRejected` 再試行回数、スポーン円周と shrink 境界の余裕ゼロ、その他気づいた仕様判断待ち事項

### H. この確認では言えないこと（明記して引き渡す）
- 面白さ・操作感・学習曲線（人間参加者の計測 `HA-005` は代替不可）
- タッチ操作（テストセッションで Device Emulation 無効）
- 本番環境（正数 UserId、実ネットワーク遅延、実プレイヤー数変動）での挙動
- **Publish は Owner の専権**。ビルドが通っても公開しない

---

## 9. 所要時間と中断ポイント

| Phase | 目安 | 中断していい場所 |
|---|---|---|
| Phase 0 疎通 | 5〜10分 | 通ったら中断可 |
| Phase 1 構築 | 10〜20分（クライアント追加が環境で数十秒ぶれる） | 4台揃ったら中断可（放置するとタイムアウトはしないが、参加者ロードは維持される） |
| Phase 2〜3 通し | 1試合3分 ＋ 操作と観測で 40〜60分 | 各判定項目の区切り |
| Phase 4 後始末 | 5分 | — |

待ちは**固定 sleep にしない**。プロセス数・ウィンドウ・MCP のインスタンス一覧など、成立を判定できる条件でループする（`studio_session.ps1` は既にそうなっている）。Studio の起動とクライアント追加は環境で数十秒ぶれるので、固定待機は短すぎれば取りこぼし、長すぎれば無駄になる。
