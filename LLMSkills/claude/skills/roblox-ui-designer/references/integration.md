# 既存 UI への組み込み

## 目次
1. 棚卸しで見るもの
2. 方式の選び方
3. 実行時スキン（アダプタ）の作り方
4. 主役画面の作り直し
5. Place への適用
6. 記録と報告

## 1. 棚卸しで見るもの

- **テーマ/スタイルの中心**: 色表（`Theme.colors` のような table）、ボタン・ラベル・パネル・入力欄を作る関数、フォントの指定箇所。無い場合は各画面が直接 `Instance.new` している。`grep -rn "Color3.fromRGB\|BackgroundColor3 =" src` で色の散らばりを把握する。
- **画面の一覧**: ロビー/メイン、モード選択、ショップ、インベントリ、設定、リザルト、ロード/遷移、HUD、ワールドの看板（BillboardGui / SurfaceGui、サーバー側で作られていることが多い）。
- **名前の契約**: テスト（`grep -rn "FindFirstChild(\"" tests scripts`）、他のスクリプト、QA ツールが参照する Instance 名・属性・階層。ここを変えると見た目以外が壊れる。
- **描画の仕組み**: 画面を毎回作り直す（render 関数で子を全消去して再生成）のか、一度作って更新するのか。作り直す型なら、スキンは「作られるたび」に掛かる必要がある（→ 生成関数を包む方式が合う）。
- **他の編集者**: `git status`、`git log -5 -- <file>`。他の人・セッションが同じファイルを編集中なら、そのファイルは触らずに包む。
- **Place の構成**: Rojo プロジェクト（`*.project.json`）でスクリプトを組み立てるのか、Studio で保存された `.rbxl(x)` にスクリプトが直接入っていて、それが正本なのか。

## 2. 方式の選び方

- **A. 実行時スキン（推奨）**: 起動時に 1 回、テーマの色表をその場で書き換え、生成関数を包む。
  - 利点: 共有コードを編集しない（衝突しない）、画面が増えても自動で掛かる、失敗しても元の見た目に戻る、特定の Place（ロビーだけ等）に限定できる。
  - 向く: テーマ関数を経由して画面が作られている、共有コードを他者が持っている、テストが既存の構造を固定している。
- **B. 直接編集**: テーマ関数そのものを書き換える。
  - 向く: 小さなコードベースを自分だけが触る、テーマ関数が無く各画面に色が散らばっている（この場合はまず色をテーマ表へ集約してから）。
- **C. 主役画面の新規作成**: 方式 A/B と併用。主役画面は既存の部品の塗り替えでは届かないので、専用の組み立て関数を書き、失敗したら元の組み立てへ戻す。

## 3. 実行時スキン（アダプタ）の作り方

```lua
-- ui/MotifSkin.luau (client)
local Kit = require(script.Parent.MotifSkinKit)
local kit = Kit.new(require(script.Parent.MotifSpec))
local Skin = {kit = kit}

function Skin.apply(Theme)
	if type(Theme) ~= "table" or type(Theme.button) ~= "function" then return false end
	if Theme.skin == Skin then return true end -- 冪等: 2 回呼ばれても包み直さない
	local P = kit.P
	-- 1) 色表は「その場で」書き換える。モジュールが起動時に Theme.colors の参照を
	--    ローカルへ取っていても、同じ table なので新しい色が見える。
	local C = Theme.colors
	C.background, C.panel, C.text, C.accent = P.paper, P.panel, P.ink, P.primary
	-- 2) 生成関数を包む。元の関数に作らせてから、見た目だけ上書きする。
	local button = Theme.button
	Theme.button = function(parent, name, text, callback, options)
		local object = button(parent, name, text, callback, options)
		pcall(kit.styleButton, kit, object, {
			role = options and options.primary and "primary" or (NAME_ROLES[name] or "plain"),
			order = options and options.order, emoji = ICONS[name] or ICONS[string.match(name, "^([^_]+)_") or ""],
		})
		return object
	end
	-- label / panel / input も同じ形で包む
	Theme.skin = Skin
	return true
end
return Skin
```

要点:
- **包む前に元の関数を保存し、元の関数に作らせる**。名前・コールバック・有効判定は元のまま。
- **Name で役割と絵文字を引く表**（`NAME_ROLES`, `ICONS`）: 「キャンセル系は danger」「退出系は tangerine」「`Open_shop` は 🛍️」。完全一致 → `_` より前の接頭辞の順で引くと、`ShopCategory_emote` のような動的な名前にも効く。
- **既存のホバー/押下の演出と喧嘩させない**: テーマ側に状態変化のコールバック（onState 等）があればそれに乗って `kit:paint(button, state)` を呼ぶ。テーマが自前で色を戻す処理を持つなら、それが走った後に塗り直す。`MotifSkinKit:styleButton` の既定の入力処理は、テーマ側に状態管理が無い場合用（`interactive = false` で切れる）。
- **旧配色が引数で渡される箇所**: 呼び出し側が旧テーマの色（紺など）を直接渡していたら、アダプタで「旧色 → 新しい役割」に読み替える表を持つ。
- **範囲を限定する**: スキンを適用するのは入口スクリプト（例: ロビー Place のクライアント起動スクリプト）だけにすれば、試合 Place などは元の見た目のまま残せる。共有モジュールの中では `Theme.skin` の有無で分岐する。
- **失敗時に戻す**: 主役画面の専用組み立ては `pcall` し、失敗したら途中まで作った Instance を消して元の組み立てを呼ぶ。スキンの不具合で画面が出ないことだけは避ける。
- **描画の再入に注意**: 描画中に自分の大きさを変える処理（UISizeConstraint の変更など）があると、AbsoluteSize の監視から描画が同期的に再入し、同じ内容が二重に並ぶ。スキンで大きさを変えるときは、描画関数に「描画中フラグ」があるか確認する。

## 4. 主役画面の作り直し

プレイヤーが最初に見て最も長く見る画面から順に:

1. **メイン / ドック**: CTA を 1 つだけ突出させる（主役色、ピル型、少し傾ける、呼吸する後光）。副次の入口はアイコンタイルで横一列（6 個前後、各 92 px 角、絵文字＋短いラベル）。
2. **モード / ステージ選択**: 「箱絵」にする。カードの上 2/3 に ViewportFrame で小さな情景（床、壁、キャラ、そのモードの特徴物）を描き、下 1/3 にステッカーのモード名と一言タグ。未実装モードは縞模様で無反応（ボタンにしない）。
3. **ロード / 遷移**: 何を待っているかを大きく、進捗をキャラが歩くバーで、背景はゆっくり回る光線。数秒しか見ない画面こそ印象に残る。
4. **リザルト**: 勝敗のスタンプ（傾いた大きな英字＋縁取り）、報酬のカウントアップ、次の行動の CTA 1 つ。
5. **ワールドの看板**: 紙の板＋色のリボン＋絵文字バッジ。サーバーで作る看板もクライアントの UI と同じ配色表を使う。

既存テストが要求する Name は、作り直した画面でも同じ Name・同じ親関係で置く。演出用の部品は子として追加し、元の部品を消さない。

## 5. Place への適用

- **Rojo 構成**: ソースを直せば通常のビルドで反映。ビルド結果の Place をバックアップしてから。
- **Studio 保存の Place が正本**の場合（手で置いたアセットやアリーナが入っている）: `rojo build` で上書きすると手作業の部分が消える。変更したスクリプトの `Source` だけを差し込み（新規 ModuleScript は所定のフォルダへ挿入）、Source 以外の XML が変わっていないことを機械的に確かめる。差し込む前に Place をバックアップし、差し込む Source が正本の現行 Source と比べて自分の変更だけであること（他の未完了作業を運んでいないこと）を確認する。
- 共有モジュール（複数の Place に入っているもの）を変えたら、全 Place に同じ Source を入れる。スキンを適用しない Place では見た目は変わらないが、Place 間で共有モジュールの中身が食い違うと後で追跡できなくなる。
- 反映後、更新した Place のコピーを Studio で開いて Play し、エラー 0 と主要画面の表示を確認する。

## 6. 記録と報告

- 決定の記録（プロジェクトに DECISIONS 等があればそこへ）: 依頼、モチーフの翻訳、方式、変更ファイル、検証、見送り、バックアップの場所。
- 報告: 何が変わったか（画面ごとに 1 行）、変えていない範囲とその理由、検証（数値と目視）、未検証（実機・他言語）、次の候補（例: 試合中の HUD にも広げる）。
