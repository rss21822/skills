# 報告: R15 剣 3連撃（袈裟斬り → 横薙ぎ → 振りかぶって叩きつけ）＋ヒットストップ

## 何を作ったか

Animate と共存する**手続き的ポーズレイヤー**（Luau、upload 不要でそのまま動く）と、後で upload するための **KeyframeSequence 生成ツール**。関節角とタイミングの仕様は `SPEC.md`。

| ファイル | 置き場所（Place） | 役割 |
|---|---|---|
| `src/shared/SwordCombo/Spec.luau` | ReplicatedStorage.SwordCombo.Spec | 3 撃のキー（角度・時刻・緩急・ヒットストップ・受付/連結）と純粋な sampler |
| `src/shared/SwordCombo/Player.luau` | ReplicatedStorage.SwordCombo.Player | 1 体ぶんの純粋な状態機械: ポーズ時計、ヒットストップ、連撃バッファ、遷移（速度の持ち越し＋360°/s の補正上限）、脚の二関節 IK、歩行時に脚を Animate へ返す |
| `src/shared/SwordCombo/AvatarPoseKit.luau` | ReplicatedStorage.SwordCombo.AvatarPoseKit | スキル同梱のキット（無改変コピー、349 契約 PASS） |
| `src/shared/SwordCombo/Layer.luau` | ReplicatedStorage.SwordCombo.Layer（クライアントで require） | 実行層: PreAnimation で Animator の値へ戻し、PreSimulation で Animator の出力を読んで Player.step の姿勢を書く。自機・他プレイヤー・NPC を同じ関数で描く |
| `src/client/SwordComboClient.client.luau` | StarterPlayerScripts | 入力（Tool.Activated）→ Layer.attack（即時）＋サーバーへ通知 |
| `src/server/SwordComboRelay.server.luau` | ServerScriptService | RemoteEvent を作り、検証（種類・0.12 s の間隔・生存・剣を装備）後に character の `SwordComboSeq` を +1 → 他クライアントが再生 |
| `default.project.json` | — | 上の配置の Rojo 定義（既存プロジェクトに入れるなら該当 3 エントリだけ足す） |
| `tools/solve_arm_keys.luau` | —（オフライン） | 腕のキーを「胸空間の手の位置＋刃の向き」から数値解する作成補助 |
| `tools/BakeSwordComboKeyframes.luau` | —（Studio のコマンドバー、Edit） | 同じ Spec から 3 本の KeyframeSequence（Priority Action、60 fps、マーカー Contact / ChainOpen / Chain）を ServerStorage に作る。upload 用 |
| `tools/studio_measure_combo.luau` | —（Studio Play、Client） | 読み取り専用の実測（関節の 1 フレーム最大回転、踏んでいる足の横滑り、足と床の差、止まっていたフレーム数） |
| `tests/test_sword_combo.luau` | — | Spec / Player / Kit のオフライン契約（486） |
| `tests/test_layer_runtime.luau` | — | Layer の配線（RunService・キャラクタをモック、11 契約） |

### 配線（Animate との共存）

- Animate は置き換えない。コンボが走っていない間、Layer は Transform を 1 つも書かない（テストで確認: 待機 30 フレームで書き込み 0）。
- コンボ中は Animator の後（PreSimulation）に上半身・Root・脚を書く。遷移は描いている姿勢から（入り 0.10 s / 撃間 0.08 s / 戻り 0.28 s + 脚 0.08 s）。終わると Animate の値へ 0.05° 以内で合流してから書くのをやめる。
- 物理・HumanoidRootPart・WalkSpeed・AutoRotate・入力には触れない。ヒットストップは**ポーズ時計だけ**を止める。
- 剣の Tool: 名前 `Sword` か属性 `SwordCombo = true` の Tool を装備して左クリック（Activated）。
- 当たり判定はゲーム側（範囲外）。フックは 3 つ:
  - 自機の予測: `Layer.setHitTest(function(character, strikeIndex) return <当たったか> end)`（接触フレームで呼ばれ、true ならその瞬間に止まる）。
  - サーバー確定: 攻撃者の character の `SwordComboHitSeq` を +1 → 全クライアントで止まる（接触後 0.05 s までに届いた分）。
  - 演出: `Layer.onEvent(function(character, kind, index) ... end)`（kind = strike / contact / hit / exit / done）で SE・VFX・カメラの揺れ。
- NPC: サーバーの AI が NPC の `SwordComboSeq`（当たれば `SwordComboHitSeq`）を +1。クライアントで `Layer.track(npcModel)` を呼ぶ（プレイヤーは `Layer.trackAll()` 済み）。
- プレビュー: workspace 属性 `SwordComboPreviewHits = true` で毎撃ヒット扱い、`SwordComboTimeScale = 0.1` でポーズ時計だけスロー。

### upload（後で）の経路

`tools/BakeSwordComboKeyframes.luau` で KeyframeSequence を作り、ゲームの所有者（ユーザー／グループ）のアカウントで upload。track で再生する場合、ヒットストップは Contact マーカーで `track:AdjustSpeed(0)` → hitStop 秒後に `AdjustSpeed(1)`、連撃は Chain マーカーで次の track を `Play(0.08)`。
`KeyframeSequenceProvider:RegisterKeyframeSequence` などの実行時登録の一時 id は **Studio のプレビュー専用**（本番のサーバーでは再生されない）。本番は upload した asset id を使う。ポーズレイヤーの経路はこの制約を受けない。

## 検証（実行結果）

Lune 0.10.5 で実行（outputs フォルダから）:

```
lune run tests/test_sword_combo.luau      -> PASS sword combo checks=486
lune run tests/test_layer_runtime.luau    -> PASS layer runtime checks=11
lune run <skill>/scripts/test_pose_kit.luau src/shared/SwordCombo/AvatarPoseKit.luau tests/rig-r15.json
                                          -> PASS pose kit checks=349
```

`test_sword_combo` は 0.8 / 1.0 / 1.3 倍 × 30 / 60 / 144 fps で 3 撃を連打（0.1 s ごとに押下）して測る。主な実測値（60 fps・1.0 倍、`--dump` で再現）:

| 項目 | 値 | 合格条件 |
|---|---|---|
| 符号（FK） | Shoulder +X 前 / RightShoulder +Z 外 / **Elbow +X で手が前へ（z −0.305→−0.719）** / Waist −X 前傾 / Neck +X 上 / Root +Y 左 / Root +Z 左傾 | 7 契約すべて成立 |
| イベント順 | strike1, contact1, hit1, strike2, contact2, hit2, strike3, contact3, hit3, exit3, done（全 9 条件で一致） | 完全一致 |
| ヒットストップ（ポーズ時計が止まっていた実時間） | 1撃目 0.0600 s、2撃目 0.0700 s、3撃目 0.1200 s（30/60/144 fps の全条件で ±1e-6 s） | 仕様値 ±1e-6 s |
| ヒットストップ中の動き | 最大 1.20° / 1.26° / 2.98°（= 揺れのみ） | ≤ 揺れ振幅 ×2 |
| 遷移の補正（描画の回転 − 作者の動き） | 最大 6.00°/frame（= 360°/s × 1/60） | ≤ 6°+0.05 |
| Animate との出入りのフレーム | 最大 0.23°（60 fps） | ≤ 360°/s·dt + 0.5° |
| 踏んでいる足 | IK 誤差 7.4e-7 stud、床より下 ≥ −1e-3、横滑り < 2e-3·倍率 stud/frame（床の上にいる連続 2 フレーム） | 全 9 条件 PASS |
| 脚の伸び | 最大 脚長の 0.991 倍 | < 0.999 |
| 刃先と床 | 最低 床上 +0.028 stud（1撃目の振り終わり付近） | > −0.05 |
| 重さ（手の速さ 予備動作 → 振り） | 33.9→96.0 / 21.8→61.0 / 14.7→86.3 stud/s | 振り ≥ 予備 ×2 |
| 軌道 | 1撃目: 手が右上 (0.41, 0.56) → 左下 (−0.74, −1.46)。2撃目: 手が左 (x −0.96) → 右 (+1.44)。3撃目: 両手が頭上 (y 1.01)・刃は頭の後ろ → 正面低く | PASS |
| 歩行中 | 脚は Animate の歩き（差 < 0.5°）、剣の腕は連撃のまま | PASS |
| 入力 | 受付前の連打は捨てる、接触後 0.05 s 以内の確定は即停止、ヒット無しなら止まらない、1 回押しは 1 撃で終わる | PASS |

`test_layer_runtime`（モックの RunService で PreAnimation → Animator → PreSimulation を 1 フレームずつ）: 待機中は書かない、自機の 3 連撃を描いて Animate へ完全に戻る、他の体は `SwordComboSeq` / `SwordComboHitSeq` で再生しヒットストップ 3〜4 フレーム（0.06 s）、自機へのサーバーの反響は二重再生しない、死亡で Animate の姿勢へ戻す — 11 契約 PASS。

検証の途中で見つけて直した不具合:

1. **死亡などで PreSimulation 中に体を外すと、前フレームの Animator の値でこのフレームの値を上書きしていた**（実行層の本物の不具合。PreSimulation からは戻さないよう修正）。
2. 終了時、Root がまだ動いている間に脚を関節空間で混ぜていて、足が最大 0.06 stud/frame 滑っていた（Root が戻り切ってから 0.08 s で残差だけ混ぜるよう修正）。
3. 踏み替えの着地・離地で床すれすれに横移動していた（前後 15% は垂直だけに）。
4. 腕のキーを Euler 角の直感で置いたら、袈裟の溜めで手が背中の下へ入っていた → 胸空間の手の位置・刃の向きから数値解する方式に変更。3撃目は胸の前傾（約 40°）の分だけ刃の目標を起こさないと刃先が床に 1.3 stud 刺さっていた（修正後 床上 0.64）。

**Studio では未検証**（この作業では Studio を使っていない）。以下の手順で確かめること。

## Studio での検証手順

作業は Place のコピー（正本と別の Studio ウィンドウ）で行う。

- **S0 配置**: `rojo build default.project.json -o SwordCombo.rbxlx` で試験用 Place を作るか、既存 Place のコピーに上表の 3 か所を入れる。R15 アバター、Baseplate。StarterPack に Tool（名前 `Sword`、Handle に剣、`RequiresHandle = true`）。
- **S1 符号の確認（最初に 1 回）**: Play → Client の execute_luau で
  `local c = game.Players.LocalPlayer.Character; _G.hold = game:GetService("RunService").PreSimulation:Connect(function() c.RightLowerArm.RightElbow.Transform = CFrame.Angles(math.rad(30), 0, 0) end)`
  → 手が**前**へ出れば Elbow +X = 屈曲（本仕様どおり）。後ろへ出たら全キーの Elbow X の符号を反転（solver も）して報告。確認後 `_G.hold:Disconnect()`。
- **S2 目視**: Play、剣を装備、左クリックを連打。workspace の属性 `SwordComboPreviewHits = true`、`SwordComboTimeScale = 0.1` にして 3 撃の形を横・正面・ゲームカメラ距離の斜め上から撮る（カメラは RenderStep に固定）。見る点: 溜め → 速い振り → 行き過ぎて戻る、接触で止まってわずかに震える、3撃目で左足が踏み込み叩きつけと同時に着く、剣の握り（刃が拳の前）が仮定どおりか。
- **S3 数値**: Client の execute_luau で `tools/studio_measure_combo.luau` の中身を実行 → 連打 → 出力 `[SwordComboMeasure]` を読む。合格の目安: `minSole ≥ −0.02`、`footDrift ≤ 0.01`、剣の腕以外の関節の 1 フレーム最大回転 ≤ 15°（振りそのものは速いので右腕は大きくてよい）、`stillFrames` がヒットストップのフレーム数（60 fps で 1撃目 3〜4、2撃目 4〜5、3撃目 7〜8）と合う。`PreviewHits = false` では止まらないこと。
- **S4 共存**: 歩きながら攻撃 → 脚は歩きのまま上半身だけ連撃。立ち止まって攻撃 → 足が構えへ踏み替え、終わると Animate の待機（剣を持つなら toolnone）へ 1 フレームで跳ばずに戻る。
- **S5 複製**: Test → Clients 2 → 片方で連打、もう片方で相手の体に同じ 3 連撃が出る（遅延分ずれるのは正常）。server の execute_luau で `<相手の character>:SetAttribute("SwordComboHitSeq", <現在値+1>)` を接触前に入れると両クライアントで止まる。
- **S6 エラー**: client / server とも `game:GetService("LogService"):GetLogHistory()` で自分の変更由来のエラー・警告 0。
- **S7 後片付け**: 測定の接続を外す（`_G.SwordComboMeasureStop()`）。開いたコピーは正本へ保存しない。

## 制約・未確定事項（判断が要るもの）

1. **Elbow の符号**: スキル資料（−X で曲げる）と、このリグの FK（+X で曲げる）が食い違う。本実装は FK に従った。S1 で 1 回確認が要る。
2. **刃の向きの仮定**: 刃 = RightHand の −Z。実際の Tool.Grip が違うと刃の向きがずれる（手の位置は合う）。`tools/solve_arm_keys.luau` の目標で解き直せば直る。手首の値が −75〜−82° と大きいのはこの仮定のため（ブロック体では破綻して見えないはずだが S2 で確認）。
3. **横薙ぎの刃先の揺れ**: 2撃目の間 → 振り終わりで、手の高さの変化は 0.59 stud（ほぼ水平）だが、刃先の高さは 2.65 stud 動く（前腕のひねり 69°→24°→81° をキー間で球面補間するため刃が一度起きる）。真横に水平な薙ぎにしたいなら、0.265 s と 0.335 s に solver で解いた中間キーを足す（未実施）。
4. **3撃目の左手**: 柄への添え手は右手首の最終値で解き直したが、解の誤差が最大 0.06 stud 残る。
5. **攻撃中に体が回る・動くと足は世界で滑る**: 足は HumanoidRootPart 空間に固定しているため、攻撃中の旋回（AutoRotate）で足が回る。物理・入力に触れない方針なので、攻撃中の旋回や移動の制限（AutoRotate を切る、WalkSpeed を下げる等）はゲーム側で決めること。歩行中は脚を Animate へ返しているので歩きの見た目は保たれる。
6. **他の画面のヒットストップ**: サーバー確定（`SwordComboHitSeq`）が相手画面の接触後 0.05 s 以内に届かないと、その画面では止まらない（遅れて別の姿勢で止まるより良い、という判断）。ping が大きい相手にも見せたいなら、サーバーが接触前に「当たる」予告を送る設計が要る。
7. **KeyframeSequence 生成ツールは Studio で未実行**（Instance を作るためオフラインで試せない）。マーカーだけの Keyframe を同じ Sequence に足している点も Studio で確認すること。
8. **負荷**: コンボ中の体だけ毎フレーム IK（2 脚 × 二分法 40 回）と表の複製を行う。待機中の体はほぼ 0。12 体以上が同時に連撃する場面は MicroProfiler で測っていない。

commit / push / publish はしていない。
