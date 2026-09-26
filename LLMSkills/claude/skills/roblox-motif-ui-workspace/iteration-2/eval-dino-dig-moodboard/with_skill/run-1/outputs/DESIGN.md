# obby-rush メインメニュー / ショップ — "Lost Valley Dig"

## モチーフブリーフ

```
モチーフ: 恐竜の発掘調査をするジャングル（moodboard-dino-dig.png）
トーン: 冒険・わくわく（子供向けの探検）＋手作りの調査記録。フラットで艶なし
7 軸: 素材 = 調査ノートの生成り紙・砂岩の石板・地層の土・琥珀（唯一光る素材）・蔓と葉・骨
      形   = 角の小さい紙(4-6px)、丸みのある石板(14px)、琥珀だけカプセル、蔓は折れ線＋丸い葉、縁は 3px の焦げ茶
      色   = ムードボードの 6 色見本そのまま: ジャングル #3E622E / 若葉 #8CAA46 / 琥珀 #EFA52B(#D07A14) /
             骨 #F0E4C4 / 土 #5C3E26 / 目印の赤 #B43C22 ＋ 砂 #E2D3B0・額縁の焦げ茶 #3A2616(インク)
      字   = 見出し・ボタン Oswald Bold（"FIELD NOTES" の太い細長ゴシック）/ 注記 SpecialElite（タイプライター、英字のみ）
             / 本文 Montserrat Bold・ExtraBold。日本語は全部 Bold 以上
      物   = 虫入り琥珀、アンモナイト、恐竜の骨格、発掘グリッドの杭と糸、赤い旗と X、刷毛、足跡。マスコットは作らない
      動き = 静か。琥珀だけ 2.4 s でゆっくり光る（ページが開いている間は停止）、押すと小さく沈む、ページは 0.18 s でスッと出る
世界の中の UI: CTA = 土に埋まった虫入り琥珀（発掘グリッドの中）/ パネル = FIELD NOTES のページ / ナビ = 地層に並んだ化石の石板
使わないもの: キャンディ色・艶と下縁のステッカー語彙・白文字の縁取り・傾いた黄色いピル・マスコット・紺
              （ムードボードはフラットで縁取り文字も艶も無い。琥珀のハイライトだけは素材として残した）
言い換えテスト: 「ジャングルで恐竜の化石を掘る調査隊」— 決め手は上の低ポリの葉と垂れる蔓、下の地層と骨格、琥珀の CTA、緑帯のフィールドノート
```

モチーフ名を伏せたサブエージェントに home / shop の画像だけを見せた結果: 「先史時代の化石発掘現場・古生物学の調査キャンプ」「PLAY は虫入りの磨いた琥珀に見える」。

## ムードボードからの翻訳

| ムードボード | 画面 |
|---|---|
| ジャングルの写真パネル（低ポリの葉） | 画面上部の林冠。葉は「菱形 2 枚を軸方向に並べて明暗 2 面に割った凧形」で描画し、下端は垂れ下がる葉でギザギザに終わる |
| パネルを横切る蔓 | 左右に垂れる蔓、タイトルカードとノートの右端に絡む短い蔓（ボタンには掛からない位置に制限） |
| AMBER（虫入り琥珀） | PLAY ボタン＝琥珀（濃い琥珀の縁 6px、ハイライト、琥珀越しに見える虫）。土の窪みと杭・糸の発掘グリッドの中に置き、ゆっくり光る。通貨表示と価格も琥珀の粒 |
| FIELD NOTES No.07（緑帯＋罫線の紙、Site/Layer の注記） | タイトルカード（OBBY RUSH / EXPEDITION No.07）、全ページ（緑の見出し帯＋タイプライターの「FIELD NOTES No.0X · …」＋罫線）、CTA 上の「DIG SITE A-7 · CRETACEOUS」札 |
| 土の中の骨格・刷毛 | 画面下部の地層（表土・土・岩盤）、発掘グリッド、骨格、刷毛、アンモナイト |
| アンモナイトの石板 | ナビ＝砂岩の石板。各石板に「土の窓」から覗く発見物（琥珀 / 骨 / 赤い点線と X / 刷毛）。開いているページの石板は緑に |
| 赤い点線ルートと X | クエストのアイコンと空状態 |
| 6 色の見本 | spec のパレットにそのまま（役割を割り当て直し） |

ショップの行は「標本ラベル」: 骨色の標本トレイ（⚡🌈🦘、Unicode 12 以下）、SPECIMEN No.00X、商品名、琥珀＋価格、緑の「購入」。

## 実装（`obby-rush/`）

- 方式: 実行時スキン（skill の方式 A）＋主役画面の作り込み。`MainMenu.luau` は起動時にスキンを読み、`UITheme` の色表をその場で書き換えて生成関数を包み、ビルド後に `Skin.decorate(gui, state)` を呼ぶだけ。読み込み・装飾に失敗しても pcall で元のメニューが出る。
- 追加: `src/client/DigSite/DinoDigSkin.luau`（アダプタと場面・主役部品）、`MotifSpec.luau`（`dino-dig-skin.spec.json` から `skin_preview.py --luau` で生成）、`MotifSkinKit.luau`（skill の kit を無改変コピー）。
- 既存ファイルの変更は最小: `UITheme.luau` はホバーで色を戻す処理に「スキン済みなら何もしない」ガード 2 行、`MainMenu.luau` は読み込みと decorate 呼び出し、`README.md` に説明。
- 名前・親子関係・コールバック・Visible の切替は変えていない。装飾はすべて `Motif*` の非アクティブな Frame/TextLabel で、ボタンは 1 つも増やしていない（14 個のまま）。
- ついでに直したもの（見た目の範囲）: `🪙`（Unicode 13）は Roblox で豆腐になるため、コイン表示・価格から取り除いて描画した琥珀に置換（後から他スクリプトが Text を書き換えても除去）／旧タイトルが Roblox のトップバーの下に潜っていたのを `kit:clearTopbar` で下へ／開いたページの空白をタップすると下の PLAY に届いていたので、ページを `Active = true` に。
- 小さい画面: 高さ 520 未満では発掘グリッドの糸・杭・旗・札と足跡を省き、ナビは横幅に合わせて UIScale で縮める。

## 検証

- `lune run tests/test_main_menu.luau` → 29/29 PASS（tests\ は無変更。元ファイルと diff 一致を確認）。
- `lune run skin-tests/test_dino_dig_skin.luau` → 39/39 PASS: エラー・警告 0、冪等、旧配色の残り 0、名前の契約とボタン数、CTA が最大で琥珀＋暗い文字、全ボタンの文字コントラスト ≥ 4.5、日本語は Bold 以上・タイプライター書体に日本語なし、Unicode 13 以降の絵文字なし、コインの豆腐除去（更新後も）、ページ開閉で暗幕・石板の選択・琥珀の光が追従、トグルの ON/OFF 色、ホバーで色が戻らない、reduced motion で tween 0、decorate 失敗時とスキン欠落時に元のメニューで動くこと。
- `lune run skin-tests/compile_check.luau` → src の全 Luau がコンパイル OK。
- プレビュー: `skin-tests/render_preview.luau` が実際の Luau のインスタンスツリーを HTML に書き出し（UDim2・UICorner・UIStroke・UIGradient・UIPadding・UIListLayout・UIScale・ZIndex・書体）、headless Chrome で撮影＋レイアウト監査（文字の収まり・48px・重なり・装飾がボタンを覆う・Roblox トップバー）。5 画面 × 1280x720 / 844x390 / 1024x768 の 15 状態すべて AUDIT PASS（元の UI は「タイトルがトップバーの下」で失敗）。結果は `preview/audit.txt`。

成果物: `preview.html`（一覧）、`preview-home.png`、`preview-shop.png`、`preview-before-after.png`、`preview-moodboard-vs-menu.png`、`preview-all-screens.png`、`preview-small-screens.png`、`style-board.png/html`（spec の lint: 0 error / 0 warning）、`dino-dig-skin.spec.json`。

## 未検証・注意

- Studio では未確認（指示どおり Studio は使っていない）。プレビューは Google Fonts の同等書体と Noto Sans JP で描いた近似で、Roblox の実際の文字幅・CJK フォールバックとは差がある。次の段階では Studio の Play で `studio_ui_audit.luau` と画面キャプチャを取るのが残作業。
- 縦持ちスマホは対象外（元のレイアウトも横持ち前提で、ナビ 560px が収まらない）。
- 装飾で GuiObject が約 810 個（林冠だけで約 260）。静的なので描画負荷は小さいはずだが、低スペック端末で重ければ林冠の葉の数（`inside`/`hanging`）を減らす。
- 背景は不透明にした（元は 25% 透過で 3D ワールドが透けていた）。ワールドを見せたい場合は `buildScene` の `BackgroundTransparency` を戻し、林冠と地層だけ残す。
