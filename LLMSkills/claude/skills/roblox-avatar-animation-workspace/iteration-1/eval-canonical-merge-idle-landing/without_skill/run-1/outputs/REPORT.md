# mini-game 着地アニメ／待機呼吸 改善レポート

（サブエージェントがファイルに書けなかったため、最終メッセージの本文を採点用にここへ保存。本文は要約せず転記。）

## 1. 診断
旧 `src/client/AnimController.client.luau` の問題:
1. **`RenderStepped` で `Motor6D.Transform` を書いている** — フレーム順は RenderStepped → (Animator書込) → PreSimulation → 物理。既定 Animate のトラックが膝・Waist を毎フレーム上書きするので、着地も呼吸もほぼ消える（「ほとんど効いてない」の主因）。
2. アニメの上に重ねず `=` で代入 — 仮に残ってもアニメのポーズを捨てる。
3. 膝の回転が逆向き（+X）— R15 では +X で下肢の先が前に出る（鳥脚）。+35° 単独でつま先が前 0.578 / 上 0.497 stud 動く（Lune で計測）。
4. 膝だけ曲げる — 骨盤を下げず、股関節・足首も補正しないので足が浮き、沈み込み（重さ）が出ない。
5. 着地の瞬間に 0→35° へ 1 フレームで跳び、線形で戻る。落下速度と無関係に毎回同じ。
6. 呼吸は Waist の X 軸だけの純サイン ±3°（振れ幅 6°）、固定周期、頭も頷く、歩行中・空中でも常時オン。
（補足: 正本の `IDLE_BREATH_SECONDS=2` は 30 回/分で速い。チームメイトが未コミットで 2.6 に変更中）

## 2. 変更内容
**`src/client/AnimLayers.luau`（新規 ModuleScript・エンジン非依存の純関数 → Lune でそのままテスト）**
- 着地強度 = 落下中の速度から。12 stud/s 未満は無し、通常ジャンプ（50）でちょうど `LAND_KNEE_DEGREES`、95 以上で 1.7 倍が上限。持続時間も強度で 0.7〜1.35 倍。
- 接地を保つ解: 目標の膝屈曲から骨盤の下げ・股関節屈曲・膝（−X）・足首を解き、足裏を着地位置に固定。
- エンベロープ: 25% 地点までクォーターサインで沈み、smoothstep で戻る（終端で値も傾きも 0 → 切れ目なし）。上体は少し遅れて追従＋軽い反動（フォロースルー）、首が上体の前傾を打ち消して頭を安定、腕はバランスで少し外へ。
- 呼吸: 吸気 38% / 呼気 48% / 休止 14% の非対称波形、1 呼吸ごとに周期 ±8%・深さ ±12% を揺らす（切替は休止中なので跳ばない）。胸の傾き＋胸・肩のわずかな持ち上げ、首が胸の傾きの 85% を打ち消し頭は水平、7.3 秒周期の小さな重心揺れ。
- 待機判定: 動き出すと 0.12 秒で呼吸オフ、止まって 0.7 秒でフェードイン。
- 累積防止ガード（`newJointLayer`）: どのトラックも書かなかった関節は前回の基準姿勢から再計算し、自分の出力に掛け続けて膨らまない。

**`src/client/AnimController.client.luau`（書き換え）**
- **`RunService.PreSimulation`**（Animator の後）で、アニメ済み Transform に重ねて書く。管理する関節は毎フレーム書き、層が無ければ元へ戻す。
- 落下中の最大速度を衝撃速度に使う（`Landed` 時点では速度がほぼ 0）。脚の長さはリグの C0/C1 から実測。リスポーン対応。

**`src/shared/AnimConfig.luau`: 一切変更していない。**
4 つのノブ（`LAND_SECONDS` / `LAND_KNEE_DEGREES` / `IDLE_BREATH_SECONDS` / `IDLE_BREATH_DEGREES`）は引き続きここから読み、細かい形の値は `AnimLayers.TUNING` に置いた。

## 3. 正本 Place の更新と証明
Game.rbxlx は Studio 保存（手置きマップ入り）なので Rojo で作り直さず、`tools/splice_place.py --apply` で対象スクリプトの Source だけをテキストで差し替えた（適用済み）。
- 差し替え: `StarterPlayer.StarterPlayerScripts.Anim.AnimController` の Source（1529 → 4790 文字）
- 追加: 同フォルダに ModuleScript `AnimLayers`
- **`ReplicatedStorage.Shared.AnimConfig` は取り込まない（保護対象）**。正本の値は HEAD の `IDLE_BREATH_SECONDS = 2` のまま。

証明:
1. 前提チェック: Place 内の Source が前回同期版（`places/Game.sync.json`、初回は git HEAD）と一致しなければ中止。HEAD の旧 Place のコピーで再実行すると `ABORT ... differs from the last synced version` で止まることを確認。
2. 差し替え領域を除いた SHA-256 が前後で一致（`b05b3c56a3af6360`）。
3. インスタンス木 11 → 12（増えたのは AnimLayers だけ）。既存全インスタンスの Source 以外のプロパティは同一。AnimConfig は変化なし。
4. 改行は作業コピーと同じ CRLF。git diff で消えた行は旧 AnimController だけ。
5. 冪等: 再実行で `nothing to do`。
6. 別パーサ（Lune rbx-dom）でも ALL PASS: 3 スクリプトがコンパイル可、AnimController / AnimLayers は src と一致、AnimConfig は HEAD のまま、Baseplate / SpawnLocation / Ledge の位置・サイズ・Anchored は元のまま。
7. ファイル: 4408 bytes（`48be66bc…`）→ 21377 bytes（`51b0f2cc…`）。

## 4. 検証（Lune 0.10.5、3 本とも ALL PASS）
着地（R15 脚 FK、60 Hz）:
- 旧: 膝ピーク 35°（逆向き）、ピーク時刻 0 s、骨盤の下げ 0、1 フレーム最大 35°、足裏のずれ 0.58 前 / 0.50 上
- 20 stud/s: 15.5°、0.067 s、0.016、6.9°、0.00000
- 50（通常ジャンプ）: 34.9°、0.083 s、0.080、12.0°、0.00000
- 70: 45.8°、0.083 s、0.137、13.7°、0.00000
- 95 以上: 59.5°、0.100 s、0.229、15.2°、0.00000

実スクリプトをモックのフレーム順（RenderStepped → Animator → PreSimulation）で実行:
- 旧（HEAD）: 上乗せされた膝屈曲 0.0°、骨盤の下げ 0、足裏のずれ 0、待機時の胸 0.00°、頭 0.00°、歩行中の呼吸 0.00°
- 新: 31.5°、0.065、0.0205、1.51°、0.23°、0.00°

呼吸（60 秒）:
- 旧: 30 回/分、2.00 s 固定、吸気:呼気 1:1、胸 ±3°、頭 ±3°（頷く）
- 2.0: 28 回/分、平均 2.03 / 最小 1.88 / 最大 2.15 s、0.81、胸 1.68°、頭 0.25°
- 2.6: 21 回/分、2.63 / 2.45 / 2.78 s、0.80、1.68°、0.25°

待機の重みは動き出して 0.133 s で 0、止まって 0.700 s で戻る。誰も上書きしない関節に +10° を 120 フレーム掛けても 10.000° のまま（累積しない）。

## 5. Studio での確認手順
1. 正本 Place を Studio で開いていたら保存せずに閉じる（保存すると差し替えを上書き）。
2. `places/Game.rbxlx` を開き、`Anim` フォルダに AnimController（LocalScript）と AnimLayers（ModuleScript）、AnimConfig が `IDLE_BREATH_SECONDS = 2` のままを確認。
3. F5 → エラーが無いこと。
4. 目視: 静止で胸がゆっくり上下・頭は揺れない、歩くと呼吸が消え止まるとふわっと戻る。平地でジャンプ → 着地で腰が沈み膝が前に曲がり足は地面に付いたまま。Ledge（X=20、高さ 6）から降りる → より深く長い。
5. 数値: Command Bar を **Client** にして `tools/studio/anim_probe.command.luau` を貼って実行し、12 秒以内に「静止 → 平地ジャンプ → Ledge から降りる → 静止」。期待値: pelvis drop 平地 約 0.06〜0.08 / Ledge 約 0.07〜0.14、sole height change < 0.05 stud、idle head pitch range < 1°（旧は約 6°）。
6. 旧版と比べるなら `git show HEAD:places/Game.rbxlx > old.rbxlx` で同じ手順。
7. Studio で保存した後は `python tools/splice_place.py`（`nothing to do` ならよい）と `lune run tests/place_scripts.spec.luau` を再実行。

## 6. ユーザー側でまだ必要なこと
- Studio 確認後にコミット。publish はオーナー指示の後。
- チームメイトの AnimConfig 作業がコミットされたら `python tools/splice_place.py --apply --include ReplicatedStorage/Shared/AnimConfig` で正本に取り込む。
- 呼吸周期の推奨は 3.5〜4.5 秒（チームメイトの担当なので値は変えていない）。
- 残課題: 脚の解は「脚がまっすぐ」前提の近似（基準姿勢が曲がっていると足裏が最大 0.02 stud ずれる）。Transform はローカル専用で他プレイヤーからは見えない（旧版と同じ）。「Animator が毎フレーム上書きする」という前提は Studio 手順 5 で確かめる必要あり。

## 7. ファイル（すべて `outputs/mini-game/` 内）
変更: `src/client/AnimController.client.luau`, `places/Game.rbxlx`
新規: `src/client/AnimLayers.luau`, `tests/anim_layers.spec.luau`, `tests/controller_harness.spec.luau`, `tests/place_scripts.spec.luau`, `tools/splice_place.py`, `tools/studio/anim_probe.command.luau`, `places/Game.sync.json`
未変更: `src/shared/AnimConfig.luau`（チームメイトの WIP を保持）
ログ（`outputs/` 直下）: `anim_layers.spec.out.txt`, `controller_harness.spec.out.txt`, `place_scripts.spec.out.txt`, `splice_apply.out.txt`
