-- Main menu: top bar, PLAY, nav bar and the Shop / Inventory / Quests / Settings pages.
-- Other systems find these instances by name (see tests/test_main_menu.luau). Every name and
-- parent/child path of the original menu is kept; the ink painting is added around them.
-- Look (see DESIGN.md): one sheet of washi, everything brushed in sumi, one vermilion seal to press.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))

local MainMenu = {}

local NAV = {
	{id = "Shop", label = "ショップ"},
	{id = "Inventory", label = "持ち物"},
	{id = "Quests", label = "クエスト"},
	{id = "Settings", label = "設定"},
}
local PAGE_NAMES = {"ShopPage", "SettingsPage", "InventoryPage", "QuestsPage"}

local INSCRIPTION = "七転び八起き" -- 画賛: "fall seven times, rise eight" — the obby in six characters
local PLAY_SEAL = "出\n走" -- 出走: "to the start line", reversed out of the seal
local ENSO_CENTER = UDim2.fromScale(0.42, 0.47)
local ENSO_SIZE = 0.5 -- of screen height
local SEAL_SIZE = ENSO_SIZE * 0.38 -- the PLAY seal, also of screen height (≥ 64 px via UISizeConstraint)
local MARGIN = 48 -- 余白: generous page margins everywhere

local function formatAmount(value)
	local digits = tostring(math.floor(tonumber(value) or 0))
	local sign = ""
	if string.sub(digits, 1, 1) == "-" then
		sign, digits = "-", string.sub(digits, 2)
	end
	local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	if string.sub(grouped, 1, 1) == "," then grouped = string.sub(grouped, 2) end
	return sign .. grouped
end

local function page(gui, name, title)
	local frame = Theme.panel(gui, name, UDim2.new(0.6, 0, 0.62, 0), UDim2.new(0.2, 0, 0.16, 0))
	frame.Visible = false
	frame.ZIndex = 10
	Theme.label(frame, "Title", title, 26, {frameSize = UDim2.new(1, -200, 0, 40)}).Position = UDim2.new(0, 40, 0, 28)
	Theme.brush(frame, "TitleStroke", UDim2.new(0, 72, 0, 3), UDim2.new(0, 38, 0, 74))
	local close = Theme.button(frame, "CloseButton", "閉じる", function() frame.Visible = false end,
		{size = UDim2.new(0, 96, 0, 48), textSize = 18})
	close.Position = UDim2.new(1, -128, 0, 24)
	return frame
end

-- An empty page is left mostly blank on purpose: a small pale ensō and one line of 中墨.
local function emptyState(parent, text)
	Theme.enso(parent, "EmptyEnso", UDim2.fromOffset(64, 64), UDim2.new(0.5, 0, 0.5, -20),
		{weight = 0.06, transparency = 0.55, segments = 36, hairs = 2, seed = 3})
	local label = Theme.label(parent, "Empty", text, 18, {ink = Theme.ink.mid, align = Enum.TextXAlignment.Center,
		frameSize = UDim2.new(1, -80, 0, 26)})
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0.5, 30)
	return label
end

-- The painting on the sheet: aged paper edges, two ranges of distant mountains (遠山) in dilute ink.
local function paint(background)
	Theme.wash(background, "PaperEdgeX", {size = UDim2.fromScale(1, 1), position = UDim2.fromScale(0.5, 0.5), direction = 0,
		fade = {{0, 0.93}, {0.12, 1}, {0.88, 1}, {1, 0.93}}})
	Theme.wash(background, "PaperEdgeY", {size = UDim2.fromScale(1, 1), position = UDim2.fromScale(0.5, 0.5), direction = 90,
		fade = {{0, 0.95}, {0.16, 1}, {0.8, 1}, {1, 0.92}}})
	-- Each range is a rotated square: unequal rotations give unequal slopes; the ridge is densest and the
	-- ink dissolves into mist toward the foot.
	local ranges = {
		{"FarMountain", 0.66, 0.05, 1.03, 41, 0.9},
		{"FarMountain2", 0.5, 0.22, 1.06, 52, 0.92},
		{"NearMountain", 0.4, 0.12, 1.1, 46, 0.84},
	}
	for _, range in ipairs(ranges) do
		local name, size, x, y, rotation, ridge = table.unpack(range)
		Theme.wash(background, name, {size = UDim2.fromScale(1, size), position = UDim2.fromScale(x, y), rotation = rotation,
			square = true, corner = UDim.new(0.09, 0), fade = {{0, ridge}, {0.14, ridge + 0.035}, {0.36, 1}, {1, 1}}})
	end
end

-- handlers: {play = fn(), buy = fn(productId), toggle = fn(settingId, on), navigate = fn(pageId)?}
-- state: {coins = number, products = {{id, name, price}}, settings = {music = bool, sfx = bool}}
function MainMenu.build(playerGui, handlers, state)
	local gui = Theme.create("ScreenGui", {Name = "MainMenu", ResetOnSpawn = false, IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = playerGui})
	local background = Theme.create("Frame", {Name = "Background", Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.colors.background, BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 1, Parent = gui})
	paint(background)

	-- Top: the name in quiet serif at the left, the purse at the right. No box, just paper.
	local top = Theme.panel(background, "TopBar", UDim2.new(1, -MARGIN * 2, 0, 64), UDim2.new(0, MARGIN, 0, 24), {bare = true})
	Theme.label(top, "Title", "OBBY RUSH", 26, {frameSize = UDim2.new(0.5, 0, 1, 0)})
	local coins = Theme.label(top, "CoinLabel", formatAmount(state.coins), 22,
		{ink = Theme.ink.dark, align = Enum.TextXAlignment.Right, frameSize = UDim2.new(0, 180, 1, 0)})
	coins.Position = UDim2.new(1, -214, 0, 0)
	Theme.coin(top, "CoinIcon", 22, UDim2.new(1, -22, 0.5, 0))

	-- Centre: an ensō, and inside it the one vermilion seal on the screen. Pressing it starts the run.
	Theme.enso(background, "Enso", UDim2.fromScale(1, ENSO_SIZE), ENSO_CENTER, {weight = 0.034})
	local play = Theme.button(background, "PlayButton", PLAY_SEAL, function() handlers.play() end,
		{seal = true, size = UDim2.fromScale(1, SEAL_SIZE), textSize = 52, rotation = -3})
	play.AnchorPoint = Vector2.new(0.5, 0.5)
	play.Position = ENSO_CENTER
	Theme.create("UIAspectRatioConstraint", {AspectRatio = 1, Parent = play})
	Theme.create("UISizeConstraint", {MinSize = Vector2.new(64, 64), Parent = play})
	-- The plain word sits in the mouth of the ensō, under the seal, and scales with it.
	local caption = Theme.label(background, "PlayCaption", "プレイ", 16, {ink = Theme.ink.mid,
		align = Enum.TextXAlignment.Center, frameSize = UDim2.new(0, 160, 0, 22)})
	caption.AnchorPoint = Vector2.new(0.5, 0)
	caption.Position = UDim2.new(ENSO_CENTER.X.Scale, 0, ENSO_CENTER.Y.Scale + SEAL_SIZE / 2, 10)
	-- The seal is stamped onto the paper when the menu appears.
	local press = play:FindFirstChild("Press")
	if press then
		press.Scale = 1.12
		Theme.tween(press, {Scale = 1}, 0.35, 0.2)
	end

	-- Right: the inscription (画賛) in a vertical column, closed by a small seal (落款).
	local verse = Theme.label(background, "Inscription", Theme.vertical(INSCRIPTION), 30, {ink = Theme.ink.dark,
		align = Enum.TextXAlignment.Center, frameSize = UDim2.fromScale(0.05, 0.34)})
	verse.AnchorPoint = Vector2.new(0.5, 0)
	verse.Position = UDim2.fromScale(0.83, 0.22)
	verse.TextWrapped = false
	verse.TextScaled = true
	verse.LineHeight = 1.08
	verse.TextYAlignment = Enum.TextYAlignment.Top
	Theme.create("UITextSizeConstraint", {MaxTextSize = 30, Parent = verse})
	Theme.seal(background, "Rakkan", "遊", UDim2.fromOffset(32, 32), UDim2.new(0.83, 0, 0.56, 14),
		{anchor = Vector2.new(0.5, 0), rotation = 2})

	-- Bottom: the four pages as brushed words on the paper.
	local nav = Theme.create("Frame", {Name = "NavBar", Size = UDim2.new(0, 584, 0, 64), AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -28), BackgroundTransparency = 1, Parent = background})
	Theme.create("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 24),
		HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder, Parent = nav})

	-- A second sheet of thin paper lies over the menu while a page is open; clicking it closes the page.
	local veil = Theme.create("TextButton", {Name = "PageVeil", Text = "", AutoButtonColor = false, Selectable = false,
		BackgroundColor3 = Theme.colors.washi, BackgroundTransparency = 0.14, BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 5, Parent = gui})
	veil.Activated:Connect(function()
		for _, name in ipairs(PAGE_NAMES) do
			local frame = gui:FindFirstChild(name)
			if frame then frame.Visible = false end
		end
	end)

	local pages = {}
	pages.Shop = page(gui, "ShopPage", "ショップ")
	pages.Settings = page(gui, "SettingsPage", "設定")
	pages.Inventory = page(gui, "InventoryPage", "持ち物")
	pages.Quests = page(gui, "QuestsPage", "クエスト")
	emptyState(pages.Inventory, "まだアイテムがありません")
	emptyState(pages.Quests, "今日のクエストは準備中です")

	local navButtons = {}
	for index, item in ipairs(NAV) do
		navButtons[item.id] = Theme.button(nav, "Nav_" .. item.id, item.label, function()
			MainMenu.open(gui, item.id)
			if handlers.navigate then handlers.navigate(item.id) end
		end, {size = UDim2.new(0, 128, 0, 56), order = index})
	end

	-- The veil and the nav stroke follow whichever page is open.
	local function sync()
		local any = false
		for id, frame in pairs(pages) do
			any = any or frame.Visible
			if navButtons[id] then navButtons[id]:SetAttribute("Selected", frame.Visible == true) end
		end
		veil.Visible = any
	end
	for _, frame in pairs(pages) do
		frame:GetPropertyChangedSignal("Visible"):Connect(sync)
	end

	-- Shop: one ruled line per product — name, price with the coin mark, and an ink-ruled 購入.
	local list = Theme.create("ScrollingFrame", {Name = "ProductList", Size = UDim2.new(1, -80, 1, -120), Position = UDim2.new(0, 40, 0, 100),
		BackgroundTransparency = 1, BorderSizePixel = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 2, ScrollBarImageColor3 = Theme.colors.sumi, ScrollBarImageTransparency = Theme.ink.pale, Parent = pages.Shop})
	Theme.create("UIListLayout", {Padding = UDim.new(0, 0), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list})
	for index, product in ipairs(state.products or {}) do
		local row = Theme.panel(list, "Product_" .. product.id, UDim2.new(1, -8, 0, 72), nil, {bare = true})
		row.LayoutOrder = index
		Theme.rule(row)
		Theme.label(row, "ProductName", product.name, 20, {frameSize = UDim2.new(0.5, 0, 1, 0)}).Position = UDim2.new(0, 4, 0, 0)
		Theme.label(row, "Price", formatAmount(product.price), 20, {ink = Theme.ink.mid, align = Enum.TextXAlignment.Right,
			frameSize = UDim2.new(0, 96, 1, 0)}).Position = UDim2.new(1, -252, 0, 0)
		Theme.coin(row, "PriceCoin", 16, UDim2.new(1, -148, 0.5, 0), {ink = Theme.ink.mid})
		local buy = Theme.button(row, "BuyButton", "購入", function() handlers.buy(product.id) end,
			{primary = true, size = UDim2.new(0, 104, 0, 48), textSize = 18})
		buy.Position = UDim2.new(1, -108, 0.5, -24)
	end

	-- Settings: ruled lines; the state is written in 中墨 and marked with a filled or open ink dot.
	local settings = state.settings or {}
	for index, id in ipairs({"music", "sfx"}) do
		local label = id == "music" and "音楽" or "効果音"
		local on = settings[id] ~= false
		local toggle, dot
		local function render()
			toggle.Text = label .. "　" .. string.format('<font transparency="%.2f">%s</font>', Theme.ink.mid, on and "ON" or "OFF")
			dot.BackgroundTransparency = on and Theme.ink.dark or 1
		end
		toggle = Theme.button(pages.Settings, "Toggle_" .. (id == "music" and "Music" or "SFX"), label, function()
			on = not on
			render()
			handlers.toggle(id, on)
		end, {size = UDim2.new(1, -80, 0, 56), align = Enum.TextXAlignment.Left, mark = false})
		toggle.RichText = true
		toggle.Position = UDim2.new(0, 40, 0, 104 + (index - 1) * 64)
		Theme.rule(toggle)
		dot = Theme.create("Frame", {Name = "StateMark", Size = UDim2.fromOffset(16, 16), AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0), BackgroundColor3 = Theme.colors.sumi, BorderSizePixel = 0, Parent = toggle})
		Theme.round(dot)
		Theme.stroke(dot, {transparency = Theme.ink.dark, thickness = 1.5})
		render()
	end

	sync()
	return gui
end

function MainMenu.open(gui, pageId)
	for _, name in ipairs(PAGE_NAMES) do
		local frame = gui:FindFirstChild(name)
		if frame then frame.Visible = (name == pageId .. "Page") end
	end
end

return MainMenu
