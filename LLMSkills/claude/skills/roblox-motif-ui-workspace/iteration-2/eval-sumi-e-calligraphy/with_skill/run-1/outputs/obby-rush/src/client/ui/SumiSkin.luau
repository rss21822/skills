--!nocheck
-- SumiSkin: the "Sumi & Washi" look for Obby Rush — ink, washi paper and one vermilion seal.
--
--   Skin.apply(Theme)      runtime skin of ReplicatedStorage.Shared.UITheme: recolours Theme.colors in
--                          place and wraps panel / label / button so every screen built through the
--                          theme draws in ink on paper. Idempotent; the shared module is not edited.
--   Skin.decorate(gui)     the main menu composition (paper, distant mountains, ensō moon, inscription,
--                          the PLAY seal, brush nav, hanging-scroll pages, the veil behind pages).
--
-- Contract: names, parents, callbacks, Active/Visible logic and texts of the menu are left as built.
-- The skin only changes presentation (colour, font, corner, size/position of the same instances) and
-- adds "Motif*" children that are never buttons. Every step is pcall'd: a skin error leaves the
-- original look, never a missing screen.
local Kit = require(script.Parent:WaitForChild("MotifSkinKit"))
local Parts = require(script.Parent:WaitForChild("SumiParts"))
local Spec = require(script.Parent:WaitForChild("MotifSpec"))

local kit = Kit.new(Spec)
local P = kit.P
local Skin = {kit = kit, Parts = Parts, name = "Sumi & Washi"}

local COIN_EMOJI = "\240\159\170\153" -- U+1FA99, drawn as a tofu box by Roblox and colourful anyway
local SEAL_COLORS = {shu = P.primary, paper = P.white}
local PAGE_SEALS = {ShopPage = "市", InventoryPage = "蔵", QuestsPage = "修", SettingsPage = "調"}

local states = setmetatable({}, {__mode = "k"}) -- button -> presentation state
local held = setmetatable({}, {__mode = "k"}) -- button -> background colour the skin wants

local function try(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then warn("[SumiSkin] " .. tostring(err)) end
	return ok
end

local function create(className, parent, props)
	return Parts.create(className, parent, props)
end

local function viewport()
	local ok, size = pcall(function() return workspace.CurrentCamera.ViewportSize end)
	if ok and size and size.X > 0 then return size.X, size.Y end
	return 1280, 720
end

-- Approximate text width for placing the coin icon (TextBounds when Roblox has laid the text out).
local function textWidth(object)
	local ok, bounds = pcall(function() return object.TextBounds end)
	if ok and bounds and typeof(bounds) == "Vector2" and bounds.X > 0 then return bounds.X end
	local size, width = object.TextSize or 16, 0
	for char in string.gmatch(object.Text or "", "[\0-\127\194-\244][\128-\191]*") do
		if #char >= 3 then
			width += size
		elseif char == " " or char == "," or char == "." or char == ":" then
			width += size * 0.3
		else
			width += size * 0.62
		end
	end
	return width
end

local function disableThemeStroke(object)
	for _, child in ipairs(object:GetChildren()) do
		if child.ClassName == "UIStroke" and string.sub(child.Name, 1, 5) ~= "Motif" then
			pcall(function()
				child.Enabled = false
				child.Transparency = 1
			end)
		end
	end
end

local function setCorner(object, radius)
	local corner = object:FindFirstChildOfClass("UICorner") or create("UICorner", object)
	corner.CornerRadius = UDim.new(0, radius)
end

-- The only colour the skin enforces on a button: themes reset BackgroundColor3 on hover, the skin
-- puts its own back (ink stamps must not flash to the theme accent, the seal stays vermilion).
local function hold(button, color)
	held[button] = color
	button.BackgroundColor3 = color
end

local function watchHeld(button)
	pcall(function()
		button:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
			local want = held[button]
			if want and button.BackgroundColor3 ~= want then button.BackgroundColor3 = want end
		end)
	end)
end

local function setScale(button, scale, seconds)
	local node = button:FindFirstChild("MotifScale") or create("UIScale", button, {Name = "MotifScale", Scale = 1})
	kit:tween(node, {Scale = scale}, seconds or 0.1, Enum.EasingStyle.Quad)
end

-- Buttons -------------------------------------------------------------------------------------------
-- Roles: seal (the one vermilion CTA), stamp (a worn ink seal: buy / confirm), brush (bare ink
-- characters over a brush stroke: nav, close, toggles, everything else).
local function paint(button)
	local s = states[button]
	if not s then return end
	pcall(function()
		if s.role == "seal" or s.role == "stamp" then
			local face = s.role == "seal" and P.primary or P.ink
			if not s.enabled then
				face = P.disabled
			elseif s.pressed then
				face = face:Lerp(s.role == "seal" and P.ink or P.paper, s.role == "seal" and 0.22 or 0.14)
			elseif s.hover then
				face = face:Lerp(s.role == "seal" and P.ink or P.paper, s.role == "seal" and 0.1 or 0.2)
			end
			button.BackgroundTransparency = 0
			hold(button, face)
			button.TextColor3 = s.enabled and P.white or P.muted
		else
			hold(button, P.ink)
			button.BackgroundTransparency = not s.enabled and 1 or s.pressed and 0.9 or s.hover and 0.95 or 1
			button.TextColor3 = s.enabled and P.ink or P.muted
			local brush = button:FindFirstChild("MotifBrush")
			if brush then
				Parts.setBrushOpacity(brush, not s.enabled and 0 or s.selected and 1 or s.hover and 0.75 or 0.22)
				if string.sub(button.Name, 1, 4) == "Nav_" then
					-- the open page's tab is written with a loaded brush
					brush.Size = UDim2.new(0.64, 0, 0, s.selected and 9 or 6)
				end
			end
		end
	end)
end
Skin.paint = paint

-- Toggle mark: ON = a closed ensō with a drop of ink in it, OFF = the same circle in pale ink, empty.
-- (A circle with a gap read as a loading spinner, so the state is carried by the dot, not the gap.)
local function toggleMark(button)
	local mark = button:FindFirstChild("MotifToggleMark")
	if not mark then
		mark = Parts.enso(button, "MotifToggleMark", {
			-- inside the toggle's 52 px right padding (children are laid out in the padded box)
			size = UDim2.fromOffset(26, 26), position = UDim2.new(1, 22, 0.5, 0), anchor = Vector2.new(0.5, 0.5),
			color = P.ink, thickness = 4, alpha = 0.05, gap = -45, closed = true, zIndex = button.ZIndex,
		})
		local dot = create("Frame", mark, {Name = "Dot", BackgroundColor3 = P.ink, BorderSizePixel = 0, Active = false,
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.42, 0.42),
			ZIndex = button.ZIndex})
		create("UICorner", dot, {CornerRadius = UDim.new(0.5, 0)})
	end
	local text = string.upper(button.Text or "")
	local on = string.find(text, "OFF", 1, true) == nil
	for _, ring in ipairs(mark:GetChildren()) do
		local stroke = ring:FindFirstChild("Ink")
		local lift = stroke and stroke:FindFirstChild("Lift")
		if stroke then stroke.Color = on and P.ink or P.usuzumi end
		if lift then
			local base = ring.Name == "Body" and 0 or ring.Name == "Bristle" and 0.1 or 0.4
			lift.Transparency = NumberSequence.new(on and base or math.min(1, base + 0.35))
		end
	end
	local dot = mark:FindFirstChild("Dot")
	if dot then dot.Visible = on end
end

local function styleButton(button, role)
	local s = {role = role, enabled = button.Active ~= false, hover = false, pressed = false, selected = false}
	states[button] = s
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	disableThemeStroke(button)
	watchHeld(button)
	if role == "seal" then
		setCorner(button, 3)
		kit:setFont(button, "strong")
	elseif role == "stamp" then
		-- 墨印: a black seal impression, worn at the rim like the vermilion one.
		setCorner(button, 2)
		kit:setFont(button, "button")
		Parts.sealFace(button, P.white, {inset = 4, line = 1, flecks = 6, fleck = 3, chips = 3, seed = #button.Name + 3})
	else
		setCorner(button, 2)
		kit:setFont(button, "button")
		-- 払い: a short brush stroke under the characters, lifting slightly to the right.
		Parts.brush(button, "MotifBrush", {
			position = UDim2.new(0.5, 0, 1, -7), anchor = Vector2.new(0.5, 0.5), size = UDim2.new(0.64, 0, 0, 6),
			rotation = -1.5, color = P.ink, alpha = 0, seed = #(button.Name or "") * 31 + 5, layers = 3, zIndex = button.ZIndex,
		})
		if string.sub(button.Name, 1, 7) == "Toggle_" then
			button.TextXAlignment = Enum.TextXAlignment.Left
			create("UIPadding", button, {Name = "MotifPadding", PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 52)})
			-- Children sit inside the padding: offsets below are relative to the padded box.
			local brush = button:FindFirstChild("MotifBrush")
			if brush then
				brush.AnchorPoint = Vector2.new(0, 0.5)
				brush.Position = UDim2.new(0, -8, 1, -5)
				brush.Size = UDim2.new(1, 44, 0, 4)
				brush.Rotation = 0
			end
			toggleMark(button)
			button:GetPropertyChangedSignal("Text"):Connect(function() pcall(toggleMark, button) end)
		end
	end
	local function input(isBegin)
		return function(object)
			local kind = object and object.UserInputType
			if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then return end
			s.pressed = isBegin and s.enabled
			if role == "seal" or role == "stamp" then setScale(button, s.pressed and 0.97 or 1, 0.08) end
			paint(button)
		end
	end
	button.MouseEnter:Connect(function() s.hover = true; paint(button) end)
	button.MouseLeave:Connect(function()
		s.hover, s.pressed = false, false
		if role == "seal" or role == "stamp" then setScale(button, 1, 0.12) end
		paint(button)
	end)
	button.InputBegan:Connect(input(true))
	button.InputEnded:Connect(input(false))
	pcall(function()
		button:GetPropertyChangedSignal("Active"):Connect(function() s.enabled = button.Active ~= false; paint(button) end)
	end)
	paint(button)
	return s
end

function Skin.setSelected(button, selected)
	local s = states[button]
	if s and s.selected ~= selected then
		s.selected = selected
		paint(button)
	end
end

local function roleFor(name, options)
	if name == "PlayButton" then return "seal" end
	if options and options.primary and name ~= "CloseButton" then return "stamp" end
	return "brush"
end

-- Labels ---------------------------------------------------------------------------------------------
local function placeCoin(label)
	local coin = label:FindFirstChild("MotifCoin")
	if not coin then return end
	local size = coin.Size.X.Offset
	if label.TextXAlignment == Enum.TextXAlignment.Right then
		coin.Position = UDim2.new(1, -(textWidth(label) + size + 8), 0.5, 0)
	else
		-- UIPadding moves children too: step back into the gap the padding opened for the coin.
		local pad = label:FindFirstChild("MotifPadding")
		coin.Position = UDim2.new(0, -(pad and pad.PaddingLeft.Offset or size + 8), 0.5, 0)
	end
end

-- "🪙 300" -> an ink coin before "300". Follows later Text updates from other systems.
local function sanitizeCoin(label)
	local text = label.Text
	if type(text) ~= "string" or not string.find(text, COIN_EMOJI, 1, true) then return end
	label.Text = (string.gsub(string.gsub(text, COIN_EMOJI, ""), "^%s+", ""))
	if not label:FindFirstChild("MotifCoin") then
		local size = math.floor((label.TextSize or 18) * 0.95)
		Parts.coin(label, "MotifCoin", size, P.ink, P.paper)
		if label.TextXAlignment ~= Enum.TextXAlignment.Right then
			create("UIPadding", label, {Name = "MotifPadding", PaddingLeft = UDim.new(0, size + 8)})
		end
		label:GetPropertyChangedSignal("Text"):Connect(function() pcall(sanitizeCoin, label); pcall(placeCoin, label) end)
		pcall(function() label:GetPropertyChangedSignal("TextBounds"):Connect(function() pcall(placeCoin, label) end) end)
	end
	placeCoin(label)
end

local function styleLabel(label, options)
	kit:setFont(label, options and options.bold and "title" or "body")
	sanitizeCoin(label)
end

-- Panels ---------------------------------------------------------------------------------------------
local function stylePanel(frame, name)
	disableThemeStroke(frame)
	setCorner(frame, 0)
	frame.BorderSizePixel = 0
	if name == "TopBar" then
		frame.BackgroundTransparency = 1
	elseif string.match(name, "^Product_") then
		-- A ruled line of a letter: no box, a pale brush rule underneath.
		frame.BackgroundTransparency = 1
		Parts.brush(frame, "MotifRule", {position = UDim2.new(0, 4, 1, -2), size = UDim2.new(1, -8, 0, 3),
			color = P.ink, alpha = 0.72, layers = 2, seed = #name * 13})
	elseif string.match(name, "Page$") then
		-- A hanging scroll (横物): washi mounted in cloth, 天/地, 一文字, 風帯, rod and roller.
		-- Re-anchored at its centre (same place) so a minimum size keeps it on narrow phones.
		local position, size = frame.Position, frame.Size
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.new(position.X.Scale + size.X.Scale / 2, position.X.Offset + size.X.Offset / 2,
			position.Y.Scale + size.Y.Scale / 2, position.Y.Offset + size.Y.Offset / 2)
		create("UISizeConstraint", frame, {Name = "MotifSize", MinSize = Vector2.new(320, 230), MaxSize = Vector2.new(780, 520)})
		frame.BackgroundColor3, frame.BackgroundTransparency = P.panel, 0
		create("UIStroke", frame, {Name = "MotifMount", ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = P.mount,
			Thickness = 7, Transparency = 0, LineJoinMode = Enum.LineJoinMode.Miter})
		frame.ZIndex = 3
		-- Short screens (landscape phones) get a slimmer mounting so the roller stays clear of the nav.
		local _, vh = viewport()
		local roomy = vh >= 500
		Parts.scroll(frame, {ink = P.ink, knob = P.nakazumi, mount = P.mount, ichimonji = P.ichimonji, futai = P.futai},
			{band = 7, ten = roomy and 22 or 8, chi = roomy and 30 or 0, roller = roomy and 10 or 6})
		if not roomy then
			-- lift the scroll a little so its roller clears the nav labels below
			frame.Position = frame.Position + UDim2.fromOffset(0, -8)
		end
	else
		frame.BackgroundColor3, frame.BackgroundTransparency = P.panel, 0
		create("UIStroke", frame, {Name = "MotifMount", ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = P.mount,
			Thickness = 4, Transparency = 0, LineJoinMode = Enum.LineJoinMode.Miter})
	end
end

-- Theme adapter --------------------------------------------------------------------------------------
function Skin.apply(Theme)
	if type(Theme) ~= "table" or type(Theme.button) ~= "function" or type(Theme.colors) ~= "table" then return false end
	if Theme.skin == Skin then return true end
	-- Same table, new values: modules that cached Theme.colors see the ink palette too.
	local C = Theme.colors
	C.background, C.panel, C.panelLight = P.paper, P.panel, P.paper
	C.accent, C.text, C.subtext = P.ink, P.ink, P.muted
	C.danger, C.success = P.danger, P.success

	local panel, label, button = Theme.panel, Theme.label, Theme.button
	Theme.panel = function(parent, name, size, position)
		local frame = panel(parent, name, size, position)
		try(stylePanel, frame, name)
		return frame
	end
	Theme.label = function(parent, name, text, size, options)
		local object = label(parent, name, text, size, options)
		try(styleLabel, object, options)
		return object
	end
	Theme.button = function(parent, name, text, onClick, options)
		local object = button(parent, name, text, onClick, options)
		try(styleButton, object, roleFor(name, options))
		return object
	end
	Theme.skin = Skin
	return true
end

-- Main menu composition --------------------------------------------------------------------------------
local SEAL_SIZE = Vector2.new(208, 86)

-- Where the header ends (it is pushed under Roblox's top bar by clearTopbar: inset + 8 + 16 + 64).
local function headerBottom()
	return kit:topbar().height + 8 + 16 + 64
end

local function scenery(background)
	local vw, vh = viewport()
	local holder = create("Frame", background, {Name = "MotifScenery", BackgroundTransparency = 1, Active = false,
		Size = UDim2.fromScale(1, 1), ZIndex = 1})

	-- Washi: short, faint fibres (楮) scattered in the paper. Texture, not decoration.
	local rand = Parts.rng(2718)
	local fibres = create("Frame", holder, {Name = "MotifFibres", BackgroundTransparency = 1, Active = false,
		Size = UDim2.fromScale(1, 1), ZIndex = 1})
	for index = 1, 22 do
		create("Frame", fibres, {Name = "Fibre" .. index, BorderSizePixel = 0, BackgroundColor3 = P.usuzumi,
			BackgroundTransparency = rand(0.86, 0.93), Active = false, ZIndex = 1, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(rand(0.03, 0.97), rand(0.05, 0.95)), Size = UDim2.fromOffset(rand(10, 34), 1),
			Rotation = rand(-80, 80)})
	end

	-- The moon: a pale ensō over the mountains, right of centre, below the header.
	local diameter = math.min(vw * 0.26, vh * 0.34)
	Parts.enso(holder, "MotifEnso", {size = UDim2.fromScale(0.26, 0.34), position = UDim2.new(0.79, 0, 0, headerBottom() + 8),
		anchor = Vector2.new(0.5, 0), color = P.ink, alpha = 0.42, thicknessRatio = 0.075, diameterHint = diameter, gap = -45,
		zIndex = 1})

	-- Distant mountains dissolving into mist, lower right; the nav keeps clean paper below them.
	local range = create("Frame", holder, {Name = "MotifMountains", BackgroundTransparency = 1, Active = false,
		AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, -92), Size = UDim2.fromScale(0.62, 0.5), ZIndex = 1})
	create("UIAspectRatioConstraint", range, {AspectRatio = 1.9, AspectType = Enum.AspectType.FitWithinMaxSize,
		DominantAxis = Enum.DominantAxis.Width})
	-- {centre x, centre y, width, height} in the range's scale; far ranges paler (濃淡 = distance).
	local layers = {
		{alpha = 0.9, z = 1, peaks = {{0.2, 0.8, 0.2, 0.4}, {0.46, 0.7, 0.36, 0.62}, {0.63, 0.75, 0.14, 0.34}, {0.9, 0.78, 0.26, 0.44}}},
		{alpha = 0.84, z = 3, peaks = {{0.72, 0.9, 0.3, 0.46}, {0.36, 0.95, 0.22, 0.3}}},
		{alpha = 0.76, z = 4, peaks = {{0.89, 1.02, 0.34, 0.4}, {0.57, 1.05, 0.18, 0.26}}},
	}
	for layerIndex, layer in ipairs(layers) do
		for peakIndex, peak in ipairs(layer.peaks) do
			Parts.peak(range, string.format("Peak%d_%d", layerIndex, peakIndex), peak[1], peak[2], peak[3], peak[4],
				layer.alpha, P.ink, layer.z)
		end
	end
	local mist = create("Frame", range, {Name = "MotifMist", BorderSizePixel = 0, BackgroundColor3 = P.paper,
		BackgroundTransparency = 0.05, Active = false, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.52, 0.82), Size = UDim2.fromScale(1.1, 0.2), ZIndex = 2})
	create("UIGradient", mist, {Rotation = 90, Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.25), NumberSequenceKeypoint.new(1, 1)})})
	-- The one idle motion on the screen: the mist drifts, very slowly (none under reduced motion).
	kit:loop(mist, {Position = UDim2.new(0.52, 22, 0.82, 0)}, 14)
	return holder
end

-- The 落款 column: the inscription (款) written down the centre, the PLAY seal (印) stamped below it.
-- 七転八起, "fall seven times, rise eight" — an obby's whole philosophy. Only shown where it fits
-- between the header and the seal (not on landscape phones).
local function inscription(background)
	local play = background:FindFirstChild("PlayButton")
	local scenery = background:FindFirstChild("MotifScenery")
	if not play or not scenery then return end
	local label = create("TextLabel", scenery, {Name = "MotifInscription", BackgroundTransparency = 1, Active = false,
		AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(38, 136), Text = "七\n転\n八\n起", TextSize = 26,
		LineHeight = 1.08, TextColor3 = P.nakazumi, TextTransparency = 0.15, TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Bottom, TextWrapped = false, ZIndex = 1})
	kit:setFont(label, "title")
	local function place()
		local _, vh = viewport()
		local sealTop = play.Position.Y.Scale * vh + play.Position.Y.Offset - SEAL_SIZE.Y / 2
		label.Position = UDim2.new(play.Position.X.Scale, play.Position.X.Offset, play.Position.Y.Scale,
			play.Position.Y.Offset - SEAL_SIZE.Y / 2 - 18)
		label.Visible = sealTop - 18 - label.Size.Y.Offset >= headerBottom() + 20
	end
	place()
	pcall(function() workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(place) end)
end

local function topBar(background)
	local top = background:FindFirstChild("TopBar")
	if not top then return end
	top.ZIndex = 2
	kit:clearTopbar(top)
	local title = top:FindFirstChild("Title")
	if title then
		title.TextSize = 30
		title.TextColor3 = P.ink
		kit:setFont(title, "display")
		kit:fitHeading(title, 30, 18)
	end
	local coins = top:FindFirstChild("CoinLabel")
	if coins then
		coins.TextSize = 22
		coins.TextColor3 = P.ink
		kit:setFont(coins, "strong")
		local coin = coins:FindFirstChild("MotifCoin")
		if coin then coin.Size = UDim2.fromOffset(21, 21) end
		placeCoin(coins)
	end
	-- A pale brush line under the title only: the right half of the header stays empty paper.
	Parts.brush(top, "MotifRule", {position = UDim2.new(0, 8, 1, -2), size = UDim2.new(0.46, 0, 0, 5), color = P.ink,
		alpha = 0.55, layers = 3, seed = 91})
end

local function sealButton(background)
	local play = background:FindFirstChild("PlayButton")
	if not play then return end
	play.ZIndex = 3
	play.Size = UDim2.fromOffset(SEAL_SIZE.X, SEAL_SIZE.Y)
	play.Rotation = -1.2 -- stamped by hand
	play.TextSize = 34
	play.TextColor3 = P.white
	Parts.sealFace(play, P.white, {inset = 6, line = 1.5, flecks = 11, fleck = 4, chips = 5, seed = 17})
	-- Uneven paste: the impression is a little lighter in two places (text is paper-coloured, so the
	-- gradient multiplying it changes nothing visible).
	create("UIGradient", play, {Name = "MotifInk", Rotation = 28, Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.1), NumberSequenceKeypoint.new(0.55, 0.01),
		NumberSequenceKeypoint.new(0.85, 0.02), NumberSequenceKeypoint.new(1, 0.14)})})
	-- Stamp-in: the seal is pressed onto the paper when the menu appears (instant with reduced motion).
	local scale = play:FindFirstChild("MotifScale") or create("UIScale", play, {Name = "MotifScale", Scale = 1})
	if not kit:reduceMotion() then
		scale.Scale = 1.08
		play.BackgroundTransparency, play.TextTransparency = 0.6, 0.6
	end
	kit:tween(scale, {Scale = 1}, 0.35, Enum.EasingStyle.Quad)
	kit:tween(play, {BackgroundTransparency = 0, TextTransparency = 0}, 0.35, Enum.EasingStyle.Quad)
end

local function navBar(background)
	local nav = background:FindFirstChild("NavBar")
	if not nav then return end
	nav.ZIndex = 2
	-- Same place and look on desktop; shrinks with narrow screens instead of running off them.
	nav.Size = UDim2.new(1, -32, 0, 64)
	create("UISizeConstraint", nav, {Name = "MotifSize", MaxSize = Vector2.new(560, 64)})
	for _, button in ipairs(nav:GetChildren()) do
		if button:IsA("GuiButton") then
			button.Size = UDim2.new(0.25, -9, 0, 56)
			button.TextSize = 20
			kit:fitHeading(button, 20, 13)
			if button.LayoutOrder > 1 then
				-- Column rule between the characters, as between lines of a letter.
				create("Frame", button, {Name = "MotifColumnRule", BorderSizePixel = 0, BackgroundColor3 = P.usuzumi,
					BackgroundTransparency = 0.45, Active = false, AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.new(0, -6, 0.45, 0), Size = UDim2.fromOffset(1, 26), ZIndex = button.ZIndex})
			end
		end
	end
end

local function pageHeader(page)
	local title = page:FindFirstChild("Title")
	local glyph = PAGE_SEALS[page.Name]
	if title then
		title.TextSize = 26
		title.Position = UDim2.new(0, glyph and 54 or 18, 0, 10)
		title.Size = UDim2.new(1, glyph and -170 or -134, 0, 40)
		kit:setFont(title, "title")
	end
	if glyph then
		-- 引首印: a small seal before the title — the only vermilion on an open page.
		Parts.seal(page, "MotifPageSeal", glyph, 26, SEAL_COLORS, kit:font("strong"),
			{position = UDim2.fromOffset(18, 15), zIndex = page.ZIndex, seed = #page.Name})
	end
	Parts.brush(page, "MotifHeaderRule", {position = UDim2.new(0, 16, 0, 55), size = UDim2.new(1, -32, 0, 4), color = P.ink,
		alpha = 0.55, layers = 3, seed = #page.Name * 7})
	local close = page:FindFirstChild("CloseButton")
	if close then close.Position = UDim2.new(1, -108, 0, 5) end
end

local function pageBody(page)
	local list = page:FindFirstChild("ProductList")
	if list then
		pcall(function()
			list.ScrollBarThickness = 4
			list.ScrollBarImageColor3 = P.usuzumi
			list.ScrollBarImageTransparency = 0.2
		end)
		for _, row in ipairs(list:GetChildren()) do
			if string.match(row.Name, "^Product_") then
				-- A line of a price list: the name, the price written small beneath it, the ink stamp to
				-- the right. Fits from 320 px up without squeezing the name into a column.
				local name, price = row:FindFirstChild("ProductName"), row:FindFirstChild("Price")
				if name then
					name.Position = UDim2.new(0, 14, 0, 6)
					name.Size = UDim2.new(1, -140, 0, 28)
					name.TextYAlignment = Enum.TextYAlignment.Bottom
					kit:fitHeading(name, 18, 12)
				end
				if price then
					price.Position = UDim2.new(0, 14, 0, 34)
					price.Size = UDim2.new(0, 140, 0, 24)
					price.TextSize = 16
					price.TextColor3 = P.nakazumi
					price.TextYAlignment = Enum.TextYAlignment.Top
					local coin = price:FindFirstChild("MotifCoin")
					if coin then
						coin.Size = UDim2.fromOffset(15, 15)
						local pad = price:FindFirstChild("MotifPadding")
						if pad then pad.PaddingLeft = UDim.new(0, 21) end
						placeCoin(price)
					end
				end
			end
		end
	end
	local empty = page:FindFirstChild("Empty")
	if empty then
		empty.TextColor3 = P.muted
		if page.Name == "InventoryPage" then
			-- An empty bag is an ensō: the circle of emptiness.
			Parts.enso(page, "MotifEmpty", {size = UDim2.fromOffset(96, 96), position = UDim2.new(0.5, 0, 0.62, 0), color = P.ink,
				alpha = 0.3, thickness = 12, gap = -45, closed = true, zIndex = page.ZIndex})
		else
			-- Not written yet: a single horizontal stroke (一) waiting on the paper.
			Parts.brush(page, "MotifEmpty", {position = UDim2.new(0.5, 0, 0.62, 0), anchor = Vector2.new(0.5, 0.5),
				size = UDim2.fromOffset(180, 14), rotation = -2, color = P.ink, alpha = 0.3, layers = 5, seed = 404,
				kasure = true, paper = P.panel, zIndex = page.ZIndex})
		end
	end
end

local PAGES = {"ShopPage", "SettingsPage", "InventoryPage", "QuestsPage"}

local function pagesAndVeil(gui, background)
	-- The veil: a thin wash of ink over the room while a scroll hangs in front of it.
	local veil = create("Frame", gui, {Name = "MotifVeil", BorderSizePixel = 0, BackgroundColor3 = P.dim,
		BackgroundTransparency = 0.92, Active = false, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 2})
	background.ZIndex = 1
	local nav = background:FindFirstChild("NavBar")
	local bases = {}
	local function refresh(changed)
		local any = false
		for _, name in ipairs(PAGES) do
			local page = gui:FindFirstChild(name)
			if page and page.Visible then any = true end
			local button = nav and nav:FindFirstChild("Nav_" .. string.gsub(name, "Page$", ""))
			if button then Skin.setSelected(button, page ~= nil and page.Visible == true) end
		end
		-- The moon steps behind the scroll instead of peeking out beside it.
		local enso = background:FindFirstChild("MotifScenery") and background.MotifScenery:FindFirstChild("MotifEnso")
		if enso then enso.Visible = not any end
		if any and not veil.Visible then
			veil.BackgroundTransparency = 1
			veil.Visible = true
			kit:tween(veil, {BackgroundTransparency = 0.92}, 0.3, Enum.EasingStyle.Quad)
		elseif not any then
			veil.Visible = false
		end
		if changed and changed.Visible and bases[changed] then
			-- The scroll settles into place (a few pixels), no bounce.
			changed.Position = bases[changed] + UDim2.fromOffset(0, 10)
			kit:tween(changed, {Position = bases[changed]}, 0.32, Enum.EasingStyle.Quad)
		end
	end
	for _, name in ipairs(PAGES) do
		local page = gui:FindFirstChild(name)
		if page then
			page.ZIndex = 3
			bases[page] = page.Position
			try(pageHeader, page)
			try(pageBody, page)
			page:GetPropertyChangedSignal("Visible"):Connect(function() pcall(refresh, page) end)
		end
	end
	refresh(nil)
end

function Skin.decorate(gui)
	if typeof(gui) ~= "Instance" and type(gui) ~= "table" then return false end
	if gui:FindFirstChild("MotifVeil") then return true end
	pcall(function() gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling end)
	local background = gui:FindFirstChild("Background")
	if not background then return false end
	background.BackgroundColor3 = P.paper
	background.BackgroundTransparency = 0 -- opaque washi: the world's colours stay out of the painting
	try(scenery, background)
	try(topBar, background)
	try(sealButton, background)
	try(inscription, background)
	try(navBar, background)
	try(pagesAndVeil, gui, background)
	pcall(function() kit:selectionRing(gui.Parent, P.ink) end)
	return true
end

return Skin
