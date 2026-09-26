-- Main menu: top bar, PLAY, nav bar and the Shop / Inventory / Quests / Settings pages.
-- Look: "Retro Toy Box" (see UITheme / ToyDecor and DESIGN.md).
--
-- Other systems find these instances by name (see tests/test_main_menu.luau). The reskin keeps every
-- named instance, its class and its parent exactly where the previous menu had it:
--   MainMenu.Background.TopBar.{Title, CoinLabel}      MainMenu.Background.PlayButton
--   MainMenu.Background.NavBar.Nav_<Shop|Inventory|Quests|Settings>
--   MainMenu.<Shop|Settings|Inventory|Quests>Page.{Title, CloseButton}
--   MainMenu.ShopPage.ProductList.Product_<id>.{ProductName, Price, BuyButton}
--   MainMenu.SettingsPage.{Toggle_Music, Toggle_SFX}   MainMenu.<Inventory|Quests>Page.Empty
-- Everything new (awning, confetti, toys, windows, scrim) is extra decoration beside those instances.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("UITheme"))
local ToyDecor = require(Shared:WaitForChild("ToyDecor"))

local create = Theme.create
local P = Theme.palette

local MainMenu = {}

local AWNING_HEIGHT = 96
local NAV_WIDTH = 612

-- Two sizes of the home screen. "compact" kicks in on short screens (phones in landscape, < 450 px
-- tall) so the robot + PLAY stack still fits between the awning and the nav tray.
local LAYOUTS = {
	regular = {play = Vector2.new(340, 112), playText = 46, robot = 0.2, nav = 88, navButton = 66},
	compact = {play = Vector2.new(280, 84), playText = 34, robot = 0.15, nav = 80, navButton = 60},
}
local ROBOT_PEEK = 0.86 -- the robot's AnchorPoint.Y: the part above this line pokes out of the toy box

-- Each tab is a toy: its colour is used for the nav button bezel and for its page frame.
local NAV = {
	{id = "Shop", label = "ショップ", color = P.coral, icon = "coin"},
	{id = "Inventory", label = "持ち物", color = P.teal, icon = "ring"},
	{id = "Quests", label = "クエスト", color = P.mustard, icon = "star"},
	{id = "Settings", label = "設定", color = P.sky, icon = "bot"},
}
local PAGE_IDS = {"Shop", "Settings", "Inventory", "Quests"}

-- Shop rows cycle through these (coral is kept for the BUY buttons).
local ROW_COLORS = {P.teal, P.mustard, P.sky, P.mint}
local PRODUCT_ICONS = {speed_coil = "ring", rainbow_trail = "rainbow", double_jump = "twostars"}
local FALLBACK_ICONS = {"star", "ring", "coin", "bot"}

local function navInfo(id)
	for _, item in ipairs(NAV) do
		if item.id == id then return item end
	end
	return NAV[1]
end

-- Page = the coral-frame toy: coloured bezel, cream window ("Body"), brown title tag, round close
-- button. Returns the page frame; content is parented to the page itself (kept path-compatible) and
-- positioned over the body.
local function page(gui, name, title, id, withBody)
	local info = navInfo(id)
	local frame = create("Frame", {Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -52),
		Size = UDim2.new(0.76, 0, 1, -150), BackgroundColor3 = info.color, BorderSizePixel = 0, Visible = false, ZIndex = 10,
		Active = true, -- sink clicks so tapping the panel itself does not reach the scrim (which closes it)
		Parent = gui})
	Theme.corner(frame, 30)
	Theme.stroke(frame, 5)
	create("UISizeConstraint", {MaxSize = Vector2.new(920, 560), Parent = frame})
	create("UIScale", {Name = "PopScale", Scale = 1, Parent = frame})

	if withBody ~= false then
		local body = Theme.panel(frame, "Body", UDim2.new(1, -28, 1, -80), UDim2.new(0, 14, 0, 66), {radius = 20})
		body.ZIndex = 1
	end

	local titleTag = Theme.tag(frame, "Title", title, 26, 48, {icon = ToyDecor.icon(info.icon), iconSize = 30})
	titleTag.Position = UDim2.new(0, 16, 0, 9)
	titleTag.ZIndex = 3

	local close = Theme.button(frame, "CloseButton", "×", function() MainMenu.open(gui, nil) end,
		{solid = true, color = P.brown, textColor = P.creamLight, size = UDim2.new(0, 56, 0, 56), radius = 26, depth = 4,
			textSize = 34, font = Theme.fonts.display})
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 6)
	close.ZIndex = 3
	return frame
end

-- Empty state: a toy illustration in the body with a caption underneath (caption is a page child named "Empty").
local function emptyState(pageFrame, drawIllustration, text)
	drawIllustration(pageFrame:FindFirstChild("Body"))
	local label = Theme.label(pageFrame, "Empty", text, 22, {font = "label", color = Theme.colors.subtext,
		align = Enum.TextXAlignment.Center, frameSize = UDim2.new(1, -60, 0, 34)})
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.new(0.5, 0, 0.74, 7) -- 74% down the body window
	label.ZIndex = 2
	return label
end

-- Switch graphic inside a settings toggle (track + knob). Purely visual; the button's Text carries the state.
local function switch(button)
	local window = button:FindFirstChild("Window", true)
	local track = create("Frame", {Name = "Switch", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(72, 34), BackgroundColor3 = P.creamDark, BorderSizePixel = 0, Parent = window})
	Theme.corner(track, UDim.new(0.5, 0))
	Theme.stroke(track, Theme.outlineSmall)
	local knob = create("Frame", {Name = "Knob", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 17, 0.5, 0),
		Size = UDim2.fromOffset(26, 26), BackgroundColor3 = P.creamLight, BorderSizePixel = 0, Parent = track})
	Theme.corner(knob, UDim.new(0.5, 0))
	Theme.stroke(knob, Theme.outlineSmall)
	return function(on, animated)
		track.BackgroundColor3 = on and P.teal or P.creamDark
		local goal = UDim2.new(0, on and 55 or 17, 0.5, 0)
		if animated and not Theme.reducedMotion() then
			Theme.tween(knob, 0.18, {Position = goal}, Enum.EasingStyle.Back)
		else
			knob.Position = goal
		end
	end
end

local function popIn(frame)
	local scale = frame:FindFirstChild("PopScale")
	if not scale then return end
	local rest = frame:GetAttribute("RestScale") or 1 -- screen-size scale set by applyLayout
	if Theme.reducedMotion() then
		scale.Scale = rest
		return
	end
	scale.Scale = rest * 0.9
	Theme.tween(scale, 0.24, {Scale = rest}, Enum.EasingStyle.Back)
end

-- handlers: {play = fn(), buy = fn(productId), toggle = fn(settingId, on), navigate = fn(pageId)?}
-- state: {coins = number, products = {{id, name, price}}, settings = {music = bool, sfx = bool}}
function MainMenu.build(playerGui, handlers, state)
	local gui = create("ScreenGui", {Name = "MainMenu", ResetOnSpawn = false, IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = playerGui})
	local background = create("Frame", {Name = "Background", Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.colors.background, BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 1, Parent = gui})
	-- Everything was drawn for a 720 px tall screen; on bigger screens this scales the whole home screen up
	-- (Background is sized 1/s so that after the UIScale it still exactly covers the screen).
	local screenScale = create("UIScale", {Name = "ScreenScale", Scale = 1, Parent = background})

	-- Scenery from the mood board: confetti, the striped awning, the teal donut and the stars.
	ToyDecor.confetti(background, 1, AWNING_HEIGHT + 8)
	ToyDecor.awning(background, AWNING_HEIGHT, 2)
	local donut = ToyDecor.donut(background, "Donut", UDim2.fromScale(0.14, 0.47), 0.26, 3)
	local bigStar = ToyDecor.star(background, "BigStar", P.mustard, UDim2.fromScale(0.86, 0.42), 0.28, -10, 3)
	local coralStar = ToyDecor.star(background, "CoralStar", P.coral, UDim2.fromScale(0.79, 0.7), 0.1, 14, 3)
	local blueStar = ToyDecor.star(background, "BlueStar", P.sky, UDim2.fromScale(0.24, 0.72), 0.12, -8, 3)
	Theme.idle(bigStar:FindFirstChild("Shape"), 2.6, {Rotation = 6})
	Theme.idle(donut, 1.9, {Position = UDim2.new(0.14, 0, 0.47, 8)})

	-- Top bar: brown title tag (the "RETRO TOY BOX" pill) and a cream coin capsule, on the awning.
	local top = create("Frame", {Name = "TopBar", Size = UDim2.new(1, -48, 0, 64), Position = UDim2.new(0, 24, 0, 16),
		BackgroundTransparency = 1, ZIndex = 5, Parent = background})
	Theme.tag(top, "Title", "OBBY RUSH", 36, 64, {font = "display", icon = ToyDecor.icon("star"), iconSize = 36, padLeft = 20,
		padRight = 30})
	local coins = Theme.tag(top, "CoinLabel", Theme.formatNumber(state.coins or 0), 30, 56, {font = "display", color = P.creamLight,
		textColor = P.brown, stroke = Theme.outline, icon = ToyDecor.icon("coin"), iconSize = 40, padLeft = 8, padRight = 22})
	coins.AnchorPoint = Vector2.new(1, 0)
	coins.Position = UDim2.new(1, 0, 0, 4)

	-- PLAY: the coral toy box with a cream window. The robot pops out from behind its top edge.
	-- (Sizes and positions are set by applyLayout below.)
	local robot = ToyDecor.robot(background, "Robot", UDim2.fromScale(0.5, 0.4), 0.2, 4)
	robot.AnchorPoint = Vector2.new(0.5, ROBOT_PEEK)
	local play = Theme.button(background, "PlayButton", "プレイ", function() handlers.play() end,
		{primary = true, size = UDim2.fromOffset(LAYOUTS.regular.play.X, LAYOUTS.regular.play.Y), textSize = 46, depth = 8,
			inset = 12, radius = 30, font = Theme.fonts.heavy})
	play.AnchorPoint = Vector2.new(0.5, 0.5)
	play.ZIndex = 6
	local breathe = create("UIScale", {Name = "Breathe", Scale = 1, Parent = play})
	Theme.idle(breathe, 1.1, {Scale = 1.035})

	-- Dims the scenery while a page is open; tapping it closes the page. The nav tray stays above it.
	local scrim = create("TextButton", {Name = "Scrim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = P.brown,
		BackgroundTransparency = 0.45, BorderSizePixel = 0, Text = "", AutoButtonColor = false, Visible = false, ZIndex = 50,
		Selectable = false, Parent = background})
	scrim.Activated:Connect(function() MainMenu.open(gui, nil) end)

	-- Nav: four toy blocks on a cream tray.
	local nav = create("Frame", {Name = "NavBar", Size = UDim2.new(0, NAV_WIDTH, 0, 88), AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16), BackgroundColor3 = P.creamLight, BorderSizePixel = 0, ZIndex = 60, Active = true,
		Parent = background})
	local navFit = create("UIScale", {Name = "Fit", Scale = 1, Parent = nav}) -- shrinks the tray on very narrow screens
	Theme.corner(nav, 28)
	Theme.stroke(nav, Theme.outline)
	Theme.padding(nav, 12, 12, 10, 10)
	create("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12),
		HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder, Parent = nav})

	local pages = {}
	pages.Shop = page(gui, "ShopPage", "ショップ", "Shop", false)
	pages.Settings = page(gui, "SettingsPage", "設定", "Settings")
	pages.Inventory = page(gui, "InventoryPage", "持ち物", "Inventory")
	pages.Quests = page(gui, "QuestsPage", "クエスト", "Quests")
	emptyState(pages.Inventory, function(body)
		ToyDecor.donut(body, "Illustration", UDim2.fromScale(0.5, 0.4), 0.42, 1, P.creamLight)
	end, "まだアイテムがありません")
	emptyState(pages.Quests, function(body)
		ToyDecor.star(body, "Illustration", P.mustard, UDim2.fromScale(0.5, 0.35), 0.56, -8)
	end, "今日のクエストは準備中です")

	local navButtons = {}
	for index, item in ipairs(NAV) do
		navButtons[index] = Theme.button(nav, "Nav_" .. item.id, item.label, function()
			MainMenu.open(gui, item.id)
			if handlers.navigate then handlers.navigate(item.id) end
		end, {color = item.color, size = UDim2.new(0, 138, 0, 66), order = index, textSize = 20, inset = 6, radius = 18,
			icon = ToyDecor.icon(item.icon), iconSize = 26})
	end

	-- Shop: the ProductList is the page's cream window; one toy-shelf row per product (coloured bezel
	-- with the toy icon, cream window with name, coin price and a coral BUY block).
	local list = create("ScrollingFrame", {Name = "ProductList", Size = UDim2.new(1, -28, 1, -80), Position = UDim2.new(0, 14, 0, 66),
		BackgroundColor3 = P.creamLight, BackgroundTransparency = 0, BorderSizePixel = 0, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 8,
		ScrollBarImageColor3 = P.brown, ZIndex = 1, Parent = pages.Shop})
	Theme.corner(list, 20)
	Theme.stroke(list, Theme.outline)
	Theme.padding(list, 14, 22, 14, 14)
	create("UIListLayout", {Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list})
	-- Coin balance inside the shop header (the top bar is behind the page); mirrors CoinLabel, so
	-- whatever updates CoinLabel.Text also updates this.
	local wallet = Theme.tag(pages.Shop, "Wallet", coins.Text, 24, 44, {font = "display", color = P.creamLight, textColor = P.brown,
		stroke = Theme.outlineSmall, icon = ToyDecor.icon("coin"), iconSize = 30, padLeft = 6, padRight = 16})
	wallet.AnchorPoint = Vector2.new(1, 0)
	wallet.Position = UDim2.new(1, -84, 0, 11)
	wallet.ZIndex = 3
	coins:GetPropertyChangedSignal("Text"):Connect(function() wallet.Text = coins.Text end)

	for index, product in ipairs(state.products or {}) do
		local color = ROW_COLORS[(index - 1) % #ROW_COLORS + 1]
		local row = Theme.panel(list, "Product_" .. product.id, UDim2.new(1, 0, 0, 96), nil, {color = color, radius = 22})
		row.LayoutOrder = index
		local iconKind = PRODUCT_ICONS[product.id] or FALLBACK_ICONS[(index - 1) % #FALLBACK_ICONS + 1]
		ToyDecor.iconFrame(row, "ToyIcon", iconKind, 58, UDim2.new(0, 44, 0.5, 0), Vector2.new(0.5, 0.5))
		local window = Theme.panel(row, "Window", UDim2.new(1, -96, 1, -16), UDim2.new(0, 88, 0, 8), {radius = 16, stroke = 3})
		window.ZIndex = 1
		local name = Theme.label(row, "ProductName", product.name, 22, {font = "heavy", frameSize = UDim2.new(1, -262, 0, 30)})
		name.Position = UDim2.new(0, 104, 0, 14)
		name.TextWrapped = false
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.ZIndex = 2
		local price = Theme.tag(row, "Price", Theme.formatNumber(product.price), 22, 28, {font = "display", color = P.creamLight,
			textColor = P.brown, icon = ToyDecor.icon("coin"), iconSize = 24, padLeft = 0, padRight = 0})
		price.BackgroundTransparency = 1
		price.Position = UDim2.new(0, 104, 1, -46)
		price.ZIndex = 2
		local buy = Theme.button(row, "BuyButton", "購入", function() handlers.buy(product.id) end,
			{primary = true, size = UDim2.new(0, 128, 0, 60), textSize = 22, radius = 16})
		buy.AnchorPoint = Vector2.new(1, 0.5)
		buy.Position = UDim2.new(1, -18, 0.5, 0)
		buy.ZIndex = 2
	end

	-- Settings: toy toggles with an ON/OFF switch. Button text keeps the "<label>: ON|OFF" format.
	local settings = state.settings or {}
	for index, id in ipairs({"music", "sfx"}) do
		local label = id == "music" and "音楽" or "効果音"
		local on = settings[id] ~= false
		local renderSwitch
		local toggle
		toggle = Theme.button(pages.Settings, "Toggle_" .. (id == "music" and "Music" or "SFX"), label .. ": " .. (on and "ON" or "OFF"),
			function()
				on = not on
				toggle.Text = label .. ": " .. (on and "ON" or "OFF")
				renderSwitch(on, true)
				handlers.toggle(id, on)
			end,
			{color = id == "music" and P.teal or P.mustard, size = UDim2.new(1, -64, 0, 60), textSize = 22,
				align = Enum.TextXAlignment.Left, icon = ToyDecor.icon(id == "music" and "note" or "sparkle"), iconSize = 34})
		toggle.Position = UDim2.new(0, 32, 0, 80 + (index - 1) * 72)
		toggle.ZIndex = 2
		renderSwitch = switch(toggle)
		renderSwitch(on, false)
	end
	-- The robot "tinkering" at the bottom of the settings window (hidden on short screens, see applyLayout).
	local helper = ToyDecor.robot(pages.Settings:FindFirstChild("Body"), "Illustration", UDim2.fromScale(0.5, 0.74), 0.34, 1)

	-- Responsive layout: regular vs compact, re-applied whenever the screen size changes.
	local robotBob
	local lastCompact, lastFit, lastScale
	local function applyLayout()
		local size = gui.AbsoluteSize
		if typeof(size) ~= "Vector2" or size.X < 2 then
			local camera = workspace.CurrentCamera
			size = camera and camera.ViewportSize or Vector2.new(1280, 720)
		end
		local compact = size.Y < 450
		local fit = math.clamp((size.X - 24) / NAV_WIDTH, 0.75, 1)
		local s = compact and 1 or math.clamp(math.min(size.Y / 720, size.X / 1280), 1, 2)
		s = math.floor(s * 20 + 0.5) / 20
		if compact == lastCompact and fit == lastFit and s == lastScale then return end
		lastCompact, lastFit, lastScale = compact, fit, s
		local L = compact and LAYOUTS.compact or LAYOUTS.regular

		background.Size = UDim2.fromScale(1 / s, 1 / s)
		screenScale.Scale = s
		for _, id in ipairs(PAGE_IDS) do
			local frame = pages[id]
			frame:SetAttribute("RestScale", s)
			frame.PopScale.Scale = s
			if compact then
				frame.Size = UDim2.new(0.8, 0, 1, -124)
				frame.Position = UDim2.new(0.5, 0, 0.5, -44)
			else
				frame.Size = UDim2.new(0.76 / s, 0, 1 / s, -150)
				frame.Position = UDim2.new(0.5, 0, 0.5, -52 * s)
			end
		end

		-- Centre the robot + PLAY stack in the space between the awning and the nav tray.
		local playY = 0.5 + ROBOT_PEEK * L.robot / 2
		play.Size = UDim2.fromOffset(L.play.X, L.play.Y)
		play.Position = UDim2.new(0.5, 0, playY, 0)
		local playLabel = play:FindFirstChild("Label", true)
		if playLabel then playLabel.TextSize = L.playText end
		robot.Size = UDim2.fromScale(1, L.robot)
		local robotRest = UDim2.new(0.5, 0, playY, -L.play.Y / 2)
		if robotBob then robotBob:Cancel() end
		robot.Position = robotRest
		robotBob = Theme.idle(robot, 1.3, {Position = robotRest + UDim2.fromOffset(0, -9)})

		nav.Size = UDim2.new(0, NAV_WIDTH, 0, L.nav)
		for _, button in ipairs(navButtons) do
			button.Size = UDim2.new(0, 138, 0, L.navButton)
		end
		navFit.Scale = fit
		coralStar.Visible = not compact
		blueStar.Visible = not compact
		helper.Visible = not compact
	end
	applyLayout()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)

	return gui
end

-- Shows exactly one page (or none when pageId is nil), lights its nav tab and the scrim.
function MainMenu.open(gui, pageId)
	local anyOpen = false
	for _, id in ipairs(PAGE_IDS) do
		local frame = gui:FindFirstChild(id .. "Page")
		local show = pageId ~= nil and id == pageId
		if frame then
			local wasVisible = frame.Visible
			frame.Visible = show
			if show and not wasVisible then popIn(frame) end
			anyOpen = anyOpen or show
		end
		local navButton = gui:FindFirstChild("Nav_" .. id, true)
		if navButton then Theme.setActive(navButton, show) end
	end
	local scrim = gui:FindFirstChild("Scrim", true)
	if scrim then scrim.Visible = anyOpen end
end

function MainMenu.close(gui)
	MainMenu.open(gui, nil)
end

return MainMenu
