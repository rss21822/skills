# obby-rush メインメニュー / ショップ — "Retro Toy Box" スキン

依頼: 添付ムードボード（moodboard-retro-toys.png）の雰囲気で、obby-rush のメインメニューとショップ画面をかわいくする。名前で参照している他のスクリプトがあるので `tests/test_main_menu.luau` は通るままにする。

結論: 紺のダッシュボード風メニューを、ムードボードの「昔のおもちゃ箱」（クリーム色の厚紙、ココア色の太い縁、マスタードの斜め縞、ティールのドーナツリング、コーラルの額縁、星と紙吹雪、四角いブリキのロボット）に着せ替えた。名前・親子関係・コールバック・Text・Visible の規則は元のまま。契約テスト 29/29 PASS、新しいスキンテスト 41/41 PASS。Studio はこの実行では使えなかったので、実機での見た目の確認は未実施（後述）。

## 成果物（このフォルダ）

| パス | 内容 |
|---|---|
| `obby-rush/` | 作業コピー（原本は未変更）。変更点は下の「実装」 |
| `style-board.html` / `style-board.png` | skin spec の lint とスタイルボード（`skin_preview.py`）。コードを書く前の見た目合わせ |
| `preview-before-after.png` | 変更前後（1280x720、メイン / ショップを開いた状態） |
| `preview-main_1280x720.png`, `preview-shop_1280x720.png` | 完成形のメインとショップ |
| `preview-other-pages.png` | 設定・持ち物・クエスト（1280x720）とショップ（828x369） |
| `preview-phone-sizes.png` | 366x820（縦持ち）メイン / ショップ、828x369（横持ち）メイン |
| `preview-tools/` | プレビューの作り方（下の「検証」参照）と各シーンの JSON / HTML / PNG（`renders/`） |

プレビュー画像は Roblox の描画ではない。実際の Luau コードが Lune のモック上で組み立てた GUI ツリーを書き出し、Roblox のレイアウト規則（UDim2・AnchorPoint・Sibling ZIndex・UIListLayout・UIPadding・UIScale・UISizeConstraint・UICorner・UIStroke・UIGradient・TextScaled）を再実装した HTML で描いたもの。書体は Google Fonts の同名書体、日本語は M PLUS Rounded、絵文字は Windows の Segoe UI Emoji で代用している。

## 1. ムードボードの読み取り

`extract_palette.py` と画素のサンプリングで拾った色（抽出値そのまま）:

| 役割 | 色 | ボード上の出どころ |
|---|---|---|
| ink / outline | `#563426` ココア | 全部の縁、下の帯、「RETRO TOY BOX」ラベル |
| paper | `#F6ECD6` クリーム | 背景 |
| panel | `#FFF4DE` 生成り | コーラルの額縁の内側 |
| primary（CTA 専用） | `#F2B630` マスタード（ボード `#E8B034` を少しだけ明るく） | 縞・大きい星 |
| stripe（装飾用の淡いマスタード） | `#EEC66A` | 縞・装飾の星（CTA より一段弱くして主役を守る） |
| candies | tincar `#EE6C54` コーラル / ring `#269696` ティール / robot `#78BEDC` 空色 / gumdrop `#96CDA0` ミント | 額縁・ドーナツ・ロボット・紙吹雪 |
| coin | `#F7C640` | コインを Frame で描くための金色 |

6 軸への翻訳:
- **素材**: 印刷した厚紙のおもちゃ箱と塗装した木のブロック。つやは付けない（ボードが平塗りなので、kit の gloss はボタンから外した）。下縁（lip）だけ残して積み木の厚みにする。影はぼかさず、ココアの板を右下にずらす「版ずれ」風。
- **形**: 太い角丸（パネル 28 px、ボタン 16〜22 px、ピル）、ドーナツ、五芒星、丸。額縁の中に窓がある入れ子（コーラルの額縁＋クリームの窓）。ロゴと CTA だけ −2〜−3° 傾ける。
- **色**: 上表。写真ではなく平塗りのイラストなので、キャンディ色の彩度は上げずにボードの値を保った（上げると Pop 系の別物になる）。レトロの落ち着きは色そのもので、主役感は大きさ・傾き・後光で出す。
- **字**: 英字の見出しは LuckiestGuy（おもちゃ箱のロゴ、`latinOnly`）、見出し・ボタンは FredokaOne Bold、本文は Nunito Bold / Heavy。日本語はすべてシステムの CJK 書体に落ちるので Bold 以上を要求。
- **生き物・小物**: ボードのロボット（空色の四角い頭、コーラルのアンテナ玉、白い目、マスタードのボルトと口、ほっぺ）を 12 個の Frame で描いた。星は「★」の文字グリフ＋ココアの縁取り、ドーナツは Frame 2 枚、紙吹雪は丸い Frame。アイコン絵文字はおもちゃで統一（🎁 🧸 ⭐ 🔧、商品 🌀 🌈 🦘）。
- **動き**: ねじ巻きおもちゃのように「弾む・ゆらぐ」。押すと沈んで Back で戻る、ページはポップして開く、常時ループは CTA の後光の呼吸とロボットの揺れ＋まばたきの 2 つだけ。reduced motion で全ループ停止、状態変化は即時。

lint: エラー 0・警告 0、本文（ink on paper）のコントラスト 9.3:1。途中で lint が `icons.coin 🪙`（Unicode 13 の絵文字は Roblox で豆腐になる）をエラーにしたので、コインは Frame で描く方針に切り替えた。

## 2. 画面ごとのデザイン

**メイン（主役画面）**
- 画面上端に「おもちゃ箱のふた」: 淡いマスタードの 45° 縞＋ココアの太い罫線（ボードの上帯そのまま）。
- 「OBBY RUSH」はココアのラベルテープ（ボードの「RETRO TOY BOX」ラベル）に LuckiestGuy の生成り文字、−2° 傾けて版ずれ影。コインは生成りのピル＋Frame で描いた金貨＋数字。
- CTA「プレイ」: 画面で一番大きく明るいマスタードのピル（300x88、−3°、白文字＋ココア縁取り）、呼吸する後光、右上にコーラルの★ステッカー、版ずれ影。隣でロボットが揺れてまばたきする（画面幅 820 未満・高さ 520 未満では隠す）。
- ドック: 4 枚の積み木タイル（124x100）。色はそれぞれ開くページの額縁と同じ（ショップ=コーラル、持ち物=ティール、クエスト=空色、設定=ミント）。上に絵文字、下に白文字＋縁取りのラベル。開いているページのタイルは −4° 傾いて★が付く。
- 背景: クリーム一面に、左にティールのドーナツ、右に大きな星、紙吹雪。CTA の周りには置かない。短辺に合わせて縮む。

**ショップ（もう一つの主役）**
- ページはコーラルの額縁＋クリームの窓（ボードの額縁そのもの）。見出し帯にクリームの丸バッジ（🎁、−8°）と白文字＋縁取りの「ショップ」、右に生成りの「閉じる」ピル。額縁の上辺に「RETRO TOY SHOP」のラベルテープ（英字のみ、狭いとき・全画面シートのときは隠す）。
- 商品の行は棚のカード: 行ごとに違うパステル（コーラル / ティール / 空色）、左に傾いたおもちゃバッジ（🌀 🌈 🦘）、商品名は Nunito Heavy、値段はココアのテープに金貨＋数字、「購入」はマスタードの積み木にココア文字。
- ページを開くと背景がココア色の薄い暗幕で沈み、ページは版ずれ影つきでポップする。ドックとトップバーは暗幕の上に残る。

**その他のページ（同じ ScreenGui の中なので揃えた。手間は軽め）**
- 設定: ミントの額縁。トグルは ON でミント＋ティールのスイッチ、OFF でクリーム＋灰色のスイッチ（ノブが動く）。🎵 🔊 アイコン。
- 持ち物: ティールの額縁、空の一覧にロボットが待っている（動かない版）。
- クエスト: 空色の額縁、「準備中」の下に 3 色の★。

**画面サイズ**: 1280x720 ではページをふたとドックの間に収め、横持ちスマホ（828x369）のように間が狭いときは全高のシートにする。縦持ち（366x820）ではトップバーを Roblox のトップバー（GetGuiInset）の下へ下げ、ドックを縮め、商品行はバッジを外して名前と値段の幅を確保する。

## 3. 実装

方式: スキルの「方式 A（実行時スキン）」を MainMenu の ScreenGui だけに掛ける形。`UITheme` は全画面共有なので触っていない（他の画面の見た目は変わらない）。

- `src/client/MainMenu.luau`（+32/−3 行）: 元の組み立てを `buildPlain` に名前だけ移し、`MainMenu.build` は「素の組み立て → `RetroToySkin.apply(gui)`」。スキンが読めない・どこかの段で失敗したら、途中まで着せた gui を Destroy して素の組み立てをやり直す（半端な見た目や UI が出ない状態を作らない）。`MainMenu.useSkin = false` で素の見た目（テスト・A/B 用）。`MainMenu.open` と各コールバックは変更なし。
- `src/client/MenuSkin/MotifSkinKit.luau`: スキルの kit をそのままコピー（バイト一致）。
- `src/client/MenuSkin/MotifSpec.luau`: `design/retro-toy-skin.json` から `skin_preview.py --luau` で生成（手で編集しない）。
- `src/client/MenuSkin/RetroToySkin.luau`: アダプタ本体。10 段（root / topBar / play / nav / pages / shop / settings / empty / fit / motion）。
- `design/retro-toy-skin.json`: skin spec（色・書体・形・アイコン・ロボット）。
- `tests/test_menu_skin.luau`: スキンのテスト（新規）。`tests/test_main_menu.luau` と `tests/mock.luau` は変更なし（バイト一致を確認）。
- `README.md`: 上記ファイルの説明を末尾に追記。

名前の契約を守るためにしたこと:
- 元の Instance は一つも消さず、名前・親を変えない。追加したものは全部 `Motif` で始まる名前（例外なし、テストで検査）。位置・大きさ・色・書体・ZIndex・回転などの見た目の値だけ書き換えた。
- Theme がパネルとボタンに付ける 1 px の UIStroke は、2 本目の Border ストロークを重ねずに同じ Instance を `MotifEdge` として再利用（名前が変わるのは UI 修飾子の UIStroke だけ）。
- Theme のボタンは MouseEnter / MouseLeave で自前の紺色を BackgroundColor3 に書き戻すので、BackgroundColor3 の変化を監視して設計した面に塗り直す。
- CoinLabel / Price の `Text`（`🪙 1250` など）は変えない。🪙 は Roblox で豆腐になるため、元のラベルの文字だけ透明にして、子のラベルが Text を絵文字抜きでミラーし、横に金貨を Frame で描く。他のスクリプトが後で Text を書き換えても追従する。

## 4. 検証したこと

| 項目 | 結果 |
|---|---|
| 契約テスト `lune run tests/test_main_menu.luau` | PASS 29/29（スキン適用後の画面に対して実行されている） |
| スキンテスト `lune run tests/test_menu_skin.luau` | PASS 41/41: スキンが本当に掛かる（黙って素の見た目に落ちていない）、素の組み立ての全 GuiObject / レイアウトが同じパス・クラスで残る、追加物は Motif 名のみ、Text 不変、旧 Theme 色（紺・アクセント・旧文字色）が見える面・文字・縁に残っていない、1 つの Instance に Border ストロークは 1 本、CTA・購入・タイル・行の面と文字色、絵文字の箱が TextSize の 1.5 倍以上、ホバーで紺に戻らない、押下で沈み離すと戻る、ページ開閉で暗幕・影・タイルの印が追従、トグルの面とスイッチが状態に追従、reduced motion でループ 0、apply の冪等性、途中の段で失敗したら素のメニューだけが 1 つ残る |
| テストが壊れを検出できるか | ホバーの塗り直しと背景色を一時的に外した変異版で、スキンテストが該当 2 件を FAIL にすることを確認（その後元に戻した） |
| 全 Luau のコンパイル | `luau.compile` で 9 ファイル OK |
| spec の lint | エラー 0・警告 0（最初は 🪙 がエラー → 対応） |
| Rojo | `rojo build`（7.7.0）成功。Client の下に MenuSkin / MotifSkinKit / MotifSpec / RetroToySkin が入る |
| 目視（プレビュー） | 1280x720・828x369・366x820 × メイン / ショップ / 設定 / 持ち物 / クエスト を描いて確認。最初の版で見つけた問題を直した: ページがドックに触れる → ふたとドックの間に配置、横持ちでページがトップバーに半端に重なる → 全高シートに、縦持ちで商品名が購入ボタンに潰される → 狭い行はバッジを外す、全高シートでラベルテープが画面外に切れる → 隠す、装飾が小さい画面で大きすぎる → 短辺で縮小 |

自己レビュー（スキルの品質基準）: 面はクリーム / コーラル / ティールなどモチーフの色相、縁はココア 3〜4 px、CTA が一番大きく明るく傾いて後光付き、同種の要素にも色の変化（タイル 4 色・行 3 色）、字は 3 段（LuckiestGuy / FredokaOne / Nunito）、ロボット・星・ドーナツ・縞・紙吹雪がいる、1 画面の主役は 1 つ。

## 5. 検証できなかったこと（Studio が使えなかった）

この実行では Roblox Studio を別ジョブが使っていたため、Studio の MCP には一切触れていない。次は未確認:

- Studio での Play と `studio_ui_audit.luau`（TextFits・48 px・はみ出し・重なり）を 3 サイズで流すこと、`screen_capture` での目視。プレビューは実際の Luau の出力だが描画は HTML の再現なので、グリフの幅・CJK フォールバックの太さ・絵文字の絵柄・TextScaled の縮み方は Roblox と違いうる。
- 「★」（U+2605）が Roblox のフォールバック書体で描かれ、Contextual の UIStroke が効くこと（描かれない場合は星の装飾だけが欠ける。機能には影響しない）。
- ふたの縞: 回転した Frame を CanvasGroup で切り抜いている。CanvasGroup が使えない端末では縞がふたの下へ最大 30 px ほどはみ出す可能性。
- Theme のホバー色を塗り直す監視が、Deferred のシグナル動作で 1 フレームのちらつきも出ないこと。
- `GuiService:GetGuiInset()` による縦持ち時のトップバー位置、Roblox のトップバーのボタンとロゴの重なり具合。
- 窓（`MotifWindow`、Active）が、全高シート時にページ越しのドックへのタップを止めること。
- 実機（スマホ・タブレット・ゲームパッド）での押しやすさ、reduced motion の実挙動。
- Place への反映: この課題は Rojo 構成なので通常のビルドで反映される想定。Studio 保存の正本 Place があるかどうかは確認していない。

## 6. 変えていない範囲とその理由

- `src/shared/UITheme.luau`: 「全画面が使う」共有モジュール。依頼はメインメニューとショップなので、試合中の HUD など他画面の見た目を巻き込まないよう変更なし。スキンは MainMenu の ScreenGui にだけ掛かる。
- ボタンの文言・商品データ・購入 / 設定 / 遷移の振る舞い・ページの開閉規則（`MainMenu.open`）。
- 「購入できない」状態や「NEW」札などの表示は、元に状態が無いので作っていない。
- メイン画面のロボットの揺れ tween は kit が内部で持っているため、`gui.Enabled = false` の間も止まらない（後光のループは止まる）。コストは小さいが、気になるなら kit から tween を返してもらう小改修が次の候補。

## 7. 次の候補

1. Studio で Play し、`studio_ui_audit.luau` を 1080x720 / 828x369 / 366x820 で回して失敗 0 まで直す。★グリフと CanvasGroup の縞を目で確認。
2. 購入時のフィードバック（コインのカウントダウン、行が弾む）と、持ち物にアイテムが入ったときのカード表示。
3. 試合中の HUD やリザルトにも同じ spec を広げるかどうかの判断（UITheme を通す画面は同じアダプタ方式で広げられる）。

## 再現方法

```bash
cd obby-rush
lune run tests/test_main_menu.luau          # 契約テスト
lune run tests/test_menu_skin.luau          # スキンテスト
python <skill>/scripts/skin_preview.py design/retro-toy-skin.json --html ../style-board.html --png ../style-board.png --luau src/client/MenuSkin/MotifSpec.luau
cd .. && python preview-tools/make_previews.py obby-rush .   # プレビュー一式を再生成
```
