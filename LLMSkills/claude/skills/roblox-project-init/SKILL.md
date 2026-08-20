---
name: roblox-project-init
description: RobloxゲームをRojo + lune + Studio MCP構成で新規セットアップする（プロジェクト骨格生成）。Rojoプロジェクト作成、default.project.json、Init/Start形状のモジュール雛形、ServerMain/ClientMainの2段階初期化ループ、luneテスト骨格、rojo buildゲート、MCP実機ログ検証までを一貫して行う。ユーザーが「Robloxの新規プロジェクトを立ち上げる」「Rojoの骨格を作る」「プロジェクト初期設定」「Phase0」「セットアップ」「ディレクトリ骨格を用意」等に言及したら、Rojoやluneを明示していなくても使うこと。設計文書（CLAUDE.md / phase計画 / 詳細設計書）が存在する場合はそれを正本として構造・依存順・命名を読み取り、無ければ標準骨格を生成する。
---

# Roblox プロジェクト初期セットアップ

Robloxゲーム開発の最初の一歩＝「動く空の骨格」を作る作業を、Rojo + lune + Roblox Studio MCP の標準構成で一貫実行するためのスキル。目的は、この後のフェーズ実装がすぐ乗せられる土台（ファイルツリー・初期化の仕組み・ビルド確認・テスト基盤）を、手戻りなく用意すること。

Studioで手作業ノードを置くのではなく、**すべてコード（Rojo管理下のファイル）で構築する**。理由は、手作業構築は再現性がなく差分レビューもできないため。Studioは「同期先」であって「編集場所」ではない、という思想で進める。

## いつ使うか

- 新しいRobloxプロジェクトの骨格を最初に作るとき
- 既存の設計文書（GDD・フェーズ計画・詳細設計書）に基づいて Phase 0 / セットアップ工程を実行するとき
- 「Rojoの雛形」「Init/Startの初期化ループ」「tests骨格」「プロジェクト構造を用意」といった依頼

## 設計文書がある場合とない場合

このスキルは2モードで動く。**まず設計文書を探すことを最優先する**（`docs/` 配下や `CLAUDE.md`、`*phase*` `*design*` を含むファイル）。

- **文書がある**：それを正本とする。ディレクトリ構造・全モジュール名・初期化の依存順・命名規約・時刻正本（`now()`注入の有無）を文書から読み取り、そのとおりに骨格を作る。文書とこのスキルの手順が食い違う場合、**構造・命名・依存順は文書が勝つ**。このスキルは「作り方の型」だけを提供する。
- **文書がない**：下記テンプレートの標準骨格を生成する。モジュール名・依存順はユーザーに確認するか、最小構成（ServerMain/ClientMainと空のServices/Controllersフォルダ）で始める。

## 手順

### 0. ツール前提の確認

`rojo` / `lune` / `rokit` の有無を確認する。無いものがあれば導入する（rokitがあれば `rokit init` → `rokit add rojo-rbx/rojo` `rokit add lune-org/lune`。初回は `rokit trust <tool>` が要る）。

- **rojo**：ビルドとStudio同期の要。必須
- **lune**：ユニットテストランナー。テストを書くなら必須（無くてもrojo buildゲートは通る＝後回し可）
- **rokit**：ツールのバージョン固定。あれば `rokit.toml` で管理すると再現性が上がる

luneが未導入でも、Phase 0/セットアップの自動ゲートは `rojo build` だけなので、セットアップ自体は進められる。テスト実行フェーズの前に入れればよい。

### 1. 現状確認（衝突チェック）

`default.project.json` や `src/` が既にあるか確認する。上書き事故を避けるため、既存があれば中身を見てから進める。空の新規なら迷わず作る。

### 2. default.project.json（Rojoマッピング）

ソースの物理配置（`src/...`）を Roblox のサービス階層へ写像する。下の「テンプレート」を土台に、設計文書のディレクトリ構造へ合わせる。`Remotes` や `DroneTemplates` のような「実体は後のフェーズで生成するが位置だけ先に確保したいフォルダ」は `{"$className": "Folder"}` で宣言する。

### 3. モジュール空雛形（Init/Start形状）

Service / Controller は**依存注入つき2段階初期化**の形に統一する。理由は、全モジュールのInitが終わってからStartを呼ぶことで「初期化順の罠（まだInitされていない相手を参照する）」を構造的に消せるため。

```lua
--!strict
local M = {}
function M.Init(deps)  -- 依存注入・参照解決のみ。副作用禁止
end
function M.Start()     -- イベント接続・ループ開始。全Init完了後に呼ばれる
end
return M
```

注意すべき例外：**純粋データ層・純粋関数モジュール（型定義・定数・計算関数）はInit/Startを持たせない**。これらは副作用や状態を持ってはいけない層なので、`return <テーブル>` や `return <関数群>` の素の形にする。Init/Startを機械的に全ファイルへ付けないこと。

### 4. ServerMain / ClientMain（2段階初期化ループ）

エントリスクリプトは「依存順の配列」を持ち、その順で全モジュールを `Init(deps)` → 全部終わってから同順で `Start()` を呼ぶ。各ステップで `print` ログを出す設計にする（後のMCP検証で初期化順を目視確認するため）。

- ServerMainは `.server.luau` 拡張子（Rojoが `Script` にする）
- ClientMainは `.client.luau` 拡張子（Rojoが `LocalScript` にする）。配置先は `StarterPlayerScripts`
- 依存順は設計文書が正。無ければ「他に依存されるものを先に」の原則で並べる
- `deps` には時刻関数を入れておく（`now = function() return workspace:GetServerTimeNow() end`）。テストでモック差替できる形にするため

### 5. tests 骨格（lune）

`tests/run.luau` を一括実行エントリにする。この時点では中身は骨格でよい（本実装は次フェーズ）。luneで `build.rbxlx` を読み込んでRoblox形式の相対require（`script.Parent.X`）を解決するには、`deserializePlace` + `luau.load(environment=...)` のローダーを噛ませる（下記テンプレート参照）。Roblox datatypes（Vector3等）は `@lune/roblox` から環境へ注入する。

### 6. 自動ゲート：rojo build

```bash
rojo build -o build.rbxlx
```

exit 0 で成功。生成された `build.rbxlx` に主要ノード（ServerMain/ClientMain/各モジュール/位置確保フォルダ）が入っているか `grep` で軽く確認するとよい。**「動くはず」で完了報告しない**——ビルド出力（コマンドと結果）を必ず添える。

### 7. MCP 実機検証（Roblox Studio）

自動ゲートに加え、実機で初期化ループが無事故で回ることを確認する。

1. `rojo serve` をバックグラウンド起動（既定 `localhost:34872`）
2. ユーザーへ依頼：Studioで **Rojoプラグイン → Connect**（Host `localhost` / Port `34872`）→ Sync。**Rojoに「Connection Code」欄は無い**。Host + Port の2欄だけ。1欄しか無いならそれはRojoではない別プラグイン
3. 同期後、MCPで構造確認（`ServerScriptService.ServerMain` が `Script`、各モジュールが `ModuleScript` になっているか）
4. MCPで **Play開始** → 数秒待つ → コンソール出力を取得
5. `[ServerMain] Init ...` → `[ServerMain] Start ...` → `[ClientMain] ...` が**依存順どおり・エラーゼロ**で並ぶことを確認
6. **Play停止** → Edit復帰

MCP検証は環境（Studio起動・プラグイン接続）に依存するので、接続はユーザー操作を待つ。接続できない/スキップ希望なら、rojo buildゲート合格をもってセットアップ完了とする。

### 8. PROGRESS 記録

進捗ファイル（`PROGRESS.md` 等、プロジェクト規約に従う）へ、完了タスク・ゲート結果（コマンドと出力）・次フェーズへの引継ぎを記録する。設計文書に無い判断（例：追加ファイルの新設）をした場合は差異として明記する。

## テンプレート

### default.project.json

```json
{
  "name": "<ProjectName>",
  "tree": {
    "$className": "DataModel",
    "ReplicatedStorage": {
      "Shared": { "$path": "src/Shared" },
      "Remotes": { "$className": "Folder" }
    },
    "ServerScriptService": { "$path": "src/Server" },
    "StarterPlayer": {
      "StarterPlayerScripts": { "$path": "src/Client" }
    }
  }
}
```

「位置だけ先に確保したいフォルダ」は `{ "$className": "Folder" }` を追加する。

### ServerMain.server.luau

```lua
--!strict
-- Builders実行（あれば） → Service依存順 Init → 全Init後に Start
local ServerScriptService = game:GetService("ServerScriptService")
local Services = ServerScriptService:WaitForChild("Services")

-- 依存順（他に依存されるものを先に。設計文書があればそれに従う）
local INIT_ORDER = {
	-- "DataService", "LoadoutService", ... , "MatchService",
}

local deps = {
	now = function(): number
		return workspace:GetServerTimeNow()
	end,
}

local modules: { [string]: any } = {}
for _, name in ipairs(INIT_ORDER) do
	modules[name] = require(Services:WaitForChild(name))
end

for _, name in ipairs(INIT_ORDER) do
	local m = modules[name]
	if m.Init then m.Init(deps) end
	print(string.format("[ServerMain] Init %s", name))
end

for _, name in ipairs(INIT_ORDER) do
	local m = modules[name]
	if m.Start then m.Start() end
	print(string.format("[ServerMain] Start %s", name))
end

print("[ServerMain] 初期化完了")
```

### ClientMain.client.luau

`ServerScriptService` を `Players.LocalPlayer` と `script.Parent.Controllers` に、`Services` を `Controllers` に置き換えた同型。依存順は「入力→移動→カメラ→兵装→演出→UI」のように、下流が上流に依存する順で並べる。

### モジュール雛形（Service / Controller）

上の「手順3」のコードブロックをそのまま使う。純粋データ/関数層には付けない。

### tests/loader.luau（lune用 requireエミュレータ）

`build.rbxlx` を `roblox.deserializePlace` で読み、各ModuleScriptの `Source` を `luau.load` で実行する。環境テーブルに `script`（当該ModuleScript）・`require`（このエミュ関数を再帰）・`game`・`Vector3` 等のdatatypes（`@lune/roblox` から）・標準ライブラリを注入する。requireはキャッシュし、循環を検出したらエラーにする。これで Roblox形式の `require(script.Parent.X)` がluneで解決できる。

## よくある落とし穴

- **Shared層にInit/Startを付けてしまう**：純粋関数・データ層は副作用禁止。素の `return` にする。機械的に全ファイルへ2段階初期化を付けない
- **`.server.luau` / `.client.luau` を忘れる**：ただの `.luau` だとRojoは `ModuleScript` にする。エントリは実行スクリプトにするため拡張子で種別指定する
- **Rojo接続で「Connection Code」を探す**：標準RojoはHost + Portの2欄のみ。Connection Code欄は存在しない
- **luneが `build.rbxlx` を直接requireできると思う**：Roblox形式の相対requireはlune素では解決不可。`deserializePlace` + `luau.load` のローダーが要る
- **rojo serveのポート衝突**：既定34872。使用中なら別ポート。起動ログでlisteningを確認してからユーザーへ接続依頼する
- **サブエージェントのモデル解決不良**：オーケストレーションでサブエージェントに委譲する構成のとき、メインモデルによってはサブエージェントのモデル指定が誤ルーティングされ起動不能になることがある。その場合は `model` を明示オーバーライドするか、インライン実行に切り替える
- **数値・構造のハードコード**：バランス値やゲーム定数は設計文書側（データ定義・Config層）に置き、ロジックやエントリに埋め込まない

## 完了の目安

- `rojo build -o build.rbxlx` が exit 0
- （MCP検証まで行う場合）Play時に ServerMain/ClientMain の Init→Start ログが依存順・エラーゼロで出る
- 進捗ファイルにゲート結果を記録済み
