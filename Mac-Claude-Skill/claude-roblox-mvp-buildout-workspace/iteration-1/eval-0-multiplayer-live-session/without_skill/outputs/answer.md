# SpinOut MVP — Studio 4人マルチプレイ「人が操作する」実機検証手順

対象 repo: `C:\Users\Administrator\Documents\GitHub\SpinOut`
基準 commit: `3966738`（tracked clean で実測）／ビルド成果物: `artifacts\build\MVP.rbxlx`
環境: Windows 11 / Roblox Studio + Studio MCP（`Roblox_Studio`、接続済み）

---

## 0. 先に結論（3行）

1. **4人ちょうど**でないと試合が始まらない実装なので、クライアントは4枚きっかり立てる。多くても少なくても `Starting` に入らない。
2. **人間は1名で足りる**。残り3クライアントは待機のまま「的」として有効。MCP からクライアントへ入力は届かない（実測済み制約）ので、操作は「対象ウィンドウをフォアグラウンドにして自分でキーを叩く」が正道。
3. 決着経路は3本あり、**live 実測済みは1本だけ**（サドンデス経路）。今回の人手 run の最大の価値は、残り2本（5点先取／時間切れリーダーあり）を埋めることにある。

---

## 1. 手順の前提になる、実装から読み取った事実

手順が「なぜこの形になるか」の根拠。すべて HEAD `3966738` のコードと `docs/evidence/**` の実測記録から。

### 1.1 試合成立条件は「ちょうど4人」

`src\mvp\server\MatchService.luau:301`

```lua
local passed = #eligible == Config.match.playerCount and self._deps.arenaReady() and self._deps.requiredDataReady()
```

`Config.match.playerCount = 4`（`src\mvp\shared\Config.luau:52`、DATA-MATCH-001）。等号比較なので **3人でも5人でも `RosterReady` guard が落ちる**。クライアントは必ず4枚。

### 1.2 決着経路は3本。live 実測済みは1本のみ

| 経路 | 遷移 | 条件 | live 実測 |
|---|---|---|---|
| A: 5点先取 | `Active --ScoreTargetReached--> Finished` | 誰かが 5 点（DATA-MATCH-003） | **未実測** |
| B: 時間切れ・単独首位 | `Active --RegulationExpiredWithLeader--> Finished` | 3分経過かつ最高得点が単独（DATA-MATCH-002/008） | **未実測** |
| C: 時間切れ同点 → サドンデス | `Active --RegulationExpiredTied--> SuddenDeath --SuddenDeathPointAwarded--> Finished` | 3分経過・同点 → 次の1点 | **実測済み**（`docs\evidence\SPINOUT-MVP-WP10.md` §3） |

`docs\evidence\SPINOUT-MVP-WP10.md` に記録があるのは `RegulationExpiredTied → SuddenDeath → SuddenDeathPointAwarded → Finished` のみ。A と B は WP-07 で実装・静的確認までで、実機で通した記録がない。**今回の run では B を主目標に置くのが費用対効果が最も高い**（3分で確実に到達でき、未実測経路を1本潰せる）。

### 1.3 操作キー（`src\mvp\client\InputController.luau:310-340`）

| 入力 | キー | 送信フィールド |
|---|---|---|
| 移動・操舵 | `W` `A` `S` `D` | `move` (Vector2) |
| 加速（クロスオーバー） | `Space` | `crossover` |
| スピン（攻撃） | `E` | `spin` |
| ブレーキ | `LeftShift` | `brake` |

**移動はカメラ相対ではなく自機の heading 相対**（`MovementService.luau:257-258` で `right = (-heading.Z, 0, heading.X)`、`desired = right*move.X + heading*move.Y`）。P-A prototype で起きた「カメラとキャラが逆を向く」問題はこの経路には無い。`W` は常に自機の正面へ進む。

### 1.4 得点の作り方（ここを知らないと3分無得点で終わる）

- スピンは **速度比 0.33 以上**でないと発動しない（DATA-SPIN-001、`CombatService.luau` の `spin_start eligible=false` ログで拒否が見える）。最高速 72 studs/s の 33% ≒ **24 studs/s 以上**。実務上は `W` 保持＋`Space` で数秒助走する。
- スピン発動で**速度を60%消費**（DATA-SPIN-002）、その後 **0.9秒の硬直**（DATA-SPIN-004）で全入力無効（DATA-SPIN-005）。連打はできない。
- 命中1回で balance が `floor(40 × 速度比)` 減る（DATA-DMG-002）。WP-10 実測では 1発 17、**6発で KO**（100→83→66→49→32→15→−2）。
- **KO まで殴りきらなくても、1回当ててから場外へ押し出せば得点になる**。`CombatService.luau:448` で被弾者に `lastSourcePlayerId = attackerId` が記録され、`:404` の course_out がそれを得点者に引き継ぐ。**一度も当てていない相手が勝手に場外へ出ても誰にも点は入らない**（`ScoreService.luau` で `scorer == actor` と `sourcePlayerId == nil` を弾く）。
- 結論として、最短の1点は「助走 → `E` を1発当てる → 体当たりで境界外へ押す」。

### 1.5 アリーナと終盤縮小

リンク半径 64、中心半径 26（DATA-ARENA-001/002）。**残り60秒で境界が 64 → 26 へ縮む**（DATA-ARENA-004/005/006）。スポーン円周も半径 26 なので、**縮小後は初期配置の位置がちょうど境界線上**になる（WP-10 特記観察2、Owner レビュー対象）。終盤に棒立ちしていると場外判定に触れる。これは既知で、欠陥ではない。

### 1.6 マルチクライアント環境の実測済み制約（`docs\HANDOVER.md` §6 経路C）

- 起動は **メニューバー「テスト > テストセッションを開始 > サーバーとクライアント」**。Studio CLI の `-task StartServer` は現行版で無効。
- **`execute_luau` は Server のみ到達可。Client は "Target is not reachable"**。したがってクライアント側の状態確認・入力注入を MCP 経由で行うことはできない前提で組む。クライアント側コードは各クライアントウィンドウの**コマンドバーへ貼って Ctrl+Enter**。
- OS レベル入力は複数 Studio ウィンドウで `SetForegroundWindow` が競合する。**対象以外を最小化してから送る**。入力デスクトップ喪失（`GetForegroundWindow()=0`）時は `tscon <id> /dest:console`。
- **テストセッションでは Device Emulation が無効**。タッチ経路はこの手順では検証できない（`docs\evidence\SPINOUT-H-015_3p_touch2p.md` §3）。
- ログはクライアントごとに別ファイル。`*_last.log` 1本だけ読むと取りこぼす。

### 1.7 起動時に必ず出る「正常なノイズ」

WP-10 で2セッション連続再現。`StartCommitted` の effect が数回失敗して `rolled_back_effect_failed → StartRejected → WaitingForPlayers` を 3〜4 回繰り返してから `Active` に入る。クライアントのキャラクターロード待ちが原因と推定されており、**設計どおりの回復経路で自己収束する**。これを見て「壊れている」と判断しない。

---

## 2. 事前準備（所要 10〜15分）

### 2.1 作業樹とビルドを固定する

```powershell
cd C:\Users\Administrator\Documents\GitHub\SpinOut
git status --short          # 何も出ないこと
git rev-parse --short HEAD  # 3966738 を期待

rojo --version              # 7.7.0 であること（rokit.toml pin）
rojo build mvp.project.json --output artifacts\build\MVP.rbxlx
(Get-FileHash artifacts\build\MVP.rbxlx -Algorithm SHA256).Hash
```

同じコマンドをもう一度実行して **sha256 が一致すること**を確認する（決定論ビルド。この repo の慣行）。この hash が「何を動かしたか」の identity になるので必ず控える。

注意: Studio が place を開いている間 `artifacts\build\MVP.rbxlx.lock` が生成される。**Studio を閉じてからビルドする**（開いたままだと上書きに失敗するか、古い place を検証してしまう）。

### 2.2 ログの基準時刻を作る

過去 run のログと混ざるのが一番多い事故。run 開始時刻を控えるだけでよい。

```powershell
$runStart = Get-Date
$runStart.ToString('s')
New-Item -ItemType Directory -Force artifacts\recordings | Out-Null
```

`artifacts\recordings\` は `.gitignore` 済み。生ログと録画はここへ置き、抜粋だけ `docs\evidence\` へ書く。

### 2.3 画面録画（推奨）

「人が操作したところを見た」を後から他人へ示せるのは録画だけ。repo に既存スクリプトがある。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\record_session.ps1 `
  -OutFile artifacts\recordings\live-4p-run1.mp4 -DurationSec 420
```

この環境では gdigrab が使えず ddagrab を使う（実測済み、スクリプト内に記録あり）。420秒＝起動待ち＋3分の regulation ＋サドンデス余裕。

### 2.4 ウィンドウ配置を先に決める

サーバー1枚＋クライアント4枚＝計5ウィンドウ。1画面なら「操作対象のクライアントを最大化、他は最小化」を基本にし、**サーバーウィンドウのコンソールだけは常に見える位置に残す**。MCP でサーバーコンソールを読めるので、サーバーは背面でも構わない。

---

## 3. 4人テストセッションの立ち上げ

### 3-1. place を開く

Studio で `C:\Users\Administrator\Documents\GitHub\SpinOut\artifacts\build\MVP.rbxlx` を開く。

MCP で状態確認:

```
mcp__Roblox_Studio__list_roblox_studios              -> studio_id を取得
mcp__Roblox_Studio__get_studio_state { studio_id }   -> Edit であること、place 名 SpinOutMVP
```

### 3-2. テストセッションを開始（プレイヤー数 0）

メニューバー **「テスト」→「テストセッションを開始」→「サーバーとクライアント」**。**プレイヤー数は 0 で開始する。**

`start_stop_play` は単独 Play 用であり、マルチクライアントの起動には使えない。ここは GUI 操作でしか始まらない（実測済み）。

### 3-3. サーバー起動の健全性を確認（クライアントを足す前に）

```
mcp__Roblox_Studio__get_console_output { studio_id }
```

以下3行が出ていること。出ていなければクライアントを足しても無駄なので、ここで止める。

```
MVP_BOOTSTRAP stage=service_initialization result=ready ingress=disabled
MVP_BOOTSTRAP stage=arena_generation result=ready
MVP_BOOTSTRAP stage=player_participation result=open
```

### 3-4. クライアントを1名ずつ4枚追加

テストメニュー「**クライアントを追加**」を 4 回。**1枚ずつ、前のクライアントのキャラクターがロードされてから次を足す**（同時に足すと 3-6 の StartRejected 再試行が増えるだけ）。

追加のたびにサーバーコンソールへ次が出る:

```
MVP_FSM_DIAG event=PlayerAdded roster=1 eligible=[-1] phase=WaitingForPlayers
...
MVP_FSM_DIAG event=PlayerAdded roster=4 eligible=[-4,-3,-2,-1] phase=WaitingForPlayers
```

Studio のテストプレイヤーは **UserId が負数**（−1〜−4）。これは正常（`Protocol.luau:137` が負数を許容するよう WP-10 で修正済み）。

### 3-5. 試合開始の遷移を確認

```
MVP_FSM phase=match from=WaitingForPlayers event=RosterReady guard=... result=committed to=Starting
MVP_FSM phase=match from=Starting event=StartCommitted guard=... result=committed to=Active
MVP_FSM phase=round from=Dormant ... to=Preparing
MVP_FSM phase=round from=Preparing ... to=InPlay
```

途中に `StartRejected → WaitingForPlayers` が数回混じるのは §1.7 のとおり正常。

`to=Active` が出ない場合は `MVP_FSM_DIAG event=prepareStart stage=... result=failed code=...` を探す。3系統（prepareStart / applyRoundEvent / setRosterOpen）の失敗理由が抑制なしで出るよう WP-10 で計装済み。

### 3-6. スポーン配置を実測（人が動かす前の基準点）

MCP でサーバー側から:

```
mcp__Roblox_Studio__execute_luau { studio_id, datamodel_type: "Server", code: ... }
```

```lua
local out = {}
for _, p in game:GetService("Players"):GetPlayers() do
	local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	table.insert(out, string.format("uid=%d pos=%s", p.UserId, hrp and tostring(hrp.Position) or "nil"))
end
return table.concat(out, "\n")
```

**期待**: 4名が半径 26 の円周上に 90° 間隔（DATA-ARENA-007）。全員が `(0, 3.2, 0)` に重なっていたら WP-10 で修正済みのスポーン欠陥が再発しているので、そこで中断する。

---

## 4. 誰がどのクライアントを操作するか

### 4.1 人間1名で成立する

- 人間が操作するのは **同時に1クライアントだけ**。キーボード入力はフォアグラウンドのウィンドウにしか届かない。
- 残り3クライアントは**待機のままでよい**。roster 4 の条件を満たし、かつスピンの標的として有効。
- 試合中に Alt+Tab でフォーカスを移せば、**同一試合内で操作対象を切り替えられる**。これで「別のクライアントからの入力もサーバーへ届き、得点が正しい player へ帰属する」ところまで1 run で確認できる。

### 4.2 MCP でクライアントを動かそうとしない

`user_keyboard_input` は `datamodel_type` を要求するが、マルチクライアント中は `execute_luau` が Client へ到達できないことが実測済み（`docs\HANDOVER.md` §6 経路C）。同じ経路の `user_keyboard_input` も Client 指定では通らない前提で組む。**今回の目的は「人が操作した」ことの確認なので、そもそも注入で代替してはいけない。**

### 4.3 推奨する役割

| ウィンドウ | 役 | やること |
|---|---|---|
| Server | 観測 | MCP `get_console_output` で遷移・得点・KO を追う |
| Client A（uid −1） | 主操作 | 前半 90秒、人間が操作。得点を作る |
| Client B（uid −2） | 副操作 | 後半 90秒、人間が操作。入力経路の対称性を確認 |
| Client C / D | 待機（的） | 何もしない |

---

## 5. 実操作: 最初から決着まで

`Active` に入った瞬間から regulation の 3 分（DATA-MATCH-002）が走る。**主目標は経路 B（時間切れ・単独首位）**、副目標は経路 A（5点先取）。

### 5-1. 開始直後（0:00〜0:20）: 入力経路の確認

Client A を最大化してフォーカスし、`W` を 2〜3秒保持。

- 初回起動時は `FirstExperienceOverlay`（60秒のチュートリアル表示）が出るが、`phase == Active` になった時点で自動的に消える（`UIController.luau:300`）。残っていれば「スキップ」ボタンで消せる。表示は進行を止めない。
- 画面下の `LocalInput` ラベルが `PC MOVE 0.00,1.00 ACCEL false SPIN false BRAKE false` に変わることを目視。
- サーバーコンソールに `MVP_MOVE server_state player=-1 sequence=... speed=... heading=(...)` が出て、**speed が 0 から増える**こと。

ここで speed が 0 のままなら、`ae4f465` で修正した「静止から発進不能」が再発している。中断して原因を追う。

### 5-2. 助走と初撃（0:20〜1:00）: 1点目を作る

1. `W` 保持＋`Space`（クロスオーバー）で加速。速度比 0.33（≒24 studs/s）を超えるまで数秒。
2. 待機クライアント（C か D）へ正面から接近。
3. 至近距離で `E` を押す。

期待ログ（サーバー）:

```
MVP_COMBAT spin_start player=-1 eligible=true speed_ratio=0.4xx speed_before=... speed_after=... state=Spinning
MVP_COMBAT spin_hit source=-1 actor=-3 speed_ratio=0.4xx balance_before=100 balance_after=83
MVP_COMBAT recovery=start player=-1 duration=0.900 input_rule=全入力無効。滑走慣性のみ継続 state=Recovery
MVP_COMBAT recovery=end player=-1 state=Ready
```

速度不足だと `spin_start player=-1 eligible=false speed_ratio=0.2xx threshold=0.330` が出る。**この拒否ログも1回は見ておく価値がある**（ゲートが効いている証拠）。

4. 当てた相手を、そのまま体当たりでリンク境界（半径 64）の外へ押し出す。

```
MVP_COMBAT_DIAG course_out player=-3 position=(...) transform_position=(...)
MVP_COMBAT outcome=course_out player=-3 state=Eliminated forwarded_to=MatchService
MVP_SCORE data=DATA-MATCH-005 player=-1 score=1 outcome=course_out
MVP_RESPAWN player=-3 state=Respawning wait=3.000 data=DATA-RESPAWN-001
```

押し出しが難しければ、同じ相手へ `E` を計6発当てて KO でもよい（`MVP_SCORE data=DATA-MATCH-004 ... outcome=ko`）。**この時点で 1-0 になり、経路 B の成立条件（単独首位）が確定する。**

### 5-3. 中盤（1:00〜2:00）: 操作クライアントを切り替える

Alt+Tab で **Client B** をフォアグラウンドへ（他は最小化）。同じ手順で B からも 1 点取る。

確認したいのは:

- `MVP_MOVE server_state player=-2` が出る（B の入力もサーバーへ届く）
- `MVP_SCORE ... player=-2` が出る（得点が正しい player へ帰属する）
- **A の HUD 上でも B のスコアが更新される**（snapshot → 全クライアント配信）

得点が 1-1 になると同点なので経路 B は成立しなくなる。**経路 B を狙うなら B での得点は 2 点にして 1-2 の単独首位を作るか、B では得点せず入力到達の確認だけに留める。** どちらを取るか run 前に決めておく。

### 5-4. 終盤（2:00〜3:00）: 縮小と時間切れ

- 残り 60 秒で境界が縮む: `MVP_FSM ... EndgameShrinkDue ... result=committed`。**縮小後の境界半径は 26 で、スポーン円周と同一**。棒立ちの待機クライアントが場外になることがあるが、`sourcePlayerId` が付いていなければ誰にも点は入らない（§1.4）。
- HUD の `RemainingTime` が `TIME 0.0` へ向かって減る。
- 3分到達:

```
MVP_FSM phase=match from=Active event=RegulationExpiredWithLeader guard=... result=committed to=Finished
MVP_SCORE winner=-1 reason=RegulationExpiredWithLeader
MVP_FSM phase=round ... MatchTerminated ... to=Complete
```

**同点で終わった場合**は `RegulationExpiredTied → SuddenDeath` へ入る（実測済み経路）。この場合は誰か1点取るまで終わらないので、Client A で 1 点取って `SuddenDeathPointAwarded → Finished` を出す。

### 5-5. 決着の見え方（クライアント側）

`Finished` かつ winner が確定すると `ResultScreen` が出る（`UIController.luau:_updateResult`）。

- `Winner` = `WINNER P-1` のような表示
- `FinalScores` = `SCORE ...`
- **同時に入力が無効化される**（`self._input:setEnabled(not visible)`）。結果画面が出た後にキーを叩いても動かないのが正しい挙動。
- 「再戦」ボタンは**表示のみで何も送らない**（設計上の意図。リマッチはサーバー自動）。「退出」は自分を Kick する。

### 5-6. リマッチ循環（余力があれば）

放置していると自動で次の試合が始まる:

```
MVP_FSM phase=match from=Finished event=ResetCommitted ... to=WaitingForPlayers
MVP_FSM phase=match from=WaitingForPlayers event=RosterReady ... to=Starting
```

WP-10 で実測済みだが、人が操作した状態からの復帰も見ておくと「1試合で終わる実装ではない」ことが示せる。

---

## 6. 観測と証跡の取り方

### 6.1 サーバー: MCP

```
mcp__Roblox_Studio__get_console_output { studio_id }
```

長いと truncate される。**要所（開始直後・初得点直後・決着直後）で分割して取る**。取りこぼしの正本はログファイル（6.3）。

### 6.2 クライアント: 各ウィンドウのコマンドバー（Ctrl+Enter）

MCP は届かないので手貼り。決着直後に操作したクライアントで実行する。

```lua
local gui = game.Players.LocalPlayer.PlayerGui:WaitForChild("SpinOutUI")
local hud = gui:WaitForChild("MatchHUD")
print("HUD.Visible", hud.Visible)
for _, n in {"Scores", "Balances", "RemainingTime", "Phase", "LocalInput", "ResyncWaiting"} do
	local l = hud:FindFirstChild(n)
	print(n, l and l.Text)
end
local res = gui:FindFirstChild("ResultScreen")
if res then
	print("RESULT.Visible", res.Visible, res.Winner.Text, res.FinalScores.Text)
end
```

GUI パスは `PlayerGui.SpinOutUI.{MatchHUD, ResultScreen, FirstExperienceOverlay, RespawnOverlay}`。

### 6.3 ログファイルからの回収

```powershell
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$since = $runStart.AddMinutes(-2)
$pattern = 'MVP_FSM|MVP_SCORE|MVP_COMBAT|MVP_RESPAWN|MVP_MOVE|MVP_NETWORK|MVP_BOOTSTRAP|MVP_CLIENT|CreatorError|Stack Begin'
Get-ChildItem "$env:LOCALAPPDATA\Roblox\logs\*.log" |
  Where-Object { $_.LastWriteTime -gt $since } |
  ForEach-Object {
    $f = $_.Name
    Select-String -Path $_.FullName -Encoding UTF8 -Pattern $pattern |
      ForEach-Object { "{0}`t{1}" -f $f, $_.Line }
  } | Set-Content -Encoding utf8 artifacts\recordings\live-4p-run1.log.txt
```

注意点（すべて実測済みの落とし穴）:

- **`*_last.log` を1本だけ読まない**。クライアントごとに別ファイルが生成される。
- `Get-Content` / `Select-String` は `-Encoding UTF8` を必ず付ける。既定だと日本語が化ける。
- `print` は `[FLog::CreatorOutput]`、エラーは `[FLog::CreatorError]` と `Stack Begin` として現れる。

---

## 7. 詰まったときの分岐

| 症状 | 見るもの | 対処 |
|---|---|---|
| `to=Starting` に入らない | `MVP_FSM_DIAG event=PlayerAdded roster=N` | N が 4 でなければクライアント枚数の問題。4 なのに落ちるなら `prepareStart` の failed ログを読む |
| `StartRejected` が延々続く | クライアントのキャラクターロード | §1.7。4〜5回までは正常。10回超えるならクライアントを1枚落として再追加 |
| `W` を押しても動かない | `MVP_MOVE server_state ... speed=0.000` が続く | `ae4f465` の発進修正が入っていない。ビルドが古い可能性。sha256 を照合 |
| HUD が更新されない | クライアント側 `MatchHUD` の Text が既定値のまま | `dbc3c50` の wire decode 修正が入っていない。ビルドが古い |
| `MVP_NETWORK ... code=InternalFailure` が毎 tick | snapshot 検証失敗 | `ea8a5bd`（負数 UserId 許容）が入っていない。ビルドが古い |
| フォーカスが移らない | 複数 Studio ウィンドウの競合 | 対象以外を最小化。`GetForegroundWindow()=0` なら `tscon <id> /dest:console` |
| 全員が `(0,3.2,0)` に重なる | `execute_luau` の位置ダンプ | `cc3392f`（DATA-ARENA-007）が入っていない。ビルドが古い |
| キャラが勝手に場外へ | `MVP_COMBAT_DIAG course_out position=` | 座標が半径 64（縮小後 26）超なら正当な判定。実装欠陥ではない |

「ビルドが古い」系が多いので、**§2.1 の sha256 照合を省略しない**。

---

## 8. 「動作確認できた」と言うために揃っているべきもの

以下を**必須**とする。ひとつでも欠けたら「通し確認済み」とは言わない。

### 8.1 必須チェックリスト（11項目）

| # | 確認事項 | 合格条件 | 取得元 |
|---|---|---|---|
| 1 | 何を動かしたかが特定できる | commit `3966738`、tracked clean、`MVP.rbxlx` の sha256 が2回ビルドで一致 | `git status` / `Get-FileHash` |
| 2 | サーバー起動が完走 | `MVP_BOOTSTRAP` の 3 stage が `ready` / `open` | サーバーコンソール |
| 3 | 4人成立 | `MVP_FSM_DIAG event=PlayerAdded roster=4 eligible=[4件]` | サーバーコンソール |
| 4 | 試合開始 | `RosterReady → Starting` と `StartCommitted → Active`、round が `Preparing → InPlay` | サーバーコンソール |
| 5 | スポーン配置 | 4名が半径 26 円周に 90° 間隔（重なっていない） | `execute_luau` 位置ダンプ |
| 6 | **人の入力がサーバーへ届く** | 人が押した `W` に対応する `MVP_MOVE server_state player=<操作した uid> speed>0`。**2つの異なる uid で確認** | サーバーコンソール |
| 7 | **人の操作で戦闘が成立** | `spin_start eligible=true` → `spin_hit source=<操作した uid> actor=<相手>` で balance が減る | サーバーコンソール |
| 8 | **人の操作で得点** | `MVP_SCORE data=DATA-MATCH-004 または 005 player=<操作した uid> score=N` | サーバーコンソール |
| 9 | 復帰系列 | `outcome=ko\|course_out ... state=Eliminated` → `MVP_RESPAWN wait=3.000` → Alive 復帰 | サーバーコンソール |
| 10 | **決着** | `to=Finished` へ至る遷移1本と `MVP_SCORE winner=<uid> reason=<event>` | サーバーコンソール |
| 11 | **人が見える形で結果が出る** | 操作したクライアントで `ResultScreen.Visible=true`、`Winner.Text = WINNER P<uid>`、決着後にキー入力が効かない | クライアントコマンドバー＋目視 |

加えて **異常が出ていないこと**を明示的に確認する（「出なかった」ことも証跡）:

- `MVP_NETWORK ... result=dropped code=InternalFailure` が **0 件**
- `[FLog::CreatorError]` / `Stack Begin` が **0 件**

### 8.2 HUD が生きていることの確認（項目 11 の補強）

`Active` 中に操作クライアントで最低1回ダンプし、次がすべて実値であること:

- `Phase` = `PHASE Active / InPlay`
- `RemainingTime` = `TIME <減っていく数値>`（`TIME --` ではない）
- `Scores` = 4人分、得点後は該当 player の値が増えている
- `Balances` = 初期 100、被弾後に減っている
- `LocalInput` = 押しているキーが反映されている
- `ResyncWaiting` が非表示

### 8.3 望ましい（必須ではないが、あると説得力が段違い）

- **画面録画**（`artifacts\recordings\live-4p-run1.mp4`）。「人が操作したところを見た」を第三者へ示せる唯一の手段。
- 未実測だった決着経路のどちらか（A: `ScoreTargetReached` / B: `RegulationExpiredWithLeader`）を1本埋めること。両方埋まれば決着3経路がすべて live 実測済みになる。
- 決着後のリマッチ循環（`ResetCommitted → WaitingForPlayers → Starting`）を人が操作した状態から確認。
- 操作した人間の所感メモ（操作が意図どおりか、スピンの間合いが取れるか）。これは**証跡ではなく次の設計入力**として別枠で残す。

### 8.4 これが揃っても「言えないこと」

範囲を誤らないために明示しておく。

- **タッチ／モバイル経路**: Studio テストセッションでは Device Emulation が無効（実測済み）。この run では一切カバーされない。
- **実ネットワーク下の挙動**: Studio ローカルサーバーは同一マシン。遅延・パケットロス・帯域は本番と別物。rate limit / retry / resync の実挙動は未確認のまま。
- **同時に4人が本気で操作した場合**: 1名が順に操作する方式では、4人同時入力時の負荷・競合・帰属は確認できない。
- **Publish 後の挙動**: この repo の運行では push / Publish は禁止（`PROGRESS.md` 実行権限）。
- **面白いかどうか**: 通し動作の確認であって、体験評価ではない。FR 判定（`SPINOUT-FEAS`）は人間参加者が必要で、AI 単独では出せない（`HUMAN_ACTIONS.md` HA-005）。

### 8.5 記録の残し方（この repo の作法）

1. 新規証跡ファイル `docs\evidence\SPINOUT-MVP-LIVE4P.md` を作る。フォーマットは `docs\evidence\SPINOUT-MVP-WP10.md` に倣う（対象 / 状態 / 記録者 / 関連テスト / 実測ログ抜粋 / 特記観察）。
2. Test ID を採番して `docs\IMPLEMENTATION_READINESS.md` の Test ID registry へ追加する（例: `MVP-LIVE4P-HUMAN-001` = 人手操作による試合成立から決着まで）。**未実施を Pass と書かない**のがこの repo の明文規則。
3. 生ログ・録画は `artifacts\recordings\`（gitignore 済み）。証跡ファイルには抜粋のみ。
4. `PROGRESS.md` の現在地を更新。
5. commit する（**push は禁止**）。メッセージは PowerShell の引数分割事故を避けるためファイルに書いて `git commit -F <file>`。

---

## 9. タイムライン要約

| 時刻 | 作業 |
|---|---|
| −15分 | ビルド・sha256 二重確認、ログ基準時刻、録画開始 |
| −5分 | place を開く、テストセッション開始（0人）、BOOTSTRAP 3行確認 |
| −3分 | クライアント4枚を1枚ずつ追加、`roster=4` 確認 |
| −1分 | `Active` 到達、スポーン配置ダンプ |
| 0:00 | 人が Client A を操作開始。入力到達確認 |
| 0:20〜1:00 | 助走 → スピン命中 → 場外 or KO で 1 点 |
| 1:00〜2:00 | Client B へ切替、入力到達と帰属を確認 |
| 2:00〜3:00 | 終盤縮小を確認、時間切れ待ち |
| 3:00 | 決着。ResultScreen 確認、HUD ダンプ |
| +5分 | ログ回収、証跡ファイル作成、commit |

正味 **20〜25分**。ビルドから記録まで含めて 40 分程度を見ておけば足りる。
