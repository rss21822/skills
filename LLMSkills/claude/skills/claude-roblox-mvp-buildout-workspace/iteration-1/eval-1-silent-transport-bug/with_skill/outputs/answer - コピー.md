# 「サーバーは送っているのにクライアントの HUD が一度も更新されない」の切り分け

結論から言うと、**あなたの症状は実測済みの platform 挙動と形が一致しています**。ただしそれを前提に直しにいくのは順序が逆なので、まず一撃で送信側/受信側を分ける計測を打ってください。当て推量で直すと、正しいコードを壊して症状だけ移動します。

---

## 0. 先に押さえるべき2つの事実

### (1)「送信成功」は「届いた」を証明していない

サーバーのログが証明しているのは、多くの場合「`FireAllClients` を呼んだ」ことだけです。Roblox のリモートは送信側で例外を投げずに通ってしまう経路があり、送信ログは受信の証拠になりません。**送信側のログと受信側の実測は別の証拠として集めてください。**

### (2) エラーが一切出ないのは「情報」であって「手がかりが無い」ではない

例外が発生していないということは、どこかで **正常系として早期 return されている** という意味です。落ちる場所は構造的に次のどれかに絞れます。

| 沈黙の型 | 起きていること |
|---|---|
| 受信ハンドラに到達していない | リスナーが別インスタンスに張られている／LocalScript が実行されない位置にある |
| 到達しているが検証層が false を返して黙って捨てている | 検証が `return` するだけで warn しない実装 |
| 検証は通るが `phase` の比較が成立しない | 値の型・表現が送受で食い違っている |
| 全部通るが画面に出ない | GUI インスタンスの掴み直し／可視性 |

「エラーも警告も出ない」という条件は、**上の4つ以外を実質的に消してくれています**。ここを順に潰すのが最短です。

---

## 1. 最有力仮説（ただし確定させてから直す)

**Roblox のリモート直列化は、数値をキーに持つ辞書のキーを文字列へ変換します。**

```
送信側: scores = { [-1] = 0, [-2] = 0 }     -- キーは number
受信側: scores = { ["-1"] = 0, ["-2"] = 0 } -- キーは string
```

配列の添字と、テーブル内の「値」は変換されません。変換されるのは**辞書のキーだけ**です。

あなたの payload は「プレイヤー ID をキーにしたスコアとバランスの辞書」。まさにこの形です。そして症状も一致します。

- サーバーは送信に成功している（実際に成功している）
- クライアントが一切反映しない
- **エラーが出ない**（受信側の検証が黙って捨てている）
- HUD は初期状態のまま

**これは本番でも起きます。** テスト環境固有ではありません。送信側と受信側で同じ検証ロジックを共有している設計だと、**受信側でだけ検証が落ちます**。送信側では number キーなので通り、受信側では string キーになって落ちる。コードは1行も間違っていないのに、片側だけ落ちる。

**静的検査で見えない理由**: 送信側・受信側・検証ロジックのどれも単体では正しいからです。変換は言語にもコードにも現れない transport の性質で、読んで見つけるのは人にも AI にも困難です。

### 併発しうる第2の罠（ローカルテストのみ）

Studio のローカルテストセッションが割り当てるプレイヤー識別子は **負数（-1, -2, -3, …）** です。本番の識別子は正数なので、`userId > 0` を前提にした検証は**テスト環境でだけ全滅**します。

上のキー文字列化と重なると2段で落ちます。`tonumber("-1")` は通っても `> 0` で落ちる。**症状の数と原因の数は一致しません。** 1つ直して片方が消えても、もう片方は再実測してから追加修正を判断してください。

---

## 2. 切り分け手順（この順序を守る）

### ステップ 0: 症状を実測値だけで書き直す

「HUD が更新されない」ではなく「1.5 秒の観測窓で `OnClientEvent` が n 回発火し、`scores` のキーの `typeof` が X だった」の形にします。推測を症状に混ぜると、以後の修正がその推測を前提に組まれてしまいます。

### ステップ 1: クライアント側に「生の受信」プローブを張る（最重要）

**検証層を通す前の生データを見ます。** これで送信側と受信側のどちらが悪いかが一撃で決まります。Studio MCP の `execute_luau` を `datamodel_type: Client` で実行してください（実行前に `Players.LocalPlayer` でどのクライアントに入ったかを確認）。

```lua
-- Client DataModel で実行
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remote = ReplicatedStorage:FindFirstChild("<RemoteEvent名>", true)
if not remote then return "REMOTE_NOT_FOUND" end

local got, count = nil, 0
local conn = remote.OnClientEvent:Connect(function(payload)
    count += 1
    if got == nil then got = payload end
end)
task.wait(1.5)
conn:Disconnect()

if got == nil then
    return string.format("NO_PACKET recv=%d remote=%s", count, remote:GetFullName())
end

local out = {
    string.format("recv=%d/1.5s payload_type=%s", count, typeof(got)),
    string.format("phase=[%s] phase_type=%s", tostring(got.phase), typeof(got.phase)),
}
for k, v in pairs(got.scores or {}) do
    -- 値だけでなく「型」を必ず出す。型の食い違いが原因のことが多い
    table.insert(out, string.format("scores key=[%s] keytype=%s valtype=%s",
        tostring(k), typeof(k), typeof(v)))
end
for k in pairs(got.balance or {}) do
    table.insert(out, string.format("balance key=[%s] keytype=%s", tostring(k), typeof(k)))
end
return table.concat(out, "\n")
```

20Hz なら 1.5 秒で `recv` は 30 前後になるはずです。

### ステップ 2: 結果で分岐する

| プローブの結果 | 確定すること | 次の手 |
|---|---|---|
| `REMOTE_NOT_FOUND` / `recv=0` | **受信ハンドラに到達していない。** 通信より手前の問題 | §3-A へ |
| `recv≈30`、`keytype=string` | **キー文字列化が確定。** 最有力仮説どおり | §4 の修正へ |
| `recv≈30`、`keytype=number`、`phase` の値か型が想定と違う | phase 比較の食い違い | §3-B へ |
| `recv≈30`、すべて想定どおり | **受信は正常。欠陥は受信より後**（検証層・UI 更新・GUI 可視性） | §3-C へ |

**ここまでは一切コードを直しません。** 直すのはステップ 3 以降です。

### ステップ 3: 根本原因が一意に決まらないなら、診断ログを入れて再実測する

コードを読むだけで原因が一意に決まるなら修正へ。**決まらないなら「決まらない」と認めて、診断ログを入れてください。** 推測で修正しないこと。

診断ログの書き方には条件があります。

- **抑制なしで 1 行**（`if DEBUG` で消えるものは診断の役に立ちません）
- **実際に判定に使った値そのもの**を出す。「検証に失敗した」ではなく「検証に渡したキーとその型、比較した閾値」
- `key=value` 形式に揃える。機械的に追える

受信ハンドラの各段に置きます。

```lua
print(string.format("[hud] enter keys=%d key1=[%s] key1type=%s phase=[%s] phasetype=%s",
    n, tostring(firstKey), typeof(firstKey), tostring(state.phase), typeof(state.phase)))
print(string.format("[hud] validate ok=%s reason=%s", tostring(ok), tostring(reason)))
print(string.format("[hud] gate phase=[%s] expected=[%s] match=%s",
    tostring(state.phase), tostring(EXPECTED), tostring(state.phase == EXPECTED)))
print(string.format("[hud] apply label=%s text=[%s]", label:GetFullName(), label.Text))
```

20Hz で全部流すと読めないので、**先頭 N パケットだけ**出すか、値が前回と変わったときだけ出してください。

### ステップ 4: 再実測してログの値を読む。**そこで初めて修正する。**

---

## 3. 分岐別に疑うもの

### §3-A: `recv=0`（受信ハンドラに到達していない）

順に潰します。

1. **RemoteEvent インスタンスの取り違え。** サーバーが送っている `remote:GetFullName()` と、クライアントが購読している `remote:GetFullName()` を**両方ログに出して文字列比較**する。同名の別インスタンスが親違いで存在するのは頻出です。
2. **LocalScript が実行されない位置にある。** `ReplicatedStorage` や `ServerStorage` 直下の LocalScript は走りません。`StarterPlayerScripts` / `StarterGui` 配下（またはそこからコピーされる経路）にあるか確認。
3. **リスナー登録が送信開始より遅い** — ただし 20Hz で送り続けているなら該当しません（この可能性は症状から消えています）。
4. **`FireClient` の宛先が誤っている。** `FireAllClients` ではなく `FireClient(player, ...)` を使っていて、`player` が古い参照や nil の場合。サーバー側ログに**宛先人数と宛先名**を出させてください。
5. **クライアントがまだゲームに参加していない。** プロセスが立っていることと、ゲームに参加していることは別です。サーバーのコンソールで参加者数と識別子を確認。

### §3-B: `phase` の比較が成立しない

`phase` が Active になっているのはサーバー側で確認済みとのことですが、**確認したのは送信前の値**です。受信側で比較しているものと同一とは限りません。

- **表現の違い**: サーバーが enum テーブルの参照（`Phase.Active`）を送り、クライアントが文字列 `"Active"` と比較している。テーブル参照はリモートを跨ぐと**同一性が保たれません**（別テーブルとして復元される）。この場合 `==` は永久に false になります。
- **大文字小文字・前後空白**。`tostring` して `[]` で囲んでログに出せば一目です。
- **ネストの位置違い**: `payload.phase` と `payload.state.phase` の取り違え。`nil == "Active"` は false になるだけで、**エラーは出ません**。
- **数値 enum の場合**、値としては変換されないので比較は通るはずです。通らないならネストか名前の問題。

### §3-C: 受信は正常だが画面に出ない

- **検証層が黙って捨てている。** 検証関数が `false` を返すだけで warn しない実装なら、これが沈黙の正体です。理由コード付きで 1 行出させてください。
- **`ScreenGui.ResetOnSpawn = true`。** キャラクタがリスポーンするたびに GUI が作り直されます。更新ハンドラが**起動時に掴んだ古い TextLabel を保持し続けている**と、書き込みは成功しているのに画面には反映されません。エラーは出ません（破棄済みインスタンスへの書き込みは例外になりません）。これは「一度も更新されない」症状と非常に相性が良い候補です。
- **`pcall` が握りつぶしている。** 更新処理が `pcall` で包まれ、戻り値を捨てていないか。包むなら失敗時に必ず 1 行出す。
- **HUD の可視性**: 親の `Visible=false`、`ZIndex`、別の ScreenGui に隠れている、`Size` が 0。

これは GUI ツリーを歩いてテキストを直接読むのが確実です。画面キャプチャより速く、値が正確に取れます。

```lua
local gui = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("<ScreenGui名>")
if not gui then return "SCREENGUI_NOT_FOUND" end
local out = {string.format("gui.Enabled=%s", tostring(gui.Enabled))}
for _, c in gui:GetDescendants() do
    if c:IsA("TextLabel") then
        table.insert(out, string.format("%s visible=%s text=[%s]",
            c:GetFullName(), tostring(c.Visible), c.Text))
    end
end
return table.concat(out, "\n")
```

---

## 4. キー文字列化が確定した場合の直し方

### やること: 受信側に wire decode 層を置く

**検証の前に**キーを数値へ復元します。

```lua
-- 受信直後、検証より前。受信 payload は破壊せず、新しいテーブルへ詰め替える
local function decodeKeyedMap(src)
    if type(src) ~= "table" then return src end
    local out, seen = {}, {}
    for k, v in pairs(src) do
        local nk = (type(k) == "string") and tonumber(k) or k
        if type(nk) ~= "number" or nk ~= nk or nk == math.huge or nk == -math.huge or seen[nk] then
            -- 復元不能／復元後に衝突 → 復元しない。そのまま検証へ渡して落とす
            return src
        end
        seen[nk] = true
        out[nk] = v
    end
    return out
end
```

### 守るべき境界

- **検証は緩めない。** 復元不能なキー、復元後に衝突するキーがあれば復元せず、そのまま検証へ渡して落とします。「通すために検証を甘くする」は別の欠陥を招き入れる行為です。
- **これは schema の緩和ではなく transport 変換の復元です。** この区別を仕様書に書き残さないと、後から「なぜ受信側だけ特別扱いなのか」が誰にも分からなくなり、次の人が「不要な処理」として消します。
- **識別子の妥当性は「有限な非ゼロ整数」で表現する。符号に意味を持たせない。** `> 0` の前提はローカルテストで全滅します。
- **テスト専用の分岐で回避しない。** テスト経路と本番経路が別物になり、検証そのものの意味が薄れます。

### 恒久的な設計変更（推奨）

そもそも数値キー辞書を payload に載せなければ、この変換の影響を受けません。

```lua
-- 変換の影響を受けない形
players = {
    { id = -1, score = 0, balance = 100 },
    { id = -2, score = 3, balance =  80 },
}
```

配列の添字は変換されません。新規設計ならこちらが安全です。既存を直すなら、まず decode 層で症状を止めてから、payload 形状の変更を別の変更として計画してください（一度に両方やると、どちらが効いたか分からなくなります）。

---

## 5. やってはいけないこと

- **当て推量で直さない。** 実測すると当て推量は普通に外れます。実運用で「FSM のバグ」に見えた症状の真因が、まったく別レイヤの検証関数の数値制約だった例があります。そちらを直したら FSM の症状も同時に消えました。
- **症状の数を原因の数と混同しない。** 1 つ直して片方が消えたら、**もう片方も再実測してから**追加修正を判断してください。
- **実装報告を証拠として扱わない。** 実装を人や別モデルに委譲するのは構いませんが、**検証は委譲しない**でください。「受信を確認した」という報告と、あなたが `execute_luau` で得た `keytype=string` という行は、証拠としての重みが違います。
- **観測の主軸を画面に置かない。** 画面キャプチャは「何かおかしい」までしか言えません。`phase from=X event=Y guard=Z result=committed to=W` のような構造化 1 行ログは、どの遷移がどの条件で成立したかを一意に決めます。

---

## 6. 最短経路のまとめ

1. §2 ステップ 1 の**生受信プローブ**を Client DataModel で実行する（所要 2 分）
2. `keytype` を見る
   - `string` → **確定**。§4 の decode 層を入れる
   - `number` → §3-B / §3-C へ
   - `recv=0` → §3-A へ
3. 一意に決まらなければ、抑制なしの診断ログ（判定に使った値そのもの）を入れて再実測
4. 修正後、**同じプローブをもう一度回して**、症状が消えたことをログの実値で確認する

最初のプローブ 1 回で、8 割方は決着がつくはずです。
