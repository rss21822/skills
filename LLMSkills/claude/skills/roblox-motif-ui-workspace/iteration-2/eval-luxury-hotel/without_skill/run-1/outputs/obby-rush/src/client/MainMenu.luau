-- Main menu: top bar, PLAY, nav bar and the Shop / Inventory / Quests / Settings pages.
-- Other systems find these instances by name (see tests/test_main_menu.luau).
-- Look: the lobby of a grand hotel (see UITheme / LobbyBackdrop). The top bar is the hotel masthead, the
-- nav bar is the lobby directory (bilingual placards), pages are gold-framed menu cards, PLAY is "check in".
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))
local LobbyBackdrop = require(script.Parent:WaitForChild("LobbyBackdrop"))

local MainMenu = {}

local Align = Enum.TextXAlignment

-- caption: the English line of the bilingual placard (hotel names for each room of the menu).
local NAV = {
	{id = "Shop", label = "ショップ", caption = "Boutique"},
	{id = "Inventory", label = "持ち物", caption = "Cloakroom"},
	{id = "Quests", label = "クエスト", caption = "Concierge"},
	{id = "Settings", label = "設定", caption = "Preferences"},
}
local PAGE_IDS = {"Shop", "Settings", "Inventory", "Quests"}
local PRICE_LEFT = 186 -- price column starts this far from a product row's right edge (buy button: last 108 px)
local COMPACT_HEIGHT = 560 -- below this viewport height (phones in landscape) cards use the compact layout

local function page(gui, name, title, caption, seed)
	local frame = Theme.panel(gui, name, UDim2.new(0.6, 0, 0.62, 0), UDim2.new(0.2, 0, 0.16, 0), {seed = seed, transparency = 0})
	frame.Visible = false
	frame.ZIndex = 5
	Theme.inlay(frame, 8)
	local eyebrow = Theme.caption(frame, "Caption", caption, 11, {frameSize = UDim2.new(1, -240, 0, 14)})
	eyebrow.AnchorPoint = Vector2.new(0.5, 0)
	eyebrow.Position = UDim2.new(0.5, 0, 0, 24)
	local heading = Theme.label(frame, "Title", title, 24, {bold = true, align = Align.Center, frameSize = UDim2.new(1, -240, 0, 34)})
	heading.AnchorPoint = Vector2.new(0.5, 0)
	heading.Position = UDim2.new(0.5, 0, 0, 40)
	Theme.rule(frame, "TitleRule", UDim.new(1, -96), UDim2.new(0.5, 0, 0, 86))
	local close = Theme.button(frame, "CloseButton", "閉じる", function() MainMenu.open(gui, nil) end,
		{outline = true, size = UDim2.new(0, 96, 0, 48), textSize = 16})
	close.Position = UDim2.new(1, -118, 0, 22)
	return frame
end

-- Centred ornament + quiet line for pages with nothing to list yet.
local function emptyState(pageFrame, text)
	local ornament = Theme.rule(pageFrame, "EmptyOrnament", UDim.new(0, 120), UDim2.new(0.5, 0, 0.5, 18), {transparency = 0.5})
	ornament.ZIndex = 2
	local label = Theme.label(pageFrame, "Empty", text, 18, {color = Theme.colors.subtext, align = Align.Center,
		frameSize = UDim2.new(1, -96, 0, 28)})
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.new(0.5, 0, 0.5, 50)
	return label
end

local function stateText(label, on)
	local color = on and "#C9A55E" or "#9E9689"
	return string.format('%s　<font color="%s">%s</font>', label, color, on and "ON" or "OFF")
end

-- handlers: {play = fn(), buy = fn(productId), toggle = fn(settingId, on), navigate = fn(pageId)?}
-- state: {coins = number, products = {{id, name, price}}, settings = {music = bool, sfx = bool}}
function MainMenu.build(playerGui, handlers, state)
	local gui = Theme.create("ScreenGui", {Name = "MainMenu", ResetOnSpawn = false, IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = playerGui})
	local background = Theme.create("Frame", {Name = "Background", Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.14, BorderSizePixel = 0,
		ClipsDescendants = true, Parent = gui})
	-- Warm at the ceiling (chandelier), onyx at the floor.
	Theme.gradient(background, {{0, Color3.fromRGB(26, 21, 14)}, {0.42, Color3.fromRGB(11, 10, 9)},
		{1, Color3.fromRGB(5, 5, 6)}}, 90)
	LobbyBackdrop.build(background)

	-- Masthead: centred wordmark between gold rules; the corners stay clear for Roblox's own buttons.
	local top = Theme.create("Frame", {Name = "TopBar", Size = UDim2.new(1, -32, 0, 64), Position = UDim2.new(0, 16, 0, 16),
		BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 3, Parent = background})
	local title = Theme.label(top, "Title", Theme.track("Obby Rush"), 30, {font = Theme.fontDisplay,
		color = Color3.new(1, 1, 1), align = Align.Center, frameSize = UDim2.new(0, 300, 0, 36)})
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.new(0.5, 0, 0, 2)
	Theme.goldLeaf(title, 90) -- white text x gold gradient = foil-stamped wordmark
	local tagline = Theme.caption(top, "Tagline", "The Grand Hotel", 11, {color = Theme.colors.subtext,
		frameSize = UDim2.new(0, 260, 0, 14)})
	tagline.AnchorPoint = Vector2.new(0.5, 0)
	tagline.Position = UDim2.new(0.5, 0, 0, 41)
	for side, sign in ipairs({-1, 1}) do
		Theme.hairline(top, side == 1 and "RuleLeft" or "RuleRight", UDim.new(0, 70), UDim2.new(0.5, sign * 195, 0, 21),
			{transparency = 0.3, fadeCurve = sign < 0 and {{0, 1}, {1, 0}} or {{0, 0}, {1, 1}}})
		Theme.diamond(top, side == 1 and "PipLeft" or "PipRight", 4, UDim2.new(0.5, sign * 157, 0, 21))
	end
	Theme.rule(top, "Rule", UDim.new(1, 0), UDim2.new(0.5, 0, 1, 0), {transparency = 0.45})

	-- Purse: coin mark + figure, flush right.
	local purse = Theme.create("Frame", {Name = "Purse", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, -2),
		Size = UDim2.new(0, 200, 0, 40), BackgroundTransparency = 1, BorderSizePixel = 0, Parent = top})
	local coins = Theme.label(purse, "CoinLabel", Theme.formatNumber(state.coins or 0), 22, {font = Theme.fontDisplay,
		align = Align.Right, frameSize = UDim2.new(1, 0, 1, 0)})
	local coinIcon = Theme.coin(purse, "CoinIcon", 18, UDim2.new(1, 0, 0.5, 0))
	local function placeCoin()
		coinIcon.Position = UDim2.new(1, -math.ceil(Theme.textWidth(coins.Text, 22) + 10), 0.5, 0)
	end
	placeCoin()
	-- Other scripts update the balance by writing CoinLabel.Text; keep it as a plain grouped figure
	-- (drops a legacy "🪙 " prefix) and keep the coin mark beside it.
	coins:GetPropertyChangedSignal("Text"):Connect(function()
		local raw = string.match(coins.Text, "%-?%d[%d,]*")
		local clean = raw and Theme.formatNumber((string.gsub(raw, ",", ""))) or coins.Text
		if clean ~= coins.Text then
			coins.Text = clean
			return
		end
		placeCoin()
	end)

	local play = Theme.button(background, "PlayButton", "プレイ", function() handlers.play() end,
		{primary = true, size = UDim2.new(0, 280, 0, 72), textSize = 26, caption = "Check In", captionPad = 20})
	play.AnchorPoint = Vector2.new(0.5, 0.5)
	play.Position = UDim2.new(0.5, 0, 0.58, 0)
	play.ZIndex = 4

	-- Lobby directory.
	local nav = Theme.create("Frame", {Name = "NavBar", Size = UDim2.new(0, 560, 0, 64), AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24), BackgroundTransparency = 1, ZIndex = 4, Parent = background})
	Theme.create("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12),
		HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = nav})

	local pages = {}
	pages.Shop = page(gui, "ShopPage", "ショップ", "Boutique", 0)
	pages.Settings = page(gui, "SettingsPage", "設定", "Preferences", 1)
	pages.Inventory = page(gui, "InventoryPage", "持ち物", "Cloakroom", 2)
	pages.Quests = page(gui, "QuestsPage", "クエスト", "Concierge", 1)
	emptyState(pages.Inventory, "まだアイテムがありません")
	emptyState(pages.Quests, "今日のクエストは準備中です")

	for index, item in ipairs(NAV) do
		Theme.button(nav, "Nav_" .. item.id, item.label, function()
			MainMenu.open(gui, item.id)
			if handlers.navigate then handlers.navigate(item.id) end
		end, {size = UDim2.new(0, 131, 0, 64), order = index, textSize = 16, caption = item.caption, captionPad = 20,
			selectable = true})
	end

	-- Shop: a menu card. Name, dotted leader, price in gold, then a quiet gold "購入".
	local list = Theme.create("ScrollingFrame", {Name = "ProductList", Size = UDim2.new(1, -80, 1, -120),
		Position = UDim2.new(0, 40, 0, 100), BackgroundTransparency = 1, BorderSizePixel = 0, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 2,
		ScrollBarImageColor3 = Theme.colors.accent, ScrollBarImageTransparency = 0.3, Parent = pages.Shop})
	Theme.create("UIListLayout", {Padding = UDim.new(0, 0), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list})
	for index, product in ipairs(state.products or {}) do
		local row = Theme.create("Frame", {Name = "Product_" .. product.id, Size = UDim2.new(1, -10, 0, 68),
			BackgroundTransparency = 1, BorderSizePixel = 0, LayoutOrder = index, Parent = list})
		Theme.hairline(row, "Rule", UDim.new(1, 0), UDim2.new(0.5, 0, 1, -1), {transparency = 0.72,
			fadeCurve = {{0, 0.6}, {0.1, 0}, {0.9, 0}, {1, 0.6}}})
		Theme.label(row, "ProductName", product.name, 18, {bold = true, frameSize = UDim2.new(0.5, 0, 1, 0)}).Position = UDim2.new(0, 4, 0, 0)
		-- Price column: coin mark at a fixed column, figure after it (same gap on every row).
		local price = Theme.label(row, "Price", Theme.formatNumber(product.price), 20, {font = Theme.fontDisplay,
			color = Theme.colors.accent, frameSize = UDim2.new(0, 60, 1, 0)})
		price.Position = UDim2.new(1, -PRICE_LEFT, 0, 0)
		price.TextWrapped = false
		Theme.coin(row, "CoinIcon", 14, UDim2.new(1, -(PRICE_LEFT + 7), 0.5, 0))
		-- Dotted leader from just after the name to just before the coin, clipped to that gap.
		local leaderLeft = 4 + math.ceil(Theme.textWidth(product.name, 18)) + 16
		local leader = Theme.create("Frame", {Name = "Leader", Position = UDim2.new(0, leaderLeft, 0, 0),
			Size = UDim2.new(1, -(leaderLeft + PRICE_LEFT + 7 + 14 + 12), 1, 0), BackgroundTransparency = 1,
			BorderSizePixel = 0, ClipsDescendants = true, Active = false, Parent = row})
		Theme.label(leader, "Dots", string.rep(" .", 120), 18, {font = Theme.fontDisplay, color = Theme.colors.accent,
			transparency = 0.45, align = Align.Right, frameSize = UDim2.new(0, 2400, 1, 0)}).Position = UDim2.new(1, -2400, 0, 0)
		local buy = Theme.button(row, "BuyButton", "購入", function() handlers.buy(product.id) end,
			{outline = true, size = UDim2.new(0, 104, 0, 48), textSize = 17})
		buy.Position = UDim2.new(1, -108, 0.5, -24)
	end

	-- Settings: bilingual rows with a brass-and-onyx switch.
	local settings = state.settings or {}
	for index, id in ipairs({"music", "sfx"}) do
		local label = id == "music" and "音楽" or "効果音"
		local on = settings[id] ~= false
		local toggle
		toggle = Theme.button(pages.Settings, "Toggle_" .. (id == "music" and "Music" or "SFX"), stateText(label, on), function()
			on = not on
			toggle.Text = stateText(label, on)
			Theme.switch(toggle, on)
			handlers.toggle(id, on)
		end, {size = UDim2.new(1, -80, 0, 64), align = Align.Left, rich = true, textSize = 18, padLeft = 20,
			caption = id == "music" and "Music" or "Sound Effects", captionAlign = Align.Left, captionPad = 20})
		toggle:SetAttribute("Row", index)
		Theme.switch(toggle, on, true)
	end

	MainMenu.layout(gui)
	local camera = workspace.CurrentCamera
	if camera and camera.GetPropertyChangedSignal then
		local connection
		connection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if gui.Parent == nil then connection:Disconnect() return end
			MainMenu.layout(gui)
		end)
	end
	return gui
end

-- Fits the menu cards to the viewport. Tall screens: the classic card (60% x 62%). Short screens
-- (phones in landscape): the card sits between the masthead and the directory with a one-line header,
-- so two product rows stay visible without covering the nav.
function MainMenu.layout(gui, viewportSize)
	local camera = workspace.CurrentCamera
	viewportSize = viewportSize or (camera and camera.ViewportSize)
	local compact = viewportSize ~= nil and viewportSize.Y > 1 and viewportSize.Y < COMPACT_HEIGHT
	local contentTop = compact and 70 or 100
	for _, id in ipairs(PAGE_IDS) do
		local frame = gui:FindFirstChild(id .. "Page")
		if frame then
			frame.AnchorPoint = compact and Vector2.new(0.5, 0) or Vector2.new(0, 0)
			frame.Position = compact and UDim2.new(0.5, 0, 0, 84) or UDim2.new(0.2, 0, 0.16, 0)
			frame.Size = compact and UDim2.new(0.64, 0, 1, -176) or UDim2.new(0.6, 0, 0.62, 0)
			local caption, heading = frame:FindFirstChild("Caption"), frame:FindFirstChild("Title")
			local rule, close = frame:FindFirstChild("TitleRule"), frame:FindFirstChild("CloseButton")
			if caption then caption.Visible = not compact end
			if heading then
				heading.Position = UDim2.new(0.5, 0, 0, compact and 12 or 40)
				heading.TextSize = compact and 20 or 24
			end
			if rule then rule.Position = UDim2.new(0.5, 0, 0, compact and 60 or 86) end
			if close then close.Position = UDim2.new(1, -118, 0, compact and 8 or 22) end
			for _, child in ipairs(frame:GetChildren()) do
				local row = child:GetAttribute("Row")
				if row then child.Position = UDim2.new(0, 40, 0, contentTop + 4 + (row - 1) * (compact and 72 or 78)) end
			end
		end
	end
	local list = gui:FindFirstChild("ProductList", true)
	if list then
		list.Position = UDim2.new(0, 40, 0, contentTop)
		list.Size = UDim2.new(1, -80, 1, -(contentTop + 20))
	end
end

-- Shows the page for pageId (nil closes every page) and marks its directory placard.
function MainMenu.open(gui, pageId)
	for _, id in ipairs(PAGE_IDS) do
		local frame = gui:FindFirstChild(id .. "Page")
		if frame then frame.Visible = (id == pageId) end
		local placard = gui:FindFirstChild("Nav_" .. id, true)
		if placard then Theme.setSelected(placard, id == pageId) end
	end
end

return MainMenu
