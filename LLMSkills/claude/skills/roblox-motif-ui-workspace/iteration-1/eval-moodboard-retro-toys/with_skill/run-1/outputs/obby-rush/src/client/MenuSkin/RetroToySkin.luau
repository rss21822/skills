--!nocheck
-- RetroToySkin: the "Retro Toy Box" look for the MainMenu ScreenGui (from moodboard-retro-toys.png).
--
-- Printed cardboard toy box + painted wooden blocks: cream card, cocoa outlines, a mustard-striped
-- lid band, coral "picture frame" pages with cream windows, cocoa label tape, stars / donut rings /
-- confetti, and a tin robot. Colours and fonts come from MotifSpec (generated from
-- design/retro-toy-skin.json by the roblox-motif-ui skin_preview.py; edit the JSON, not MotifSpec).
--
-- Contract: MainMenu.build makes the plain menu first and then calls Skin.apply(gui). Only looks
-- change. Every Name, Parent, callback, Text and Visible rule of the plain menu stays as it was;
-- decorations are new children whose names start with "Motif". If any stage errors, apply errors and
-- MainMenu destroys the half-skinned gui and rebuilds the plain one (the menu always appears).
-- The shared UITheme module is not modified, so other screens keep their current look.
local Kit = require(script.Parent.MotifSkinKit)
local Spec = require(script.Parent.MotifSpec)

local kit = Kit.new(Spec)
local P, C = kit.P, kit.candies
local ICONS = Spec.icons or {}
local create = Kit.create

local Skin = {kit = kit, name = "RetroToyBox"}
local skinned = setmetatable({}, {__mode = "k"})

-- Page -> frame colour, badge emoji and the nav tile that opens it (same colour on tile and frame).
local PAGES = {
	{page = "ShopPage", nav = "Nav_Shop", candy = "tincar", icon = "shop"},
	{page = "InventoryPage", nav = "Nav_Inventory", candy = "ring", icon = "inventory"},
	{page = "QuestsPage", nav = "Nav_Quests", candy = "robot", icon = "quests"},
	{page = "SettingsPage", nav = "Nav_Settings", candy = "gumdrop", icon = "settings"},
}
-- Layers inside Background (ScreenGui uses Sibling z-order).
local Z = {decor = 1, lid = 2, halo = 2, shadow = 3, hero = 4, dim = 5, chrome = 6}
local COIN_EMOJI = "\240\159\170\153" -- U+1FA99 (Unicode 13): Roblox draws it as a tofu box, so it is drawn with frames instead

-- Helpers ------------------------------------------------------------------------------------------
local function need(parent, name)
	local found = parent and parent:FindFirstChild(name)
	if not found then error("RetroToySkin: missing " .. tostring(name), 2) end
	return found
end

local function colour(key)
	return P[key] or C[key] or Kit.color(key)
end

local function round(object, radius)
	local corner = object:FindFirstChildOfClass("UICorner") or create("UICorner", object)
	corner.CornerRadius = radius or UDim.new(1, 0)
	return corner
end

-- The theme adds a 1 px accent UIStroke to panels and buttons. Reuse that instance as the kit's
-- "MotifEdge" instead of stacking a second Border stroke on the same object.
local function adoptEdge(object)
	if object:FindFirstChild("MotifEdge") then return end
	local stroke = object:FindFirstChildOfClass("UIStroke")
	if stroke then stroke.Name = "MotifEdge" end
end

local function edge(object, thickness, color)
	adoptEdge(object)
	local stroke = object:FindFirstChild("MotifEdge") or create("UIStroke", object, {Name = "MotifEdge"})
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Color, stroke.Thickness, stroke.Transparency = color or P.outline, thickness or 3, 0
	return stroke
end

local function stripCoin(text)
	local plain = string.gsub(tostring(text or ""), COIN_EMOJI, "")
	plain = string.gsub(plain, "^%s+", "")
	plain = string.gsub(plain, "%s+$", "")
	return plain
end

-- Flat print: no gloss bar. The theme's own hover handler writes its old navy colour into
-- BackgroundColor3 on MouseEnter/MouseLeave; repaint the designed face whenever that happens.
local function toyButton(button, options)
	adoptEdge(button)
	local state = kit:styleButton(button, options)
	local gloss = button:FindFirstChild("MotifGloss")
	if gloss then gloss:Destroy() end
	local painting = false
	button:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
		if painting then return end
		painting = true
		kit:paint(button, state)
		painting = false
	end)
	return state
end

-- A solid cocoa plate offset down-right behind an object (retro print shadow). Lives as a sibling and
-- follows the object's geometry and visibility.
local function hardShadow(object, dx, dy, transparency, zIndex)
	local plate = create("Frame", object.Parent, {
		Name = "MotifShadow_" .. object.Name, BackgroundColor3 = P.outline, BackgroundTransparency = transparency or 0.2,
		BorderSizePixel = 0, Active = false, ZIndex = zIndex or math.max(0, object.ZIndex - 1),
	})
	local corner = object:FindFirstChildOfClass("UICorner")
	if corner then create("UICorner", plate, {CornerRadius = corner.CornerRadius}) end
	local limit = object:FindFirstChild("MotifSize")
	if limit then create("UISizeConstraint", plate, {Name = "MotifSize", MinSize = limit.MinSize, MaxSize = limit.MaxSize}) end
	local function sync()
		plate.AnchorPoint, plate.Size, plate.Rotation, plate.Visible = object.AnchorPoint, object.Size, object.Rotation, object.Visible
		plate.Position = object.Position + UDim2.fromOffset(dx, dy)
	end
	sync()
	for _, property in ipairs({"Position", "Size", "Rotation", "Visible", "AnchorPoint"}) do
		object:GetPropertyChangedSignal(property):Connect(sync)
	end
	return plate
end

-- A five-point star glyph with a cocoa outline (a text glyph, so it takes any colour and stroke).
local function star(parent, name, position, size, color, rotation, zIndex)
	local label = create("TextLabel", parent, {
		Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = position, Size = UDim2.fromOffset(math.floor(size * 1.3), math.floor(size * 1.3)),
		BackgroundTransparency = 1, Text = "\226\152\133", TextSize = size, TextColor3 = color, Rotation = rotation or 0,
		Active = false, ZIndex = zIndex or parent.ZIndex,
	})
	kit:setFont(label, "title")
	kit:outline(label, math.clamp(size / 18, 2, 5))
	return label
end

-- The teal donut ring from the board: a disc with a paper hole, both edged in cocoa.
local function donut(parent, name, position, size, color, zIndex)
	local thickness = math.clamp(size / 36, 3, 5)
	local ring = create("Frame", parent, {
		Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = position, Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = color, BorderSizePixel = 0, Active = false, ZIndex = zIndex,
	})
	round(ring)
	edge(ring, thickness)
	local hole = create("Frame", ring, {
		Name = "Hole", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.42, 0.42),
		BackgroundColor3 = P.paper, BorderSizePixel = 0, Active = false, ZIndex = zIndex,
	})
	round(hole)
	edge(hole, thickness)
	return ring
end

-- A gold coin drawn with frames (the 🪙 emoji is newer than Roblox's emoji font).
local function coin(parent, name, size, position)
	local disc = create("Frame", parent, {
		Name = name, AnchorPoint = Vector2.new(0, 0.5), Position = position, Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = P.coin, BorderSizePixel = 0, Active = false, ZIndex = parent.ZIndex,
	})
	round(disc)
	edge(disc, math.clamp(size / 12, 2, 3))
	local rim = create("Frame", disc, {
		Name = "Rim", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.56, 0.56),
		BackgroundTransparency = 1, Active = false, ZIndex = parent.ZIndex,
	})
	round(rim)
	create("UIStroke", rim, {Name = "MotifEdge", Color = P.coin:Lerp(P.outline, 0.4), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border})
	return disc
end

-- A text label shown in place of `source`, mirroring its Text without the coin emoji. The source keeps
-- its Text (other scripts may read or write it); only its own glyphs are hidden.
local function mirrorText(source, name, props)
	source.TextTransparency = 1
	local stroke = source:FindFirstChild("MotifTextOutline")
	if stroke then stroke.Transparency = 1 end
	local display = create("TextLabel", source, {
		Name = name, BackgroundTransparency = 1, Text = stripCoin(source.Text), Active = false, ZIndex = source.ZIndex,
	})
	for key, value in pairs(props or {}) do display[key] = value end
	source:GetPropertyChangedSignal("Text"):Connect(function() display.Text = stripCoin(source.Text) end)
	return display
end

local function screenSize(gui)
	local size = gui.AbsoluteSize
	if size and size.X > 0 and size.Y > 0 then return size.X, size.Y end
	local camera = workspace.CurrentCamera
	if camera and camera.ViewportSize then return camera.ViewportSize.X, camera.ViewportSize.Y end
	return 1280, 720
end

local function topInset()
	local ok, topLeft = pcall(function() return game:GetService("GuiService"):GetGuiInset() end)
	if ok and topLeft and topLeft.Y then return math.clamp(topLeft.Y, 0, 80) end
	return 36
end

-- Stages -------------------------------------------------------------------------------------------
-- Each stage gets the shared context. They run in order; an error aborts the whole skin (see top).
local function stageRoot(ctx)
	local gui = ctx.gui
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local bg = need(gui, "Background")
	bg.BackgroundColor3, bg.BackgroundTransparency = P.paper, 0
	ctx.bg = bg

	-- Toy-box scatter: a teal donut, stars and confetti around the edges, never behind the CTA.
	local decor = create("Frame", bg, {Name = "MotifDecor", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Active = false, ZIndex = Z.decor})
	ctx.decor, ctx.decorItems = decor, {}
	table.insert(ctx.decorItems, {kind = "donut", size = 200, object = donut(decor, "MotifDonut", UDim2.fromScale(0.05, 0.5), 200, C.ring, Z.decor)})
	table.insert(ctx.decorItems, {kind = "donut", size = 96, object = donut(decor, "MotifDonutSmall", UDim2.fromScale(0.955, 0.93), 96, C.gumdrop, Z.decor)})
	local STARS = {
		{0.87, 0.42, 132, "stripe", 12}, {0.8, 0.67, 54, "tincar", -10}, {0.19, 0.79, 70, "robot", -14},
		{0.14, 0.25, 42, "gumdrop", 8}, {0.95, 0.24, 40, "tincar", 18},
	}
	for index, s in ipairs(STARS) do
		local label = star(decor, "MotifStar" .. index, UDim2.fromScale(s[1], s[2]), s[3], colour(s[4]), s[5], Z.decor)
		table.insert(ctx.decorItems, {kind = "star", size = s[3], object = label})
	end
	local CONFETTI = {
		{0.04, 0.74, 22, "ring"}, {0.1, 0.81, 14, "tincar"}, {0.15, 0.7, 18, "gumdrop"}, {0.03, 0.9, 16, "stripe"},
		{0.21, 0.9, 12, "ring"}, {0.12, 0.95, 20, "stripe"}, {0.27, 0.64, 12, "tincar"}, {0.31, 0.21, 10, "ring"},
		{0.37, 0.27, 16, "gumdrop"}, {0.45, 0.19, 12, "tincar"}, {0.64, 0.23, 14, "stripe"}, {0.71, 0.3, 12, "ring"},
		{0.76, 0.52, 18, "gumdrop"}, {0.81, 0.82, 22, "tincar"}, {0.9, 0.74, 14, "ring"}, {0.86, 0.93, 12, "gumdrop"},
		{0.74, 0.9, 10, "robot"}, {0.97, 0.6, 12, "tincar"}, {0.08, 0.36, 12, "stripe"}, {0.23, 0.45, 10, "robot"},
		{0.6, 0.86, 12, "robot"}, {0.4, 0.87, 10, "stripe"}, {0.93, 0.5, 16, "ring"}, {0.26, 0.33, 14, "tincar"},
	}
	local confetti = create("Frame", decor, {Name = "MotifConfetti", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Active = false, ZIndex = Z.decor})
	for _, d in ipairs(CONFETTI) do
		local dot = create("Frame", confetti, {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(d[1], d[2]), Size = UDim2.fromOffset(d[3], d[3]),
			BackgroundColor3 = colour(d[4]), BorderSizePixel = 0, Active = false, ZIndex = Z.decor,
		})
		round(dot)
	end

	-- The lid band: mustard diagonal stripes on cream with a thick cocoa rule, as on the board.
	-- A CanvasGroup clips the rotated stripe bars to the band.
	local lid = create("CanvasGroup", bg, {Name = "MotifLid", Size = UDim2.new(1, 0, 0, 90), BackgroundColor3 = P.paper, BorderSizePixel = 0, Active = false, ZIndex = Z.lid})
	local bars = create("Frame", lid, {Name = "MotifStripes", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Active = false})
	for index = 0, 63 do
		create("Frame", bars, {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, -40 + index * 44, 0.5, 0), Size = UDim2.fromOffset(16, 200),
			Rotation = 45, BackgroundColor3 = P.stripe, BorderSizePixel = 0, Active = false,
		})
	end
	create("Frame", lid, {Name = "MotifLidRule", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 7),
		BackgroundColor3 = P.outline, BorderSizePixel = 0, Active = false, ZIndex = 2})
	ctx.lid = lid
end

local function stageTopBar(ctx)
	local top = need(ctx.bg, "TopBar")
	top.BackgroundTransparency, top.ZIndex = 1, Z.chrome
	local stroke = top:FindFirstChildOfClass("UIStroke")
	if stroke then stroke.Enabled = false end
	ctx.top = top

	-- "OBBY RUSH" on cocoa label tape (the board's RETRO TOY BOX label).
	local title = need(top, "Title")
	title.BackgroundTransparency, title.BackgroundColor3, title.BorderSizePixel = 0, P.outline, 0
	title.TextColor3 = P.panel
	title.TextXAlignment, title.TextYAlignment = Enum.TextXAlignment.Center, Enum.TextYAlignment.Center
	title.Rotation, title.ZIndex = -2, 2
	round(title)
	create("UIPadding", title, {Name = "MotifPadding", PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18), PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 3)})
	create("UISizeConstraint", title, {Name = "MotifSize", MaxSize = Vector2.new(300, 52)})
	kit:setFont(title, "display")
	kit:fitHeading(title, 34, 16)
	hardShadow(title, 4, 5, 0.25, 1)
	ctx.title = title

	-- Coin counter: cream pill, frame-drawn coin, count mirrored from CoinLabel.Text.
	local coins = need(top, "CoinLabel")
	coins.BackgroundTransparency, coins.BackgroundColor3, coins.BorderSizePixel = 0, P.panel, 0
	coins.ZIndex = 2
	round(coins)
	edge(coins, 3)
	create("UISizeConstraint", coins, {Name = "MotifSize", MaxSize = Vector2.new(190, 46)})
	coin(coins, "MotifCoin", 30, UDim2.new(0, 9, 0.5, 0))
	local count = mirrorText(coins, "MotifCoinText", {
		Position = UDim2.new(0, 46, 0, 0), Size = UDim2.new(1, -60, 1, 0), TextColor3 = P.ink,
		TextXAlignment = Enum.TextXAlignment.Center, TextSize = 24,
	})
	kit:setFont(count, "strong")
	kit:fitHeading(count, 26, 14)
	hardShadow(coins, 4, 5, 0.25, 1)
	ctx.coins = coins
end

local function stagePlay(ctx)
	local bg = ctx.bg
	local play = need(bg, "PlayButton")
	play.Size, play.TextSize, play.ZIndex = UDim2.fromOffset(300, 88), 40, Z.hero
	play.Rotation = Spec.shape and Spec.shape.tilt or -3
	toyButton(play, {role = "primary", pill = true, height = 88, edge = 4})
	star(play, "MotifPlayStar", UDim2.new(1, -20, 0, 4), 44, C.tincar, 16, play.ZIndex)
	ctx.play = play

	-- Breathing halo (the only CTA loop) and the offset print shadow.
	local halo = create("Frame", bg, {
		Name = "MotifPlayHalo", AnchorPoint = play.AnchorPoint, Position = play.Position, Size = UDim2.fromOffset(344, 124),
		Rotation = play.Rotation, BackgroundColor3 = P.primary:Lerp(P.paper, 0.6), BorderSizePixel = 0, Active = false, ZIndex = Z.halo,
	})
	round(halo)
	local ring = create("UIStroke", halo, {Name = "MotifHaloRing", Color = P.primary, Thickness = 3, Transparency = 0.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border})
	local breathing = kit:loop(ring, {Thickness = 8, Transparency = 0.1}, 1.8)
	if breathing then table.insert(ctx.loops, breathing) end
	hardShadow(play, 5, 8, 0.15, Z.shadow)

	-- The tin robot keeps the CTA company (hidden on narrow screens by stageFit).
	local mascot = Spec.mascot
	if mascot then
		local robot = kit:mascot(bg, 92, mascot.parts, {
			name = "MotifRobot", aspect = mascot.aspect, blink = mascot.blink, sway = 5, swaySeconds = 1.8,
			props = {Position = UDim2.new(0.5, 252, 0.55, 58), ZIndex = Z.hero},
		})
		ctx.robot = robot
	end
end

local function stageNav(ctx)
	local nav = need(ctx.bg, "NavBar")
	nav.Size, nav.Position, nav.ZIndex = UDim2.fromOffset(548, 108), UDim2.new(0.5, 0, 1, -14), Z.chrome
	local layout = nav:FindFirstChildOfClass("UIListLayout")
	if layout then
		layout.Padding = UDim.new(0, 14)
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
	end
	ctx.navScale = create("UIScale", nav, {Name = "MotifFit", Scale = 1})
	ctx.tiles = {}
	for _, entry in ipairs(PAGES) do
		local tile = need(nav, entry.nav)
		tile.Size, tile.TextSize = UDim2.fromOffset(124, 100), 24
		tile.TextYAlignment = Enum.TextYAlignment.Bottom
		create("UIPadding", tile, {Name = "MotifPadding", PaddingBottom = UDim.new(0, 13)})
		toyButton(tile, {role = entry.candy, corner = 22, height = 100})
		create("TextLabel", tile, {
			Name = "MotifTileIcon", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 7),
			Size = UDim2.fromOffset(46, 46), Text = ICONS[entry.icon] or "", TextSize = 30, TextColor3 = P.white, Active = false, ZIndex = tile.ZIndex,
		})
		local mark = star(tile, "MotifTileStar", UDim2.new(1, -8, 0, 6), 30, P.primary, 14, tile.ZIndex)
		mark.Visible = false
		ctx.tiles[entry.page] = {tile = tile, mark = mark}
	end
end

local function stagePages(ctx)
	local gui = ctx.gui
	local dim = create("Frame", ctx.bg, {
		Name = "MotifDim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = P.dim, BackgroundTransparency = 0, BorderSizePixel = 0,
		Visible = false, Active = false, ZIndex = Z.dim,
	})
	create("UIGradient", dim, {Name = "MotifDimFade", Rotation = 90,
		Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.62), NumberSequenceKeypoint.new(1, 0.4)})})
	ctx.pages, ctx.pageShadows = {}, {}

	local function refresh()
		local anyOpen = false
		for _, entry in ipairs(PAGES) do
			local page, tile = ctx.pages[entry.page], ctx.tiles and ctx.tiles[entry.page]
			local open = page ~= nil and page.Visible == true
			anyOpen = anyOpen or open
			if tile then
				tile.tile.Rotation = open and -4 or 0
				tile.mark.Visible = open
			end
		end
		dim.Visible = anyOpen
	end

	for _, entry in ipairs(PAGES) do
		local page = need(gui, entry.page)
		local face = C[entry.candy]
		-- Geometry is set by stageFit: centred between the lid and the dock, or a full-height sheet on short screens.
		page.AnchorPoint = Vector2.new(0.5, 0)
		page.BackgroundTransparency, page.ZIndex = 0, 3
		adoptEdge(page)
		kit:panel(page, {color = face, corner = 28, thickness = 4})

		-- Cream window inside the coloured frame. Active so taps on the window never fall through to
		-- the menu behind a page that overlaps it on short screens.
		local window = create("Frame", page, {
			Name = "MotifWindow", Position = UDim2.new(0, 12, 0, 66), Size = UDim2.new(1, -24, 1, -78),
			BackgroundColor3 = P.panel, BorderSizePixel = 0, Active = true, ZIndex = 0,
		})
		round(window, UDim.new(0, 18))
		edge(window, 3)
		kit:dots(window, {name = "MotifWindowDots", columns = 14, rows = 5, size = 8, color = face, transparency = 0.86, zIndex = 0})

		kit:badge(page, "MotifPageBadge", ICONS[entry.icon] or "", P.panel, 54, {Position = UDim2.fromOffset(10, 6), Rotation = -8, ZIndex = 2})
		local title = need(page, "Title")
		title.Position, title.Size = UDim2.new(0, 76, 0, 10), UDim2.new(1, -196, 0, 46)
		title.TextYAlignment = Enum.TextYAlignment.Center
		local ink, thickness = kit:textOn(face, 32)
		title.TextColor3 = ink
		kit:setFont(title, "title")
		kit:fitHeading(title, 32, 16)
		if thickness then kit:outline(title, thickness) end

		local close = need(page, "CloseButton")
		close.Position, close.TextSize = UDim2.new(1, -108, 0, 9), 18
		toyButton(close, {face = P.panel, pill = true})

		-- Hard print shadow + a small pop when the page opens.
		local shadow = hardShadow(page, 8, 9, 0.3, 2)
		local pop = create("UIScale", page, {Name = "MotifPop", Scale = 1})
		local shadowPop = create("UIScale", shadow, {Name = "MotifPop", Scale = 1})
		page:GetPropertyChangedSignal("Visible"):Connect(function()
			if page.Visible then
				pop.Scale, shadowPop.Scale = 0.92, 0.92
				kit:tween(pop, {Scale = 1}, 0.24)
				kit:tween(shadowPop, {Scale = 1}, 0.24)
			end
			refresh()
		end)
		ctx.pages[entry.page], ctx.pageShadows[entry.page] = page, shadow
	end
	refresh()
end

local function stageShop(ctx)
	local shop = ctx.pages.ShopPage
	local list = need(shop, "ProductList")
	list.Position, list.Size = UDim2.new(0, 20, 0, 74), UDim2.new(1, -40, 1, -88)
	list.ScrollBarThickness, list.ScrollBarImageColor3, list.ScrollBarImageTransparency = 8, P.outline, 0.25
	local layout = list:FindFirstChildOfClass("UIListLayout")
	if layout then layout.Padding = UDim.new(0, 12) end
	create("UIPadding", list, {Name = "MotifPadding", PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 10), PaddingLeft = UDim.new(0, 4)})

	local rows = {}
	ctx.rows = {}
	for _, child in ipairs(list:GetChildren()) do
		if string.sub(child.Name, 1, 8) == "Product_" then table.insert(rows, child) end
	end
	table.sort(rows, function(a, b) return (a.LayoutOrder or 0) < (b.LayoutOrder or 0) end)
	for index, row in ipairs(rows) do
		local id = string.sub(row.Name, 9)
		local candy = C[kit.candyOrder[(index - 1) % #kit.candyOrder + 1]]
		row.Size, row.BackgroundTransparency = UDim2.new(1, -14, 0, 84), 0
		adoptEdge(row)
		kit:panel(row, {color = kit.pastels[(index - 1) % #kit.pastels + 1], corner = 20, thickness = 3})
		kit:badge(row, "MotifProductBadge", ICONS[id] or ICONS.shop or "", candy, 56,
			{AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), Rotation = index % 2 == 0 and 6 or -6})

		local name = need(row, "ProductName")
		name.Position, name.Size = UDim2.new(0, 80, 0, 9), UDim2.new(1, -200, 0, 32)
		name.TextColor3, name.TextXAlignment = P.ink, Enum.TextXAlignment.Left
		kit:setFont(name, "strong")
		kit:fitHeading(name, 22, 13)

		-- Price on cocoa label tape with a frame-drawn coin.
		local price = need(row, "Price")
		price.Position, price.Size = UDim2.new(0, 80, 0, 46), UDim2.fromOffset(112, 28)
		price.BackgroundTransparency, price.BackgroundColor3, price.BorderSizePixel = 0, P.outline, 0
		round(price)
		coin(price, "MotifCoin", 20, UDim2.new(0, 5, 0.5, 0))
		local amount = mirrorText(price, "MotifPriceText", {
			Position = UDim2.new(0, 30, 0, 0), Size = UDim2.new(1, -38, 1, 0), TextColor3 = P.panel,
			TextXAlignment = Enum.TextXAlignment.Left, TextSize = 17,
		})
		kit:setFont(amount, "strong")

		local buy = need(row, "BuyButton")
		buy.TextSize = 20
		toyButton(buy, {role = "primary", corner = 14})
		table.insert(ctx.rows, {badge = row:FindFirstChild("MotifProductBadge"), name = name, price = price})
	end

	-- A little label tape on the frame's top edge (Latin only, so the toy-box face renders).
	local tag = create("TextLabel", shop, {
		Name = "MotifShopTag", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 88, 0, 0), Size = UDim2.fromOffset(150, 26),
		BackgroundColor3 = P.outline, BorderSizePixel = 0, Text = "RETRO TOY SHOP", TextSize = 15, TextColor3 = P.panel,
		Rotation = -3, Active = false, ZIndex = 3,
	})
	round(tag)
	kit:setFont(tag, "display")
	ctx.shopTag = tag
end

local function stageSettings(ctx)
	local page = ctx.pages.SettingsPage
	local TOGGLES = {{name = "Toggle_Music", icon = "\240\159\142\181"}, {name = "Toggle_SFX", icon = "\240\159\148\138"}} -- 🎵 🔊
	for index, entry in ipairs(TOGGLES) do
		local toggle = need(page, entry.name)
		toggle.Position, toggle.Size, toggle.TextSize = UDim2.new(0, 26, 0, 84 + (index - 1) * 72), UDim2.new(1, -52, 0, 60), 22
		local function isOn() return string.match(toggle.Text, "ON%s*$") ~= nil end
		local state = toyButton(toggle, {face = isOn() and C.gumdrop or P.quiet, corner = 18, height = 60})
		create("TextLabel", toggle, {
			Name = "MotifToggleIcon", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, -1),
			Size = UDim2.fromOffset(40, 40), Text = entry.icon, TextSize = 24, Active = false, ZIndex = toggle.ZIndex,
		})
		local track = create("Frame", toggle, {
			Name = "MotifSwitch", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, -1), Size = UDim2.fromOffset(64, 34),
			BorderSizePixel = 0, Active = false, ZIndex = toggle.ZIndex,
		})
		round(track)
		edge(track, 3)
		local knob = create("Frame", track, {
			Name = "MotifKnob", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(24, 24), BackgroundColor3 = P.panel,
			BorderSizePixel = 0, Active = false, ZIndex = toggle.ZIndex,
		})
		round(knob)
		edge(knob, 2.5)
		local function show(animate)
			local on = isOn()
			kit.faces[toggle] = on and C.gumdrop or P.quiet
			kit:paint(toggle, state)
			track.BackgroundColor3 = on and C.ring or P.disabled
			local target = on and UDim2.new(1, -17, 0.5, 0) or UDim2.new(0, 17, 0.5, 0)
			if animate then kit:tween(knob, {Position = target}, 0.18) else knob.Position = target end
		end
		show(false)
		toggle:GetPropertyChangedSignal("Text"):Connect(function() show(true) end)
	end
end

local function stageEmpty(ctx)
	for _, name in ipairs({"InventoryPage", "QuestsPage"}) do
		local page = ctx.pages[name]
		local empty = need(page, "Empty")
		empty.Position, empty.Size = UDim2.new(0, 24, 0, 84), UDim2.new(1, -48, 0, 32)
		empty.TextColor3, empty.TextXAlignment, empty.TextSize = P.muted, Enum.TextXAlignment.Center, 20
		kit:setFont(empty, "strong")
	end
	-- Empty toy box: the robot waits in the inventory; three stars wait for quests.
	local mascot = Spec.mascot
	if mascot then
		-- Still (no loops): this page is hidden most of the time; the main-screen robot is the animated one.
		kit:mascot(ctx.pages.InventoryPage, 76, mascot.parts, {
			name = "MotifRobot", aspect = mascot.aspect, still = true,
			props = {Position = UDim2.new(0.5, 0, 1, -24), ZIndex = 2, Rotation = -4},
		})
	end
	local quests = ctx.pages.QuestsPage
	for index, key in ipairs({"stripe", "tincar", "robot"}) do
		local mark = star(quests, "MotifQuestStar" .. index, UDim2.new(0.5, (index - 2) * 74, 1, -74), 58, colour(key), (index - 2) * 10, 2)
		mark.TextTransparency = 0.25
	end
end

-- Layout that depends on the screen: phone widths shrink the dock and move the top bar below the
-- Roblox top-bar buttons; the robot only appears where there is room beside the CTA.
local function stageFit(ctx)
	local gui = ctx.gui
	local function fit()
		local width, height = screenSize(gui)
		local narrow = width < 560
		local topY = narrow and topInset() + 4 or 14
		ctx.top.Position, ctx.top.Size = UDim2.new(0, 12, 0, topY), UDim2.new(1, -24, 0, 60)
		ctx.lid.Size = UDim2.new(1, 0, 0, topY + 60 + 16)
		if narrow then
			ctx.title.AnchorPoint, ctx.title.Position, ctx.title.Size = Vector2.new(0, 0.5), UDim2.new(0, 4, 0.5, 0), UDim2.new(0.56, 0, 0, 48)
			ctx.coins.Size = UDim2.new(0.4, 0, 0, 44)
		else
			ctx.title.AnchorPoint, ctx.title.Position, ctx.title.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), UDim2.new(0.4, 0, 0, 50)
			ctx.coins.Size = UDim2.new(0.26, 0, 0, 44)
		end
		ctx.coins.AnchorPoint, ctx.coins.Position = Vector2.new(1, 0.5), UDim2.new(1, -4, 0.5, 0)
		local navScale = math.clamp(math.min((width - 24) / 548, height / 620), 0.55, 1)
		ctx.navScale.Scale = navScale
		if ctx.robot then ctx.robot.Visible = width >= 820 and height >= 520 end

		-- Toy scatter shrinks with the short side of the screen.
		local k = math.clamp(math.min(width, height) / 720, 0.6, 1)
		for _, item in ipairs(ctx.decorItems) do
			local size = math.floor(item.size * k)
			if item.kind == "star" then
				item.object.TextSize = size
				item.object.Size = UDim2.fromOffset(math.floor(size * 1.3), math.floor(size * 1.3))
			else
				item.object.Size = UDim2.fromOffset(size, size)
			end
		end

		-- Pages sit in the free band between the lid and the dock; when that band is too short
		-- (landscape phones) they become a full-height sheet over both.
		local freeTop = topY + 60 + 16 + 12
		local freeHeight = height - 14 - 108 * navScale - 12 - freeTop
		local pageTop, pageHeight
		if freeHeight >= 260 then
			pageHeight = math.min(freeHeight, 520)
			pageTop = freeTop + (freeHeight - pageHeight) / 2
		else
			pageHeight, pageTop = height - 16, 8
		end
		local pageWidth = math.clamp(width * 0.62, math.min(340, width - 24), 760)
		for _, page in pairs(ctx.pages) do
			page.Position = UDim2.new(0.5, 0, 0, math.floor(pageTop))
			page.Size = UDim2.fromOffset(math.floor(pageWidth), math.floor(pageHeight))
		end
		if ctx.shopTag then ctx.shopTag.Visible = pageWidth >= 420 and pageTop >= 24 end -- the tape sits above the frame's top edge

		-- Product rows: on narrow pages the toy badge steps aside so the name and price keep their room.
		local narrowRows = pageWidth - 82 < 380
		for _, row in ipairs(ctx.rows or {}) do
			local x = narrowRows and 14 or 80
			if row.badge then row.badge.Visible = not narrowRows end
			row.name.Position, row.name.Size = UDim2.new(0, x, 0, 9), UDim2.new(1, -(x + 120), 0, 32)
			row.price.Position = UDim2.new(0, x, 0, 46)
		end
	end
	fit()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
end

-- Loops stop while the menu is hidden (gui.Enabled = false) and run again when it returns.
local function stageMotion(ctx)
	local gui = ctx.gui
	gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		for _, tween in ipairs(ctx.loops) do
			pcall(function()
				if gui.Enabled then tween:Play() else tween:Pause() end
			end)
		end
	end)
end

Skin.stages = {
	{name = "root", run = stageRoot},
	{name = "topBar", run = stageTopBar},
	{name = "play", run = stagePlay},
	{name = "nav", run = stageNav},
	{name = "pages", run = stagePages},
	{name = "shop", run = stageShop},
	{name = "settings", run = stageSettings},
	{name = "empty", run = stageEmpty},
	{name = "fit", run = stageFit},
	{name = "motion", run = stageMotion},
}

-- Skins one MainMenu ScreenGui. Returns true; errors (with the stage name) if a stage fails.
-- Idempotent: a gui that is already skinned is left alone.
function Skin.apply(gui)
	if gui == nil or gui.Name ~= "MainMenu" then return false end
	if skinned[gui] then return true end
	local ctx = {gui = gui, loops = {}}
	for _, stage in ipairs(Skin.stages) do
		local ok, err = pcall(stage.run, ctx)
		if not ok then error("RetroToySkin stage '" .. stage.name .. "' failed: " .. tostring(err), 0) end
	end
	skinned[gui] = true
	return true
end

return Skin
