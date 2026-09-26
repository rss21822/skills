-- Main menu: top bar, PLAY, nav bar and the Shop / Inventory / Quests / Settings pages.
-- Other systems find these instances by name (see tests/test_main_menu.luau): names, hierarchy
-- and callbacks here are the contract and did not change in the NIGHT WARD rebrand.
-- The look (exit-sign CTA, clipboard charts, room-plate dock, corridor backdrop) is layered on by
-- NightWardArt; each of its steps runs in pcall, so if it fails the plain themed menu still works.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))
local C = Theme.colors

local okArt, Art = pcall(function() return require(script.Parent:WaitForChild("NightWardArt", 5)) end)
if not okArt or type(Art) ~= "table" then Art = nil end

local MainMenu = {}

-- id = page contract; label = button text; room / tag / chart = the ward's door plate and chart header.
local NAV = {
	{id = "Shop", label = "ショップ", room = "B1", tag = "KIOSK", chart = "WARD B1 · KIOSK"},
	{id = "Inventory", label = "持ち物", room = "107", tag = "LOCKER", chart = "WARD 1F · LOCKER 107"},
	{id = "Quests", label = "クエスト", room = "203", tag = "NURSE", chart = "WARD 2F · NURSE STATION"},
	{id = "Settings", label = "設定", room = "B2", tag = "CONTROL", chart = "WARD B2 · CONTROL ROOM"},
}

local function formatCoins(value)
	local digits = tostring(math.floor(tonumber(value) or 0))
	local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	return (string.gsub(grouped, "^(%-?),", "%1"))
end
MainMenu.formatCoins = formatCoins

local function page(gui, name, title)
	local frame = Theme.panel(gui, name, UDim2.new(0.6, 0, 0.62, 0), UDim2.new(0.5, 0, 0.5, 22))
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.ZIndex = 20
	frame.Visible = false
	local heading = Theme.label(frame, "Title", title, 26, {bold = true, color = C.ink, frameSize = UDim2.new(1, -176, 0, 44)})
	heading.Position = UDim2.new(0, 36, 0, 58)
	heading.ZIndex = 10
	local close = Theme.button(frame, "CloseButton", "× 閉じる", function() frame.Visible = false end,
		{size = UDim2.new(0, 108, 0, 48), face = C.panel, textColor = C.text, edge = C.ink, textSize = 18, role = "strong"})
	close.Position = UDim2.new(1, -132, 0, 56)
	close.ZIndex = 10
	return frame
end

-- handlers: {play = fn(), buy = fn(productId), toggle = fn(settingId, on), navigate = fn(pageId)?}
-- state: {coins = number, products = {{id, name, price}}, settings = {music = bool, sfx = bool}}
function MainMenu.build(playerGui, handlers, state)
	local gui = Theme.create("ScreenGui", {Name = "MainMenu", ResetOnSpawn = false, IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = playerGui})
	local background = Theme.create("Frame", {Name = "Background", Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.background, BackgroundTransparency = 0.08, BorderSizePixel = 0, Parent = gui})

	-- Ward signboard: game name and the coin counter (moved below Roblox's top bar by the layout).
	local top = Theme.panel(background, "TopBar", UDim2.new(1, -32, 0, 64), UDim2.new(0, 16, 0, 66))
	top.ZIndex = 10
	local title = Theme.label(top, "Title", "NIGHT WARD", 32, {bold = true, role = "display", frameSize = UDim2.new(0.55, 0, 0, 34)})
	title.Position = UDim2.new(0, 22, 0, 4)
	local coins = Theme.label(top, "CoinLabel", formatCoins(state.coins), 24,
		{bold = true, role = "mono", color = C.amber, align = Enum.TextXAlignment.Right, frameSize = UDim2.new(0, 176, 0, 42)})
	coins.AnchorPoint = Vector2.new(1, 0.5)
	coins.Position = UDim2.new(1, -14, 0.5, 0)

	-- The call to action is the ward's emergency exit sign.
	local play = Theme.button(background, "PlayButton", "脱出する", function() handlers.play() end,
		{primary = true, size = UDim2.new(0, 340, 0, 100), textSize = 34, textColor = C.text, role = "strong",
		corner = 4, edge = C.steel, edgeThickness = 4})
	play.AnchorPoint = Vector2.new(0.5, 0.5)
	play.Position = UDim2.new(0.5, 0, 0.57, 0)
	play.ZIndex = 10

	local nav = Theme.create("Frame", {Name = "NavBar", Size = UDim2.new(0, 4 * 134 + 3 * 14, 0, 64), AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24), BackgroundTransparency = 1, ZIndex = 10, Parent = background})
	Theme.create("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 14),
		HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder, Parent = nav})

	local pages = {}
	pages.Shop = page(gui, "ShopPage", "ショップ")
	pages.Settings = page(gui, "SettingsPage", "設定")
	pages.Inventory = page(gui, "InventoryPage", "持ち物")
	pages.Quests = page(gui, "QuestsPage", "クエスト")
	for id, message in pairs({Inventory = "まだアイテムがありません", Quests = "今日のクエストは準備中です"}) do
		local empty = Theme.label(pages[id], "Empty", message, 18, {bold = true, color = C.muted, frameSize = UDim2.new(1, -72, 0, 28)})
		empty.Position = UDim2.new(0, 36, 0, 134)
		empty.ZIndex = 10
	end

	local navButtons = {}
	for index, item in ipairs(NAV) do
		navButtons[item.id] = Theme.button(nav, "Nav_" .. item.id, item.label, function()
			MainMenu.open(gui, item.id)
			if handlers.navigate then handlers.navigate(item.id) end
		end, {size = UDim2.new(0, 134, 0, 64), order = index, face = C.panelLight, textColor = C.ink, textSize = 20, role = "strong"})
	end

	-- Shop: one row per product (a line on the kiosk chart).
	local list = Theme.create("ScrollingFrame", {Name = "ProductList", Size = UDim2.new(1, -64, 1, -132), Position = UDim2.new(0, 34, 0, 114),
		BackgroundTransparency = 1, BorderSizePixel = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6, ScrollBarImageColor3 = C.board, ZIndex = 10, Parent = pages.Shop})
	Theme.create("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list})
	local rows = {}
	for index, product in ipairs(state.products or {}) do
		local row = Theme.panel(list, "Product_" .. product.id, UDim2.new(1, -10, 0, 64))
		row.LayoutOrder = index
		Theme.label(row, "ProductName", product.name, 19, {bold = true, color = C.ink, frameSize = UDim2.new(0.5, -34, 1, 0)}).Position = UDim2.new(0, 34, 0, 0)
		Theme.label(row, "Price", formatCoins(product.price), 18, {bold = true, role = "mono", color = C.ink,
			frameSize = UDim2.new(0.22, -30, 1, 0)}).Position = UDim2.new(0.5, 34, 0, 0)
		local buy = Theme.button(row, "BuyButton", "購入", function() handlers.buy(product.id) end,
			{size = UDim2.new(0, 104, 0, 48), face = C.paperLight, textColor = C.stamp, edge = C.stamp, edgeThickness = 3,
			pressFace = C.stamp, pressText = C.paperLight, textSize = 20, role = "strong"})
		buy.Position = UDim2.new(1, -112, 0.5, -24)
		table.insert(rows, row)
	end

	-- Settings: on/off toggles (wall switches in the control room).
	local settings = state.settings or {}
	local toggles = {}
	for index, id in ipairs({"music", "sfx"}) do
		local label = id == "music" and "音楽" or "効果音"
		local on = settings[id] ~= false
		local toggle
		toggle = Theme.button(pages.Settings, "Toggle_" .. (id == "music" and "Music" or "SFX"), label .. ": " .. (on and "ON" or "OFF"), function()
			on = not on
			toggle.Text = label .. ": " .. (on and "ON" or "OFF")
			handlers.toggle(id, on)
		end, {size = UDim2.new(1, -72, 0, 56), face = C.panelLight, textColor = C.ink, textSize = 20, role = "strong"})
		toggle.Position = UDim2.new(0, 36, 0, 116 + (index - 1) * 70)
		toggle.ZIndex = 10
		table.insert(toggles, toggle)
	end

	if Art and Art.install then
		local ok, err = pcall(Art.install, {gui = gui, background = background, top = top, title = title, coins = coins,
			play = play, nav = nav, navButtons = navButtons, navInfo = NAV, pages = pages, rows = rows, toggles = toggles})
		if not ok then warn("NightWardArt failed: " .. tostring(err)) end
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
