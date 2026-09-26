-- Naval motif kit: International Code signal flags, brass portholes and coins, laid rope, rope coils,
-- sailor-collar piping and the neckerchief knot. Everything is Frames + UICorner/UIStroke/UIGradient
-- (no image assets), so it stays crisp at any resolution and needs no uploads.
local Theme = require(script.Parent:WaitForChild("UITheme"))

local P = Theme.palette
local create = Theme.create

local Motif = {}

-- Signal flags ------------------------------------------------------------------------------------------
-- Only the flags whose real colours are blue / white / red are used, so the palette never gains the
-- yellow or black of the full code. Bands are {x, y, w, h, colour} in flag-relative scale.
local BLUE, WHITE, RED = P.flagBlue, P.white, P.red
local FLAGS = {
	C = {base = BLUE, bands = {{0, 0.2, 1, 0.2, WHITE}, {0, 0.4, 1, 0.2, RED}, {0, 0.6, 1, 0.2, WHITE}}}, -- Charlie: "yes"
	E = {base = BLUE, bands = {{0, 0.5, 1, 0.5, RED}}},
	H = {base = WHITE, bands = {{0.5, 0, 0.5, 1, RED}}},
	J = {base = BLUE, bands = {{0, 1 / 3, 1, 1 / 3, WHITE}}},
	M = {base = BLUE, saltire = WHITE},
	N = {base = WHITE, checker = BLUE}, -- November: "no"
	P = {base = BLUE, bands = {{1 / 3, 1 / 3, 1 / 3, 1 / 3, WHITE}}}, -- Papa, the Blue Peter: "about to sail"
	S = {base = WHITE, bands = {{1 / 3, 1 / 3, 1 / 3, 1 / 3, BLUE}}},
	T = {base = WHITE, bands = {{0, 0, 1 / 3, 1, RED}, {2 / 3, 0, 1 / 3, 1, BLUE}}},
	U = {base = WHITE, bands = {{0, 0, 0.5, 0.5, RED}, {0.5, 0.5, 0.5, 0.5, RED}}},
	V = {base = WHITE, saltire = RED},
	W = {base = BLUE, bands = {{1 / 6, 1 / 6, 2 / 3, 2 / 3, WHITE}, {1 / 3, 1 / 3, 1 / 3, 1 / 3, RED}}},
	X = {base = WHITE, cross = BLUE},
}
Motif.FLAG_LETTERS = {"C", "E", "H", "J", "M", "N", "P", "S", "T", "U", "V", "W", "X"}

function Motif.flag(parent, name, letter, width, height)
	local spec = FLAGS[letter]
	assert(spec, "no navy/white/red signal flag for " .. tostring(letter))
	local flag = create("Frame", {Name = name, Size = UDim2.fromOffset(width, height), BackgroundColor3 = spec.base,
		BorderSizePixel = 0, ClipsDescendants = true, Parent = parent})
	flag:SetAttribute("SignalFlag", letter)
	for index, band in ipairs(spec.bands or {}) do
		create("Frame", {Name = "Band" .. index, Position = UDim2.fromScale(band[1], band[2]), Size = UDim2.fromScale(band[3], band[4]),
			BackgroundColor3 = band[5], BorderSizePixel = 0, Parent = flag})
	end
	if spec.saltire then
		local angle = math.deg(math.atan2(height, width))
		local length = math.sqrt(width * width + height * height) + 2
		for index, rotation in ipairs({angle, -angle}) do
			create("Frame", {Name = "Saltire" .. index, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(length, math.max(2, height * 0.2)), Rotation = rotation,
				BackgroundColor3 = spec.saltire, BorderSizePixel = 0, Parent = flag})
		end
	end
	if spec.cross then
		local bar = math.max(2, height * 0.2)
		create("Frame", {Name = "CrossBar", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 0, 0, bar), BackgroundColor3 = spec.cross, BorderSizePixel = 0, Parent = flag})
		create("Frame", {Name = "CrossPost", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, bar, 1, 0), BackgroundColor3 = spec.cross, BorderSizePixel = 0, Parent = flag})
	end
	if spec.checker then
		for row = 0, 3 do
			for column = 0, 3 do
				if (row + column) % 2 == 0 then
					create("Frame", {Name = "Check", Position = UDim2.fromScale(column / 4, row / 4), Size = UDim2.fromScale(0.25, 0.25),
						BackgroundColor3 = spec.checker, BorderSizePixel = 0, Parent = flag})
				end
			end
		end
	end
	return flag
end

-- Centre a new flag inside `holder` (a porthole, usually).
function Motif.flagIn(holder, letter, width, height)
	local flag = Motif.flag(holder, "Flag", letter, width, height)
	flag.AnchorPoint = Vector2.new(0.5, 0.5)
	flag.Position = UDim2.fromScale(0.5, 0.5)
	return flag
end

-- Brass hardware -----------------------------------------------------------------------------------------
-- A porthole: night glass inside a brass rim (UIStroke with a brass gradient), bolts on the rim and a
-- glare streak. Parent content (a flag, a glyph) to the returned frame; the glare stays on top.
function Motif.porthole(parent, name, diameter, options)
	options = options or {}
	local ring = options.ring or math.max(3, math.floor(diameter * 0.11 + 0.5))
	local glass = create("Frame", {Name = name, Size = UDim2.fromOffset(diameter, diameter), BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0, Parent = parent})
	Theme.corner(glass, UDim.new(0.5, 0))
	Theme.gradient(glass, {{0, P.navyLine}, {0.55, P.deep}, {1, P.night}}, 90)
	local rim = create("UIStroke", {Name = "BrassRim", Color = Color3.new(1, 1, 1), Thickness = ring,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = glass})
	Theme.gradient(rim, {{0, P.brassLight}, {0.45, P.brass}, {1, P.brassDark}}, 45)
	if diameter >= 44 then
		local count = diameter >= 80 and 8 or 6
		local radius = diameter / 2 + ring / 2
		local bolt = math.max(2, math.floor(ring * 0.45 + 0.5))
		for index = 1, count do
			local angle = (index - 1) / count * math.pi * 2 + math.pi / count
			local head = create("Frame", {Name = "Bolt", AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, math.cos(angle) * radius, 0.5, math.sin(angle) * radius), Size = UDim2.fromOffset(bolt, bolt),
				BackgroundColor3 = P.brassDark, BorderSizePixel = 0, Parent = glass})
			Theme.corner(head, UDim.new(0.5, 0))
		end
	end
	local glare = create("Frame", {Name = "Glare", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.34, 0.28),
		Size = UDim2.fromScale(0.44, 0.13), Rotation = -38, BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.8,
		BorderSizePixel = 0, ZIndex = 3, Parent = glass})
	Theme.corner(glare, UDim.new(0.5, 0))
	return glass
end

-- A brass coin (the currency mark): polished disc, dark rim, struck inner ring.
function Motif.coin(parent, name, diameter)
	local coin = create("Frame", {Name = name, Size = UDim2.fromOffset(diameter, diameter), BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0, Parent = parent})
	Theme.corner(coin, UDim.new(0.5, 0))
	Theme.gradient(coin, {{0, P.brassLight}, {0.5, P.brass}, {1, P.brassDark}}, 45)
	create("UIStroke", {Color = P.brassDark, Thickness = math.max(1, diameter * 0.06), ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = coin})
	local rim = create("Frame", {Name = "Rim", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.6, 0.6), BackgroundTransparency = 1, BorderSizePixel = 0, Parent = coin})
	Theme.corner(rim, UDim.new(0.5, 0))
	create("UIStroke", {Color = P.brassDark, Thickness = math.max(1, diameter * 0.07), Transparency = 0.2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = rim})
	return coin
end

-- Rope ---------------------------------------------------------------------------------------------------
-- Three-strand laid rope: slanted strands with a dark groove between them, clipped to the rope's
-- bounds, plus a highlight and a shadow for the round section. length/thickness are pixels.
-- options: vertical, whipped (white thread bindings at both ends)
function Motif.rope(parent, name, length, thickness, options)
	options = options or {}
	local vertical = options.vertical == true
	local rope = create("Frame", {Name = name, BackgroundColor3 = P.ropeShade, BorderSizePixel = 0, ClipsDescendants = true,
		Size = vertical and UDim2.fromOffset(thickness, length) or UDim2.fromOffset(length, thickness), Parent = parent})
	-- one strand crest per rope diameter; the strand is a pixel narrower than its slanted pitch, which
	-- leaves the dark groove between strands
	local pitch = math.max(4, math.floor(thickness + 0.5))
	local strand = math.max(2, pitch * math.cos(math.rad(35)) - 1)
	local span = thickness * 2.4
	for index = 0, math.ceil(length / pitch) + 1 do
		local along = (index - 1) * pitch + pitch / 2
		create("Frame", {Name = "Strand", AnchorPoint = Vector2.new(0.5, 0.5), Rotation = 35,
			Size = vertical and UDim2.fromOffset(span, strand) or UDim2.fromOffset(strand, span),
			Position = vertical and UDim2.new(0.5, 0, 0, along) or UDim2.new(0, along, 0.5, 0),
			BackgroundColor3 = index % 3 == 0 and P.rope:Lerp(P.ropeShade, 0.22) or P.rope, BorderSizePixel = 0, Parent = rope})
	end
	create("Frame", {Name = "Highlight", ZIndex = 2, BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.72,
		BorderSizePixel = 0, Size = vertical and UDim2.fromScale(0.3, 1) or UDim2.fromScale(1, 0.3), Parent = rope})
	create("Frame", {Name = "Shadow", ZIndex = 2, BackgroundColor3 = P.ink, BackgroundTransparency = 0.6, BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1),
		Size = vertical and UDim2.fromScale(0.3, 1) or UDim2.fromScale(1, 0.3), Parent = rope})
	if options.whipped then
		for index, edge in ipairs({0, 1}) do
			create("Frame", {Name = "Whipping" .. index, ZIndex = 3, BackgroundColor3 = P.white, BorderSizePixel = 0,
				AnchorPoint = vertical and Vector2.new(0, edge) or Vector2.new(edge, 0),
				Position = vertical and UDim2.fromScale(0, edge) or UDim2.fromScale(edge, 0),
				Size = vertical and UDim2.new(1, 0, 0, 4) or UDim2.new(0, 4, 1, 0), Parent = rope})
		end
	end
	return rope
end

-- Rope grommet around the inside of a pixel-sized frame (the PLAY button).
function Motif.ropeFrame(frame, width, height, inset, thickness)
	local left = Motif.rope(frame, "RopeLeft", height - inset * 2, thickness, {vertical = true})
	left.Position = UDim2.fromOffset(inset, inset)
	local right = Motif.rope(frame, "RopeRight", height - inset * 2, thickness, {vertical = true})
	right.Position = UDim2.fromOffset(width - inset - thickness, inset)
	local top = Motif.rope(frame, "RopeTop", width - inset * 2, thickness)
	top.Position = UDim2.fromOffset(inset, inset)
	local bottom = Motif.rope(frame, "RopeBottom", width - inset * 2, thickness)
	bottom.Position = UDim2.fromOffset(inset, height - inset - thickness)
end

-- A Flemish coil (rope flaked down in tight turns) with its tail running off to the right.
function Motif.ropeCoil(parent, name, diameter)
	local coil = create("Frame", {Name = name, Size = UDim2.fromOffset(diameter, diameter), BackgroundTransparency = 1,
		BorderSizePixel = 0, Parent = parent})
	local thickness = math.max(5, math.floor(diameter * 0.07 + 0.5))
	local turns = math.floor(diameter / 2 / thickness) - 1
	for index = 1, turns do
		local outer = diameter / 2 - (index - 1) * thickness
		local size = (outer - thickness) * 2
		local turn = create("Frame", {Name = "Turn" .. index, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, BorderSizePixel = 0, Parent = coil})
		Theme.corner(turn, UDim.new(0.5, 0))
		local stroke = create("UIStroke", {Color = Color3.new(1, 1, 1), Thickness = thickness - 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = turn})
		local lit = index % 2 == 0 and P.rope or P.white
		Theme.gradient(stroke, {{0, lit}, {0.55, P.rope}, {1, P.ropeShade}}, 45)
	end
	local heart = create("Frame", {Name = "Heart", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(thickness * 2, thickness * 2), BackgroundColor3 = P.ropeShade, BorderSizePixel = 0, Parent = coil})
	Theme.corner(heart, UDim.new(0.5, 0))
	local tail = Motif.rope(coil, "Tail", math.floor(diameter * 0.6), thickness, {whipped = true})
	tail.Position = UDim2.new(0.5, 0, 1, -thickness)
	return coil
end

-- Uniform details ----------------------------------------------------------------------------------------
-- The three white stripes of a sailor collar, along the left, bottom and right edges of `frame`.
function Motif.collar(frame)
	local weight = 2
	for index = 1, 3 do
		local offset = 5 + (index - 1) * 5
		create("Frame", {Name = "CollarStripeBottom" .. index, BackgroundColor3 = P.white, BorderSizePixel = 0,
			Position = UDim2.new(0, offset, 1, -offset - weight), Size = UDim2.new(1, -offset * 2, 0, weight), Parent = frame})
		create("Frame", {Name = "CollarStripeLeft" .. index, BackgroundColor3 = P.white, BorderSizePixel = 0,
			Position = UDim2.fromOffset(offset, 0), Size = UDim2.new(0, weight, 1, -offset), Parent = frame})
		create("Frame", {Name = "CollarStripeRight" .. index, BackgroundColor3 = P.white, BorderSizePixel = 0,
			Position = UDim2.new(1, -offset - weight, 0, 0), Size = UDim2.new(0, weight, 1, -offset), Parent = frame})
	end
end

-- The red neckerchief knot with its two tails (hangs from the collar).
function Motif.neckerchief(parent, name)
	local tie = create("Frame", {Name = name, Size = UDim2.fromOffset(60, 58), BackgroundTransparency = 1, BorderSizePixel = 0,
		Parent = parent})
	for index, side in ipairs({-1, 1}) do
		local tail = create("Frame", {Name = "Tail" .. index, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, side * 9, 0, 12),
			Size = UDim2.fromOffset(16, 42), Rotation = -side * 15, BackgroundColor3 = P.redDeep, BorderSizePixel = 0, Parent = tie})
		Theme.corner(tail, 2)
		-- a white edge stripe on each tail, like the tape on a sailor scarf
		create("Frame", {Name = "Tape", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -5), Size = UDim2.new(1, 0, 0, 2),
			BackgroundColor3 = P.white, BackgroundTransparency = 0.25, BorderSizePixel = 0, Parent = tail})
	end
	local knot = create("Frame", {Name = "Knot", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(24, 24), Rotation = 45, BackgroundColor3 = P.red, BorderSizePixel = 0, Parent = tie})
	Theme.corner(knot, 3)
	create("UIStroke", {Color = P.redDeep, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = knot})
	return tie
end

return Motif
