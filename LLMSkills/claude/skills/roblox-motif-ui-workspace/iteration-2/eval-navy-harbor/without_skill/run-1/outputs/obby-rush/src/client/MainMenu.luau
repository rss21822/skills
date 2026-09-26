-- Main menu: top bar, PLAY, nav bar and the Shop / Inventory / Quests / Settings pages.
-- Other systems find these instances by name (see tests/test_main_menu.luau).
-- Look: "night harbour & navy" (see DESIGN.md). The top bar is a sailor collar with its red
-- neckerchief, a dressing line of signal flags hangs over a night port, PLAY is a red rope-bound
-- plate under the Blue Peter (flag P: "about to sail"), the tabs hang from a rope rail and show
-- their own code flag in a brass porthole.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Theme = require(Shared:WaitForChild("UITheme"))
local Motif = require(Shared:WaitForChild("NavalMotif"))
local HarborBackdrop = require(script.Parent:WaitForChild("HarborBackdrop"))

local P = Theme.palette
local MainMenu = {}

-- Every tab flies an International Code flag from the navy/white/red subset, picked by a sea word:
-- S = ship's Store, H = cargo Hold, V = Voyage (quests; its red saltire also reads as "X marks the
-- spot"), W = Wheel (the helm = settings). M and T were avoided: they read as Scotland's saltire and
-- a mirrored French tricolour at icon size.
local NAV = {
	{id = "Shop", label = "ショップ", flag = "S", caption = "S · SHIP'S STORE"},
	{id = "Inventory", label = "持ち物", flag = "H", caption = "H · CARGO HOLD"},
	{id = "Quests", label = "クエスト", flag = "V", caption = "V · VOYAGES"},
	{id = "Settings", label = "設定", flag = "W", caption = "W · WHEELHOUSE"},
}
local NAV_BY_ID = {}
for _, item in ipairs(NAV) do NAV_BY_ID[item.id] = item end

local NAV_WIDTH, NAV_HEIGHT, NAV_GAP = 144, 58, 12
local NAV_TEXT_LEFT, NAV_TEXT_RIGHT = 52, 8 -- the label is centred in the space right of the porthole
local PLAY_WIDTH, PLAY_HEIGHT = 300, 84
-- Below this viewport height (phones in landscape) the decorative extras that would collide with the
-- top bar and the tab rail are hidden; every control keeps its size.
local COMPACT_HEIGHT = 560
local COMPACT_HIDDEN = {"BluePeter", "PlayCaption", "PlayHint", "RopeCoil", "AwaitingSignal"}
-- Dressing line overhead ("満艦飾"): 22 slots, the two centre slots left free for the neckerchief.
local DRESS_SLOTS = 22
local DRESS_FLAGS = {"U", "E", "J", "W", "X", "C", "V", "S", "N", "H", "P", "T", "M", "E", "U", "J", "W", "V", "C", "X"}

local function withCommas(amount)
	local digits = tostring(math.floor(tonumber(amount) or 0))
	local sign, body = string.match(digits, "^(%-?)(%d+)$")
	if not body then return digits end
	local grouped = string.reverse((string.gsub(string.reverse(body), "(%d%d%d)", "%1,")))
	if string.sub(grouped, 1, 1) == "," then grouped = string.sub(grouped, 2) end
	return sign .. grouped
end

-- First character of a UTF-8 string (product names are Japanese).
local function firstCharacter(text)
	return string.match(text or "", "^[\1-\127\194-\244][\128-\191]*") or "?"
end

-- Underline the open page's tab and dim the harbour behind the page (nil = no page open).
local function markNav(gui, pageId)
	for _, item in ipairs(NAV) do
		local button = gui:FindFirstChild("Nav_" .. item.id, true)
		local mark = button and button:FindFirstChild("Selected")
		if mark then mark.Visible = item.id == pageId end
	end
	local scrim = gui:FindFirstChild("Scrim", true)
	if scrim then scrim.Visible = pageId ~= nil end
end

local function page(gui, name, title, item)
	local frame = Theme.panel(gui, name, UDim2.new(0.6, 0, 0.62, 0), UDim2.new(0.2, 0, 0.16, 0))
	frame.Visible = false
	local well = Motif.porthole(frame, "Porthole", 44)
	well.Position = UDim2.fromOffset(20, 14)
	Motif.flagIn(well, item.flag, 24, 16)
	Theme.label(frame, "Title", title, 26, {bold = true, frameSize = UDim2.new(1, -200, 0, 32)}).Position = UDim2.new(0, 80, 0, 10)
	Theme.label(frame, "Caption", item.caption, 14, {font = Theme.fonts.displayLight, color = P.whiteDim,
		frameSize = UDim2.new(1, -200, 0, 18)}).Position = UDim2.new(0, 81, 0, 42)
	Motif.rope(frame, "HeaderRope", 150, 7, {whipped = true}).Position = UDim2.fromOffset(20, 72)
	Theme.create("Frame", {Name = "HeaderRule", Position = UDim2.new(0, 178, 0, 75), Size = UDim2.new(1, -198, 0, 1),
		BackgroundColor3 = P.white, BackgroundTransparency = 0.75, BorderSizePixel = 0, Parent = frame})
	local close = Theme.button(frame, "CloseButton", "閉じる", function()
		frame.Visible = false
		markNav(gui, nil)
	end, {size = UDim2.new(0, 96, 0, 48)})
	close.Position = UDim2.new(1, -112, 0, 14)
	return frame
end

local function topBar(background, state)
	local top = Theme.create("Frame", {Name = "TopBar", Size = UDim2.new(1, -32, 0, 64), Position = UDim2.new(0, 16, 0, 16),
		BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = background})
	Theme.corner(top, 4)
	Theme.gradient(top, {{0, P.navyRaised}, {1, P.navy}}, 90)
	Theme.stroke(top, P.ink, 2, 0.3)
	Motif.collar(top)
	Theme.label(top, "Title", "OBBY RUSH", 32, {display = true, frameSize = UDim2.new(0.5, 0, 0, 46)}).Position = UDim2.new(0, 30, 0, 0)
	local coins = Theme.label(top, "CoinLabel", withCommas(state.coins or 0), 26,
		{display = true, align = Enum.TextXAlignment.Right, frameSize = UDim2.new(0.4, 0, 0, 46)})
	coins.Position = UDim2.new(0.6, -72, 0, 0)
	local coin = Motif.coin(top, "CoinIcon", 30)
	coin.AnchorPoint = Vector2.new(1, 0.5)
	coin.Position = UDim2.new(1, -28, 0, 23)
	local tie = Motif.neckerchief(top, "Neckerchief")
	tie.AnchorPoint = Vector2.new(0.5, 0)
	tie.Position = UDim2.new(0.5, 0, 1, -10)
	return top
end

local function dressLine(background)
	local line = Theme.create("Frame", {Name = "DressLine", Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 0, 98),
		BackgroundTransparency = 1, Parent = background})
	Theme.create("Frame", {Name = "Halyard", Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = P.rope, BackgroundTransparency = 0.3,
		BorderSizePixel = 0, Parent = line})
	local count = 0
	for slot = 1, DRESS_SLOTS do
		if slot ~= DRESS_SLOTS / 2 and slot ~= DRESS_SLOTS / 2 + 1 then
			count += 1
			local flag = Motif.flag(line, "Flag" .. slot, DRESS_FLAGS[(count - 1) % #DRESS_FLAGS + 1], 26, 18)
			flag.AnchorPoint = Vector2.new(0.5, 0)
			flag.Position = UDim2.new((slot - 0.5) / DRESS_SLOTS, 0, 0, 2)
		end
	end
end

local function playArea(background, handlers)
	-- The Blue Peter hoisted on a staff right above PLAY.
	local hoist = Theme.create("Frame", {Name = "BluePeter", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0.55, -40),
		Size = UDim2.fromOffset(160, 120), BackgroundTransparency = 1, Parent = background})
	Theme.create("Frame", {Name = "Staff", Position = UDim2.new(0.5, -1, 0, 6), Size = UDim2.new(0, 3, 1, -6),
		BackgroundColor3 = P.white, BackgroundTransparency = 0.1, BorderSizePixel = 0, Parent = hoist})
	local finial = Motif.coin(hoist, "Finial", 10)
	finial.AnchorPoint = Vector2.new(0.5, 0.5)
	finial.Position = UDim2.new(0.5, 0.5, 0, 6)
	-- pivot centred on the hoist edge so the flag swings from the staff
	local pivot = Theme.create("Frame", {Name = "FlagPivot", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 1, 0, 10),
		Size = UDim2.fromOffset(136, 46), BackgroundTransparency = 1, Rotation = -2, Parent = hoist})
	local flag = Motif.flag(pivot, "Flag", "P", 68, 46)
	flag.Position = UDim2.fromScale(0.5, 0)
	Theme.loop(pivot, 2.6, {Rotation = 3})

	local shadow = Theme.create("Frame", {Name = "PlayShadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.55, 6),
		Size = UDim2.fromOffset(PLAY_WIDTH, PLAY_HEIGHT), BackgroundColor3 = P.ink, BackgroundTransparency = 0.45, BorderSizePixel = 0,
		Parent = background})
	Theme.corner(shadow, 10)
	local play = Theme.button(background, "PlayButton", "プレイ", function() handlers.play() end,
		{primary = true, size = UDim2.new(0, PLAY_WIDTH, 0, PLAY_HEIGHT), textSize = 34, radius = 10, piping = false})
	play.AnchorPoint = Vector2.new(0.5, 0.5)
	play.Position = UDim2.new(0.5, 0, 0.55, 0)
	local sheen = Theme.create("Frame", {Name = "Sheen", Position = UDim2.fromOffset(14, 14), Size = UDim2.new(1, -28, 0.5, -14),
		BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.92, BorderSizePixel = 0, Parent = play})
	Theme.corner(sheen, 4)
	Motif.ropeFrame(play, PLAY_WIDTH, PLAY_HEIGHT, 7, 7)

	local caption = Theme.label(background, "PlayCaption", "BLUE PETER  ·  SET SAIL", 15,
		{font = Theme.fonts.displayLight, align = Enum.TextXAlignment.Center, frameSize = UDim2.fromOffset(420, 20)})
	caption.AnchorPoint = Vector2.new(0.5, 0)
	caption.Position = UDim2.new(0.5, 0, 0.55, 56)
	local hint = Theme.label(background, "PlayHint", "P旗があがったら、まもなく出港", 14,
		{color = P.whiteDim, align = Enum.TextXAlignment.Center, frameSize = UDim2.fromOffset(420, 20)})
	hint.AnchorPoint = Vector2.new(0.5, 0)
	hint.Position = UDim2.new(0.5, 0, 0.55, 76)
end

local function navBar(background, gui, handlers)
	local width = #NAV * NAV_WIDTH + (#NAV - 1) * NAV_GAP
	-- the tabs hang from a rope rail like flags from a halyard
	local rail = Motif.rope(background, "NavRail", width + 48, 8, {whipped = true})
	rail.AnchorPoint = Vector2.new(0.5, 1)
	rail.Position = UDim2.new(0.5, 0, 1, -22 - NAV_HEIGHT - 12)
	local nav = Theme.create("Frame", {Name = "NavBar", Size = UDim2.new(0, width, 0, NAV_HEIGHT), AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -22), BackgroundTransparency = 1, Parent = background})
	Theme.create("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, NAV_GAP),
		HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Bottom,
		SortOrder = Enum.SortOrder.LayoutOrder, Parent = nav})

	for index, item in ipairs(NAV) do
		local button = Theme.button(nav, "Nav_" .. item.id, item.label, function()
			MainMenu.open(gui, item.id)
			if handlers.navigate then handlers.navigate(item.id) end
		end, {size = UDim2.new(0, NAV_WIDTH, 0, NAV_HEIGHT), order = index, textSize = 18,
			padding = {left = NAV_TEXT_LEFT, right = NAV_TEXT_RIGHT}})
		-- children sit in the padded content box, so offsets below are shifted back by NAV_TEXT_LEFT
		local well = Motif.porthole(button, "Porthole", 36)
		well.AnchorPoint = Vector2.new(0, 0.5)
		well.Position = UDim2.new(0, 12 - NAV_TEXT_LEFT, 0.5, 0)
		Motif.flagIn(well, item.flag, 20, 14)
		for side, x in ipairs({24, NAV_WIDTH - 25}) do
			Theme.create("Frame", {Name = "Lanyard" .. side, Position = UDim2.fromOffset(x - NAV_TEXT_LEFT, -14), Size = UDim2.fromOffset(1, 14),
				BackgroundColor3 = P.rope, BackgroundTransparency = 0.2, BorderSizePixel = 0, Parent = button})
		end
		Theme.create("Frame", {Name = "Selected", Visible = false, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, -11),
			Size = UDim2.fromOffset(60, 3), BackgroundColor3 = P.red, BorderSizePixel = 0, Parent = button})
	end
end

local function shopPage(shop, state, handlers)
	local list = Theme.create("ScrollingFrame", {Name = "ProductList", Size = UDim2.new(1, -32, 1, -108), Position = UDim2.new(0, 16, 0, 92),
		BackgroundTransparency = 1, BorderSizePixel = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6, ScrollBarImageColor3 = P.white, ScrollBarImageTransparency = 0.5, Parent = shop})
	Theme.create("UIListLayout", {Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list})
	for index, product in ipairs(state.products or {}) do
		local row = Theme.panel(list, "Product_" .. product.id, UDim2.new(1, -10, 0, 68), nil, {variant = "row"})
		row.LayoutOrder = index
		local well = Motif.porthole(row, "Porthole", 42)
		well.AnchorPoint = Vector2.new(0, 0.5)
		well.Position = UDim2.new(0, 14, 0.5, 0)
		Theme.label(well, "Glyph", firstCharacter(product.name), 20,
			{bold = true, align = Enum.TextXAlignment.Center, frameSize = UDim2.fromScale(1, 1)})
		Theme.label(row, "ProductName", product.name, 19, {bold = true, frameSize = UDim2.new(0.5, -74, 1, 0)}).Position = UDim2.new(0, 74, 0, 0)
		local coin = Motif.coin(row, "PriceCoin", 20)
		coin.AnchorPoint = Vector2.new(0, 0.5)
		coin.Position = UDim2.new(0.55, 0, 0.5, 0)
		Theme.label(row, "Price", withCommas(product.price), 22, {display = true, frameSize = UDim2.new(0.2, 0, 1, 0)}).Position =
			UDim2.new(0.55, 28, 0, 0)
		local buy = Theme.button(row, "BuyButton", "購入", function() handlers.buy(product.id) end,
			{primary = true, size = UDim2.new(0, 104, 0, 48)})
		buy.Position = UDim2.new(1, -116, 0.5, -24)
	end
end

-- Settings: each toggle shows flag C (Charlie, "yes") when on and N (November, "no") when off.
local function settingsPage(container, state, handlers)
	local settings = state.settings or {}
	for index, id in ipairs({"music", "sfx"}) do
		local label = id == "music" and "音楽" or "効果音"
		local on = settings[id] ~= false
		local toggle, well, caption
		local function render()
			toggle.Text = label .. ": " .. (on and "ON" or "OFF")
			toggle.TextColor3 = on and P.white or P.whiteDim
			local old = well:FindFirstChild("Flag")
			if old then old:Destroy() end
			Motif.flagIn(well, on and "C" or "N", 22, 15)
			caption.Text = on and "C · YES" or "N · NO"
		end
		toggle = Theme.button(container, "Toggle_" .. (id == "music" and "Music" or "SFX"), "", function()
			on = not on
			render()
			handlers.toggle(id, on)
		end, {size = UDim2.new(1, -32, 0, 60), textSize = 20, align = Enum.TextXAlignment.Left, padding = {left = 20}})
		toggle.Position = UDim2.new(0, 16, 0, 96 + (index - 1) * 72)
		well = Motif.porthole(toggle, "StateFlag", 38)
		well.AnchorPoint = Vector2.new(1, 0.5)
		well.Position = UDim2.new(1, -18, 0.5, 0)
		caption = Theme.label(toggle, "StateCaption", "", 15, {font = Theme.fonts.displayLight, color = P.whiteDim,
			align = Enum.TextXAlignment.Right, frameSize = UDim2.new(0, 110, 1, 0)})
		caption.Position = UDim2.new(1, -182, 0, 0)
		render()
	end
end

local function emptyStates(pages)
	-- Inventory: the hold is empty, only a coiled rope on deck.
	local coil = Motif.ropeCoil(pages.Inventory, "RopeCoil", 112)
	coil.AnchorPoint = Vector2.new(0.5, 0.5)
	coil.Position = UDim2.new(0.5, -20, 0.5, -8)
	Theme.label(pages.Inventory, "Empty", "まだアイテムがありません", 20, {bold = true, align = Enum.TextXAlignment.Center,
		frameSize = UDim2.new(1, -32, 0, 28)}).Position = UDim2.new(0, 16, 0.5, 66)
	Theme.label(pages.Inventory, "EmptyHint", "船倉は空っぽ。ショップで積み込もう", 15, {color = P.whiteDim, align = Enum.TextXAlignment.Center,
		frameSize = UDim2.new(1, -32, 0, 22)}).Position = UDim2.new(0, 16, 0.5, 96)

	-- Quests: an empty halyard waiting for today's signal.
	local waiting = Theme.create("Frame", {Name = "AwaitingSignal", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -10),
		Size = UDim2.fromOffset(300, 80), BackgroundTransparency = 1, Parent = pages.Quests})
	Motif.rope(waiting, "Halyard", 300, 6, {whipped = true})
	for slot = 1, 3 do
		local blank = Theme.create("Frame", {Name = "BlankFlag" .. slot, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(slot / 4, 0, 0, 12),
			Size = UDim2.fromOffset(60, 40), BackgroundColor3 = P.deep, BackgroundTransparency = 0.3, BorderSizePixel = 0, Parent = waiting})
		Theme.corner(blank, 2)
		Theme.stroke(blank, P.white, 1.5, 0.55)
		Theme.label(blank, "Mark", "?", 22, {display = true, color = P.whiteDim, align = Enum.TextXAlignment.Center,
			frameSize = UDim2.fromScale(1, 1)})
		Theme.create("Frame", {Name = "Line", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -6), Size = UDim2.fromOffset(1, 6),
			BackgroundColor3 = P.rope, BorderSizePixel = 0, Parent = blank})
	end
	Theme.label(pages.Quests, "Empty", "今日のクエストは準備中です", 20, {bold = true, align = Enum.TextXAlignment.Center,
		frameSize = UDim2.new(1, -32, 0, 28)}).Position = UDim2.new(0, 16, 0.5, 66)
	Theme.label(pages.Quests, "EmptyHint", "つぎの信号旗があがるのを待とう", 15, {color = P.whiteDim, align = Enum.TextXAlignment.Center,
		frameSize = UDim2.new(1, -32, 0, 22)}).Position = UDim2.new(0, 16, 0.5, 96)
end

-- handlers: {play = fn(), buy = fn(productId), toggle = fn(settingId, on), navigate = fn(pageId)?}
-- state: {coins = number, products = {{id, name, price}}, settings = {music = bool, sfx = bool}}
function MainMenu.build(playerGui, handlers, state)
	state = state or {}
	local gui = Theme.create("ScreenGui", {Name = "MainMenu", ResetOnSpawn = false, IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = playerGui})
	local background = Theme.create("Frame", {Name = "Background", Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.colors.background, BackgroundTransparency = 0, BorderSizePixel = 0, Parent = gui})
	HarborBackdrop.build(background)

	dressLine(background)
	playArea(background, handlers)
	-- dims the harbour and PLAY while a page is open; the top bar and the tabs stay bright above it
	Theme.create("Frame", {Name = "Scrim", Visible = false, Size = UDim2.fromScale(1, 1), BackgroundColor3 = P.ink,
		BackgroundTransparency = 0.4, BorderSizePixel = 0, Parent = background})
	topBar(background, state)
	navBar(background, gui, handlers)

	local pages = {}
	pages.Shop = page(gui, "ShopPage", "ショップ", NAV_BY_ID.Shop)
	pages.Settings = page(gui, "SettingsPage", "設定", NAV_BY_ID.Settings)
	pages.Inventory = page(gui, "InventoryPage", "持ち物", NAV_BY_ID.Inventory)
	pages.Quests = page(gui, "QuestsPage", "クエスト", NAV_BY_ID.Quests)

	shopPage(pages.Shop, state, handlers)
	settingsPage(pages.Settings, state, handlers)
	emptyStates(pages)

	local camera = workspace.CurrentCamera
	local function fit()
		local compact = camera ~= nil and camera.ViewportSize.Y < COMPACT_HEIGHT
		for _, name in ipairs(COMPACT_HIDDEN) do
			local item = gui:FindFirstChild(name, true)
			if item then item.Visible = not compact end
		end
	end
	fit()
	if camera and camera.GetPropertyChangedSignal then
		local connection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
		gui.Destroying:Connect(function() connection:Disconnect() end)
	end

	return gui
end

function MainMenu.open(gui, pageId)
	for _, name in ipairs({"ShopPage", "SettingsPage", "InventoryPage", "QuestsPage"}) do
		local frame = gui:FindFirstChild(name)
		if frame then frame.Visible = (name == pageId .. "Page") end
	end
	markNav(gui, pageId)
end

return MainMenu
