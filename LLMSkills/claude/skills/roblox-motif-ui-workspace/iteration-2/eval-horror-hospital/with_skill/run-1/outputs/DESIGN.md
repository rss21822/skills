# NIGHT WARD — モチーフの翻訳メモ

## ブリーフ

```
モチーフ: 「夜の廃病院から脱出する」ホラー obby。怖い雰囲気、でも小学生も遊ぶからグロは無し
トーン: 怖い（静かで不穏）× 子供向け
7 軸: 素材 … 病院の備品（クリップボードに挟んだ黄ばんだカルテ、琺瑯の病室番号プレート、
            非常口の誘導灯、受付番号の LED 表示、廊下のタイルと手すり）
      形   … ほぼ直角（角 2〜4 px）、ネジ留め、鋼のクリップ。傾けるのは判子と下敷きの紙だけ
      色   … 闇は緑がかった黒（#0B1512 / hue 163、紺ではない）。紙 #E3D9B8、インク #2B2A22、
            主役は安全緑 #087A3F（非常口の色）、差し色は発光緑・蛍光灯・懐中電灯・LED の琥珀・朱肉
      字   … 声 = SpecialElite（タイプライター、英字のみ）/ 見出し・ボタン = Oswald Bold・Arimo Heavy /
            本文 = Arimo Bold。日本語は全部 Bold 以上を要求（システム書体に太く落ちる）
      物   … マスコット無し。非常口のピクトグラム（走る人とドア）、クリップ、判子、表示灯
      動き … ゆっくりだけ。懐中電灯の光溜まりが 7.5 秒で漂う、誘導灯の光が 2.8 秒でにじむ、
            蛍光灯が 4.5〜9.5 秒に 1 回だけ 0.12 秒暗くなる（点滅はしない）。押すと沈む（暗くなる）
世界の中の UI: CTA = 非常口の誘導灯「脱出する / EMERGENCY EXIT」
              パネル = クリップボードのカルテ（WARD B1 · KIOSK / PATIENT: <プレイヤー名>）
              ナビ = 病室の琺瑯ドアプレート（B1 KIOSK / 107 LOCKER / 203 NURSE / B2 CONTROL）＋表示灯
              その他 = トップバー = 病棟の案内板、コイン = 受付番号の LED、購入 = 朱肉のスタンプ、
                       設定 = 管理室の壁スイッチ、空のページ = 「記録なし」「準備中」の判
使わないもの: 血・傷・注射器・手術器具・顔・怪物・ジャンプスケア・3 Hz 以上の明滅（子供向け）/
              艶・下縁・弾む押下・傾いたピルの CTA・キャンディ色・絵文字・マスコット（可愛いトーンの語彙）/
              ドロドロの Creepster（垂れる文字が血に見える）/ 紺の半透明パネルと 1 px の水色の縁
言い換えテスト: 緑の非常口の誘導灯、病室番号のドア、カルテのクリップボード → 「夜の病院から逃げるゲーム」
```

## 実装の方針

- 配色と書体は `obby-rush/design/night-ward.skin.json` が正本。`skin_preview.py` で lint（0 error / 0 warning）し、
  `src/shared/Motif/MotifSpec.luau` を生成。`MotifSkinKit.luau` をそのままコピーして使用。
- `UITheme.luau` は API（colors / create / panel / label / button …）を変えずに中身だけ差し替え。
  既存キーの意味（`panel` は暗い面に明るい `text`）を守ったので、他の画面も読める配色のまま NIGHT WARD になる。
  1 px 半透明の縁は不透明 2 px の塗装の縁に、押下は「縮む」ではなく「暗く沈む」に。
- 主役画面は `src/client/NightWardArt.luau` で組み立て直し、`MainMenu.luau` の最後から 1 回呼ぶ。
  各工程は pcall で独立しており、失敗しても（モジュールごと無くても）元のテーマの画面は出る。
- 名前の契約はそのまま: `MainMenu` / `Background` / `TopBar`（`Title` `CoinLabel`）/ `PlayButton` / `NavBar`（`Nav_*`）/
  `*Page`（`Title` `CloseButton` `ProductList` `Product_<id>` `BuyButton` `Toggle_Music` `Toggle_SFX` `Empty`）、
  コールバック、ページ切替、`Toggle_*` の Text（"ON"/"OFF"）。装飾は `Motif*` の子として足しただけ。
  `PlayButton.Text` は "脱出する" のまま保持し、表示は鏡写しのラベル（Text の変化に追従）。
- 変更した既存の見た目上の値: タイトル "OBBY RUSH" → "NIGHT WARD"、プレイ → 脱出する、閉じる → × 閉じる、
  コイン表示 "🪙 1250" → "1,250"（🪙 は Unicode 13 で Roblox では豆腐になるため、描いたコインに置換）。
- レイアウト: トップバーは `TopbarInset`（取れなければ 58 px）の下へ。縦持ちは見出し 2 行・ドック 2×2、横持ちは
  キッカーを畳んで誘導灯とドックを縮小、カルテは案内板とドックの間に収める。ショップ行は狭いと 2 段に詰める。
- 見送ったもの: 商品名（スピードコイル等）はショップのデータなので変更していない（ブラインド評価で「虹のトレイル」
  だけ世界観から浮くと指摘あり → 次の候補）。BGM・効果音、試合中 HUD、ワールドの看板は範囲外。

## 検証

- `lune run tests/test_main_menu.luau` — 29/29 PASS（tests/ は無変更、sha256 一致を確認）。
- `lune run design/test_night_ward_skin.luau` — 66/66 PASS: 警告 0、紺なし、主役色は CTA だけ、各部品の存在、
  押下・ホバー・スタンプの押印・ページを開くと表示灯が点く、スイッチが Text に追従、reduced motion でループ 0、
  非表示でループ停止と値の復元、縦/横スマホのレイアウト、NightWardArt が無い／1 工程が落ちても契約の名前は揃う。
- 全 Luau を `luau.compile` で確認（9 ファイル OK）。
- プレビュー（`design/render_all.sh`）: 実際の Luau を Lune で組み立て、Instance ツリーを Roblox の規則
  （UDim2・AnchorPoint・UIPadding・UIListLayout/Wraps・UIScale・UISizeConstraint・ZIndex Sibling・UICorner・
  UIStroke・UIGradient・TextScaled）で描いて headless Chrome で撮影。9 ビュー × 監査（実際に下に塗られた色との
  コントラスト、UIScale 後 48 px、トップバー下、画面外、ボタン重なり、ブラウザ実測の文字の収まり）で 0 件。
  最初の監査で EXIT の文字（3.8:1）、ドアプレートの部屋番号（4.2:1）、縦持ちショップの価格と購入の重なりを検出して修正。
- 言い換えテスト: モチーフを伏せたサブエージェントに画像 3 枚だけを見せたところ「夜の廃病院から、夜明けまでに
  非常口へ逃げる脱出ゲーム」と特定。決め手は誘導灯・病室のドアと廊下・カルテのクリップボード。グロ無し・子供可、
  CTA が最も目立つとの評価。指摘のうち「プレースホルダーに見える染みの輪」「押せそうに見えるチェック欄」
  「小さい部屋番号」は修正済み（染みを削除、行番号 01/02/03 に、13→14 px）。

## 未検証（Studio を使っていないため）

- Studio での実描画: 書体（Google Fonts の同名書体で代用）、日本語フォールバックの太さ、UIStroke の外側描画、
  `UIListLayout.Wraps` の行間、`GuiService.TopbarInset`、実機のタッチ。次は Studio で Play し
  `scripts/studio_ui_audit.luau` を 3 サイズで流し、各画面を screen_capture で確認するのが手順。
- 動き（光溜まりの漂い、誘導灯のにじみ、蛍光灯の暗転、カルテのスライド）は Lune のモックと静止画でしか見ていない。

## ファイル

- `obby-rush/src/shared/UITheme.luau`（改）、`src/client/MainMenu.luau`（改）、`src/client/NightWardArt.luau`（新）、
  `src/shared/Motif/MotifSpec.luau`（生成）、`src/shared/Motif/MotifSkinKit.luau`（コピー）、`README.md`（改）
- `obby-rush/design/`（ビルド対象外）: spec JSON、スキンテスト、ハーネス、ダンプ、レンダラ、`render_all.sh`
- `preview.html`（一覧）、`preview-*.png` / `preview-*.html`（9 ビュー）、`style-board.png` / `.html`
