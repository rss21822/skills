# 20Hz スナップショットが届いているのに HUD が一度も更新されない — 切り分け手順

## 0. 最初に整理すべきこと: 3つの別々の命題が混ざっている

いま「確認済み」と言えるのは (a) だけです。

| # | 命題 | 検証済みか |
|---|---|---|
| a | **サーバの内部状態**の phase が `Active` である | 済み（ログで確認） |
| b | **実際に送信した payload** の `phase` フィールドが `Active` である | 未検証 |
| c | **クライアントが受信した** payload の `phase` が `"Active"` と `==` になる | 未検証 |
| d | クライアントの HUD 更新コードが**そもそも実行されている** | 未検証 |
| e | 書き換えた GUI インスタンスが**画面に出ている個体**である | 未検証 |

(a) から (b) は自動的には導けません。スナップショット構築側が別のフィールド名を読んでいる（`self.phase` / `state.currentPhase` / `Phase` 大文字）、あるいはログが状態オブジェクトを読み、payload はビルダーが別途組んでいる、というだけで (a) は真・(b) は偽になります。この取り違えが、この症状で最も多い原因のひとつです。

**「サーバのログで送信成功」も同様に弱い証拠です。** その print が `FireClient` の戻りや `pcall` の結果と結びついていないなら、証明しているのは「送ろうとした」だけです。

---

## 1. 「エラーも警告も一切出ない」という手掛かりの使い方

これは強力な絞り込み条件です。Luau のランタイムエラーはクライアントでも必ず Output に出ます（`OnClientEvent` ハンドラ内のエラーも出ます）。したがって**エラーが本当にゼロなら**、原因は次の 3 バケットのいずれかに限定されます。

- **B1: ハンドラが一度も呼ばれていない**（購読が成立していない／別インスタンスを購読している／スクリプトが起動していない）
- **B2: ハンドラは呼ばれているが `phase == "Active"` が常に false**（値が nil・型違い・キー名違い）
- **B3: 条件は true だが、書き込み先が画面に出ていない個体**（Destroy 済み・StarterGui のテンプレート・`Enabled=false`・サイズ0）

これ以外（循環参照テーブル、nil インデックス、`FireClient` に Player 以外を渡す等）は**必ずエラーになる**ので、この時点で候補から外せます。

ただし前提として1つ落とし穴があります。

> **「警告が出ていない」の前に、クライアントの Output が本当に見えているかを確認してください。**
> - Studio の Output ウィンドウにはクライアント/サーバのコンテキストフィルタがあります。
> - `Start Server + N Players`（Team Test）ではクライアント側の出力は**各クライアントウィンドウ側**に出ます。サーバウィンドウだけ見ていると、クライアントのエラーも警告も見えません。
> - `WaitForChild` がタイムアウト無しで永久待機した場合の `Infinite yield possible on '...'` は**警告で、クライアント側にしか出ません**。これを見落としているケースが非常に多いです。

**Step 0（30秒）**: クライアント LocalScript の最上部、`WaitForChild` より前に `print("[NET/C] alive")` を1行入れ、それが見えることを確認する。見えないなら、以降の全ての観測は無効です。

---

## 2. 決定打になる一点測定（パイプラインの中点で二分する）

パイプラインは
`サーバ状態 → payload 構築 → FireClient → シリアライズ → クライアント受信 → 条件判定 → GUI 書き込み → 画面`
の 7 ホップです。端から順に追うより、**受信ハンドラの先頭に無条件 print を置く**のが最も情報量が大きい。ここ1点で上流/下流にきれいに割れます。

```lua
remote.OnClientEvent:Connect(function(payload)
    print("[NET/C] RAW", typeof(payload), payload)   -- 条件分岐より前、無条件で
    ...
end)
```

- **1行も出ない → 上流の問題（第3節へ）**
- **出るが phase が期待と違う → 中流（第4節へ）**
- **phase が `Active` で出るのに HUD が変わらない → 下流（第5節へ）**

---

## 3. 受信ゼロだった場合（上流）

### 3-1. クライアントスクリプトが実行される場所にあるか
`LocalScript` が実行されるのは以下の配下のみです。それ以外（`Workspace`、`ReplicatedStorage`、`ServerScriptService`、`Lighting` 等）に置いても**何も起きず、エラーも出ません**。

- `StarterPlayer > StarterPlayerScripts`
- `StarterPlayer > StarterCharacterScripts`
- `StarterGui`（→ PlayerGui に複製されて実行）
- `Player > Backpack`（Tool 経由）
- `ReplicatedFirst`

あわせて確認: `Disabled = true` になっていないか、`Script` の `RunContext` が `Legacy` のまま Workspace に置かれていないか、Rojo 同期で**同名スクリプトが2個**でき片方だけ編集していないか。

### 3-2. RemoteEvent がクライアントに複製されているか
`RemoteEvent` が `ServerStorage` / `ServerScriptService` 配下にあると、クライアントからは存在しません。サーバ側の `FireClient` は通り、クライアントは何も受け取らず、**エラーは出ません**（出るのは `WaitForChild` の infinite yield 警告だけ）。`ReplicatedStorage` 配下にあることを確認してください。

### 3-3. 送信側と受信側が「同じインスタンス」か
名前一致ではなく**同一性**を確認します。ビルド時に GUID 属性を打って両側で突き合わせるのが確実です。

```lua
-- サーバ（remote 生成直後に1回）
local HttpService = game:GetService("HttpService")
remote:SetAttribute("BuildId", HttpService:GenerateGUID(false))
print("[NET/S] remote =", remote:GetFullName(), "BuildId =", remote:GetAttribute("BuildId"))
```

```lua
-- クライアント
print("[NET/C] bound  =", remote:GetFullName(), "BuildId =", remote:GetAttribute("BuildId"))
```

BuildId が nil / 不一致なら、**同名の別インスタンスを掴んでいます**。よくある発生源:
- 旧ビルドの残骸が `ReplicatedStorage` に残り、サーバが `Instance.new` で作った新しい方を使っている
- Rojo 同期で `Remotes` フォルダが二重化した
- 名前の末尾に空白や全角文字が混入した

両側で重複スキャンをかけてください。

```lua
for _, root in ipairs({game:GetService("ReplicatedStorage"), workspace, game:GetService("ReplicatedFirst")}) do
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("RemoteEvent") or d:IsA("UnreliableRemoteEvent") then
            print("[SCAN]", d.ClassName, d:GetFullName())
        end
    end
end
```

### 3-4. 送信先の Player が本当に観測中のクライアントか
`FireClient(player, payload)` の `player` を**毎回ログに出す**。試合開始時に作ったプレイヤーリストへ配信していて、後から入った（あるいはロール未割り当ての）プレイヤーが対象外、というパターンが典型です。Studio のマルチクライアントテストでは、**見ているウィンドウと送信先が別プレイヤー**という単純な取り違えも起きます。

`FireAllClients` を使っているなら送信先の取り違えは消えるので、切り分けとして一時的に `FireAllClients` に変えてみるのも有効です。

### 3-5. UnreliableRemoteEvent を使っていないか
20Hz スナップショット用に `UnreliableRemoteEvent` を選んでいる場合、**1回あたりのペイロードサイズ上限（約 900 バイト）**があります。全プレイヤーのスコアとバランスの辞書を毎回丸ごと積むと簡単に超えます。切り分けとして通常の `RemoteEvent` に差し替えて再現するか確認してください。

### 3-6. 受信側の書き方
- `OnClientEvent:Wait()` をループで回している → イテレーション間のイベントを取りこぼす。`:Connect` を使う。
- `:Once` になっていて2回目以降来ない（ただし「一度も」の症状とは合わない）。
- 購読前に `WaitForChild` 以外の長い yield（`repeat task.wait() until ...`）が入っていて、条件が永久に満たされていない。

参考: クライアントにリモートは存在するが購読が一度も張られていない場合、エンジンはイベントをキューし、溢れると Output に警告を出すことがあります。**その警告すら出ていない**なら、「クライアント側にリモートが存在しない（3-2/3-3）」か「そもそもクライアントの Output を見ていない（Step 0）」の可能性が高い、という推論に使えます。

---

## 4. 受信はあるが phase が合わない場合（中流）

### 4-1. 値と型を必ず両方出す
`nil == "Active"` は false ですがエラーにはなりません。無言の失敗の典型です。

```lua
local phase = (type(payload) == "table") and payload.phase or nil
print(string.format("[NET/C] phase=%s type=%s eq=%s",
    tostring(phase), typeof(phase), tostring(phase == "Active")))
```

これで一気に判別できるもの:
- `nil` → **キー名の不一致**（`phase` vs `Phase` vs `gamePhase`）、または payload 構築側が別フィールドを詰めている
- `number` → サーバが enum を数値で持っていて、クライアントが文字列比較している（`Phase.Active = 2` 等）
- `"ACTIVE"` / `"Active "` → 大文字小文字・空白の不一致
- `table` / `userdata` → enum オブジェクトをそのまま入れている

### 4-2. Roblox のテーブルシリアライズの落とし穴（今回の payload 形状に直撃）
「プレイヤーIDをキーにした辞書」は、この症状で最も踏まれやすい地雷です。

- **混在テーブルは非サポート**。同一テーブル内に文字列キーと数値キーが同居していると、silently データが落ちます（配列部だけ送られる等）。`{phase = "Active", [12345] = {...}}` のような形は危険です。
- **数値キー（UserId）の辞書は疎配列とみなされる境界にあり**、破損・欠落の原因になります。**必ず `tostring(userId)` で文字列キーに統一**してください。これは Roblox の実務上の定石です。
- **nil 値は穴になる**。配列に nil が混じると以降が切れます。
- **クライアントに複製されていない Instance 参照は nil になる**（エラーなし）。`ServerStorage` 配下のオブジェクトを payload に入れていると静かに消えます。
- メタテーブルは保持されません。関数・スレッドは送れません。循環参照はエラーになります（＝エラーが出ていない以上、循環はない）。

**最短の切り分け**: 一時的にペイロードを最小化して送る。

```lua
remote:FireClient(player, { phase = "Active" })   -- これだけ
```

これで HUD が出るなら、**原因はペイロードの形（辞書のキー型 / 混在テーブル）**で確定です。出ないなら上流（第3節）に戻ります。

### 4-3. サーバ側で payload そのものを検査する
状態オブジェクトではなく、**FireClient に渡す直前のテーブル**をログします。`JSONEncode` を通すのが手軽な形状チェックになります（混在テーブルや数値キーで失敗・変形するので、それ自体がシグナルです）。

```lua
local ok, json = pcall(function() return HttpService:JSONEncode(payload) end)
print("[NET/S] to=", player.Name, player.UserId,
      "phase=", tostring(payload.phase), typeof(payload.phase),
      "jsonOK=", ok, "bytes=", ok and #json or json)
local sent, err = pcall(remote.FireClient, remote, player, payload)
if not sent then warn("[NET/S] FireClient FAILED:", err) end
```

---

## 5. phase は `Active` で来ているのに HUD が変わらない場合（下流）

### 5-1. 書き込み先インスタンスの同一性
Destroy 済み（`Parent == nil`）のインスタンスにプロパティを書いても**エラーは出ず、画面も変わりません**。

```lua
print("[HUD] target =", label:GetFullName(),
      "| Parent =", label.Parent,
      "| PlayerGui配下 =", label:IsDescendantOf(player:WaitForChild("PlayerGui")))
```

典型的な原因:
- **`StarterGui` のテンプレートを直接書き換えている**。画面に出ているのは `PlayerGui` 内の複製なので、テンプレートを触っても何も起きません。
- **`ScreenGui.ResetOnSpawn` が既定の true** のため、リスポーン時に `PlayerGui` の GUI が破棄・再複製され、スクリプトが保持している参照が死んだ個体を指している。`ResetOnSpawn = false` にするか、`CharacterAdded` で参照を取り直す。
- `PlayerGui` が用意される前に参照を取得している。

### 5-2. 「更新されているが見えない」を排除する
判定ロジックとは無関係に、起動時に強制的に目立たせてみます。

```lua
local gui = player.PlayerGui:WaitForChild("HUD")
gui.Enabled, gui.DisplayOrder = true, 100
local f = gui:FindFirstChild("Root", true)
f.Visible, f.BackgroundTransparency = true, 0
f.BackgroundColor3 = Color3.new(1, 0, 0)
f.Size, f.Position = UDim2.fromScale(0.5, 0.2), UDim2.fromScale(0.25, 0.4)
```

これで赤い箱すら出ないなら、ネットワークではなく **GUI パスの問題**で確定します（`ScreenGui.Enabled=false`、親フレームが不可視、`Size` が 0、画面外配置、`ZIndex`/`DisplayOrder` で背面、TextTransparency 1 など）。

### 5-3. エラーを握り潰していないか
`pcall` で囲んだ中で失敗している、独自ロガーがテーブルに溜めるだけで出力していない、`task.spawn` の中で戻り値を捨てている——これらは「エラーが出ない」を人工的に作ります。クライアント側の `pcall` を一時的に外して再現してください。

### 5-4. Studio 特有
実行中にスクリプトを編集しても、**すでに走っているインスタンスには反映されません**。修正が効かないように見えたら、必ず停止 → 再生してください。

---

## 6. 仮説の優先順位（「一度も」「無言」への適合度順）

| 順位 | 仮説 | 症状適合 | 判別する1手 |
|---|---|---|---|
| 1 | クライアントスクリプトが起動していない／購読前に永久 yield | 高（無言・一度も） | 最上部の `print` と `WaitForChild(name, 5)` |
| 2 | 送信側と受信側が別の RemoteEvent インスタンス（同名重複・server 側配置） | 高 | `BuildId` 属性の突き合わせ＋重複スキャン |
| 3 | payload の `phase` が nil（状態のフィールド名と構築側の不一致） | 高 | FireClient 直前で payload 自体をログ |
| 4 | クライアントの Output を見ていない（サーバウィンドウのみ観測） | 高 | クライアント側 `print` が見えるか |
| 5 | UserId 数値キー／混在テーブルによるシリアライズ破損 | 中〜高 | `{phase="Active"}` だけ送って再現 |
| 6 | GUI テンプレート（StarterGui）や Destroy 済みインスタンスへの書き込み | 中 | `GetFullName()` と `Parent` をログ |
| 7 | 送信先 Player が観測中のクライアントではない | 中 | 送信先 Name/UserId を毎回ログ／`FireAllClients` に一時変更 |
| 8 | phase の型・表記ゆれ（数値 enum、大文字小文字） | 中 | `typeof(phase)` と `%q` 出力 |
| 9 | HUD は更新されているが不可視（Enabled/Size/ZIndex） | 中 | 赤ボックス強制表示 |
| 10 | UnreliableRemoteEvent のサイズ上限超過 | 低〜中 | RemoteEvent に差し替え |

---

## 7. まとめて貼れる計測コード

### サーバ側

```lua
local HttpService = game:GetService("HttpService")
local seq = 0

remote:SetAttribute("BuildId", HttpService:GenerateGUID(false))
print("[NET/S] remote =", remote:GetFullName(), "BuildId =", remote:GetAttribute("BuildId"))

local function sendSnapshot(player, payload)
    seq += 1
    payload.__seq = seq
    if seq % 20 == 0 then                       -- 20Hz なので毎秒1行
        local ok, json = pcall(function() return HttpService:JSONEncode(payload) end)
        print(string.format("[NET/S] seq=%d to=%s(%d) phase=%s(%s) jsonOK=%s bytes=%s",
            seq, player.Name, player.UserId,
            tostring(payload.phase), typeof(payload.phase),
            tostring(ok), ok and tostring(#json) or "n/a"))
    end
    local sent, err = pcall(remote.FireClient, remote, player, payload)
    if not sent then warn("[NET/S] FireClient FAILED:", err) end
end
```

### クライアント側（StarterPlayerScripts の LocalScript）

```lua
print("[NET/C] alive")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer

local remote = ReplicatedStorage:WaitForChild("StateRemote", 10)
if not remote then
    warn("[NET/C] StateRemote が 10 秒以内に見つからない → 配置/複製の問題")
    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d:IsA("RemoteEvent") then print("[NET/C] visible:", d:GetFullName()) end
    end
    return
end
print("[NET/C] bound =", remote:GetFullName(), "BuildId =", remote:GetAttribute("BuildId"))

local received = 0
remote.OnClientEvent:Connect(function(payload)
    received += 1
    local phase = (type(payload) == "table") and payload.phase or nil
    if received <= 3 or received % 20 == 0 then
        print(string.format("[NET/C] recv#%d payloadType=%s phase=%s phaseType=%s eqActive=%s",
            received, typeof(payload), tostring(phase), typeof(phase), tostring(phase == "Active")))
    end
end)

task.delay(3, function()
    if received == 0 then
        warn("[NET/C] 3 秒間 1 件も受信していない → 上流（配線/送信先/複製）の問題")
    end
end)
```

この2つを入れれば、次の1回のテストで「上流／中流／下流」のどこで切れているかが確定します。

---

## 8. 再発防止 — 「無言の失敗」を作らない

今回の本質的な問題は、バグそのものより**システムが「何も受け取っていない」を報告する手段を持っていない**ことです。沈黙が「正常」と「全断」の両方を意味してしまうため、切り分けに時間がかかります。

- **受信ウォッチドッグを常設する**。起動後 N 秒受信ゼロなら必ず `warn`。上の `task.delay` をそのまま製品コードに残す価値があります。
- **phase の変化点は必ず 1 行ログを出す**（毎フレームではなく遷移時のみ）。「一度も更新されない」が即座に「一度も遷移ログが出ない」として観測できます。
- **Remote の取得を 1 つのモジュール（`Net.lua`）に集約**し、名前文字列を両側に散らさない。同名別インスタンス問題が構造的に消えます。
- **送信直前に payload バリデータを通す**。キーは string のみ、値は number/string/boolean/table のみ、と検査して違反を `warn`。UserId は必ず `tostring()` して詰める規約にする。
- **20Hz で全プレイヤーの辞書を毎回フルで送らない**。変化があったプレイヤーの差分のみにすれば、帯域もサイズ上限問題も同時に解消します。
