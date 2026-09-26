--!nocheck
-- Ennichi scene: dresses the main menu as a summer-festival fair at dusk.
--
--   dusk sky (plum -> rose -> sunset) with stars and two still fireworks
--   a string of paper lanterns (祭) sagging under the sign board, swaying slowly
--   the PLAY button as the big glowing lantern (soot caps, cord, ribs, breathing glow)
--   a wooden stall counter; the nav buttons are stall fronts with striped awnings
--   (candy apple / goldfish scooping / shooting gallery / ramune & wind chime)
--   goods on the counter: a goldfish in a bag, a candy apple, a ramune bottle
--   pages hang a noren curtain in their stall colour; shop rows carry price tags;
--   settings rows get on/off switches and a wind chime; empty pages get a goldfish tub / a target
--
-- Scene.decorate(gui, refs) only ADDS instances whose names start with "Motif" and changes looks
-- (colour, size, position, z-order, font) of the menu's own instances. Names, parents, text contracts
-- and callbacks stay as MainMenu built them. If anything throws, every Motif* instance added here is
-- removed again and the menu keeps the theme-level skin.
local Skin = require(script.Parent:WaitForChild("EnnichiSkin"))

local kit, P = Skin.kit, Skin.P
local candy = kit.candies

local Scene = {}

local MAX_LANTERNS = 11
local TILE_W, TILE_H, TILE_GAP = 120, 96, 14
local NAV_W = 4 * TILE_W + 3 * TILE_GAP
local PRODUCT_ICONS = {speed_coil = "🌀", rainbow_trail = "🌈", double_jump = "🐸"}

-- Small constructors ---------------------------------------------------------------------------------
local function make(className, parent, props)
	local object = Instance.new(className)
	for key, value in pairs(props or {}) do
		object[key] = value
	end
	object.Parent = parent
	return object
end

local function frame(parent, name, props)
	local object = make("Frame", nil, {Name = name, BorderSizePixel = 0, Active = false, BackgroundTransparency = 0})
	for key, value in pairs(props or {}) do
		object[key] = value
	end
	object.Parent = parent
	return object
end

local function round(object, radius)
	return make("UICorner", object, {CornerRadius = radius or UDim.new(1, 0)})
end

local function edge(object, thickness, color, transparency)
	local stroke = object:FindFirstChild("MotifEdge") or make("UIStroke", object, {Name = "MotifEdge"})
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color, stroke.Thickness, stroke.Transparency = color or P.outline, thickness or 3, transparency or 0
	pcall(function() stroke.LineJoinMode = Enum.LineJoinMode.Round end)
	return stroke
end

local function circle(parent, name, x, y, size, color, props)
	local dot = frame(parent, name, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(size, size), BackgroundColor3 = color})
	for key, value in pairs(props or {}) do dot[key] = value end
	round(dot)
	return dot
end

local function sequence(stops)
	local points = {}
	for _, stop in ipairs(stops) do table.insert(points, ColorSequenceKeypoint.new(stop[1], stop[2])) end
	return ColorSequence.new(points)
end

-- Sky --------------------------------------------------------------------------------------------------
local function firework(parent, name, position, radius, outer, inner)
	local burst = frame(parent, name, {AnchorPoint = Vector2.new(0.5, 0.5), Position = position,
		Size = UDim2.fromOffset(radius * 2, radius * 2), BackgroundTransparency = 1, ZIndex = 1})
	for index = 0, 11 do
		local angle = math.rad(index * 30)
		local cos, sin = math.cos(angle), math.sin(angle)
		frame(burst, "Streak", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5 + 0.34 * cos, 0.5 + 0.34 * sin),
			Size = UDim2.new(0.26, 0, 0, 2), Rotation = index * 30, BackgroundColor3 = outer, BackgroundTransparency = 0.45, ZIndex = 1})
		local tip = frame(burst, "Spark", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5 + 0.5 * cos, 0.5 + 0.5 * sin),
			Size = UDim2.fromOffset(7, 7), BackgroundColor3 = outer, BackgroundTransparency = 0.15, ZIndex = 1})
		round(tip)
		local angle2 = math.rad(index * 30 + 15)
		frame(burst, "Seed", {AnchorPoint = Vector2.new(0.5, 0.5), Rotation = 45, -- a 5 px diamond: no corner needed
			Position = UDim2.fromScale(0.5 + 0.22 * math.cos(angle2), 0.5 + 0.22 * math.sin(angle2)),
			Size = UDim2.fromOffset(5, 5), BackgroundColor3 = inner, BackgroundTransparency = 0.2, ZIndex = 1})
	end
	return burst
end

local function sky(background)
	background.BackgroundColor3 = P.white
	background.BackgroundTransparency = 0
	make("UIGradient", background, {Name = "MotifSky", Rotation = 90,
		Color = sequence({{0, P.dusk}, {0.42, P.akane}, {0.78, P.yuyake}, {1, P.yuyake}})})
	local stars = frame(background, "MotifStars", {Size = UDim2.fromScale(1, 0.42), BackgroundTransparency = 1, ZIndex = 1})
	local seed = 20260924
	local function random()
		seed = (seed * 16807) % 2147483647
		return seed / 2147483647
	end
	for _ = 1, 24 do
		local size = 3 + math.floor(random() * 4)
		local star = frame(stars, "Star", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(random(), random()),
			Size = UDim2.fromOffset(size, size), BackgroundColor3 = P.paper, BackgroundTransparency = 0.2 + random() * 0.5, ZIndex = 1})
		if size >= 5 then round(star) else star.Rotation = 45 end
	end
	firework(background, "MotifHanabiLeft", UDim2.fromScale(0.13, 0.42), 56, candy.wataame, P.glow)
	firework(background, "MotifHanabiRight", UDim2.fromScale(0.87, 0.35), 46, candy.ramune, P.glow)
end

-- Lanterns ---------------------------------------------------------------------------------------------
-- The holder's centre is the hang point, so rotating the holder swings the lantern from its cord.
local function lantern(parent, index)
	local red = index % 2 == 1
	local body = red and P.lanternRed or P.panel
	local holder = frame(parent, "Lantern", {AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(64, 164),
		BackgroundTransparency = 1, ZIndex = 2})
	make("UIScale", holder, {Name = "MotifLanternScale", Scale = 1})
	frame(holder, "Cord", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(32, 82), Size = UDim2.fromOffset(2, 12),
		BackgroundColor3 = P.outline, ZIndex = 2})
	circle(holder, "Glow", 32, 122, 84, P.primary, {BackgroundTransparency = 0.86, ZIndex = 2})
	circle(holder, "GlowCore", 32, 122, 62, P.primary, {BackgroundTransparency = 0.74, ZIndex = 2})
	local shell = frame(holder, "Body", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(32, 122),
		Size = UDim2.fromOffset(42, 52), BackgroundColor3 = body, ZIndex = 2})
	round(shell, UDim.new(0, 19))
	edge(shell, 2.5)
	for _, y in ipairs({0.24, 0.76}) do
		frame(shell, "Rib", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, y), Size = UDim2.new(0.86, 0, 0, 2),
			BackgroundColor3 = P.outline, BackgroundTransparency = 0.72, ZIndex = 2})
	end
	local mark = make("TextLabel", shell, {Name = "Mark", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(30, 30), Text = "祭", TextSize = 21,
		TextColor3 = red and P.outline or P.lanternRed, ZIndex = 2})
	kit:setFont(mark, "title")
	for _, y in ipairs({96, 148}) do
		local cap = frame(holder, "Cap", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(32, y),
			Size = UDim2.fromOffset(28, 7), BackgroundColor3 = P.outline, ZIndex = 2})
		round(cap, UDim.new(0, 3))
	end
	frame(holder, "Tassel", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(32, 151), Size = UDim2.fromOffset(5, 12),
		BackgroundColor3 = red and P.outline or P.lanternRed, ZIndex = 2})
	return holder
end

-- Big lantern PLAY ---------------------------------------------------------------------------------------
local function lanternButton(play, background)
	play.ZIndex = 6
	play.Rotation = (Skin.spec.shape and Skin.spec.shape.tilt) or -2
	play.TextSize = 36
	kit:setFont(play, "button")
	local corner = play:FindFirstChildOfClass("UICorner") or round(play)
	corner.CornerRadius = UDim.new(0, 40)
	-- Bamboo rings. The inner pair crosses the ends of the glyphs faintly, like lettering on a real lantern.
	for index, rib in ipairs({{0.18, 0.78, 0.7}, {0.34, 0.92, 0.82}, {0.66, 0.92, 0.82}, {0.82, 0.78, 0.7}}) do
		frame(play, "MotifRib" .. index, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, rib[1]),
			Size = UDim2.new(rib[2], 0, 0, 2), BackgroundColor3 = P.outline, BackgroundTransparency = rib[3], ZIndex = play.ZIndex})
	end
	for _, y in ipairs({0, 1}) do
		local cap = frame(play, y == 0 and "MotifCapTop" or "MotifCapBottom", {AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, y), Size = UDim2.new(0.5, 0, 0, 14), BackgroundColor3 = P.outline, ZIndex = play.ZIndex})
		round(cap, UDim.new(0, 5))
	end
	frame(play, "MotifCord", {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -6), Size = UDim2.fromOffset(3, 24),
		BackgroundColor3 = P.outline, ZIndex = play.ZIndex})
	local hook = frame(play, "MotifHook", {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -28),
		Size = UDim2.fromOffset(14, 14), BackgroundTransparency = 1, ZIndex = play.ZIndex})
	round(hook)
	edge(hook, 3)
	local state = Skin.stateOf(play)
	if state then kit:paint(play, state) end

	-- Lantern light: three warm, mostly clear layers (a soft falloff, not a flat plate).
	local glow = frame(background, "MotifPlayGlow", {AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(420, 200),
		BackgroundColor3 = P.primary, BackgroundTransparency = 0.88, ZIndex = 5})
	round(glow)
	local mid = frame(glow, "Mid", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.86, 0.8),
		BackgroundColor3 = P.primary, BackgroundTransparency = 0.8, ZIndex = 5})
	round(mid)
	local core = frame(mid, "Core", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.86, 0.8),
		BackgroundColor3 = P.glow, BackgroundTransparency = 0.72, ZIndex = 5})
	round(core)
	local breath = make("UIScale", glow, {Name = "MotifBreath", Scale = 1})
	return glow, breath
end

-- Stall counter and stall-front tiles ------------------------------------------------------------------------
local function stall(background)
	local counter = frame(background, "MotifStall", {AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 92), BackgroundColor3 = P.white, ZIndex = 3})
	make("UIGradient", counter, {Name = "MotifWood", Rotation = 90,
		Color = sequence({{0, P.wood:Lerp(P.white, 0.08)}, {1, P.wood:Lerp(P.outline, 0.35)}})})
	frame(counter, "Ledge", {Position = UDim2.fromOffset(0, 3), Size = UDim2.new(1, 0, 0, 12), BackgroundColor3 = P.woodTop, ZIndex = 3})
	frame(counter, "Edge", {Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = P.outline, ZIndex = 3})
	frame(counter, "LedgeShadow", {Position = UDim2.fromOffset(0, 15), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = P.outline,
		BackgroundTransparency = 0.55, ZIndex = 3})
	for _, y in ipairs({0.55, 0.8}) do
		frame(counter, "Plank", {Position = UDim2.fromScale(0, y), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = P.outline,
			BackgroundTransparency = 0.72, ZIndex = 3})
	end
	return counter
end

local function awning(tile, color)
	for index = 0, 3 do
		local scallop = frame(tile, "MotifScallop", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new((index + 0.5) / 4, 0, 0, 21),
			Size = UDim2.new(0.25, 0, 0, 14), BackgroundColor3 = index % 2 == 0 and color or P.paper, ZIndex = tile.ZIndex})
		round(scallop)
		edge(scallop, 2)
	end
	local cloth = frame(tile, "MotifAwning", {Size = UDim2.new(1, 0, 0, 21), BackgroundColor3 = P.white, ZIndex = tile.ZIndex + 1})
	round(cloth, UDim.new(0, 16))
	kit:stripes(cloth, color, P.paper, 4, 0)
	return cloth
end

local function navTiles(nav, buttons)
	nav.ZIndex = 8
	nav.Size = UDim2.fromOffset(NAV_W, TILE_H + 16)
	nav.Position = UDim2.new(0.5, 0, 1, -12)
	local list = nav:FindFirstChildOfClass("UIListLayout")
	if list then
		list.Padding = UDim.new(0, TILE_GAP)
		list.VerticalAlignment = Enum.VerticalAlignment.Bottom
	end
	local scale = make("UIScale", nav, {Name = "MotifNavScale", Scale = 1})
	for id, tile in pairs(buttons) do
		local info = Skin.PAGES[id]
		local color = info and Skin.color(info.color) or P.primary
		tile.ZIndex = 6
		tile.Size = UDim2.fromOffset(TILE_W, TILE_H)
		tile.TextSize = 17
		tile.TextYAlignment = Enum.TextYAlignment.Bottom
		make("UIPadding", tile, {Name = "MotifPad", PaddingBottom = UDim.new(0, 12)})
		awning(tile, color)
		make("TextLabel", tile, {Name = "MotifTileIcon", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(TILE_W / 2, 45), Size = UDim2.fromOffset(46, 46), Text = info and info.icon or "",
			TextSize = 30, TextColor3 = P.white, ZIndex = tile.ZIndex + 2, Active = false})
		-- Lit ring: the open page's stall glows lantern-gold inside its ink edge (the page covers the space
		-- above the tiles, so the marker has to live inside them).
		local lit = frame(tile, "MotifLit", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 6),
			Size = UDim2.new(1, -10, 1, -10 + 12), BackgroundTransparency = 1, Visible = false, ZIndex = tile.ZIndex + 3})
		round(lit, UDim.new(0, 13))
		edge(lit, 4, P.primary)
		local state = Skin.stateOf(tile)
		if state then kit:paint(tile, state) end
	end
	return scale
end

-- Goods on the counter --------------------------------------------------------------------------------------
local function goldfish(parent, size, props, still)
	local mascot = Skin.spec.mascot
	local root = kit:mascot(parent, size, mascot.parts, {
		name = "MotifKingyo", aspect = mascot.aspect, blink = mascot.blink, still = still,
		sway = 5, swaySeconds = 2.2, props = props,
	})
	return root
end

local function kingyoBag(parent)
	local bag = frame(parent, "MotifKingyoBag", {AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(116, 158),
		BackgroundTransparency = 1, ZIndex = 4})
	make("UIScale", bag, {Name = "MotifPropScale", Scale = 1})
	local clear = P.water:Lerp(P.white, 0.55)
	local loopRing = circle(bag, "Loop", 58, 13, 30, P.white, {Size = UDim2.fromOffset(34, 22), BackgroundTransparency = 1, ZIndex = 4})
	edge(loopRing, 3, candy.ringoame)
	local neck = frame(bag, "Neck", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(58, 36), Size = UDim2.fromOffset(30, 18),
		BackgroundColor3 = clear, BackgroundTransparency = 0.3, ZIndex = 4})
	round(neck, UDim.new(0, 6))
	edge(neck, 2, P.outline, 0.25)
	local body = frame(bag, "Bag", {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(58, 158), Size = UDim2.fromOffset(106, 116),
		BackgroundColor3 = clear, BackgroundTransparency = 0.35, ZIndex = 4})
	round(body, UDim.new(0, 44))
	edge(body, 3, P.outline, 0.1)
	local water = frame(body, "Water", {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromScale(1, 0.66),
		BackgroundColor3 = P.water, BackgroundTransparency = 0.25, ZIndex = 4})
	round(water, UDim.new(0, 42))
	frame(water, "Surface", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.04), Size = UDim2.new(0.8, 0, 0, 3),
		BackgroundColor3 = P.white, BackgroundTransparency = 0.35, ZIndex = 4})
	circle(body, "Shine", 22, 30, 14, P.white, {Size = UDim2.fromOffset(12, 30), BackgroundTransparency = 0.4, Rotation = 12, ZIndex = 4})
	circle(bag, "Knot", 58, 26, 14, candy.ringoame, {ZIndex = 4})
	goldfish(water, 58, {Position = UDim2.fromScale(0.5, 0.86), ZIndex = 4}, false)
	return bag
end

local function candyApple(parent)
	local apple = frame(parent, "MotifRingoame", {AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(80, 150),
		BackgroundTransparency = 1, ZIndex = 4})
	make("UIScale", apple, {Name = "MotifPropScale", Scale = 1})
	local stick = frame(apple, "Stick", {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(40, 150), Size = UDim2.fromOffset(8, 78),
		BackgroundColor3 = P.woodTop:Lerp(P.white, 0.35), ZIndex = 4})
	round(stick, UDim.new(0, 3))
	edge(stick, 2)
	local pool = circle(apple, "Pool", 40, 80, 40, candy.ringoame, {Size = UDim2.fromOffset(40, 12), ZIndex = 4})
	edge(pool, 2.5)
	local ball = circle(apple, "Candy", 40, 46, 72, candy.ringoame, {ZIndex = 4})
	edge(ball, 3)
	circle(ball, "Shine", 22, 22, 20, P.white, {Size = UDim2.fromOffset(22, 13), Rotation = -32, BackgroundTransparency = 0.25, ZIndex = 4})
	circle(ball, "Shine2", 48, 16, 6, P.white, {BackgroundTransparency = 0.35, ZIndex = 4})
	local stem = frame(apple, "Stem", {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(40, 13), Size = UDim2.fromOffset(4, 10),
		BackgroundColor3 = P.wood, ZIndex = 4})
	round(stem, UDim.new(0, 2))
	return apple
end

local function ramuneBottle(parent)
	local bottle = frame(parent, "MotifRamune", {AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(60, 150),
		BackgroundTransparency = 1, ZIndex = 4})
	make("UIScale", bottle, {Name = "MotifPropScale", Scale = 1})
	local glass = P.water:Lerp(P.white, 0.45)
	local neck = frame(bottle, "Neck", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(30, 52), Size = UDim2.fromOffset(28, 46),
		BackgroundColor3 = glass, BackgroundTransparency = 0.1, ZIndex = 4})
	round(neck, UDim.new(0, 11))
	edge(neck, 2.5)
	local body = frame(bottle, "Body", {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(30, 150), Size = UDim2.fromOffset(52, 90),
		BackgroundColor3 = glass, BackgroundTransparency = 0.1, ZIndex = 4})
	round(body, UDim.new(0, 16))
	edge(body, 3)
	local band = frame(body, "Label", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 0, 24),
		BackgroundColor3 = P.panel, ZIndex = 4})
	edge(band, 2)
	circle(band, "Mark", 26, 12, 14, candy.ramune, {ZIndex = 4})
	for index, spot in ipairs({{16, 16, 6}, {36, 26, 4}, {22, 74, 5}}) do
		circle(body, "Bubble" .. index, spot[1], spot[2], spot[3], P.white, {BackgroundTransparency = 0.3, ZIndex = 4})
	end
	local marble = circle(bottle, "Marble", 30, 44, 20, P.white:Lerp(P.water, 0.15), {ZIndex = 4})
	edge(marble, 2)
	circle(marble, "Shine", 7, 7, 5, P.white, {ZIndex = 4})
	local cap = frame(bottle, "Cap", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(30, 26), Size = UDim2.fromOffset(30, 14),
		BackgroundColor3 = candy.ramune, ZIndex = 4})
	round(cap, UDim.new(0, 5))
	edge(cap, 2.5)
	return bottle
end

-- Pages ---------------------------------------------------------------------------------------------------
local function noren(page, color)
	local cloth = frame(page, "MotifNoren", {Size = UDim2.new(1, 0, 0, 62), BackgroundColor3 = color, ZIndex = 1})
	round(cloth, UDim.new(0, 26))
	frame(cloth, "Square", {Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromScale(1, 0.5), BackgroundColor3 = color, ZIndex = 1})
	kit:dots(cloth, {name = "Dots", columns = 9, rows = 2, size = 9, transparency = 0.8, color = P.white, zIndex = 1})
	for _, x in ipairs({0.25, 0.5, 0.75}) do
		frame(cloth, "Slit", {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(x, 0, 1, 0), Size = UDim2.fromOffset(4, 14),
			BackgroundColor3 = P.paper, ZIndex = 1})
	end
	frame(cloth, "Rule", {Position = UDim2.new(0, 0, 1, -2), Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = P.outline, ZIndex = 1})
	return cloth
end

local function windChime(page)
	local holder = frame(page, "MotifFurin", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -74, 1, -196),
		Size = UDim2.fromOffset(70, 240), BackgroundTransparency = 1, ZIndex = 3})
	make("UIScale", holder, {Name = "MotifChimeScale", Scale = 1.3})
	circle(holder, "Peg", 35, 118, 8, P.wood, {ZIndex = 3})
	frame(holder, "Cord", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(35, 120), Size = UDim2.fromOffset(2, 16),
		BackgroundColor3 = P.outline, ZIndex = 3})
	frame(holder, "Clapper", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(35, 150), Size = UDim2.fromOffset(2, 30),
		BackgroundColor3 = P.outline, ZIndex = 3})
	local bell = frame(holder, "Bell", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(35, 134), Size = UDim2.fromOffset(46, 36),
		BackgroundColor3 = P.water:Lerp(P.white, 0.35), BackgroundTransparency = 0.15, ZIndex = 3})
	round(bell, UDim.new(0, 18))
	edge(bell, 2.5)
	circle(bell, "FishL", 14, 20, 9, candy.ringoame, {Size = UDim2.fromOffset(11, 7), Rotation = -15, ZIndex = 3})
	circle(bell, "FishR", 31, 14, 9, candy.kingyo, {Size = UDim2.fromOffset(10, 6), Rotation = 12, ZIndex = 3})
	frame(holder, "Rim", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(35, 169), Size = UDim2.fromOffset(44, 3),
		BackgroundColor3 = P.outline, ZIndex = 3})
	local strip = frame(holder, "Tanzaku", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(35, 178), Size = UDim2.fromOffset(20, 50),
		BackgroundColor3 = candy.fuji, ZIndex = 3})
	round(strip, UDim.new(0, 3))
	edge(strip, 2)
	return holder
end

local function goldfishTub(page)
	local tub = frame(page, "MotifKingyoTub", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, -20, 0.5, 60),
		Size = UDim2.new(0.66, 0, 0, 96), BackgroundColor3 = P.water, ZIndex = 3})
	make("UISizeConstraint", tub, {Name = "MotifTubSize", MaxSize = Vector2.new(340, 96)})
	round(tub)
	edge(tub, 3)
	local rim = frame(tub, "Rim", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.new(0.86, 0, 0, 18),
		BackgroundTransparency = 1, ZIndex = 3})
	round(rim)
	edge(rim, 2, P.white, 0.35)
	for index, spot in ipairs({{0.72, 0.62, 30}, {0.24, 0.72, 22}}) do
		local ripple = frame(tub, "Ripple" .. index, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(spot[1], spot[2]),
			Size = UDim2.fromOffset(spot[3], math.floor(spot[3] * 0.4)), BackgroundTransparency = 1, ZIndex = 3})
		round(ripple)
		edge(ripple, 2, P.white, 0.3)
	end
	goldfish(tub, 88, {Position = UDim2.fromScale(0.45, 0.82), ZIndex = 3}, false)
	local poi = frame(tub, "MotifPoi", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -2, 0.4, 0), Size = UDim2.fromOffset(74, 74),
		Rotation = -34, BackgroundTransparency = 1, ZIndex = 4})
	local handle = frame(poi, "Handle", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(37, 44), Size = UDim2.fromOffset(11, 34),
		BackgroundColor3 = candy.wataame, ZIndex = 4})
	round(handle, UDim.new(0, 5))
	edge(handle, 2)
	local ring = circle(poi, "Ring", 37, 26, 50, P.panel, {BackgroundTransparency = 0.15, ZIndex = 4})
	edge(ring, 4, candy.wataame)
	return tub
end

local function target(page)
	local group = frame(page, "MotifShateki", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 52),
		Size = UDim2.fromOffset(270, 150), BackgroundTransparency = 1, ZIndex = 3})
	for _, x in ipairs({64, 104}) do
		local leg = frame(group, "Leg", {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(x, 150), Size = UDim2.fromOffset(8, 44),
			Rotation = x < 84 and 10 or -10, BackgroundColor3 = P.wood, ZIndex = 3})
		edge(leg, 2)
	end
	local ring = circle(group, "Target", 84, 60, 118, candy.ringoame, {ZIndex = 3})
	edge(ring, 3)
	local parent = ring
	for index, color in ipairs({P.panel, candy.ringoame, P.panel, P.primary}) do
		local size = ({88, 60, 34, 14})[index]
		local inner = frame(parent, "Ring", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(size, size), BackgroundColor3 = color, ZIndex = 3})
		round(inner)
		parent = inner
	end
	local sign = frame(group, "Fuda", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(206, 64), Size = UDim2.fromOffset(112, 56),
		Rotation = 6, BackgroundColor3 = P.woodTop, ZIndex = 3})
	round(sign, UDim.new(0, 8))
	edge(sign, 3)
	frame(sign, "Cord", {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(2, 18),
		BackgroundColor3 = P.outline, ZIndex = 3})
	circle(sign, "Nail", 56, -19, 8, P.outline, {ZIndex = 3})
	local text = make("TextLabel", sign, {Name = "Text", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Text = "準備中",
		TextSize = 24, ZIndex = 3})
	kit:setFont(text, "title")
	local color, outline = kit:textOn(P.woodTop, 24)
	text.TextColor3 = color
	if outline then kit:outline(text, outline) end
	return group
end

-- The empty-state line sits centred just above its little scene (both hang around the page middle).
local function emptyNote(page, bottomFromMiddle)
	local note = page:FindFirstChild("Empty")
	if not note then return end
	note.TextXAlignment = Enum.TextXAlignment.Center
	note.AnchorPoint = Vector2.new(0, 1)
	note.Position = UDim2.new(0, 16, 0.5, bottomFromMiddle)
	note.Size = UDim2.new(1, -32, 0, 28)
	note.TextSize = 19
	kit:setFont(note, "strong")
end

local function dressPage(gui, id, page)
	local info = Skin.PAGES[id] or {color = "ringoame"}
	local color = Skin.color(info.color) or P.primary
	for _, child in ipairs(page:GetChildren()) do
		if child:IsA("GuiObject") then child.ZIndex = 3 end
	end
	page.ZIndex = 4
	page.AnchorPoint = Vector2.new(0.5, 0.5)
	page.Position = UDim2.fromScale(0.5, 0.53)
	local limits = {Name = "MotifPageSize", MinSize = Vector2.new(340, 330), MaxSize = Vector2.new(820, 560)}
	make("UISizeConstraint", page, limits)
	local corner = page:FindFirstChildOfClass("UICorner") or round(page)
	corner.CornerRadius = UDim.new(0, 26)
	edge(page, 4)
	noren(page, color)
	local foot = frame(page, "MotifYukata", {AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, -10), Size = UDim2.new(1, -20, 0.3, 0),
		BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 2})
	kit:dots(foot, {name = "Dots", columns = 11, rows = 2, size = 14, transparency = 0.86, color = color, zIndex = 2})
	kit:badge(page, "MotifPageBadge", info.icon or "", P.panel, 52, {Position = UDim2.fromOffset(14, 5), Rotation = -8, ZIndex = 4})
	local title = page:FindFirstChild("Title")
	if title then
		title.Position = UDim2.fromOffset(76, 11)
		title.Size = UDim2.new(1, -76 - 118, 0, 40)
		title.TextColor3 = P.white
		kit:setFont(title, "title")
		kit:outline(title, 3)
		kit:fitHeading(title, 30, 16)
	end
	local close = page:FindFirstChild("CloseButton")
	if close then close.ZIndex = 4 end

	-- Sticker shadow: same box as the page, a few px lower, behind it (page ZIndex 4, shadow 3).
	local shadow = frame(gui, "MotifPageShadow", {AnchorPoint = page.AnchorPoint, Position = UDim2.new(0.5, 0, 0.53, 8),
		Size = page.Size, BackgroundColor3 = P.outline, BackgroundTransparency = 0.55, ZIndex = 3, Visible = false})
	round(shadow, UDim.new(0, 26))
	make("UISizeConstraint", shadow, limits)
	return shadow
end

local function shopRows(list, rows)
	if not list then return end
	make("UIPadding", list, {Name = "MotifPad", PaddingLeft = UDim.new(0, 5), PaddingTop = UDim.new(0, 5),
		PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 6)})
	local layout = list:FindFirstChildOfClass("UIListLayout")
	if layout then layout.Padding = UDim.new(0, 10) end
	pcall(function() list.ScrollBarImageColor3 = P.outline end)
	for index, entry in ipairs(rows) do
		local row, product = entry.row, entry.product
		local order = (index - 1) % #kit.candyOrder + 1
		row.BackgroundColor3 = kit.pastels[order] or P.panel
		local corner = row:FindFirstChildOfClass("UICorner") or round(row)
		corner.CornerRadius = UDim.new(0, 18)
		kit:badge(row, "MotifItemBadge", PRODUCT_ICONS[product.id] or "🎁", candy[kit.candyOrder[order]], 44,
			{AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Rotation = -6, ZIndex = 2})
		local name, price, buy = row:FindFirstChild("ProductName"), row:FindFirstChild("Price"), row:FindFirstChild("BuyButton")
		if name then
			name.ZIndex = 2
			name.TextSize = 18
			name.TextColor3 = P.ink
			kit:setFont(name, "strong")
		end
		if price then
			-- A paper price tag tied on with a string (値札).
			price.ZIndex = 2
			price.BackgroundTransparency = 0
			price.BackgroundColor3 = P.panel
			price.TextXAlignment = Enum.TextXAlignment.Center
			price.TextWrapped = false
			price.TextSize = 17
			price.TextColor3 = P.ink
			price.Rotation = -3
			kit:setFont(price, "strong")
			round(price, UDim.new(0, 10))
			edge(price, 2.5)
			circle(price, "MotifTagHole", 9, 8, 7, P.paper, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 10, 0.5, 0), ZIndex = 2})
		end
		if buy then buy.ZIndex = 2 end
		local mode = nil
		local function arrange()
			local width = row.AbsoluteSize.X
			if width <= 0 then return end
			local buyWidth = width < 560 and 92 or 104
			local stacked = width < 420
			local key = (stacked and "stacked" or "row") .. buyWidth
			if key == mode then return end -- setting Size below re-fires AbsoluteSize: no re-entry
			mode = key
			if buy then
				buy.Size = UDim2.fromOffset(buyWidth, 48)
				buy.Position = UDim2.new(1, -buyWidth - 8, 0.5, -24)
			end
			local tagWidth = width < 560 and 96 or 108
			if stacked then
				row.Size = UDim2.new(1, -8, 0, 88)
				if name then
					name.TextSize = 16
					name.Position, name.Size = UDim2.fromOffset(64, 6), UDim2.new(1, -64 - buyWidth - 14, 0, 44)
				end
				if price then
					price.AnchorPoint, price.Position, price.Size = Vector2.new(0, 1), UDim2.new(0, 66, 1, -9), UDim2.fromOffset(tagWidth, 30)
				end
			else
				row.Size = UDim2.new(1, -8, 0, 68)
				if name then
					name.TextSize = 18
					name.Position, name.Size = UDim2.fromOffset(64, 0), UDim2.new(0.5, -64, 1, 0)
				end
				if price then
					price.AnchorPoint, price.Position, price.Size = Vector2.new(0, 0.5), UDim2.new(0.5, 6, 0.5, 0), UDim2.fromOffset(tagWidth, 34)
				end
			end
		end
		row:GetPropertyChangedSignal("AbsoluteSize"):Connect(arrange)
		arrange()
	end
end

local function switches(toggles)
	for index, id in ipairs({"music", "sfx"}) do
		local button = toggles[id]
		if button then
			Skin.setFace(button, kit.pastels[index == 1 and 4 or 3] or P.panel)
			button.TextSize = 20
			local switch = frame(button, "MotifSwitch", {AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0),
				Size = UDim2.fromOffset(64, 32), BackgroundColor3 = P.success, ZIndex = button.ZIndex})
			round(switch)
			edge(switch, 3)
			local knob = frame(switch, "Knob", {AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(24, 24),
				BackgroundColor3 = P.panel, ZIndex = button.ZIndex})
			round(knob)
			edge(knob, 2.5)
			local function sync(animate)
				local on = string.find(string.upper(button.Text or ""), "OFF", 1, true) == nil
				switch.BackgroundColor3 = on and P.success or P.disabled
				local goal = on and UDim2.new(1, -28, 0.5, 0) or UDim2.new(0, 4, 0.5, 0)
				if animate then kit:tween(knob, {Position = goal}, 0.16) else knob.Position = goal end
			end
			button:GetPropertyChangedSignal("Text"):Connect(function() sync(true) end)
			sync(false)
		end
	end
end

-- Layout -----------------------------------------------------------------------------------------------------
local function build(gui, refs, motion)
	local function loop(instance, props, seconds, delay)
		local tween = kit:loop(instance, props, seconds, delay)
		if tween then table.insert(motion, tween) end
		return tween
	end
	local background, top, play, nav = refs.background, refs.top, refs.play, refs.nav
	-- Every ZIndex below is relative to siblings (children always draw over their parent). Under the
	-- legacy Global behaviour page contents would sort under the page panel, so pin it.
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	sky(background)

	local string_ = frame(background, "MotifLanternString", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2})
	local rope, lanterns = {}, {}
	for index = 1, MAX_LANTERNS + 1 do
		rope[index] = frame(string_, "Rope", {AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(10, 3),
			BackgroundColor3 = P.outline, ZIndex = 2})
	end
	for index = 1, MAX_LANTERNS do
		local holder = lantern(string_, index)
		lanterns[index] = holder
		holder.Rotation = index % 2 == 0 and 3 or -3
		loop(holder, {Rotation = -holder.Rotation}, 2.4 + (index % 3) * 0.3, (index % 4) * 0.2)
	end

	-- Sign board
	top.ZIndex = 6
	kit:badge(top, "MotifSignBadge", Skin.icons.play or "🏮", P.glow, 44,
		{AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Rotation = -8})
	local title, coins = refs.title, refs.coins
	if title then
		title.Position = UDim2.fromOffset(64, 4)
		title.TextColor3 = candy.ringoame
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Rotation = -1.5
		kit:setFont(title, "display")
		kit:outline(title, 2.5)
		kit:fitHeading(title, 32, 14)
	end
	if coins then
		coins.BackgroundTransparency = 0
		coins.BackgroundColor3 = P.quiet
		coins.AnchorPoint = Vector2.new(1, 0.5)
		coins.Position = UDim2.new(1, -12, 0.5, 0)
		coins.TextXAlignment = Enum.TextXAlignment.Center
		coins.TextWrapped = false
		coins.TextColor3 = P.ink
		kit:setFont(coins, "strong")
		round(coins)
		edge(coins, 3)
	end

	local glow, breath = lanternButton(play, background)
	loop(breath, {Scale = 1.07}, 1.8)
	loop(glow, {BackgroundTransparency = 0.8}, 1.8)

	local counter = stall(background)
	local navScale = navTiles(nav, refs.navButtons or {})
	local goods = frame(background, "MotifStallGoods", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 4})
	local shelf = frame(goods, "MotifShelf", {AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(300, 12), BackgroundColor3 = P.woodTop,
		ZIndex = 4, Visible = false})
	round(shelf, UDim.new(0, 4))
	edge(shelf, 3)
	local bag, apple, bottle = kingyoBag(goods), candyApple(goods), ramuneBottle(goods)

	-- Pages
	-- Scrim lives in Background above everything except the stall tiles, so the open page's tile stays
	-- lit like a tab (pages are ScreenGui children and always draw above Background).
	local scrim = frame(background, "MotifScrim", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = P.dim, ZIndex = 7, Visible = false})
	make("UIGradient", scrim, {Name = "MotifScrimFade", Rotation = 90,
		Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0.22)})})
	local shadows = {}
	for id, page in pairs(refs.pages or {}) do
		shadows[id] = dressPage(gui, id, page)
	end
	shopRows(refs.list, refs.rows or {})
	switches(refs.toggles or {})
	for index, id in ipairs({"music", "sfx"}) do
		local toggle = refs.toggles and refs.toggles[id]
		if toggle then toggle.Position = UDim2.fromOffset(16, 84 + (index - 1) * 72) end -- clear of the noren
	end
	if refs.pages.Inventory then emptyNote(refs.pages.Inventory, -8) end
	if refs.pages.Quests then emptyNote(refs.pages.Quests, -36) end
	if refs.pages.Settings then windChime(refs.pages.Settings) end
	if refs.pages.Inventory then goldfishTub(refs.pages.Inventory) end
	if refs.pages.Quests then target(refs.pages.Quests) end
	local chime = refs.pages.Settings and refs.pages.Settings:FindFirstChild("MotifFurin")
	if chime then
		chime.Rotation = -4
		loop(chime, {Rotation = 4}, 2.2)
		-- Only hang it where it clears the two setting rows (short landscape pages have no room).
		local page = refs.pages.Settings
		local function fit() chime.Visible = page.AbsoluteSize.Y >= 430 end
		page:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		fit()
	end

	local function syncPages()
		local anyOpen = false
		for id, page in pairs(refs.pages) do
			local open = page.Visible == true
			anyOpen = anyOpen or open
			if shadows[id] then shadows[id].Visible = open end
			local tile = refs.navButtons and refs.navButtons[id]
			local lit = tile and tile:FindFirstChild("MotifLit")
			if lit then lit.Visible = open end
		end
		scrim.Visible = anyOpen
	end
	for _, page in pairs(refs.pages) do
		page:GetPropertyChangedSignal("Visible"):Connect(syncPages)
	end
	syncPages()

	-- Responsive placement: everything that depends on the screen size is set here.
	local function layout()
		local size = background.AbsoluteSize
		local w, h = size and size.X or 0, size and size.Y or 0
		if w < 320 or h < 240 then -- not laid out yet
			local camera = workspace.CurrentCamera
			if camera then w, h = camera.ViewportSize.X, camera.ViewportSize.Y end
		end
		if w < 1 or h < 1 then return end
		local u = math.clamp(math.min(w * 1.3 / 1280, h * 1.25 / 720), 0.62, 1)
		local short = h < 480

		-- Sign board: the coin pill shrinks on phones, the title scales into what is left.
		local coinWidth = w < 560 and 136 or 176
		if coins then
			coins.Size = UDim2.fromOffset(coinWidth, 44)
			coins.TextSize = w < 560 and 18 or 20
		end
		if title then title.Size = UDim2.new(1, -64 - coinWidth - 24, 1, -8) end

		-- Lantern string: a sagging rope under the sign board with evenly spaced lanterns.
		local ropeY = 88
		local lanternScale = short and 0.5 or math.clamp(u, 0.6, 1)
		local sag = short and 22 or 60 * u
		local count = math.clamp(math.floor(w / 118), 3, MAX_LANTERNS)
		local points = {{-12, ropeY}}
		for index = 1, MAX_LANTERNS do
			local holder = lanterns[index]
			holder.Visible = index <= count
			if index <= count then
				local x = w * index / (count + 1)
				local t = 2 * x / w - 1
				local y = ropeY + sag * (1 - t * t)
				holder.Position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5))
				holder.MotifLanternScale.Scale = lanternScale
				table.insert(points, {x, y})
			end
		end
		table.insert(points, {w + 12, ropeY})
		for index = 1, MAX_LANTERNS + 1 do
			local segment = rope[index]
			local a, b = points[index], points[index + 1]
			segment.Visible = a ~= nil and b ~= nil
			if a and b then
				local dx, dy = b[1] - a[1], b[2] - a[2]
				segment.Position = UDim2.fromOffset(math.floor((a[1] + b[1]) / 2 + 0.5), math.floor((a[2] + b[2]) / 2 + 0.5))
				segment.Size = UDim2.fromOffset(math.floor(math.sqrt(dx * dx + dy * dy) + 2.5), 3)
				segment.Rotation = math.deg(math.atan2(dy, dx))
			end
		end
		local lanternBottom = ropeY + sag + 82 * lanternScale

		-- Stall counter and tiles.
		local tileScale = math.clamp(math.min((w - 24) / NAV_W, u), 0.5, 1)
		navScale.Scale = tileScale
		local counterHeight = math.floor(92 * tileScale + 0.5)
		counter.Size = UDim2.new(1, 0, 0, counterHeight)
		local navTop = h - 12 - (TILE_H + 16) * tileScale

		-- The lantern button sits between the lantern string and the stall.
		local c = math.clamp(math.min((w - 48) / 300, h / 470), 0.75, 1)
		local ctaHeight = math.floor(96 * c + 0.5)
		play.Size = UDim2.fromOffset(math.floor(300 * c + 0.5), ctaHeight)
		play.TextSize = math.floor(36 * c + 0.5)
		local corner = play:FindFirstChildOfClass("UICorner")
		if corner then corner.CornerRadius = UDim.new(0, math.floor(40 * c + 0.5)) end
		local minCenter = lanternBottom + 12 + 34 * c + ctaHeight / 2
		local maxCenter = navTop - ctaHeight / 2 - 20
		local center = math.floor(math.max(minCenter, math.min(h * 0.54, maxCenter)) + 0.5)
		play.Position = UDim2.new(0.5, 0, 0, center)
		glow.Position = play.Position
		local state = Skin.stateOf(play)
		if state then kit:paint(play, state) end

		-- Goods stand on the counter beside the tiles when there is room; on tall phones they stand on a
		-- small shelf above the tiles, filling the gap under the lantern.
		local roomy = w >= 900 and h >= 560
		local tall = not roomy and h >= 640 and h >= w * 1.2
		goods.Visible = roomy or tall
		shelf.Visible = tall
		if roomy then
			local counterTop = h - counterHeight + 6
			local half = NAV_W * tileScale / 2
			local propScale = math.clamp(h / 720, 0.85, 1.15)
			bag.Position = UDim2.fromOffset(math.floor(w / 2 - half - 110), counterTop)
			apple.Position = UDim2.fromOffset(math.floor(w / 2 + half + 78), counterTop)
			bottle.Position = UDim2.fromOffset(math.floor(w / 2 + half + 148), counterTop)
			for _, prop in ipairs({bag, apple, bottle}) do prop.MotifPropScale.Scale = propScale end
		elseif tall then
			local propScale = math.clamp(w / 420, 0.75, 1)
			local shelfY = math.floor(navTop - 4)
			local ctaBottom = center + ctaHeight / 2 + 12
			if shelfY - 158 * propScale < ctaBottom then -- not enough height: hide rather than overlap the lantern
				goods.Visible = false
			else
				shelf.Position = UDim2.fromOffset(math.floor(w / 2), shelfY)
				shelf.Size = UDim2.fromOffset(math.floor(math.min(w - 40, 330 * propScale)), 12)
				bag.Position = UDim2.fromOffset(math.floor(w / 2), shelfY + 2)
				apple.Position = UDim2.fromOffset(math.floor(w / 2 - 104 * propScale), shelfY + 2)
				bottle.Position = UDim2.fromOffset(math.floor(w / 2 + 100 * propScale), shelfY + 2)
				for _, prop in ipairs({bag, apple, bottle}) do prop.MotifPropScale.Scale = propScale end
			end
		end
		glow.Size = UDim2.fromOffset(math.floor(math.min(420 * c, w * 0.96) + 0.5), math.floor(200 * c + 0.5))
	end
	background:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	layout()

	-- Idle loops stop while the menu is hidden.
	gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		for _, tween in ipairs(motion) do
			pcall(function()
				if gui.Enabled then tween:Play() else tween:Pause() end
			end)
		end
	end)
end

-- refs: {background, top, title, coins, play, nav, navButtons = {id = button}, pages = {id = frame},
--        list, rows = {{row, product}}, toggles = {music = button, sfx = button}}
function Scene.decorate(gui, refs)
	local existing = {}
	for _, object in ipairs(gui:GetDescendants()) do existing[object] = true end
	local motion = {}
	local ok, err = pcall(build, gui, refs, motion)
	if ok then
		Scene.motion = motion
		return true
	end
	for _, tween in ipairs(motion) do pcall(function() tween:Cancel() end) end
	for _, object in ipairs(gui:GetDescendants()) do
		local parent = object.Parent
		if not existing[object] and parent and (existing[parent] or parent == gui) and string.sub(object.Name, 1, 5) == "Motif" then
			object:Destroy()
		end
	end
	warn("[Ennichi] festival dressing skipped: " .. tostring(err))
	return false
end

return Scene
