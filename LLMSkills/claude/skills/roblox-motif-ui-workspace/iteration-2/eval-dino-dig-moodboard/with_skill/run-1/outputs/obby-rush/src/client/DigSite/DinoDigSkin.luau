--!nocheck
-- DinoDigSkin: the "Lost Valley Dig" look for the main menu and the shop.
-- Motif (from the user): 恐竜の発掘調査をするジャングル + moodboard-dino-dig.png.
--
-- World-in-UI translation (see DESIGN.md):
--   * CTA   = a piece of amber with a trapped bug, set in a dug-out bed of soil inside a string-and-stake
--             excavation square (the one glowing thing on screen).
--   * Panel = a FIELD NOTES page: ruled cream paper, jungle-green header, typewritten site notes.
--   * Nav   = fossil slabs lying in the dig-site strata, each showing a find in a soil window.
--   * Shop  = specimen labels (catalogue number, specimen tray); prices are paid in amber.
--   * Scene = jungle canopy with hanging vines above, excavation strata with a skeleton below.
--
-- Presentation only. Names, parents, callbacks and the Visible logic of MainMenu stay untouched (other
-- scripts and tests/test_main_menu.luau look the menu up by name). Every decoration is a non-interactive
-- Frame/TextLabel whose name starts with "Motif", and every step runs under pcall: if a step fails the
-- menu keeps the plain themed look instead of breaking.
local DigSite = script.Parent
local Kit = require(DigSite:WaitForChild("MotifSkinKit", 5))
local kit = Kit.new(require(DigSite:WaitForChild("MotifSpec", 5)))
local P = kit.P

local Skin = {kit = kit, errors = {}}

-- Faces used by the adapter (role name -> fill colour).
local FACES = {primary = P.amber, jungle = P.jungle, paper = P.paper, slab = P.slab, leaf = P.leaf, quiet = P.quiet}
-- Button Name -> role. Anything not listed uses the fossil-slab face.
local NAME_ROLE = {PlayButton = "primary", BuyButton = "jungle", CloseButton = "paper"}
-- Page id -> field-notes page number and typewritten note (English only: the typewriter face is Latin-only).
local PAGES = {
	{id = "Shop", page = "ShopPage", note = "FIELD NOTES No.01  ·  AMBER TRADING POST"},
	{id = "Inventory", page = "InventoryPage", note = "FIELD NOTES No.02  ·  FINDS"},
	{id = "Quests", page = "QuestsPage", note = "FIELD NOTES No.03  ·  SURVEY MAP"},
	{id = "Settings", page = "SettingsPage", note = "FIELD NOTES No.04  ·  FIELD KIT"},
}
-- Product id keyword -> specimen emoji (Unicode <= 12 only: newer emoji draw as a box in Roblox).
local SPECIMENS = {{"speed", "⚡"}, {"rainbow", "🌈"}, {"jump", "🦘"}}
local COIN_GLYPH = "\240\159\170\153" -- U+1FA99 coin (Unicode 13): Roblox draws it as a tofu box, so it is replaced by drawn amber

-- Small helpers ------------------------------------------------------------------------------------
-- Deterministic Park-Miller generator: the scatter of leaves is the same on every client and in tests.
local function rng(seed)
	local state = seed % 2147483647
	if state <= 0 then state += 2147483646 end
	return function(a, b)
		state = (state * 16807) % 2147483647
		local r = (state - 1) / 2147483646
		if a == nil then return r end
		return a + (b - a) * r
	end
end

local function frame(parent, name, props)
	local object = Instance.new("Frame")
	object.Name = name
	object.BorderSizePixel = 0
	object.Active = false
	object.BackgroundTransparency = 0
	for key, value in pairs(props or {}) do object[key] = value end
	object.Parent = parent
	return object
end

local function corner(object, radius)
	local item = object:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
	item.CornerRadius = radius
	item.Parent = object
	return item
end

local function stroke(object, color, thickness, transparency, name)
	local item = Instance.new("UIStroke")
	item.Name = name or "MotifStroke"
	item.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	item.LineJoinMode = Enum.LineJoinMode.Round
	item.Color, item.Thickness, item.Transparency = color, thickness, transparency or 0
	item.Parent = object
	return item
end

local function label(parent, name, text, size, role, color, props)
	local object = Instance.new("TextLabel")
	object.Name = name
	object.BackgroundTransparency = 1
	object.BorderSizePixel = 0
	object.Active = false
	object.Text = text
	object.TextSize = size
	object.TextColor3 = color
	object.TextXAlignment = Enum.TextXAlignment.Left
	object.TextYAlignment = Enum.TextYAlignment.Center
	object.TextWrapped = false
	for key, value in pairs(props or {}) do object[key] = value end
	kit:setFont(object, role)
	object.Parent = parent
	return object
end

local function padding(object, left, right, top, bottom)
	local item = object:FindFirstChildOfClass("UIPadding") or Instance.new("UIPadding")
	item.PaddingLeft, item.PaddingRight = UDim.new(0, left or 0), UDim.new(0, right or 0)
	item.PaddingTop, item.PaddingBottom = UDim.new(0, top or 0), UDim.new(0, bottom or 0)
	item.Parent = object
	return item
end

-- Round/oval blob placed by scale inside its parent.
local function blob(parent, name, x, y, w, h, color, props)
	local object = frame(parent, name, {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, y), Size = UDim2.fromScale(w, h),
		BackgroundColor3 = color,
	})
	corner(object, UDim.new(1, 0))
	for key, value in pairs(props or {}) do object[key] = value end
	return object
end

-- A straight bar between two pixel points of a fixed-size parent (stems, bones, strings).
local function segment(parent, name, x0, y0, x1, y1, thickness, color, round)
	local dx, dy = x1 - x0, y1 - y0
	local object = frame(parent, name, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset((x0 + x1) / 2, (y0 + y1) / 2),
		Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy) + thickness * 0.5, thickness),
		Rotation = math.deg(math.atan2(dy, dx)),
		BackgroundColor3 = color,
	})
	if round then corner(object, UDim.new(1, 0)) end
	return object
end

-- Two-tone "folded" leaf: the lower half is shaded through a multiplying UIGradient, like the faceted
-- low-poly leaves of the moodboard's jungle panel.
local function facet(object, shade, rotation)
	local gradient = Instance.new("UIGradient")
	gradient.Name = "MotifFacet"
	gradient.Rotation = rotation or 90
	local white, dark = Color3.new(1, 1, 1), Color3.new(shade, shade, shade)
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, white), ColorSequenceKeypoint.new(0.49, white),
		ColorSequenceKeypoint.new(0.5, dark), ColorSequenceKeypoint.new(1, dark),
	})
	gradient.Parent = object
	return gradient
end

local function textWithoutCoin(text)
	return (string.gsub(tostring(text or ""), COIN_GLYPH .. "%s*", ""))
end

-- Keep a label free of the tofu coin, also when other scripts rewrite its Text later.
local function stripCoin(object)
	local busy = false
	local function clean()
		if busy then return end
		local cleaned = textWithoutCoin(object.Text)
		if cleaned ~= object.Text then
			busy = true
			object.Text = cleaned
			busy = false
		end
	end
	clean()
	pcall(function() object:GetPropertyChangedSignal("Text"):Connect(clean) end)
end

-- Drawn finds (no image assets). Each draws inside `box` (a square Frame) by scale or box pixels.
local Glyph = {}

function Glyph.amber(box)
	blob(box, "Resin", 0.5, 0.5, 0.86, 0.86, P.amberDeep)
	blob(box, "Core", 0.5, 0.5, 0.66, 0.66, P.amber)
	blob(box, "Shine", 0.38, 0.33, 0.26, 0.17, P.amberShine, {Rotation = -18})
	blob(box, "Bug", 0.56, 0.58, 0.13, 0.22, P.bug, {Rotation = 28})
end

function Glyph.bone(box, s)
	local x0, y0, x1, y1 = 0.27 * s, 0.67 * s, 0.73 * s, 0.33 * s
	segment(box, "Shaft", x0, y0, x1, y1, 0.15 * s, P.bone, true)
	local len = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
	local px, py = -(y1 - y0) / len, (x1 - x0) / len -- perpendicular
	for _, e in ipairs({{x0, y0}, {x1, y1}}) do
		for _, side in ipairs({-1, 1}) do
			local knob = frame(box, "Knob", {
				AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = P.bone,
				Position = UDim2.fromOffset(e[1] + px * side * 0.075 * s, e[2] + py * side * 0.075 * s),
				Size = UDim2.fromOffset(0.2 * s, 0.2 * s),
			})
			corner(knob, UDim.new(1, 0))
		end
	end
end

function Glyph.route(box, s)
	for index, p in ipairs({{0.16, 0.76}, {0.28, 0.66}, {0.41, 0.6}, {0.53, 0.64}, {0.63, 0.55}}) do
		blob(box, "RouteDot" .. index, p[1], p[2], 0.09, 0.09, P.marker)
	end
	for _, angle in ipairs({45, -45}) do
		frame(box, "Cross", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.75, 0.33),
			Size = UDim2.fromOffset(0.36 * s, 0.1 * s), Rotation = angle, BackgroundColor3 = P.marker,
		})
	end
end

function Glyph.brush(box, s)
	segment(box, "Handle", 0.36 * s, 0.36 * s, 0.8 * s, 0.8 * s, 0.13 * s, P.brush, true)
	local bristle = frame(box, "Bristle", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.27, 0.27),
		Size = UDim2.fromOffset(0.3 * s, 0.22 * s), Rotation = 45, BackgroundColor3 = P.bristle,
	})
	corner(bristle, UDim.new(0, 2))
	frame(box, "Ferrule", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.38, 0.38),
		Size = UDim2.fromOffset(0.08 * s, 0.24 * s), Rotation = 45, BackgroundColor3 = P.soilDeep,
	})
end

-- A find shown through a round window in the ground (nav slabs, empty states).
local function findWindow(parent, name, kind, size, props)
	local window = frame(parent, name, {Size = UDim2.fromOffset(size, size), BackgroundColor3 = kind == "route" and P.paper or P.soil})
	corner(window, UDim.new(1, 0))
	stroke(window, P.outline, 2)
	local inner = math.floor(size * 0.8)
	local box = frame(window, "Find", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(inner, inner), BackgroundTransparency = 1,
	})
	Glyph[kind](box, inner)
	for key, value in pairs(props or {}) do window[key] = value end
	return window
end

local function amberDrop(parent, name, size, props)
	local box = frame(parent, name, {Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1})
	Glyph.amber(box)
	for key, value in pairs(props or {}) do box[key] = value end
	return box
end

-- Hanging vine: straight stem segments that zig-zag down, round leaves alternating at the joints.
-- options: minX/maxX (stem limits inside the 60 px holder), inner (leaf scale on the left side).
local function vine(parent, name, props, length, seed, options)
	options = options or {}
	local holder = frame(parent, name, {Size = UDim2.fromOffset(60, length), BackgroundTransparency = 1})
	for key, value in pairs(props or {}) do holder[key] = value end
	local rand = rng(seed)
	local points = {{30, 0}}
	local x, y = 30, 0
	while y < length - 8 do
		x = math.clamp(x + rand(-15, 15), options.minX or 16, options.maxX or 44)
		y = math.min(length, y + rand(28, 42))
		table.insert(points, {x, y})
	end
	for index = 2, #points do
		segment(holder, "Stem", points[index - 1][1], points[index - 1][2], points[index][1], points[index][2], 6, P.vine)
	end
	local side = seed % 2 == 0 and 1 or -1
	for index = 2, #points do
		local p = points[index]
		local scale = side < 0 and (options.inner or 1) or 1
		local w, h = 26 * scale, 20 * scale
		local leaf = frame(holder, "Leaf", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(p[1] + side * (w * 0.5 - 1), p[2] - 3),
			Size = UDim2.fromOffset(w, h), Rotation = side * rand(8, 32),
			BackgroundColor3 = rand() < 0.3 and P.leaf or P.vineLeaf,
		})
		corner(leaf, UDim.new(1, 0))
		side = -side
	end
	return holder
end


-- A string-and-stake excavation square; options.flag plants a red survey flag on the top-left stake.
local function excavation(parent, name, props, options)
	options = options or {}
	local plot = frame(parent, name, {BackgroundTransparency = 1})
	for key, value in pairs(props or {}) do plot[key] = value end
	local inset = 8
	frame(plot, "String", {Position = UDim2.fromOffset(inset, inset), Size = UDim2.new(1, -inset * 2, 0, 2), BackgroundColor3 = P.string})
	frame(plot, "String", {Position = UDim2.new(0, inset, 1, -inset - 2), Size = UDim2.new(1, -inset * 2, 0, 2), BackgroundColor3 = P.string})
	frame(plot, "String", {Position = UDim2.fromOffset(inset, inset), Size = UDim2.new(0, 2, 1, -inset * 2), BackgroundColor3 = P.string})
	frame(plot, "String", {Position = UDim2.new(1, -inset - 2, 0, inset), Size = UDim2.new(0, 2, 1, -inset * 2), BackgroundColor3 = P.string})
	for _, c in ipairs({{0, 0}, {1, 0}, {0, 1}, {1, 1}}) do
		local stake = frame(plot, "Stake", {
			AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = P.brush, Size = UDim2.fromOffset(12, 12),
			Position = UDim2.new(c[1], c[1] == 0 and inset + 1 or -inset - 1, c[2], c[2] == 0 and inset + 1 or -inset - 1),
		})
		corner(stake, UDim.new(0, 2))
		stroke(stake, P.outline, 2)
	end
	local flag = nil
	if options.flag then
		flag = frame(plot, "MotifSurveyFlag", {Position = UDim2.fromOffset(inset - 1, inset - 36), Size = UDim2.fromOffset(28, 36), BackgroundTransparency = 1})
		frame(flag, "Pole", {Size = UDim2.fromOffset(3, 36), BackgroundColor3 = P.outline})
		local pennant = frame(flag, "Pennant", {Position = UDim2.fromOffset(3, 1), Size = UDim2.fromOffset(24, 15), BackgroundColor3 = P.marker, Rotation = -3})
		stroke(pennant, P.outline, 2)
	end
	return plot, flag
end

local function ammonite(parent, name, size, props)
	local box = frame(parent, name, {Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1})
	for key, value in pairs(props or {}) do box[key] = value end
	for _, whorl in ipairs({{0.5, 0.92}, {0.53, 0.6}, {0.555, 0.32}}) do
		local ring = blob(box, "Whorl", whorl[1], 0.5, whorl[2], whorl[2], P.bone, {BackgroundTransparency = 1})
		stroke(ring, P.bone, math.max(2, size * 0.045))
	end
	blob(box, "Umbilicus", 0.565, 0.5, 0.1, 0.1, P.bone)
	local c, r = size / 2, size * 0.46
	for index = 0, 11 do
		local a = math.rad(index * 30 + 8)
		segment(box, "Rib", c + math.cos(a) * r * 0.8, c + math.sin(a) * r * 0.8, c + math.cos(a) * r * 1.12, c + math.sin(a) * r * 1.12, 2, P.bone)
	end
	return box
end

-- The half-excavated skeleton from the moodboard: skull with an eye hole, spine, ribs, two legs.
local function skeleton(box)
	local bone = P.bone
	local spine = {{58, 40}, {102, 26}, {152, 18}, {202, 22}, {244, 38}, {284, 60}, {326, 84}}
	for index = 2, #spine do
		segment(box, "Spine", spine[index - 1][1], spine[index - 1][2], spine[index][1], spine[index][2], 7, bone, true)
	end
	local function spineY(x)
		for index = 2, #spine do
			local a, b = spine[index - 1], spine[index]
			if x <= b[1] then return a[2] + (b[2] - a[2]) * (x - a[1]) / (b[1] - a[1]) end
		end
		return spine[#spine][2]
	end
	for index, x in ipairs({112, 130, 148, 166, 184, 202, 220, 238}) do
		local top = spineY(x)
		segment(box, "Rib", x, top, x - 4, top + 30 + (index % 2) * 6, 5, bone, true)
	end
	for _, leg in ipairs({{{116, 24}, {106, 80}, {122, 108}}, {{214, 26}, {228, 80}, {210, 110}}}) do
		segment(box, "Leg", leg[1][1], leg[1][2], leg[2][1], leg[2][2], 7, bone, true)
		segment(box, "Leg", leg[2][1], leg[2][2], leg[3][1], leg[3][2], 6, bone, true)
	end
	local skull = frame(box, "Skull", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(36, 34), Size = UDim2.fromOffset(50, 36),
		Rotation = -8, BackgroundColor3 = bone,
	})
	corner(skull, UDim.new(0, 5))
	blob(skull, "Eye", 0.6, 0.38, 0.22, 0.3, P.soil)
	segment(box, "Jaw", 14, 56, 62, 54, 5, bone, true)
end

-- A fly caught in the resin, drawn in a 34 px box and veiled with amber so it sits inside the stone.
local function trappedBug(box)
	for _, leg in ipairs({{5, 10}, {4, 19}, {7, 28}, {29, 10}, {30, 19}, {27, 28}}) do
		segment(box, "Leg", 17, 19, leg[1], leg[2], 2, P.bug)
	end
	segment(box, "Feeler", 15, 8, 10, 1, 1.5, P.bug)
	segment(box, "Feeler", 19, 8, 24, 1, 1.5, P.bug)
	blob(box, "WingL", 0.35, 0.43, 0.3, 0.46, P.bone, {Rotation = 22, BackgroundTransparency = 0.25})
	blob(box, "WingR", 0.65, 0.43, 0.3, 0.46, P.bone, {Rotation = -22, BackgroundTransparency = 0.25})
	blob(box, "Body", 0.5, 0.6, 0.26, 0.5, P.bug)
	blob(box, "Head", 0.5, 0.24, 0.2, 0.2, P.bug)
	blob(box, "Resin", 0.5, 0.5, 1.15, 1.15, P.amber, {BackgroundTransparency = 0.6})
end

-- One low-poly leaf: two diamonds (square rotated 45 deg) along the leaf axis, each split light/dark
-- along that axis. Points toward +x of its holder; `angle` turns the whole leaf.
local function kiteLeaf(parent, position, length, angle, tone)
	local holder = frame(parent, "Leaf", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = position, Size = UDim2.fromOffset(length, length * 0.5),
		Rotation = angle, BackgroundTransparency = 1,
	})
	local base = length * 0.5
	for _, part in ipairs({{"Blade", base, base * 0.72}, {"Tip", base * 0.66, base * 1.34}}) do
		local diamond = frame(holder, part[1], {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, part[3] - length * 0.05, 0.5, 0),
			Size = UDim2.fromOffset(part[2], part[2]), Rotation = 45, BackgroundColor3 = tone,
		})
		facet(diamond, 0.76, 45)
	end
	return holder
end

-- A three-toed track pressed into the sand.
local function footprint(parent, position, size, angle)
	local track = frame(parent, "MotifFootprint", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = position, Size = UDim2.fromOffset(size, size),
		Rotation = angle, BackgroundTransparency = 1,
	})
	local fade = 0.55
	blob(track, "Pad", 0.5, 0.66, 0.42, 0.38, P.string, {BackgroundTransparency = fade})
	blob(track, "ToeL", 0.3, 0.38, 0.17, 0.44, P.string, {BackgroundTransparency = fade, Rotation = -28})
	blob(track, "ToeM", 0.5, 0.3, 0.17, 0.48, P.string, {BackgroundTransparency = fade})
	blob(track, "ToeR", 0.7, 0.38, 0.17, 0.44, P.string, {BackgroundTransparency = fade, Rotation = 28})
	return track
end

-- A tuft of jungle-floor grass standing on the dig-site rim.
local function tuft(parent, x, seed)
	local rand = rng(seed)
	local clump = frame(parent, "MotifTuft", {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(x, 0, 0.8, -18), Size = UDim2.fromOffset(44, 30),
		BackgroundTransparency = 1, ZIndex = 1,
	})
	for blade = 1, 5 do
		local bx = 22 + (blade - 3) * 4
		segment(clump, "Blade", bx, 30, bx + (blade - 3) * rand(4, 8), rand(2, 12), 4, blade % 2 == 0 and P.vineLeaf or P.leaf, true)
	end
	return clump
end

-- Scene: jungle canopy with hanging vines above, excavation strata with a skeleton below ------------
local function buildCanopy(background)
	local band = frame(background, "MotifCanopy", {Size = UDim2.new(1, 0, 0.2, 0), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 1})
	local depth = Instance.new("UIGradient")
	depth.Name = "MotifDepth"
	depth.Rotation = 90
	depth.Color = ColorSequence.new(P.jungleDeep, P.jungle)
	depth.Parent = band
	local rand = rng(20260924)
	local tones = {P.jungleDeep, P.vine, P.jungle, P.vineLeaf, P.leaf}
	-- Low-poly leaves like the moodboard's jungle panel: each leaf is a kite made of two diamonds along its
	-- axis, split into a light and a dark facet. The last 36 hang over the band's lower edge so the canopy
	-- ends raggedly instead of on a ruler line.
	local inside, hanging = 50, 36
	for index = 1, inside + hanging do
		local fringe = index > inside
		local slot = fringe and (index - inside - 1) / hanging or (index - 1) / inside
		local x = slot + rand(0, fringe and 1 / hanging or 1 / inside)
		local y = fringe and rand(0.86, 1.16) or rand(0, 0.9)
		local tone = tones[math.floor(rand(fringe and 2 or 1, 5.99))]
		local angle = fringe and rand(60, 120) or rand(-180, 180)
		kiteLeaf(band, UDim2.fromScale(x, y), fringe and rand(46, 80) or rand(40, 96), angle, tone)
	end
	return band
end

local function buildStrata(background)
	local ground = frame(background, "MotifStrata", {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0.2, 20),
		BackgroundColor3 = P.soil, ClipsDescendants = true, ZIndex = 1,
	})
	frame(ground, "Topsoil", {Size = UDim2.new(1, 0, 0.18, 0), BackgroundColor3 = P.slab})
	frame(ground, "Bedrock", {AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0.16, 0), BackgroundColor3 = P.soilDeep})
	frame(ground, "LayerLine", {Position = UDim2.fromScale(0, 0.18), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = P.soilDeep})
	frame(ground, "Rim", {Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = P.outline})
	kit:dots(ground, {name = "MotifSpeckles", columns = 24, rows = 3, size = 4, color = P.soilDeep, transparency = 0.3})
	for index = 1, 11 do -- excavation grid: strings pegged into the topsoil
		frame(ground, "GridString", {Position = UDim2.new(index / 12, 0, 0.18, 3), Size = UDim2.new(0, 2, 0.66, 0), BackgroundColor3 = P.string, BackgroundTransparency = 0.25})
		local peg = frame(ground, "GridPeg", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(index / 12, 1, 0.18, 2), Size = UDim2.fromOffset(9, 9), BackgroundColor3 = P.brush})
		stroke(peg, P.outline, 1.5)
	end
	frame(ground, "GridString", {Position = UDim2.fromScale(0, 0.56), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = P.string, BackgroundTransparency = 0.25})
	skeleton(frame(ground, "MotifSkeleton", {Position = UDim2.new(0, 22, 0.18, 12), Size = UDim2.fromOffset(330, 124), BackgroundTransparency = 1}))
	ammonite(ground, "MotifAmmonite", 80, {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(1, -96, 0.18, 16)})
	local tool = frame(ground, "MotifBrush", {Position = UDim2.new(1, -250, 0.18, 12), Size = UDim2.fromOffset(84, 84), BackgroundTransparency = 1, Rotation = 28})
	Glyph.brush(tool, 84)
	return ground
end

local function buildScene(background)
	background.BackgroundColor3 = P.sand
	background.BackgroundTransparency = 0
	-- A dinosaur's trail across the clearing, heading for the dig site.
	local tracks = {}
	for step = 0, 5 do
		local side = step % 2 == 0 and 1 or -1
		table.insert(tracks, footprint(background, UDim2.new(0.085 + 0.037 * step, side * 7, 0.735 - 0.03 * step, side * 9), 34, 66))
	end
	buildCanopy(background)
	vine(background, "MotifVineLeft", {Position = UDim2.new(0.055, -30, 0.2, -12), ZIndex = 1}, 330, 11)
	vine(background, "MotifVineRight", {Position = UDim2.new(0.945, -30, 0.2, -12), ZIndex = 1}, 280, 12)
	buildStrata(background)
	for index, x in ipairs({0.03, 0.17, 0.3, 0.71, 0.85, 0.975}) do
		tuft(background, x, 40 + index)
	end
	return tracks
end

-- CTA: amber in its soil bed, inside the excavation square ---------------------------------------
local function dressPlay(background, play)
	local w, h = 300, 92
	play.Size = UDim2.fromOffset(w, h)
	play.ZIndex = 5
	play.TextSize = 36
	kit:setFont(play, "button")
	corner(play, UDim.new(1, 0))
	local edge = play:FindFirstChild("MotifEdge")
	if edge then edge.Color, edge.Thickness = P.amberDeep, 6 end
	local depth = Instance.new("UIGradient") -- resin is darker at the bottom (multiplies the dark text too: still dark)
	depth.Name = "MotifAmberDepth"
	depth.Rotation = 90
	depth.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(0.45, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(236, 204, 172)),
	})
	depth.Parent = play
	blob(play, "MotifShine", 0.18, 0.34, 0.19, 0.3, P.amberShine, {Rotation = -14})
	blob(play, "MotifShineDot", 0.29, 0.22, 0.035, 0.11, P.amberShine)
	trappedBug(frame(play, "MotifTrappedBug", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.85, 0.52), Size = UDim2.fromOffset(34, 34),
		BackgroundTransparency = 1, Rotation = 24,
	}))

	local plot, flag = excavation(background, "MotifDigPlot", {
		AnchorPoint = play.AnchorPoint, Position = play.Position, Size = UDim2.fromOffset(w + 110, h + 76), ZIndex = 2,
	}, {flag = true})
	local glow = frame(plot, "MotifAmberGlow", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(w + 46, h + 42),
		BackgroundTransparency = 1,
	})
	corner(glow, UDim.new(1, 0))
	local ring = stroke(glow, P.amberShine, 3, 0.5, "MotifGlowRing")
	local bed = frame(plot, "MotifSoilBed", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(w + 22, h + 20),
		BackgroundColor3 = P.soil,
	})
	corner(bed, UDim.new(1, 0))
	stroke(bed, P.outline, 3)
	local tag = label(plot, "MotifSiteTag", "DIG SITE A-7  ·  CRETACEOUS", 15, "note", P.ink, {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -10), Size = UDim2.fromOffset(300, 30),
		BackgroundTransparency = 0, BackgroundColor3 = P.paper, TextXAlignment = Enum.TextXAlignment.Center, Rotation = -1.5,
	})
	padding(tag, 18, 6, 0, 0)
	corner(tag, UDim.new(0, 3))
	stroke(tag, P.outline, 2)
	local pin = frame(tag, "Pin", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, -6, 0.5, 0), Size = UDim2.fromOffset(10, 10), BackgroundColor3 = P.marker})
	corner(pin, UDim.new(1, 0))
	stroke(pin, P.outline, 1.5)

	-- One slow glow, the only idle loop on the screen; paused while a page covers the amber.
	local glowTween = nil
	local function setGlow(on)
		if on and not glowTween then
			glowTween = kit:loop(ring, {Thickness = 8, Transparency = 0.1}, 2.4)
		elseif not on and glowTween then
			glowTween:Cancel()
			glowTween = nil
			ring.Thickness, ring.Transparency = 3, 0.5
		end
	end
	setGlow(true)
	-- On short screens only the amber, its bed and glow stay: strings, stakes, flag and tag would crowd
	-- the title card and the nav.
	local crowd = {tag, flag}
	for _, child in ipairs(plot:GetChildren()) do
		if child.Name == "String" or child.Name == "Stake" then table.insert(crowd, child) end
	end
	return setGlow, crowd
end

-- Title card (FIELD NOTES header) and the amber counter -------------------------------------------
local function dressTopBar(top)
	top.BackgroundTransparency = 1
	local edge = top:FindFirstChild("MotifEdge")
	if edge then edge.Transparency = 1 end
	top.Size = UDim2.new(1, -32, 0, 70)
	top.ZIndex = 5
	kit:clearTopbar(top) -- below Roblox's menu/chat buttons; the scene behind stays full-bleed

	local title = top:FindFirstChild("Title")
	title.Position, title.Size = UDim2.fromOffset(0, 0), UDim2.fromOffset(260, 46)
	title.BackgroundTransparency, title.BackgroundColor3 = 0, P.jungle
	title.TextColor3, title.TextSize, title.TextWrapped = P.white, 34, false
	title.TextXAlignment = Enum.TextXAlignment.Left
	kit:setFont(title, "display")
	padding(title, 14, 10, 0, 0)
	corner(title, UDim.new(0, 4))
	stroke(title, P.outline, 3)
	local note = label(top, "MotifTitleNote", "EXPEDITION No.07", 13, "note", P.ink, {
		Position = UDim2.fromOffset(0, 44), Size = UDim2.fromOffset(260, 24), BackgroundTransparency = 0, BackgroundColor3 = P.paper,
	})
	padding(note, 14, 6, 0, 0)
	corner(note, UDim.new(0, 4))
	stroke(note, P.outline, 3)
	vine(top, "MotifTitleVine", {Position = UDim2.fromOffset(230, -14)}, 104, 5, {minX = 24, maxX = 36, inner = 0.7})

	local coins = top:FindFirstChild("CoinLabel")
	stripCoin(coins) -- the coin emoji is Unicode 13 and renders as a box in Roblox; the drawn amber replaces it
	coins.AnchorPoint, coins.Position, coins.Size = Vector2.new(1, 0), UDim2.new(1, 0, 0, 0), UDim2.fromOffset(170, 46)
	coins.BackgroundTransparency, coins.BackgroundColor3 = 0, P.paper
	coins.TextColor3, coins.TextSize, coins.TextWrapped = P.ink, 26, false
	coins.TextXAlignment = Enum.TextXAlignment.Center
	kit:setFont(coins, "title")
	padding(coins, 50, 14, 0, 0)
	corner(coins, UDim.new(1, 0))
	stroke(coins, P.outline, 3)
	amberDrop(coins, "MotifAmber", 34, {AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, -42, 0.5, 0)})
end

-- Nav: fossil slabs lying in the strata ------------------------------------------------------------
local NAV_FIND = {Shop = "amber", Inventory = "bone", Quests = "route", Settings = "brush"}

local function setNavSelected(button, selected)
	kit.faces[button] = selected and P.jungle or P.slab
	kit:paint(button, {enabled = button.Active ~= false})
end

local function dressNav(nav)
	nav.Size = UDim2.new(0, 620, 0, 64)
	nav.ZIndex = 5
	local layout = nav:FindFirstChildOfClass("UIListLayout")
	if layout then
		layout.Padding = UDim.new(0, 12)
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
	end
	for id, kind in pairs(NAV_FIND) do
		local button = nav:FindFirstChild("Nav_" .. id)
		if button then
			button.Size = UDim2.fromOffset(146, 64)
			button.TextSize = 20
			corner(button, UDim.new(0, 14))
			kit:lip(button, 6, Color3.fromRGB(206, 196, 184)) -- the slab's broken edge (stone thickness), sinks when pressed
			padding(button, 50, 8, 0, 0)
			findWindow(button, "MotifFind", kind, 40, {AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, -42, 0.5, -2)})
			setNavSelected(button, false)
		end
	end
	-- Narrow screens: scale the row of slabs down instead of letting it run off the edge.
	local fit = nav:FindFirstChild("MotifFit") or Instance.new("UIScale")
	fit.Name = "MotifFit"
	fit.Parent = nav
	local function refit()
		local parent = nav.Parent
		local width = parent and parent.AbsoluteSize and parent.AbsoluteSize.X or 0
		fit.Scale = width > 0 and math.clamp((width - 24) / 620, 0.55, 1) or 1
	end
	refit()
	if nav.Parent then nav.Parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit) end
end

-- Pages: FIELD NOTES ------------------------------------------------------------------------------
local function dressPage(gui, entry, index)
	local page = gui:FindFirstChild(entry.page)
	page.ZIndex = 10
	page.Active = true -- the open notebook takes the clicks, so a tap on empty paper cannot reach PLAY underneath
	kit:panel(page, {color = P.paper, corner = 6})
	page.BackgroundTransparency = 0
	for _, child in ipairs(page:GetChildren()) do
		if child:IsA("GuiObject") then child.ZIndex = math.max(child.ZIndex or 1, 3) end
	end
	local header = frame(page, "MotifHeader", {Size = UDim2.new(1, 0, 0, 72), BackgroundColor3 = P.jungle, ZIndex = 1})
	corner(header, UDim.new(0, 6))
	frame(header, "Square", {Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromScale(1, 0.5), BackgroundColor3 = P.jungle})
	frame(header, "Rule", {Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = P.outline})
	local rules = frame(page, "MotifRuledPaper", {Position = UDim2.fromOffset(0, 75), Size = UDim2.new(1, 0, 1, -75), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 1})
	for line = 0, 17 do
		frame(rules, "Line", {Position = UDim2.new(0, 14, 0, 30 + line * 32), Size = UDim2.new(1, -28, 0, 1), BackgroundColor3 = P.slab, BackgroundTransparency = 0.25})
	end
	local title = page:FindFirstChild("Title")
	if title then
		title.Position, title.Size = UDim2.fromOffset(18, 6), UDim2.new(1, -150, 0, 38)
		title.TextColor3, title.TextSize = P.white, 28
		kit:setFont(title, "title")
	end
	label(page, "MotifPageNote", entry.note, 14, "note", P.leafLight, {Position = UDim2.fromOffset(18, 44), Size = UDim2.new(1, -150, 0, 20), ZIndex = 3})
	local close = page:FindFirstChild("CloseButton")
	if close then close.Position = UDim2.new(1, -110, 0, 12) end
	vine(page, "MotifPageVine", {Position = UDim2.new(1, -30, 0, 62), ZIndex = 4}, 150, 20 + index, {minX = 28, maxX = 40, inner = 0.45})
	-- Opening: the page settles in (no bounce; instant under reduced motion).
	local settle = Instance.new("UIScale")
	settle.Name = "MotifSettle"
	settle.Parent = page
	page:GetPropertyChangedSignal("Visible"):Connect(function()
		if page.Visible then
			settle.Scale = 0.97
			kit:tween(settle, {Scale = 1}, 0.18, Enum.EasingStyle.Quad)
		end
	end)
end

local function specimenEmoji(id)
	local key = string.lower(tostring(id))
	for _, entry in ipairs(SPECIMENS) do
		if string.find(key, entry[1], 1, true) then return entry[2] end
	end
	return "🦴"
end

-- Shop rows become specimen labels: tray, catalogue number, name, amber price, green BUY.
local function dressShop(page, state)
	local list = page:FindFirstChild("ProductList")
	list.Position, list.Size = UDim2.fromOffset(16, 88), UDim2.new(1, -32, 1, -100)
	list.ScrollBarImageColor3 = P.soil
	local layout = list:FindFirstChildOfClass("UIListLayout")
	if layout then layout.Padding = UDim.new(0, 10) end
	padding(list, 4, 4, 4, 4) -- the labels' ink edge sits outside their box; keep it inside the scroll clip
	for index, product in ipairs(state.products or {}) do
		local row = list:FindFirstChild("Product_" .. product.id)
		if row then
			row.Size = UDim2.new(1, -10, 0, 76)
			kit:panel(row, {color = P.panel, corner = 4, thickness = 2})
			row.BackgroundTransparency = 0
			local tray = frame(row, "MotifTray", {AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), Size = UDim2.fromOffset(54, 54), BackgroundColor3 = P.bone})
			corner(tray, UDim.new(0, 4))
			stroke(tray, P.outline, 2)
			label(tray, "Specimen", specimenEmoji(product.id), 28, "body", P.ink, {Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center})
			label(row, "MotifCatalogNo", string.format("SPECIMEN No.%03d", index), 13, "note", P.muted, {Position = UDim2.fromOffset(80, 10), Size = UDim2.new(0.5, -80, 0, 18)})
			local name = row:FindFirstChild("ProductName")
			if name then
				name.Position, name.Size = UDim2.fromOffset(80, 30), UDim2.new(0.5, -80, 0, 32)
				name.TextSize, name.TextWrapped = 20, false
				kit:setFont(name, "strong")
			end
			local price = row:FindFirstChild("Price")
			if price then
				stripCoin(price)
				price.AnchorPoint, price.Position, price.Size = Vector2.new(0, 0.5), UDim2.new(0.5, 44, 0.5, 0), UDim2.fromOffset(80, 36)
				price.TextSize, price.TextColor3 = 24, P.ink
				kit:setFont(price, "title")
				amberDrop(row, "MotifPriceAmber", 30, {AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.5, 8, 0.5, 0)})
			end
			local buy = row:FindFirstChild("BuyButton")
			if buy then
				buy.Position, buy.Size, buy.TextSize = UDim2.new(1, -124, 0.5, -24), UDim2.fromOffset(112, 48), 22
			end
		end
	end
end

local function dressSettings(page)
	for index, name in ipairs({"Toggle_Music", "Toggle_SFX"}) do
		local toggle = page:FindFirstChild(name)
		if toggle then
			toggle.Position = UDim2.new(0, 16, 0, 90 + (index - 1) * 70)
			toggle.TextSize = 20
			kit:icon(toggle, index == 1 and "🎵" or "🔊", 160)
			local function paintState() -- ON reads as a fresh leaf, OFF as bare paper
				local on = string.find(string.upper(toggle.Text), "OFF", 1, true) == nil
				kit.faces[toggle] = on and P.leaf or P.quiet
				kit:paint(toggle, {enabled = toggle.Active ~= false})
			end
			paintState()
			toggle:GetPropertyChangedSignal("Text"):Connect(paintState)
		end
	end
end

-- Inventory / Quests empty states: an empty excavation square with a find waiting in it.
local function dressEmpty(page, kind)
	local empty = page:FindFirstChild("Empty")
	if empty then
		empty.AnchorPoint, empty.Position, empty.Size = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0.5, 76), UDim2.new(1, -40, 0, 26)
		empty.TextXAlignment = Enum.TextXAlignment.Center
		kit:setFont(empty, "body")
	end
	local plot = excavation(page, "MotifEmptyPlot", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 14), Size = UDim2.fromOffset(200, 104), ZIndex = 3,
	}) -- no survey flag here: on short screens it would poke into the page header
	findWindow(plot, "MotifFind", kind, 64, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5)})
end

-- Page shade + nav selection + pausing the glow, all driven by the pages' own Visible.
local function watchPages(gui, background, nav, setGlow)
	local shade = frame(background, "MotifShade", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = P.dim, BackgroundTransparency = 0.35, ZIndex = 4, Visible = false})
	local function refresh()
		local open = nil
		for _, entry in ipairs(PAGES) do
			local page = gui:FindFirstChild(entry.page)
			if page and page.Visible then open = entry.id end
		end
		shade.Visible = open ~= nil
		if setGlow then setGlow(open == nil and gui.Enabled ~= false and background.Visible ~= false) end
		for _, entry in ipairs(PAGES) do
			local button = nav and nav:FindFirstChild("Nav_" .. entry.id)
			if button then setNavSelected(button, entry.id == open) end
		end
	end
	for _, entry in ipairs(PAGES) do
		local page = gui:FindFirstChild(entry.page)
		if page then page:GetPropertyChangedSignal("Visible"):Connect(refresh) end
	end
	gui:GetPropertyChangedSignal("Enabled"):Connect(refresh)
	background:GetPropertyChangedSignal("Visible"):Connect(refresh)
	refresh()
end

-- Short landscape phones: drop the paper tags that would crowd the title card.
local function compact(background, parts)
	local function apply()
		local size = background.AbsoluteSize
		local short = size ~= nil and size.Y > 0 and size.Y < 520
		for _, part in ipairs(parts) do
			if part then part.Visible = not short end
		end
	end
	apply()
	background:GetPropertyChangedSignal("AbsoluteSize"):Connect(apply)
end

local function step(name, fn, ...)
	local results = table.pack(pcall(fn, ...))
	if not results[1] then
		table.insert(Skin.errors, name .. ": " .. tostring(results[2]))
		warn("[DinoDigSkin] " .. name .. " skipped: " .. tostring(results[2]))
		return false
	end
	return true, table.unpack(results, 2, results.n)
end

-- Public API ---------------------------------------------------------------------------------------
-- Skin.theme(Theme): recolour the shared theme in place and wrap its builders so every panel, label and
-- button MainMenu creates comes out in the field-kit look. Idempotent; returns false for non-themes.
function Skin.theme(Theme)
	if type(Theme) ~= "table" or type(Theme.button) ~= "function" or type(Theme.colors) ~= "table" then return false end
	if Theme.skin == Skin then return true end
	local C = Theme.colors
	C.background, C.panel, C.panelLight = P.sand, P.paper, P.slab
	C.accent, C.text, C.subtext = P.amber, P.ink, P.muted
	C.danger, C.success = P.marker, P.jungle
	local original = {stroke = Theme.stroke, panel = Theme.panel, label = Theme.label, button = Theme.button}
	Skin.original = original
	-- The faint 1 px accent line becomes the field kit's ink edge (named so the kit reuses it).
	Theme.stroke = function(object)
		local edge = Instance.new("UIStroke")
		edge.Name = "MotifEdge"
		edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		edge.LineJoinMode = Enum.LineJoinMode.Round
		edge.Color, edge.Thickness, edge.Transparency = P.outline, kit.shape.stroke or 3, 0
		edge.Parent = object
		return edge
	end
	Theme.panel = function(parent, name, size, position)
		local object = original.panel(parent, name, size, position)
		pcall(function()
			kit:panel(object, {color = P.paper})
			object.BackgroundTransparency = 0
		end)
		return object
	end
	Theme.label = function(parent, name, text, size, options)
		local object = original.label(parent, name, text, size, options)
		pcall(kit.setFont, kit, object, options and options.bold and "title" or "body")
		return object
	end
	Theme.button = function(parent, name, text, onClick, options)
		local object = original.button(parent, name, text, onClick, options)
		pcall(function()
			object:SetAttribute("MotifSkinned", true) -- UITheme's own hover recolour stands down
			local role = NAME_ROLE[name] or (options and options.primary and "primary") or "slab"
			kit:styleButton(object, {face = FACES[role], pill = role == "primary"})
		end)
		return object
	end
	Theme.skin = Skin
	return true
end

-- Skin.decorate(gui, state): build the dig-site scene and the hero parts on a MainMenu ScreenGui.
-- Returns true when every step applied; failed steps are listed in Skin.errors (the menu still works).
function Skin.decorate(gui, state)
	state = state or {}
	Skin.errors = {}
	local background = gui:FindFirstChild("Background")
	assert(background, "MainMenu has no Background frame")
	pcall(function() gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling end)
	local nav = background:FindFirstChild("NavBar")
	local okScene, tracks = step("scene", buildScene, background)
	local okPlay, setGlow, extras = step("amber", dressPlay, background, background:FindFirstChild("PlayButton"))
	step("title", dressTopBar, background:FindFirstChild("TopBar"))
	step("nav", dressNav, nav)
	for index, entry in ipairs(PAGES) do
		step("page " .. entry.id, dressPage, gui, entry, index)
	end
	step("shop", dressShop, gui:FindFirstChild("ShopPage"), state)
	step("settings", dressSettings, gui:FindFirstChild("SettingsPage"))
	step("inventory", dressEmpty, gui:FindFirstChild("InventoryPage"), "bone")
	step("quests", dressEmpty, gui:FindFirstChild("QuestsPage"), "route")
	step("pages", watchPages, gui, background, nav, okPlay and setGlow or nil)
	local crowd = {}
	for _, part in ipairs(okPlay and extras or {}) do table.insert(crowd, part) end
	for _, part in ipairs(okScene and tracks or {}) do table.insert(crowd, part) end
	step("compact", compact, background, crowd)
	return #Skin.errors == 0
end

return Skin
