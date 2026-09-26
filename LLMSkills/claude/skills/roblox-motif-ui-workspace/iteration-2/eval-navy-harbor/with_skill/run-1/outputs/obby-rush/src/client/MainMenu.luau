-- Main menu: top bar, PLAY, nav bar and the Shop / Inventory / Quests / Settings pages.
-- Other systems find these instances by name (see tests/test_main_menu.luau).
--
-- Look: the "night harbour navy" skin (ReplicatedStorage.Shared.Harbor) restyles UITheme at runtime and
-- HarborMenu dresses this screen (portholes, signal flags, rope, sailor-collar pages). Both are
-- optional and guarded: if either is missing or fails, this module still builds the same menu with
-- the same names, sizes and callbacks.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("UITheme"))

local function optional(find)
	local ok, result = pcall(function()
		local module = find()
		return module and require(module) or nil
	end)
	return ok and result or nil
end
local HarborSkin = optional(function()
	local folder = Shared:WaitForChild("Harbor", 5)
	return folder and folder:WaitForChild("HarborSkin", 5)
end)
local HarborMenu = optional(function()
	return script.Parent:WaitForChild("HarborMenu", 5)
end)

local MainMenu = {}

local NAV = {
	{id = "Shop", label = "ショップ"},
	{id = "Inventory", label = "持ち物"},
	{id = "Quests", label = "クエスト"},
	{id = "Settings", label = "設定"},
}

-- 1250 -> "1,250"
local function commas(value)
	local text = tostring(math.floor(tonumber(value) or 0))
	local sign, digits = string.match(text, "^(-?)(%d+)$")
	if not digits then return text end
	local out = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	if string.sub(out, 1, 1) == "," then out = string.sub(out, 2) end
	return sign .. out
end
MainMenu.formatCoins = commas

local function page(gui, name, title)
	local frame = Theme.panel(gui, name, UDim2.new(0.6, 0, 0.62, 0), UDim2.new(0.2, 0, 0.16, 0))
	frame.Visible = false
	local heading = Theme.label(frame, "Title", title, 24, {bold = true, frameSize = UDim2.new(1, -120, 0, 40)})
	heading.Position = UDim2.new(0, 16, 0, 10)
	local close = Theme.button(frame, "CloseButton", "閉じる", function() frame.Visible = false end, {size = UDim2.new(0, 96, 0, 48)})
	close.Position = UDim2.new(1, -108, 0, 8)
	return frame, heading, close
end

-- Builds the menu structure (the name contract). Returns the ScreenGui and references for dressing.
local function buildBase(playerGui, handlers, state)
	local refs = {navButtons = {}, pages = {}, pageTitles = {}, closeButtons = {}, rows = {}, toggles = {}, empties = {}}
	local gui = Theme.create("ScreenGui", {Name = "MainMenu", ResetOnSpawn = false, IgnoreGuiInset = true, Parent = playerGui})
	local background = Theme.create("Frame", {Name = "Background", Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.colors.background, BackgroundTransparency = 0.25, BorderSizePixel = 0, Parent = gui})
	refs.gui, refs.background = gui, background

	local top = Theme.panel(background, "TopBar", UDim2.new(1, -32, 0, 64), UDim2.new(0, 16, 0, 16))
	local title = Theme.label(top, "Title", "OBBY RUSH", 28, {bold = true, frameSize = UDim2.new(0.5, 0, 1, 0)})
	title.Position = UDim2.new(0, 16, 0, 0)
	-- 💰 (Unicode 6) instead of 🪙: Roblox's emoji font stops at Unicode 12 and draws 🪙 as a box.
	local coins = Theme.label(top, "CoinLabel", "💰 " .. commas(state.coins or 0), 20,
		{bold = true, align = Enum.TextXAlignment.Right, frameSize = UDim2.new(0.4, 0, 1, 0)})
	coins.Position = UDim2.new(0.6, -16, 0, 0)
	refs.top, refs.title, refs.coins = top, title, coins

	local play = Theme.button(background, "PlayButton", "プレイ", function() handlers.play() end,
		{primary = true, size = UDim2.new(0, 280, 0, 72), textSize = 30})
	play.AnchorPoint = Vector2.new(0.5, 0.5)
	play.Position = UDim2.new(0.5, 0, 0.55, 0)
	refs.play = play

	local nav = Theme.create("Frame", {Name = "NavBar", Size = UDim2.new(0, 560, 0, 64), AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24), BackgroundTransparency = 1, Parent = background})
	local navLayout = Theme.create("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12),
		HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = nav})
	refs.nav, refs.navLayout = nav, navLayout

	local pages = {}
	pages.Shop, refs.pageTitles.Shop, refs.closeButtons.Shop = page(gui, "ShopPage", "ショップ")
	pages.Settings, refs.pageTitles.Settings, refs.closeButtons.Settings = page(gui, "SettingsPage", "設定")
	pages.Inventory, refs.pageTitles.Inventory, refs.closeButtons.Inventory = page(gui, "InventoryPage", "持ち物")
	pages.Quests, refs.pageTitles.Quests, refs.closeButtons.Quests = page(gui, "QuestsPage", "クエスト")
	refs.pages = pages
	refs.empties.Inventory = Theme.label(pages.Inventory, "Empty", "まだアイテムがありません", 18, {color = Theme.colors.subtext})
	refs.empties.Inventory.Position = UDim2.new(0, 16, 0, 72)
	refs.empties.Quests = Theme.label(pages.Quests, "Empty", "今日のクエストは準備中です", 18, {color = Theme.colors.subtext})
	refs.empties.Quests.Position = UDim2.new(0, 16, 0, 72)

	for index, item in ipairs(NAV) do
		refs.navButtons[item.id] = Theme.button(nav, "Nav_" .. item.id, item.label, function()
			MainMenu.open(gui, item.id)
			if handlers.navigate then handlers.navigate(item.id) end
		end, {size = UDim2.new(0, 128, 0, 56), order = index})
	end

	-- Shop: one row per product.
	local list = Theme.create("ScrollingFrame", {Name = "ProductList", Size = UDim2.new(1, -32, 1, -80), Position = UDim2.new(0, 16, 0, 64),
		BackgroundTransparency = 1, BorderSizePixel = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6, Parent = pages.Shop})
	refs.list = list
	refs.listLayout = Theme.create("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list})
	for index, product in ipairs(state.products or {}) do
		local row = Theme.panel(list, "Product_" .. product.id, UDim2.new(1, -8, 0, 64))
		row.LayoutOrder = index
		local name = Theme.label(row, "ProductName", product.name, 18, {bold = true, frameSize = UDim2.new(0.5, 0, 1, 0)})
		name.Position = UDim2.new(0, 12, 0, 0)
		local price = Theme.label(row, "Price", "💰 " .. commas(product.price), 18, {frameSize = UDim2.new(0.2, 0, 1, 0)})
		price.Position = UDim2.new(0.5, 0, 0, 0)
		local buy = Theme.button(row, "BuyButton", "購入", function() handlers.buy(product.id) end,
			{primary = true, size = UDim2.new(0, 104, 0, 48)})
		buy.Position = UDim2.new(1, -112, 0.5, -24)
		table.insert(refs.rows, {row = row, name = name, price = price, buy = buy, product = product})
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
		table.insert(refs.toggles, {button = toggle, id = id, index = index})
	end

	return gui, refs
end

-- handlers: {play = fn(), buy = fn(productId), toggle = fn(settingId, on), navigate = fn(pageId)?}
-- state: {coins = number, products = {{id, name, price}}, settings = {music = bool, sfx = bool}}
function MainMenu.build(playerGui, handlers, state)
	local skinned = false
	if HarborSkin then
		local ok, applied = pcall(HarborSkin.apply, Theme)
		skinned = ok and applied == true
	end
	local gui, refs = buildBase(playerGui, handlers, state)
	if skinned and HarborMenu then
		local ok, err = pcall(HarborMenu.dress, refs, HarborSkin, state)
		if not ok then
			-- Never lose the menu to a presentation bug: drop the half-dressed copy, rebuild it plain.
			warn("[MainMenu] harbour dressing failed, using the plain menu: " .. tostring(err))
			gui:Destroy()
			gui = buildBase(playerGui, handlers, state)
		end
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
