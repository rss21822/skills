-- FestivalArt: 縁日 (festival stall) illustrations drawn from plain Frames, so there are no image assets to
-- upload or moderate: 提灯 (paper lantern), 金魚 (goldfish, seen from above as in a 金魚すくい tub),
-- りんご飴 (candy apple), ラムネ (ramune bottle with its glass marble), 五円玉 (coin), 的 (shooting-gallery
-- target), うちわ (fan), 金魚袋 (goldfish bag), 太鼓 (drum), 風鈴 (wind chime), ポイ (scoop), 暖簾 (shop curtain),
-- 屋号紋 (shop crest) and a ラムネ marble switch.
--
-- Every piece is decorative: Active = false, so none of it swallows clicks meant for buttons underneath.
-- Geometry is in scale space of each illustration's root, so the art scales with whatever size it is given.
local Theme = require(script.Parent:WaitForChild("UITheme"))

local P = Theme.palette
local create = Theme.create
local WHITE = Color3.new(1, 1, 1)

local Art = {}

local function gray(value)
	return Color3.new(value, value, value)
end

-- Creation order = draw order (explicit ZIndex, so it does not depend on engine tie-breaking).
local zCounter = setmetatable({}, {__mode = "k"})
local function nextZ(parent)
	local z = (zCounter[parent] or 0) + 1
	zCounter[parent] = z
	return z
end

local function merge(props, extra)
	if extra then
		for key, value in pairs(extra) do props[key] = value end
	end
	return props
end

-- Rectangle centred on (cx, cy) in the parent's scale space.
local function piece(parent, name, color, cx, cy, w, h, extra)
	return create("Frame", merge({Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(cx, cy),
		Size = UDim2.fromScale(w, h), BackgroundColor3 = color or WHITE, BackgroundTransparency = 0, BorderSizePixel = 0,
		Active = false, ZIndex = nextZ(parent), Parent = parent}, extra))
end

-- Pill / stadium.
local function blob(parent, name, color, cx, cy, w, h, extra)
	local frame = piece(parent, name, color, cx, cy, w, h, extra)
	Theme.round(frame)
	return frame
end

-- Circle whose diameter d is a fraction of the parent's width (SizeConstraint RelativeXX keeps it round).
local function circle(parent, name, color, cx, cy, d, extra)
	local frame = piece(parent, name, color, cx, cy, d, d, merge({SizeConstraint = Enum.SizeConstraint.RelativeXX}, extra))
	Theme.round(frame)
	return frame
end

local function group(parent, name, props)
	return create("Frame", merge({Name = name, BackgroundTransparency = 1, BorderSizePixel = 0, Active = false,
		Size = UDim2.fromScale(1, 1), ZIndex = nextZ(parent), Parent = parent}, props))
end

local function glyph(parent, name, text, color, cx, cy, w, h, extra)
	return create("TextLabel", merge({Name = name, Text = text, TextScaled = true, FontFace = Theme.faces.bold,
		TextColor3 = color, BackgroundTransparency = 1, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(cx, cy), Size = UDim2.fromScale(w, h), TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center, ZIndex = nextZ(parent), Parent = parent}, extra))
end

local function aspect(object, ratio)
	return create("UIAspectRatioConstraint", {AspectRatio = ratio, Parent = object})
end

Art.gray = gray

-- 提灯 ----------------------------------------------------------------------------------------------
-- A paper lantern filling its root (about 0.72 wide : 1 tall). kind = "red" | "white".
-- Returns root, {glows} (frames whose transparency the menu flickers).
function Art.lantern(parent, name, kind, text, props)
	local white = kind == "white"
	local body = white and P.washi or P.vermilion
	local rib = white and P.washiShade or P.vermilionDeep
	local ink = white and P.vermilion or P.lacquer
	local root = group(parent, name, props)

	local halo = blob(root, "Halo", P.lanternGlow, 0.5, 0.55, 2.0, 1.4, {BackgroundTransparency = 0.86})
	local haloInner = blob(root, "HaloInner", P.lanternGlow, 0.5, 0.55, 1.35, 0.98, {BackgroundTransparency = 0.76})
	piece(root, "Cord", P.lacquer, 0.5, 0.05, 0, 0.12, {Size = UDim2.new(0, 2, 0.12, 0)})
	Theme.corner(piece(root, "TopRing", P.lacquer, 0.5, 0.125, 0.52, 0.07), 3)

	local volume = {{0, gray(0.72)}, {0.5, WHITE}, {1, gray(0.72)}}
	Theme.gradient(blob(root, "BodyTall", body, 0.5, 0.52, 0.8, 0.76), volume, 0)
	Theme.gradient(blob(root, "BodyWide", body, 0.5, 0.52, 1, 0.54), volume, 0)
	local core = blob(root, "Core", white and P.lanternGlow or P.lanternCore, 0.5, 0.52, 0.52, 0.5,
		{BackgroundTransparency = white and 0.72 or 0.62})

	for index, y in ipairs({0.25, 0.32, 0.39, 0.46, 0.53, 0.6, 0.67, 0.74, 0.8}) do
		local t = (y - 0.52) / 0.39
		local width = math.max(0.3, math.sqrt(math.max(0, 1 - t * t)) * 0.88)
		piece(root, "Rib" .. index, rib, 0.5, y, width, 0, {Size = UDim2.new(width, 0, 0, 1), BackgroundTransparency = 0.45})
	end
	glyph(root, "Glyph", text or "祭", ink, 0.5, 0.53, 0.62, 0.42)
	Theme.corner(piece(root, "BottomRing", P.lacquer, 0.5, 0.905, 0.46, 0.06), 3)
	piece(root, "Tassel", white and P.vermilion or P.gold, 0.5, 0.965, 0, 0.07, {Size = UDim2.new(0, 3, 0.07, 0)})
	return root, {halo, haloInner, core}
end

-- 金魚 ------------------------------------------------------------------------------------------------
-- Seen from above, facing +X (Rotation turns it). length in pixels. Returns root, tail (wag its Rotation).
local FISH = {
	red = {body = P.goldfish, head = P.vermilion, tail = P.goldfishLight, eye = P.ink, eyeScale = 0.085, eyeY = 0.32},
	orange = {body = P.goldfishLight, head = P.goldfish, tail = P.lanternCore, eye = P.ink, eyeScale = 0.085, eyeY = 0.32},
	calico = {body = P.washiWhite, head = P.goldfish, tail = P.washi, patch = P.goldfish, eye = P.ink, eyeScale = 0.085, eyeY = 0.32},
	demekin = {body = P.demekin, head = Color3.fromRGB(22, 17, 19), tail = Color3.fromRGB(78, 64, 70), eye = Color3.fromRGB(58, 50, 54),
		eyeScale = 0.15, eyeY = 0.1},
}
function Art.goldfish(parent, name, kind, length)
	local look = FISH[kind] or FISH.red
	local fishLength = length or 46
	local root = group(parent, name, {AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(fishLength, math.floor(fishLength * 0.55))})

	-- The tail box is centred on the tail joint so rotating it wags the tail from the body.
	local tail = group(root, "Tail", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.38, 0.5), Size = UDim2.fromScale(0.76, 1.5)})
	blob(tail, "LobeTop", look.tail, 0.27, 0.38, 0.52, 0.26, {Rotation = -24, BackgroundTransparency = 0.12})
	blob(tail, "LobeBottom", look.tail, 0.27, 0.62, 0.52, 0.26, {Rotation = 24, BackgroundTransparency = 0.12})
	blob(tail, "LobeCore", look.body, 0.42, 0.5, 0.26, 0.14, {BackgroundTransparency = 0.05})

	blob(root, "FinTop", look.tail, 0.62, 0.15, 0.2, 0.24, {Rotation = -38, BackgroundTransparency = 0.2})
	blob(root, "FinBottom", look.tail, 0.62, 0.85, 0.2, 0.24, {Rotation = 38, BackgroundTransparency = 0.2})
	Theme.gradient(blob(root, "Body", look.body, 0.63, 0.5, 0.56, 0.62), {{0, WHITE}, {1, gray(0.84)}}, 0)
	if look.patch then blob(root, "Patch", look.patch, 0.56, 0.42, 0.24, 0.34, {Rotation = 18}) end
	blob(root, "Head", look.head, 0.82, 0.5, 0.28, 0.5)
	blob(root, "Sheen", WHITE, 0.62, 0.4, 0.3, 0.13, {BackgroundTransparency = 0.62})
	local eye = math.max(3, math.floor(fishLength * look.eyeScale + 0.5))
	blob(root, "EyeTop", look.eye, 0.86, look.eyeY, 0, 0, {Size = UDim2.fromOffset(eye, eye)})
	blob(root, "EyeBottom", look.eye, 0.86, 1 - look.eyeY, 0, 0, {Size = UDim2.fromOffset(eye, eye)})
	return root, tail
end

-- りんご飴 ---------------------------------------------------------------------------------------------
function Art.candyApple(parent, name, props)
	local root = group(parent, name, props)
	aspect(root, 0.56)
	Theme.corner(piece(root, "Stick", P.woodLight, 0.5, 0.775, 0.09, 0.45), 2)
	blob(root, "Pool", P.candy, 0.5, 0.588, 0.66, 0.045, {BackgroundTransparency = 0.1})
	local apple = circle(root, "Apple", P.candy, 0.5, 0.33, 0.94)
	Theme.gradient(apple, {{0, WHITE}, {0.55, gray(0.84)}, {1, gray(0.52)}}, 55)
	blob(root, "Gloss", WHITE, 0.33, 0.21, 0.2, 0.05, {Rotation = -38, BackgroundTransparency = 0.18})
	circle(root, "Glint", WHITE, 0.67, 0.16, 0.09, {BackgroundTransparency = 0.15})
	Theme.corner(piece(root, "Stem", P.woodDark, 0.5, 0.055, 0.06, 0.06), 2)
	blob(root, "Leaf", P.leaf, 0.63, 0.06, 0.22, 0.045, {Rotation = -22})
	return root
end

-- A wooden stand holding three candy apples, with a paper price tag.
function Art.appleStand(parent, name, props)
	local root = group(parent, name, props)
	aspect(root, 0.95)
	Art.candyApple(root, "AppleLeft", {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.25, 0.8), Size = UDim2.fromScale(1, 0.62), Rotation = -9})
	Art.candyApple(root, "AppleRight", {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.75, 0.8), Size = UDim2.fromScale(1, 0.62), Rotation = 9})
	Art.candyApple(root, "AppleFront", {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.84), Size = UDim2.fromScale(1, 0.74)})
	local block = piece(root, "Block", P.wood, 0.5, 0.88, 0.96, 0.2)
	Theme.corner(block, 6)
	Theme.stroke(block, P.woodDark, 2)
	Theme.shade(block, 90, 0.25)
	piece(root, "BlockTop", P.woodLight, 0.5, 0.795, 0.9, 0, {Size = UDim2.new(0.9, 0, 0, 4), BackgroundTransparency = 0.2})
	local tag = piece(root, "Tag", P.washiWhite, 0.5, 0.885, 0.56, 0.12, {Rotation = -3})
	Theme.corner(tag, 3)
	Theme.stroke(tag, P.woodDark, 1.5)
	glyph(tag, "Text", "りんご飴", P.candyDeep, 0.5, 0.5, 0.9, 0.84)
	return root
end

-- ラムネ -----------------------------------------------------------------------------------------------
-- Glass is drawn opaque (a pale aqua) so the overlapping parts merge into one bottle silhouette:
-- body, shoulder, neck, the pinch that traps the marble, the marble chamber and the mouth.
-- Returns root, {bubbles}.
function Art.ramune(parent, name, props)
	local root = group(parent, name, props)
	aspect(root, 0.32)
	local glass = P.ramune
	local volume = {{0, gray(0.78)}, {0.32, WHITE}, {1, gray(0.74)}}
	Theme.gradient(blob(root, "Body", glass, 0.5, 0.7, 1, 0.6), {{0, gray(0.8)}, {0.32, WHITE}, {1, gray(0.7)}}, 0)
	Theme.gradient(blob(root, "Neck", glass, 0.5, 0.38, 0.5, 0.16), volume, 0)
	Theme.gradient(piece(root, "Pinch", glass, 0.5, 0.3, 0.34, 0.05), volume, 0)
	Theme.gradient(blob(root, "Chamber", glass, 0.5, 0.225, 0.6, 0.12), volume, 0)
	Theme.gradient(blob(root, "Mouth", glass, 0.5, 0.14, 0.44, 0.07), volume, 0)
	local bubbles = {}
	for index = 1, 4 do
		bubbles[index] = circle(root, "Bubble" .. index, WHITE, 0.3 + 0.13 * (index % 3), 0.92 - index * 0.07, 0.1,
			{BackgroundTransparency = 0.3})
	end
	local marble = circle(root, "Marble", P.ramuneFoam, 0.5, 0.225, 0.4)
	Theme.stroke(marble, P.ramuneDeep, 1, 0.3)
	circle(root, "MarbleGlint", WHITE, 0.42, 0.212, 0.12)
	Theme.gradient(blob(root, "Cap", P.vermilion, 0.5, 0.085, 0.5, 0.075), volume, 0)
	Theme.corner(piece(root, "CapRing", P.washi, 0.5, 0.125, 0.52, 0.02), 2)
	local band = piece(root, "Band", P.washiWhite, 0.5, 0.72, 1, 0.1)
	Theme.corner(band, 2)
	glyph(band, "Brand", "ラムネ", P.ramuneDeep, 0.5, 0.5, 0.78, 0.72)
	blob(root, "Highlight", WHITE, 0.24, 0.72, 0.1, 0.38, {BackgroundTransparency = 0.5})
	return root, bubbles
end

-- Two bottles cooling in a tub of ice water. Returns root, {bubbles}.
function Art.ramuneCooler(parent, name, props)
	local root = group(parent, name, props)
	aspect(root, 0.9)
	local back = blob(root, "BasinBack", P.waterDeep, 0.5, 0.84, 0.98, 0.2, {BackgroundTransparency = 0.25})
	Theme.stroke(back, P.woodDark, 2)
	local _, bubblesA = Art.ramune(root, "BottleA", {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.36, 0.9),
		Size = UDim2.fromScale(1, 0.86), Rotation = -6})
	local _, bubblesB = Art.ramune(root, "BottleB", {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.66, 0.92),
		Size = UDim2.fromScale(1, 0.76), Rotation = 7})
	local water = blob(root, "WaterFront", P.water, 0.5, 0.88, 0.98, 0.16, {BackgroundTransparency = 0.3})
	Theme.stroke(water, WHITE, 1.5, 0.4)
	for index, spec in ipairs({{0.22, 0.83, -14}, {0.52, 0.86, 10}, {0.78, 0.82, 24}}) do
		local cube = piece(root, "Ice" .. index, P.ramuneFoam, spec[1], spec[2], 0.13, 0.13,
			{SizeConstraint = Enum.SizeConstraint.RelativeXX, Rotation = spec[3], BackgroundTransparency = 0.25})
		Theme.corner(cube, 4)
		Theme.stroke(cube, WHITE, 1.5, 0.2)
	end
	local bubbles = {}
	for _, list in ipairs({bubblesA, bubblesB}) do
		for _, bubble in ipairs(list) do table.insert(bubbles, bubble) end
	end
	return root, bubbles
end

-- 五円玉 ----------------------------------------------------------------------------------------------
function Art.coin(parent, name, props, holeColor)
	local root = group(parent, name, props)
	local disc = circle(root, "Disc", P.gold, 0.5, 0.5, 1)
	Theme.gradient(disc, {{0, WHITE}, {1, gray(0.74)}}, 45)
	Theme.stroke(disc, P.goldDeep, 1.5)
	Theme.stroke(circle(root, "Ring", P.gold, 0.5, 0.5, 0.72, {BackgroundTransparency = 1}), P.goldDeep, 1, 0.5)
	Theme.stroke(circle(root, "Hole", holeColor or P.washi, 0.5, 0.5, 0.3), P.goldDeep, 1.5)
	blob(root, "Glint", WHITE, 0.33, 0.25, 0.28, 0.1, {Rotation = -40, BackgroundTransparency = 0.35})
	return root
end

-- 的 (射的) ---------------------------------------------------------------------------------------------
function Art.target(parent, name, props, withArrow)
	local root = group(parent, name, props)
	local rings = {{1, P.vermilion}, {0.8, P.washiWhite}, {0.6, P.vermilion}, {0.4, P.washiWhite}, {0.2, P.vermilion}}
	for index, spec in ipairs(rings) do
		local ring = circle(root, "Ring" .. index, spec[2], 0.5, 0.5, spec[1])
		if index == 1 then Theme.stroke(ring, P.woodDark, 2) end
	end
	if withArrow then
		local arrow = group(root, "Arrow", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.72, 0.3),
			Size = UDim2.fromScale(0.62, 0.62), SizeConstraint = Enum.SizeConstraint.RelativeXX, Rotation = -40})
		Theme.corner(piece(arrow, "Shaft", P.woodLight, 0.5, 0.5, 0.9, 0.06), 2)
		piece(arrow, "FeatherA", P.washiWhite, 0.9, 0.42, 0.18, 0.1, {Rotation = 25})
		piece(arrow, "FeatherB", P.washiWhite, 0.9, 0.58, 0.18, 0.1, {Rotation = -25})
	end
	return root
end

-- うちわ -----------------------------------------------------------------------------------------------
function Art.uchiwa(parent, name, props)
	local root = group(parent, name, props)
	local handle = piece(root, "Handle", P.woodLight, 0.5, 0.8, 0.14, 0.42)
	Theme.corner(handle, 3)
	Theme.stroke(handle, P.woodDark, 1)
	local face = circle(root, "Paper", P.washiWhite, 0.5, 0.4, 0.8)
	Theme.stroke(face, P.vermilion, 2)
	blob(face, "Wave", P.ramune, 0.5, 0.78, 0.86, 0.22)
	blob(face, "FishBody", P.goldfish, 0.52, 0.45, 0.36, 0.2, {Rotation = -12})
	blob(face, "FishTail", P.goldfishLight, 0.3, 0.5, 0.18, 0.2, {Rotation = 20})
	return root
end

-- 金魚袋 ----------------------------------------------------------------------------------------------
function Art.goldfishBag(parent, name, props, fishLength)
	local root = group(parent, name, props)
	local air = blob(root, "Air", WHITE, 0.5, 0.36, 0.5, 0.34, {BackgroundTransparency = 0.72})
	Theme.stroke(air, WHITE, 1.5, 0.3)
	local water = blob(root, "Water", P.water, 0.5, 0.68, 0.9, 0.58, {BackgroundTransparency = 0.25})
	Theme.stroke(water, WHITE, 1.5, 0.15)
	if fishLength then
		local fish = Art.goldfish(root, "Fish", "red", fishLength)
		fish.Position = UDim2.fromScale(0.5, 0.7)
		fish.Rotation = -18
	end
	blob(root, "Glint", WHITE, 0.26, 0.64, 0.08, 0.3, {BackgroundTransparency = 0.45})
	blob(root, "Tie", P.vermilion, 0.5, 0.17, 0.34, 0.07)
	local loop = blob(root, "Loop", P.vermilion, 0.5, 0.07, 0.26, 0.13, {BackgroundTransparency = 1})
	Theme.stroke(loop, P.vermilion, 2)
	return root
end

-- 太鼓 (music): drum face with a 巴 crest, the two bachi resting behind it (never crossing the face,
-- which would read as a "muted" sign).
function Art.taiko(parent, name, props)
	local root = group(parent, name, props)
	Theme.corner(piece(root, "StickA", P.woodLight, 0.3, 0.2, 0.62, 0.09, {Rotation = 55}), 3)
	Theme.corner(piece(root, "StickB", P.woodLight, 0.7, 0.2, 0.62, 0.09, {Rotation = -55}), 3)
	local rim = circle(root, "Rim", P.vermilionDeep, 0.5, 0.56, 0.88)
	Theme.stroke(rim, P.woodDark, 1.5)
	circle(root, "Head", P.washiWhite, 0.5, 0.56, 0.68)
	for index, spec in ipairs({{0.5, 0.45}, {0.4, 0.62}, {0.6, 0.62}}) do
		circle(root, "Tomoe" .. index, P.vermilion, spec[1], spec[2], 0.18)
	end
	return root
end

-- 風鈴 (sound effects) ---------------------------------------------------------------------------------
function Art.furin(parent, name, props)
	local root = group(parent, name, props)
	piece(root, "String", P.inkSoft, 0.5, 0.62, 0, 0.3, {Size = UDim2.new(0, 1, 0.3, 0)})
	local strip = piece(root, "Tanzaku", P.washiWhite, 0.5, 0.86, 0.3, 0.26, {Rotation = 8})
	Theme.stroke(strip, P.vermilion, 1.5)
	local bell = circle(root, "Bell", P.ramune, 0.5, 0.36, 0.66, {BackgroundTransparency = 0.15})
	Theme.stroke(bell, P.ramuneDeep, 1.5)
	blob(bell, "Pattern", P.vermilion, 0.6, 0.45, 0.3, 0.16, {Rotation = -15})
	piece(root, "Lip", P.ramuneDeep, 0.5, 0.52, 0.6, 0, {Size = UDim2.new(0.6, 0, 0, 2)})
	return root
end

-- ポイ (goldfish scoop) ---------------------------------------------------------------------------------
function Art.poi(parent, name, props)
	local root = group(parent, name, props)
	aspect(root, 0.46)
	local pink = Color3.fromRGB(241, 106, 142)
	Theme.corner(piece(root, "Handle", pink, 0.5, 0.74, 0.2, 0.52), 4)
	local rim = circle(root, "Rim", pink, 0.5, 0.25, 1)
	Theme.stroke(rim, Color3.fromRGB(176, 58, 92), 1.5)
	circle(root, "Paper", P.washiWhite, 0.5, 0.25, 0.78, {BackgroundTransparency = 0.12})
	return root
end

-- 屋号紋 (a shop crest with one character) ---------------------------------------------------------------
function Art.crest(parent, name, text, color, props)
	local root = group(parent, name, props)
	local disc = circle(root, "Disc", color or P.vermilion, 0.5, 0.5, 1)
	Theme.stroke(disc, P.woodDark, 1.5)
	Theme.stroke(circle(root, "Ring", color or P.vermilion, 0.5, 0.5, 0.82, {BackgroundTransparency = 1}), P.washi, 1.5, 0.3)
	glyph(root, "Glyph", text, P.washi, 0.5, 0.52, 0.56, 0.56)
	return root
end

-- 暖簾 (shop curtain) across the top of a panel ----------------------------------------------------------
function Art.noren(parent, color, height)
	local root = group(parent, "Noren", {Size = UDim2.new(1, 0, 0, height or 64)})
	local cloth = piece(root, "Cloth", color, 0.5, 0.5, 1, 1)
	Theme.corner(cloth, 12)
	Theme.gradient(cloth, {{0, WHITE}, {1, gray(0.86)}}, 90)
	piece(root, "Seam", color:Lerp(Color3.new(0, 0, 0), 0.3), 0.5, 0.16, 1, 0, {Size = UDim2.new(1, 0, 0, 2), BackgroundTransparency = 0.35})
	for index = 1, 3 do
		piece(root, "Slit" .. index, P.washi, index / 4, 0.8, 0, 0.4, {Size = UDim2.new(0, 6, 0.4, 0)})
	end
	local rod = piece(root, "Rod", P.woodDark, 0.5, 0, 0, 0, {Size = UDim2.new(1, 18, 0, 8)})
	Theme.round(rod)
	return root
end

-- ラムネ switch: the marble rolls right (ON, fizzy aqua) or left (OFF, empty glass). Returns root, set(on, animate).
function Art.ramuneSwitch(parent, name, on, props)
	local track = create("Frame", merge({Name = name, Size = UDim2.fromOffset(78, 36), BackgroundColor3 = P.ramune,
		BorderSizePixel = 0, Active = false, ZIndex = nextZ(parent), Parent = parent}, props))
	Theme.round(track)
	Theme.stroke(track, P.ramuneDeep, 2)
	local fizz = {}
	for index, x in ipairs({0.2, 0.33, 0.46}) do
		fizz[index] = circle(track, "Fizz" .. index, WHITE, x, 0.5 + (index % 2 == 0 and 0.12 or -0.1), 0.07, {BackgroundTransparency = 0.25})
	end
	local knob = create("Frame", {Name = "Marble", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(28, 28),
		Position = UDim2.new(0, 18, 0.5, 0), BackgroundColor3 = P.ramuneFoam, BorderSizePixel = 0, Active = false,
		ZIndex = nextZ(track), Parent = track})
	Theme.round(knob)
	Theme.stroke(knob, P.ramuneDeep, 1.5)
	circle(knob, "Glint", WHITE, 0.36, 0.32, 0.3)
	local function set(value, animate)
		track.BackgroundColor3 = value and P.ramune or Color3.fromRGB(205, 214, 216)
		for _, bubble in ipairs(fizz) do bubble.Visible = value end
		local target = UDim2.new(0, value and 60 or 18, 0.5, 0)
		if animate then Theme.tween(knob, 0.16, {Position = target}, Enum.EasingStyle.Back) else knob.Position = target end
	end
	set(on, false)
	return track, set
end

return Art
