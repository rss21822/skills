# Luau の実装技法

`assets/MotifSkinKit.luau` にある部品（縁取り・下縁・艶・縞・ドット・パネル・バッジ・絵文字アイコン・ボタン・マスコット・選択枠・見出しの縮小）はそちらを使う。ここは Kit に入っていない「主役画面用」の技法と落とし穴。1〜10 はステッカー系（可愛い・元気）、11 は全トーン共通、12〜16 はそれ以外の素材（高級・ドット・墨・廃墟・ブラウン管）の技法。モチーフに合うものだけ選ぶ。

## 目次
1. ステッカー文字
2. CTA の後光とゆらぎ
3. ステッカーの影
4. 見出しリボンとページバッジ
5. モードカードの箱絵（ViewportFrame）
6. 縞の「近日公開」札とタグのピル
7. 遷移・ロード画面
8. 発光（ネオン）
9. ワールドの看板（BillboardGui / SurfaceGui）
10. モーダルの暗幕
11. トップバーの安全域
12. 二重線の枠
13. ドット枠と ▶ カーソル
14. 筆の帯と朱の印
15. 欠け・染み・テープ
16. 走査線・明滅
17. 落とし穴

## 1. ステッカー文字

太い書体＋白文字＋インクの Contextual ストローク（丸い角）＋少し傾ける。

```lua
local title = Instance.new("TextLabel")
title.Text, title.TextSize, title.TextColor3 = "CLASSIC", 44, P.white
kit:setFont(title, "display")          -- 英字なら飾り書体、日本語なら title に自動切替
kit:outline(title, 4)                  -- MotifTextOutline (Contextual, Round)
title.Rotation = -3
title.BackgroundTransparency = 1
```

`TextStrokeTransparency`（古い文字の縁）は角が尖り細いので使わない。UIStroke の Contextual を使う。

## 2. CTA の後光とゆらぎ

後光はモチーフに光源（照明、発光、太陽、宝石のきらめき）があるときの技法。どの画面の CTA にも付けると、それ自体がハウススタイルになる。

CTA の背面に一回り大きいピル（主役色を紙へ寄せた色）を置き、その UIStroke の太さと透明度を呼吸させる。CTA 本体はときどき小さく揺らす（常時ではなく数秒おき、ホバー中と reduced motion では止める）。

```lua
local halo = Instance.new("Frame")
halo.Name, halo.AnchorPoint, halo.Size = "PlayHalo", Vector2.new(0.5, 0.5), UDim2.fromOffset(290, 98)
halo.Position, halo.BackgroundColor3 = play.Position, P.primary:Lerp(P.paper, 0.6)
halo.ZIndex = play.ZIndex - 1
Instance.new("UICorner", halo).CornerRadius = UDim.new(1, 0)
local ring = Instance.new("UIStroke"); ring.Color, ring.Thickness, ring.Transparency = P.primary, 3, 0.5; ring.Parent = halo
halo.Parent = play.Parent
kit:loop(ring, {Thickness = 7, Transparency = 0.05}, 1.8)
-- 画面が隠れたら止める: dock:GetPropertyChangedSignal("Visible") で tween を Cancel / 再開
```

## 3. ステッカーの影

ぼかし影の代わりに、同じ形の板をインク色・透明度 0.7 で真下へ 4〜6 px ずらして背面に置く。紙が机から浮いて見える。

```lua
local shadow = frame:Clone()
shadow:ClearAllChildren()
local corner = frame:FindFirstChildOfClass("UICorner")
if corner then corner:Clone().Parent = shadow end
shadow.Name, shadow.BackgroundColor3, shadow.BackgroundTransparency = "MotifShadow", P.outline, 0.7
shadow.Position = frame.Position + UDim2.fromOffset(0, 6)
shadow.ZIndex = frame.ZIndex - 1
shadow.Parent = frame.Parent
```

レイアウト（UIListLayout）の中の要素には使えない（影も並んでしまう）。その場合は要素の子に「下へはみ出す」板を置き、`ZIndex` を下げ、要素の `ClipsDescendants` を切る。

## 4. 見出しリボンとページバッジ

モーダル上端に高さ 60 px 前後の色帯（ページごとに色を変える）、下に 4 px のインクの罫線、左に傾いた丸バッジ（絵文字）、見出しは白文字＋縁取り。帯の下角は四角く（上だけ丸い）するため、帯の下半分に同色の四角い Frame を重ねる。

```lua
local ribbon = Instance.new("Frame"); ribbon.Name = "MotifRibbon"
ribbon.Size, ribbon.BackgroundColor3, ribbon.BorderSizePixel = UDim2.new(1, 0, 0, 62), pageColor, 0
Instance.new("UICorner", ribbon).CornerRadius = UDim.new(0, 24)
local square = Instance.new("Frame"); square.Size, square.Position = UDim2.new(1, 0, 0.5, 0), UDim2.fromScale(0, 0.5)
square.BackgroundColor3, square.BorderSizePixel, square.Parent = pageColor, 0, ribbon
local rule = Instance.new("Frame"); rule.Size, rule.Position = UDim2.new(1, 0, 0, 4), UDim2.fromScale(0, 1)
rule.BackgroundColor3, rule.BorderSizePixel, rule.Parent = P.outline, 0, ribbon
kit:dots(ribbon, {columns = 12, rows = 2, size = 9, transparency = 0.7})
local badge = kit:badge(modal, "PageBadge", "🛍️", P.primary, 52, {Position = UDim2.fromOffset(14, 5), Rotation = -8})
kit:fitHeading(heading, 34, 14)
```

ページが変わるたびに帯の色・バッジの絵文字を差し替える（画面が `Page` のような属性を持つなら `GetAttributeChangedSignal` で追う）。

## 5. モードカードの箱絵（ViewportFrame）

画像アセット無しで「そのモードらしい情景」を描ける。Part を数個並べ、カメラを斜め上から向ける。

```lua
local vp = Instance.new("ViewportFrame")
vp.Name, vp.Size, vp.BackgroundColor3, vp.BorderSizePixel = "ArenaArtwork", UDim2.fromScale(1, 0.66), P.paper, 0 -- BorderSizePixel 0 を忘れると 1px の線が出る
vp.Ambient, vp.LightColor, vp.LightDirection = Color3.fromRGB(200, 200, 220), P.white, Vector3.new(-1, -2, -1)
local world = Instance.new("WorldModel"); world.Parent = vp
local function part(size, cf, color, shape)
	local p = Instance.new("Part"); p.Anchored, p.Size, p.CFrame, p.Color = true, size, cf, color
	p.Material = Enum.Material.SmoothPlastic
	if shape then p.Shape = shape end
	p.Parent = world
	return p
end
part(Vector3.new(24, 1, 16), CFrame.new(0, -0.5, 0), P.paper)                       -- 床
part(Vector3.new(0.06, 8, 8), CFrame.new(0, 0.03, 0) * CFrame.Angles(0, 0, math.rad(90)), kit.candies.sky, Enum.PartType.Cylinder) -- 床の円（薄い円柱は X 軸が厚み）
-- 壁、キャラ（胴の直方体＋頭の球）、モードの特徴物 ...
local cam = Instance.new("Camera"); cam.FieldOfView = 40
cam.CFrame = CFrame.lookAt(Vector3.new(10, 9, 14), Vector3.new(0, 0, 0)); cam.Parent = vp
vp.CurrentCamera = cam
vp.Parent = card
```

- 絵の下端を面の色へ溶かす「フェード」の Frame（UIGradient の Transparency で上 0→下 1 を反転）を重ねるとカードの下 1/3 と繋がる。
- ホバーで絵を 1.07 倍にするなら、フェードの Frame も同じ倍率で動かす（絵だけ拡大すると、フェードの外にはみ出した絵の端が色なしで見える）。
- 薄い円柱は `Size = Vector3.new(厚み, 直径, 直径)` を Z 軸回りに 90° 回す。`(8, .05, 8)` は棒になる。

## 6. 縞の「近日公開」札とタグのピル

- 未実装のカードは TextButton にしない（Frame にして `Active = false`）。押せそうに見えて何も起きないのが一番がっかりする。縞（`kit:stripes`）＋大きな「?」＋ステッカー文字で「楽しみ」に見せる。
- カード下部の一言タグは紙のピル＋インクの縁。幅に合わせて文字を縮め（`TextSize = clamp(幅 / 15, 11, 18)`）、幅 150 px 未満では隠す。

## 7. 遷移・ロード画面

構成: 暗幕 → 中央のカード（キャンディ 2 色の斜めグラデーション）→ ゆっくり首を振る光線 → 紙の帯（−3° 傾き、上下にインクの罫線）→ 帯の上にキッカーのピル（「マッチング！」）、見出し、進捗バー、状態文。

```lua
-- 光線: 画面より大きい Frame を UIGradient の Transparency で縞にし、Offset をゆっくり往復させる
local rays = Instance.new("Frame"); rays.Name = "Rays"; rays.AnchorPoint = Vector2.new(0.5, 0.5)
rays.Position, rays.Size, rays.BackgroundColor3 = UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1.8, 1.8), P.white
local g = Instance.new("UIGradient"); g.Rotation = 20
local points = {}
for i = 0, 9 do
	table.insert(points, NumberSequenceKeypoint.new(i / 10, i % 2 == 0 and 0.82 or 1))
	table.insert(points, NumberSequenceKeypoint.new(i == 9 and 1 or (i + 1) / 10 - 0.001, i % 2 == 0 and 0.82 or 1)) -- 最後は必ず 1
end
g.Transparency = NumberSequence.new(points); g.Parent = rays
kit:loop(g, {Offset = Vector2.new(0.08, 0)}, 3.2)
```

- 進捗バーの上をマスコットが歩く: マスコットの `Position.X.Scale = 0.19 + 0.62 * fill` を、Fill の Size の変化に追従させる。
- 文字要素が重ならない配置を先に決める（見出し・区切り・バー・キャラ・状態文を縦に割り付けてから装飾を足す）。キャラは状態文や見出しに重ねない。
- テストが要素名（Title、Status、Fill など）を見ていれば、その名前と親子関係を維持する。

## 8. 発光（ネオン）

UIStroke を 2 重にする: 外側に太く半透明（Thickness 8、Transparency 0.7、発光色）、内側に細く不透明（Thickness 2、明るい色）。外側は `Border` の UIStroke を持つ一回り大きい透明な Frame で作る（1 つの Instance に UIStroke は 1 本しか効かない）。明滅は Transparency を 0.55↔0.75 でゆっくり（2 s 以上）。速い点滅・フラッシュは光過敏への配慮で使わない。

## 9. ワールドの看板（BillboardGui / SurfaceGui）

サーバー側で作る看板も同じ配色にする（クライアントのスキンはサーバーのインスタンスには掛からない）。紙の Frame（縁 4 px）＋上部に色のリボン（下角は四角）＋絵文字バッジ＋白文字の見出し＋インクの本文。`MaxDistance` を設定し、`AlwaysOnTop` は必要な札だけ。サーバー用の配色はクライアントの spec と同じ値を定数で持つ（生成した MotifSpec を ReplicatedStorage に置けば共用できる）。

## 10. モーダルの暗幕

黒の 50% ではなく、`dim` 色に上下の UIGradient（上 0.35、下 0.15 の透明度）。暗幕越しの世界がモチーフの色に染まり、画面が「その世界の中」に見える。

## 11. トップバーの安全域

`IgnoreGuiInset = true`（背景を全面に敷くため）の ScreenGui では、座標 0 が画面の最上端になり、Roblox のメニュー/チャットのボタン列（左上）の下に見出しが潜る。`GuiService.TopbarInset`（Rect）がトップバーのうち開発者が使える範囲を返す: `Max.Y` がトップバーの高さ（現行 58 px）、`Min.X` が左のボタン列の右端。

```lua
-- Kit にある: 名前と階層は変えずに、上端の要素だけトップバーの下へ（背景は全面のまま）
kit:clearTopbar(gui.Header)        -- Position.Y に TopbarInset.Max.Y + 8 を足す。変化にも追従
local bar = kit:topbar()           -- {left = TopbarInset.Min.X, height = TopbarInset.Max.Y}（取れなければ 200 / 58）
```

- 見出しやコイン表示を左上に置くなら `x >= inset.Min.X` か `y >= inset.Max.Y`。右上も Roblox のボタン（リーダーボード等）が出うる。
- 新しく作る画面なら、背景だけ `ScreenInsets = None` の ScreenGui に敷き、中身は既定（`CoreUISafeInsets`）の ScreenGui に置くのが一番簡単。
- トップバーの無い環境では `TopbarInset.Max.Y` は 0。GuiService から取れないとき（Lune のモックなど）Kit は 58 px で代用する。

## 12. 二重線の枠（高級・証書・古い RPG のウィンドウ）

外枠の UIStroke と、4〜6 px 内側の透明な Frame の UIStroke で 2 本にする。四隅に小さな ◆（45° 回転した正方形）を置くと額縁や証書になる。

```lua
local function doubleRule(frame, color, gap)
	local outer = Instance.new("UIStroke")
	outer.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	outer.Color, outer.Thickness = color, 1
	outer.Parent = frame
	local inner = Instance.new("Frame")
	inner.Name = "InnerRule"
	inner.BackgroundTransparency = 1
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(0.5, 0.5)
	inner.Size = UDim2.new(1, -gap * 2, 1, -gap * 2)
	inner.Active = false
	outer:Clone().Parent = inner
	inner.Parent = frame
	return inner
end
```

金属の艶は面のグラデーションではなく、上辺だけ明るい 1 px の線（高さ 1 の Frame）で出す。

## 13. ドット枠（ゲーム機のウィンドウ）と ▶ カーソル

角を 1 マス欠いた枠は、4 本の辺を Frame で描く（UICorner は使わない）。外側に明るい線、内側に暗い線を重ねると当時のウィンドウになる。

```lua
local function pixelFrame(frame, color, px)
	local edges = {
		{UDim2.new(0, px, 0, 0), UDim2.new(1, -2 * px, 0, px)},   -- 上
		{UDim2.new(0, px, 1, -px), UDim2.new(1, -2 * px, 0, px)}, -- 下
		{UDim2.new(0, 0, 0, px), UDim2.new(0, px, 1, -2 * px)},   -- 左
		{UDim2.new(1, -px, 0, px), UDim2.new(0, px, 1, -2 * px)}, -- 右
	}
	for _, e in ipairs(edges) do
		local edge = Instance.new("Frame")
		edge.Name = "PixelEdge"
		edge.BorderSizePixel = 0
		edge.BackgroundColor3 = color
		edge.Position, edge.Size = e[1], e[2]
		edge.Active = false
		edge.Parent = frame
	end
end
```

選択中の項目の左に `▶` の TextLabel を置き、選択が変わったら位置を移す。何も操作していない最初の状態でも、既定の項目（START など）に ▶ を置いておく（当時のメニューは常にどこかを指している）。点滅は 1 Hz（0.5 s ごとに表示/非表示）で、reduced motion では点けたまま。動きは Tween ではなく段階的に（位置は即座に移す、`EasingStyle.Constant`）。影・グラデーション・角丸は使わない。

## 14. 筆の帯と朱の印（墨・書道・手描き）

筆の帯は、角の丸い細長い Frame を少しずつ傾け・ずらし・濃さを変えて 4〜5 枚重ね、UIGradient の透明度で入りと抜けを作る。見出しの背後や区切り線に使う。

```lua
local function brushBand(parent, color, seed)
	local rng = Random.new(seed)
	local band = Instance.new("Frame")
	band.Name = "BrushBand"
	band.BackgroundTransparency = 1
	band.Size = UDim2.fromScale(1, 1)
	band.Active = false
	for i = 1, 5 do
		local s = Instance.new("Frame")
		s.BorderSizePixel = 0
		s.BackgroundColor3 = color
		s.BackgroundTransparency = 0.1 + i * 0.12
		s.AnchorPoint = Vector2.new(0, 0.5)
		s.Position = UDim2.new(0, rng:NextInteger(-6, 6), 0.5, rng:NextInteger(-4, 4))
		s.Size = UDim2.new(rng:NextNumber(0.85, 1.05), 0, 0.5 + rng:NextNumber(-0.15, 0.2), 0)
		s.Rotation = rng:NextNumber(-1.5, 1.5)
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = s
		local stroke = Instance.new("UIGradient") -- 入り（濃い）と抜け（かすれ）
		stroke.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(0.06, 0),
			NumberSequenceKeypoint.new(0.8, 0.1), NumberSequenceKeypoint.new(1, 1),
		})
		stroke.Parent = s
		s.Parent = band
	end
	band.Parent = parent
	return band
end
```

**円相や筆の曲線**は、短い Frame を円周に沿って回転させながら並べ、太さを入り（太い）から抜け（細い）へ変え、最後を数本の細い線に割ってかすれにする。色は平坦な墨色（透明度だけ変える）。曲面に明暗のグラデーションを掛けると、筆ではなく金属やプラスチックの輪に見える。

朱の印（落款）は、朱の正方形に白抜きの漢字 1〜2 字（Bold 以上）、角はごく小さく（2 px）、画面に 1 つだけ。CTA や決定の印に使うと「押す」行為と意味が重なる。にじみは紙色より少し濃い半透明の大きな円を 2〜3 個。

## 15. 欠け・染み・テープ（廃墟・古い紙・手作り）

- **欠けた縁**: UIStroke の代わりに、辺ごとに長さの違う短い Frame を隙間を空けて並べる。
- **染み**: 紙色を暗くした半透明（0.6〜0.8）の円を大きさを変えて 2〜4 個重ねる。文字の下には置かない。
- **テープ・クリップ**: パネルの上角に、半透明の細長い矩形を ±30° で重ねる。紙が「貼られている」ことが素材を伝える。
- **ずれ**: パネルを 0.5〜1.5° だけ傾け、隣と揃えない。

## 16. 走査線・明滅（ブラウン管・蛍光灯・モニタ）

- **走査線**: 高さ 1〜2 px の Frame を 3〜4 px おきに縦に並べ（UIListLayout で可）、透明度 0.85〜0.9 で画面に重ねる。`Active = false`、ZIndex は最前面。
- **明滅**: 照明を表す半透明の板の透明度を、数秒おきに 0.1〜0.2 s だけ暗くして戻す。1 秒に 3 回以上の明滅は光過敏への配慮で使わない。reduced motion では止める。
- **トラッキングのずれ**: 画面全体を 2 px 横にずらして戻す。数秒に 1 回まで。

## 17. 落とし穴

- **UIGradient は文字色も掛け算する**: TextButton に下縁のグラデーションを掛けると文字の色も変わる。文字の掛かる帯は白（掛け算で不変）にする。全面グラデーションなら文字はインク色に。
- **UIStroke のモード**: 文字を持つ Instance の UIStroke は既定で Contextual（文字の縁）。面の縁にしたいときは `ApplyStrokeMode = Border` を明示する。Lune のモックでは既定値が nil なので、コードでは明示しておく。
- **絵文字の大きさ**: TextSize の約 1.5 倍の高さ。22 pt を 32 px の箱に入れると TextFits が false になる。
- **TextScaled と日本語**: 見出しを TextScaled にするときは `TextWrapped = false` と UITextSizeConstraint（最大・最小）を併用する。無制限だと短い語が巨大になる。
- **Rotation とレイアウト**: UIListLayout の子を回転させると隣と重なる。傾けるのは自由配置の要素か、回転ぶんの余白を取った要素だけ。
- **ZIndex**: 装飾（影・後光・ドット）は ZIndex を下げ、`Active = false`（クリックを吸わない）。
- **レイアウトを持つ Frame への装飾**: UIListLayout / UIGridLayout を持つ Frame に装飾の子 Frame（枠の辺、染み、印）を足すと、並びの 1 項目として配置されてしまう。装飾はレイアウトを持たない外側の Frame に付けるか、UIStroke / UIGradient のような GuiObject でない部品で描く。
- **AnchorPoint 0.5 の拡大**: ホバーで UIScale を変えるならアンカー中央の要素だけ（左上アンカーだと右下へ伸びて隣に被る）。
- **フォントのキャッシュ**: `Font.new` は軽いが、同じ役割の Font を 1 回だけ作って使い回す（Kit は役割ごとにキャッシュ）。
- **再描画される画面**: 画面が開くたびに子を作り直す実装では、スキンの部品も毎回作られる。一回きりの装飾（マスコット等）は画面の外側の永続する Frame に置く。
