# Roblox: サーバーは20Hzで送っているのにクライアントHUDが一度も更新されない — 切り分け手順

## まず前提を2つ疑ってください

**1. 「サーバー側ログで送信成功」は配送を1ミリも証明していません。**
`RemoteEvent:FireClient()` / `FireAllClients()` は fire-and-forget です。戻り値はなく、失敗も返しません。宛先プレイヤーが受け取ったか、そもそもクライアントがそのイベントに接続しているか、サーバーからは一切分かりません。ログが証明しているのは「その行が実行された」ことだけです（しかも後述のとおり、ログ行と実際の fire が別の分岐にいるケースが実在します）。

**2. 「エラーも警告も出ない」は、「クライアント側の出力を見ていない」可能性を含みます。**
Studio の Output はコンテキスト（Server / Client）でフィルタされます。Team Test や複数クライアント起動時は、クライアントのエラーがサーバー側の Output に出ません。実機なら F9（Developer Console）の Client タブです。**まずここを確認してから**「エラーなし」という観測を信用してください。

なお「警告も出ていない」こと自体が情報になります。`:WaitForChild("Name")`（タイムアウト無し）が永久待機していれば5秒後に *Infinite yield possible on ...* という警告が必ず出ます。それが出ていないなら、(a) 待ちは成功している、(b) クライアント出力が見えていない、(c) そのスクリプト自体が実行されていない、のいずれかです。

そして重要な示唆がもう一つ。**本当に payload が nil なら `payload.phase` で "attempt to index nil" が出るはず**です。エラーが皆無ということは、コードのどこかに「nil なら黙って return する」ガードがあるか、ハンドラ自体が一度も呼ばれていないかのどちらかです。この2つを分けるのが最初の一手です。

---

## Step 1: 最初の分岐 — 「裸の受信プローブ」を1個入れる（これが最重要）

HUD も phase ゲートも一切通さない、受信だけを見るLocalScriptを `StarterPlayer/StarterPlayerScripts` に置きます。既存コードは触りません。

```lua
-- StarterPlayer > StarterPlayerScripts > _RecvProbe (LocalScript)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
print("[probe] localscript started")

local remote = ReplicatedStorage:WaitForChild("RaceSnapshot", 10) -- ★実名に置換
print("[probe] remote =", remote and remote:GetFullName(),
      remote and remote.ClassName,
      remote and remote:GetAttribute("Stamp"))
if not remote then
    warn("[probe] remote NOT FOUND on client")
    return
end

local n = 0
remote.OnClientEvent:Connect(function(...)
    n += 1
    local args = table.pack(...)
    if n <= 3 or n % 20 == 0 then
        local desc = {}
        for i = 1, args.n do
            desc[i] = ("arg%d=%s"):format(i, typeof(args[i]))
        end
        print(("[probe] #%d nargs=%d %s"):format(n, args.n, table.concat(desc, " ")))
    end
end)

task.delay(5, function() print("[probe] received in 5s =", n) end)
```

5秒で **約100件** 出るはずです。結果で道が二つに割れます。

- **0件 → A（届いていない＝transport の問題）へ**
- **来ている → B（届いているのに映らない＝payload / ゲート / 描画の問題）へ**

このプローブは同時に、`nargs` と各引数の `typeof` を出すことで後述の B-0（引数ズレ）も一撃で暴きます。

---

## A. 受信0件の場合（transport）

上から順に潰します。

### A-1. そもそもその LocalScript は動いているか
`print("[probe] localscript started")` すら出ないなら、コードの中身は無関係です。

- **設置場所**: LocalScript が動くのは `StarterPlayerScripts` / `StarterCharacterScripts` / `StarterGui`（→ PlayerGui にコピーされて動く）/ `ReplicatedFirst` / Backpack・Tool の中だけ。**Workspace 直下・ReplicatedStorage・ServerScriptService に置いた LocalScript は、エラーも警告も出さずに黙って動きません。** 「エラーゼロ」症状の最頻出原因の一つです。
- `Disabled = true` のまま、あるいは `Script` の `RunContext` を `Client` にしたつもりが `Legacy`/`Server` のまま。
- 親が `Enabled=false` の ScreenGui 配下 → GUI は非表示でもスクリプトは動きますが、`ResetOnSpawn` で作り直されると別インスタンスになります（B-3参照）。
- **先行する yield で止まっている**: 接続行に到達する前に `WaitForChild` / `repeat wait() until` / 無限ループの初期化がある。プローブのように「1行目に print」を置けば即判別できます。

### A-2. サーバーとクライアントが「同じ RemoteEvent インスタンス」を見ているか
これも定番です。名前が同じでも別物、というケース。

サーバー側で作成直後に刻印を打ちます。

```lua
remote:SetAttribute("Stamp", HttpService:GenerateGUID(false))
print("[srv] remote =", remote:GetFullName(), remote:GetAttribute("Stamp"))
```

クライアントのプローブが出す `GetFullName()` と `Stamp` を突き合わせてください。食い違う典型パターン:

- 同名の RemoteEvent が2つ存在する（片方は手置き、片方は `Instance.new` で生成）。クライアントの `WaitForChild` は先に見つかった方を掴みます。
- **ラウンドごとに RemoteEvent を作り直している / Destroy している**。クライアントは最初に掴んだ古いインスタンスへの接続を保持したまま。親から外れた（または Destroy 済みの）オブジェクトへの接続は、**エラーを出さずに永久に発火しません**。これは「1度も更新されない」症状と完全に一致します。
- 親が `ServerStorage` / `ServerScriptService` 配下 → クライアントには複製されません（この場合はクライアントの `WaitForChild` が待ち続け、警告が出るはず）。
- クライアント側が `ReplicatedStorage.Remotes.RaceSnapshot`、サーバー側が `ReplicatedStorage.RaceSnapshot` のようなパスずれ。

### A-3. 宛先が正しいか
- `FireClient(player, payload)` の `player` が **stale な Player オブジェクト**（前ラウンドで取得してキャッシュ、退出済み、キャラクター再生成前に取得したもの）ではないか。
- プレイヤーリストをループ開始前に一度だけキャプチャしていないか（後から参加した人に永久に届かない）。
- 逆に `FireAllClients` を使っているのに、送信ループが `PlayerAdded` より前の初期化タイミングで起動している。
- 検証: fire の直前に `print("[srv] targets:", #Players:GetPlayers(), player and player.Name, player and player.Parent)` を出す。`player.Parent` が nil なら退出済みです。

### A-4. トランスポートの種類とサイズ
- **`UnreliableRemoteEvent` を使っているなら要注意**: 1回あたりのペイロードサイズに上限（おおよそ1KB弱）があり、超えると届きません。順序保証も配送保証もありません。20Hz スナップショットで採用しがちな選択肢なので、**一度 通常の `RemoteEvent` に差し替えて再現するか確認**してください。届くようになったらサイズ・分割の問題です。
- ペイロードサイズを実測: `print(#HttpService:JSONEncode(payload))`（Instance 参照が入っていると JSONEncode は失敗するので、それ自体も検査になります）。
- 20Hz × 人数 × サイズが過大だと送信キューが詰まります。その場合は *Remote event queue exhausted* 系の警告が出るはずなので、警告が皆無ならこの線は薄いです。

### A-5. 「送信成功」ログと実際の fire が本当に同じ分岐にあるか
コードを目で追ってください。よくある形:

```lua
-- 20Hzループ
print("[srv] snapshot sent")          -- ← 無条件で出る
if self.phase == "Racing" and target then
    remote:FireClient(target, payload) -- ← 実はここに来ていない
end
```

あるいは `pcall(function() remote:FireClient(...) end)` で例外を握り潰している。ログは **fire の直後**に、`FireClient` に渡した引数そのものを含めて出すよう書き換えてください。

---

## B. 受信できているのにHUDが変わらない場合

### B-0. 引数の形がズレていないか（最有力候補）
サーバーとクライアントでシグネチャが違います。

- サーバー: `remote:FireClient(player, payload)` … 第1引数は宛先で、**送られるデータは第2引数以降**
- クライアント: `remote.OnClientEvent:Connect(function(payload) ... end)` … **Player は渡ってきません**

ここでよくある2つの事故:

1. クライアント側をサーバー側の `OnServerEvent` と同じ形で書いてしまう:
   `OnClientEvent:Connect(function(player, data) if data and data.phase == "Racing" then ... end end)`
   → `data` は常に nil。`if data and ...` のガードがあるので **エラーは一切出ず、HUD も永久に更新されない**。症状が完全一致します。
2. サーバー側で `FireAllClients(player, payload)` と書いてしまう（`FireClient` からのコピペ）。
   → クライアントの第1引数が Player インスタンス、第2引数が payload。第1引数だけ見ていれば `payload.phase` は nil。

Step 1 のプローブが `nargs=2 arg1=Instance arg2=table` のように出したら、これが原因です。

### B-1. phase ゲートを一時的に外す
ゲートの前後にログを入れ、**受信直後の生値**を型付きで出します。

```lua
print("[recv] phase =", tostring(payload and payload.phase),
      "typeof =", typeof(payload and payload.phase),
      "len =", #tostring(payload and payload.phase))
```

確認すべきこと:
- **型の食い違い**: サーバーが Enum や数値（`Phase.Racing == 2`）、クライアントが文字列 `"Racing"` と比較している。
- **大文字小文字・前後の空白**（`#tostring()` を出すのはこのため）。
- **クライアントの phase の出所**。ここが一番怖い点です。HUD が参照している phase は、**この payload 由来ですか？** それとも別チャネル（別の RemoteEvent、Attribute、ValueObject、クライアント側で独自に回している状態機械）由来ですか？ 「サーバー側 phase が Racing なのは確認済み」という観測は、クライアント側 phase については何も語りません。別チャネルなら、壊れているのはスナップショットではなく **phase 伝達チャネルの方**です。
- 検証: ゲートを一時的に `if true then` に置き換える。HUD の数字が動き出したらゲートが犯人、動かなければ描画側（B-3）が犯人。この1回の実験で残り半分が消えます。

### B-2. payload の中身を「キーの型つき」でダンプする
`print(payload)` はテーブルのアドレスしか出ません。必ず中身を展開してください。

```lua
local function dump(t, indent)
    indent = indent or ""
    for k, v in pairs(t) do
        print(("%s[%s %s] = %s (%s)"):format(indent, typeof(k), tostring(k), tostring(v), typeof(v)))
        if type(v) == "table" then dump(v, indent .. "  ") end
    end
end
```

**ここでプレイヤーIDをキーにした辞書を重点的に見てください。** リモート越しのテーブルはシリアライズを経由するため、素の Lua テーブルと同じ挙動を期待できません。確認すべき既知のハマりどころ:

- **配列部と辞書部が混在したテーブル**（`{ [1]="a", name="b" }`）は、片方が欠落します。ランキング配列とメタ情報を同じテーブルに詰めていませんか。
- **nil 穴のある配列**は途中で切り捨てられます。順位配列に欠番があると以降が消えます。
- **数値キーの辞書**（= UserId キー）は、疎で巨大な数値キーになるため最も事故りやすい形です。キーが数値のまま届くか、文字列化されるか、そもそも欠落するかを **ダンプの `typeof(k)` で実測**してください。サーバーで `[123456789]`、クライアントで `["123456789"]` になっていれば、`standings[LocalPlayer.UserId]` は当然 nil を返し、ガード付きコードなら無言で return します。
- **対策（そして推奨形）**: 辞書をやめて **レコードの配列**にする。
  ```lua
  payload.standings = {
      { userId = 123456789, place = 1, lapTime = 42.13 },
      { userId = 987654321, place = 2, lapTime = 43.02 },
  }
  ```
  順序も保たれ、シリアライズの罠を全部回避できます。どうしても辞書にしたいなら `tostring(userId)` でキーを文字列に固定し、参照側も `tostring()` を通す。
- **メタテーブルは剥がれます**。OOP 的に `setmetatable` した順位オブジェクトを送ると、クライアント側ではメソッドのない素のテーブルになります（`standings:GetPlace()` は当然エラーになりますが、`__index` 経由のフィールドアクセスは静かに nil になります）。
- **関数・スレッドは送れません**。クロージャを含むテーブルを渡していないか。
- **クライアントから見えない Instance 参照は nil で届きます**（ServerStorage 配下の車オブジェクトなど）。
- 途中引数の `nil` は引数リストごと切り詰められます。

**ペイロードの二分探索**が効きます。中身を `{ seq = n }` だけに削ってHUDにその数字を出す。動いたら、フィールドを1つずつ戻していく。壊れる境目のフィールドが原因です。

### B-3. 「更新しているUIオブジェクト」が画面上のものと同一か
ゲートを外しても変わらないなら、書き込み先が違います。

- **`StarterGui` の元を書き換えている**。実際に画面に出ているのは `player.PlayerGui` にコピーされた方です。`StarterGui.HUD.LapLabel.Text = ...` は **エラーなしで成功し、そして何も見えません**。参照は必ず `player:WaitForChild("PlayerGui")` から辿ること。
- **`ScreenGui.ResetOnSpawn = true`（既定）**。キャラクターがスポーン/リスポーンすると PlayerGui の GUI は破棄され新しくコピーし直されます。スクリプトが起動時に掴んだラベル参照は **孤児インスタンス**になり、以後の書き込みは成功するが画面には反映されません。エラーは出ません。レース開始時に必ずリスポーンが入る設計なら、これが本命です。対策は `ResetOnSpawn = false`、または `CharacterAdded` ごとに参照を取り直す。
- テンプレートを `Clone()` したが `Parent` を設定していない（あるいは設定前に書き込んでいる）。
- `ScreenGui.Enabled = false`、`Frame.Visible = false`、`TextTransparency = 1`、`Position` が画面外、`ZIndex` が背面、`Size` がゼロ。
- 同名ラベルが複数あり `FindFirstChild` が別の方を掴んでいる。
- **検証**: 受信ハンドラ登録の直後に、無条件で `label.Text = "PROBE"` と `label.BackgroundColor3 = Color3.new(1,0,1)` を書く。派手なマゼンタが画面に出なければ、参照しているオブジェクトは画面上のものではありません。

### B-4. 接続の寿命
- `:Once()` を使っていれば1回だけ発火します（「一度も」ではなく「一度だけ」になるので今回は該当しにくい）。
- どこかで `:Disconnect()` していないか。特に phase 遷移で接続を張り替える設計だと、遷移イベントを取りこぼした瞬間に永久沈黙になります。
- 接続が「レース開始通知を受け取ってから張られる」設計なら、**その開始通知チャネルこそが壊れている**可能性。接続はスクリプト起動時に無条件で張り、ゲートはハンドラ内で判定するのが安全です。

---

## 恒久的な計装（入れておけば次回は30秒で切り分く）

1. **payload に `seq`（単調増加）と `serverTime = workspace:GetServerTimeNow()` を必ず含める。**
2. **HUD にデバッグ行を1本常設**（開発ビルドのみ）: `recv#{seq} age={now-serverTime}s rate={直近1秒の受信数}`。
3. クライアントで「最後に受信してからの経過秒」を1秒ごとに監視し、1秒を超えたら `warn`。無音の失敗を無音のままにしない。
4. サーバーは「送った seq」、クライアントは「受けた seq」をログ。欠番＝ドロップ、完全無音＝未接続、と即断できます。
5. `FireClient` の直後（同じ分岐内）でのみ送信ログを出す。ループ先頭で出さない。

## 疑う順序（経験則）

1. **B-0 引数ズレ**（`OnClientEvent` を `function(player, data)` で受けている／`FireAllClients(player, payload)`）— エラーが出ない症状と最も整合
2. **A-1 LocalScript が動かない場所にある / A-2 別の（または作り直された）RemoteEvent を見ている**
3. **B-3 StarterGui を更新している／ResetOnSpawn で参照が孤児化**
4. **B-1 phase の型・出所の食い違い**（クライアントの phase が payload 由来でない）
5. **B-2 UserId 数値キー辞書のシリアライズ欠落**
6. **A-4 UnreliableRemoteEvent のサイズ超過**

Step 1 のプローブ1本で 1〜2 と 3〜6 が分かれ、B-1 のゲート撤去で 3 と 4〜5 が分かれます。実質2回の実行で原因は1つに絞れます。

---

## 補足（バグとは別の設計上の指摘）

20Hz で全プレイヤー分のフルスナップショットを全クライアントに配るのは、人数が増えると帯域とキューを圧迫します。原因が判明したあとで構いませんが、(a) 差分のみ送る、(b) 順位・ラップのような低頻度データは変化時のみ送り、位置補間など高頻度なものと分ける、(c) 各クライアントに必要な分だけ送る、を検討する価値があります。20Hz の帯域は「常時変わる値」のためだけに使うのが定石です。
