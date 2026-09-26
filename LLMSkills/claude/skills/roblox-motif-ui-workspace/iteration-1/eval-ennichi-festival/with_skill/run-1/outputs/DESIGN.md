# obby-rush メインメニュー作り直し: 「夏祭りの縁日」スキン (Ennichi Night Stall)

依頼: 紺色の「いかにも AI が作った」メインメニューを、モチーフ「夏祭りの縁日（提灯・金魚すくい・りんご飴・ラムネ）」で作り直す。
`tests/test_main_menu.luau` は通ったまま。作業は `obby-rush/`（コピー）のみ。元のファイルは未変更。

見る順番: `preview-sheet-desktop.png`（左上が作り直し前、右上が作り直し後、下は各ページ）→ `preview-sheet-phone.png` → `style-board.png`。

## 1. モチーフの読み方（6 軸）と翻訳

| 軸 | モチーフから | 画面への翻訳 |
|---|---|---|
| 素材 | 和紙の提灯、屋台の木の台、暖簾、りんご飴の艶、ラムネ瓶のガラス | 面は和紙色 `#FFF4DE`、縁は墨茶 `#3A1E14` の 3〜4 px。ボタンは飴の艶（gloss）と押し込める下縁（lip）。屋台の台は木目グラデーション |
| 形 | 丸い提灯、上下の黒い輪、暖簾の切れ目、屋台の縞の日よけ | PLAY は上下に墨の輪・紐・フック・竹の輪が付いた大提灯（-2° 傾け）。ナビは縞の日よけ付きの屋台正面。ページ見出しは切れ目の入った暖簾 |
| 色 | 夕暮れの空、提灯の灯、りんご飴の赤、金魚の橙、ラムネの水色 | 空は茄子紫→茜→夕焼け。主役色は提灯の灯 `#FFC02E`（PLAY 専用）。屋台 4 色: りんご飴 `#E8304F` / 金魚 `#FF7A2F` / 射的の若葉 `#45B84A` / ラムネ `#23AEE0`（+藤・綿あめ） |
| 字 | 手描きの屋台看板 | 3 段: 飾り見出し PermanentMarker（英字のロゴのみ、`latinOnly`）/ DenkOne Bold・FredokaOne Bold（見出し・ボタン）/ Nunito Bold・Heavy（本文）。日本語は全部 Bold 以上を要求（CJK フォールバックが太く描かれる） |
| 生き物・小物 | 金魚、提灯、りんご飴、ラムネ、ポイ、風鈴、射的の的、花火 | Frame で描いた金魚マスコット（瞬き・揺れ）、金魚袋、りんご飴、ラムネ瓶（ビー玉入り）、金魚すくいの水槽とポイ、風鈴（金魚柄）、射的の的と「準備中」の木札、花火 2 つ。絵文字は 🏮🍎🐠🎯🎐🥁🔔🌀🌈🐸💰（すべて Unicode 12 以前） |
| 動き | 提灯がゆっくり揺れる、灯が息づく | 提灯の列が 2.4〜3 s でゆらゆら、PLAY の灯（3 層の光）が 1.8 s で呼吸、金魚がゆっくり揺れて時々瞬き、風鈴が揺れる。押すと 94% に縮んで下縁が沈む。reduced motion ではループを作らない。メニューが非表示（`Enabled=false`）の間はループを一時停止 |

「AI っぽさ」を外した点: 紺・スレートの面を全廃（lint で紺判定 0）、1 px 半透明の水色の縁を 3 px の墨の縁に（テストで検査）、CTA は画面で一番大きく一番明るい唯一の主役色、ナビ 4 つは同形だが色と絵が全部違う、字の階層 3 段、空白は花火・星・浴衣の水玉・小物で「演出」に。

## 2. 画面ごと

- **メイン**: 夕暮れの空（星・花火）→ 看板（TopBar: 🏮 バッジ、赤いマーカー書体の OBBY RUSH、和紙のコイン札）→ 看板の下に垂れる提灯の列（祭の字、赤と白が交互、画面幅で 3〜11 個）→ 中央に大提灯の PLAY（灯が呼吸）→ 屋台の木の台と、その上の屋台正面ナビ 4 枚。横長の広い画面では台の上に金魚袋・りんご飴・ラムネ、縦長スマホでは小さな棚に並べてナビの上の空白を埋める。
- **ページ共通**（ショップ/持ち物/クエスト/設定）: 屋台と同じ色の暖簾見出し＋丸い絵文字バッジ＋白抜き見出し、紙の閉じるボタン、下のほうに浴衣の水玉。背面に茄子色の暗幕とステッカーの影。開いているページの屋台タイルは暗幕の上に残り、内側が提灯の金色に光る（タブ表示）。
- **ショップ**: 行はパステル（行ごとに色違い）＋商品アイコンのバッジ＋紐穴付きの値札（💰 300）＋金魚色の「購入」。行の幅が狭いときは値札を名前の下に回し、購入ボタンを 92 px に。
- **設定**: 行の右に ON/OFF スイッチ（トグルの文字 ON/OFF を監視して連動）、左に 🥁/🔔。広いページでは金魚柄の風鈴が揺れる。
- **持ち物（空）**: 金魚すくいの水槽で泳ぐ金魚とポイ、その上に「まだアイテムがありません」を中央寄せ。
- **クエスト（空）**: 射的の的と「準備中」の木札、その上に元の文言。

## 3. 実装の方式と変更範囲

方式は skill の「A. 実行時スキン」＋「C. 主役画面の作り直し」。共有の `UITheme` は編集せず、実行時に包む。

| ファイル | 変更 |
|---|---|
| `design/ennichi-skin.json` | 新規。配色・書体・形・絵文字・金魚マスコットの正本（skin spec） |
| `src/client/Ennichi/EnnichiSpec.luau` | 新規・生成物（`skin_preview.py --luau`。手で編集しない） |
| `src/client/Ennichi/MotifSkinKit.luau` | 新規。skill の kit を無改変でコピー |
| `src/client/Ennichi/EnnichiSkin.luau` | 新規。`Skin.apply(Theme)`: `Theme.colors` をその場で書き換え、`panel/label/button/stroke` を包む（元の関数に作らせてから見た目だけ変える）。冪等、途中で失敗したら元のテーマに戻す。旧テーマのホバー処理が旧色を書き戻すので、`task.defer` で塗り直す |
| `src/client/Ennichi/EnnichiScene.luau` | 新規。メニューの演出（空・提灯・大提灯・屋台・小物・暖簾・値札・スイッチ・空状態の絵）とレスポンシブ配置。足すのは `Motif*` の Instance だけ。例外が起きたら自分が足した `Motif*` を全部消して warn（メニューはテーマ級のスキンのまま動く） |
| `src/client/MainMenu.luau` | 最小変更: スキン/シーンを `pcall(require)` で任意読み込み、`build` 冒頭で `Skin.apply`、末尾で `Scene.decorate`、演出用に既存 Instance の参照（refs）を集める、コイン表記 |
| `README.md` | スキンの節を追記 |
| `tests/ennichi_harness.luau`, `tests/test_ennichi_skin.luau` | 新規。スキンのテストと共用ハーネス |
| `tools/ui_preview/*` | 新規。Studio 無しのプレビュー描画と監査、Studio 用監査の設定済みコピー |
| 変更なし | `tests/test_main_menu.luau`, `tests/mock.luau`, `src/shared/UITheme.luau`, `MenuEntry.client.luau`, `default.project.json`（diff で確認） |

名前の契約: Instance の Name・親子関係・コールバック・有効判定は元のまま（`TopBar.CoinLabel` の直下関係、`NavBar` の子はタイルだけ、各ページ直下の `Title`/`CloseButton`、`Product_*/BuyButton`、`Toggle_*` などをスキンテストでも固定）。ボタンの `Text` も変えていない（ナビのラベルはボタン自身の Text を下寄せにして使用）。

見た目のために変えた既存プロパティ（振る舞いは不変）:
- サイズ・位置: PLAY 300x96（狭い画面で縮小、最小 225x72）、ナビ 120x96 ＋ `UIScale`（最小 0.5 倍でも 60x48）、購入 92〜104x48、ページは中央寄せ＋`UISizeConstraint`（340x330〜820x560、電話の縦持ちで 0.6 幅だと 220 px しかなかったため）、設定の行を暖簾の下へ 20 px 下げた。すべてタッチ領域 48 px 以上。
- `Background` を不透明に（元は 25% 透過で背後のワールドが見えた。夕暮れの空で塗るため）。
- `MainMenu` ScreenGui の `ZIndexBehavior` を `Sibling` に固定（重なり順が兄弟間の ZIndex 前提のため）。
- コイン表記を `🪙 1250` → `💰 1,250`。🪙 は Unicode 13 の絵文字で Roblox では豆腐（□）になる（skill の lint が検出）。契約テストは `1250` / `1,250` の両方を許容している。**他のスクリプトが CoinLabel.Text を `🪙 ...` 形式で書き換えている場合はそちらも 💰 に合わせる必要がある。**

スキンの範囲: `Skin.apply` は `UITheme` テーブルを実行時に書き換えるので、MainMenu を作った後にクライアントで `UITheme` 経由で作られる他の画面も同じ和紙＋墨の見た目になる（意図的。サーバー側の看板などには掛からない）。

## 4. 検証したこと（すべてこの環境で実行）

| 検証 | 結果 |
|---|---|
| `skin_preview.py` lint（紺判定・書体実在・コントラスト・絵文字の Unicode 版） | 0 error / 0 warning（本文 墨/和紙 14.0:1）。`style-board.html/png` |
| 全 Luau のコンパイル（`luau.compile`、src/tests/tools の 13 ファイル） | 13/13 OK |
| 契約テスト `lune run tests/test_main_menu.luau` | **PASS 29/29** |
| スキンテスト `lune run tests/test_ennichi_skin.luau` | **PASS 92/92**: スキン適用と冪等、紺色の残りゼロ（テーマ表・全 Instance の面）、細い半透明の縁ゼロ、名前の契約、各ボタンの面と文字色、ホバー/離脱で屋台色が戻らないこと、押下で下縁が沈む、ページを開くと暗幕とタブ点灯、スイッチが ON/OFF に連動、4 サイズ（1280x720/1080x720/828x369/366x820）で PLAY が提灯列とナビの間に収まる・ナビが幅に収まる・48 px・小物が PLAY と重ならない、reduced motion でループ 0、シーンの失敗時に `Motif*` が全部消えてメニューが動く、Ennichi フォルダが無くても素のテーマで組み上がる |
| kit 自己テスト（skill 同梱） | PASS 25 |
| テストが本当に落ちるか（ミューテーション） | `Scene.decorate` を外す → 多数 FAIL・exit 1。`Theme.stroke` の差し替えを外す → 細い縁の検査が FAIL。元に戻して全 PASS |
| 見た目: 実際の Luau が作った Instance ツリーを Lune で JSON に書き出し、ブラウザで描画してスクリーンショット（`preview-*.png`、11 状態 × 3 サイズ） | 目視: 3 秒で縁日とわかる、PLAY が一番強い、読めない文字なし、日本語は太く表示。見直しで直した点: 提灯の光と PLAY の光が灰色の円盤に見えた→暖色 3 層に、暗幕でタブの点灯が隠れた→暗幕を屋台タイルの下へ、設定行が暖簾に接触、空状態の文言が左上に孤立、狭い画面で暖簾の切れ目が見出しに刺さる、狭い行で商品名が折り返す、縦持ちでナビ上に空白 |
| プレビューの DOM 監査（文字の収まり・48 px・画面外・ボタン重なり） | 11 状態すべて 0 件（`preview-audit.json`）。監査自体の健全性: コイン札を 40x20 に、タイルを 40x40 に壊したダンプでは FIT 2 件・SMALL 1 件を検出 |
| Instance 数・常時ループ | 素 85 → スキン後 1,228（ドット柄の角丸を削って 1,552 から削減）。表示中のメイン画面は約 600（ページは閉じている間 Visible=false）。常時ループの tween 16（提灯 11 本は 1 つの「揺れ」、ほかに PLAY の灯 2、金魚 2、風鈴 1） |

## 5. 検証できなかったこと（Studio はこの実行では使用不可 = 別ジョブが占有）

skill の手順 5-3（Studio で Play して `studio_ui_audit.luau` を実行）と 5-4 のうち Studio の実画面の目視は**未実施**。代わりのブラウザ描画は近似で、次が Roblox と違いうる:
- 書体: Google Fonts の同名書体で代用。日本語は Noto Sans JP（Roblox は端末の CJK フォント）。`TextFits` の実値は Studio でしか分からない。
- 絵文字: Windows の Segoe UI Emoji で描画（Roblox 独自の絵文字フォントとは絵柄と大きさが違う）。Unicode 12 以前に限定済み。
- エンジン挙動の前提: UIStroke(Border) が外側に描かれる、`UIScale` がアンカー基準で縮む、`UICorner` のスケール値が短辺基準、UIListLayout の揃え。どれも崩れても機能は壊れないが見た目がずれる可能性。
- 実機・タッチ・Device Simulator、`GuiService.ReducedMotionEnabled` の実機切替、ホバー/押下の手触り（Lune では tween が即時完了）、モバイルでの描画負荷。
- Rojo ビルド（`rojo build`）は未実行（ツールを使っていない。プロジェクト構成は変更なし、新規ファイルは `src/client/Ennichi/` 配下の ModuleScript のみ）。

Studio が空いたら: Play → `tools/ui_preview/studio_ui_audit.luau` を MCP `execute_luau`（Client）で実行（メイン＋4 ページ × 3 サイズ、ページが前面のモーダルである重なりは除外設定済み）→ 各画面の screen_capture を目視。

## 6. 次の候補

- 他の画面（試合中 HUD、リザルト）へ同じ spec を展開。PLAY を押した後の遷移（提灯が灯って暗転）を作ると統一感が出る。
- CoinLabel を書き換える他スクリプトの表記（🪙）を 💰 に揃える。
- 暖簾や浴衣の水玉を 9 スライス画像 1 枚に置き換えれば Instance 数をさらに減らせる（今回は画像アセット無しの方針）。

## 再実行

```bash
cd obby-rush
lune run tests/test_main_menu.luau          # 契約
lune run tests/test_ennichi_skin.luau       # スキン
python <skill>/scripts/skin_preview.py design/ennichi-skin.json --html board.html --png board.png --luau src/client/Ennichi/EnnichiSpec.luau
lune run tools/ui_preview/dump_menu.luau out && python tools/ui_preview/render_preview.py out previews
lune run tools/ui_preview/dump_menu.luau out-before --plain   # 作り直し前（素のテーマ）
```

`preview-before-*.png` は現在の MainMenu をスキン無しで描いたもの（コイン表記だけは新しい 💰 1,250）。
