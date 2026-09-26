# Obby Rush メインメニュー — 「夏祭りの縁日」リデザイン

作業したのはコピー `outputs/obby-rush/` だけです。元のプロジェクトは変更していません。
`tests/test_main_menu.luau` と `tests/mock.luau` も変更していません。

- 変更前: `preview_before_main.png`
- 変更後: `preview_main.png`、`preview_contact_sheet.png`(8画面)、`preview_idle_motion.gif`(待機アニメ)

## 1. 元のUIの問題点

- 紺(#0B1426 / #13233F)の上に水色(#3FA9F5)というよくある配色。フォントは Gotham。角丸の四角に 1px の水色枠を付けただけ。何のゲームなのかが画面から伝わらなかった。
- PLAY ボタンの文字色と背景色のコントラストは **2.23:1** で、大きい文字の基準(3:1)にも届いていなかった。
- ボタンは平らな板で、押せそうに見えなかった。押したときの反応もなかった。ページを開いても、どのタブが開いているか分からなかった。

## 2. コンセプト: 夕暮れの境内に並ぶ縁日の屋台

モチーフを画面の端に飾るだけにせず、UI の部品そのものにモチーフの役割を持たせました。

| UI の部品 | モチーフ | 意図 |
|---|---|---|
| 背景 `Background` | 夕焼けの空(藤紫→茜→橙)から、下は境内の暗い地面へ | 紺色を使わない。下が暗いので、下部の木札(ナビ)がはっきり見える |
| `TopBar` | 屋台の木の看板。赤い判子「祭」、ロゴは手描き看板風の LuckiestGuy | 屋台の雰囲気の入口 |
| コイン表示 `CoinLabel` | 生成りの札に**五円玉**のアイコン、`1,250` | 縁日のお小遣い |
| 提灯の列 `LanternGarland` | 縄から赤「祭」と白「夏」の提灯を交互に吊るす。揺れて、灯りがゆらぐ | 縁日と一目で分かる要素 |
| 中央 `GoldfishTub` | **金魚すくい**の水槽。赤・更紗・出目金が泳ぎ、波紋が広がる。「きんぎょすくい」の札とポイ | 画面の主役 |
| `PlayButton` | **灯った提灯**として描いた朱色の大ボタン(黒い上輪・下輪と骨の線、水面に映る灯り) | 一番押してほしいボタンが一番明るい |
| 左の飾り | **りんご飴**の屋台(3本と木の台、値札) | モチーフ |
| 右の飾り | 氷水で冷やした**ラムネ**2本(ビー玉・くびれ・ラベル・泡) | モチーフ |
| ナビ `Nav_*` | 屋台の**木札**。アイコンは ショップ=りんご飴、持ち物=**金魚袋**(持ち帰るもの)、クエスト=射的の的、設定=うちわ | 開いているページの木札は朱色で「灯る」 |
| 各ページ | 生成りの和紙のパネル。上部は色違いの**暖簾**(ショップ=朱、持ち物=ラムネ青、クエスト=若竹、設定=藤) | タブの区別がつく |
| 商品の行 | 屋号紋(商品名の頭文字)+ 五円玉の値段 + 朱色の「購入」 | 屋台の品書き |
| 設定のトグル | 音楽=太鼓、効果音=風鈴。スイッチは**ラムネのビー玉**が転がる(ON=泡の出るラムネ色、OFF=空き瓶の灰色) | ラムネを操作部品に使った |
| 空のページ | 持ち物=空の金魚袋、クエスト=矢の刺さった的 | 空の状態でも寂しく見えない |

### パレット(`Theme.palette`)
朱 `#E0382B` / 生成り `#FFF4DE` / 墨 `#2B1A14` / 屋台の木 `#B5743C`・`#E8B676`・`#6A3B1C` / ラムネ `#74D4E4`・`#1F8FAD` /
金魚 `#FF5A2C` / りんご飴 `#D8122C` / 五円玉 `#EDB83E` / 夕暮れ `#3E1A57 → #9C3A6A → #E8854A → 地面 #4A1E2C`。
紺は使っていません。一番暗い色も紫〜臙脂系です。

### 形とボタン
- ボタンは「面(Face)」の下に濃い色の「縁(Lip)」がある押しボタンです。押している間は面が 4px 沈み、ホバーすると少し明るくなります。ゲームパッドやキーボードで選択したときは、灰色の四角ではなく金色の太枠が出ます。
- パネルは和紙色で、濃い木の色の 2〜3px の枠です。文字は墨色、朱色の上の文字は生成り色に暗い縁取りを付けました。

### 動き
- 待機中: 提灯が揺れて灯りがゆらぐ、金魚が泳ぐ(進む向きに回転し、尾を振る)、波紋、ラムネの泡、PLAY の灯りの脈動。
  全部 Heartbeat の接続1本で動かしています。画面を閉じると(`Destroying`)接続を切り、非表示のあいだは止まります。
- 操作したとき: ボタンが沈む、ページが開くときにポップする(`UIScale`、Back イージング)、ラムネのスイッチでビー玉が転がる。
- `GuiService.ReducedMotionEnabled` が有効なときは、待機アニメを止めて静止ポーズにします。tween もすぐ最終状態にします。

### レイアウトと画面サイズ
- Roblox 本体のトップバー(メニュー・チャットボタン)の下に隠れないよう、`GuiService:GetGuiInset()` の高さだけ看板を下げます(元の UI はこのボタンの下に重なっていました)。
- 提灯は `UIScale` で縮めます(短い辺 390px の横向きスマホで 0.55 倍)。**ボタンは縮めません**。タッチしやすい大きさを保つためです。
- 水槽・PLAY・左右の屋台は、提灯と木札のあいだの空きスペースの中央に置きます。すべて UDim2 のオフセットで計算しているので、`ViewportSize` が変わったときに計算し直すだけで済みます。
- ページは看板のすぐ下から始まり、木札の手前で終わります。スマホでは高さが最小値の 240px になり、木札の上に重なります。ページには閉じるボタンがあるので操作はできます。
- 確認したサイズ: 1280×720、1024×768、844×390(横向きスマホ)。縦向きのスマホは対象外です(元の UI も木札の列が幅 560px 固定でした)。

## 3. 他のスクリプトとの互換性(壊していないもの)

- テストが見ている名前はすべて残しました。元の**親子関係のパス**もそのままです:
  `MainMenu.Background.TopBar.{Title,CoinLabel}`、`Background.PlayButton`、`Background.NavBar.Nav_*`、
  `MainMenu.{Shop,Inventory,Quests,Settings}Page.{Title,CloseButton}`、`ShopPage.ProductList.Product_<id>.{ProductName,Price,BuyButton}`、
  `SettingsPage.Toggle_{Music,SFX}`、`InventoryPage/QuestsPage.Empty`。
- `MainMenu.build(playerGui, handlers, state)` と `MainMenu.open(gui, pageId)` の引数と動作は変えていません。追加したのは `MainMenu.setCoins(gui, n)` と `MainMenu.formatCoins` だけです。
- ボタンの `Text` と `TextColor3` は今までどおり TextButton 本体にあります。本体の文字は非表示にして、見える文字は `Face.Label` に描いています。他のスクリプトが `button.Text = ...` と書き換えても表示に反映されます(確認済み)。
- `UITheme` のキーと関数は元のまま使えます: `Theme.colors.*`、`font/fontBold`、`create/corner/stroke/panel/label/button`。

### 気をつける点
- `Theme.label` の文字色の初期値は墨(暗い色)になりました。和紙のパネルの上に置く前提です。暗い背景の上に直接ラベルを置いている別の画面は、`color = Theme.palette.washi` を指定する必要があります。
- ボタンの色は `Lip` と `Face` の色で決まります。`button.BackgroundColor3` を変えても見た目は変わりません。色を変えるときは `Theme.setButtonStyle(button, "primary"|"wood"|"washi"|"ramune"|"danger")` を使ってください。
- `CoinLabel` の表示は `🪙 1250` から `1,250` に変わりました(アイコンは絵で描いています)。値段(`Price`)も数字だけです。テストは `1,250` の形式も受け付けます。
- `Background` は不透明になりました(元は 25% 透過で、奥のワールドが見えていました)。

## 4. 変更したファイル

- `src/shared/UITheme.luau` — 全面的に書き直しました(パレット、フォント、押しボタン、グラデーション、reduced motion 対応の tween、`setButtonStyle`)。
- `src/shared/FestivalArt.luau` — **新規**。提灯、金魚、りんご飴、ラムネ、五円玉、的、うちわ、金魚袋、太鼓、風鈴、ポイ、屋号紋、暖簾、ラムネスイッチを Frame の組み合わせだけで描いています。画像アセットは使っていないので、アップロードや審査は要りません。飾りのパーツはすべて `Active = false` なので、クリックを横取りしません。
- `src/client/MainMenu.luau` — 画面の組み立てを全面的に書き直しました。
- `README.md` — ファイル一覧に2行追加しました。
- 変更なし: `src/client/MenuEntry.client.luau`、`default.project.json`、`tests/*`。

## 5. 確認したこと

1. **契約テスト**: `lune run tests/test_main_menu.luau` → **29 checks, 0 failed**(変更前も 29/29)。
2. **追加の動作チェック** `preview/extra_checks.luau`(出力フォルダで `lune run preview/extra_checks.luau obby-rush`)→ **19/19 PASS**。
   確認した内容: 提灯が揺れる・金魚が泳ぐ / reduced motion で止まる / 画面を閉じると Heartbeat の接続が切れる / ページの開閉に合わせて暗幕と木札の色が変わる /
   `Text` の書き換えが表示に反映される / `setCoins` の桁区切り / 元の親子パスが残っている / 初期値 OFF のトグル表示とビー玉の移動 / 押すと面が沈む / 14px 未満の固定サイズ文字がない。
3. **見た目のプレビュー**: `preview/dump_menu.luau` は、テストと同じ mock に実際の `MainMenu.build` を組み立て、インスタンスツリーを JSON に書き出します。
   `preview/render.html` はそれを近似的に描画する自作のレンダラーで、UDim2/Anchor/SizeConstraint/UISizeConstraint/UIAspectRatioConstraint/UIListLayout/UIPadding/UIScale/Rotation/UICorner/UIStroke/UIGradient/ZIndex に対応しています。
   headless Chrome で撮った PNG が `preview_*.png` です(`python preview/make_previews.py [--gif] [--before <元プロジェクトのコピー>]`)。
   これで描いているのは**このコードが実際に作ったツリー**で、別に作ったモックアップではありません。
4. **コントラスト**(WCAG): 木札の文字 9.0:1、商品名・トグル・閉じる 16.1:1、値段 7.6:1、空のページのメッセージ 6.8:1、PLAY・購入・選択中の木札 4.0:1(暗い縁取りあり、34px/20px の太字)、
   暖簾の見出し 3.4〜5.2:1(26px 太字、縁取りあり)。元の PLAY は 2.23:1 でした。
5. **プレビューで見つけて直した不具合**:
   - Luau の `math.atan(y, x)` は2つ目の引数を無視します。そのため、左へ泳ぐ金魚が逆を向いていました。`math.atan2` に変更しました(Lune で確認)。
   - 太鼓のアイコンのバチが面の上で交差していて、「ミュート(禁止)」の記号に見えました。バチを太鼓の後ろに回しました。
   - ラムネの半透明パーツが重なった部分に継ぎ目が出て、瓶が雪だるまのように見えていました。パーツを不透明にしました。
   - 横向きスマホで水槽と木札が重なっていたので、空きスペースの中央に置く方式にしました。

## 6. 確認できていないこと(Studio 未使用)

**この作業では Roblox Studio を使えませんでした(別のジョブが使用中)。Studio MCP のツールは一度も呼んでいません。** そのため、以下は実機で未確認です。

- 実際のエンジンでの描画。プレビューは Web ブラウザでの近似です。特に次の点は実機で見る必要があります:
  - フォント: `rbxasset://fonts/families/FredokaOne.json` と `LuckiestGuy.json` を `Font.new` で指定しています。日本語は Roblox の CJK 代替フォントで表示されますが、そのとき Bold/Medium の太さが効くかどうか。プレビューでは Noto Sans JP で代用しています。
  - UIStroke が外側に描かれるか。`ClipsDescendants` を付けた枠の中で、縄(円の UIStroke)が切り取られて弧に見えるか。UICorner の Scale が短い辺を基準にするか。TextScaled で文字がどの大きさになるか。
  - 回転している親(提灯のハンガー)の子要素も一緒に回るか。1px の骨の線が見えるか。
- 実際の端末での入力(タッチで押したときの沈み込み、ゲームパッドで選択したときの金枠)、`GetGuiInset()` が実際に返す値、低性能なスマホでの負荷(毎フレーム約 100 個のプロパティを書き換えます)。
- 縦向きのスマホ、4K などの極端な画面サイズ、自動翻訳(ローカライズ)の後の文字の長さ。
- このメニュー以外で `UITheme` を使っている画面への影響(このプロジェクトにはメニュー以外の画面がありませんでした)。

## 7. プレビューファイル一覧(出力フォルダ直下)

`preview_main.png`(1280×720)、`preview_main_t3.png`(アニメ 3.1 秒後)、`preview_main_hover_play.png`(PLAY をホバーして押した状態)、
`preview_shop.png`、`preview_settings_music_off.png`(音楽を OFF にした後)、`preview_inventory.png`、`preview_quests.png`、
`preview_phone_main.png` / `preview_phone_shop.png`(844×390)、`preview_tablet_main.png`(1024×768)、
`preview_before_main.png` / `preview_before_shop.png`(変更前)、`preview_contact_sheet.png`、`preview_idle_motion.gif`。
左上の半透明の丸い四角は、Roblox 本体のトップバーボタンの位置を示すためにプレビューにだけ描いた目印です。ゲームの UI には含まれません。
