# Codex CLI 委譲用 指示文 — サーバー側 移動処理のバグ修正（SpinOut / Rojo）

過去に起きた 2 つの失敗（1. バックグラウンドで何時間も無進捗、2. モジュールが読み込めなくなる書き換え）は、原因が違うので対策も分けてあります。

- **無進捗ハング** … 指示文だけでは防げません。「常駐コマンドを禁止する」＋「無言で進まない報告義務」＋「**フォアグラウンドで走らせて自分で見る**」の 3 点セットで潰します。バックグラウンド実行そのものを今回はやめてください。
- **モジュール破壊** … Rojo は「ファイル名 → Roblox インスタンス型」の変換規則で動くので、リネーム・拡張子変更・新規ファイル追加をやられると `require` が壊れます。これは **禁止事項として明文化すれば防げます**。

---

## 0. 投げる前に 1 箇所だけ埋める

指示文の `【症状】` ブロックだけは埋めてください。ここが曖昧だと Codex は当てずっぽうで探索を始め、それが長時間ハングの最大の原因になります。

- 何をすると（操作手順）
- どうなるか（実際の挙動）
- どうなってほしいか（期待）
- Output に出るログ／エラー文字列があればそのまま貼る

あわせて、投げる前に `git status` がクリーンなことと、作業ブランチを切ってあることを確認してください（差分レビューが一瞬で終わります）。

---

## 1. そのまま貼る指示文

```text
あなたは SpinOut（Roblox / Rojo プロジェクト）のサーバー側移動処理のバグを 1 件修正します。
以下の制約は「守れなかったら作業を止めて報告する」種類の制約です。自己判断で回避しないでください。

────────────────────────────
【リポジトリの事実】※推測で補わないこと
────────────────────────────
- リポジトリルート: C:\Users\Administrator\Documents\GitHub\SpinOut
- ビルド構成: Rojo 7.7.0（rokit.toml で固定）。プロジェクトファイルは mvp.project.json
- mvp.project.json のマッピング（これが Roblox 上の階層を決める）
    src/mvp/shared  -> ReplicatedStorage.Shared
    src/mvp/server  -> ServerScriptService.Server
    src/mvp/client  -> StarterPlayer.StarterPlayerScripts.Client
- 拡張子がインスタンス型を決める
    Foo.luau         -> ModuleScript
    Foo.server.luau  -> Script（サーバー実行）
    Foo.client.luau  -> LocalScript
- 既存の require 規約（これに合わせる。新しい書き方を導入しない）
    共有モジュール    : local Types = require(ReplicatedStorage.Shared.Types)
    サーバー内の兄弟  : local Bootstrap = require(script.Parent.Bootstrap)
- サーバー起動の実体は src/mvp/server/Main.server.luau。
  ここが Bootstrap.run(RobloxServerAdapters.new()) を呼び、成功時に
  「MVP_BOOTSTRAP entrypoint=Main result=ok」を print する。この print は検証に使っているので消さない。

────────────────────────────
【症状】※ここが今回の唯一のゴール
────────────────────────────
再現手順:
  <<ここに手順を書く>>
実際の挙動:
  <<ここに書く>>
期待する挙動:
  <<ここに書く>>
Output に出るログ/エラー:
  <<あれば貼る。なければ「なし」>>

────────────────────────────
【変更してよい範囲】
────────────────────────────
- 第一候補は src/mvp/server/MovementService.luau。原則ここだけを直す。
- 読むのは自由（src/ 配下・docs/ 配下すべて読んでよい）。書き換えだけを絞る。
- 修正が MovementService.luau の外に必要だと判断したら、書き換えずに停止して報告する。
  特に RobloxServerAdapters.luau / MatchService.luau / shared/Config.luau に手を入れたくなった場合は、
  「なぜ必要か」を書いて指示を仰ぐこと。

────────────────────────────
【禁止事項 A: モジュール解決を壊さないため】
────────────────────────────
1. ファイルの新規作成・削除・リネーム・移動をしない。既存ファイルの中身だけを編集する。
   （必要だと思ったら実行せず、提案として報告して停止）
2. 拡張子を変えない。.luau を .server.luau にする等はインスタンス型が変わり require が即死する。
3. require の書き方を変えない。既存行の書き換え・パスの付け替えをしない。
   - script.Parent.Parent... のような階層跨ぎに書き換えない
   - 文字列 require（require("path/to/x")）を使わない
   - 共有モジュールを script.Parent 経由で取りに行かない（Shared は ReplicatedStorage 側にある）
4. 循環 require を作らない。A が B を、B が A を require する形になったら、その場で停止して報告する。
5. ModuleScript の末尾の return を消さない・条件分岐の中に入れない。必ず単一の値を return したまま保つ。
6. ファイル先頭の --!strict を消さない。型エラーを型注釈の削除や any 化で黙らせない。
7. 既存の print ログ（MVP_BOOTSTRAP など）の有無・文言・フォーマットを変えない。
8. mvp.project.json / pa.project.json / rokit.toml を編集しない。
9. *.rbxlx / *.rbxl を編集・再生成しない（.gitattributes で binary 指定、ハッシュが壊れる）。
10. 依存を新規追加しない（rokit / wally / npm いずれも）。
11. ファイル全体を書き直さない。該当箇所のみ差分編集する（改行コードは既存のまま LF を保つ）。

────────────────────────────
【禁止事項 B: 停止・ハングを防ぐため】
────────────────────────────
1. 常駐する（自分で終了しない）コマンドを一切実行しない。
   禁止例: rojo serve / --watch 系 / tail -f / dev server / Studio の起動と起動待ち
2. バックグラウンド実行をしない。& や start やジョブ化を使わない。全コマンドはフォアグラウンドで実行し、
   終了コードを確認してから次に進む。
3. 標準入力を要求する対話コマンドを使わない（git rebase -i、git add -i、エディタ起動、確認プロンプト等）。
4. 1 コマンドの想定実行時間は 60 秒以内。それを超える見込みのものは実行せず、
   「何を実行したいか」を報告して停止する。
5. Roblox Studio を操作しない。実機での Play 検証はこちらで行う。
6. git commit / git push / git checkout / git reset / git stash をしない。作業ツリーに差分を残すだけにする。

実行してよいコマンドの例:
  git status / git diff / git diff --name-status / git diff --stat
  ファイルの読み書き
  rojo build mvp.project.json --output "$env:TEMP\spinout_verify.rbxl"   （一発で終わる。リポジトリを汚さない）

────────────────────────────
【進捗報告の義務】
────────────────────────────
- 各手順の冒頭に「[STEP n] これから何をするか」を 1 行で出力してから実行する。
- 無言のまま作業を続けない。5 分以上出力が途切れる状態を作らない。
- 探索が長引いた場合も、黙って続けずに [STEP n] を出し続ける。

────────────────────────────
【停止条件】※どれかに当たったら即座に中断して報告し、終了する
────────────────────────────
- 原因が MovementService.luau の外にあると判断した
- 修正が 3 ファイル以上に波及しそう
- 同じエラー・同じ失敗を 2 回繰り返した
- 着手から合計 15 分、または 30 ステップを超えた
- 上記の禁止事項に触れないと直せないと判断した
停止するときは「勝手に方針転換して探索を続ける」ことをしない。分かったところまでを報告して終わる。

────────────────────────────
【完了条件】
────────────────────────────
1. 症状の原因を、ファイル名と該当行で特定できている
2. 修正が入っている（原則 MovementService.luau のみ）
3. rojo build mvp.project.json --output "$env:TEMP\spinout_verify.rbxl" が終了コード 0
4. git diff --name-status が M（変更）のみ。A/D/R（追加・削除・リネーム）が 1 件も無い
5. git diff に、require 行の変更・--!strict の削除・return の削除・print ログの削除が含まれていない

────────────────────────────
【最終報告のフォーマット】
────────────────────────────
1. 原因（ファイル:行 と、なぜその挙動になるか）
2. 修正内容（何をどう変えたか、3 行以内）
3. git diff --stat の出力そのまま
4. rojo build の結果（終了コードと出力パス）
5. 完了条件 4・5 を自分で確認した結果（○/×）
6. 未検証事項（Studio 実機で確認すべきこと）
7. 副作用・リスク（他の挙動に影響しうる点）
```

---

## 2. 走らせ方（ここを変えないとハングは再発します）

- **フォアグラウンドで実行し、画面を見ておく。** 今回はバックグラウンドに回さないでください。前回無進捗のまま何時間も経ったのは、誰も見ていなかったからです。
- **自分の側でも時計を見る。** 10 分で何も終わっていなければ、指示文の停止条件を守っていません。Ctrl+C で止めて、「現状の差分と分かったことだけ報告して」と投げ直します。
- `rojo serve` という文字列が出た瞬間に中断してください。これが一番典型的な「永遠に返ってこない」パターンです。

---

## 3. 投げたあとに確認すること

### A. 実行中（ハングの早期検知）

1. `[STEP n]` が更新され続けているか。**5 分以上無言なら中断**。
2. 常駐コマンド（`rojo serve` / `--watch` / `tail -f`）を叩いていないか。
3. 入力待ちのプロンプトで止まっていないか（`(y/N)` などが表示されたまま無反応）。

### B. 終了直後（モジュール破壊の検知）— 上から順に

PowerShell で実行します。

1. **変更ファイル一覧**
   ```powershell
   git status --porcelain
   git diff --name-status
   ```
   → **`M` 以外が出たら赤信号**。`A`（新規）・`D`（削除）・`R`（リネーム）は禁止事項違反です。特に `R` は拡張子が変わって ModuleScript が Script になっている可能性があります。

2. **変更規模が説明と合っているか**
   ```powershell
   git diff --stat
   ```
   → 「1 行のバグ」と言いながら 200 行変わっていたら、リファクタを勝手に始めています。

3. **プロジェクト定義が無傷か**
   ```powershell
   git diff -- mvp.project.json rokit.toml
   ```
   → **何も出力されないこと**。

4. **require が書き換わっていないか**（今回の再発防止の本丸）
   ```powershell
   git diff | Select-String "require|--!strict|^\-return"
   ```
   → `-` 側（削除行）に `require(` / `--!strict` / `return` が出たら要確認。

5. **検証用ログが消されていないか**
   ```powershell
   git diff | Select-String "MVP_BOOTSTRAP"
   ```
   → 削除・文言変更が無いこと。

6. **ビルドが通るか**
   ```powershell
   rojo build mvp.project.json --output "$env:TEMP\spinout_verify.rbxl"; $LASTEXITCODE
   ```
   → `0` であること。
   **注意: これが通っても「モジュールが読み込める」証明にはなりません。** `rojo build` はファイル→インスタンス変換が成立するかまでしか見ません。`require` の失敗・循環参照・`return` 忘れは実行時にしか出ません。次の 7 が本番の判定です。

7. **Studio で Play して Output を見る**（モジュール読み込みの実質判定）
   - **合格**: `MVP_BOOTSTRAP entrypoint=Main result=ok` が出る
   - **不合格**: `MVP_BOOTSTRAP entrypoint=Main result=failed stage=... code=...` → 起動段階で失敗。`stage` を見れば場所が分かります
   - **モジュール破壊のサイン**（赤エラー）:
     - `Requested module experienced an error while loading` → 循環 require か、モジュール内で例外
     - `Module code did not return exactly one value` → `return` が消えた／条件分岐に入った
     - `Attempt to call a Script`／`Unable to cast` 系 → 拡張子が変わって ModuleScript でなくなった
     - `Infinite yield possible on 'WaitForChild(...)'` → 期待した階層にインスタンスが無い（パスの前提が崩れた）

8. **バグ本体の確認**
   - 報告された再現手順をなぞって、症状が消えていること
   - **直前まで動いていた移動挙動（加速・旋回・ブレーキ・停止）が壊れていないこと**。移動処理は相互に効くので、ここのリグレッション確認は省かないでください。

### C. 合格後

`git commit` は自分で行ってください（指示文で Codex には禁止してあります）。差分を自分の目で通した上でコミットする、という順番を崩さないのが安全です。

---

## 4. NG だったときの差し戻し文（短く、範囲を狭めて再投入）

```text
前回の修正は受け入れません。以下を守って、作業ツリーの現状から再実行してください。

- 検知した問題: <<例: git diff --name-status に R が出ている / Play 時に Requested module experienced an error>>
- まず、前回入れた変更のうち禁止事項に触れている部分だけを元に戻す（ファイルの新規作成・リネーム・require 行の変更・return や --!strict の削除）
- そのうえで、変更を src/mvp/server/MovementService.luau の中だけに限定して直す
- 直せないと判断したら、直さずに「なぜ MovementService.luau だけでは直せないか」を報告して停止する
- 前回と同じ制約（禁止事項 A / B、進捗報告、停止条件）はすべて有効
```

---

## 補足: なぜこの 2 つが起きるのか（対策の根拠）

- **モジュール破壊**: Rojo は「ファイル名の形」でインスタンス型を決めます。`Foo.luau` は ModuleScript ですが `Foo.server.luau` は Script です。エージェントは「サーバー用だから .server を付けよう」という一見自然な判断をしがちで、それだけで `require` が死にます。さらにこのプロジェクトは共有モジュールを `ReplicatedStorage.Shared` から、サーバー内モジュールを `script.Parent` から取る二本立てなので、片方の流儀でもう片方を書き換えると壊れます。**だから「ファイル操作禁止・require 行変更禁止」を明示的な禁止事項として書くのが効きます。**
- **無進捗ハング**: 原因のほとんどは (a) 常駐コマンドを叩いて戻ってこない、(b) 対話プロンプトで入力待ち、(c) ゴールが曖昧で探索が終わらない、の 3 つです。上の指示文はそれぞれ「禁止事項 B-1/B-3」「【症状】欄の記入」で塞ぎ、それでも漏れた場合に備えて「停止条件」と「[STEP n] の報告義務」で外から気づけるようにしています。
