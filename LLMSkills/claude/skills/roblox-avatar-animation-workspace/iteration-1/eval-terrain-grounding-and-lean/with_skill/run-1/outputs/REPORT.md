# TerrainPose: 坂・階段の接地と旋回の内傾（既定 Animate の上に重ねる LocalScript）

（サブエージェントがファイルに書けなかったため、最終メッセージの REPORT 本文を採点用にここへ保存。）

## 1. 作ったもの
upload なし・Animate 無改造。Animator が書いた関節の `Transform` を毎フレーム補正するクライアント側ポーズレイヤー。物理・HumanoidRootPart・入力・複製には触らない（見た目だけ）。

- `src/client/TerrainPose/AvatarPoseKit.luau` (ModuleScript): 接地・二関節 IK・速さ制限・二次運動の部品（skill の assets を無改変で複製）
- `src/client/TerrainPose/TerrainPoseCore.luau` (ModuleScript): 1 体 1 フレームの純粋関数（Instance なし）。オフラインテストと本番で同じコード
- `src/client/TerrainPose/TerrainPoseLayer.luau` (ModuleScript): 実行時: 体の追跡（自機・他プレイヤー・R15 NPC）、raycast、PreAnimation / PreSimulation での読み書き
- `src/client/TerrainPose/Boot.client.luau` (LocalScript): `trackAll()` と A/B（LocalPlayer 属性 `TerrainPoseOff`）
- `tests/test_terrain_pose.luau` (Lune): オフライン契約テスト（978 契約）
- `tests/studio/*.luau` (Studio): 接地・傾き・跳びの実測（execute_luau）
- `tools/make_sandbox.py` (Python): 検証用 sandbox Place（平地・22° 坂・1 stud 階段 + 4 スクリプト）

1 フレームの処理（`TerrainPoseCore.step`、PreSimulation = Animator の後）:
1. 二次運動（速度だけから → 自機・NPC・他プレイヤー共通）: 旋回で内傾 `atan(1.4·v·ω/g)`（上限 20°、4→14 stud/s で立ち上げ、その場旋回では傾かない）、ばね 7.5 rad/s・減衰 0.72。軸は踏み足、傾けた後にその足の高さを戻す。頭は付け足した傾きの 55% を打ち消し曲がる先を見る。加速で胸が前（最大 9°）、減速で後ろ（最大 8°）、腕でバランス。
2. 接地: 足ごとにつま先・かかとの 2 本を **root の高さから**真下へ撃ち、高い方に立つ。振り足は速度 × 0.12 s 先の床も持ち上げ量に応じて見る。`Kit.fitFeetToFloor` で各足を自分の床へ（二関節 IK）。骨盤の高さは 70 ms で追従（骨盤の決め手が左右で入れ替わる瞬間に伸びた膝が IK 特異点で 1 フレーム 18〜70° 跳ぶのを計測したため）。
3. 空中・着地: 1 物理ステップ先の床より下へ足を描かない（上げるだけ）。段を下りる瞬間の浮き（床まで 1.3 stud 以内・落下 35 stud/s 未満）も接地扱いで足を伸ばし続ける。
4. 速さの上限: 補正の出入りは「Animate 自身の動き + 360°/s」まで（`Kit.carryLimit`）。
5. 安全網: 踏み足を床の中に描かない（全身の縦移動のみ）。NaN の関節は Animate の値へ戻す。

中断: Climbing / Swimming / Seated / PlatformStanding / Ragdoll / FallingDown / Physics、Core 以外で Action2 以上の track 再生中、キャラクター属性 `TerrainPoseSuspend = true` のとき 0.12 s で Animate に戻す。AnimationConstraint（Server Authority）にも対応。

## 2. ゲームへの組み込み
Rojo の `default.project.json`:
```json
"StarterPlayer": { "$className": "StarterPlayer",
  "StarterPlayerScripts": { "$className": "StarterPlayerScripts",
    "TerrainPose": { "$path": "src/client/TerrainPose" } } }
```
Rojo なしなら StarterPlayerScripts/TerrainPose フォルダに同名で 4 つ置く。
- NPC: Workspace 内の R15 Humanoid モデルは自動で対象（後から出現・StreamingEnabled も拾う）。サーバー側の変更不要。他プレイヤーも自動。
- 負荷: カメラから 200 stud 超は Animate のみ。ray は 1 体あたり 4〜5 本（+ 他の体の接地確認 1 本、空中のみ +1 本）。毎フレームの Instance 生成・属性書き込みなし。
- 調整値: `TerrainPoseCore.SECONDARY`（bankGain 1.4 / bankMax 20° / bankMinSpeed 4 / bankSpeedSpan 10）、`Core.DEFAULTS`（pelvisTau 0.07 s / lookahead 0.12 s / correctionRate 360°/s）。変えたらテストを再実行。

## 3. 検証（実行結果）
- `lune run tests/test_terrain_pose.luau`（outputs で、Lune 0.10.5）→ **`PASS terrain pose checks=978`**（約 50 秒、全文は `tests/last_run.txt`）。キットのテスト（rig-r15.json）も `PASS pose kit checks=349`。
- 前提: Animate は代用品（既定 R15 に近い比率の歩き/走り周期。平地向けに作られている点は本物と同じ）。Humanoid は「root 中心の真下の床 + 立ち高さ」を模擬（段は上りで 0.04 s で持ち上げ、下りは重力で落下）。ray は解析地形を読む。体格 0.8/1.0/1.3 × 30/60/144 fps。測定は描いた足の角 − その足の下の床（つま先・かかとの高い方）。

接地（1.0 倍・60 fps。踏み足 = 低い方の足。sink = −0.05 未満、float = +0.10 超のフレーム数; OFF min / max / sink / float → ON min / max / sink / float）:
- 平地 走り: −0.000 / +0.060 / 0 / 0 → −0.000 / +0.025 / 0 / 0
- 上り坂 歩き: −0.577 / +0.020 / 113 / 0 → −0.062 / +0.005 / 4 / 0
- 上り坂 走り: −0.773 / +0.000 / 148 / 0 → −0.072 / +0.236 / 3 / 46
- 下り坂 歩き: −0.422 / −0.181 / 150 / 0 → −0.023 / +0.048 / 0 / 0
- 下り坂 走り: −0.462 / +0.104 / 128 / 1 → −0.069 / +0.119 / 7 / 10
- 坂を横切る 走り: −0.143 / +0.173 / 77 / 35 → −0.000 / +0.026 / 0 / 0
- 階段上り 走り: −1.126 / +0.025 / 110 / 0 → −0.273 / +1.000 / 8 / 44
- 階段下り 走り: −0.895 / +0.510 / 31 / 42 → −0.880 / +0.726 / 44 / 14

旋回（平地・走り 16 stud/s）: R=5 → 20.00°（上限）、R=8 → 12.86°、R=16 → 6.51°、R=40 → 2.61°（期待値 ±1° を全体格・全 fps で満たす、左右とも内側）。頭は −11.0〜−1.4° 打ち消す。直進・その場旋回 0.000°。傾け中の踏み足 −0.000〜+0.025。
関節の跳び: 全シナリオで上限超過 0.0°（上限を外すと坂 24°・階段 72° 跳ぶのを確認）。ジャンプ: 床下 0.02 未満に入らない。中断: 2.5 s で Animate との差 0.000°。3 体同時 = 1 体ずつ（状態の共有なし）。root の軌跡は ON/OFF で同一。dt = 0・0.25 s のヒッチでも有限で、その後接地に戻る。

## 4. Studio での検証手順
1. `python tools/make_sandbox.py C:\temp\TerrainSandbox.rbxlx` → 正本とは別の Studio で開く: `RobloxStudioBeta.exe -task EditFile -localPlaceFile "C:\temp\TerrainSandbox.rbxlx"`
2. Play → Client で `tests/studio/contact_probe.luau`、続けて `tests/studio/bank_probe.client.luau`（記録開始）。
3. Server で `tests/studio/spawn_npcs.server.luau`（R15 NPC 3 体、90 s）。
4. Client で `tests/studio/drive_route.client.luau`（OFF → ON で坂・階段・R=8 の円 3 周）。
5. 各ファイル末尾の READ 部分を別に実行。合格の目安: contact は坂・平地の ON で minGap ≥ −0.02、sink 0、float ≈ 0。bank は turning の |err|mean < 1.5°、符号 = 旋回方向、OFF は drawn ≈ 0、maxPop は ON が OFF + 6° 以内。NPC の行が自機と同じ傾向。
6. Client / Server とも `LogService:GetLogHistory()` でエラー・警告 0。
7. 目視（坂は横、階段は斜め後ろ、旋回は正面）。sandbox は保存しない。本番 Place でも 2〜6 を繰り返す。

## 5. 残る制約・判断事項
- **階段は未解決に近い（最重要）**: 上りは改善するが踏み足が 1 段ぶん浮くフレームが残る（float 44）。下りは OFF より悪化（走り sink 31 → 44、歩き 43 → 56）。原因は段を下りるたびの Humanoid の浮き・落下に 360°/s の上限と 70 ms の骨盤追従が追いつかないこと。上限を外すと sink は 2 に減るが膝が 40〜70° 跳ぶ。判断は Studio の A/B 実測で。案: (a) 階段区間だけ correctionRate 720°/s、(b) root の縦の急変を描画側で 0.1 s ならす（未検証）、(c) 階段では骨盤を動かさず段差の大きい足だけ IK。
- オフラインの Animate は代用品なので表の OFF 値は本物の基準ではない。本物の変更前の数値は Studio で取る（skill の `capture_pose.luau` で本物の track を取り込める）。
- 走って坂を上ると踏み足が最大 +0.24 浮く。
- 傾きの強さは推定の出発点。実際のカメラで調整。
- 他プレイヤーはネットワーク補間で傾きがやや鈍る見込み（未計測）。
- Rthro・独自リグは `dump_rig.luau` で測った JSON を渡して再テスト（`lune run tests/test_terrain_pose.luau path/to/rig.json`）。
- R6 は対象外（自動で無視）。
- commit / push / publish なし。正本の Place・開いている Studio には触れていない。
