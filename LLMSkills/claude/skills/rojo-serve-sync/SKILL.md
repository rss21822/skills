---
name: rojo-serve-sync
description: |
  Rojo serve を起動して Roblox Studio プラグインと確実に同期接続させる手順。版不一致（protocolVersion エラー）・PATH汚染による古い rojo 実行・ポート衝突（os error 10048）・別プロジェクトのserve占有を切り分けて解決し、接続後に MCP で構造とPlayログを検証するところまで行う。
  ユーザーが「rojo serve」「rojo sync」「Studioと同期」「Rojo接続」「Connectできない」「同期されない」「rojoが繋がらない」「ポートが使われてる」に言及したとき、また `attempt to index number with 'protocolVersion'` / `os error 10048` / `Rojo crashed!` のエラーを見せてきたときは必ずこのスキルを使うこと。
  「rojo serve 起動して」のような単純な依頼でも使う — 素直に起動するとPATH上の古いrojoが動いて後で接続エラーになるため、版確認を挟む価値がある。Roblox / Rojo / Studio同期の文脈なら、ユーザーがエラー名やポート番号を明示しなくても適用する。
---

# Rojo serve → Studio 同期接続

Rojo は「CLI（serve側）」と「Studioプラグイン（クライアント側）」の2つが噛み合って初めて動く。接続失敗のほとんどは**この2つの版がズレている**か、**ポートを別プロセスが握っている**かのどちらか。どちらも起動前に潰せるので、`rojo serve` を叩く前に確認する。

順番が重要。版を確認せずに serve を上げると、ユーザーが Studio で Connect してから初めて失敗が判明して往復が増える。CLI側で完結する検証を先に済ませる。

## 手順

### 1. 使う rojo バイナリを確定する（最重要）

`rojo --version` を信用しない。PATH に複数の rojo が入っていることがあり、先頭に来たものが古い版だと、正しい版がインストール済みでも古い方が動く。

```bash
type -a rojo          # PATH上の全候補を順に列挙
~/.rokit/bin/rojo --version   # rokit管理版（プロジェクトルートで実行すること）
```

`type -a` が2行以上返したら PATH汚染。rokit 管理下のプロジェクトなら **rokit の shim を明示的に使う**のが正解:

```bash
cd <プロジェクトルート> && ~/.rokit/bin/rojo serve
```

rokit shim は**カレントディレクトリの `rokit.toml` を読んで版を解決する**。プロジェクトルート外で実行すると別の版が起動するので、必ず `rokit.toml` のある場所から実行する。

shim が期待の版を返さない場合のみ、tool-storage の実体を絶対パスで叩く:

```bash
~/.rokit/tool-storage/rojo-rbx/rojo/<version>/rojo.exe serve
```

**プラグイン側の版**は Studio の Plugins タブか、エラーメッセージの `cloud_<id>.Rojo.Plugin.*` から辿る。プラグインは自動更新されるため最新に寄りがちで、CLI が取り残されるのが典型的な壊れ方。

### 2. ポートの空きと占有主を確認する

既定は 34872。使用中なら Rojo は起動時に `os error 10048` でクラッシュする。

```bash
netstat -ano | grep 34872 | grep LISTEN
```

PID が出たら、それが何かを特定する。**いきなり kill しない** — 別プロジェクトの作業中 serve である可能性が高い:

```bash
powershell -Command "Get-Process -Id <PID> | Select-Object Id,ProcessName,Path | Format-List"
curl -s http://localhost:34872/api/rojo | head -c 300
```

`/api/rojo` の `projectName` で、そのserveがどのプロジェクトを配信しているか分かる。判断:

- **別プロジェクトのserve** → 別ポート（`--port 34873`）を使う。ユーザーが明示的に「止めていい」と言った場合のみ停止する
- **自分のプロジェクトの古いserve** → 停止して上げ直す
- **応答なし／rojo以外のプロセス** → 別ポートを使う

### 3. serve を起動して応答を検証する

バックグラウンド起動し、必ず `/api/rojo` を叩いて**期待どおりの版とプロジェクトを配信しているか**確認してからユーザーに接続を依頼する。起動ログの "listening" だけでは、間違ったバイナリが上がっていても気づけない。

```bash
cd <プロジェクトルート> && ~/.rokit/bin/rojo serve --port 34872   # バックグラウンド
sleep 2 && curl -s http://localhost:34872/api/rojo | head -c 400
```

**応答形式が版の判別材料になる**:

- **JSON がそのまま読める** → Rojo 7.6 系（protocolVersion 4）
- **バイナリ混じり（msgpack）で `serverVersion` `projectName` が断片的に読める** → Rojo 7.7 系

curl の出力が化けていても異常ではない。7.7 は msgpack を返す。`serverVersion` と `projectName` の値が読み取れれば正常。

### 4. ユーザーに接続を依頼する

Connect は Studio UI 操作なので、こちらからは実行できない。ユーザーへ渡す情報は Host と Port だけでよい:

> Studio → Plugins → Rojo → Connect（Host `localhost` / Port `34872`）→ Sync

**Rojo の Connect 画面に「Connection Code」欄は存在しない。** Host と Port の2欄のみ。ユーザーが1欄しかないと言ったら、それは Rojo ではない別のプラグイン（Rojo風の別プラグインや Studio 標準の何か）を開いている。

### 5. 接続後の検証

同期されたか、Rojo が意図どおりのインスタンス種別を作ったかを MCP で確認する。

```
mcp__Roblox_Studio__search_game_tree(path: "ServerScriptService", max_depth: 3)
```

`ServerScriptService` が空のままなら未接続。同期済みなら、拡張子どおりの種別になっているか見る:

- `*.server.luau` → `Script`
- `*.client.luau` → `LocalScript`
- `*.luau` → `ModuleScript`

問題なければ Play で初期化ログを確認する:

1. `mcp__Roblox_Studio__start_stop_play(is_start: true)`
2. 数秒待つ
3. `mcp__Roblox_Studio__get_console_output` — 初期化ログが依存順どおり・エラーゼロで並ぶか
4. `mcp__Roblox_Studio__start_stop_play(is_start: false)` で Edit 復帰

## エラー対応表

| 症状 | 原因 | 対処 |
|---|---|---|
| `attempt to index number with 'protocolVersion'` | プラグイン(7.7)とCLI(7.6)のプロトコル不一致。プラグインが新形式の応答を期待しているのに旧形式が返っている | 手順1でCLIをプラグインと同世代に揃える |
| `os error 10048` / `error binding to 127.0.0.1:<port>` | ポート使用中 | 手順2で占有主を特定 → 別ポートか停止 |
| Connect成功だがノードが空 | Sync未実行、または別プレイスに繋いでいる | Studio側でSync実行／対象プレイス確認 |
| `rojo --version` は正しいのに接続失敗 | PATH上の別バイナリが実際には動いている | `type -a rojo` で全候補を確認 |
| プロジェクトルート外で版が変わる | rokit shim が `rokit.toml` を見つけられず別版に解決 | 必ずプロジェクトルートから実行 |

## PATH汚染の恒久対処

`type -a rojo` で複数出た場合、優先されている側の実体を確認してから対処を選ぶ。**パッケージマネージャ経由と決めつけない**:

```bash
ls ~/AppData/Roaming/npm/node_modules/ | grep -i rojo   # npmパッケージなら出る
```

- **npmパッケージとして入っている**（`node_modules/` に存在し、`.cmd` / `.ps1` ラッパーが揃っている）→ `npm uninstall -g rojo`
- **exe が直置きされているだけ**（`node_modules/` に無く、ラッパーも無い）→ `npm uninstall` は効かない。exe を直接削除するか、PATH の順序を変えて rokit を優先させる

いずれもユーザーの環境を変える操作なので、実行前に何をどう変えるか伝えて確認を取る。作業中は絶対パス／shim 指定で回避できるので、急いで消す必要はない。

## 判断のポイント

**他人のserveを勝手に止めない。** ポート衝突時、占有しているのが別プロジェクトの開発中 serve なら、そのユーザーは今まさにそれで作業しているかもしれない。別ポートで回避するのが既定。停止はユーザーが明示的に指示したときだけ。

**「listening が出た」で完了報告しない。** 間違ったバイナリでも listening は出る。`/api/rojo` の `serverVersion` と `projectName` を確認して初めて、正しい serve が正しいプロジェクトを配信していると言える。

**接続はユーザー操作で止まる。** Connect は MCP から実行できない。serve の準備が整った時点で必要な情報（Host / Port）を渡し、接続完了の返事を待ってから検証に進む。待っている間に他の作業を進めるのは構わないが、接続を仮定して先に進まない。
