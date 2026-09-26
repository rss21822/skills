-- Retro-toy decorations drawn from plain Frames / TextLabels (no uploaded images needed):
-- the striped awning, confetti dots, the teal donut, stars, the little robot, coins and small icons.
-- All of it is non-interactive (Frames/TextLabels only, Active = false) so it never steals input.
local Theme = require(script.Parent:WaitForChild("UITheme"))

local create = Theme.create
local P = Theme.palette

local ToyDecor = {}

local function square(object, ratio)
	create("UIAspectRatioConstraint", {AspectRatio = ratio or 1, Parent = object})
	return object
end

-- A circle. size / position are UDim2; circles sized by Scale get a 1:1 constraint.
local function circle(parent, name, color, size, position, stroke)
	local frame = create("Frame", {Name = name, Size = size, Position = position or UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = color, BorderSizePixel = 0, Parent = parent})
	Theme.corner(frame, UDim.new(0.5, 0))
	if stroke and stroke > 0 then Theme.stroke(frame, stroke) end
	if size.X.Scale > 0 or size.Y.Scale > 0 then square(frame) end
	return frame
end
ToyDecor.circle = circle

-- A text glyph drawn as a shape (★, ♪). Glyphs used here are in JIS X 0208, so the Japanese
-- fallback font always has them.
local function glyph(parent, name, text, color, size, position, stroke, rotation)
	local label = create("TextLabel", {Name = name, Text = text, TextScaled = true, FontFace = Theme.fonts.heavy,
		TextColor3 = color, BackgroundTransparency = 1, Size = size, Position = position or UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5), Rotation = rotation or 0, Parent = parent})
	if stroke and stroke > 0 then
		create("UIStroke", {Color = P.brown, Thickness = stroke, LineJoinMode = Enum.LineJoinMode.Round,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Parent = label})
	end
	return label
end
ToyDecor.glyph = glyph

-- Scale-sized decoration: `height` is a fraction of the parent's height, width follows `ratio`
-- (the 1 x height box is shrunk to the ratio by FitWithinMaxSize).
local function holder(parent, name, position, height, ratio, zIndex)
	local frame = create("Frame", {Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = position,
		Size = UDim2.fromScale(1, height), BackgroundTransparency = 1, ZIndex = zIndex or 1, Parent = parent})
	square(frame, ratio or 1)
	return frame
end

-- Mustard / cream diagonal stripes with a brown rule underneath (top of the mood board).
function ToyDecor.awning(parent, height, zIndex)
	local awning = create("Frame", {Name = "Awning", Size = UDim2.new(1, 0, 0, height), BackgroundColor3 = P.cream,
		BorderSizePixel = 0, ClipsDescendants = true, ZIndex = zIndex or 2, Parent = parent})
	-- Fixed pixel pitch so stripes keep their width on any screen; 96 stripes cover ~3900 px.
	for index = 0, 95 do
		create("Frame", {Name = "Stripe", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, index * 42 - 60, 0.5, 0),
			Size = UDim2.new(0, 17, 0, height * 2 + 40), Rotation = 45, BackgroundColor3 = P.mustard, BorderSizePixel = 0,
			Parent = awning})
	end
	create("Frame", {Name = "AwningRule", Position = UDim2.new(0, 0, 0, height), Size = UDim2.new(1, 0, 0, 8),
		BackgroundColor3 = P.brown, BorderSizePixel = 0, ZIndex = zIndex or 2, Parent = parent})
	return awning
end

-- Flat confetti dots scattered around the edges (kept clear of the centre column).
local DOTS = {
	{0.045, 0.25, 18, "teal"}, {0.10, 0.20, 10, "coral"}, {0.03, 0.60, 22, "mustard"}, {0.075, 0.78, 14, "mint"},
	{0.13, 0.88, 20, "teal"}, {0.21, 0.24, 10, "mustard"}, {0.28, 0.31, 16, "coral"}, {0.36, 0.22, 12, "sky"},
	{0.64, 0.22, 10, "coral"}, {0.73, 0.28, 18, "mustard"}, {0.79, 0.21, 12, "mint"}, {0.955, 0.22, 16, "coral"},
	{0.915, 0.17, 10, "teal"}, {0.97, 0.47, 12, "mint"}, {0.965, 0.78, 20, "mustard"}, {0.91, 0.88, 14, "sky"},
	{0.74, 0.80, 20, "teal"}, {0.69, 0.74, 12, "coral"}, {0.33, 0.75, 16, "mint"}, {0.27, 0.84, 12, "coral"},
	{0.40, 0.70, 10, "mustard"}, {0.60, 0.70, 14, "sky"},
}
-- top: px kept clear at the top (the awning), dots are spread over the rest.
function ToyDecor.confetti(parent, zIndex, top)
	top = top or 0
	local layer = create("Frame", {Name = "Confetti", Position = UDim2.fromOffset(0, top), Size = UDim2.new(1, 0, 1, -top),
		BackgroundTransparency = 1, ZIndex = zIndex or 1, Parent = parent})
	for index, dot in ipairs(DOTS) do
		circle(layer, "Dot" .. index, P[dot[4]], UDim2.fromOffset(dot[3], dot[3]), UDim2.fromScale(dot[1], dot[2]))
	end
	return layer
end

-- The teal donut ring.
-- holeColor should match whatever is behind the donut (cream background by default).
function ToyDecor.donut(parent, name, position, height, zIndex, holeColor)
	local box = holder(parent, name, position, height, 1, zIndex)
	circle(box, "Ring", P.teal, UDim2.fromScale(1, 1), nil, 5)
	circle(box, "Hole", holeColor or P.cream, UDim2.fromScale(0.42, 0.42), nil, 5)
	return box
end

function ToyDecor.star(parent, name, color, position, height, rotation, zIndex)
	local box = holder(parent, name, position, height, 1, zIndex)
	glyph(box, "Shape", "★", color, UDim2.fromScale(1, 1), nil, 2, rotation)
	return box
end

-- The sky-blue robot: rounded head, white eyes, antenna with a coral ball (+ coral cheeks).
function ToyDecor.robot(parent, name, position, height, zIndex)
	local box = holder(parent, name, position, height, 0.78, zIndex)
	create("Frame", {Name = "Antenna", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.1),
		Size = UDim2.fromScale(0.07, 0.24), BackgroundColor3 = P.brown, BorderSizePixel = 0, Parent = box})
	circle(box, "AntennaBall", P.coral, UDim2.fromScale(0.24, 0.24), UDim2.fromScale(0.5, 0.1), 4)
	local head = create("Frame", {Name = "Head", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromScale(1, 0.7), BackgroundColor3 = P.sky, BorderSizePixel = 0, Parent = box})
	Theme.corner(head, UDim.new(0.18, 0))
	Theme.stroke(head, 5)
	circle(head, "EyeLeft", P.white, UDim2.fromScale(0.3, 0.3), UDim2.fromScale(0.3, 0.4), 4)
	circle(head, "EyeRight", P.white, UDim2.fromScale(0.3, 0.3), UDim2.fromScale(0.7, 0.4), 4)
	local cheekL = circle(head, "CheekLeft", P.coral, UDim2.fromScale(0.13, 0.13), UDim2.fromScale(0.16, 0.7))
	local cheekR = circle(head, "CheekRight", P.coral, UDim2.fromScale(0.13, 0.13), UDim2.fromScale(0.84, 0.7))
	cheekL.BackgroundTransparency, cheekR.BackgroundTransparency = 0.25, 0.25
	create("Frame", {Name = "Mouth", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.74),
		Size = UDim2.fromScale(0.22, 0.06), BackgroundColor3 = P.brown, BorderSizePixel = 0, Parent = head})
	return box
end

-- Small pixel-sized icons (nav tabs, shop rows, settings). holder is a px x px transparent frame.
local ICONS = {}

function ICONS.coin(frame, px)
	local outline = px >= 36 and 3 or 2
	circle(frame, "Coin", P.mustard, UDim2.new(1, -outline * 2, 1, -outline * 2), nil, outline)
	local inner = circle(frame, "Rim", P.mustard, UDim2.new(0.58, 0, 0.58, 0), nil, 2)
	inner.BackgroundTransparency = 1
end

function ICONS.ring(frame, px)
	local outline = px >= 36 and 3 or 2
	circle(frame, "Ring", P.teal, UDim2.new(1, -outline * 2, 1, -outline * 2), nil, outline)
	circle(frame, "Hole", P.creamLight, UDim2.fromScale(0.4, 0.4), nil, outline)
end

function ICONS.star(frame, px)
	glyph(frame, "Star", "★", P.mustard, UDim2.fromScale(1.15, 1.15), nil, px >= 36 and 2 or 1.5)
end

function ICONS.twostars(frame, px)
	glyph(frame, "StarBack", "★", P.coral, UDim2.fromScale(0.8, 0.8), UDim2.fromScale(0.34, 0.36), 1.5, -12)
	glyph(frame, "StarFront", "★", P.mustard, UDim2.fromScale(0.9, 0.9), UDim2.fromScale(0.64, 0.62), px >= 36 and 2 or 1.5, 8)
end

function ICONS.bot(frame, px)
	local outline = px >= 36 and 3 or 2
	create("Frame", {Name = "Antenna", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.08),
		Size = UDim2.new(0, math.max(2, math.floor(px / 14)), 0.26, 0), BackgroundColor3 = P.brown, BorderSizePixel = 0, Parent = frame})
	circle(frame, "Ball", P.coral, UDim2.fromOffset(math.floor(px * 0.26), math.floor(px * 0.26)), UDim2.fromScale(0.5, 0.1), outline - 1)
	local head = create("Frame", {Name = "Head", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -outline),
		Size = UDim2.new(0.84, 0, 0.62, 0), BackgroundColor3 = P.sky, BorderSizePixel = 0, Parent = frame})
	Theme.corner(head, UDim.new(0.2, 0))
	Theme.stroke(head, outline)
	local eye = math.max(5, math.floor(px * 0.2))
	circle(head, "EyeLeft", P.white, UDim2.fromOffset(eye, eye), UDim2.fromScale(0.3, 0.45), outline - 1)
	circle(head, "EyeRight", P.white, UDim2.fromOffset(eye, eye), UDim2.fromScale(0.7, 0.45), outline - 1)
end

function ICONS.rainbow(frame, px)
	local outline = px >= 36 and 3 or 2
	local clip = create("Frame", {Name = "Arc", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.78),
		Size = UDim2.new(1, outline * 2, 0.5, outline), BackgroundTransparency = 1, ClipsDescendants = true, Parent = frame})
	local bands = {{P.coral, 1}, {P.mustard, 0.74}, {P.teal, 0.48}, {P.creamLight, 0.24}}
	for index, band in ipairs(bands) do
		local size = math.floor(px * band[2])
		local disc = circle(clip, "Band" .. index, band[1], UDim2.fromOffset(size - outline * 2, size - outline * 2),
			UDim2.new(0.5, 0, 1, 0), outline)
		disc.ZIndex = index
	end
	create("Frame", {Name = "Ground", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.78),
		Size = UDim2.new(1, 0, 0, outline), BackgroundColor3 = P.brown, BorderSizePixel = 0, Parent = frame})
end

function ICONS.note(frame, px)
	circle(frame, "Badge", P.mint, UDim2.new(1, -4, 1, -4), nil, 2)
	glyph(frame, "Note", "♪", P.brown, UDim2.fromScale(0.78, 0.78), UDim2.fromScale(0.5, 0.52))
end

function ICONS.sparkle(frame, px)
	circle(frame, "Badge", P.mustard, UDim2.new(1, -4, 1, -4), nil, 2)
	glyph(frame, "Spark", "★", P.creamLight, UDim2.fromScale(0.72, 0.72), UDim2.fromScale(0.5, 0.52), 1.5)
end

ToyDecor.iconKinds = {"coin", "ring", "star", "twostars", "bot", "rainbow", "note", "sparkle"}

-- ToyDecor.icon("ring") returns fn(holder, px) for Theme.button's options.icon, or draws directly
-- when given a holder: ToyDecor.icon("ring", holder, px).
function ToyDecor.icon(kind, frame, px)
	local draw = ICONS[kind] or ICONS.star
	if frame then
		draw(frame, px)
		return frame
	end
	return function(target, size) draw(target, size) end
end

-- A fixed-size icon holder (transparent px x px frame) with the icon drawn in it.
function ToyDecor.iconFrame(parent, name, kind, px, position, anchor)
	local frame = create("Frame", {Name = name, Size = UDim2.fromOffset(px, px), Position = position or UDim2.new(),
		AnchorPoint = anchor or Vector2.new(0, 0), BackgroundTransparency = 1, Parent = parent})
	ToyDecor.icon(kind, frame, px)
	return frame
end

return ToyDecor
