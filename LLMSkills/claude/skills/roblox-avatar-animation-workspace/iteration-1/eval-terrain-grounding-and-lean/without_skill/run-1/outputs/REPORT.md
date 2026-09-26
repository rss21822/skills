# R15 足の接地 + 旋回リーン (手続きレイヤー) 報告

（サブエージェントがファイルに書けなかったため、最終メッセージの REPORT 本文を採点用にここへ保存。）

## 1. 作ったもの
既定の Animate とアニメはそのまま。Animator が毎フレーム書いた Motor6D.Transform を RunService.PreSimulation で読み、補正を重ねて書き戻すクライアント専用レイヤー。アニメのアップロード不要。

- src/ReplicatedStorage/ProceduralGrounding/init.luau (ModuleScript): 対象登録 (全プレイヤー + NPC 自動検出/タグ)・足下レイ・Transform 読み書き
- src/ReplicatedStorage/ProceduralGrounding/Solver.luau (ModuleScript): 純粋な数学 (CFrame/Vector3 のみ): 脚 IK・骨盤の沈み・足首の面合わせ・旋回リーン
- src/ReplicatedStorage/ProceduralGrounding/Config.luau (ModuleScript): 調整値 (日本語コメント)
- src/StarterPlayer/StarterPlayerScripts/ProceduralGrounding.client.luau (LocalScript): 起動のみ
- default.project.json (Rojo): 配置
- tests/grounding.spec.luau, tests/fixtures/rig-r15.json, tests/last-run.txt (Lune): オフライン検証 32 項目とログ

### 足の接地
原因: Humanoid は HRP を「足元中心の床 + HipHeight」に保つだけなので、坂では前足の下が高くめり込み、階段では HRP が上段に乗って下段の足が浮く。
1. 素のアニメで FK し、各足の かかと・足裏中心・つま先 の真下へ鉛直レイ (6 本/キャラ)。
2. 足裏の傾きは当たった面の法線から (上限 前後35°/左右25°)。階段の踏み面は法線が真上なので足は水平のまま上段に乗り、段の角で折れない。3 点すべてが地面より上になる高さに置く。
3. 届かない足があれば骨盤 (Root) を下げる (上限 1.2)。下げるのは即時、戻すのはゆっくり。HRP が段差で急上昇した分は骨盤で相殺しワールド高さを保つ。
4. 2 ボーン IK (膝は素のアニメの向き、真っ直ぐなら前へ)、足首で面合わせ (振り上げ中の足は合わせない)。
5. 空中・泳ぎ・登り・座り・ラグドール等では約 1/12 秒で素のアニメへ戻る。

### 旋回リーン
横加速度 = 水平速度 × HRP ヨー角速度、傾き = atan(横加速度 / workspace.Gravity)、上限 18°、臨界減衰ばね。支点は足元の地面 (足は IK で残る)。Waist に +25%、Neck でその 60% を打ち消して頭を水平寄りに。速度 4 以下は傾かない、12 で 100%。

### NPC
Transform はレプリケートされないので、各クライアントが自分・他プレイヤー・NPC 全員に同じ処理をかける。既定で workspace 内の R15 Humanoid を自動検出 (ストリームインも DescendantAdded で拾う)。サーバー変更不要。除外は属性 ProceduralGroundingDisabled=true、自動検出を切るなら autoDetectHumanoids=false + タグ ProceduralGrounding。カメラから 120 stud 以内の近い順 24 体まで。寸法は各キャラの実際の C0/C1・HipHeight・足 Size を毎フレーム読むので体格違いにも効く。

## 2. 組み込み
ReplicatedStorage に ModuleScript ProceduralGrounding (init.luau)、その子に Solver と Config。StarterPlayerScripts に LocalScript。Rojo なら default.project.json。Animate は触らない。

## 3. 検証 (オフライン実測)
lune run tests/grounding.spec.luau (outputs フォルダで, Lune 0.10.5) → 32 passed, 0 failed。全 5 ファイル luau.compile OK。
足裏 5 点の地面からの高さ (負=めり込み, 正=浮き):
- 素の立ち姿勢で足裏は床ちょうど (0.000)。脚 = 1.1896 + 0.6935 = 1.8831。平地では素のアニメとの差 最大 0.030°。
- 上り坂25°歩幅: 補正なし L -0.588 / R 0.070 → 補正あり 0.000 / 0.000、骨盤の沈み 0.415
- 下り坂25°歩幅: 0.188 / -0.470 → 0.000 / 0.000、0.438
- 横坂20°立ち: -0.239 / 0.018 → 0.000 / 0.000、0.151
- 上り坂35°立ち: -0.389 / -0.389 → 0.000 / 0.000、0.054
- 段差0.8を横にまたぐ: 0.800 / 0.000 → 0.000 / 0.000、0.800
- 階段0.6/1.2上り: 0.000 / 0.600 → 0.000 / 0.000、0.600
- 階段0.6/1.2下り: 0.600 / -0.600 → 0.000 / 0.000、0.600

旋回 (体 / UpperTorso / 頭 / 足 L/R):
- 歩き6, 3rad/s: 0.82° / 1.02° / 0.41° / 0/0
- 走り16, 3rad/s (物理値13.75°): 13.75° / 17.18° / 6.87° / 0/0
- 走り16, 9rad/s: 17.96° / 22.45° / 8.98° / 0/0
- その場旋回: 0 / 0 / 0

- 左旋回で左、右旋回で右 (±17.18°)。立ち上がり最大 0.93°/フレーム、0.47 s で 90%。
- 膝は常に前 (+0.582)。空中は 35 フレームで完全に素のアニメ (0.0000°)。
- HRP が 0.8 瞬時に跳ねても骨盤・接地足の移動 0.000。
- 体格 1.3 倍・0.8 倍でも 0.000。
- 補正の累積なし (0.00000°)。
- 合成歩行 (足が滑るコンパス歩行) 足裏誤差 p50/p95/max: 上り 0.000/0.002/0.270 (補正なし 0/0.6/0.6)、下り 0.000/0.003/0.491。骨盤の 1 フレーム最大変化 上り 0.638→0.302、下り 0.638→0.563。脚関節の 1 フレーム最大変化は約 90° (非現実的な合成歩行のため。実アニメは Studio で要確認)。

## 4. Studio 確認手順
1. Config.debugAttributes=true で Play → モデル属性 PG_Lean(度)/PG_Drop/PG_Weight を監視。
2. 25° の坂 Part、高さ 0.8 × 奥行 1.2 の階段、Terrain の丘を用意。
3. 坂の上り・下り・横向きで静止 → 足裏が面に沿う。階段で段違いに立つ → 下の足が浮かず PG_Drop ≈ 段差。
4. Client のコマンドバーで各足の 4 隅から下へレイを撃ち、足裏最低点と地面の差を print。目安は静止時 |値| ≤ 0.05。補正なし (ProceduralGroundingDisabled=true) と比較する。
5. 全力で走りながら大きく曲がる → PG_Lean は左で正・右で負・最大±18。その場旋回は 0。
6. R15 NPC (サーバーの Animate 付き) を坂・階段に置いて同様に確認。Test > Clients 2 で他クライアントから自キャラも傾いて見えるか確認。
7. ジャンプで PG_Weight が 0 → 着地で 1。
8. MicroProfiler で 24 体時の処理が約 1 ms 以内か確認。

## 5. 残る制限
- 実アニメ・実物理では未検証。Humanoid の段差上りの HRP 挙動は仮定 (足元 2×1 範囲の最高点)。
- 足の滑り (フットロック) は扱わない。加減速の前後傾きは未実装。シフトロックでカメラを回すと移動方向に関係なく傾く。
- 他クライアントの GetState が不正確な場合に備え、レイが当たらなければ空中扱いにしているが、ジャンプ直後の数フレームは地上扱いになり得る。
- 見た目だけの補正 (当たり判定・移動は不変)。R6 と非標準名のカスタムリグはスキップ。他キャラの上に立つと足は合わない。腕の IK なし。
