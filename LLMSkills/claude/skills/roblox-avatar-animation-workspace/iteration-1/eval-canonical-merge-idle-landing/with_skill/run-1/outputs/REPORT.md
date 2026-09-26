# mini-game: 着地アニメと待機の呼吸の改善（2026-09-26）

（サブエージェントがファイルに書けなかったため、最終メッセージの本文を採点用にここへ保存。本文は要約せず転記。）

作業リポジトリ: `outputs/mini-game/`（入力フォルダのコピー。元は未変更）。commit / push / publish なし。正本 `places/Game.rbxlx` はまだ書き換えていない（取り込みは証明つきの 1 コマンド、3 章）。

## 1. 診断: 着地が「ほとんど効かない」、呼吸が「ロボットっぽい」理由

旧 `src/client/AnimController.client.luau`:
1. `RenderStepped` で `Transform` を書いている — RenderStepped（PreRender）で書いた Transform は描画に反映されない（skill の Studio 実測事実）。Animator の後の `PreSimulation` で書く必要がある。**着地・呼吸ともほぼ見えない主因**（取り込み前の Place での確認手順は 4 章）。
2. 着地で膝を `CFrame.Angles(+35°)` に置き換え — R15 の膝は −X で曲がる。+X は過伸展で逆向き（オフライン計測で足が 0.411 stud 前へ振れる）。股関節・足首・骨盤が動かないのでしゃがんだ形にならない。
3. 1 フレーム目で 0→35°、0.3 s で直線的に戻る — 予備動作なしの 35° の跳び。落下速度に関係なく同じ深さ。
4. 着地の検出が `Landed` 状態だけ・自機だけ — 接地後に始まるので膝が遅れて見える。他プレイヤーには何も掛からない。
5. 呼吸が Waist ±3° の純 sin — 吸う・吐くが 50/50、2 s（src WIP は 2.6 s）で正確に繰り返す。胸以外は動かず頭も一緒に揺れる。
6. 呼吸が全状態で Waist を置き換え — 走り・ジャンプ中も Animator の Waist を上書き。

## 2. 変更内容

経路: 既定の Animate をそのまま残し、その上に手続き的ポーズレイヤー（アセット upload 不要、物理・HumanoidRootPart・入力には触れない）。

スクリプト（`src/client/`）:
- `AnimController.client.luau`（書き換え）: `PreAnimation` で前フレームの Animator 出力へ戻し、`PreSimulation` で書く。全プレイヤーの体を同じ関数で描く。床は足ごとの raycast（1 物理ステップ先を予測）。落下中に接地を予測し、接地の 30 ms 前から吸収を始める。A/B 切替 = LocalPlayer 属性 `LandBreathOff`、体の属性 `PoseMode` は変化時だけ書く。
- `LandBreathPose.luau`（新規）: 着地と待機のポーズ計算（Instance に触らない純関数、Lune で同じコードを検証）。
- `AvatarPoseKit.luau`（新規）: skill の共通部品（接地・二関節 IK・速さの上限）。原本から改行を LF にしただけ。

テスト・ツール: `tests/test_land_breath.luau`、`tests/compile_check.luau`、`tests/rig-r15.json`（計測済み R15 リグ）、`tools/place_layer.py`（正本への証明つき取り込み: build / check / apply / revert）、`tools/studio/verify_land_breath.luau`（Studio Play の実測）。

Place: `places/work/Game.land-breath.rbxlx` = 取り込み候補（正本 + 層、manifest JSON 付き）。

`src/shared/AnimConfig.luau` は 1 バイトも変えていない（チームメイトの未 commit の `IDLE_BREATH_SECONDS = 2.6` をそのまま。sha256 `7ef2f9b9…` が作業前後で同じ）。新コードは既存の 4 キーを毎フレーム読むだけ:
- `LAND_KNEE_DEGREES` = 最も強い着地の膝（`impact = clamp(落下速度/55, 0.35, 1)` 倍）
- `LAND_SECONDS` = 立ち直りの長さの基準（着地全体 = 0.07 s + LAND_SECONDS × (0.7〜1.3、impact 比例)）
- `IDLE_BREATH_SECONDS` = 呼吸の周期
- `IDLE_BREATH_DEGREES` = 吸い切りの胸の持ち上がり（**0→3°**。旧 ±3° から意味が変わる）

着地:
- 接地予測の 30 ms 前から吸収、0.07 s で最深（衝撃なので速さの上限を外す）→ 短く溜めて smootherstep で戻る。
- 空中 0.12 s 未満 or 落下 10 stud/s 未満では発動しない（段差・小さな跳ね）。
- 脚: 膝 −X、股関節は足首が股関節の真下に残る角度（tan h = 脛·sin k /(腿 + 脛·cos k)、実測の腿 1.19 / 脛 0.69 stud）、足首は足底水平、骨盤を必要な分だけ下げて両足を床へ（Humanoid の圧縮で root が沈む分も膝で吸収）。
- 左右差: 骨盤が先行脚側へ最大 3° 傾き、その膝が IK で深くなる。先行脚は着地ごとに左右交互。
- 遅れ: 胸は脚から 35 ms、頭は 60 ms 遅れて追う。腕は外・前へ開き肘が少し緩む。
- 走りながら（3 stud/s 以上）の着地は低い方の足だけ床へ、振り脚は元の動きのまま。

待機:
- 呼吸: 吸気 40 % / 呼気 60 %、周期 ±8 % のゆらぎ、胸が上がり肩が 0.03 stud 上がり腕が少し開く（左右で量を変える）。頭は少し遅れて胸を打ち消し目線を保つ。
- 体重移動（周期 = 呼吸 × 2.47、2.6 s で約 6.4 s）: 骨盤が非荷重側へ 1.3° 落ち、その側の膝が緩む（最大 +7°）。膝は常に 9° ほど緩める。
- 目線（周期 = 呼吸 × 3.83）: 遅いヨーの揺れ。
- 入り 0.35 s、抜け 0.1 s（時定数）。すべて 360°/s の上限内。

## 3. 正本への取り込み方と証明

Studio 保存の Place（手置きマップ）なので Rojo で作り直さない。`tools/place_layer.py` は層だけを差し込む:
- AnimController の Source 差し替え（前提: 正本の Source が作業の元 = `git HEAD` と同じ。違えば停止して 3-way merge を要求）
- `Anim` フォルダに ModuleScript 2 つを追加（referent は既存の最大値の次から）
- 改行はファイルの CRLF に合わせる
- AnimConfig は層に含めない（Place の値は 2 のまま、WIP の 2.6 は持ち込まない）

`python tools/place_layer.py check`（全項目 OK）:
```
OK   canonical unchanged since build (sha256 48be66bccd08af87)
OK   candidate == canonical + layer (rebuilt byte-for-byte, sha256 48628afe97ddcc64)
OK   removing the layer gives back the canonical bytes exactly
OK   every other Item (10, incl. Baseplate / SpawnLocation / Ledge / AnimConfig) identical
OK   only AvatarPoseKit and LandBreathPose were added
OK   AnimController (LocalScript) Source == src/client/AnimController.client.luau
OK   AvatarPoseKit (ModuleScript) Source == src/client/AvatarPoseKit.luau
OK   LandBreathPose (ModuleScript) Source == src/client/LandBreathPose.luau
OK   AnimConfig in the Place keeps its synced value (teammate WIP 2.6 not pushed)
CHECK PASS
```
- 正本 `places/Game.rbxlx` sha256 `48be66bccd08af877102004d3e0e088f53bcffbe2547caeb2cd042d8c854e1e4`（変更なし）
- 候補 `places/work/Game.land-breath.rbxlx` sha256 `48628afe97ddcc64cfa1e5329b8a3187598c106fb62636665823be70842ce092`
- `apply` / `revert` を使い捨てコピーで実行: apply 後の正本 = 候補の sha256、revert 後 = 元の `48be66bc…` と完全一致。バックアップは `places/backup/` に作られる。
- 候補の Place から XML パーサで Script を抽出し、そのコードでオフラインテストを再実行 → compile と契約テストすべて PASS。

## 4. 検証

### オフライン（Lune 0.10.5）
`lune run tests/test_land_breath.luau` → `PASS land-breath checks=124656`（体格 0.8 / 1.0 / 1.3 × 30 / 60 / 144 fps × AnimConfig 2 種（src 2.6 s・Place 2 s））。`tests/compile_check.luau` で 4 ファイル compile OK。

代表値（1.0 倍・60 fps、変更前 → 変更後、基準）:
- 待機: 足の沈み −0.00000 stud（≥ −0.0001）、両足と床の差 0.00009（≤ 0.002）、足の滑り 0.008（≤ 0.03）、1 フレーム最大回転 2.15°（≤ 6°）
- 待機: 吸気の割合 50 % → 40–41 %（33–47 %）、1 周期後の姿勢の差 0°（完全周期）→ 最大 10.6°（≥ 1°）、左右の膝の差 0° → 10.7°（≥ 4°）、頭のピッチ ±3° → ≤ 2.1°（≤ 3°）
- 強い着地（−60 stud/s）: 膝 +35° 過伸展・1 フレームで跳ぶ → −X に最深 45°（開始 0.167 s 後）、長さ 0.3 s（直線）→ 0.43 s、沈み / 両足と床の差 / 滑り: 足が 0.41 stud 前へ → −0.00000 / 0.00000 / 0.016、1 フレーム最大回転 35° → 衝撃区間 19.5°・それ以外 3.4°
- 弱い着地（−18 stud/s）: 35° / 0.3 s（落下速度に無関係）→ 21.6° / 0.32 s
- 走りながらの着地（12 stud/s）: 振り脚は持ち上がったまま、低い足は床から 0.002 以内
- 段差（空中 0.06 s）: 発動しない
- 待機 → 歩き: 0.70 s で元の動きに完全に戻る、最大 2.96°/フレーム

強い着地の膝 45° は LAND_KNEE_DEGREES 35° に Humanoid の圧縮 0.3 stud の吸収が加わった値。圧縮（0.005 × 落下速度、最大 0.4）はテストではモデルとして与えている（実値は Studio で確認が必要）。

### Studio Play の手順（未実行）
1. 正本の窓とは別の Studio で候補を開く: `RobloxStudioBeta.exe -task EditFile -localPlaceFile "<フルパス>\mini-game\places\work\Game.land-breath.rbxlx"`。「変更前」は `places/Game.rbxlx` のバイトコピーを別名で同じ手順。
2. Play → `tools/studio/verify_land_breath.luau` を execute_luau（Client）で 3 回（`PHASE` = "start" → "drive" → "read"）。drive = 待機 8 s、その場ジャンプ 3 回、20 stud からの落下、`LandBreathOff` を OFF にしてもう一度。
3. 合格の目安（`ON|Idle|ground` / `ON|Land|ground` の行）: minGap ≥ −0.02、sink = 0、maxRot/frame ≤ 6（着地の衝撃区間を除く）、maxKnee が OFF より明らかに大きい、waist の幅 およそ 0〜1.8°、errors+warnings = 0。
4. 目視（ゲームカメラの距離）: 着地で膝 → 胸 → 頭の順に沈んで戻る。待機で体重が左右に移り周期が見えない。1 秒未満の着地は RenderStep に固定したカメラで撮って複数フレームを並べる。
5. 他プレイヤーにも掛かることを Team Test か 2 人の Local Server で確認。
6. 終わったら Play を止め、コピーの窓は保存しない。

## 5. ユーザーにお願いしたいこと
1. 4 章の Studio 手順で確認（特に強い着地の実際の圧縮量と、呼吸の量感 `IDLE_BREATH_DEGREES`）。
2. 採用するなら: 正本を開いている Studio を先に閉じる（開いたまま保存すると取り込みが消える）→ `python tools/place_layer.py check` → `python tools/place_layer.py apply`（戻すときは `revert`）。正本がその後変わっていれば apply は止まるので `build` → `check` をやり直す。
3. チームメイトの `IDLE_BREATH_SECONDS = 2.6`（WIP）は src だけ、Place は 2 のまま。新コードは両方の値でテスト済み。Place への同期はチームメイトの判断で。`IDLE_BREATH_DEGREES` の意味が「±値」から「0→値」に変わったことを共有してほしい。
4. commit と publish はオーナーの判断待ち。

## 6. 残る制約
- 既定 Animate の歩き・走りそのものの接地（体格差の沈み・浮き）は依頼の範囲外として触っていない。
- 強い着地の衝撃区間は 1 フレーム最大 19.5° 回る（意図して上限を外す）。
- 描画は物理ステップ前の root で計算するため、Studio では強い着地で 1 フレームだけ ±0.15 stud 程度のずれが残りうる。
- 他プレイヤーの着地は複製された速度から判定するので、ネットワーク遅延のぶん遅れることがある。
- R6 の体には何もしない。
