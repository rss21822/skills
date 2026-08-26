# Codex CLI への実装委譲 — サーバー移動処理のバグ修正

対象リポジトリ: `C:\Users\Administrator\Documents\GitHub\SpinOut`（Rojo プロジェクト、rojo 7.7.0 pin、サーバー移動処理は `src/mvp/server/MovementService.luau`）

---

## 0. 先に結論 — 過去に踏んだ2つは原因が確定している

| あなたが踏んだ症状 | 実測済みの原因 | 対処（本文に組み込み済み） |
|---|---|---|
| バックグラウンド実行のまま何時間も進まない | 標準入力を閉じずに対話型 CLI を起動したため、入力待ちで永久停止（実測 11 時間ハングの事例あり） | 起動コマンドに `< /dev/null`（PowerShell なら空ファイルを `-RedirectStandardInput`）を必ず付ける → §4 |
| モジュールが読み込めなくなる書き方をされた | 行頭が開き括弧で始まる型キャストへの代入 `(x :: T).Prop = ...`。前行の続きと解釈されて曖昧構文になり、**そのモジュールが丸ごと読み込み失敗**する。委譲すると自然に量産される（1 回の委譲で 13 箇所出た事例あり） | プロンプトの「常設禁止条項」に明記＋受領後に grep で全数検出 → §3・§5.2 |

さらに重要な前提が1つあります。

> **`rojo build` は Luau をパースしません。** ソースを文字列として place に詰めるだけなので、上記の曖昧構文が入っていても **build は成功し、sha256 も決定論的に一致します。** つまり「ビルドが通った」はモジュールが読めることの証明になりません。**読み込みの可否は Studio 側でしか判定できません**（§5.2 に実証手順）。

---

## 1. 投げる前に、こちらで決めておくこと（3分）

### 1-1. 症状を「実測値だけ」で書き出す

推測を症状に混ぜると、実装側がその推測を前提に直してしまいます。

- 悪い例: 「移動処理の速度計算がバグっている」
- 良い例: 「W を押し続けても `HumanoidRootPart.Position` が 10 秒間まったく変化しない。同時刻のサーバーログでは `speed` が 0.0 のまま」

### 1-2. 「コードだけで原因が一意に決まるか」を判断する

| 状況 | やること |
|---|---|
| 原因箇所が一意に絞れている（例: 積分の1行が欠けているのを目視で確認済み） | §3 の修正プロンプトを直接投げる |
| 症状は分かるが原因箇所が絞れない | **先に §2 の読み取り専用の調査を投げる。** 修正を投げると推測で「直され」ます |
| そもそも症状が実測できていない | 投げる前に Studio で実測する。診断ログを入れて 1 回回すほうが速い |

### 1-3. baseline を pin する

```powershell
git -C C:\Users\Administrator\Documents\GitHub\SpinOut status --short   # 空であること
git -C C:\Users\Administrator\Documents\GitHub\SpinOut rev-parse HEAD
```

作業ツリーが汚れたまま投げると、あとで「どれが Codex の変更か」が切り分けられなくなります。

---

## 2. 段1（原因が絞れていないとき）— 読み取り専用の調査プロンプト

`docs/handoffs/SPINOUT-H-0XX_move_diag.md` として保存して投げます。

### 起動

```bash
codex exec --model gpt-5.6-sol -c model_reasoning_effort=high \
  -s read-only -o docs/handoffs/out/H-0XX_diag.md \
  "$(cat docs/handoffs/SPINOUT-H-0XX_move_diag.md)" < /dev/null
```

### プロンプト本文

````markdown
あなたは読み取り専用の原因調査担当。**ファイルを一切変更しない。** 最終メッセージが成果物。日本語で答える。

## 対象リポジトリ

SpinOut（Rojo）。baseline commit `<HEAD の実値>`。

## 症状（実測値のみ。以下に書かれていない事象を前提にしない）

- <例> Studio のローカルテストセッション（server + client 2）で、client 1 が W を押し続けても `HumanoidRootPart.Position` が 12 秒間 `(0.0, 3.0, -24.0)` から変化しない。
- <例> 同区間のサーバー Output に `move p=-1 speed=0.000` が毎フレーム出ている。`intent.move` は `(0.000, 0.000, 1.000)` で届いている。
- <例> エラーも警告も 0 件。

**上記以外の症状は観測していない。推測を症状として扱わない。**

## 調査範囲（この範囲外は読まなくてよい）

- `src/mvp/server/MovementService.luau`
- `src/mvp/server/Main.server.luau` / `Bootstrap.luau` / `MatchService.luau`（step 駆動と ingress）
- `src/mvp/server/RobloxServerAdapters.luau`（CFrame / velocity の反映）
- `src/mvp/shared/Config.luau`（`DATA-MOVE-001`〜`DATA-MOVE-010` の転記）
- `src/mvp/client/InputController.luau`（意図の生成のみ）

## 求める出力

1. **根本原因**を `file:line` 付きで。該当行を引用する。
2. **最小修正案**を「記述で」示す（コードは書かない。変更する行と変更後の意味を説明する）。
3. 副作用の見込み（この修正が触る他の経路）。

## 重要な指示

- **根本原因が一意に確定できない場合は、「確定できない」と報告すること。** それらしい候補を確定として書かない。確定できないときは、代わりに「どの値をログに出せば一意に決まるか」を、判定に使われている変数名で列挙する。
- 複数候補が残る場合は、候補ごとに「この症状と矛盾しない理由」と「棄却するために必要な実測値」を書く。
- 実行していない検証を実行したと書かない。Studio 実機での確認はあなたの環境からはできないので、それを行ったと書かない。
````

**「確定できない」と返ってきたら、それは失敗ではなく正しい応答です。** その場合は返ってきた変数名で診断ログを 1 行入れ、Studio で実測してから §3 へ進みます。

---

## 3. 段2（本体）— 修正の委譲プロンプト

`docs/handoffs/SPINOUT-H-0XX.md` として保存します（このリポジトリの既存 handoff 形式に合わせてあります）。`<>` を埋めてください。

````markdown
# Handoff SPINOUT-H-0XX — サーバー移動処理の欠陥修正

| 項目 | 値 |
|---|---|
| handoffId | `SPINOUT-H-0XX` |
| status | `Active`（<日付> 発行） |
| phase | MVP / WP-04 系の是正 |
| baseline | commit `<HEAD の実値>`（作業ツリー clean を確認済み） |
| resultCommit | `pending` |

## 症状（実測値のみ。ここに無い事象を前提にしない）

- <§2 と同じ実測記述をそのまま貼る>

## 根本原因（確定済み）

`<file>:<line>` — <確定した原因を1〜3行で>

（段1 を実施した場合はその結論を貼る。実施していない場合は、この節に「未確定」と書かず、**そもそも修正 handoff を出さない**。§2 を先に回す）

## objective（完了時に観測できる状態）

- <例> Studio のローカルテストセッションで W 入力を保持したとき、サーバーログの `speed` が 0 から単調増加し、`DATA-MOVE-001`（最高速度）で頭打ちになる。
- <例> 同時に `HumanoidRootPart.Position` が入力方向へ変化する。
- `rojo build mvp.project.json` を 2 回実行した sha256 が一致する。
- `git status --short` の変更が inScope のパスのみ。

## inScope（これ以外のファイルを変更しない）

- `src/mvp/server/MovementService.luau`
- <必要なら> `src/mvp/server/RobloxServerAdapters.luau`

## outOfScope（変更禁止。読むのは可）

- `src/pa/**`（P-A は計測装置として凍結）
- `docs/SPINOUT_gdd.md`、`docs/SPINOUT_data_definition.md`、`docs/SPINOUT_detailed_design.md`
- `mvp.project.json`、`rokit.toml`、`.gitattributes`
- `artifacts/build/PA.rbxlx` および P-A の全 artifact
- テストの合否判定ロジック（通すために緩めない）

## dataIds（使用を許可する数値。これ以外の数値を書かない）

`DATA-MOVE-001` 〜 `DATA-MOVE-010`（`src/mvp/shared/Config.luau` の転記表から**実行時に読む**。値を `MovementService` へ複製しない）

## 常設禁止条項（すべて厳守）

1. **数値の新規創作を禁止。** gameplay 数値は上記 dataIds の参照のみ。既存値の変更も禁止。マジックナンバーを一時的にも書かない。
2. **行頭が開き括弧になる型キャストへの代入を禁止。**

   ```lua
   -- 禁止（曖昧構文。モジュールが丸ごと読み込み失敗する）
   (someValue :: SomeType).Property = x

   -- 必須の書き方
   local casted = someValue :: SomeType
   casted.Property = x
   ```

   これに限らず、**行頭が `(` で始まる文を作らない。**
3. **モジュールの読み込み契約を壊さない。** 具体的には:
   - ファイル先頭の `--!strict` を維持する
   - `require` のパス（`ReplicatedStorage.Shared.*` 等）を変更しない
   - ファイル末尾の `return <module>` を維持する（分岐内 return にしない）
   - 新しい `require` を追加して循環参照を作らない（server → shared の一方向を維持）
4. **状態遷移表・guard の構造を変更しない。** 診断ログの追加は可（追加する場合はその旨を報告に明記する）。
5. **実施していない検証を実施したと書かない。** 「実機で確認」「Studio で動作確認」「照合済み」といった検証語彙を、自分が実行していない検証に使わない。**あなたのサンドボックスから Roblox Studio は触れない。実機検証はこちらが行う。**
6. **sha256 は実測値のみ報告する。** 推定値・過去値を書かない。
7. 修正は最小差分にする。リファクタ・整形・命名変更を混ぜない。

## commands（実行してよいコマンド）

```powershell
# 決定論ビルド（まず一時パスへ。正本 artifacts/build/MVP.rbxlx はここでは上書きしない）
rojo build mvp.project.json --output "$env:TEMP\MVP_h0XX_1.rbxlx"
rojo build mvp.project.json --output "$env:TEMP\MVP_h0XX_2.rbxlx"
Get-FileHash -Algorithm SHA256 "$env:TEMP\MVP_h0XX_1.rbxlx"
Get-FileHash -Algorithm SHA256 "$env:TEMP\MVP_h0XX_2.rbxlx"

# 自己検査
git status --short
git diff --check
git grep -n -E "^[[:space:]]*\(" -- "src/mvp/**/*.luau"
```

## acceptance（各項目の判定に使った実出力を報告へ貼る）

- `H0XX-FIX-001`: 上記 objective の観測条件を満たす修正が `<file>:<line>` に入っている
- `H0XX-DET-001`: 2 回ビルドの sha256 が一致（両方の実値を報告）
- `H0XX-SYNTAX-001`: `git grep -n -E "^[[:space:]]*\(" -- "src/mvp/**/*.luau"` の結果が **0 件**（実出力を貼る。0 件なら「0 件」と明記）
- `H0XX-DATA-001`: 差分に新規の数値リテラルが 0 個（`diff` 内の数値をすべて列挙し、それぞれが DATA ID 由来か行番号で示す）
- `H0XX-SCOPE-001`: `git status --short` の変更が inScope のみ（実出力を貼る）

## evidence（報告に必ず含める）

1. `git status --short` の**生出力**
2. `git diff` の全文（または変更した関数の前後）
3. sha256 の実値 2 つ
4. `git grep` の実出力
5. 追加した診断ログがあれば、その出力形式（1 行の例）

## execution

model `gpt-5.6-sol` / reasoningEffort `high` / sandbox `workspace-write` / approvalPolicy `never` / network `false`

## rollback

`git checkout -- src/mvp/server/` で baseline commit `<HEAD の実値>` の状態へ戻す。

## 停止条件

- dataIds に無い数値が必要になったら **BLOCKED として停止**し、何が必要かを報告する。推測で埋めない。
- outOfScope を変更しないと objective を満たせないなら **BLOCKED として停止**する。こっそり広げない。
- 症状が根本原因の記述と噛み合わないと判断したら、修正せず**その旨を報告して停止**する。
````

---

## 4. ハングさせない起動方法と、ハングの見分け方

### 4-1. 起動（標準入力を必ず閉じる）

**Git Bash（推奨。クォートが素直）**

```bash
cd /c/Users/Administrator/Documents/GitHub/SpinOut
codex exec --model gpt-5.6-sol -c model_reasoning_effort=high \
  --sandbox workspace-write --skip-git-repo-check \
  "$(cat docs/handoffs/SPINOUT-H-0XX.md)" < /dev/null \
  > docs/handoffs/out/H-0XX.log 2>&1
```

**PowerShell（`<` によるリダイレクトが使えないので空ファイルを渡す）**

```powershell
Set-Location C:\Users\Administrator\Documents\GitHub\SpinOut
New-Item -ItemType Directory -Force docs\handoffs\out | Out-Null
Set-Content -Path "$env:TEMP\empty.txt" -Value "" -NoNewline -Encoding utf8

$prompt = Get-Content -Raw docs\handoffs\SPINOUT-H-0XX.md
$argList = @(
  'exec','--model','gpt-5.6-sol','-c','model_reasoning_effort=high',
  '--sandbox','workspace-write','--skip-git-repo-check', $prompt
)
Start-Process -FilePath codex -ArgumentList $argList `
  -RedirectStandardInput  "$env:TEMP\empty.txt" `
  -RedirectStandardOutput "docs\handoffs\out\H-0XX.log" `
  -RedirectStandardError  "docs\handoffs\out\H-0XX.err" `
  -NoNewWindow
```

3つのポイント:

- **標準入力を閉じる**（`< /dev/null` / 空ファイル）。これが無いと入力待ちで永久停止します。バックグラウンドだと止まっていることに気づけません。
- **モデルは起動ごとにコマンドラインで明示する。** 設定ファイルの既定値に頼ると、後から「どのモデルが書いたか」を再構成できません。
- **プロンプトはファイルに書いて渡す。** クォート地獄を避けられ、投げた内容がそのまま記録に残ります（`docs/handoffs/` が正本）。

### 4-2. ハングの見分け方

**ポーリングはしません**（完了通知で受けます）。ただし長時間の実装では、節目で 1 回だけ「進んでいるか」を確認します。**出力サイズと CPU 時間の両方が伸びていなければハングを疑う**、が判定基準です。

```powershell
# 2回、数分あけて実行し、両方の値を比較する
$p = Get-Process codex -ErrorAction SilentlyContinue
"{0}  cpu={1}  log={2} bytes" -f (Get-Date -f HH:mm:ss), $p.CPU, (Get-Item docs\handoffs\out\H-0XX.log).Length
```

- ログサイズが伸びている → 正常
- ログは止まっているが CPU が回っている → 思考中。待つ
- **どちらも止まっている → ハング。** 落として、標準入力を閉じているか確認してから投げ直す

固定 `sleep` で「たぶん終わってるだろう」と待つのはやめます。成立条件（プロセス終了・ログの伸長）で判定します。

---

## 5. 投げたあとに、こちらで確認すること

**大原則: 実装は委譲してよいが、検証は委譲しません。** 実装側の報告は要約であって証拠ではありません。実運用で「実施していない検証を実施した」と報告された事例が複数あります。争わず、報告は参考にとどめて、以下は自分のツール実行で確認します。

### 5.1 受領直後（5分）

```powershell
cd C:\Users\Administrator\Documents\GitHub\SpinOut
git status --short          # 報告と突き合わせる。inScope 外があれば即差し戻し
git diff                    # 中身を自分の目で読む（要約を信じない）
git diff --stat
```

見る点:

- [ ] 変更ファイルが inScope のみか。`src/pa/**`、`docs/*.md`、`mvp.project.json`、`.gitattributes` が入っていないか
- [ ] **新規の数値リテラルが入っていないか。** `Config` は DATA ID の転記表なので、`MovementService` に生値が現れたら違反
- [ ] 状態遷移表・guard の構造が変わっていないか（診断ログの追加は可）
- [ ] リファクタや整形が混ざっていないか（混ざると差分が読めなくなる）

### 5.2 モジュール読み込みの実証 ← あなたが踏んだ2つ目への対策

**まず静的に全数検出**（曖昧構文は grep で確実に見つかります）:

```powershell
git grep -n -E "^[[:space:]]*\(" -- "src/mvp/**/*.luau"
```

0 件でなければ、その行を `local casted = x :: T` の形へ直させます（自分で直してもよい。1行の機械的変換です）。

**次に実際に読み込ませる。** 前述のとおり `rojo build` は Luau をパースしないので、build 成功は読み込み可能の証明になりません。Studio で全モジュールに `require` を通します（Studio MCP のサーバー実行）:

```lua
local fails = {}
local roots = { game.ServerScriptService.Server, game.ReplicatedStorage.Shared }
for _, root in ipairs(roots) do
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("ModuleScript") then
            local ok, err = pcall(require, d)
            if not ok then
                table.insert(fails, d:GetFullName() .. " :: " .. tostring(err))
            end
        end
    end
end
return (#fails == 0) and "ALL MODULES LOADED" or table.concat(fails, "\n")
```

クライアント側モジュール（`StarterPlayer.StarterPlayerScripts.Client`）は同じ処理をクライアント実行側で回します。これが通って初めて「モジュールが読み込める」と言えます。

### 5.3 決定論ビルド（3回目は自分で回す）

```powershell
# Studio は閉じてから。開いていると place へ自動保存で書き戻し、sha が変わる
rojo build mvp.project.json --output "$env:TEMP\MVP_verify.rbxlx"
Get-FileHash -Algorithm SHA256 "$env:TEMP\MVP_verify.rbxlx"
```

- [ ] Codex 報告の 2 つの sha と、自分で回した 3 回目が一致するか
- [ ] 一致しないなら、生成に時刻・順序が混ざっているか、Studio が開いたままだったか
- [ ] 正本 `artifacts/build/MVP.rbxlx` を更新するのは、一致を確認したあと。`.gitattributes` で `*.rbxlx` は binary 指定済み（CRLF 正規化で sha が壊れる事故が実際に起きています）

### 5.4 実機検証（移動処理は「節目」に該当するので必須）

移動は「入力から状態が動く経路」そのものです。ここは飛ばせません。そして**重要な制約**があります。

> **MCP の合成キー入力は `UserInputService` / `ContextActionService` に届きません。** ゲームの操作系はこれらに載っているので、合成入力ではプレイヤー操作を一切再現できません。実操作の再現には OS レベルの入力注入が必要で、対象ウィンドウが実際に前面にある必要があります。

役割分担:

| 目的 | 手段 |
|---|---|
| 状態の読み取り・モジュール require の確認 | Studio MCP の Luau 実行 |
| サーバーログの回収 | Studio MCP のコンソール取得 |
| **W/A/S/D などの実操作** | **OS 入力注入** `skills\claude-roblox-mvp-buildout\scripts\studio_input.ps1` |
| セッション構築（server + N client） | `scripts\studio_session.ps1` |

実機セッションを立てる前に `references\studio-automation.md` を読んでください（前面制御・ダイアログ・プロセス待ちを知らずに始めると、原因不明の無反応で時間が溶けます）。待ちは固定 sleep ではなく、プロセス数・ウィンドウタイトル・MCP のインスタンス一覧など**成立条件のループ**で行います。

観測の主軸は画面ではなく**サーバーの構造化ログ**に置きます。画面キャプチャは「何かおかしい」までしか言えませんが、

```
move p=-1 dt=0.0167 intent=(0.00,0.00,1.00) accel=42.0 vBefore=0.000 vAfter=0.000 snap=applied pos=(0.0,3.0,-24.0)
```

のような 1 行は、どの判定がどの値で成立したかを一意に決めます。

### 5.5 移動処理でまず疑う場所（実測済みの型）

修正後も直っていない／別の症状が出たときは、当て推量で追加修正せず、以下を実測ログで潰します。

1. **停止閾値スナップが加速を殺している**（最有力）。「一定値未満の速度は 0 に丸める」を毎ステップ無条件に適用すると、`(加速度 - 抵抗) / フレームレート` が停止閾値未満のとき**永久に発進できません**。`MovementService` は `stopSpeed` / `passiveDrag` / `baseAcceleration` を持っているので、この組み合わせが成立し得ます。対処はスナップを「有効な加速入力が無いとき」に限定すること。値ではなく**関係**で確認します。
2. **速度は更新しているが位置を積分していない。** 速度ログは正常値なのにキャラクタが動かず、やがて落下して消える、という形で出ます。
3. **step の駆動が失われている。** `Heartbeat` → `MatchService:step` → `MovementService:step` の鎖のどこかが切れると、各関数は単体で正しいまま何も起きません。
4. **テスト環境のプレイヤー識別子が負数。** Studio のローカルテストセッションは `-1, -2, -3...` を割り当てます。`> 0` を前提にした検証は**テスト環境でだけ全滅**します。識別子の妥当性は「有限な非ゼロ整数」で表現します。
5. **通信層が数値キー辞書のキーを文字列へ変換する。** 「サーバーは送っているのにクライアントが反映しない、エラーも出ない」形の症状ならこれ。本番でも起きます。

**症状を数えて原因を数えないでください。** 症状が 2 つ見えても根本原因が 1 つのことがあります。1 つ直して片方が消えたら、もう片方も再実測してから追加修正を判断します。逆に、**環境固有の挙動を実装欠陥と決めつけない**ことも同じくらい重要です。「不可解な場外判定」が、実は入力を入れっぱなしにして本当に場外へ出ていただけ、という事例があります（推測のまま「修正」していたら正しい判定を壊していました）。

### 5.6 記録と commit

- [ ] 投げたプロンプト本文を `docs/handoffs/SPINOUT-H-0XX.md` に残す（正本）
- [ ] Codex の最終メッセージを `docs/handoffs/out/` に改変せず保存
- [ ] 実測値（sha256、実機ログの実値、判定 PASS/FAIL）を `docs/evidence/SPINOUT-H-0XX*.md` に記録。既存の evidence 形式に合わせる
- [ ] 自分が下した運行判断は `DECISIONS.md` へ
- [ ] **承認可になった時点で commit する。** 溜めると baseline が commit hash で一意に決まらず、rollback 契約が空文になります。**修正・文書・証跡は別 commit に分けます**
- [ ] 中核サービスの修正なので、余力があれば**別の Codex session による読み取り専用の独立照合**を 1 巡入れる（実装した session に自己レビューさせても、自分の前提を疑えないので意味がありません）

---

## 6. 報告に出たら「不採用」と記録する表現

Codex のサンドボックスから Roblox Studio は触れません。したがって以下は**実施不可能な検証の自己申告**であり、記録へ「不採用」と残して、こちらの実測結果を採ります（訂正を求めるやり取りは費用に見合いません）。

- 「Studio で動作確認しました」「実機で確認済み」「Play して問題ないことを確認」
- 「別セッションで独立照合済み」（発注していないなら虚偽）
- sha256 の値があるのに、ビルドコマンドの実出力が報告に無い
- 「テストは全て通りました」だけで、実行コマンドと生出力が無い

同じ基準は自分にも適用します。こちらの範囲指定ミスや実測値の誤記も起こります。そのときは成果物を歪めて辻褄を合わせず、**契約側（プロンプト）を訂正して記録します。**

---

## 付録: 最短の実行順

1. Studio で症状を実測 → 実測値だけで症状を書く
2. 原因が絞れないなら §2（読み取り専用調査）を投げる → 「確定できない」なら診断ログを入れて再実測
3. §3 のプロンプトを `docs/handoffs/SPINOUT-H-0XX.md` に保存
4. §4 の起動コマンドで投げる（**標準入力を閉じる**）。完了通知で受ける
5. §5.1 差分を自分で読む → §5.2 grep 0 件＋Studio で require 全通し → §5.3 3回目の sha
6. §5.4 OS 入力注入で実操作し、サーバー構造化ログの実値で確認
7. §5.6 evidence 記録 → commit（修正／文書／証跡を分ける）

外部公開（Publish）は所有者の専権です。ビルドが通っても公開しません。
