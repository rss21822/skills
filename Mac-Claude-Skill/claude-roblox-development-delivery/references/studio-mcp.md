# .rbxlx作成とStudio検証

ローカルのソースからplaceファイルを作り、Roblox Studioで開き、Play状態で実測する。Claudeが自分で実行する（Codexサンドボックスからはできない）。

以下のコマンド例で `<Place>` はプロジェクトのplace名、`<place>.project.json` はそのRojo project fileを指す。実プロジェクトの名前へ読み替える。

## 1. buildして.rbxlxを作る

Rojoで生成する。project JSONを手編集しない。placeの構成はマニフェスト等から生成し、生成物とtrackedバイトの一致を `--check` で検証する設計にしておくと、手編集が混入した瞬間に落ちる。

```bash
export PATH="$HOME/.rokit/bin:$PATH"
rojo build <place>.project.json --output artifacts/build/<Place>.rbxlx
shasum -a 256 artifacts/build/<Place>.rbxlx
```

hashは必ず取る。実行したartifactを後から特定するために要る。

**決定論の確認**: 同じ入力から2回buildしてhashが一致することを確認する。一致しないなら、生成に非決定的な要素（時刻・順序）が混ざっている。

## 2. Studioで開く

```bash
open artifacts/build/<Place>.rbxlx
```

起動には時間がかかる。固定時間待つのではなく、次節の `list_roblox_studios` が対象インスタンスを返すまで確認を繰り返す。目安は5秒間隔で最大7回（約35秒）。それを超えても現れないなら、Studio側の起動失敗を疑う（固定待機のまま次へ進むと、まだ開いていないインスタンスを操作しようとして原因の分かりにくい失敗になる）。

## 3. MCPで接続

```
mcp__roblox-built-in__list_roblox_studios   → 起動中のインスタンス一覧
mcp__roblox-built-in__set_active_studio     → 対象を選ぶ
```

**複数インスタンスに注意**: 古いwindowが残っていると、新しいbuildではなく古いplaceを操作してしまう。実運用で、旧buildでPlayして新機能が出ずに混乱したことがある。必ず `list_roblox_studios` で確認し、意図したインスタンスを `set_active_studio` する。idは起動順ではないので、新しく開いたものが最後とは限らない。

## 4. Play開始

```
mcp__roblox-built-in__start_stop_play { is_start: true }
```

**既知事象**: 新規に開いたStudioインスタンスの**初回**は、MCPからのPlay開始がタイムアウトまたは「Start play hasn't finished yet」で進まないことがある。90秒待っても `get_studio_state` が `Edit` のままなら、ユーザーへPlay押下を1回依頼する。2回目以降は同じインスタンスならMCPで開始できる。

状態確認:
```
mcp__roblox-built-in__get_studio_state
→ Current Studio Mode: Play / Available DataModels: Client, Server
```

## 5. 実測データを取る

`execute_luau` をServer/Client両方のDataModelに対して実行する。`get_console_output` は空を返すことがあるので、`LogService:GetLogHistory()` を直接読むほうが確実。

```lua
local h = game:GetService("LogService"):GetLogHistory()
local errors, warns, lines = 0, 0, {}
for _, x in h do
    if x.messageType == Enum.MessageType.MessageError then errors += 1
    elseif x.messageType == Enum.MessageType.MessageWarning then warns += 1 end
    table.insert(lines, string.format("%.3f|%s|%s", x.timestamp, x.messageType.Name, x.message))
end
return "errors=" .. errors .. " warns=" .. warns .. " total=" .. #h
    .. " studioVersion=" .. version()
    .. " matchmaking=" .. tostring(game.MatchmakingType.Name)
    .. "\n" .. table.concat(lines, "\n")
```

一緒に取っておくと後で困らないもの: `version()`（Studioバージョン）、`game.PlaceId` / `game.GameId` / `game.JobId`（未publishのローカルファイルは0や空文字）、`RunService:IsStudio()`、`game.MatchmakingType.Name`（server processでは非nullが期待される）。

**PII**: `Player.UserId` を生のまま記録しない。ドメイン分離したハッシュにする。saltは実行時に生成し、保存しない。原則は `evidence.md` の「PII」節。

```lua
-- SHA-256はRobloxの標準ライブラリに無い。Luau実装のモジュールを用意して require する。
local HttpService = game:GetService("HttpService")
local sha256 = require(<SHA-256モジュール>)

local salt = HttpService:GenerateGUID(false)  -- 実行時生成。保存しない
local hash = sha256("<domain>" .. "\0" .. salt .. "\0" .. tostring(userId))
```

## 6. 停止して記録

```
mcp__roblox-built-in__start_stop_play { is_start: false }
```

回収したログはファイルへ保存し、hashを取る。証拠として参照できる形にしておく。

**注意**: Studioはplace fileを開いている間にディスクへ書き戻すことがあり、実行前に取ったhashと停止後のhashが変わる。この場合、`rojo build` で再生成して元のhashが再現することを示せば、実行内容の同一性を証明できる。

## 7. 検証ハーネスの設計

Studioでの1回のPlayで多くの条件を確認したいなら、機械可読な出力形式を決めておく。

```
SV0_RESULT branch=<ID> kind=measured|simulated status=PASS|FAIL detail=<...>
SV0_SUMMARY stage=FINAL status=PASS measured=17 simulated=6 passed=23 failed=0
```

**measured と simulated を必ず区別する**。1回のPlay内で条件を模擬して確認したもの（guardを偽にした場合の挙動、2人目のプレイヤー等）は `simulated`。実際にその条件が成立していたものが `measured`。

これを混ぜると、テストが実配線されているのか入力を捏造しているのか区別できなくなる。実運用で、ハーネスがシミュレーション入力だけでPASSしていた（modeやparticipant数を実際のブートストラップへ渡していなかった）欠陥が照合で見つかった。分類を出力に含めれば、レビュアーが実装実態と突き合わせられる。

外部サービス（DataStore・MemoryStore・Teleport・Marketplace・Analytics）はfake adapterへ置き換え、実呼び出し0を計測して出力する。
