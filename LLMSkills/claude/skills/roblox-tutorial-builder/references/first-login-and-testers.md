# 初回ログインだけ・テスターは毎回

## 目次
1. 記録（TutorialRecord）
2. 判定（TutorialGate）
3. ログインの定義
4. テスター（指定 UserId は毎ログイン）
5. 失敗時の扱い
6. Studio と RTBF
7. 専用 Place（TutorialRouting と到着ガード）

## 1. 記録
- DataStore `<prefix>_<env>_tutorial_v1`（環境ごとに別）、キー `u:<UserId>`、値 `{ v = 1, starts, startedAt?, completedAt? }`。
- 無いキー = 新規。`sanitize` に通らない値はエラー（新規扱いしない。壊れた値で毎回出るのを防ぐ）。
- `MAX_STARTS = 1`。開始は**見せる前（送る前）**に `markStarted` で数える。UpdateAsync の変換の中で `canStart` を再判定するので、別サーバーが先に書いても二重に出ない。
- 読みは `UseCache = false`（チュートリアル Place が書いた直後を読む）。1xx/4xx は再試行しない。
- プロフィールに安全な任意項目の仕組みがあれば同じ規則をそこに置いてもよい。全 Place 同時のスキーマ変更が要るなら別 DataStore のまま。

## 2. 判定
`Gate.new{ store, testers, ownPlaceIds, isExperienced, log }`
- `precheck`（待たない）: ログインでない → skip "arrival" / テスター → "tester" / `isExperienced` が nil → "later" / true → skip "experienced" / それ以外 → "check"。
- `decide`（記録を 1 訪問 1 回読む）→ "tester" | "first_time" | nil, why。
- `begin` → 数える（テスターは何もしない）。`refund` / `complete` / `forget`。

## 3. ログインの定義
体験の外からの参加 = `player:GetJoinData().SourcePlaceId` が自分の Place（`ownPlaceIds` + game.PlaceId）でない。試合 → ロビー、チュートリアル → ロビー、サーバー移動はログインではない。テスターにも効く（往復ループ防止）。`ownPlaceIds` に全 Place を入れ忘れると帰還のたびに出る。

## 4. テスター（指定 UserId は毎ログイン）
- `Config.TESTER_USER_IDS = { studio = {...}, staging = {...}, production = {...} }`、`Config.testersFor(env)` を Gate に渡す。
- 一覧の UserId は**毎ログイン**チュートリアルが出る。記録は読まない・書かない（何度でも初回として確認できる）。到着（帰還）では出ない。
- 数値の正の整数だけ有効。文字列 "123" や 0、小数は無視（`Config.validate` が問題として報告）。
- ユーザーが UserId を指定したら: 指定の環境へ。環境の指定が無ければ studio と staging に入れ、production は Owner に確認してから（本番の他の挙動は変わらないが、そのアカウントは本番でも毎回出る）。
- UserId の調べ方（Owner への案内）: roblox.com のプロフィール URL `https://www.roblox.com/users/<数字>/profile` の数字。Studio の Play 中なら `print(game.Players.LocalPlayer.UserId)`。
- 「毎回表示」の真偽フラグは作らない。消し忘れると全員に毎回出る。既存のフラグはテスター一覧へ移す。

## 5. 失敗時の扱い
- 読み失敗・記録不正: その訪問は出さない、ログ。何も数えていないので次のログインで再試行。
- `begin` 失敗: 出さない（数えずに出すと次回また出る）。
- 送信が例外 / TeleportInitFailed / 送る前に退出: `refund`（確実に届いていない）。
- 応答なしのタイムアウト: 返さない（届くかもしれない）。
- 送信失敗が続く: ブレーカーで一時停止（Routing）。

## 6. Studio と RTBF
- 未公開ファイルの Studio では DataStore が例外 → `Record.newMemoryStore()`（Play ごとに新規）。既存プレイヤーの確認は `data` に記録を入れて。
- Studio のテスターは `studio` 一覧。自分の UserId を入れると毎 Play で出る。
- 記録ストアは個人データ。RTBF（削除依頼）の対象一覧に `<prefix>_<env>_tutorial_v1` の `u:<UserId>` を加える。

## 7. 専用 Place
- ロビー: `TutorialRouting.new{ gate, placeId, players, isLive, isFree, lock, unlock, beforeTeleport?, teleport, newOptions, log }`、Heartbeat で `step()`。PlaceId が 0（未作成）や Studio では作らない。
- `newOptions` は `ShouldReserveServer = true`（一人一サーバー）。パーティ・キュー・他の送信中（`isFree` false）は待つ。
- チュートリアル Place: 予約サーバー以外（公開・VIP）で来た人、二人目、退出後の到着はロビーへ返す。完了で記録の `markCompleted`（テスター以外）、Result 後にロビーへ帰す（失敗は再試行、最後は諦めてキック前にログ）。
- 帰還はロビーから見て「到着」なのでテスターでも再送されない。
