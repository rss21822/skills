--!nocheck
-- DeepSeaSkin ("Abyss Lantern"): the 深海探検 (deep-sea expedition) look for obby-rush.
--
-- Motif: an anglerfish's lure light, glowing jellyfish and rising bubbles in dark teal water.
--   * material  dark teal sea-glass lit from inside: bright bioluminescent rims, jelly-glass tiles
--   * shape     round like bubbles and jellyfish bells (24 px panels, pill buttons, bead tentacles)
--   * colour    abyss teal (hue ~180, never navy), lemon lure light = PLAY only, five creature glows
--   * type      LuckiestGuy for short Latin shouts, FredokaOne for headings/buttons, Nunito Bold body
--   * creatures the anglerfish holding its lure over PLAY, jellyfish nav tiles and page mascots
--   * motion    slow: bubbles rise, the lure halo breathes, the fish sways; all off under reduced motion
--
-- Two layers, both presentation only:
--   Skin.apply(Theme)   runtime skin. Recolours Theme.colors in place and wraps Theme.stroke / panel /
--                       label / button, so every screen built through UITheme gets the look.
--                       Idempotent; Skin.restore(Theme) puts the original functions and colours back.
--   Skin.decorate(gui)  hero dressing of the MainMenu ScreenGui (water, fish + lure, dock, pages).
-- Names, parents, callbacks and Visible rules stay exactly as MainMenu builds them
-- (tests/test_main_menu.luau). Everything added is named "Motif*"; every section is pcall-guarded
-- and a failing section removes what it added, so the menu always works.
local Kit = require(script.Parent:WaitForChild("MotifSkinKit"))
local Spec = require(script.Parent:WaitForChild("MotifSpec"))
local TweenService = game:GetService("TweenService")

local kit = Kit.new(Spec)
local P, C = kit.P, kit.candies
local ICONS = Spec.icons or {}
local create = Kit.create
local BORDER = Enum.ApplyStrokeMode.Border

local Skin = {kit = kit, spec = Spec, name = "AbyssLantern"}

-- Each page owns one creature glow: its nav tile, ribbon, rim and mascot share it.
local PAGES = {
	Shop = {candy = "kurage", icon = ICONS.shop or "🐚"},
	Inventory = {candy = "umibotaru", icon = ICONS.inventory or "💎"},
	Quests = {candy = "mendako", icon = ICONS.quests or "🗺️"},
	Settings = {candy = "murasaki", icon = ICONS.settings or "⚙️"},
}
Skin.pages = PAGES
-- Emoji must be Unicode 12 or older (newer ones draw as tofu in Roblox).
local PRODUCT_ICONS = {speed_coil = "🌀", rainbow_trail = "🌈", double_jump = "⏫"}
local SEA_ICONS = {"🐠", "🦑", "🐙", "🐚", "⭐"}
local TOGGLE_ICONS = {Toggle_Music = "🎵", Toggle_SFX = "🔊"}

-- Button state tables from kit:styleButton, so the dressing can repaint (selected nav tile).
local states = setmetatable({}, {__mode = "k"})
Skin.states = states

-- Deep jelly tint of a creature colour (spec pastels, same order as the candies).
local function tintOf(name)
	local index = table.find(kit.candyOrder, name)
	return index and kit.pastels[index] or P.panel
end
Skin.tintOf = tintOf

-- Deterministic 0..1 scatter (no Random: the same layout every time, also under Lune).
local function hash(i, k)
	local v = math.sin(i * 12.9898 + k * 78.233) * 43758.5453
	return v - math.floor(v)
end

local function pageOf(object)
	local node = object
	while node do
		local id = type(node.Name) == "string" and string.match(node.Name, "^(%a+)Page$") or nil
		if id and PAGES[id] then return id end
		node = node.Parent
	end
	return nil
end

-- Bioluminescent glow: a second, thick, translucent stroke. One Instance draws one UIStroke, so the
-- glow lives on a transparent child frame of the same shape (`grow` compensates a UIPadding).
local function glowRing(object, color, radius, thickness, transparency, grow)
	local ring = object:FindFirstChild("MotifGlow") or create("Frame", object, {
		Name = "MotifGlow", BackgroundTransparency = 1, BorderSizePixel = 0, Active = false, ZIndex = object.ZIndex,
	})
	ring.Size = UDim2.new(1, 0, 1, grow or 0)
	local corner = ring:FindFirstChildOfClass("UICorner") or create("UICorner", ring)
	corner.CornerRadius = radius
	local stroke = ring:FindFirstChildOfClass("UIStroke") or create("UIStroke", ring, {Name = "MotifGlowStroke"})
	stroke.ApplyStrokeMode = BORDER
	stroke.Color, stroke.Thickness, stroke.Transparency = color, thickness or 8, transparency or 0.8
	return ring, stroke
end

local function round(object, radius)
	return create("UICorner", object, {CornerRadius = radius or UDim.new(1, 0)})
end

-- Look of a Theme.button by Name (exact name, then Nav_/Toggle_ prefix, then options).
local function lookFor(object, name, options)
	if name == "PlayButton" then
		return {role = "primary", pill = true, font = "title", emoji = ICONS.play}
	end
	local navId = string.match(name, "^Nav_(%a+)$")
	if navId and PAGES[navId] then
		local candy = PAGES[navId].candy
		return {face = tintOf(candy), rim = C[candy], candy = candy, corner = 26, glow = true}
	end
	if name == "CloseButton" then
		return {face = P.outline, rim = P.ink, pill = true}
	end
	if name == "BuyButton" then
		return {role = "umibotaru", pill = true}
	end
	local page = pageOf(object)
	local pageCandy = page and PAGES[page].candy or nil
	if string.match(name, "^Toggle_") then
		local candy = pageCandy or "umibotaru"
		return {face = P.panel, rim = C[candy], candy = candy, corner = 20, toggle = true}
	end
	if options.primary then return {role = "umibotaru"} end
	if options.danger then return {role = "danger"} end
	local index = ((options.order or 0) % #kit.pastels) + 1
	return {role = "plain", rim = C[pageCandy or kit.candyOrder[index]] or P.rim}
end

-- Settings toggles: a bubble knob in a glowing track, driven by the button's own "…: ON/OFF" text.
local function toggleSwitch(button, candy)
	local pad = 60
	create("UIPadding", button, {Name = "MotifPad", PaddingLeft = UDim.new(0, pad)})
	button.TextXAlignment = Enum.TextXAlignment.Left
	local icon = kit:icon(button, TOGGLE_ICONS[button.Name] or "⚙️", 160)
	if icon then icon.Position = UDim2.new(0, 14 - pad, 0.5, -2) end -- children sit inside the padding
	local track = create("Frame", button, {
		Name = "MotifSwitch", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, -2),
		Size = UDim2.fromOffset(62, 30), BorderSizePixel = 0, Active = false, ZIndex = button.ZIndex,
	})
	round(track)
	create("UIStroke", track, {Name = "MotifEdge", ApplyStrokeMode = BORDER, Color = P.outline, Thickness = 2.5})
	local knob = create("Frame", track, {
		Name = "Knob", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(22, 22), BorderSizePixel = 0,
		ZIndex = button.ZIndex, Active = false,
	})
	round(knob)
	local shine = create("Frame", knob, {
		Name = "Shine", Position = UDim2.fromScale(0.2, 0.16), Size = UDim2.fromScale(0.36, 0.36),
		BackgroundColor3 = P.white, BackgroundTransparency = 0.15, BorderSizePixel = 0, ZIndex = button.ZIndex,
	})
	round(shine)
	local function isOn()
		local text = string.upper(tostring(button.Text))
		return string.find(text, "OFF", 1, true) == nil and string.find(text, "ON", 1, true) ~= nil
	end
	local function update(animate)
		local on = isOn()
		track.BackgroundColor3 = on and C[candy] or P.disabled
		knob.BackgroundColor3 = on and P.white or P.muted
		local target = on and UDim2.new(1, -15, 0.5, 0) or UDim2.new(0, 15, 0.5, 0)
		if animate then kit:tween(knob, {Position = target}, 0.18) else knob.Position = target end
		track:SetAttribute("On", on)
	end
	update(false)
	button:GetPropertyChangedSignal("Text"):Connect(function() pcall(update, true) end)
end

local function styleButton(object, name, options)
	local look = lookFor(object, name, options)
	local state = kit:styleButton(object, {
		role = look.role, face = look.face, pill = look.pill, corner = look.corner, font = look.font,
		emoji = look.emoji, order = options.order,
	})
	states[object] = state
	local face = kit.faces[object]
	-- Dark (jelly-glass) faces get a bright creature rim; bright faces keep the dark sticker edge.
	if face and Kit.luminance(face) < 0.5 then
		local edge = object:FindFirstChild("MotifEdge")
		if edge then edge.Color, edge.Thickness = look.rim or P.rim, 3 end
	end
	if look.glow then
		local corner = object:FindFirstChildOfClass("UICorner")
		glowRing(object, C[look.candy] or P.rim, corner and corner.CornerRadius or UDim.new(0, 18), 7, 0.8)
	end
	if look.toggle then
		local gloss = object:FindFirstChild("MotifGloss") -- flat glass: a gloss band reads as a progress bar
		if gloss then gloss:Destroy() end
		object.TextSize = 20
		kit:paint(object, state)
		toggleSwitch(object, look.candy)
	end
	-- UITheme's own hover handlers recolour the fill; repaint after them (handler order is not
	-- guaranteed, so defer to after this input event).
	local function repaint() task.defer(function() kit:paint(object, state) end) end
	object.MouseEnter:Connect(repaint)
	object.MouseLeave:Connect(repaint)
end

local function stylePanel(frame)
	frame.BackgroundTransparency = 0
	kit:panel(frame, {color = P.paper, edge = P.rim, thickness = 3})
end

-- Runtime skin ---------------------------------------------------------------------------------
local REQUIRED = {"create", "corner", "stroke", "panel", "label", "button"}

function Skin.apply(Theme)
	if type(Theme) ~= "table" or type(Theme.colors) ~= "table" then return false end
	for _, key in ipairs(REQUIRED) do
		if type(Theme[key]) ~= "function" then return false end
	end
	if Theme.skin == Skin then return true end -- idempotent: never wrap twice
	local original = {colors = table.clone(Theme.colors), stroke = Theme.stroke, panel = Theme.panel,
		label = Theme.label, button = Theme.button}
	-- 1) Colours in place: modules that captured Theme.colors see the new values.
	local colors = Theme.colors
	colors.background, colors.panel, colors.panelLight = P.abyss, P.paper, P.panel
	colors.accent, colors.text, colors.subtext = P.primary, P.ink, P.muted
	colors.danger, colors.success = P.danger, P.success
	-- 2) Generators: the original builds the Instance (names, callbacks), the skin restyles it.
	Theme.stroke = function(object)
		local stroke = original.stroke(object)
		pcall(function()
			stroke.Name = "MotifEdge" -- the kit restyles this one instead of adding a second stroke
			stroke.ApplyStrokeMode = BORDER
			stroke.Color, stroke.Thickness, stroke.Transparency = P.rim, (Spec.shape or {}).stroke or 3, 0
		end)
		return stroke
	end
	Theme.panel = function(parent, name, size, position)
		local frame = original.panel(parent, name, size, position)
		pcall(stylePanel, frame)
		return frame
	end
	Theme.label = function(parent, name, text, size, options)
		local label = original.label(parent, name, text, size, options)
		pcall(function()
			local bold = type(options) == "table" and options.bold
			kit:setFont(label, (size or 16) >= 24 and "title" or bold and "strong" or "body")
		end)
		return label
	end
	Theme.button = function(parent, name, text, onClick, options)
		local button = original.button(parent, name, text, onClick, options)
		pcall(styleButton, button, name, type(options) == "table" and options or {})
		return button
	end
	Theme.skin, Theme.skinOriginal = Skin, original
	return true
end

-- Put UITheme back exactly as it was (screens built afterwards get the original look).
function Skin.restore(Theme)
	if type(Theme) ~= "table" or Theme.skin ~= Skin or type(Theme.skinOriginal) ~= "table" then return false end
	local original = Theme.skinOriginal
	for key, value in pairs(original.colors) do Theme.colors[key] = value end
	Theme.stroke, Theme.panel, Theme.label, Theme.button = original.stroke, original.panel, original.label, original.button
	Theme.skin, Theme.skinOriginal = nil, nil
	return true
end

-- Run fn; on error remove every Instance it added under root (pre-existing ones stay) and warn.
function Skin.section(root, name, fn)
	local before = {[root] = true}
	for _, object in ipairs(root:GetDescendants()) do before[object] = true end
	local ok, err = pcall(fn)
	if not ok then
		for _, object in ipairs(root:GetDescendants()) do
			if not before[object] and before[object.Parent] then pcall(function() object:Destroy() end) end
		end
		warn(string.format("[DeepSeaSkin] %s skipped: %s", tostring(name), tostring(err)))
	end
	return ok
end

-- Creatures -------------------------------------------------------------------------------------
-- A jellyfish from rounded frames: bell with a frilled margin, glowing core, bead-free tentacles.
-- ghost 0..1 fades the whole animal (background jellies); face adds eyes and blush (page mascots).
local function jellyParts(color, ghost, face)
	local g = ghost or 0
	local function t(value) return value + g * (1 - value) end
	local light = color:Lerp(P.white, 0.5) -- inner glow: the creature's own colour, lifted
	local parts = {
		{"Halo", 0.5, 0.3, 1.2, 0.7, color, transparency = t(0.86)},
		{"TentacleA", 0.25, 0.66, 0.055, 0.5, color, transparency = t(0.3), rotation = 8},
		{"TentacleB", 0.39, 0.7, 0.055, 0.56, color, transparency = t(0.3), rotation = -5},
		{"TentacleC", 0.61, 0.7, 0.055, 0.56, color, transparency = t(0.3), rotation = 5},
		{"TentacleD", 0.75, 0.66, 0.055, 0.5, color, transparency = t(0.3), rotation = -8},
		{"OralArm", 0.5, 0.6, 0.08, 0.38, light, transparency = t(0.35), corner = 0.5},
		{"Bell", 0.5, 0.28, 0.92, 0.5, color, transparency = t(0.15)},
		{"FrillA", 0.2, 0.47, 0.22, 0.1, color, transparency = t(0.15)},
		{"FrillB", 0.4, 0.49, 0.22, 0.1, color, transparency = t(0.15)},
		{"FrillC", 0.6, 0.49, 0.22, 0.1, color, transparency = t(0.15)},
		{"FrillD", 0.8, 0.47, 0.22, 0.1, color, transparency = t(0.15)},
		{"Core", 0.5, 0.19, 0.4, 0.16, light, transparency = t(0.45)},
	}
	if face then
		table.insert(parts, {"EyeL", 0.38, 0.32, 0.09, 0.075, "outline"})
		table.insert(parts, {"EyeR", 0.62, 0.32, 0.09, 0.075, "outline"})
		table.insert(parts, {"BlushL", 0.27, 0.39, 0.12, 0.05, "kurage", transparency = 0.35})
		table.insert(parts, {"BlushR", 0.73, 0.39, 0.12, 0.05, "kurage", transparency = 0.35})
		table.insert(parts, {"Smile", 0.5, 0.38, 0.1, 0.035, "outline", corner = 0.5})
	end
	return parts
end
Skin.jellyParts = jellyParts

local function makeJelly(parent, name, size, candy, options)
	options = options or {}
	local root = kit:mascot(parent, size, jellyParts(C[candy] or P.rim, options.ghost, options.face),
		{name = name, aspect = 1.3, still = true, props = options.props})
	return root
end

-- Hero dressing -----------------------------------------------------------------------------------
local function water(ctx)
	local bg = ctx.background
	bg.BackgroundColor3, bg.BackgroundTransparency = P.white, 0.03
	-- Depth: sunlit teal near the surface, down to near-black teal. Every stop stays in hue ~180,
	-- so the blend never passes through dashboard navy.
	create("UIGradient", bg, {Name = "MotifDepth", Rotation = 90, Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, P.surface), ColorSequenceKeypoint.new(0.42, P.paper), ColorSequenceKeypoint.new(1, P.abyss),
	})})
	-- Light shafts from the surface, fading out with depth.
	local rays = create("Frame", bg, {Name = "MotifRays", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 0.8), Active = false, ZIndex = 1})
	for index, shaft in ipairs({{0.16, 70}, {0.34, 130}, {0.6, 90}, {0.82, 60}}) do
		local beam = create("Frame", rays, {
			Name = "Shaft" .. index, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(shaft[1], 0, -0.12, 0),
			Size = UDim2.new(0, shaft[2], 1.2, 0), Rotation = 14, BackgroundColor3 = P.rim, BorderSizePixel = 0, Active = false, ZIndex = 1,
		})
		create("UIGradient", beam, {Rotation = 90, Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.83), NumberSequenceKeypoint.new(1, 1),
		})})
	end
	-- Marine snow: still flecks drifting in the dark.
	local snow = create("Frame", bg, {Name = "MotifSnow", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Active = false, ZIndex = 1})
	for i = 1, 38 do
		local size = 2 + math.floor(hash(i, 3) * 3)
		local fleck = create("Frame", snow, {
			Name = "Fleck", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(hash(i, 1), 0.1 + hash(i, 2) * 0.88),
			Size = UDim2.fromOffset(size, size), BackgroundColor3 = P.ink, BackgroundTransparency = 0.5 + hash(i, 4) * 0.35,
			BorderSizePixel = 0, Active = false, ZIndex = 1,
		})
		round(fleck)
	end
	-- Rising bubbles: hollow rings with a highlight. Static and scattered under reduced motion.
	local bubbles = create("Frame", bg, {Name = "MotifBubbles", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true, Active = false, ZIndex = 1})
	local calm = kit:reduceMotion()
	for i = 1, 14 do
		local size = 8 + math.floor(hash(i, 5) * 14)
		local x = 0.04 + hash(i, 6) * 0.92
		local bubble = create("Frame", bubbles, {
			Name = "Bubble", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(size, size),
			Position = calm and UDim2.fromScale(x, 0.18 + hash(i, 7) * 0.7) or UDim2.new(x, 0, 1, size),
			BackgroundColor3 = P.rim, BackgroundTransparency = 0.86, BorderSizePixel = 0, Active = false, ZIndex = 1,
		})
		round(bubble)
		create("UIStroke", bubble, {ApplyStrokeMode = BORDER, Color = P.ink, Thickness = size >= 14 and 2 or 1.5, Transparency = 0.35})
		local shine = create("Frame", bubble, {Name = "Shine", Position = UDim2.fromScale(0.2, 0.18), Size = UDim2.fromScale(0.32, 0.32),
			BackgroundColor3 = P.white, BackgroundTransparency = 0.15, BorderSizePixel = 0, Active = false, ZIndex = 1})
		round(shine)
		if not calm then
			local ok, tween = pcall(function()
				local rise = TweenService:Create(bubble, TweenInfo.new(9 + hash(i, 8) * 8, Enum.EasingStyle.Linear,
					Enum.EasingDirection.InOut, -1, false, hash(i, 9) * 9), {Position = UDim2.new(x + (hash(i, 10) - 0.5) * 0.06, 0, 0, -size)})
				rise:Play()
				return rise
			end)
			if ok and tween then table.insert(ctx.loops, tween) end
		end
	end
	-- Two big ghostly jellyfish far away in the water.
	ctx.jellyA = makeJelly(bg, "MotifJellyA", 118, "kurage", {ghost = 0.5, props = {Position = UDim2.new(0.1, 0, 0.44, 0), ZIndex = 1}})
	ctx.jellyB = makeJelly(bg, "MotifJellyB", 88, "murasaki", {ghost = 0.55, props = {Position = UDim2.new(0.9, 0, 0.74, 0), ZIndex = 1}})
	for _, jelly in ipairs({ctx.jellyA, ctx.jellyB}) do
		if jelly then create("UIScale", jelly, {Name = "MotifMascotScale"}) end
	end
end

local function topBar(ctx)
	local top = ctx.background:FindFirstChild("TopBar")
	if not top then return end
	-- No full-width header strip (the most "dashboard" shape there is): the bar becomes an invisible
	-- row and the title floats in the water as a glowing sign next to a porthole.
	top.ZIndex, top.BackgroundTransparency = 3, 1
	local topEdge = top:FindFirstChild("MotifEdge")
	if topEdge then topEdge.Transparency = 1 end
	-- A brass-rimmed porthole with the expedition's pufferfish.
	local port = kit:badge(top, "MotifPorthole", ICONS.title or "🐡", P.surface, 54,
		{AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), ZIndex = 3})
	ctx.port = port
	if port then
		local rim = port:FindFirstChildOfClass("UIStroke")
		if rim then rim.Color, rim.Thickness = P.gold, 4 end
		for _, degrees in ipairs({45, 135, 225, 315}) do
			local angle = math.rad(degrees)
			local rivet = create("Frame", port, {
				Name = "Rivet", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(6, 6),
				Position = UDim2.fromScale(0.5 + 0.5 * math.cos(angle), 0.5 + 0.5 * math.sin(angle)),
				BackgroundColor3 = P.gold, BorderSizePixel = 0, Active = false, ZIndex = 3,
			})
			round(rivet)
		end
	end
	local title = top:FindFirstChild("Title")
	ctx.title = title
	if title then
		title.Position, title.Size = UDim2.new(0, 78, 0, 2), UDim2.new(1, -240, 1, -4)
		title.TextColor3, title.TextSize, title.Rotation, title.ZIndex = P.white, 42, -3, 3
		kit:setFont(title, "display")
		kit:outline(title, 3.5, C.kurage) -- white type with a pink bioluminescent edge
		kit:fitHeading(title, 42, 16)
	end
	local coins = top:FindFirstChild("CoinLabel")
	if coins then
		coins.AnchorPoint, coins.Position = Vector2.new(1, 0.5), UDim2.new(1, -12, 0.5, 0)
		coins.Size, coins.AutomaticSize = UDim2.fromOffset(112, 42), Enum.AutomaticSize.X
		coins.TextXAlignment, coins.TextWrapped, coins.TextSize = Enum.TextXAlignment.Center, false, 20
		coins.BackgroundColor3, coins.BackgroundTransparency, coins.TextColor3, coins.ZIndex = P.outline, 0, P.ink, 3
		kit:setFont(coins, "title")
		round(coins)
		create("UIStroke", coins, {Name = "MotifEdge", ApplyStrokeMode = BORDER, Color = P.gold, Thickness = 3})
		create("UIPadding", coins, {Name = "MotifPad", PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16)})
	end
end

local function lure(ctx)
	local bg = ctx.background
	local play = bg:FindFirstChild("PlayButton")
	if not play then return end
	ctx.play = play
	local tilt = (Spec.shape or {}).tilt or -2
	play.Size, play.TextSize, play.Rotation, play.ZIndex = UDim2.fromOffset(300, 84), 34, tilt, 4
	if states[play] then kit:paint(play, states[play]) end
	-- Glass-bulb shine (the kit's gloss is off on very bright faces).
	local shine = create("Frame", play, {Name = "MotifShine", Position = UDim2.new(0, 26, 0, 9), Size = UDim2.new(0.34, 0, 0, 12),
		BackgroundColor3 = P.white, BackgroundTransparency = 0.45, BorderSizePixel = 0, Active = false, ZIndex = play.ZIndex})
	round(shine)
	-- The lure light: the bulb's glow pools live on the fish (spec parts LureGlow*); the sign gets a
	-- breathing halo ring.
	local function pill(name, width, height, transparency, z)
		local frame = create("Frame", bg, {
			Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = play.Position, Size = UDim2.fromOffset(width, height),
			Rotation = tilt, BackgroundColor3 = P.primary, BackgroundTransparency = transparency, BorderSizePixel = 0,
			Active = false, ZIndex = z,
		})
		round(frame)
		return frame
	end
	local halo = pill("MotifPlayHalo", 324, 106, 0.84, 3)
	ctx.halo = halo
	local ring = create("UIStroke", halo, {Name = "MotifHaloRing", ApplyStrokeMode = BORDER, Color = P.primary, Thickness = 3, Transparency = 0.45})
	local breathe = kit:loop(ring, {Thickness = 8, Transparency = 0.08}, 1.8)
	if breathe then table.insert(ctx.loops, breathe) end
	-- "DIVE!" sticker slapped on the corner of the sign.
	local tag = create("Frame", bg, {
		Name = "MotifDiveTag", AnchorPoint = Vector2.new(0.5, 0.5), Position = play.Position + UDim2.fromOffset(128, -46),
		Size = UDim2.fromOffset(96, 36), Rotation = 7, BackgroundColor3 = C.kurage, BorderSizePixel = 0, Active = false, ZIndex = 5,
	})
	round(tag)
	ctx.tag = tag
	create("UIStroke", tag, {Name = "MotifEdge", ApplyStrokeMode = BORDER, Color = P.outline, Thickness = 3})
	local label = create("TextLabel", tag, {Name = "Label", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Text = "DIVE!",
		TextSize = 22, TextColor3 = P.white, Active = false, ZIndex = 5})
	kit:setFont(label, "display")
	kit:outline(label, 2.5)
	-- The anglerfish, holding its lure up next to PLAY.
	local mascot = Spec.mascot
	if mascot then
		local fish, parts = kit:mascot(bg, 150, mascot.parts, {name = "MotifAngler", aspect = mascot.aspect, still = true, props = {ZIndex = 3}})
		if fish then
			create("UIScale", fish, {Name = "MotifMascotScale"})
			for _, name in ipairs({"Body", "Tail", "FinTop", "FinSide"}) do
				local stroke = parts[name] and parts[name]:FindFirstChildOfClass("UIStroke")
				if stroke then stroke.Color, stroke.Thickness = P.anglerRim, 3 end -- rim light from the lure
			end
			for name, thickness in pairs({Eye = 2.5, Bulb = 2}) do
				local stroke = parts[name] and parts[name]:FindFirstChildOfClass("UIStroke")
				if stroke then stroke.Thickness = thickness end
			end
			local sway = kit:loop(fish, {Rotation = 3}, 2.6)
			if sway then table.insert(ctx.loops, sway) end
			local eye = parts.Eye
			if eye and not kit:reduceMotion() then
				task.spawn(function()
					while fish.Parent do
						task.wait(2.8 + (os.clock() % 1.9))
						if not fish.Parent then break end
						if ctx.showing() and fish.Visible then
							local size = eye.Size
							eye.Size = UDim2.fromScale(size.X.Scale, size.Y.Scale * 0.15)
							task.wait(0.12)
							eye.Size = size
						end
					end
				end)
			end
			ctx.fish = fish
		end
	end
end

local function jellyTile(tile, id, page)
	local color = C[page.candy]
	local pad = 12
	tile.Size, tile.ZIndex, tile.TextSize = UDim2.new(0.25, -9, 1, 0), 9, 17
	tile.TextYAlignment, tile.TextWrapped = Enum.TextYAlignment.Bottom, false
	create("UIPadding", tile, {Name = "MotifPad", PaddingBottom = UDim.new(0, pad)})
	-- The padding shrinks the content box that children are laid out in: full-height parts add `pad`.
	local corner = tile:FindFirstChildOfClass("UICorner")
	glowRing(tile, color, corner and corner.CornerRadius or UDim.new(0, 26), 7, 0.8, pad)
	create("TextLabel", tile, {
		Name = "MotifTileIcon", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 5), Size = UDim2.fromOffset(38, 38),
		BackgroundTransparency = 1, Text = page.icon, TextSize = 24, TextColor3 = P.white, Active = false, ZIndex = 9,
	})
	-- Three strands of glowing beads hanging under the bell.
	local strands = create("Frame", tile, {
		Name = "MotifTentacles", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, pad + 2),
		Size = UDim2.new(0.66, 0, 0, 22), BackgroundTransparency = 1, Active = false, ZIndex = 9,
	})
	for strand, x in ipairs({0, 0.5, 1}) do
		for bead = 1, 3 do
			local size = 8 - bead * 1.5
			local dot = create("Frame", strands, {
				Name = "Bead", AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(x, ((bead + strand) % 2 == 0) and 2 or -2, 0, (bead - 1) * 7),
				Size = UDim2.fromOffset(size, size), BackgroundColor3 = color, BackgroundTransparency = 0.05 + bead * 0.2,
				BorderSizePixel = 0, Active = false, ZIndex = 9,
			})
			round(dot)
		end
	end
	local glow = tile:FindFirstChild("MotifGlow")
	local stroke = glow and glow:FindFirstChildOfClass("UIStroke")
	if stroke then
		tile.MouseEnter:Connect(function() kit:tween(stroke, {Transparency = 0.45}, 0.15) end)
		tile.MouseLeave:Connect(function() kit:tween(stroke, {Transparency = 0.8}, 0.2) end)
	end
end

local function dock(ctx)
	local nav = ctx.background:FindFirstChild("NavBar")
	if not nav then return end
	nav.ZIndex, nav.Size, nav.Position = 9, UDim2.new(1, -24, 0, 76), UDim2.new(0.5, 0, 1, -34)
	ctx.nav = nav
	ctx.navMax = create("UISizeConstraint", nav, {Name = "MotifMaxWidth", MaxSize = Vector2.new(600, 76)})
	for id, page in pairs(PAGES) do
		local tile = nav:FindFirstChild("Nav_" .. id)
		if tile then
			jellyTile(tile, id, page)
			ctx.tiles[id] = tile
		end
	end
end

local function dressRow(row, color, icon)
	row.BackgroundColor3 = P.panel
	local edge = row:FindFirstChild("MotifEdge")
	if edge then edge.Color, edge.Thickness = color, 2.5 end
	local chip = kit:badge(row, "MotifChip", icon, P.outline, 44, {AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0)})
	local chipEdge = chip and chip:FindFirstChildOfClass("UIStroke")
	if chipEdge then chipEdge.Color = color end
	local name = row:FindFirstChild("ProductName")
	if name then
		name.Position, name.Size = UDim2.new(0, 64, 0, 7), UDim2.new(1, -184, 0, 26)
		kit:setFont(name, "strong")
		kit:fitHeading(name, 19, 12)
	end
	local price = row:FindFirstChild("Price")
	if price then
		price.Position, price.Size, price.TextSize, price.TextColor3 = UDim2.new(0, 64, 0, 34), UDim2.new(1, -184, 0, 22), 16, P.gold
		kit:setFont(price, "title")
	end
end

local CONTENT_TOP = 76

local function dressPage(ctx, frame, id, page)
	local color = C[page.candy]
	frame.ZIndex, frame.Active = 10, true -- above the menu; clicks on the page do not reach PLAY below
	local edge = frame:FindFirstChild("MotifEdge")
	if edge then edge.Color, edge.Thickness = color, 3.5 end
	local radius = UDim.new(0, (Spec.shape or {}).panelCorner or 24)
	glowRing(frame, color, radius, 9, 0.76)
	-- Ribbon in the page's creature colour: rounded top, square bottom, ink rule, bubble dots.
	local ribbon = create("Frame", frame, {Name = "MotifRibbon", Size = UDim2.new(1, 0, 0, 62), BackgroundColor3 = color,
		BorderSizePixel = 0, Active = false, ZIndex = 2})
	create("UICorner", ribbon, {CornerRadius = radius})
	create("Frame", ribbon, {Name = "MotifSquare", Size = UDim2.new(1, 0, 0.5, 0), Position = UDim2.fromScale(0, 0.5),
		BackgroundColor3 = color, BorderSizePixel = 0, Active = false, ZIndex = 2})
	create("Frame", ribbon, {Name = "MotifRule", Size = UDim2.new(1, 0, 0, 4), Position = UDim2.fromScale(0, 1),
		BackgroundColor3 = P.outline, BorderSizePixel = 0, Active = false, ZIndex = 2})
	kit:dots(ribbon, {name = "MotifRibbonBubbles", columns = 8, rows = 2, size = 7, transparency = 0.72, color = P.white, zIndex = 2})
	local badge = kit:badge(frame, "MotifPageBadge", page.icon, P.surface, 50, {Position = UDim2.fromOffset(12, 6), Rotation = -8, ZIndex = 3})
	local badgeEdge = badge and badge:FindFirstChildOfClass("UIStroke")
	if badgeEdge then badgeEdge.Color, badgeEdge.Thickness = P.gold, 4 end
	local title = frame:FindFirstChild("Title")
	if title then
		title.Position, title.Size = UDim2.new(0, 72, 0, 11), UDim2.new(1, -190, 0, 40)
		title.TextColor3, title.ZIndex = P.white, 3
		kit:setFont(title, "title")
		kit:outline(title, 3)
		kit:fitHeading(title, 30, 16)
	end
	local close = frame:FindFirstChild("CloseButton")
	if close then close.ZIndex = 3 end
	-- Content starts under the ribbon.
	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("GuiButton") and string.match(child.Name, "^Toggle_") then
			child.Position = UDim2.new(child.Position.X.Scale, child.Position.X.Offset, 0, child.Position.Y.Offset + (CONTENT_TOP - 64))
		end
	end
	local list = frame:FindFirstChild("ProductList")
	if list then
		list.Position, list.Size = UDim2.new(0, 16, 0, CONTENT_TOP), UDim2.new(1, -32, 1, -(CONTENT_TOP + 14))
		list.ScrollBarImageColor3, list.ScrollBarThickness = color, 6
		create("UIPadding", list, {Name = "MotifPad", PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4)})
		local rows = {}
		for _, row in ipairs(list:GetChildren()) do
			if row:IsA("GuiObject") and string.match(row.Name, "^Product_") then table.insert(rows, row) end
		end
		table.sort(rows, function(a, b) return (a.LayoutOrder or 0) < (b.LayoutOrder or 0) end)
		for index, row in ipairs(rows) do
			local candy = kit.candyOrder[((index - 1) % #kit.candyOrder) + 1]
			local productId = string.sub(row.Name, 9)
			dressRow(row, C[candy], PRODUCT_ICONS[productId] or SEA_ICONS[((index - 1) % #SEA_ICONS) + 1])
		end
	end
	local empty = frame:FindFirstChild("Empty")
	if empty then
		empty.Position, empty.Size = UDim2.new(0, 16, 0, CONTENT_TOP + 4), UDim2.new(1, -32, 0, 28)
		empty.TextXAlignment = Enum.TextXAlignment.Center
		ctx.emptyJellies[frame] = makeJelly(frame, "MotifEmptyJelly", 96, page.candy,
			{face = true, props = {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, CONTENT_TOP + 42), ZIndex = 2}})
	end
end

local function pages(ctx)
	local scrim = create("Frame", ctx.background, {Name = "MotifScrim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = P.dim,
		BackgroundTransparency = 0.35, BorderSizePixel = 0, Visible = false, Active = true, ZIndex = 8})
	create("UIGradient", scrim, {Rotation = 90, Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0)})})
	for id, page in pairs(PAGES) do
		local frame = ctx.gui:FindFirstChild(id .. "Page")
		if frame then
			ctx.pages[id] = frame
			dressPage(ctx, frame, id, page)
		end
	end
	-- One sync for the scrim and the selected jelly tile, run whenever a page shows or hides.
	local function sync()
		local open = false
		for id, page in pairs(PAGES) do
			local frame = ctx.pages[id]
			local shown = frame ~= nil and frame.Visible == true
			open = open or shown
			local tile = ctx.tiles[id]
			if tile and states[tile] then
				kit.faces[tile] = shown and C[page.candy] or tintOf(page.candy)
				local edge = tile:FindFirstChild("MotifEdge")
				if edge then edge.Color = shown and P.outline or C[page.candy] end
				kit:paint(tile, states[tile])
				tile:SetAttribute("Selected", shown)
			end
		end
		scrim.Visible = open
	end
	for _, frame in pairs(ctx.pages) do
		frame:GetPropertyChangedSignal("Visible"):Connect(function() pcall(sync) end)
	end
	sync()
end

-- Phone and short screens: pages widen, the fish moves above PLAY or steps aside.
local function responsive(ctx)
	local bg = ctx.background
	local function apply()
		local size = bg.AbsoluteSize
		local width, height = size.X, size.Y
		local narrow, short = width < 700, height < 480
		-- Short (landscape phone): PLAY rises and the dock drops so the halo clears the jelly tiles.
		local playY = short and not narrow and 0.5 or 0.55
		if ctx.play then
			ctx.play.Position = UDim2.new(0.5, 0, playY, 0)
			if ctx.halo then ctx.halo.Position = ctx.play.Position end
			if ctx.tag then ctx.tag.Position = ctx.play.Position + UDim2.fromOffset(128, -46) end
		end
		if ctx.nav then
			local navHeight = short and 72 or 76
			ctx.nav.Size, ctx.nav.Position = UDim2.new(1, -24, 0, navHeight), UDim2.new(0.5, 0, 1, short and -24 or -34)
			if ctx.navMax then ctx.navMax.MaxSize = Vector2.new(600, navHeight) end
		end
		-- Phone width: the porthole steps aside so the title keeps a readable size.
		if ctx.port then ctx.port.Visible = not narrow end
		if ctx.title then
			ctx.title.Position = UDim2.new(0, narrow and 12 or 78, 0, 2)
			ctx.title.Size = UDim2.new(1, narrow and -150 or -240, 1, -4)
		end
		local pageHeight
		for _, frame in pairs(ctx.pages) do
			if narrow then
				frame.Size, frame.Position = UDim2.new(1, -24, 1, -214), UDim2.new(0, 12, 0, 92)
				pageHeight = height - 214
			elseif short then
				frame.Size, frame.Position = UDim2.new(0.6, 0, 1, -192), UDim2.new(0.2, 0, 0, 88)
				pageHeight = height - 192
			else
				frame.Size, frame.Position = UDim2.new(0.6, 0, 0.62, 0), UDim2.new(0.2, 0, 0.16, 0)
				pageHeight = height * 0.62
			end
		end
		for _, jelly in pairs(ctx.emptyJellies) do
			jelly.Visible = (pageHeight or 0) >= 260
		end
		local fish = ctx.fish
		local scale = fish and fish:FindFirstChild("MotifMascotScale")
		if fish and scale then
			-- Lure bulb sits 90 px right of / 130 px above the fish's anchor (bottom centre) at scale 1.
			if not narrow then
				local s = short and 0.75 or 1
				scale.Scale, fish.Visible = s, true
				fish.Position = UDim2.new(0.5, math.floor(-164 - 90 * s), playY, math.floor(-50 + 129.6 * s))
			elseif height >= 600 then
				scale.Scale, fish.Visible = 0.8, true
				fish.Position = UDim2.new(0.5, -70, 0.55, -50)
			else
				fish.Visible = false
			end
		end
		-- Background jellies drift to where they do not sit behind the title, the fish or the dock.
		local function placeJelly(jelly, scale, position, visible)
			if not jelly then return end
			local jellyScale = jelly:FindFirstChild("MotifMascotScale")
			if jellyScale then jellyScale.Scale = scale end
			jelly.Position, jelly.Visible = position, visible
		end
		if narrow then
			placeJelly(ctx.jellyA, 0.7, UDim2.new(0.13, 0, 0.3, 0), true)
			placeJelly(ctx.jellyB, 0.7, UDim2.new(0.84, 0, 0.82, 0), height >= 700)
		elseif short then
			placeJelly(ctx.jellyA, 0.6, UDim2.new(0.07, 0, 0.92, 0), true)
			placeJelly(ctx.jellyB, 0.7, UDim2.new(0.92, 0, 0.5, 0), true)
		else
			placeJelly(ctx.jellyA, 1, UDim2.new(0.1, 0, 0.44, 0), true)
			placeJelly(ctx.jellyB, 1, UDim2.new(0.9, 0, 0.74, 0), true)
		end
	end
	bg:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() pcall(apply) end)
	apply()
end

-- Loops pause while the menu is not on screen.
local function motion(ctx)
	local function sync()
		local on = ctx.showing()
		for _, tween in ipairs(ctx.loops) do
			pcall(function() if on then tween:Play() else tween:Pause() end end)
		end
	end
	ctx.gui:GetPropertyChangedSignal("Enabled"):Connect(sync)
	ctx.background:GetPropertyChangedSignal("Visible"):Connect(sync)
end

-- Dress the MainMenu ScreenGui. Returns {section = ok} (nil when there is nothing to dress).
function Skin.decorate(gui)
	if not gui or gui:GetAttribute("MotifSkin") == Skin.name then return nil end
	local background = gui:FindFirstChild("Background")
	if not background then return nil end
	gui:SetAttribute("MotifSkin", Skin.name)
	pcall(function() gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling end)
	local ctx = {gui = gui, background = background, loops = {}, tiles = {}, pages = {}, emptyJellies = {}}
	function ctx.showing() return gui.Enabled ~= false and background.Visible ~= false end
	local report = {}
	for _, step in ipairs({{"water", water}, {"topBar", topBar}, {"lure", lure}, {"dock", dock},
		{"pages", pages}, {"responsive", responsive}, {"motion", motion}}) do
		report[step[1]] = Skin.section(gui, step[1], function() step[2](ctx) end)
	end
	Skin.lastContext, Skin.lastReport = ctx, report
	return report
end

return Skin
