-- Main menu, 夏祭りの縁日 edition: a stall signboard (top bar), a string of paper lanterns, a 金魚すくい tub with
-- a lantern-red PLAY button floating on the water, a candy-apple stand and a ramune cooler either side, and
-- wooden stall tags (nav) that open 暖簾-curtained pages.
-- Other systems find these instances by name (see tests/test_main_menu.luau); the names and parent/child paths
-- of the previous menu are all kept: MainMenu.Background.TopBar.{Title,CoinLabel}, Background.PlayButton,
-- Background.NavBar.Nav_*, MainMenu.{Shop,Inventory,Quests,Settings}Page.{Title,CloseButton},
-- ShopPage.ProductList.Product_<id>.{ProductName,Price,BuyButton}, SettingsPage.Toggle_{Music,SFX}, *.Empty.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("UITheme"))
local Art = require(Shared:WaitForChild("FestivalArt"))

local P = Theme.palette
local create = Theme.create

local MainMenu = {}

local NAV = {
	{id = "Shop", label = "ショップ", icon = "candyApple", noren = P.vermilion},
	{id = "Inventory", label = "持ち物", icon = "goldfishBag", noren = P.ramuneDeep},
	{id = "Quests", label = "クエスト", icon = "target", noren = P.bamboo},
	{id = "Settings", label = "設定", icon = "uchiwa", noren = P.wisteria},
}
local PAGE_NAMES = {"ShopPage", "SettingsPage", "InventoryPage", "QuestsPage"}
local CREST_COLORS = {P.vermilion, P.ramuneDeep, P.bamboo}

local TOP_BAR_HEIGHT = 56
local SPAN, SPANS, SAG = 190, 12, 26 -- lantern rope: pixel span between lanterns, number of spans, droop
local LANTERN_W, LANTERN_H = 58, 80
local NAV_W, NAV_H, NAV_GAP = 136, 60, 12
local NAV_BOTTOM = 18
local NAV_RESERVE = NAV_BOTTOM + NAV_H + 4 + 10 -- kept free at the bottom for the stall tags
local LANTERN_DROP = LANTERN_H + 8 -- how far the lanterns hang below the rope (before the decor scale)

local function formatCoins(amount)
	local digits = tostring(math.floor(tonumber(amount) or 0))
	local sign, body = string.match(digits, "^(-?)(%d+)$")
	if not body then return digits end
	local grouped = (string.gsub(string.reverse(body), "(%d%d%d)", "%1,"))
	grouped = string.reverse(grouped)
	grouped = (string.gsub(grouped, "^,", ""))
	return sign .. grouped
end
MainMenu.formatCoins = formatCoins

local function firstCharacter(text)
	return string.match(text or "", "^[\1-\127\194-\244][\128-\191]*") or "?"
end

-- Top inset of Roblox's own top bar (menu / chat buttons), so our signboard never sits under them.
local function topInset()
	local ok, inset = pcall(function() return GuiService:GetGuiInset() end)
	if ok and typeof(inset) == "Vector2" then return inset.Y end
	return 0
end

local function viewportSize()
	local camera = workspace.CurrentCamera
	return camera and camera.ViewportSize or Vector2.new(1280, 720)
end

-- The lantern string is drawn in pixels; shrink it on short (phone) screens. Buttons are never scaled.
local function decorScale()
	local size = viewportSize()
	return math.clamp(math.min(size.Y / 720, size.X / 1280), 0.55, 1)
end

local ICONS = {
	candyApple = function(face, props) return Art.candyApple(face, "Icon", props) end,
	goldfishBag = function(face, props) return Art.goldfishBag(face, "Icon", props, 12) end,
	target = function(face, props) return Art.target(face, "Icon", props) end,
	uchiwa = function(face, props) return Art.uchiwa(face, "Icon", props) end,
}

-- Idle motion ---------------------------------------------------------------------------------------------
local function animate(anim, t)
	for _, lantern in ipairs(anim.lanterns) do
		lantern.frame.Rotation = math.sin(t * 1.25 + lantern.phase) * 3.2
	end
	for _, glow in ipairs(anim.glows) do
		glow.frame.BackgroundTransparency = math.clamp(glow.base + math.sin(t * glow.speed + glow.phase) * glow.amp, 0, 1)
	end
	local waterSize = anim.water.AbsoluteSize
	local width, height = math.max(waterSize.X, 1), math.max(waterSize.Y, 1)
	for _, fish in ipairs(anim.fish) do
		local x = 0.5 + fish.ax * math.sin(t * fish.wx + fish.px)
		local y = 0.5 + fish.ay * math.sin(t * fish.wy + fish.py)
		local dx = fish.ax * fish.wx * math.cos(t * fish.wx + fish.px) * width
		local dy = fish.ay * fish.wy * math.cos(t * fish.wy + fish.py) * height
		fish.frame.Position = UDim2.fromScale(x, y)
		fish.frame.Rotation = math.deg(math.atan2(dy, dx)) -- Luau math.atan ignores a 2nd argument
		fish.tail.Rotation = math.sin(t * 7 + fish.px * 3) * 16
	end
	for _, bubble in ipairs(anim.bubbles) do
		local p = (t * bubble.speed + bubble.phase) % 1
		bubble.frame.Position = UDim2.fromScale(bubble.x + math.sin(p * 9) * 0.04, 0.95 - p * 0.5)
		bubble.frame.BackgroundTransparency = 0.25 + p * 0.65
	end
	for _, ripple in ipairs(anim.ripples) do
		local p = (t / ripple.period + ripple.phase) % 1
		local d = 14 + p * 96
		ripple.frame.Size = UDim2.fromOffset(d, d * 0.7)
		ripple.stroke.Transparency = 0.3 + p * 0.7
	end
end

local function startAnimation(gui, background, anim)
	animate(anim, 0) -- resting pose, also what reduced-motion players see
	local heartbeat = RunService and RunService.Heartbeat
	if not heartbeat then return end
	local start = os.clock()
	local connection
	connection = heartbeat:Connect(function()
		if not gui.Parent then connection:Disconnect() return end
		if not gui.Enabled or not background.Visible or Theme.reducedMotion() then return end
		animate(anim, os.clock() - start)
	end)
	gui.Destroying:Connect(function() connection:Disconnect() end)
end

-- Pages ---------------------------------------------------------------------------------------------------
-- Pages hang just under the signboard and stop above the stall tags; on short phone screens the minimum
-- height wins and the page covers the tags (it has its own close button).
local function page(gui, name, title, norenColor, pageTop)
	local frame = Theme.panel(gui, name, UDim2.new(0.62, 0, 1, -(pageTop + NAV_RESERVE)), UDim2.new(0.5, 0, 0, pageTop))
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.ZIndex = 20
	frame.Visible = false
	frame:FindFirstChildOfClass("UIStroke").Thickness = 3
	create("UISizeConstraint", {MinSize = Vector2.new(360, 240), MaxSize = Vector2.new(780, 440), Parent = frame})
	create("UIScale", {Name = "PopScale", Scale = 1, Parent = frame})
	Art.noren(frame, norenColor, 64).ZIndex = 1
	local titleLabel = Theme.label(frame, "Title", title, 26, {bold = true, color = P.washi, stroke = norenColor:Lerp(Color3.new(0, 0, 0), 0.55),
		frameSize = UDim2.new(1, -150, 0, 44)})
	titleLabel.Position = UDim2.new(0, 22, 0, 6)
	titleLabel.ZIndex = 5
	local close = Theme.button(frame, "CloseButton", "閉じる", function() frame.Visible = false end,
		{size = UDim2.new(0, 96, 0, 48), style = "washi"})
	close.Position = UDim2.new(1, -110, 0, 6)
	close.ZIndex = 6
	return frame
end

local function popIn(frame)
	local scale = frame:FindFirstChild("PopScale")
	if not scale then return end
	if Theme.reducedMotion() then scale.Scale = 1 return end
	scale.Scale = 0.9
	Theme.tween(scale, 0.22, {Scale = 1}, Enum.EasingStyle.Back)
end

-- handlers: {play = fn(), buy = fn(productId), toggle = fn(settingId, on), navigate = fn(pageId)?}
-- state: {coins = number, products = {{id, name, price}}, settings = {music = bool, sfx = bool}}
function MainMenu.build(playerGui, handlers, state)
	state = state or {}
	local inset = topInset()
	local anim = {lanterns = {}, glows = {}, fish = {}, bubbles = {}, ripples = {}}

	local gui = create("ScreenGui", {Name = "MainMenu", ResetOnSpawn = false, IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = playerGui})

	-- 夕暮れの境内: dusk sky fading to the warm glow of the stalls, dark ground at the bottom.
	local background = create("Frame", {Name = "Background", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 1, Parent = gui})
	Theme.gradient(background, {{0, P.duskTop}, {0.45, P.duskMid}, {0.74, P.duskLow}, {1, P.ground}}, 90)

	-- Out-of-focus lights of the stalls further down the approach.
	local bokeh = create("Frame", {Name = "Bokeh", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
		ZIndex = 2, Parent = background})
	for index, spec in ipairs({{0.07, 0.36, 96}, {0.2, 0.52, 58}, {0.34, 0.32, 40}, {0.64, 0.3, 52}, {0.79, 0.47, 88},
		{0.94, 0.33, 46}, {0.5, 0.4, 30}, {0.1, 0.8, 72}, {0.9, 0.8, 66}}) do
		local light = create("Frame", {Name = "Light" .. index, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(spec[1], spec[2]),
			Size = UDim2.fromOffset(spec[3], spec[3]), BackgroundColor3 = P.lanternGlow, BackgroundTransparency = 0.84,
			BorderSizePixel = 0, ZIndex = index, Parent = bokeh})
		Theme.round(light)
		table.insert(anim.glows, {frame = light, base = 0.84, amp = 0.05, speed = 0.6 + index * 0.11, phase = index})
	end

	-- 屋台の看板 (top bar) --------------------------------------------------------------------------------
	local top = Theme.panel(background, "TopBar", UDim2.new(1, -32, 0, TOP_BAR_HEIGHT), UDim2.new(0, 16, 0, inset + 6))
	top.ZIndex = 30
	top.BackgroundColor3 = P.wood
	top:FindFirstChildOfClass("UIStroke").Thickness = 3
	top:FindFirstChildOfClass("UIGradient"):Destroy()
	Theme.shade(top, 90, 0.2)
	for index, y in ipairs({0.33, 0.67}) do
		create("Frame", {Name = "Grain" .. index, Position = UDim2.new(0, 8, y, 0), Size = UDim2.new(1, -16, 0, 2),
			BackgroundColor3 = P.woodDark, BackgroundTransparency = 0.75, BorderSizePixel = 0, ZIndex = 1, Parent = top})
	end
	local seal = create("Frame", {Name = "Seal", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(38, 38), Rotation = -4, BackgroundColor3 = P.vermilion, BorderSizePixel = 0, ZIndex = 2, Parent = top})
	Theme.corner(seal, 6)
	Theme.stroke(seal, P.washi, 2)
	Theme.label(seal, "Glyph", "祭", 24, {bold = true, color = P.washi, align = Enum.TextXAlignment.Center, frameSize = UDim2.fromScale(1, 1)})
	local title = Theme.label(top, "Title", "OBBY RUSH", 34, {display = true, color = P.washi, stroke = P.woodDark,
		strokeThickness = 2.5, frameSize = UDim2.new(0.5, -60, 1, 0)})
	title.Position = UDim2.new(0, 62, 0, 1)
	title.ZIndex = 2
	local chip = create("Frame", {Name = "CoinChip", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(168, 40), BackgroundColor3 = P.washi, BorderSizePixel = 0, ZIndex = 2, Parent = top})
	Theme.round(chip)
	Theme.stroke(chip, P.woodDark, 2)
	Art.coin(chip, "CoinIcon", {AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 6, 0.5, 0), Size = UDim2.fromOffset(30, 30)}, P.washi)
	local coins = Theme.label(top, "CoinLabel", formatCoins(state.coins), 22, {bold = true, align = Enum.TextXAlignment.Right,
		frameSize = UDim2.fromOffset(112, 32)})
	coins.AnchorPoint = Vector2.new(1, 0.5)
	coins.Position = UDim2.new(1, -30, 0.5, 0)
	coins.ZIndex = 3

	-- 提灯 string --------------------------------------------------------------------------------------------
	local garland = create("Frame", {Name = "LanternGarland", AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, inset + 6 + TOP_BAR_HEIGHT + 4), Size = UDim2.fromOffset(SPAN * SPANS, LANTERN_H + SAG + 24),
		BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 4, Parent = background})
	local garlandScale = create("UIScale", {Scale = decorScale(), Parent = garland})
	local radius = (SPAN * SPAN / 4 + SAG * SAG) / (2 * SAG) -- circle through both hang points, dipping SAG px
	for index = 0, SPANS - 1 do
		local span = create("Frame", {Name = "Rope" .. index, Position = UDim2.fromOffset(index * SPAN, 0), Size = UDim2.fromOffset(SPAN, SAG + 6),
			BackgroundTransparency = 1, BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 1, Parent = garland})
		local arc = create("Frame", {Name = "Arc", Position = UDim2.fromOffset(SPAN / 2 - radius, SAG - 2 * radius),
			Size = UDim2.fromOffset(2 * radius, 2 * radius), BackgroundTransparency = 1, BorderSizePixel = 0, Parent = span})
		Theme.round(arc)
		Theme.stroke(arc, Color3.fromRGB(58, 30, 22), 3)
	end
	for index = 0, SPANS do
		local hanger = create("Frame", {Name = "Hanger" .. index, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(index * SPAN, 3),
			Size = UDim2.fromOffset(LANTERN_W, LANTERN_H * 2), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2, Parent = garland})
		local kind = index % 2 == 0 and "red" or "white"
		local _, glows = Art.lantern(hanger, "Lantern", kind, kind == "red" and "祭" or "夏",
			{AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 0.5)})
		table.insert(anim.lanterns, {frame = hanger, phase = index * 0.9})
		for _, glow in ipairs(glows) do
			table.insert(anim.glows, {frame = glow, base = glow.BackgroundTransparency, amp = 0.035, speed = 2.1 + (index % 3) * 0.4, phase = index * 1.7})
		end
	end

	-- Side stalls -------------------------------------------------------------------------------------------
	local stand = Art.appleStand(background, "CandyAppleStand", {AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 5})
	local cooler, bubbles = Art.ramuneCooler(background, "RamuneCooler", {AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 5})
	for _, stall in ipairs({stand, cooler}) do
		create("UISizeConstraint", {MaxSize = Vector2.new(250, 290), Parent = stall})
	end
	for index, bubble in ipairs(bubbles) do
		table.insert(anim.bubbles, {frame = bubble, x = bubble.Position.X.Scale, speed = 0.35 + (index % 3) * 0.08, phase = index * 0.27})
	end

	-- 金魚すくい tub -----------------------------------------------------------------------------------------
	local tub = create("Frame", {Name = "GoldfishTub", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = P.tubRim,
		BorderSizePixel = 0, ZIndex = 6, Parent = background})
	create("UISizeConstraint", {MinSize = Vector2.new(300, 104), MaxSize = Vector2.new(640, 250), Parent = tub})
	Theme.round(tub)
	Theme.stroke(tub, P.ramuneDeep, 3)
	Theme.shade(tub, 90, 0.14)
	local water = create("Frame", {Name = "Water", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -22, 1, -22), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 2, Parent = tub})
	Theme.round(water)
	Theme.gradient(water, {{0, P.water}, {1, P.waterDeep}}, 90)
	Theme.stroke(water, P.waterDeep, 2, 0.4)
	anim.water = water
	for index, spec in ipairs({{0.3, 0.3, 0.2, 0.07}, {0.66, 0.24, 0.14, 0.05}, {0.78, 0.7, 0.18, 0.06}, {0.22, 0.72, 0.12, 0.05}}) do
		local caustic = create("Frame", {Name = "Caustic" .. index, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(spec[1], spec[2]),
			Size = UDim2.fromScale(spec[3], spec[4]), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.84,
			BorderSizePixel = 0, ZIndex = 1, Parent = water})
		Theme.round(caustic)
	end
	for index, spec in ipairs({{0.2, 0.36, 4.2, 0}, {0.74, 0.62, 5.1, 0.45}, {0.42, 0.78, 4.6, 0.75}}) do
		local ring = create("Frame", {Name = "Ripple" .. index, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(spec[1], spec[2]),
			Size = UDim2.fromOffset(40, 28), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2, Parent = water})
		Theme.round(ring)
		table.insert(anim.ripples, {frame = ring, stroke = Theme.stroke(ring, Color3.new(1, 1, 1), 2, 0.5), period = spec[3], phase = spec[4]})
	end
	-- kind, length px, Lissajous amplitude x/y (water scale), angular speed x/y, phase x/y
	local school = {
		{"red", 56, 0.4, 0.3, 0.22, 0.44, -1.3, 0.6},
		{"calico", 54, 0.32, 0.28, 0.3, 0.3, 2.1, 3.6},
		{"demekin", 48, 0.36, 0.3, 0.19, 0.38, 4.0, 0.2},
		{"red", 52, 0.42, 0.32, 0.26, 0.26, 1.0, 5.6},
		{"orange", 46, 0.26, 0.3, 0.34, 0.17, 3.4, 1.1},
		{"red", 44, 0.38, 0.26, 0.28, 0.21, 5.6, 2.3},
	}
	for index, spec in ipairs(school) do
		local fish, tail = Art.goldfish(water, "Goldfish" .. index, spec[1], spec[2])
		fish.ZIndex = 3 + index
		table.insert(anim.fish, {frame = fish, tail = tail, ax = spec[3], ay = spec[4], wx = spec[5], wy = spec[6], px = spec[7], py = spec[8]})
	end
	local sign = create("Frame", {Name = "StallSign", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 28, 0, 3),
		Size = UDim2.fromOffset(156, 34), Rotation = -4, BackgroundColor3 = P.washiWhite, BorderSizePixel = 0, ZIndex = 10, Parent = tub})
	Theme.corner(sign, 4)
	Theme.stroke(sign, P.vermilion, 2)
	Theme.label(sign, "Text", "きんぎょすくい", 18, {bold = true, color = P.vermilionDeep, align = Enum.TextXAlignment.Center,
		frameSize = UDim2.fromScale(1, 1)})
	local poi = Art.poi(tub, "Poi", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -26, 1, -20), Size = UDim2.fromOffset(40, 88),
		Rotation = 38, ZIndex = 11})
	local decorScales = {}
	for _, object in ipairs({sign, poi}) do
		table.insert(decorScales, create("UIScale", {Name = "DecorScale", Parent = object}))
	end

	-- PLAY: a lit lantern floating on the tub ---------------------------------------------------------------------
	-- Three stacked pale pills fake a soft radial glow (UIGradient is linear only).
	local playGlows = {}
	for index, spec in ipairs({{460, 190, 0.9}, {390, 150, 0.86}, {330, 118, 0.8}}) do
		local glow = create("Frame", {Name = "PlayGlow" .. index, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(spec[1], spec[2]),
			BackgroundColor3 = P.lanternCore, BackgroundTransparency = spec[3], BorderSizePixel = 0, ZIndex = 7, Parent = background})
		Theme.round(glow)
		table.insert(decorScales, create("UIScale", {Name = "DecorScale", Parent = glow}))
		table.insert(playGlows, glow)
		table.insert(anim.glows, {frame = glow, base = spec[3], amp = 0.04, speed = 2.2, phase = index})
	end
	local play = Theme.button(background, "PlayButton", "プレイ", function() handlers.play() end,
		{primary = true, size = UDim2.new(0, 280, 0, 76), textSize = 34, radius = 38})
	play.AnchorPoint = Vector2.new(0.5, 0.5)
	play.ZIndex = 9
	local playFace = play:FindFirstChild("Face")
	for index, y in ipairs({0.3, 0.52, 0.74}) do
		create("Frame", {Name = "Rib" .. index, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, y),
			Size = UDim2.new(0.86, 0, 0, 2), BackgroundColor3 = P.vermilionDeep, BackgroundTransparency = 0.65, BorderSizePixel = 0,
			ZIndex = 2, Parent = playFace})
	end
	local topRing = create("Frame", {Name = "TopRing", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, 5),
		Size = UDim2.new(0.34, 0, 0, 11), BackgroundColor3 = P.lacquer, BorderSizePixel = 0, ZIndex = 6, Parent = playFace})
	Theme.corner(topRing, 4)
	local bottomRing = create("Frame", {Name = "BottomRing", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, -3),
		Size = UDim2.new(0.3, 0, 0, 9), BackgroundColor3 = P.lacquer, BorderSizePixel = 0, ZIndex = 6, Parent = playFace})
	Theme.corner(bottomRing, 4)

	-- Dim the fairground while a page is open (top bar and stall tags stay lit).
	local scrim = create("Frame", {Name = "Scrim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = P.night, BackgroundTransparency = 0.38,
		BorderSizePixel = 0, Visible = false, ZIndex = 25, Parent = background})

	-- 屋台の木札 (nav) ----------------------------------------------------------------------------------------
	local nav = create("Frame", {Name = "NavBar", Size = UDim2.fromOffset(NAV_W * #NAV + NAV_GAP * (#NAV - 1), NAV_H + 4),
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -NAV_BOTTOM), BackgroundTransparency = 1, BorderSizePixel = 0,
		ZIndex = 30, Parent = background})
	create("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, NAV_GAP),
		HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = nav})

	local pages = {}
	for _, item in ipairs(NAV) do
		pages[item.id] = page(gui, item.id .. "Page", item.label, item.noren, inset + 6 + TOP_BAR_HEIGHT + 8)
	end

	local navButtons = {}
	for index, item in ipairs(NAV) do
		local button = Theme.button(nav, "Nav_" .. item.id, item.label, function()
			MainMenu.open(gui, item.id)
			if handlers.navigate then handlers.navigate(item.id) end
		end, {size = UDim2.fromOffset(NAV_W, NAV_H), order = index, iconSpace = 36, style = "wood"})
		local iconSize = item.icon == "candyApple" and UDim2.fromOffset(36, 42) or UDim2.fromOffset(34, 34)
		ICONS[item.icon](button:FindFirstChild("Face"), {AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0),
			Size = iconSize, ZIndex = 4})
		navButtons[item.id] = button
	end

	-- Shop: one wooden price tag per product.
	local list = create("ScrollingFrame", {Name = "ProductList", Size = UDim2.new(1, -24, 1, -86), Position = UDim2.new(0, 12, 0, 76),
		BackgroundTransparency = 1, BorderSizePixel = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 6, ScrollBarImageColor3 = P.wood, ZIndex = 2, Parent = pages.Shop})
	create("UIListLayout", {Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list})
	create("UIPadding", {PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 10), PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 12), Parent = list})
	for index, product in ipairs(state.products or {}) do
		local row = Theme.panel(list, "Product_" .. product.id, UDim2.new(1, 0, 0, 72))
		row.LayoutOrder = index
		row.BackgroundColor3 = P.washiWhite
		Art.crest(row, "Crest", firstCharacter(product.name), CREST_COLORS[(index - 1) % #CREST_COLORS + 1],
			{AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), Size = UDim2.fromOffset(46, 46)})
		local nameLabel = Theme.label(row, "ProductName", product.name, 20, {bold = true, frameSize = UDim2.new(1, -200, 0, 28)})
		nameLabel.Position = UDim2.new(0, 70, 0, 7)
		nameLabel.TextScaled = true
		create("UITextSizeConstraint", {MaxTextSize = 20, MinTextSize = 12, Parent = nameLabel})
		Art.coin(row, "PriceCoin", {AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 70, 0, 50), Size = UDim2.fromOffset(22, 22)}, P.washiWhite)
		local price = Theme.label(row, "Price", formatCoins(product.price), 19, {bold = true, color = P.vermilionDeep,
			frameSize = UDim2.fromOffset(110, 26)})
		price.Position = UDim2.new(0, 98, 0, 37)
		local buy = Theme.button(row, "BuyButton", "購入", function() handlers.buy(product.id) end,
			{primary = true, size = UDim2.new(0, 104, 0, 52), textSize = 20})
		buy.AnchorPoint = Vector2.new(1, 0.5)
		buy.Position = UDim2.new(1, -12, 0.5, 0)
	end

	-- Settings: 太鼓 = music, 風鈴 = sound effects, each with a ramune-marble switch.
	local settings = state.settings or {}
	for index, id in ipairs({"music", "sfx"}) do
		local labelText = id == "music" and "音楽" or "効果音"
		local on = settings[id] ~= false
		local toggle, setSwitch
		toggle = Theme.button(pages.Settings, "Toggle_" .. (id == "music" and "Music" or "SFX"), labelText .. ": " .. (on and "ON" or "OFF"), function()
			on = not on
			toggle.Text = labelText .. ": " .. (on and "ON" or "OFF")
			setSwitch(on, true)
			handlers.toggle(id, on)
		end, {size = UDim2.new(1, -32, 0, 60), style = "washi", align = Enum.TextXAlignment.Left, iconSpace = 42, textSize = 20})
		toggle.Position = UDim2.new(0, 16, 0, 80 + (index - 1) * 72)
		local face = toggle:FindFirstChild("Face")
		local drawIcon = id == "music" and Art.taiko or Art.furin
		drawIcon(face, "Icon", {AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), Size = UDim2.fromOffset(36, 36), ZIndex = 4})
		local _, set = Art.ramuneSwitch(face, "Switch", on, {AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), ZIndex = 6})
		setSwitch = set
	end

	-- Empty pages get a small illustration above the original message.
	Art.goldfishBag(pages.Inventory, "Illustration", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 18),
		Size = UDim2.fromOffset(84, 104), ZIndex = 3})
	Art.target(pages.Quests, "Illustration", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 18),
		Size = UDim2.fromOffset(96, 96), ZIndex = 3}, true)
	for _, id in ipairs({"Inventory", "Quests"}) do
		local text = id == "Inventory" and "まだアイテムがありません" or "今日のクエストは準備中です"
		local empty = Theme.label(pages[id], "Empty", text, 18, {bold = true, color = P.inkSoft, align = Enum.TextXAlignment.Center,
			frameSize = UDim2.new(1, -32, 0, 28)})
		empty.AnchorPoint = Vector2.new(0.5, 0)
		empty.Position = UDim2.new(0.5, 0, 0.5, 78)
		empty.ZIndex = 3
	end

	-- Selected stall tag lights up like a lantern; the fairground dims behind an open page.
	local function refresh()
		local openId
		for _, item in ipairs(NAV) do
			if pages[item.id].Visible then openId = item.id end
		end
		scrim.Visible = openId ~= nil
		for id, button in pairs(navButtons) do
			Theme.setButtonStyle(button, id == openId and "primary" or "wood")
		end
	end
	for _, frame in pairs(pages) do
		frame:GetPropertyChangedSignal("Visible"):Connect(refresh)
	end
	refresh()

	-- The fairground (tub, PLAY, stalls) is centred in whatever space the lanterns and stall tags leave.
	-- Everything is expressed as UDim2 offsets, so it only needs recomputing when the decor scale changes.
	local function relayout()
		local scale = decorScale()
		garlandScale.Scale = scale
		for _, uiScale in ipairs(decorScales) do uiScale.Scale = scale end
		local heroTop = inset + 6 + TOP_BAR_HEIGHT + 4 + math.floor(LANTERN_DROP * scale)
		local used = heroTop + NAV_RESERVE
		local centre = (heroTop - NAV_RESERVE) / 2
		tub.Position = UDim2.new(0.5, 0, 0.5, centre)
		tub.Size = UDim2.new(0.5, 0, 1, -(used + 8))
		play.Position = UDim2.new(0.5, 0, 0.5, centre)
		for _, glow in ipairs(playGlows) do glow.Position = UDim2.new(0.5, 0, 0.5, centre) end
		stand.Position = UDim2.new(0.13, 0, 0.5, centre)
		cooler.Position = UDim2.new(0.87, 0, 0.5, centre)
		for _, stall in ipairs({stand, cooler}) do stall.Size = UDim2.new(0.2, 0, 1, -used) end
	end
	relayout()

	-- Re-fit when the screen changes (rotating a phone, resizing the Studio window).
	local camera = workspace.CurrentCamera
	local okSignal, viewportChanged = pcall(function() return camera:GetPropertyChangedSignal("ViewportSize") end)
	if okSignal and viewportChanged then
		local connection = viewportChanged:Connect(relayout)
		gui.Destroying:Connect(function() connection:Disconnect() end)
	end

	startAnimation(gui, background, anim)
	return gui
end

function MainMenu.open(gui, pageId)
	for _, name in ipairs(PAGE_NAMES) do
		local frame = gui:FindFirstChild(name)
		if frame then
			local show = name == pageId .. "Page"
			if show and not frame.Visible then popIn(frame) end
			frame.Visible = show
		end
	end
end

-- Convenience for the coin updater: writes the formatted amount into TopBar.CoinLabel.
function MainMenu.setCoins(gui, amount)
	local label = gui and gui:FindFirstChild("CoinLabel", true)
	if label then label.Text = formatCoins(amount) end
end

return MainMenu
