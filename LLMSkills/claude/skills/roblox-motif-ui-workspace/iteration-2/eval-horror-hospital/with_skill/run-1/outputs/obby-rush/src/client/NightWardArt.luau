-- NIGHT WARD: the motif layer of the main menu (escape from an abandoned hospital at night).
--
-- World-in-the-UI mapping:
--   call to action -> the green 非常口 (emergency exit) light box, glowing, with a runner pictogram
--   panels         -> yellowed patient charts on a clipboard (steel clip, ruled lines, typed header)
--   dock           -> enamel room-number door plates with an indicator lamp (lit = page open)
--   backdrop       -> a corridor at 2 a.m.: tiled wainscot and handrail, two ward doors, a faint
--                     fluorescent spill that dips now and then, a drifting flashlight pool
--
-- Scary but for children: darkness, stillness and slow light only. No blood, injury, needles or
-- faces; no jump scares; light dips are single and >= 4.5 s apart (well under 3 Hz); every loop
-- stops under reduced motion and while the menu is hidden.
--
-- Everything here only adds children named "Motif..." or changes presentation properties. Names,
-- hierarchy and callbacks of the menu contract are never touched, and MainMenu calls each step in
-- pcall, so a failure here leaves the plain themed menu working.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UITheme"))

local C = Theme.colors
local kit = Theme.kit
local Art = {}

-- Z order inside Background (Sibling mode): backdrop 1-6, menu content 10.
local Z = {wash = 1, pool = 2, wall = 2, rail = 3, door = 4, vignette = 5, glow = 6, content = 10}

local function make(className, parent, props)
	local object = Instance.new(className)
	for key, value in pairs(props or {}) do object[key] = value end
	object.Parent = parent
	return object
end

local function merge(base, extra)
	for key, value in pairs(extra or {}) do base[key] = value end
	return base
end

-- Decoration frames never take input.
local function deco(parent, name, props)
	return make("Frame", parent, merge({Name = name, BorderSizePixel = 0, Active = false}, props))
end

local function round(object, pixels)
	return make("UICorner", object, {CornerRadius = pixels and UDim.new(0, pixels) or UDim.new(1, 0)})
end

local function line(object, color, thickness, transparency, name)
	return make("UIStroke", object, {Name = name or "MotifLine", ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = color, Thickness = thickness or 2, Transparency = transparency or 0})
end

local function text(parent, name, value, size, color, role, props)
	local label = make("TextLabel", parent, merge({Name = name, Text = value, TextSize = size, TextColor3 = color,
		BackgroundTransparency = 1, BorderSizePixel = 0, Active = false, TextWrapped = false, Font = Theme.fontBold,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center}, props))
	Theme.setFont(label, role)
	return label
end

local function reduced()
	return kit ~= nil and kit:reduceMotion()
end

local function tween(object, props, seconds)
	if kit then return kit:tween(object, props, seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) end
	for key, value in pairs(props) do object[key] = value end
	return nil
end

local function gradient(parent, rotation, from, to)
	return make("UIGradient", parent, {Rotation = rotation, Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, from), NumberSequenceKeypoint.new(1, to)})})
end

-- Backdrop ----------------------------------------------------------------------------------------
function Art.corridor(background)
	local r = {doors = {}}
	-- Fluorescent spill from the ceiling (dips now and then, see Art.motion).
	r.wash = deco(background, "MotifFluorescent", {Size = UDim2.fromScale(1, 0.7), BackgroundColor3 = C.fluoro, ZIndex = Z.wash})
	make("UIGradient", r.wash, {Rotation = 90, Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(0.45, 0.94), NumberSequenceKeypoint.new(1, 1)})})
	local fixture = deco(background, "MotifTube", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 3),
		Size = UDim2.fromOffset(300, 12), BackgroundColor3 = C.panel, ZIndex = Z.wash})
	round(fixture, 3)
	r.tube = deco(fixture, "Tube", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.new(1, -16, 0, 5), BackgroundColor3 = C.fluoro:Lerp(C.text, 0.6)})
	round(r.tube)

	-- Flashlight pool: the container is placed by the layout, the inner drift moves slowly.
	r.pool = deco(background, "MotifFlashlight", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(760, 760), BackgroundTransparency = 1, ZIndex = Z.pool})
	r.drift = deco(r.pool, "Drift", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1})
	for index, scale in ipairs({1, 0.86, 0.72, 0.59, 0.47, 0.36}) do
		round(deco(r.drift, "Beam" .. index, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(scale, scale), BackgroundColor3 = C.flashlight, BackgroundTransparency = 0.968}))
	end

	-- Tiled wainscot with a handrail, like every ward corridor.
	local wainscot = deco(background, "MotifWainscot", {Position = UDim2.fromScale(0, 0.66), Size = UDim2.fromScale(1, 0.34),
		BackgroundColor3 = C.background:Lerp(C.edge, 0.13), ZIndex = Z.wall})
	for index = 1, 15 do
		deco(wainscot, "Grout", {Position = UDim2.new(index / 16, -1, 0, 0), Size = UDim2.new(0, 2, 1, 0),
			BackgroundColor3 = C.dim, BackgroundTransparency = 0.45})
	end
	for index = 1, 2 do
		deco(wainscot, "Grout", {Position = UDim2.new(0, 0, index / 3, -1), Size = UDim2.new(1, 0, 0, 2),
			BackgroundColor3 = C.dim, BackgroundTransparency = 0.45})
	end
	local rail = deco(background, "MotifHandrail", {Position = UDim2.new(0, 0, 0.66, -12), Size = UDim2.new(1, 0, 0, 14),
		BackgroundColor3 = C.panel:Lerp(C.edge, 0.4), ZIndex = Z.rail})
	deco(rail, "Shine", {Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = C.edge:Lerp(C.fluoro, 0.35)})
	deco(rail, "Shadow", {Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 5), BackgroundColor3 = C.dim, BackgroundTransparency = 0.35})
	for index = 1, 5 do
		deco(background, "MotifRailBracket", {Position = UDim2.new((index - 0.5) / 5, -5, 0.66, 2), Size = UDim2.fromOffset(10, 18),
			BackgroundColor3 = C.panel, ZIndex = Z.rail})
	end

	-- Two ward doors at the edges; light leaks from the one on the right.
	for _, side in ipairs({{x = 0.025, anchor = 0, room = "401", leak = false}, {x = 0.975, anchor = 1, room = "402", leak = true}}) do
		local door = deco(background, "MotifDoor", {AnchorPoint = Vector2.new(side.anchor, 1), Position = UDim2.fromScale(side.x, 1),
			Size = UDim2.new(0, 132, 0.68, 0), BackgroundColor3 = C.background:Lerp(C.panel, 0.7), ZIndex = Z.door})
		line(door, C.panel:Lerp(C.edge, 0.55), 4)
		local window = deco(door, "Window", {Position = UDim2.fromScale(0.2, 0.08), Size = UDim2.fromScale(0.6, 0.2),
			BackgroundColor3 = C.fluoro, BackgroundTransparency = side.leak and 0.72 or 0.86})
		line(window, C.dim, 3)
		deco(window, "Wire", {Position = UDim2.new(0.5, -1, 0, 0), Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = C.dim, BackgroundTransparency = 0.4})
		deco(window, "Wire", {Position = UDim2.new(0, 0, 0.5, -1), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = C.dim, BackgroundTransparency = 0.4})
		local plate = deco(door, "Plate", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.33),
			Size = UDim2.fromOffset(54, 20), BackgroundColor3 = C.panelLight, BackgroundTransparency = 0.5})
		text(plate, "Room", side.room, 13, C.ink, "display", {Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 0.3})
		deco(door, "Handle", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(side.anchor == 0 and 0.84 or 0.16, 0.55),
			Size = UDim2.fromOffset(8, 28), BackgroundColor3 = C.steel, BackgroundTransparency = 0.55})
		if side.leak then
			deco(door, "LightLeak", {Position = UDim2.new(0, -4, 0, 6), Size = UDim2.new(0, 4, 1, -6), BackgroundColor3 = C.fluoro, BackgroundTransparency = 0.4})
		end
		table.insert(r.doors, door)
	end

	-- Darker edges so the eye falls on the lit middle.
	for _, v in ipairs({
		{UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.24), 90},
		{UDim2.fromScale(0, 0.7), UDim2.fromScale(1, 0.3), 270},
		{UDim2.fromScale(0, 0), UDim2.fromScale(0.18, 1), 0},
		{UDim2.fromScale(0.82, 0), UDim2.fromScale(0.18, 1), 180},
	}) do
		gradient(deco(background, "MotifVignette", {Position = v[1], Size = v[2], BackgroundColor3 = C.dim, ZIndex = Z.vignette}), v[3], 0.15, 1)
	end
	return r
end

-- The voice line above the exit sign.
function Art.hero(background)
	local r = {}
	r.kicker = text(background, "MotifKicker", "02:13 AM   —   WARD 4F   —   LIGHTS OUT", 18, C.fluoro, "display",
		{AnchorPoint = Vector2.new(0.5, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = Z.content, TextTransparency = 0.1})
	r.headline = text(background, "MotifHeadline", "夜明けまでに、非常口へ。", 46, C.text, "strong",
		{AnchorPoint = Vector2.new(0.5, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = Z.content})
	return r
end

-- Top bar = the ward's enamel signboard; coins on the reception number display.
function Art.coinToken(parent, size, position)
	local rim = C.amber:Lerp(C.ink, 0.5)
	local token = deco(parent, "MotifCoinToken", {AnchorPoint = Vector2.new(0, 0.5), Position = position,
		Size = UDim2.fromOffset(size, size), BackgroundColor3 = C.amber:Lerp(C.board, 0.25)})
	round(token)
	line(token, rim, 2)
	local ring = deco(token, "Ring", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.56, 0.56), BackgroundTransparency = 1})
	round(ring)
	line(ring, rim, 1.5)
	return token
end

function Art.wardSign(top, title, coins)
	local r = {}
	top.BackgroundColor3 = C.panel
	local inner = deco(top, "MotifPinstripe", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -10, 1, -10), BackgroundTransparency = 1})
	round(inner, 2)
	line(inner, C.edge, 1)
	for _, corner in ipairs({{0, 0}, {1, 0}, {0, 1}, {1, 1}}) do
		local screw = deco(top, "MotifScrew", {AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(corner[1], corner[1] == 0 and 11 or -11, corner[2], corner[2] == 0 and 11 or -11),
			Size = UDim2.fromOffset(7, 7), BackgroundColor3 = C.steel:Lerp(C.panel, 0.4)})
		round(screw)
		deco(screw, "Slot", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = C.panel, Rotation = 35})
	end
	title.TextColor3 = C.text
	title.TextYAlignment = Enum.TextYAlignment.Bottom
	Theme.setFont(title, "display")
	r.subtitle = text(top, "MotifSubtitle", "廃病院からの脱出", 16, C.subtext, "strong", {Size = UDim2.new(0.5, 0, 0, 20)})

	coins.BackgroundTransparency = 0
	coins.BackgroundColor3 = C.dim:Lerp(C.ink, 0.25)
	coins.TextColor3 = C.amber
	coins.TextXAlignment = Enum.TextXAlignment.Right
	round(coins, 3)
	line(coins, C.edge, 2)
	make("UIPadding", coins, {Name = "MotifPad", PaddingLeft = UDim.new(0, 44), PaddingRight = UDim.new(0, 14)})
	Art.coinToken(coins, 26, UDim2.new(0, -34, 0.5, 0)) -- inside the padding: sits 10 px from the left edge
	return r
end

-- Call to action: the 非常口 light box -----------------------------------------------------------
local RUNNER = {
	-- name, x, y, w, h, rotation (px in a 76 x 76 box, centres). White on green, like the JIS sign.
	{"Head", 24, 13, 13, 13, 0, true},
	{"Torso", 21, 31, 9, 23, 24},
	{"ArmFront", 30, 27, 6, 17, -58},
	{"ArmBack", 13, 27, 6, 16, 55},
	{"LegFront", 27, 49, 7, 22, -38},
	{"LegBack", 11, 47, 7, 20, 46},
}

function Art.exitSign(play, parent)
	local r = {}
	Theme.setFace(play, C.accent, C.text)
	local casing = play:FindFirstChild("MotifEdge")
	if casing then casing.Color, casing.Thickness = C.steel, 4 end
	-- The button keeps its Text (other code may read it); a mirrored label lays it out beside the pictogram.
	local label = text(play, "MotifExitText", play.Text, 34, C.text, "strong",
		{Position = UDim2.new(0, 100, 0, 8), Size = UDim2.new(1, -112, 0, 54), TextXAlignment = Enum.TextXAlignment.Center})
	play:GetPropertyChangedSignal("Text"):Connect(function() label.Text = play.Text end)
	text(play, "MotifExitEn", "EMERGENCY EXIT", 15, C.text, "display",
		{Position = UDim2.new(0, 100, 1, -34), Size = UDim2.new(1, -112, 0, 20), TextXAlignment = Enum.TextXAlignment.Center})
	play.TextTransparency = 1
	local diffuser = deco(play, "MotifDiffuser", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -10, 1, -10), BackgroundTransparency = 1})
	round(diffuser, 2)
	line(diffuser, C.glow, 1.5, 0.45)
	local picto = deco(play, "MotifExitPicto", {AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0),
		Size = UDim2.fromOffset(76, 76), BackgroundTransparency = 1})
	local door = deco(picto, "Door", {Position = UDim2.fromOffset(46, 6), Size = UDim2.fromOffset(28, 64), BackgroundColor3 = C.text})
	deco(door, "Opening", {Position = UDim2.fromOffset(5, 5), Size = UDim2.new(1, -10, 1, -5), BackgroundColor3 = C.accent})
	for _, part in ipairs(RUNNER) do
		local limb = deco(picto, part[1], {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(part[2], part[3]),
			Size = UDim2.fromOffset(part[4], part[5]), Rotation = part[6], BackgroundColor3 = C.text})
		if part[7] then round(limb) else round(limb, 3) end
	end
	-- The glow is a sibling behind the sign (children always draw above their parent): an inner
	-- glow with a breathing ring, and a wider, fainter haze child for the falloff.
	r.glow = deco(parent, "MotifExitGlow", {AnchorPoint = play.AnchorPoint, Position = play.Position,
		Size = UDim2.fromOffset(play.Size.X.Offset + 36, play.Size.Y.Offset + 36), BackgroundColor3 = C.glow,
		BackgroundTransparency = 0.86, ZIndex = Z.glow})
	round(r.glow, 16)
	r.glowRing = line(r.glow, C.glow, 10, 0.74, "MotifGlowRing")
	round(deco(r.glow, "Haze", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 90, 1, 70), BackgroundColor3 = C.glow, BackgroundTransparency = 0.94, ZIndex = 0}), 44)
	r.glowScale = make("UIScale", r.glow, {Name = "MotifFit", Scale = 1})
	return r
end

-- Dock: room-number door plates --------------------------------------------------------------------
function Art.roomPlate(button, room, tag)
	Theme.setFace(button, C.panelLight, C.ink)
	button.TextSize = 20
	make("UIPadding", button, {Name = "MotifPad", PaddingTop = UDim.new(0, 12)})
	-- children below sit inside the 12 px top padding: offsets are relative to it
	text(button, "MotifRoomNo", room .. "  " .. tag, 14, C.muted:Lerp(C.ink, 0.5), "display",
		{Position = UDim2.new(0, 9, 0, -8), Size = UDim2.new(1, -30, 0, 16)})
	local lamp = deco(button, "MotifLamp", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -13, 0, -1),
		Size = UDim2.fromOffset(9, 9), BackgroundColor3 = C.lampOff})
	round(lamp)
	line(lamp, C.ink, 1.5, 0, "MotifLampRing")
	for _, x in ipairs({0, 1}) do
		local screw = deco(button, "MotifScrew", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(x, x == 0 and 7 or -7, 0.5, 0),
			Size = UDim2.fromOffset(6, 6), BackgroundColor3 = C.steel:Lerp(C.ink, 0.25)})
		round(screw)
	end
end

function Art.setPlateLit(button, lit)
	Theme.setFace(button, lit and C.paperLight or C.panelLight, C.ink)
	local lamp = button:FindFirstChild("MotifLamp")
	if lamp then
		lamp.BackgroundColor3 = lit and C.glow or C.lampOff
		local ring = lamp:FindFirstChild("MotifLampRing")
		if ring then ring.Color, ring.Thickness, ring.Transparency = lit and C.glow or C.ink, lit and 3 or 1.5, lit and 0.45 or 0 end
	end
end

-- Panels: patient charts on a clipboard -----------------------------------------------------------
function Art.clipboard(page, header, patient)
	page.BackgroundColor3 = Color3.new(1, 1, 1) -- the grain gradient below carries the board colour
	make("UIGradient", page, {Name = "MotifGrain", Rotation = 0, Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, C.board), ColorSequenceKeypoint.new(0.3, C.board:Lerp(C.ink, 0.1)),
		ColorSequenceKeypoint.new(0.55, C.board), ColorSequenceKeypoint.new(0.8, C.board:Lerp(C.ink, 0.08)),
		ColorSequenceKeypoint.new(1, C.board)})})
	local edge = page:FindFirstChild("MotifEdge")
	if edge then edge.Color, edge.Thickness = C.board:Lerp(C.ink, 0.6), 2 end
	local corner = page:FindFirstChildOfClass("UICorner")
	if corner then corner.CornerRadius = UDim.new(0, 8) end

	deco(page, "MotifSheetUnder", {Position = UDim2.new(0, 16, 0, 30), Size = UDim2.new(1, -30, 1, -42),
		BackgroundColor3 = C.paper:Lerp(C.board, 0.22), Rotation = 1.2, ZIndex = 1})
	local sheet = deco(page, "MotifSheet", {Position = UDim2.new(0, 12, 0, 24), Size = UDim2.new(1, -24, 1, -36),
		BackgroundColor3 = C.paper, ZIndex = 2, ClipsDescendants = true})
	round(sheet, 2)
	for index = 0, 11 do
		deco(sheet, "MotifRule", {Position = UDim2.new(0, 10, 0, 108 + index * 36), Size = UDim2.new(1, -20, 0, 1),
			BackgroundColor3 = C.edge, BackgroundTransparency = 0.55})
	end
	deco(sheet, "MotifMargin", {Position = UDim2.new(0, 14, 0, 34), Size = UDim2.new(0, 2, 1, -34), BackgroundColor3 = C.stamp, BackgroundTransparency = 0.6})
	text(sheet, "MotifChartHead", header, 14, C.muted, "display", {Position = UDim2.new(0, 22, 0, 7), Size = UDim2.new(0.62, -22, 0, 20)})
	local id = text(sheet, "MotifChartId", "PATIENT: " .. patient, 14, C.muted, "display",
		{AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 7), Size = UDim2.new(0.38, -14, 0, 20), TextXAlignment = Enum.TextXAlignment.Right})
	if kit then kit:fitHeading(id, 14, 9) end
	deco(sheet, "MotifHeadRule", {Position = UDim2.new(0, 14, 0, 30), Size = UDim2.new(1, -28, 0, 2), BackgroundColor3 = C.ink, BackgroundTransparency = 0.15})

	-- Steel clip across the top edge.
	local steelDark = C.steel:Lerp(C.ink, 0.55)
	local clip = deco(page, "MotifClip", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(144, 34), BackgroundColor3 = C.steel, ZIndex = 30})
	round(clip, 6)
	line(clip, steelDark, 2)
	deco(clip, "Groove", {Position = UDim2.new(0, 6, 1, -10), Size = UDim2.new(1, -12, 0, 4), BackgroundColor3 = steelDark, BackgroundTransparency = 0.3})
	for _, x in ipairs({0.2, 0.8}) do
		round(deco(clip, "Rivet", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, 0.4), Size = UDim2.fromOffset(8, 8),
			BackgroundColor3 = steelDark}))
	end
	local ring = deco(clip, "Ring", {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.fromOffset(54, 22),
		BackgroundTransparency = 1})
	round(ring, 11)
	line(ring, C.steel:Lerp(C.ink, 0.3), 5)
	return sheet
end

-- A rubber stamp on a chart ("記録なし", "準備中").
function Art.stampMark(parent, value, position)
	local stamp = text(parent, "MotifStamp", value, 26, C.stamp, "strong", {AnchorPoint = Vector2.new(0.5, 0.5), Position = position,
		Size = UDim2.fromOffset(176, 58), TextXAlignment = Enum.TextXAlignment.Center, Rotation = -9, TextTransparency = 0.2, ZIndex = 9})
	line(stamp, C.stamp, 3, 0.25)
	local inner = deco(stamp, "Inner", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -10, 1, -10), BackgroundTransparency = 1})
	line(inner, C.stamp, 1.5, 0.35)
	return stamp
end

-- Shop rows become lines on the chart: typed line number, name, price, and a stamp to buy.
function Art.lineItem(row, index)
	row.BackgroundTransparency = 1
	local edge = row:FindFirstChild("MotifEdge")
	if edge then edge.Transparency = 1 end
	deco(row, "MotifRowRule", {Position = UDim2.new(0, 0, 1, -2), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = C.ink, BackgroundTransparency = 0.35})
	text(row, "MotifLineNo", string.format("%02d", index or 0), 15, C.muted, "display",
		{AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(30, 22)})
	local price = row:FindFirstChild("Price")
	if price then Art.coinToken(price, 22, UDim2.new(0, -30, 0.5, 0)) end
	local buy = row:FindFirstChild("BuyButton")
	if buy then
		local inner = deco(buy, "MotifStampInner", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -10, 1, -10), BackgroundTransparency = 1})
		round(inner, 2)
		line(inner, C.stamp, 1.5, 0.3)
	end
end

-- Settings toggles become wall switches with an indicator lamp. Follows the button Text, so the
-- switch stays right whoever changes it.
function Art.wallSwitch(button)
	button.TextXAlignment = Enum.TextXAlignment.Left
	make("UIPadding", button, {Name = "MotifPad", PaddingLeft = UDim.new(0, 46)})
	local lamp = deco(button, "MotifLamp", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, -23, 0.5, 0),
		Size = UDim2.fromOffset(14, 14), BackgroundColor3 = C.lampOff})
	round(lamp)
	local ring = line(lamp, C.ink, 2, 0, "MotifLampRing")
	local plate = deco(button, "MotifSwitch", {AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(30, 42), BackgroundColor3 = C.paperLight})
	round(plate, 3)
	line(plate, C.ink, 2)
	local slot = deco(plate, "Slot", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(14, 30), BackgroundColor3 = C.ink})
	round(slot, 3)
	local lever = deco(slot, "Lever", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 2),
		Size = UDim2.new(1, -4, 0.5, -2), BackgroundColor3 = C.steel})
	round(lever, 2)
	local function state()
		local value = string.upper(button.Text or "")
		if string.find(value, "OFF", 1, true) then return false end
		return string.find(value, "ON", 1, true) ~= nil
	end
	local function apply(animate)
		local on = state()
		local target = on and UDim2.new(0.5, 0, 0, 2) or UDim2.new(0.5, 0, 0.5, 0)
		if animate then tween(lever, {Position = target}, 0.12) else lever.Position = target end
		lamp.BackgroundColor3 = on and C.glow or C.lampOff
		ring.Color, ring.Thickness, ring.Transparency = on and C.glow or C.ink, on and 3 or 2, on and 0.45 or 0
	end
	apply(false)
	button:GetPropertyChangedSignal("Text"):Connect(function() apply(true) end)
end

-- Layout --------------------------------------------------------------------------------------------
local function viewport(gui)
	local ok, size = pcall(function() return gui.AbsoluteSize end)
	if ok and typeof(size) == "Vector2" and size.X > 1 and size.Y > 1 then return size end
	local camera = workspace.CurrentCamera
	return camera and camera.ViewportSize or Vector2.new(1280, 720)
end

local HEADLINE = {wide = "夜明けまでに、非常口へ。", narrow = "夜明けまでに、\n非常口へ。"}

-- Keeps the menu clear of Roblox's top bar and readable from a phone in portrait to a desktop.
function Art.layout(refs, art)
	local gui, play, nav, top = refs.gui, refs.play, refs.nav, refs.top
	local playScale = play:FindFirstChild("MotifFit") or make("UIScale", play, {Name = "MotifFit", Scale = 1})
	local navScale = nav:FindFirstChild("MotifFit") or make("UIScale", nav, {Name = "MotifFit", Scale = 1})
	local navLayout = nav:FindFirstChildWhichIsA("UIListLayout")
	local bases = {}
	for _, page in pairs(refs.pages) do
		if not page:FindFirstChild("MotifSize") then
			make("UISizeConstraint", page, {Name = "MotifSize", MinSize = Vector2.new(340, 290), MaxSize = Vector2.new(820, 520)})
		end
	end
	local function apply()
		local size = viewport(gui)
		local w, h = size.X, size.Y
		local narrow, short = w < 700, h < 520
		local bar = kit and kit:topbar() or {height = 58}

		top.Size = narrow and UDim2.new(1, -24, 0, 96) or UDim2.new(1, -32, 0, 64)
		top.Position = UDim2.new(0, narrow and 12 or 16, 0, bar.height + 8)
		refs.title.Size = narrow and UDim2.new(1, -44, 0, 36) or UDim2.new(0.55, 0, 0, 34)
		refs.title.Position = UDim2.new(0, 22, 0, narrow and 6 or 4)
		if kit then kit:fitHeading(refs.title, 32, 18) end
		if art.sign and art.sign.subtitle then
			art.sign.subtitle.Position = UDim2.new(0, 22, 0, narrow and 44 or 38)
			art.sign.subtitle.Size = UDim2.new(narrow and 0.5 or 0.5, 0, 0, 20)
		end
		local coins = refs.coins
		coins.AnchorPoint = narrow and Vector2.new(1, 1) or Vector2.new(1, 0.5)
		coins.Position = narrow and UDim2.new(1, -12, 1, -10) or UDim2.new(1, -14, 0.5, 0)
		coins.Size = narrow and UDim2.fromOffset(160, 38) or UDim2.fromOffset(176, 42)

		local ctaY = short and 0.63 or narrow and 0.54 or 0.57
		local ctaScale = short and 0.8 or narrow and math.min(0.92, (w - 24) / 340) or 1
		play.Position = UDim2.new(0.5, 0, ctaY, 0)
		playScale.Scale = ctaScale
		if art.exit then
			art.exit.glow.Position = play.Position
			art.exit.glowScale.Scale = ctaScale
		end
		local ctaTop = -math.floor(50 * ctaScale) - 22
		if art.hero then
			local headline, kicker = art.hero.headline, art.hero.kicker
			local height = narrow and 100 or short and 32 or 58
			headline.Text = narrow and HEADLINE.narrow or HEADLINE.wide
			headline.Size = narrow and UDim2.new(1, -40, 0, height) or UDim2.new(0.9, 0, 0, height)
			headline.Position = UDim2.new(0.5, 0, ctaY, ctaTop)
			if kit then kit:fitHeading(headline, narrow and 42 or short and 28 or 50, 18) end
			kicker.Visible = not short
			kicker.Size = UDim2.new(0.9, 0, 0, 22)
			kicker.Position = UDim2.new(0.5, 0, ctaY, ctaTop - height - 6)
			if kit then kit:fitHeading(kicker, 18, 11) end
		end
		if art.corridor then
			art.corridor.pool.Position = UDim2.new(0.5, 0, ctaY, -70)
			for _, door in ipairs(art.corridor.doors) do door.Visible = w >= 1000 and not short end
		end

		local plateSize = narrow and UDim2.fromOffset(160, 64) or UDim2.fromOffset(134, 64)
		for _, button in pairs(refs.navButtons) do button.Size = plateSize end
		if navLayout then pcall(function() navLayout.Wraps = narrow end) end
		if narrow then
			nav.Size = UDim2.fromOffset(2 * 160 + 14, 2 * 64 + 14)
			navScale.Scale = math.min(1, (w - 20) / (2 * 160 + 14))
		else
			nav.Size = UDim2.fromOffset(4 * 134 + 3 * 14, 64)
			navScale.Scale = short and 0.84 or math.min(1, (w - 24) / (4 * 134 + 3 * 14))
		end

		local rowWidth = math.clamp(0.6 * w, 340, 820) - 64 - 10
		local compact = rowWidth < 440
		for _, row in ipairs(refs.rows) do
			local name, price, buy = row:FindFirstChild("ProductName"), row:FindFirstChild("Price"), row:FindFirstChild("BuyButton")
			if name then
				name.Position = compact and UDim2.new(0, 34, 0, 4) or UDim2.new(0, 34, 0, 0)
				name.Size = compact and UDim2.new(1, -134, 0, 30) or UDim2.new(0.5, -34, 1, 0)
				name.TextSize = compact and 17 or 19
			end
			if price then
				price.Position = compact and UDim2.new(0, 66, 0, 34) or UDim2.new(0.5, 34, 0, 0)
				price.Size = compact and UDim2.new(1, -200, 0, 24) or UDim2.new(0.22, -30, 1, 0)
			end
			if buy then
				buy.Size = compact and UDim2.fromOffset(88, 48) or UDim2.fromOffset(104, 48)
				buy.Position = compact and UDim2.new(1, -92, 0.5, -24) or UDim2.new(1, -112, 0.5, -24)
			end
		end

		local topEdge = bar.height + 8 + (narrow and 96 or 64) + 12
		local bottomEdge = h - 24 - nav.Size.Y.Offset * navScale.Scale - 12
		if bottomEdge - topEdge < 290 then
			topEdge, bottomEdge = bar.height + 8, h - 8
		end
		local pageHeight = math.min(bottomEdge - topEdge, 520)
		for _, page in pairs(refs.pages) do
			page.AnchorPoint = Vector2.new(0.5, 0.5)
			page.Size = UDim2.new(0.6, 0, 0, pageHeight)
			page.Position = UDim2.new(0.5, 0, 0, math.floor((topEdge + bottomEdge) / 2))
			bases[page] = page.Position
		end
	end
	apply()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(apply)
	pcall(function() game:GetService("GuiService"):GetPropertyChangedSignal("TopbarInset"):Connect(apply) end)
	return bases
end

-- Pages: dim the corridor behind an open chart, light its door plate, slide the chart in.
function Art.pages(refs, bases)
	local scrim = make("Frame", refs.gui, {Name = "MotifScrim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.dim,
		BackgroundTransparency = 0.3, BorderSizePixel = 0, Active = false, Visible = false, ZIndex = 15})
	local function sync()
		local any = false
		for _, item in ipairs(refs.navInfo) do
			local page = refs.pages[item.id]
			local open = page ~= nil and page.Visible == true
			any = any or open
			local plate = refs.navButtons[item.id]
			if plate then pcall(Art.setPlateLit, plate, open) end
		end
		scrim.Visible = any
	end
	for _, page in pairs(refs.pages) do
		page:GetPropertyChangedSignal("Visible"):Connect(function()
			local base = bases and bases[page]
			if page.Visible and base and not reduced() then
				page.Position = base + UDim2.fromOffset(0, 26)
				tween(page, {Position = base}, 0.3)
			end
			sync()
		end)
	end
	sync()
	return scrim
end

-- Motion ----------------------------------------------------------------------------------------------
-- Two slow loops (flashlight drift, exit-sign glow) and an occasional single light dip. All stop
-- while the menu is hidden and never start under reduced motion.
function Art.motion(refs, art)
	local gui, background = refs.gui, refs.background
	local specs = {}
	if art.corridor then
		table.insert(specs, {art.corridor.drift, {Position = UDim2.new(0.5, 54, 0.5, -18)}, 7.5})
	end
	if art.exit then
		table.insert(specs, {art.exit.glowRing, {Transparency = 0.5, Thickness = 15}, 2.8})
	end
	for _, spec in ipairs(specs) do
		spec.base = {}
		for key in pairs(spec[2]) do spec.base[key] = spec[1][key] end
	end
	local running = {}
	local function shown()
		return gui.Parent ~= nil and gui.Enabled ~= false and background.Visible ~= false
	end
	local function stop()
		for _, handle in ipairs(running) do pcall(function() handle:Cancel() end) end
		table.clear(running)
		for _, spec in ipairs(specs) do
			for key, value in pairs(spec.base) do pcall(function() spec[1][key] = value end) end
		end
	end
	local function start()
		if #running > 0 or not shown() or not kit then return end
		for _, spec in ipairs(specs) do
			local handle = kit:loop(spec[1], spec[2], spec[3])
			if handle then table.insert(running, handle) end
		end
	end
	local function refresh() if shown() then start() else stop() end end
	gui:GetPropertyChangedSignal("Enabled"):Connect(refresh)
	background:GetPropertyChangedSignal("Visible"):Connect(refresh)
	start()

	-- The fluorescent light dips once every 4.5-9.5 s (one 0.12 s dip, never a strobe).
	local dips = {}
	if art.corridor then
		table.insert(dips, {art.corridor.wash, "BackgroundTransparency", 0, 0.7})
		table.insert(dips, {art.corridor.tube, "BackgroundTransparency", 0, 0.75})
	end
	if art.hero then table.insert(dips, {art.hero.headline, "TextTransparency", 0, 0.35}) end
	task.spawn(function()
		while gui.Parent do
			task.wait(4.5 + math.random() * 5)
			if gui.Parent and shown() and not reduced() then
				for _, dip in ipairs(dips) do dip[1][dip[2]] = dip[4] end
				task.wait(0.12)
				for _, dip in ipairs(dips) do dip[1][dip[2]] = dip[3] end
			end
		end
	end)
	return running
end

-- Everything, step by step. Each step is isolated: one failing leaves the others (and the menu).
function Art.install(refs)
	local art = {}
	local function step(name, fn)
		local ok, err = pcall(fn)
		if not ok then warn("NightWardArt." .. name .. ": " .. tostring(err)) end
	end
	local patient = "YOU"
	pcall(function() patient = string.upper(Players.LocalPlayer.Name) end)

	refs.gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	step("corridor", function() art.corridor = Art.corridor(refs.background) end)
	step("hero", function() art.hero = Art.hero(refs.background) end)
	step("wardSign", function() art.sign = Art.wardSign(refs.top, refs.title, refs.coins) end)
	step("exitSign", function() art.exit = Art.exitSign(refs.play, refs.background) end)
	for _, item in ipairs(refs.navInfo) do
		step("roomPlate", function() Art.roomPlate(refs.navButtons[item.id], item.room, item.tag) end)
		step("clipboard", function() Art.clipboard(refs.pages[item.id], item.chart, patient) end)
	end
	step("stamps", function()
		Art.stampMark(refs.pages.Inventory, "記録なし", UDim2.fromScale(0.7, 0.62))
		Art.stampMark(refs.pages.Quests, "準備中", UDim2.fromScale(0.7, 0.62))
	end)
	for index, row in ipairs(refs.rows) do step("lineItem", function() Art.lineItem(row, index) end) end
	for _, toggle in ipairs(refs.toggles) do step("wallSwitch", function() Art.wallSwitch(toggle) end) end
	local bases
	step("layout", function() bases = Art.layout(refs, art) end)
	step("pages", function() Art.pages(refs, bases) end)
	step("motion", function() Art.motion(refs, art) end)
	return art
end

return Art
