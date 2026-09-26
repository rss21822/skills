# Obby Rush メインメニュー: 深海探検スキン「Abyss」

対象: `obby-rush/`(オリジナルのコピー。オリジナルは読んでコピーしただけで、編集していない)
比較: `preview_before_after.png`(左 = 元の紺色テーマ、右 = 今回のスキン)

## 1. コンセプト

**深海では、光は生き物からしか来ない。** 画面は暗いままにして、光るものにそれぞれ役割を持たせた。

| モチーフ | UI での役割 | 実装 |
|---|---|---|
| チョウチンアンコウの誘引突起(エスカ) | **メインの操作**: PLAY、購入 | 温かい琥珀色の球(`shape = "orb"`)と、同じ色のピル型ボタン。PLAY の周りに光の輪が脈打ち、光る竿が暗闇の中の頭部へ弧を描いてつながる。頭部には縁だけに光が当たり、緑に光る目(ときどき瞬きする)と三角の牙が見える |
| 光るクラゲ | **ナビ**と、ナビで開く**ページ** | ナビの 4 ボタンはドーム型の傘と、光の点でできた触手を持つクラゲ(ショップ = 琥珀、持ち物 = ピンク、クエスト = グリーン、設定 = バイオレット)。開いたページは同じ色をまとい、傘の縁(lappets)と、縁を追いかけるように光る点(クシクラゲ風)を持つ膜状のパネルになる。選択中のクラゲは点灯する |
| 泡 | **サブの操作**: 閉じる、トグル。コイン表示 | 暗いガラスのピルに、上だけ光る縁とハイライト。トグルは発光器のランプ(ON = 緑に点灯、OFF = 消灯) |
| マリンスノー・差し込む光・遠くのクラゲ | 背景の奥行き | 石油色の水の層から黒へのグラデーション、上から消えていく光の筋、落ちてくる雪、上がっていく泡、ゆっくり漂う薄いクラゲ 2 体 |

### 「よくある紺色ダッシュボード」にしないためにやったこと

| 元の画面(紺色ダッシュボード) | 今回 |
|---|---|
| 背景 `#0B1426` と パネル `#13233F` の紺の平面 | 色相 175〜190° の石油色から黒へ落ちていく**水の層**(`#0F2E2F → #061214 → #030708`)。紺色の平面は 1 枚も使っていない |
| アクセントは企業っぽいシアン `#3FA9F5` 1 色 | 光の色は**生き物ごと**に決めた: ルアーの琥珀 `#FFB547`、クラゲのピンク `#FF6FD8`・グリーン `#5CFFC6`・バイオレット `#A98BFF`。アクセントの青は使わない |
| 角丸 8〜10px の長方形と 1px の青い枠 | 円・ドーム・ピル・光る点の触手・縁の垂れ(lappets)。枠線は上だけが光って下で闇に溶ける「リムライト」 |
| 光る表現なし | 半透明の円を重ねたにじみ光(`Theme.glow`)、ガラスのハイライト、脈打つ・揺れる・漂う動き |
| Gotham 1 書体 | 見出しと数字は Fredoka One(丸くて泡っぽい)、本文は Nunito SemiBold/ExtraBold |
| 同じ形のカードの格子 | PLAY を画面の主役(アンコウの舞台)にし、ナビは生き物の列にした |

## 2. パレット(`Theme.palette`、既存のキーは `Theme.colors` にも残した)

| 名前 | 値 | 役割 |
|---|---|---|
| abyss / deep / haze | `#030708` / `#061214` / `#0F2E2F` | 水の層(下 → 上)。わずかに緑を含んだ黒で、紺ではない |
| ink / membrane | `#081416` / `#0F2426` | ページの膜 / 泡ボタンの本体 |
| lure / lureCore / lureDeep | `#FFB547` / `#FFF6CD` / `#FF7A1A` | メインの操作、コイン、タイトル |
| jellyPink / jellyViolet / bioGreen / bioCyan | `#FF6FD8` / `#A98BFF` / `#5CFFC6` / `#78E8FF` | ナビとページの色、発光器、泡の縁 |
| foam / mist / inkText / coral | `#EAFBF6` / `#86A9A3` / `#2B1500` / `#FF5C70` | 本文 / 補足 / ルアーの上に載る文字 / 危険操作 |

互換のために残したキー: `background, panel, panelLight, accent, text, subtext, danger, success`(値は深海パレットに置き換えた)。`Theme.font` / `Theme.fontBold`(Enum)も残してある。

## 3. モーション

- 飾りのインスタンスには `Motion` 属性(`sway / bob / drift / pulse / breathe / rise / fall / blink`)と、`Amp / Speed / Phase / Range` を付けた。動かすのは `DeepSea.animate(gui)` の **RenderStepped 1 本だけ**。
- `UDim` のオフセットは整数なので、1 桁ピクセルの小さな揺れは**Scale 側(小数)**で動かし、親のピクセルサイズで割っている。こうしないと 3px の上下動が段々になる(プレビューで値を見て見つけ、直した)。
- 閉じているページの中の飾りは計算しない。ScreenGui が Enabled=false のときも止まる。`Destroying` で接続を切る。
- **Reduced Motion**(`GuiService.ReducedMotionEnabled`)が ON のときは、ループを一切張らない静止画になる。ボタンの押下・ページのポップインも即時の値変更に切り替わる。

## 4. レイアウト(画面の高さに合わせる)

`layoutFor(viewport)`(MainMenu.luau)で縦方向を決めている:
- ページは必ず「トップバーの下 〜 ナビのクラゲの上」に収める(元の `0.16〜0.78` 固定だと、低い画面でナビに重なったため)。
- 高さ 560px 未満(横向きのスマホ)では、クラゲを下に寄せて触手を短くする。PLAY は 112〜168px の間で縮む。
- アンコウの頭・目・牙は、ナビの上に余裕があるときだけ描く。余裕がなければルアーと竿だけ(「本体は闇の中」)。「深海へダイブ」の文言も、ナビにぶつかるときは出さない。
- 設定の項目は、ショップと同じくスクロールするリストに入れた(低い画面で 2 つ目のトグルがはみ出していたため)。

## 5. 契約(他のスクリプトから見える部分)

- テストで固定されている名前はすべてそのまま: `MainMenu`, `PlayButton`, `CoinLabel`, `Nav_*`, `*Page`, `Product_*`, `BuyButton`, `Toggle_Music/SFX`, `CloseButton`。コールバックとページ切り替えの動作も変えていない。ボタンはすべて 48×48px 以上。
- 親子関係で変わった点が 1 つある: **`Toggle_Music` / `Toggle_SFX` は `SettingsPage.SettingsList` の下になった**(スクロール対応のため)。README とテストの通り名前で(再帰的に)探していれば影響はない。`SettingsPage.Toggle_Music` のような直接パスで参照しているコードがあれば、直す必要がある。
- `Nav_*` ボタンの `.Text` は元のラベルのまま(文字は子のラベル `Caption` に描き、`.Text` と同期させている)。`CoinLabel` は `TopBar` の直下、`PlayButton` は `Background` の直下のまま。
- `Theme.panel / label / button / stroke / corner / create` の引数の形は元のまま使える。追加分はすべて省略可能な options(`hue`, `variant`, `shape`, `lamp`, `display`, `glow` など)。

## 6. 変更したファイル

- `obby-rush/src/shared/UITheme.luau` — 全面的に書き換え(パレット、フォント、glow / bubble / jelly / jellyButton / 膜のパネル / ルアー・泡ボタン / setLit / setSelected / popIn / tween / formatNumber)。RunService は触らない。
- `obby-rush/src/client/DeepSea.luau` — 新規(背景、アンコウ、アニメーションの駆動部)
- `obby-rush/src/client/MainMenu.luau` — 新しいスキンでの組み立てと、高さに応じたレイアウト
- `obby-rush/README.md` — モジュールの一覧を更新
- `tests/test_main_menu.luau` と `tests/mock.luau` は変更していない(オリジナルとの diff で確認済み)

## 7. 検証したこと

1. **契約テスト**: `lune run tests/test_main_menu.luau` → `PASS main menu contract: 29 checks, 0 failed`(変更のたびに実行し、最後にも実行)。
2. **実際に組み上がったツリーをレンダリング**(`preview_tools/`): `dump_tree.luau` がテストと同じモックに src/ をマウントし、本物の `MainMenu.build` を実行し、ナビをクリックし、RenderStepped を進めてから、インスタンスツリーを JSON に書き出す。`render_preview.py` がそれを HTML に変換し(UDim2、AnchorPoint、Rotation、Sibling ZIndex、Clips、UIListLayout、UICorner、UIStroke と勾配、UIGradient、UIScale に対応)、Chrome ヘッドレスで撮影する。つまりプレビューは手描きのモックではなく、コードが実際に作ったものを描いている。最終コードで撮り直した画像は、保存済みの `preview_home.png` とピクセル単位で一致した。
   - `preview_home / shop / settings(音楽を OFF にした状態)/ inventory / quests / hover` … 1280×720
   - `preview_phone / phone_shop` … 844×390(横向きスマホ)、`preview_fullhd` … 1920×1080
   - `preview_before_home / before_shop` … 元のプロジェクトを同じ仕組みで描いたもの。`preview_before_after.png` が左右比較
   - `preview_motion.gif` … 駆動部を 0.125 秒ずつ進めた 24 コマ(クラゲの上下、触手の揺れ、泡、光の輪の呼吸)
3. **文字のはみ出し**: ブラウザでテキストの範囲を測った。最終版はどのビューポート・どの状態でも 0 件。途中では、タイトルの枠が低すぎる問題を見つけて直した。
4. **コントラスト**(WCAG、重なっている色を合成して計算): ページタイトル 8.7、商品名 15.8、価格 15.5、補足文 7.4、トグル OFF 6.5 / ON 15.5、ルアーの上の文字 9.9(中央)/ 7.0(下端)、PLAY の文言 7.8、コイン 14.5。ナビの文字は、最初は選択時に 2.2〜3.0 しかなかった。そこで「選択中 = 傘が点灯して文字は暗い色」「通常 = 傘を暗めにして文字は明るい色」に変え、**通常 5.4〜8.5、選択中 4.8〜9.6** になった。
5. **モーションの値**: 目の瞬き(t = 3.97 で 14×2 に閉じ、前後では 14×14)、光の輪の呼吸(507 → 514 → 521px)、クラゲの上下(2.02 → 2.47 → 2.89px、小数で滑らかに動く)をダンプした値で確認した。

## 8. 検証できなかったこと(正直に)

- **Roblox Studio では一度も確認していない。** Studio は別のジョブが使っていたため、Studio MCP は呼んでいない。したがって、Roblox の実際の描画・入力・実行時の動作は未確認で、上の見た目はすべて近似のレンダラーによるもの。特に次の点は Studio で見る必要がある:
  - **フォント**: プレビューは Segoe UI / Yu Gothic で代用している。実機では Fredoka One / Nunito になり、日本語は Roblox の CJK 代替フォントになるので、字幅と太さは変わる。
  - **UIStroke に UIGradient を付けたリムライトの見え方**、**UIGradient による文字の色かぶり**(ルアーの上の文字は暗いインク色なので、どの色がかぶっても読める前提で作った)。
  - **牙**は「45° 回転させた正方形を、回転していないクリップ枠で半分に切る」作り。回転した子要素が ClipsDescendants で正しく切られることは、実機で確認していない。
  - ZIndex が同じ兄弟の重なり順(大事な部分は明示的に ZIndex を付けた)と、Scrim(`Active = true` の Frame)が後ろの PLAY への入力を本当に止めるか。
  - 性能: `Motion` の付いた飾りは全部で 366 個。ホーム画面では 252 個、ページを 1 つ開くとさらに数十個を毎フレーム更新する(閉じているページの 114 個は計算しない)。軽いはずだが、プロファイルは取っていない。
  - `GuiService.ReducedMotionEnabled` は pcall で守ってある。実際の端末で設定を切り替えたときの挙動は未確認。
  - タッチ端末での実機操作。
- **ビューポートの変化への追従**: レイアウトは組み立て時の画面サイズで 1 回だけ決める(元の実装と同じ)。ウィンドウのサイズ変更や端末の回転では組み直さない。
- **1920×1080 では全体が小さく見える**: サイズは元と同じピクセル固定で、UIScale は入れていない。大きな画面での拡大は今回の範囲外にした。
- コントラストの値は、重なりを合成した**推定値**。実機の画面から測ったものではない。

## 9. プレビューの作り直し方

```
cd obby-rush
lune run ../preview_tools/dump_tree.luau shop 1280 720 2.4 ../preview_tools/tree_shop.json
python ../preview_tools/render_preview.py ../preview_tools/tree_shop.json ../preview_shop.png
```

シナリオ: `home | shop | settings | inventory | quests | hover`。引数は幅、高さ、アニメーションを進める秒数の順。
