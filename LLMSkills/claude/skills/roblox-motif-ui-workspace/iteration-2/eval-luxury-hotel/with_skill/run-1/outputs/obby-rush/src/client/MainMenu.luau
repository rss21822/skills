-- Main menu: top bar, PLAY, nav bar and the Shop / Inventory / Quests / Settings pages.
-- Other systems find these instances by name (see tests/test_main_menu.luau).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))

local MainMenu = {}

-- Coin amounts: the stage skin supplies its own format (and draws the coin); otherwise the emoji.
local function coinText(amount)
	if type(Theme.formatCoins) == "function" then
		local ok, text = pcall(Theme.formatCoins, amount)
		if ok and type(text) == "string" then return text end
	end
	return "🪙 " .. tostring(amount)
end

local NAV = {
	{id = "Shop", label = "ショップ"},
	{id = "Inventory", label = "持ち物"},
	{id = "Quests", label = "クエスト"},
	{id = "Settings", label = "設定"},
}

local function page(gui, name, title)
	local frame = Theme.panel(gui, name, UDim2.new(0.6, 0, 0.62, 0), UDim2.new(0.2, 0, 0.16, 0))
	frame.Visible = false
	Theme.label(frame, "Title", title, 24, {bold = true, frameSize = UDim2.new(1, -120, 0, 40)}).Position = UDim2.new(0, 16, 0, 10)
	local close = Theme.button(frame, "CloseButton", "閉じる", function() frame.Visible = false end, {size = UDim2.new(0, 96, 0, 48)})
	close.Position = UDim2.new(1, -108, 0, 8)
	return frame
end

-- handlers: {play = fn(), buy = fn(productId), toggle = fn(settingId, on), navigate = fn(pageId)?}
-- state: {coins = number, products = {{id, name, price}}, settings = {music = bool, sfx = bool}}
function MainMenu.build(playerGui, handlers, state)
	local gui = Theme.create("ScreenGui", {Name = "MainMenu", ResetOnSpawn = false, IgnoreGuiInset = true, Parent = playerGui})
	local background = Theme.create("Frame", {Name = "Background", Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.colors.background, BackgroundTransparency = 0.25, BorderSizePixel = 0, Parent = gui})

	local top = Theme.panel(background, "TopBar", UDim2.new(1, -32, 0, 64), UDim2.new(0, 16, 0, 16))
	Theme.label(top, "Title", "OBBY RUSH", 28, {bold = true, frameSize = UDim2.new(0.5, 0, 1, 0)}).Position = UDim2.new(0, 16, 0, 0)
	local coins = Theme.label(top, "CoinLabel", coinText(state.coins or 0), 20,
		{bold = true, align = Enum.TextXAlignment.Right, frameSize = UDim2.new(0.4, 0, 1, 0)})
	coins.Position = UDim2.new(0.6, -16, 0, 0)

	local play = Theme.button(background, "PlayButton", "プレイ", function() handlers.play() end,
		{primary = true, size = UDim2.new(0, 280, 0, 72), textSize = 30})
	play.AnchorPoint = Vector2.new(0.5, 0.5)
	play.Position = UDim2.new(0.5, 0, 0.55, 0)

	local nav = Theme.create("Frame", {Name = "NavBar", Size = UDim2.new(0, 560, 0, 64), AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24), BackgroundTransparency = 1, Parent = background})
	Theme.create("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12),
		HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = nav})

	local pages = {}
	pages.Shop = page(gui, "ShopPage", "ショップ")
	pages.Settings = page(gui, "SettingsPage", "設定")
	pages.Inventory = page(gui, "InventoryPage", "持ち物")
	pages.Quests = page(gui, "QuestsPage", "クエスト")
	Theme.label(pages.Inventory, "Empty", "まだアイテムがありません", 18, {color = Theme.colors.subtext}).Position = UDim2.new(0, 16, 0, 72)
	Theme.label(pages.Quests, "Empty", "今日のクエストは準備中です", 18, {color = Theme.colors.subtext}).Position = UDim2.new(0, 16, 0, 72)

	for index, item in ipairs(NAV) do
		Theme.button(nav, "Nav_" .. item.id, item.label, function()
			MainMenu.open(gui, item.id)
			if handlers.navigate then handlers.navigate(item.id) end
		end, {size = UDim2.new(0, 128, 0, 56), order = index})
	end

	-- Shop: one row per product.
	local list = Theme.create("ScrollingFrame", {Name = "ProductList", Size = UDim2.new(1, -32, 1, -80), Position = UDim2.new(0, 16, 0, 64),
		BackgroundTransparency = 1, BorderSizePixel = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6, Parent = pages.Shop})
	Theme.create("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list})
	for index, product in ipairs(state.products or {}) do
		local row = Theme.panel(list, "Product_" .. product.id, UDim2.new(1, -8, 0, 64))
		row.LayoutOrder = index
		Theme.label(row, "ProductName", product.name, 18, {bold = true, frameSize = UDim2.new(0.5, 0, 1, 0)}).Position = UDim2.new(0, 12, 0, 0)
		Theme.label(row, "Price", coinText(product.price), 18, {frameSize = UDim2.new(0.2, 0, 1, 0)}).Position = UDim2.new(0.5, 0, 0, 0)
		local buy = Theme.button(row, "BuyButton", "購入", function() handlers.buy(product.id) end,
			{primary = true, size = UDim2.new(0, 104, 0, 48)})
		buy.Position = UDim2.new(1, -112, 0.5, -24)
	end

	-- Settings: on/off toggles.
	local settings = state.settings or {}
	for index, id in ipairs({"music", "sfx"}) do
		local label = id == "music" and "音楽" or "効果音"
		local on = settings[id] ~= false
		local toggle
		toggle = Theme.button(pages.Settings, "Toggle_" .. (id == "music" and "Music" or "SFX"), label .. ": " .. (on and "ON" or "OFF"), function()
			on = not on
			toggle.Text = label .. ": " .. (on and "ON" or "OFF")
			handlers.toggle(id, on)
		end, {size = UDim2.new(1, -32, 0, 56)})
		toggle.Position = UDim2.new(0, 16, 0, 64 + (index - 1) * 68)
	end

	-- Stage skin (Grand Hotel lobby): decorative children and presentation only; everything named
	-- above keeps its name, parent and callback.
	if type(Theme.skin) == "table" and type(Theme.skin.decorateMainMenu) == "function" then
		pcall(Theme.skin.decorateMainMenu, gui)
	end

	return gui
end

function MainMenu.open(gui, pageId)
	for _, name in ipairs({"ShopPage", "SettingsPage", "InventoryPage", "QuestsPage"}) do
		local frame = gui:FindFirstChild(name)
		if frame then frame.Visible = (name == pageId .. "Page") end
	end
end

return MainMenu
