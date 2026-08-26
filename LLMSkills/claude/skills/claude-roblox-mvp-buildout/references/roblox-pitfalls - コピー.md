# Roblox実行時pitfalls

候補集であり、永続的なplatform仕様表ではない。現在のStudio版、実行モード、最小reproで再確認してから原因として採用する。

最終確認日: 2026-08-17

## 目次

- [0. 証拠化ルール](#0-証拠化ルール)
- [1. Scripted testingを先に試す](#1-scripted-testingを先に試す)
- [2. local testのPlayer識別子](#2-local-testのplayer識別子)
- [3. Remoteのtable変換](#3-remoteのtable変換)
- [4. client側の無言失敗](#4-client側の無言失敗)
- [5. Luauの曖昧なcast代入](#5-luauの曖昧なcast代入)
- [6. 起動直後の初期化競合](#6-起動直後の初期化競合)
- [7. Studioによるartifact変更](#7-studioによるartifact変更)
- [8. 毎stepの丸めが加速を消す](#8-毎stepの丸めが加速を消す)
- [9. Windows自動化](#9-windows自動化)

## 0. 証拠化ルール

各platform観測を次の形で証跡へ残す。

- Studio版、OS版、実行モード、日時、build SHA-256。
- 最小reproのコードと実行場所。
- 期待値、実値、型、ログartifact。
- 公式文書URLと参照日。公式保証でない場合は`observed-only`。
- 再現しなかった版と条件。

古い観測と症状が一致しても、現在版でprobeを通すまで修正しない。

## 1. Scripted testingを先に試す

現行公式文書はStudio専用の`StudioTestService`と`VirtualInput`を案内している。`VirtualInput`は実ハードウェア相当として処理される。利用可能ならOS入力より先に使う。

- https://create.roblox.com/docs/studio/testing-modes#scripted-testing
- 参照日: 2026-08-17

利用不能、MCP経由で対象clientを指定不能、または対象経路を再現できないことをprobeで確認した場合だけOS入力へ落とす。「以前MCPの合成入力が届かなかった」だけで現在環境の不能を断定しない。

## 2. local testのPlayer識別子

観測候補: local Server & Clientsで、test Playerの`UserId`が負数になる版がある。

症状:

- `UserId > 0`のguardで全test playerが拒否される。
- snapshot公開失敗と人数遷移停止が同時に出る。

repro:

```lua
for _, player in game:GetService("Players"):GetPlayers() do
    print("USER_ID_PROBE", player.Name, player.UserId, typeof(player.UserId))
end
```

この観測は版依存の`observed-only`として扱う。識別子の符号をゲーム規則に使わず、仕様が要求する性質だけを検証する。本番UserIdの保証まで緩めない。

## 3. Remoteのtable変換

公式文書は、RemoteEvent/RemoteFunctionへ渡すtableの非string indexがstringへ変換されること、numeric/string keyのmixed tableを避けることを明記する。

- https://create.roblox.com/docs/scripting/events/remote#argument-limitations
- 参照日: 2026-08-17

数値Player IDをdictionary keyにしたpayloadでは、受信側の型を必ず測る。

```lua
remote.OnClientEvent:Once(function(payload)
    for key, value in payload.scores do
        print("WIRE_KEY", tostring(key), typeof(key), typeof(value))
    end
end)
```

対処は次のどちらかにする。

- wire formatを`{{id = number, value = number}, ...}`の配列にする。
- 仕様化したdecode層でstring keyを厳密に数値へ復元し、変換不能・衝突・重複を拒否する。

受信schemaを黙って緩めない。送信tableと受信tableの同一性も仮定しない。

## 4. client側の無言失敗

エラーが無い場合は、まず無条件probeが正しいclient出力へ見えることを確認する。その後、安い順に分ける。

- handlerが0回: Remoteがclientへ複製される場所にあるか、同名別instanceでないか。
- handlerは動く: 生payloadの引数数、値、`typeof`、key型を検証前に出す。
- updateは動く: 書込先のfull pathと、表示中PlayerGui配下のinstanceかを読む。
- respawn後だけ止まる: 古いGUI参照を保持していないか。
- 大きいpayloadだけ失敗: 小さい1-field payloadで経路と形状を二分する。
- 例外0: `pcall`やguardが握り潰していないか、拒否理由を出す。

server consoleだけを見てclient error 0件と宣言しない。

## 5. Luauの曖昧なcast代入

観測候補: 行頭の括弧付きtype castへの代入が、前行の継続として解釈され、parserで失敗する構成がある。

```lua
-- 避ける
(someValue :: SomeType).Property = nextValue

-- 使用する
local typedValue = someValue :: SomeType
typedValue.Property = nextValue
```

採用中のpinされたLuau parserで最小reproを確認する。Rojo build成功はこのparse成功を保証しない。

## 6. 起動直後の初期化競合

症状候補: 人数は揃ったが、characterや依存instanceの生成前に開始処理が走り、数回再試行してから成立する。

測るもの:

- roster ready時刻。
- character/primary part ready時刻。
- 開始試行回数、拒否理由、収束までの時間。

有限回で自己収束しても、再試行回数は観察事項として残す。無限再試行、上限超過、部分初期化は欠陥。固定sleepで隠さず、成立条件を待つ。

## 7. Studioによるartifact変更

観測候補: Studioが開いたplaceへ保存または自動回復情報を書き戻し、検証前後でbyte列が変わる。

対処:

1. canonical buildをStudioで開かない。
2. SHA-256を記録した専用test copyを作り、可能ならread-only化する。
3. Studio終了後に同じfileのSHA-256を再計測する。
4. 変化した場合、そのセッションのartifact同一性主張を無効にする。
5. test copyを証跡とともに保持する。

## 8. 毎stepの丸めが加速を消す

症状候補: 入力中なのに速度が常に0。加速度、抵抗、停止閾値は個別には仕様値。

関係を測る。

```text
step_delta = (acceleration - resistance) * dt
step_delta < stop_snap_threshold
```

加速中にも毎step停止snapを適用すると、増分が毎回消える。snapの適用条件と連続stepの実値をログに出す。値を勝手に変えず、規則の修正が必要なら所有者承認を得る。

## 9. Windows自動化

- Codex CLIへprompt file全体を渡す現在の手順は`codex exec -`。stdin redirectがEOFを閉じる。旧来の「prompt引数に`< /dev/null`必須」という説明は使わない。
- OS input前に、PID、process start time、exact executable path、desktop session、cached/current main HWND一致、exact main HWND = foreground HWND、owner PIDを毎action確認する。
- 全画面画像のpixel原点は`(0,0)`だが、OS仮想スクリーン原点は負値を取りうる。`osX = imageX + OriginX`、`osY = imageY + OriginY`で変換する。
- clipboard自動操作は同梱helperがlossless backup/restoreを保証しないため、このskillでは使わない。MCP/test harnessで代替できなければ`BLOCKED`にする。
- `tscon`は対話desktopを切り替える破壊的操作。自動実行しない。
- 固定sleepで起動完了を決めない。manifestに登録したPID、window、role/player handshakeを条件に待つ。
