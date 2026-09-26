# R15 のリグ・符号・アニメーション API

## 目次

1. 関節の階層と式
2. Motor6D と AnimationConstraint
3. 符号表（実測）と確かめ方
4. 体格の違い（計測する理由）
5. AnimationTrack / KeyframeSequence の事実
6. どの経路を選ぶか

## 1. 関節の階層と式

```
HumanoidRootPart --Root--> LowerTorso --Waist--> UpperTorso --Neck--> Head
UpperTorso --LeftShoulder--> LeftUpperArm --LeftElbow--> LeftLowerArm --LeftWrist--> LeftHand   (Right も同じ)
LowerTorso --LeftHip--> LeftUpperLeg --LeftKnee--> LeftLowerLeg --LeftAnkle--> LeftFoot         (Right も同じ)
```

`Part1.CFrame = Part0.CFrame * C0 * Transform * C1:Inverse()`。Animator が毎フレーム `Transform` を書き、C0 / C1 は体格で決まる。
足の位置は Root から Hip → Knee → Ankle を順に掛けて HumanoidRootPart の空間で求める（`Kit.footFrame`）。物理の root は動かさず、描画だけが動く。

R6 は関節名が違う（`RootJoint`、`Left Hip` など空白入り）で脚が 1 パーツ。キットの足の関数は R15 前提（R6 では nil を返す）。R6 は root の縦移動と上体の二次運動だけにする。

## 2. Motor6D と AnimationConstraint

- Server Authority（新しいアバターの物理）の体は、関節が `AnimationConstraint`（Attachment0 / Attachment1 の CFrame が C0 / C1 に相当）。
  Motor6D も残っていることがあるが、Animator が動かすのは AnimationConstraint。**両方あるときは AnimationConstraint を使う**（`Kit.collectJoints`）。
- 式は同じ: `Part1 = Part0 * Attachment0.CFrame * Transform * Attachment1.CFrame:Inverse()`。`Kit.jointData` が両方を同じ形（c0, c1, part1）へ揃える。
- オフラインのテストでは `{ C0, C1, Part1 = { Size } }` の表で代用できる（`scripts/test_pose_kit.luau`）。

## 3. 符号表（Transform の関節ローカル回転。SpinOut の R15 ブロック体で実測）

- Hip: +X 腿を前へ。Y: 左 + / 右 − でつま先が外へ（右脚の +Y はつま先が内）。Z: 左 − / 右 + で脚を横へ開く。
- Knee: −X で曲げる（+X は過伸展。IK は −X 側だけを使う）。
- Ankle: +X つま先を上げる。**hip + knee + ankle = 0 で足底が床に平ら**（脚の角度から足首を決める式）。Y はつま先だけ回す、Z は足を長軸まわりに転がす。
- Waist: −X 前傾。Neck: +X 視線を上げる。
- Shoulder: +X 腕を前へ。Z: 左 − / 右 + で腕を外へ開く。
- Elbow: **+X で肘を曲げる**（腕を下ろした状態で手が前・上へ。計測リグの FK: +30° で手が 0.41 前・0.31 上、−30° は後ろへ = 過伸展）。
  膝と逆向きなのに注意（膝は −X）。UpperArm の Y を捻ると肘の曲がる面が回る（Y −95 のまま Elbow −78 で手が腰の後ろ、−120 で肩甲骨まで、
  +35 で前腕が外へ。これは捻った腕での値で、捻らない腕の曲げ方向ではない）。
- Root（LowerTorso）の roll: +Z で体が**キャラクターの左**へ傾く。Root / Waist / Neck の +Y は左を向く。
- 左右反転: Left と Right の姿勢を入れ替え、位置 (−x, y, z)、Euler XYZ を (rx, −ry, −rz) に。
- KeyframeSequence の Pose.CFrame も同じ慣例（Pose.CFrame が Transform になる）。

直感の符号（右へ傾く = 正、Y = つま先を外）は 2 回外れた。**新しい関節・新しいリグは推測せず確かめる**:
1 軸だけ ±30° にしたホールドポーズを Play 中に置き、横・前・後ろから撮る（Studio のカメラを RenderStep に固定、`references/verification.md`）。
Rthro・他社のリグでも C0 / C1 の向きが違えば符号が変わりうる。

## 4. 体格の違い（計測する理由）

- 既定のブロック体、縮尺（BodyHeightScale など）、Rthro で C0 / C1・パーツ寸法・HipHeight が違う。
  作者のリグで作られた track をそのまま流すと、足が最大 0.5 沈み 0.2 浮く（SpinOut 実測）。
- 接地や IK の数値はすべて**出荷する体を測った値**で決め、テストは 0.8 / 1.0 / 1.3 倍で回す。
- 立ったときの足の最下点（`Kit.neutralLow`）は HipHeight + root 半分の高さとほぼ一致する（実測で 0.15 以内）。床の基準にはこれを使う。
- 計測: `scripts/studio/dump_rig.luau` → JSON（c0, c1, s1 = Part1 の寸法, _hipHeight, _rootSize）。

## 5. AnimationTrack / KeyframeSequence の事実

- 再生: `Animator:LoadAnimation(Animation)` → AnimationTrack。`Priority` は Core < Idle < Movement < Action < Action2 < Action3 < Action4。
  関節ごとに高い Priority が勝ち、同じ Priority は重み（`AdjustWeight`）で混ざる。`Play(fadeTime, weight, speed)`、`AdjustSpeed`、`Looped`、`TimePosition`。
  足音などは `GetMarkerReachedSignal` のマーカーで。
- 複製: 自機の Animator でクライアントが再生した track は他のクライアントへ複製される（名前・重み・時刻）。NPC は通常サーバーで再生する。
  他プレイヤーの体について届くのは「どの track をどの重みで」だけで、コントローラの内部状態（スタイル名）は届かない。
- 所有: 本番で再生されるのは、ゲームの所有者（ユーザーまたはグループ）が持つ（または Roblox 製の）アニメーション asset だけ。
- KeyframeSequence: Keyframe（Time）→ Pose の木（Pose.Name = パーツ名、Pose.CFrame = Transform、Pose ごとに EasingStyle / EasingDirection）。
  コードで組める。upload は Animation Editor / plugin / Open Cloud。
- 実行時の登録（`KeyframeSequenceProvider:RegisterKeyframeSequence`、`AnimationClipProvider:RegisterAnimationClip` の一時 id）は
  **Studio の試験用**として扱う。SpinOut では登録した派生 track が本番で再生されず、元の track に戻った。
- 既存 asset の中身: `KeyframeSequenceProvider:GetKeyframeSequenceAsync(id)` で取得できる（アクセス権のある asset）。複製して変形し、Studio で一時登録してプレビューできる。
- 既定の Animate: キャラクター内の LocalScript `Animate`（StringValue に各 id）。置き換えるなら StarterCharacterScripts に同名の LocalScript を置く。

## 6. どの経路を選ぶか

- upload できない・体格や地面に合わせたい・物理に反応させたい → **ポーズレイヤー**（`references/pose-layer.md`）。
- 作者の細かい動き（エモート、長い演技、表情のある全身の動き）をそのまま流したい・upload できる → **AnimationTrack**。上に接地だけレイヤーで掛ける。
- 両方: 大きな動きは track、接地・二次運動・遷移・overlay はレイヤー。SpinOut の Classic はこの形（購入済み Idle / Run / Jump + ポーズレイヤー）。
- 第三者のアニメーションデータ（他ゲームの keyframe、retarget したモーション）を黙って使わない。購入済み・自作・ユーザーが権利を持つものだけ。
