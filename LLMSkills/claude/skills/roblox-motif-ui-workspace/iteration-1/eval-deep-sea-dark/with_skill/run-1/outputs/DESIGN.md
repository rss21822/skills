# obby-rush 「深海探検」スキン — Abyss Lantern

依頼: obby-rush の UI を「深海探検」モチーフに（チョウチンアンコウの光・光るクラゲ・泡）。暗くてよいが、紺色のダッシュボードっぽさは出さない。テストは壊さない。

作業場所: `obby-rush/`（元の `evals/files/obby-rush` のコピー。元ファイルは未変更）。

## 1. モチーフの読み（6 軸）

| 軸 | 決定 |
|---|---|
| 素材 | 内側から光る深い青緑の海ガラス。縁は生物発光（明るい縁 3 px＋太く半透明の 2 本目のストローク）。ボタンはクラゲの「ゼリーガラス」（暗い色味＋艶の帯） |
| 形 | 泡とクラゲの傘のように丸い: パネル角丸 24、ボタンはピルか 18〜26、ドックのタイルの下に光る玉の触手 |
| 色 | 暗さは hue ≈180 の青緑（紺の帯 195〜250 に入れない）。主役はチョウチンアンコウの誘引突起のレモン色 `#FFE04D`（PLAY 専用）。発光色 5 つ: kurage `#FF62C6` / umibotaru `#34EFDA` / mendako `#FF8B4E` / murasaki `#B27BFF` / umiushi `#AEEF5C`。縁取り・明るい面の文字は暗い青緑 `#03181A`、本文は泡色 `#E8FFF7` |
| 字 | LuckiestGuy（英字の叫び: OBBY RUSH / DIVE!、日本語は自動で FredokaOne に切替）、FredokaOne Bold（見出し・ボタン）、Nunito Bold/Heavy（本文。日本語フォールバックが太く出るよう Bold 以上） |
| 生き物・小物 | 誘引突起で PLAY を照らすチョウチンアンコウ（Frame 26 部品）、遠くを漂う半透明のクラゲ 2 匹、空のページのクラゲ（顔つき）、真鍮リベットの舷窓バッジ（🐡・各ページの絵文字）、泡、マリンスノー、水面からの光の筋 |
| 動き | 泡がゆっくり上昇、PLAY の後光が呼吸（1.8 s）、アンコウがゆらり＋まばたき。すべて Sine/Linear のゆっくりした動き、点滅なし。reduced motion で全ループ停止、メニュー非表示中は一時停止 |

## 2. 「紺のダッシュボード」を外すためにしたこと

- 面の色相を青緑（hue 173〜186）に固定。深さのグラデーションも「水面の青緑 → 海ガラス → ほぼ黒の青緑」で全停止点を同じ色相に置き、紺を経由しない（青緑→紫のグラデーションは中間で紺になるので不採用）。
- ドック用の暗い色味（pastels）は発光色を黒へ寄せて作る（紙の青緑へ寄せると紫が紺 hue 247 に落ちるのを board で発見し、黒寄せ hue 265 に修正）。
- 全幅のヘッダーバー（最もダッシュボード的な形）を消し、タイトルは水中に浮かぶピンク発光の看板（−3° 傾き）＋舷窓に。コインは金縁のピル。
- 主役は 1 つ: レモン色のピル型 PLAY（300×84、−2°、呼吸する後光、「DIVE!」のピンクのステッカー、横にアンコウ）。他のボタンは暗いゼリー色で主役と競わない。
- ドックはページごとに色の違うクラゲ（ピンク/シアン/オレンジ/紫）で、同種要素にも色の変化。選択中のページのタイルだけ発光色で点灯。
- ページは色付きリボン（泡のドット、インクの罫線、舷窓バッジ）で、1 px 半透明の縁は使っていない（縁 3〜3.5 px）。

## 3. 実装

方式: スキルの推奨どおり **A. 実行時スキン＋主役画面の専用ドレッシング**。共有の `UITheme.luau` は無変更。

| ファイル | 内容 |
|---|---|
| `obby-rush/design/deep-sea.skin.json` | skin spec（正本）。`skin_preview.py` で lint・board・Luau を生成 |
| `obby-rush/src/client/ui/MotifSpec.luau` | spec から生成（手で編集しない） |
| `obby-rush/src/client/ui/MotifSkinKit.luau` | スキルの `assets/MotifSkinKit.luau` の無改変コピー |
| `obby-rush/src/client/ui/DeepSeaSkin.luau` | 新規。`Skin.apply(Theme)`: `Theme.colors` をその場で塗り替え、`stroke/panel/label/button` を包む（冪等、`Skin.restore` で元に戻せる）。`Skin.decorate(gui)`: water / topBar / lure / dock / pages / responsive / motion の 7 セクション。各セクションは pcall され、失敗したらそのセクションが足した Instance を消して warn |
| `obby-rush/src/client/MainMenu.luau` | 最小の変更: スキンを `pcall(require)` し、`build` の最初で `Skin.apply`、最後で `Skin.decorate`（どちらも pcall）。コイン絵文字 `🪙`→`💰` |
| `obby-rush/tests/test_deep_sea_skin.luau` | 新規。スキンの Lune テスト（64 項目） |
| `obby-rush/README.md` | 追加ファイルの説明を追記 |

守った契約: `tests/test_main_menu.luau` が見る Name・親子関係・コールバック・ページ切替の Visible 規則・タッチ領域はすべて元のまま。追加した部品はすべて `Motif*` という名前の子として足し、元の部品は消していない。

見た目以外に触れた点（意図的・小さい）:
- `🪙` は Unicode 13 で、Roblox では豆腐（□）になる（スキルの fonts.md / lint が検出）。元のゲームでもコイン表示が壊れていたので `💰`（Unicode 6）に変更。テストは「1250」を含むことだけを見るので影響なし。使った絵文字はすべて Unicode 12 以前（🤿🐚💎🗺️⚙️🐡💰🌀🌈⏫🎵🔊🐠🦑🐙⭐）。
- ページを開いている間は暗幕 `MotifScrim`（Active）で背面の PLAY 等へのクリックの貫通を防ぐ。ドックは暗幕より上なのでページ間の直接切替は従来どおり可能。ページ自体も `Active = true`（元は PLAY がページ越しに押せた）。
- 画面サイズ対応（`responsive`）: 幅 < 700 でページを横幅いっぱいに、ドックは幅に合わせて 4 等分（最大 600 px）、舷窓を隠してタイトル幅を確保、アンコウは PLAY の上へ。高さ < 480（横持ちスマホ）では PLAY を 0.5 に上げ、ドックを下げて後光とタイルが重ならないように。
- UITheme 側のホバー処理が面の色を上書きするので、スキンは MouseEnter/Leave の後に `task.defer` で塗り直す（ハンドラの実行順は保証されないため）。

## 4. 検証したこと

| 項目 | 結果 |
|---|---|
| spec の lint（`skin_preview.py --strict`） | **0 error / 0 warning**。本文コントラスト（インク/紙）11.9:1。途中で `🪙` の豆腐エラーと、pastel の紫が紺 hue になる問題を検出して修正 |
| 全 Luau のコンパイル（Lune `luau.compile`） | src 6 ファイル＋テスト＋プレビュー＋監査スクリプト すべて OK |
| 既存の契約テスト `lune run tests/test_main_menu.luau` | **PASS 29/29**（`test_main_menu.luau` と `mock.luau` は無変更、元とバイト一致を確認） |
| スキンのテスト `lune run tests/test_deep_sea_skin.luau` | **PASS 64/64**。スキンが pcall に握りつぶされず実際に全 7 セクション実行されたこと、warn 0、旧紺色の面・縁が残っていないこと（旧 4 色＋lint と同じ紺判定）、全ボタンの文字色が面の明るさ規則どおり、PLAY/ドック/ページ/行/購入ボタンの配色、ホバー後の塗り直し、ページ⇔暗幕⇔選択タイルの同期、トグルのスイッチが ON/OFF 文字列に追従、3 サイズの配置、ループ数と非表示時の一時停止、apply の冪等・restore・再適用、2 つ目のメニュー、セクション失敗時の巻き戻し、reduced motion でループ 0、スキン読込失敗時に素の UI で契約の名前が揃い PLAY が動くこと |
| 目視（オフライン描画） | Lune のモックで**実際の MainMenu の Instance ツリー**を組み、簡易レイアウト（UDim2/AnchorPoint/UIPadding/UIListLayout/UISizeConstraint/UIScale/AutomaticSize）を回して AbsoluteSize をスキンへ返し、HTML にして headless Chrome で撮影（`preview/render_menu.luau`, `preview/shoot.py`）。1280×720・828×369・366×820 × メイン/各ページ、と適用前 |

目視で見つけて直したもの（style board → 描画 → 修正を 3 周）:
- 全幅のトップバーがダッシュボードに見える → 廃止し浮かぶ看板＋舷窓に。
- PLAY の周りの大きなピル型の光だまりが「板」に見える → 光はアンコウの電球を中心にした同心円（spec の `LureGlow*`）へ移し、PLAY は細い後光のリングだけに。
- 背景クラゲの白い芯が灰色の柱・バイザーに見える → 芯と口腕を自分の色を明るくした色に、細く小さく。
- 設定のトグルに艶の帯があると進捗バーに見える → トグルは艶なし、文字 20 pt。
- 横持ちスマホで PLAY の後光がドックに触れる／縦持ちでタイトルが 14 px まで縮む／縦持ちでクラゲがアンコウに重なる → responsive を調整。
- ページが半透明で背後の PLAY が透ける → 面を不透明に。

## 5. 検証できなかったこと（Studio がこのジョブでは使えなかったため）

- **Studio での Play と監査**: `studio_ui_audit.obby-rush.luau`（このメニュー用に CONFIG を設定済み、未実行）を Play 中に execute_luau（Client）で、Device Simulator の 3 端末で実行し FIT / SMALL / CLIPPED / OVERLAP を 0 にする必要がある。モックにはレイアウトも文字計測もないので、`TextFits`（特に縦持ちスマホのドックの「クエスト」17 pt、商品名、fitHeading した見出し）は未確認。
- **本物の描画**: 書体（LuckiestGuy / FredokaOne / Nunito の `Font.new` が実際に効くか、日本語フォールバックの太さ）、絵文字の描画、UIStroke Border の太さと 2 重発光の見え方、UIGradient（深さ・光の筋・暗幕）、ZIndex（Sibling）での重なり順。オフライン描画は Google Fonts の代替書体と CSS 近似であり、Roblox の画素そのものではない。
- **動きと入力の手触り**: 泡の上昇速度、後光の呼吸、アンコウの揺れとまばたき（モックでは `task.spawn` が動かない）、ホバー時の `task.defer` 塗り直しのちらつき有無、押下の沈み込み、ゲームパッド選択。reduced motion は起動時の値で判定（実行中に設定を切り替えた場合の追従は未実装）。
- **性能**: スキンが足す Instance は約 745（素の UI は 85。ドット・玉・泡・クラゲの部品と、それぞれの UICorner/UIStroke を含む。ページのリボンのドットは 22→16 個に削減済み）、常時ループの tween は 16 本（泡 14＋後光＋アンコウの揺れ。まばたきは task ループ）。すべて静的な Frame で毎フレームの処理は無いが、低性能スマホでの描画負荷は未測定。多ければマリンスノー（38）とリボンのドットを減らすのが最初の手。
- **英語ロケール**、ワールドの看板や試合中 HUD（このサンプルには存在しない）。

## 6. 次の候補

1. Studio で Play → 監査スクリプトを 3 端末で実行 → 各画面のスクリーンショットで目視。
2. 試合中の HUD やワールドの看板（BillboardGui）にも同じ spec の色を使う（サーバー側は MotifSpec を ReplicatedStorage に置けば共用可）。
3. 泡の効果音・購入時の「泡がはじける」演出。

## 7. 作り直し方

```bash
# spec を直したら（skill の scripts から）
PYTHONIOENCODING=utf-8 python <skill>/scripts/skin_preview.py obby-rush/design/deep-sea.skin.json \
  --html style-board.html --png style-board.png --luau obby-rush/src/client/ui/MotifSpec.luau --strict
# テスト（obby-rush フォルダで）
lune run tests/test_main_menu.luau
lune run tests/test_deep_sea_skin.luau
# オフライン描画（obby-rush フォルダで → outputs 直下に render-*.html、続けて撮影）
lune run ../preview/render_menu.luau
python ../preview/shoot.py
```

## 8. 出力物（outputs 直下）

- `style-board.png` / `.html` — spec の style board（lint 結果・配色とコントラスト・ボタン・ドック・アンコウ）
- `preview-before-after.png` — 適用前後（デスクトップのメインとショップ）。※ 適用前の描画もコイン絵文字は修正後の 💰
- `preview-pages.png` — 設定（スイッチ）と持ち物（空のページのクラゲ）
- `preview-phones.png` — 横持ち 828×369 / 縦持ち 366×820 のメインとショップ
- `render-*.png` / `render-*.html` — 各場面の単体描画
- `studio_ui_audit.obby-rush.luau` — Studio 監査用（未実行）
- `preview/` — オフライン描画の道具
- `obby-rush/` — 変更後のプロジェクト
