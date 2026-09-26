# 検証: Lune のオフライン契約テストと Studio Play の実測

「良さそう」ではなく数値で閉じる。オフラインは速く・全組み合わせを、Studio は本物の物理・複製・体で。

## 目次

1. オフライン（Lune）
2. Studio Play の実測
3. Studio / MCP の罠
4. 見間違えやすい症状と本当の原因

## 1. オフライン（Lune）

Lune（`lune run file.luau`）は Luau と `@lune/roblox` の CFrame / Vector3 を持つ。Roblox の Instance は無いので、**ポーズの計算を純粋関数に保つ**
（Instance を触るのは描画層の外側だけ）と、同じ関数をそのままテストできる。

### モジュールの読み込み

```lua
local fs, luau, rbx = require("@lune/fs"), require("@lune/luau"), require("@lune/roblox")
local env = { CFrame = rbx.CFrame, Vector3 = rbx.Vector3, Enum = rbx.Enum,
	typeof = function(v) return type(v) == "table" and "table" or typeof(v) end } -- 表の関節を Instance と誤認させない
local Kit = luau.load(fs.readFile("src/.../AvatarPoseKit.luau"), { environment = env })()
```

- モジュールが `require(script.Parent.X)` や `game:GetService` を使うなら、environment に `script` / `require` / `game` の代用を入れる。
  描画層（RunService に接続するファイル）をテストしたいときは、`luau.load` を包んで依存（Players、Workspace.Gravity、兄弟モジュール）を注入する小さなヘルパーを作り、
  RunService の接続は捕まえて手で呼ぶ（PreAnimation → PreSimulation を 1 フレームずつ）。
- 計測したリグ: `scripts/studio/dump_rig.luau` の JSON を `{ C0, C1, Part1 = { Size } }` の表にする（`scripts/test_pose_kit.luau` の `rig(scale)`）。
- 実物の track: `scripts/studio/capture_pose.luau` の JSON（毎フレームの Euler XYZ + 位置）を base として流し込み、「live の脚に補正を足しても位相・速度を止めない」を検証する。

### 書く契約（例）

- 接地: 両足を床に置くモードで低い方の足 = 立ったときの高さ ±1e-4。どのモード・どの時刻でも ≥ −1e-4（床の中へ入らない）。
- 連続: 1 フレームの最大回転 ≤ 予算（6° / 60 fps）。遷移の全組み合わせ（A → B、B → A、途中で C）を走らせる。
- 作者の尊重: overlay の外脚 = live ＋ 横切りの回転（差が説明できる範囲）。live の関節は補間で遅れない。
- 物理: 定常旋回の傾き = atan(gain·v·ω/g) ±1°、上限で頭打ち、直進で 0、衝撃のスパイクでも上限内。
- 頑健: NaN・発散なし、dt が 0 / 0.1 超 / 144 fps でも同じ結果、体格 0.8 / 1.0 / 1.3 倍で同じ契約。
- 全身モード（エモート・空中技）で二次運動の重みが 0 へ落ちる。

### 既存テストが落ちたとき

意図した仕様変更（例: 膝を柔らかく、上体の傾きを追加）で古い契約が落ちるのは正常。**黙って閾値を緩めない**:
新しい仕様を契約として書き直し、なぜ変えたか（どの見た目のためか、測った値はいくつか）をコメントに残す。
変更と無関係な契約（例: 脚の角度）は残し、変わった部分（例: 胸の角度）だけを比較から外すなら、その理由も書く。
描画層が新しい依存を require するようになったら、古いテストのハーネスにも注入する（そのために読み込みを 1 か所のヘルパーへ寄せておく）。

## 2. Studio Play の実測

### 場所

- **作業用コピーを専用の Studio で開く**（正本の窓で Play しない・保存しない）。Windows:
  `RobloxStudioBeta.exe -task EditFile -localPlaceFile "<フルパス>"`（`start file.rbxlx` はスタート画面しか開かないことがある）。約 60 秒待って
  MCP の `list_roblox_studios` に出るのを確かめる。
- ゲームのコードと切り離して部品だけ試すなら `scripts/make_test_place.py` の sandbox（平地・坂・階段、既定 Animate + テンプレート）。
- CharacterAutoLoads が false の Place や、試合の準備待ちで自機が出ない Place は、server の execute_luau で `player:LoadCharacter()` して進める。

### 動かし方

- 決まった経路: client の execute_luau で `Humanoid:MoveTo(point)` を順に（MoveToFinished を待つ、8 秒で打ち切り）。平地・坂・階段・円を同じ経路で OFF / ON 比較。
- キー入力（MCP の user_keyboard_input）は **Play のビューポートにフォーカスがあるときだけ**届く。先にビューポートの空いた所をクリックし、速度をサンプラーで確かめる（"Success" を信じない）。
- 再現しにくい動き（特定の半径の旋回、ジャンプの着地、スピン、要素）は、ゲームのソースに**属性で駆動する検証用フック**を一時的に入れる
  （例: LocalPlayer の `LabStyle` / `LabSpeed` / `LabRadius` を見て、複製したマネキンに track とモードを与える）。Studio 専用で、終わったら除去し、
  ソースの指紋（ハッシュ）が元と一致することを確かめてから保存する。
- A/B: レイヤーを属性で OFF / ON できるようにしておく（テンプレートの `Layer.setEnabled`、sandbox の `PoseLayerOff`）。

### 測り方

- 接地: `scripts/studio/contact_probe.luau`（体 × 床 × OFF/ON × モード × 移動/静止ごとに、足ごとの床との差の min / 平均 / max、沈み・浮きのフレーム数）。
  NPC の試合を 60〜90 秒流すと数万フレーム取れる。NPC を client から測るときは HRP が立ち高さ付近・|vY| < 2 のフレームに絞る。
- 跳び: RenderStepped で各関節の Transform を前フレームと比べ、最大回転をモード別に記録する（1 フレームの記録は属性やグローバル表へ）。
- 1 秒未満の出来事（着地の沈み、切替の 1 フレーム）: RenderStep の記録をフレームごとに残し、最悪のフレームの前後 5 フレームを見る。
- 撮影: `RunService:BindToRenderStep(name, Enum.RenderPriority.Last.Value + 5, fn)` でカメラを固定（`CFrame.lookAt(root + offset, root + 高さ)`、FOV 50）。
  screen_capture の camera 引数は Play 中は効かない。キャプチャは呼んでから 0.5〜10 秒遅れて撮られるので、待つ execute_luau の直後に撮る。
  1 秒未満の動きはモジュールに TimeScale 属性を持たせて 1/10〜1/24 に遅くする（ゲームの時計は実時間のまま）。
- エラー: `game:GetService("LogService"):GetLogHistory()` を client と server で読み、自分の変更由来のエラー・警告 0 を確認。
- 後片付け: Play を止める、検証用フックを除去、開いたコピーを保存しない（または保存しても正本と無関係な場所）。

## 3. Studio / MCP の罠

- execute_luau の `require(module)` は**ゲームとは別のモジュールインスタンス**（別のキャッシュ）。ゲームの状態を操作するには属性を書くか、
  ゲームのソースに一時フックを入れる。Edit で require するとソースを書き換える前のキャッシュが返ることがある（Play で確かめる）。
- MCP の実行は sandbox: HttpService なし、VirtualInputManager なし、LocalScript を PlayerScripts 等へ移せない。
  できること: Edit でソース（`.Source`）を書く、属性、`BindToRenderStep`（呼び出し後も残る）、LogService、raycast、Transform の読み取り。
- MCP の呼び出しは直列: 長く待つ execute_luau の後ろで screen_capture が待たされる。
- `_G` は execute_luau の呼び出しをまたいで残る（計測の開始と読み出しを分けられる）。
- ソースを書き換えたらモジュールのキャッシュのため Play をやり直す。

## 4. 見間違えやすい症状と本当の原因（SpinOut で実際に起きたもの）

- **NPC がときどき沈む** → 自機が倒れている間、コントローラが早期 return して他の体の更新を止め、レイヤーが古い体を外して生の track に戻していた。
- **階段・坂で足が 3 stud 浮く** → 計測（またはレイヤー）の ray が段の中から始まり、下の床を拾っていた。ray は root の高さから撃つ。
- **段の縁で足が沈む** → 足の中心の ray が下の段を拾う。つま先とかかとの 2 本で高い方。
- **平地で低い方の足が 0.45 浮く** → 走りの track の flight 区間（両足が浮く）を「作者の浮き」として保っていた。低い方の足を毎フレーム置く。
- **PreRender で書いた補正が効かない** → PreRender の Transform は描画されない。PreSimulation で書く。
- **強い着地で 1 フレームだけ沈む** → Humanoid の圧縮（落下速度に比例して 0.2〜0.5）。描画は物理の前の root で計算されるため、予測の下限を持って ±0.15 まで。
- **Classic では入るのに本番の他プレイヤーで overlay が出ない** → 届くのは track 名だけ。スタイルを動きから推定する。
- **Studio では派生アニメが動くのに本番で元に戻る** → 実行時登録の一時 id は Studio 専用。
