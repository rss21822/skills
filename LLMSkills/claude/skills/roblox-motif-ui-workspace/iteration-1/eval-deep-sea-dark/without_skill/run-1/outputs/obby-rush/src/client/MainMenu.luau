-- Main menu: top bar, PLAY, nav bar and the Shop / Inventory / Quests / Settings pages.
-- Other systems find these instances by name (see tests/test_main_menu.luau).
--
-- Skin: deep-sea expedition. PLAY is the glowing bulb of an anglerfish lurking in the dark,
-- the nav bar is a row of jellyfish (each page keeps its jelly's colour), secondary buttons are
-- bubbles, and pages are jellyfish-bell membranes. See DESIGN.md next to the project.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))
local DeepSea = require(script.Parent:WaitForChild("DeepSea"))

local MainMenu = {}
local C = Theme.colors

local NAV = {
	{id = "Shop", label = "ショップ", hue = C.lure},
	{id = "Inventory", label = "持ち物", hue = C.jellyPink},
	{id = "Quests", label = "クエスト", hue = C.bioGreen},
	{id = "Settings", label = "設定", hue = C.jellyViolet},
}
local HUE = {}
for _, item in ipairs(NAV) do
	HUE[item.id] = item.hue
end
local PAGE_NAMES = {"ShopPage", "SettingsPage", "InventoryPage", "QuestsPage"}
local PEARLS = {C.bioCyan, C.jellyPink, C.bioGreen, C.jellyViolet}

-- Light the jelly of the open page and dim the scene behind an open page.
local function refresh(gui)
	local anyOpen = false
	for _, item in ipairs(NAV) do
		local frame = gui:FindFirstChild(item.id .. "Page")
		local open = frame ~= nil and frame.Visible == true
		anyOpen = anyOpen or open
		local nav = gui:FindFirstChild("Nav_" .. item.id, true)
		if nav then
			Theme.setSelected(nav, open)
		end
	end
	local scrim = gui:FindFirstChild("Scrim", true)
	if scrim then
		scrim.Visible = anyOpen
	end
end

-- Vertical layout from the screen height: pages always fit between the top bar and the nav jellies,
-- and on short screens (phones in landscape) the jellies sit lower with shorter tentacles.
local function layoutFor(viewport)
	local navGap = viewport.Y >= 560 and 72 or 44
	local pageTop = math.max(88, math.floor(viewport.Y * 0.13))
	return {
		navGap = navGap,
		tentacles = navGap >= 72 and 34 or 22,
		navTop = viewport.Y - navGap - 64,
		pageTop = pageTop,
		pageReserve = pageTop + navGap + 64 + 26, -- 26 = lappets + breathing room above the bells
	}
end

local function page(gui, layout, name, title, hue)
	local frame = Theme.panel(gui, name, UDim2.new(0.6, 0, 1, -layout.pageReserve), UDim2.new(0.2, 0, 0, layout.pageTop), {hue = hue})
	frame.Visible = false
	frame.ZIndex = 10
	Theme.create("UIScale", {Name = "OpenScale", Scale = 1, Parent = frame})
	Theme.glow(frame, "TitleGlow", 34, UDim2.new(0, 30, 0, 30), hue, {rings = 3, strength = 0.8, inner = 0.4}).ZIndex = 2
	Theme.circle(frame, "TitleLight", 11, UDim2.new(0, 30, 0, 30), hue:Lerp(Color3.new(1, 1, 1), 0.35), 0).ZIndex = 2
	Theme.label(frame, "Title", title, 26, {display = true, frameSize = UDim2.new(1, -160, 0, 44)}).Position = UDim2.new(0, 48, 0, 8)
	local close = Theme.button(frame, "CloseButton", "閉じる", function()
		frame.Visible = false
		refresh(gui)
	end, {size = UDim2.new(0, 96, 0, 48), hue = hue})
	close.Position = UDim2.new(1, -112, 0, 8)
	return frame
end

-- Page body that scrolls when the screen is short (phones in landscape).
local function scrollList(frame, name, barColor)
	local list = Theme.create("ScrollingFrame", {Name = name, Size = UDim2.new(1, -32, 1, -88), Position = UDim2.new(0, 16, 0, 68),
		BackgroundTransparency = 1, BorderSizePixel = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6, ScrollBarImageColor3 = barColor, ScrollBarImageTransparency = 0.35, ZIndex = 2, Parent = frame})
	Theme.create("UIListLayout", {Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list})
	return list
end

-- An empty page gets a small sleeping jelly instead of a bare line of text.
local function emptyState(frame, text, hue)
	Theme.jelly(frame, "EmptyJelly", {width = 64, hue = hue, tentacles = 3, length = 30, dots = 4, dim = 0.25,
		anchor = Vector2.new(0.5, 1), position = UDim2.new(0.5, 0, 0.5, -18), phase = 1}).ZIndex = 2
	local label = Theme.label(frame, "Empty", text, 18, {color = C.subtext, align = Enum.TextXAlignment.Center,
		frameSize = UDim2.new(1, -32, 0, 26)})
	label.Position = UDim2.new(0, 16, 0.5, 34)
	return label
end

-- handlers: {play = fn(), buy = fn(productId), toggle = fn(settingId, on), navigate = fn(pageId)?}
-- state: {coins = number, products = {{id, name, price}}, settings = {music = bool, sfx = bool}}
function MainMenu.build(playerGui, handlers, state)
	local viewport = DeepSea.viewportSize()
	local layout = layoutFor(viewport)
	local gui = Theme.create("ScreenGui", {Name = "MainMenu", ResetOnSpawn = false, IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = playerGui})
	local background = Theme.create("Frame", {Name = "Background", Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.colors.background, BackgroundTransparency = 0.04, BorderSizePixel = 0, Parent = gui})
	DeepSea.backdrop(background, viewport)

	-- Top bar: bioluminescent wordmark on the left, a pearl-bubble coin counter on the right.
	local top = Theme.panel(background, "TopBar", UDim2.new(1, -32, 0, 64), UDim2.new(0, 16, 0, 16), {variant = "clear"})
	top.ZIndex = 6
	Theme.label(top, "Title", "OBBY RUSH", 34, {display = true, color = C.lureCore, glow = C.lureDeep,
		frameSize = UDim2.new(0.5, 0, 0, 46)}).Position = UDim2.new(0, 16, 0, -1)
	Theme.label(top, "Subtitle", "深海たんけん", 14, {bold = true, color = C.subtext,
		frameSize = UDim2.new(0.5, 0, 0, 18)}).Position = UDim2.new(0, 19, 0, 45)
	Theme.panel(top, "CoinBubble", UDim2.fromOffset(188, 48), UDim2.new(1, -204, 0, 8), {variant = "capsule", hue = C.lure})
	local coins = Theme.label(top, "CoinLabel", "🪙 " .. Theme.formatNumber(state.coins or 0), 22,
		{display = true, color = C.lureCore, align = Enum.TextXAlignment.Center, frameSize = UDim2.fromOffset(188, 48)})
	coins.Position = UDim2.new(1, -204, 0, 8)
	coins.ZIndex = 3

	-- PLAY: the anglerfish lure. Sized so it never meets the nav jellies on short screens; the fish
	-- itself (head, eye, teeth) only surfaces when there is room above the nav.
	local orb = math.clamp(math.floor(viewport.Y * 0.24), 112, 168)
	local center = UDim2.new(0.5, 0, 0.5, -28)
	DeepSea.lure(background, orb, center, {roomBelow = layout.navTop - (viewport.Y / 2 - 28)})
	local play = Theme.button(background, "PlayButton", "プレイ", function() handlers.play() end,
		{primary = true, shape = "orb", size = UDim2.fromOffset(orb, orb), textSize = math.floor(orb * 0.2)})
	play.AnchorPoint = Vector2.new(0.5, 0.5)
	play.Position = center
	play.ZIndex = 3
	local hint = Theme.label(background, "PlayHint", "深海へダイブ", 16, {bold = true, color = C.lure,
		align = Enum.TextXAlignment.Center, frameSize = UDim2.fromOffset(220, 22)})
	hint.AnchorPoint = Vector2.new(0.5, 0)
	hint.Position = UDim2.new(0.5, 0, 0.5, -28 + orb / 2 + 14)
	hint.ZIndex = 3
	-- On short screens (phones in landscape) the hint would touch the nav jellies: drop it.
	hint.Visible = viewport.Y / 2 - 28 + orb / 2 + 14 + 22 + 8 <= layout.navTop

	-- Behind an open page the sea goes darker (and PLAY can't be hit through it).
	Theme.create("Frame", {Name = "Scrim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.abyss, BackgroundTransparency = 0.18,
		BorderSizePixel = 0, Active = true, Visible = false, ZIndex = 5, Parent = background})

	-- Nav: jellyfish. Tentacles hang into the gap below the bar.
	local nav = Theme.create("Frame", {Name = "NavBar", Size = UDim2.new(0, 560, 0, 64), AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -layout.navGap), BackgroundTransparency = 1, ZIndex = 6, Parent = background})
	Theme.create("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 16),
		HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = nav})

	local pages = {}
	pages.Shop = page(gui, layout, "ShopPage", "ショップ", HUE.Shop)
	pages.Settings = page(gui, layout, "SettingsPage", "設定", HUE.Settings)
	pages.Inventory = page(gui, layout, "InventoryPage", "持ち物", HUE.Inventory)
	pages.Quests = page(gui, layout, "QuestsPage", "クエスト", HUE.Quests)
	emptyState(pages.Inventory, "まだアイテムがありません", HUE.Inventory)
	emptyState(pages.Quests, "今日のクエストは準備中です", HUE.Quests)

	for index, item in ipairs(NAV) do
		Theme.jellyButton(nav, "Nav_" .. item.id, item.label, function()
			MainMenu.open(gui, item.id)
			if handlers.navigate then handlers.navigate(item.id) end
		end, {hue = item.hue, size = UDim2.new(0, 128, 0, 64), order = index, tentacleLength = layout.tentacles})
	end

	-- Shop: one capsule per product, a glowing specimen pearl, the price and a lure-coloured Buy.
	local list = scrollList(pages.Shop, "ProductList", C.lure)
	for index, product in ipairs(state.products or {}) do
		local row = Theme.panel(list, "Product_" .. product.id, UDim2.new(1, -10, 0, 64), nil, {variant = "capsule", hue = C.lure})
		row.LayoutOrder = index
		local pearlColor = PEARLS[(index - 1) % #PEARLS + 1]
		Theme.glow(row, "PearlGlow", 52, UDim2.new(0, 36, 0.5, 0), pearlColor, {rings = 3, strength = 0.82, inner = 0.5})
		local pearl = Theme.circle(row, "Pearl", 26, UDim2.new(0, 36, 0.5, 0), pearlColor:Lerp(Color3.new(1, 1, 1), 0.3), 0)
		Theme.circle(pearl, "Glint", 8, UDim2.fromScale(0.34, 0.32), Color3.new(1, 1, 1), 0.2)
		Theme.label(row, "ProductName", product.name, 18, {bold = true, frameSize = UDim2.new(0.5, -64, 1, 0)}).Position = UDim2.new(0, 64, 0, 0)
		Theme.label(row, "Price", "🪙 " .. Theme.formatNumber(product.price), 18, {display = true, color = C.lureCore,
			frameSize = UDim2.new(0.25, 0, 1, 0)}).Position = UDim2.new(0.5, 0, 0, 0)
		local buy = Theme.button(row, "BuyButton", "購入", function() handlers.buy(product.id) end,
			{primary = true, size = UDim2.new(0, 104, 0, 48)})
		buy.Position = UDim2.new(1, -112, 0.5, -24)
	end

	-- Settings: toggles with a photophore lamp (lit green = ON).
	local settings = state.settings or {}
	local settingsList = scrollList(pages.Settings, "SettingsList", HUE.Settings)
	for index, id in ipairs({"music", "sfx"}) do
		local label = id == "music" and "音楽" or "効果音"
		local on = settings[id] ~= false
		local toggle
		toggle = Theme.button(settingsList, "Toggle_" .. (id == "music" and "Music" or "SFX"), label .. ": " .. (on and "ON" or "OFF"), function()
			on = not on
			toggle.Text = label .. ": " .. (on and "ON" or "OFF")
			Theme.setLit(toggle, on)
			handlers.toggle(id, on)
		end, {size = UDim2.new(1, -10, 0, 56), hue = HUE.Settings, lamp = true, lit = on, order = index})
	end

	refresh(gui)
	DeepSea.animate(gui)
	return gui
end

function MainMenu.open(gui, pageId)
	for _, name in ipairs(PAGE_NAMES) do
		local frame = gui:FindFirstChild(name)
		if frame then
			local show = name == pageId .. "Page"
			if show and not frame.Visible then
				Theme.popIn(frame)
			end
			frame.Visible = show
		end
	end
	refresh(gui)
end

return MainMenu
