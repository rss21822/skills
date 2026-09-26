---
name: roblox-avatar-animation
description: Robloxのプレイヤーアバター（R15の自機・NPC・他プレイヤー）のアニメーションを制作・洗練する。走り・旋回・ジャンプと着地・攻撃・スピン・よろけ・停止・待機・構え・フィギュア系の要素・エモートを、接地（足が沈まない・浮かない・滑らない）、重さ、予備動作とフォロースルー、物理連動の二次運動（曲がると内へ傾く・加減速で上体・頭の安定）、関節が跳ばない遷移で作る。Luau（Motor6D / AnimationConstraint の Transform を書く手続き的ポーズレイヤー、または KeyframeSequence / AnimationTrack）で実装し、Lune のオフライン計測テストと Studio Play の実測で検証してから、安全に正本へ取り込む。「アニメを良くして」「足が地面に埋まる・浮く・滑る」「動きがロボットっぽい・硬い」「旋回で体を傾けたい」「着地に重さを」「攻撃モーションを作って」「モーションを洗練して」「クロスオーバー」「IK」「Animate スクリプトを置き換えたい」「NPC の動きが変」など、Roblox のキャラクターの動きの見た目に関する依頼では、アニメーションという語が無くても必ずこのスキルを使う。Use it for any Roblox character/avatar animation or pose work in Luau and Studio — not for Blender keyframe/FBX production (use the game-animator agent) and not for gameplay physics or movement tuning.
---

# Roblox アバターアニメーション

Roblox のプレイヤーアバターの動きを「超一流」に仕上げ、**数値で証明して**出荷する。

ゴールは見た目の印象ではなく、測れる品質:

- **接地** — 氷・床・坂の上で刃や足が沈まない（−0.02 stud 以内）、浮かない、踏んでいる足が滑らない。どの体格・どの体（自機・NPC・他プレイヤー）でも。
- **重さと意図** — 予備動作 → 本動作 → フォロースルー、着地の吸収、荷重の移動、非対称の間。
- **物理との連動** — 曲がれば内へ倒れ、加速で前へ、減速で後ろへ。頭は水平を保ち、進む先を見る。
- **途切れない** — モード切替・overlay の出入り・補正の出入りで、関節が 1 フレームで跳ばない（既定 360°/s）。
- **壊さない** — 物理・入力・ゲームプレイには触れない。正本は検証済みのコピーからだけ変える。

失敗は 3 通りある。(1) **目で見て「良さそう」で終わる**: 体格差や遠景で沈み・浮きが残る。(2) **一つの体でしか試さない**: 自機は直っても NPC・他プレイヤーは別経路で描かれている。(3) **作者のアニメーションを壊す**: 補正を足したつもりで、購入済み track の位相や速度を止めてしまう。この手順はその 3 つを防ぐためにある。

## 成果物

1. **現状の計測**（変更前の接地・跳び・エラーの数値）と、動きの**仕様表**（モードごとの角度・秒数・ばね定数と理由）。
2. **実装**: 作業用コピー上の Luau（ポーズレイヤー、ポーズ曲線、必要なら KeyframeSequence）。共通部品は `assets/AvatarPoseKit.luau`。
3. **検証**: Lune のオフライン契約テスト（計測したリグ、複数の体格・フレームレート）と Studio Play の実測（自機・NPC・他プレイヤー、コンソール 0 エラー）。
4. **取り込みと報告**: 採用されたら正本へ証明つきで取り込み、変更前後の数値・残る制約を報告する。commit / push / publish は依頼があるまでしない。

## 手順

### 0. 作業場所を決める（最初に）

正本の Place や開いている Studio の DataModel を直接いじらない。Place のバイトコピーを作り、変更は**差分の層**（差し替えるモジュールだけのフォルダ）として持ち、`build --check` で「コピー = 元 + 層」を再現できるようにする。開いている正本の Studio ウィンドウは保存しない（保存すると取り込みが消える／他の作業を上書きする）。並行セッションが同じツリーを編集している前提で、他人の未 commit の変更は真実として扱う。詳細: `references/integration.md`。

### 1. 現状を読み、測る

コードを書く前に、**誰がどの体をどの経路で動かしているか**を全部書き出す:

- 自機: Animate スクリプトか独自コントローラか。どの track をどの Priority・重みで流すか。
- NPC: サーバーが属性でスタイルを渡すのか、同じコントローラか。
- 他プレイヤー: クライアントに届くのは**相手が再生した track の名前と重みだけ**。独自の状態は届かない（必要なら動きから推定する）。
- 既にポーズを上書きしている層（Transform を書くスクリプト）と、その実行タイミング。

次に Studio Play で**変更前の数値**を取る: `scripts/studio/contact_probe.luau` をモード別に走らせ、接地の min / max・沈んだフレーム数を記録する。関節の跳び（1 フレームの最大回転）も測る。ここが以後の比較の基準になる。

### 2. 経路を選ぶ

- **手続き的ポーズレイヤー**（Transform を毎フレーム書く）: アセットの upload が不要で本番にそのまま出る。体格ごとに接地を合わせられ、物理に反応できる。購入済み track の上に「補正・overlay」として重ねるのが基本形。
- **AnimationTrack（KeyframeSequence を upload）**: 作者の動きをそのまま流す。upload した asset はゲームの所有者（ユーザー／グループ）が持っていないと本番で再生されない。実行時に KeyframeSequence を登録する方法（`AnimationClipProvider:RegisterAnimationClip` 等）は **Studio でしか動かない**前提で扱う（本番では元の track に戻る）。
- **併用**が最も多い: track で大きな動き、レイヤーで接地・二次運動・遷移を整える。

判断材料と API の詳細: `references/r15-rig.md`。

### 3. リグと動きを計測する

- `scripts/studio/dump_rig.luau` で**実際に出荷する体**（ブロック体の既定アバター、縮尺違い、Rthro）の関節（C0 / C1 / パーツ寸法 / HipHeight）を JSON に落とす。接地の数値はすべてこれに依存する。
- 重ねる相手の track は `scripts/studio/capture_pose.luau` で毎フレームの Transform を採る（例: 旋回 track 130 フレーム）。オフラインで「live の脚に補正を足しても位相を止めない」を検証する材料になる。
- 符号を推測しない。新しい関節は**単軸のホールドポーズ**（1 軸だけ ±30° 回して見る）で向きを確かめてから組む。既知の符号表: `references/r15-rig.md`。

### 4. 動きを設計する

モードごとに仕様表を作る: 何を見せるか（バイオメカニクス上の理由）、関節角（計測した符号で度）、秒数、ばね（固有角振動数・減衰比）、入り・抜けの長さ、他のモードとの優先順位。品質の基準と作例の数値は `references/quality-bar.md`。難しい動き（クロスオーバー、スピン、着地）は、別の推論エージェント／モデルに同じブリーフ（現状のコード・符号表・制約）を渡して並行に案を出させ、数値の根拠を比べるとよい。ブリーフには「物理・入力を変えない」「upload しない」「第三者のアニメーションデータを使わない」を明記する。

### 5. 実装する

ポーズレイヤーは `assets/PoseLayerTemplate.luau`（骨組み）と `assets/AvatarPoseKit.luau`（部品）をコピーして始める。フレーム順と理由は `references/pose-layer.md`。要点:

- **関節は `Motor6D` と `AnimationConstraint` の両方を探す**（`Kit.collectJoints`）。Server Authority のアバターは Motor6D が 0 本で AnimationConstraint だけのことがある（2026-09 の Studio 実測: Motor6D 0 / AnimationConstraint 15）。Motor6D だけを探すコードはその体を何も動かさない。
- **Transform は `RunService.PreSimulation` で書く**（Animator の後）。`PreRender` / `RenderStepped` で書いても描画に反映されない。`PreAnimation` で前フレームの Animator 出力へ戻しておくと、PreSimulation で読む値が「このフレームの Animator の出力」になる（自分の前フレームの書き込みを読み違えない）。
- 足の高さを合わせるのは **Root の縦移動だけ**（関節は回さない）。片足だけ合わせるときは二関節 IK（`Kit.reachFoot`: 膝で長さ、股関節の最小の振りで向き、足首で足の向きを保つ、伸び切り手前は soft IK）。
- 坂・階段は足ごとに床を測る（`Kit.floorUnderFeet`: つま先とかかとの 2 本、**root の高さから**撃つ）→ `Kit.smoothFloor`（段の縁で床が 1 段不連続に変わるのを 2〜3 フレームの坂にする）→ `Kit.fitFeetToFloor`（低い方の足を自分の床へ、骨盤を必要な分だけ下げ、もう片方を IK で上げる。持ち上げは脚長 × 0.55 まで。越えると膝が畳まれて脚が反転する）。
- 補正（IK・接地）の出し入れは**速さに上限**をかける（`Kit.carryLimit`: live の動き + 360°/s）。live の動きそのものは遅らせない。
- 空中と着地直後は床を raycast し、物理 1 ステップ分の落下を先に足して、足を床より下へ入れない（上げるだけ、`Kit.floorClearance` + `Kit.raiseLowest`）。
- 二次運動（`Kit.Secondary`）は速度だけから計算し、作者の傾きとの差だけを足し、傾けた後も踏んでいる足の高さを戻す。全身を持つ動き（エモート・空中技・スピン）では重みを 0 へ。
- 自機・NPC・他プレイヤーで**同じ関数**を通す。接地判定は自機なら `Humanoid.FloorMaterial`、他の体は真下への短い raycast も併用（クライアント側の FloorMaterial は他の体で Air と行き来する）。
- 更新が途切れても体を外さない（自機が倒れている間はコントローラが他の体の更新を止める実装が多い。外すと生の track に戻って沈む）。
- 物理・HumanoidRootPart・入力には触れない。毎フレームの Instance 生成・属性書き込みはしない（属性は値が変わったときだけ）。12 体以上で軽いこと。

### 6. オフラインで契約を証明する

Lune で、計測したリグ（0.8 / 1.0 / 1.3 倍）と 30 / 60 / 144 fps で、測れる契約を assert する。雛形: `scripts/test_pose_kit.luau`（キット自体の 361 契約）。書く契約の例: 接地（低い方の足 = 立ったときの足の高さ ±1e-4）、沈まない（≥ −1e-4）、1 フレームの最大回転、live の脚との差、ばねの定常値（傾き = atan(gain·v·ω / g)）、NaN・発散しない、全身モードで二次運動が 0。既存のテストが**意図した仕様変更**で落ちたら、黙って緩めず、新しい契約へ書き直して理由をコメントに残す。手順と罠: `references/verification.md`。

### 7. Studio Play で実測する

コピーを専用の Studio で開き（正本の窓とは別）、Play で（部品だけ試すなら `scripts/make_test_place.py` の sandbox: 平地・坂・階段 + 既定 Animate）:

- `contact_probe.luau` で体・床・OFF/ON・モード別の接地（変更前の数値と比べる）。決まった経路は client から `Humanoid:MoveTo` で流す。NPC の試合を 60〜90 秒流すと数万フレーム取れる。
- 再現しにくい動き（特定の半径の旋回、ジャンプの着地、スピン）は、属性で駆動する**検証用フック**（Studio 専用。終わったら除去し、指紋で除去を確認）で再現する。
- クローズアップの撮影は RenderStep に固定カメラを bind する。1 秒未満の動きはモジュールに TimeScale 属性を持たせてスローにする。
- `LogService:GetLogHistory()` で client / server のエラー・警告 0 を確認。
- MCP のキー入力は Play のビューポートにフォーカスが無いと届かない。先にビューポートをクリックし、速度をサンプラーで確かめる。

Studio の罠（MCP の sandbox、キャッシュ、撮影の遅れ）: `references/verification.md`。

### 8. 取り込む（採用されたら）

正本へは「対象スクリプトが作業の元と同一なら差し替え、違えば 3-way merge」「層以外は 1 バイトも変わらない」「逆に戻すと元のバイト列になる」を証明してから書く。ソースツリー（Rojo の src など）は他セッションの未 commit 変更を保つ 3-way merge。保護対象ファイル（byte guard）には承認済みの差分層を登録する。モジュールを新規追加したら、Place へ同期するスクリプトの対象一覧にも足す（本体だけ同期されて依存が欠ける事故を防ぐ）。取り込み後にもう一度オフラインテストと Studio Play（正本のバイトコピーで）。詳細: `references/integration.md`。

### 9. 報告する

変更前 → 後の数値（接地の min / 沈んだフレーム数 / 最大跳び / エラー数）、見た目の要点、意図して変えた契約とその理由、残る制約（例: 強い着地の 1 フレームだけ ±0.15 残る理由）、ユーザーの判断が要る事項を短く。

## よくある罠（詳細は各 reference）

- `PreRender` で書いた Transform は描画されない。PreSimulation で書き、1 物理ステップ先を予測する。
- 強い着地では Humanoid の root が立ち高さより 0.2〜0.5 沈む（落下速度に比例）。床クランプは「沈みを許す下限」を持つ。
- 作者のリグと体の寸法が違うと、購入済みの track は足が最大 0.5 沈み 0.2 浮く。track にも接地を掛ける。
- 他プレイヤーの体には track 名しか届かない。独自スタイル名は再生側で推定する。
- NPC がときどき沈む → 自機が倒れている間に更新が止まっていないか疑う。
- Server Authority のアバターは `Motor6D` ではなく `AnimationConstraint` を動かす（`Kit.jointData` で両対応）。
- execute_luau の `require` は別のモジュールインスタンス。ゲームの状態を読むには属性か、ゲームのソースに一時フックを入れる。

## 参照ファイル

- `references/quality-bar.md` — 「超一流」の定義、モード別チェックリストと実績値（読む: 設計のとき）
- `references/pose-layer.md` — ポーズレイヤーの構造、フレーム順、骨組みコード、接地・IK・遷移・二次運動・他プレイヤー（読む: 実装のとき）
- `references/r15-rig.md` — R15 の関節・符号表・Motor6D と AnimationConstraint・AnimationTrack / KeyframeSequence の事実（読む: 経路選択と姿勢作成のとき）
- `references/verification.md` — Lune のオフラインハーネスと Studio Play の実測レシピ・罠（読む: 検証のとき）
- `references/integration.md` — コピー・差分層・証明つき取り込み・byte guard・同期（読む: 着手時と取り込み時）
- `assets/AvatarPoseKit.luau` — 接地（平地・坂・階段・空中）・IK・速さの上限・遷移・ばね・二次運動の部品（コピーして使う）
- `assets/PoseLayerTemplate.luau` — キットを使う描画層の骨組み（PreAnimation / PreSimulation、モード、接地、二次運動、A/B 切替）。sandbox 実測: 平地の沈み 268→8・浮き 421→0、坂 297→3、階段（移動中）53%/22%→16%/14%
- `assets/rig-r15-sample.json` — 計測済みの R15 ブロック体（テスト用）
- `scripts/test_pose_kit.luau` — キットの契約テスト（361 契約）兼オフラインハーネスの雛形（`lune run scripts/test_pose_kit.luau [kit] [rig.json]`）
- `scripts/make_test_place.py` — 検証用 sandbox Place（.rbxlx）を書き出す（`python scripts/make_test_place.py OUT.rbxlx [--layer 自分の層]`）
- `scripts/studio/dump_rig.luau`・`capture_pose.luau`・`contact_probe.luau` — Studio（execute_luau, Client）用の計測
