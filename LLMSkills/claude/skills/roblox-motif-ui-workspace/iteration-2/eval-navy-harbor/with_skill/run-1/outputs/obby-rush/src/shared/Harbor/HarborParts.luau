--!nocheck
-- HarborParts: the "night harbour navy" pieces drawn from Frames (no image assets).
--   rope        twisted white rope (halyards, the flag dressing line, cargo-tag ties)
--   rivet       brass rivet head
--   brassPlate  engraved brass nameplate (face, hairline highlight, rivets)
--   porthole    brass porthole: ring, rivets, night-glass with a reflection
--   coin        brass coin
--   anchor      anchor emblem;  wheel  ship's wheel emblem
--   flag        international code signal flags C, N, S, X (navy / white / red only)
--   collar      the three white stripes of a sailor collar, inset along a panel's edge
--   neckerchief the red sailor scarf knot
--   lamp        brass deck lamp (lit / dark) used as the ON/OFF indicator
-- Every decoration is named "Harbor*", has Active = false (never eats clicks) and is not a button,
-- so the menu's name contract and touch-size checks are unaffected.
local Parts = {}
Parts.__index = Parts

function Parts.new(kit)
	return setmetatable({kit = kit, P = kit.P}, Parts)
end

local function make(className, parent, props)
	local object = Instance.new(className)
	for key, value in pairs(props or {}) do
		object[key] = value
	end
	object.Parent = parent
	return object
end
Parts.make = make

local function round(object, radius)
	return make("UICorner", object, {CornerRadius = radius or UDim.new(1, 0)})
end
Parts.round = round

local function border(object, color, thickness, transparency)
	return make("UIStroke", object, {
		Name = "HarborEdge", ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = color,
		Thickness = thickness or 2, Transparency = transparency or 0, LineJoinMode = Enum.LineJoinMode.Round,
	})
end
Parts.border = border

-- Plain decorative frame (never clickable).
function Parts:frame(parent, name, props)
	local object = make("Frame", parent, {Name = name, BorderSizePixel = 0, Active = false, BackgroundTransparency = 1})
	for key, value in pairs(props or {}) do
		object[key] = value
	end
	return object
end

function Parts:circle(parent, name, size, color, props)
	local object = self:frame(parent, name, {
		AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = color, BackgroundTransparency = 0,
	})
	for key, value in pairs(props or {}) do
		object[key] = value
	end
	round(object)
	return object
end

-- Rope: a shaded core with diagonal strands on top. `length` is the nominal pixel length used to
-- count strands (the strands are placed by scale, so a scale-sized rope still reads as twisted).
-- Horizontal by default; pass Rotation = 90 (with a centre AnchorPoint) for a vertical halyard.
function Parts:rope(parent, name, length, thickness, props)
	local P = self.P
	local t = thickness or 6
	local holder = self:frame(parent, name, {Size = UDim2.fromOffset(length, t)})
	for key, value in pairs(props or {}) do
		holder[key] = value
	end
	local core = self:frame(holder, "Core", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = P.ropeShade, BackgroundTransparency = 0})
	round(core)
	local count = math.max(2, math.floor(length / (t * 0.95)))
	local strandW, strandH = math.floor(t * 1.35 + 0.5), math.max(2, math.floor(t * 0.62 + 0.5))
	for index = 0, count - 1 do
		local strand = self:frame(holder, "Strand", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale((index + 0.5) / count, 0.5),
			Size = UDim2.fromOffset(strandW, strandH), Rotation = -38,
			BackgroundColor3 = P.rope, BackgroundTransparency = 0,
		})
		round(strand)
	end
	return holder
end

function Parts:rivet(parent, x, y, size)
	local rivet = self:circle(parent, "HarborRivet", size or 6, self.P.brassLight, {Position = UDim2.new(x.Scale or 0, x.Offset or 0, y.Scale or 0, y.Offset or 0)})
	border(rivet, self.P.brassDark, 1)
	return rivet
end

-- Four rivets just inside the corners of a frame.
function Parts:cornerRivets(frame, inset, size)
	local i = inset or 7
	for _, corner in ipairs({{0, i, 0, i}, {1, -i, 0, i}, {0, i, 1, -i}, {1, -i, 1, -i}}) do
		self:rivet(frame, UDim.new(corner[1], corner[2]), UDim.new(corner[3], corner[4]), size)
	end
end

-- Brass nameplate look on an existing frame or label (keeps its name, text and parent).
function Parts:brassPlate(object, radius)
	local P = self.P
	object.BackgroundColor3 = P.brass
	object.BackgroundTransparency = 0
	object.BorderSizePixel = 0
	local corner = object:FindFirstChildOfClass("UICorner") or round(object, UDim.new(0, radius or 3))
	corner.CornerRadius = UDim.new(0, radius or 3)
	local edge = object:FindFirstChild("HarborEdge") or border(object, P.brassDark, 2)
	edge.Color, edge.Thickness = P.brassDark, 2
	-- metal shine: one bright hairline under the top edge, one dark hairline above the bottom edge
	self:frame(object, "HarborShine", {Position = UDim2.new(0, 6, 0, 3), Size = UDim2.new(1, -12, 0, 1), BackgroundColor3 = P.brassLight, BackgroundTransparency = 0})
	self:frame(object, "HarborShade", {Position = UDim2.new(0, 6, 1, -4), Size = UDim2.new(1, -12, 0, 1), BackgroundColor3 = P.brassDark, BackgroundTransparency = 0.2})
	self:cornerRivets(object, 7, 5)
	return object
end

function Parts:coin(parent, name, size, props)
	local P = self.P
	local coin = self:circle(parent, name or "HarborCoin", size, P.brass, props)
	border(coin, P.brassDark, 1.5)
	local rim = self:circle(coin, "Rim", math.floor(size * 0.62), P.brass, {Position = UDim2.fromScale(0.5, 0.5)})
	border(rim, P.brassLight, 1.5)
	return coin
end

-- Brass porthole: returns the root and the glass (put the content inside the glass).
function Parts:porthole(parent, name, size, props)
	local P = self.P
	local root = self:circle(parent, name or "HarborPorthole", size, P.brass, props)
	border(root, P.brassDark, 1.5)
	local glass = self:circle(root, "Glass", size - 14, P.sea, {Position = UDim2.fromScale(0.5, 0.5)})
	border(glass, P.brassDark, 1.5)
	local shine = self:circle(glass, "Shine", math.floor((size - 14) * 0.55), P.white, {Position = UDim2.fromScale(0.36, 0.34), BackgroundTransparency = 0.88})
	shine.ZIndex = glass.ZIndex
	local ringRadius = (size / 2 - 3.5) / size
	for index = 0, 7 do
		local angle = math.rad(index * 45 + 22.5)
		local rivet = self:circle(root, "HarborRivet", 4, P.brassLight, {
			Position = UDim2.fromScale(0.5 + math.cos(angle) * ringRadius, 0.5 + math.sin(angle) * ringRadius),
		})
		border(rivet, P.brassDark, 1)
	end
	return root, glass
end

-- Anchor emblem inside a square holder of `size` px.
function Parts:anchor(parent, name, size, color, props)
	local holder = self:frame(parent, name or "HarborAnchor", {Size = UDim2.fromOffset(size, size)})
	for key, value in pairs(props or {}) do
		holder[key] = value
	end
	local weight = math.max(2, math.floor(size * 0.075 + 0.5))
	local ring = self:circle(holder, "Ring", math.floor(size * 0.2), color, {Position = UDim2.fromScale(0.5, 0.13), BackgroundTransparency = 1})
	border(ring, color, weight)
	self:frame(holder, "Stock", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.new(0.56, 0, 0, weight + 1), BackgroundColor3 = color, BackgroundTransparency = 0})
	self:frame(holder, "Shank", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.22),
		Size = UDim2.new(0, weight + 1, 0.68, 0), BackgroundColor3 = color, BackgroundTransparency = 0})
	-- arms: the lower half of a ring, clipped
	local clip = self:frame(holder, "Arms", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.new(0.9, 0, 0.45, 0), ClipsDescendants = true})
	local arc = self:frame(clip, "Arc", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(0, math.floor(size * 0.74), 0, math.floor(size * 0.74))})
	round(arc)
	border(arc, color, weight)
	for _, side in ipairs({-1, 1}) do
		self:frame(holder, "Fluke", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5 + side * 0.39, 0.56),
			Size = UDim2.fromOffset(math.floor(size * 0.15), math.floor(size * 0.15)), Rotation = 45,
			BackgroundColor3 = color, BackgroundTransparency = 0})
	end
	return holder
end

-- Ship's wheel emblem.
function Parts:wheel(parent, name, size, color, props)
	local holder = self:frame(parent, name or "HarborWheel", {Size = UDim2.fromOffset(size, size)})
	for key, value in pairs(props or {}) do
		holder[key] = value
	end
	local weight = math.max(2, math.floor(size * 0.05 + 0.5))
	for _, angle in ipairs({0, 45, 90, 135}) do
		self:frame(holder, "Spoke", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0.96, 0, 0, weight), Rotation = angle, BackgroundColor3 = color, BackgroundTransparency = 0})
	end
	local rim = self:circle(holder, "Rim", math.floor(size * 0.66), color, {Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1})
	border(rim, color, weight + 1)
	self:circle(holder, "Hub", math.floor(size * 0.18), color, {Position = UDim2.fromScale(0.5, 0.5)})
	for index = 0, 7 do
		local angle = math.rad(index * 45)
		self:circle(holder, "Handle", math.floor(size * 0.1), color, {Position = UDim2.fromScale(0.5 + math.cos(angle) * 0.47, 0.5 + math.sin(angle) * 0.47)})
	end
	return holder
end

-- International code signal flags, drawn only in navy-blue / white / red.
-- C (Charlie) blue-white-red-white-blue bands; N (November) blue/white chequers;
-- S (Sierra) white with a blue centre square; X (X-ray) white with a blue cross.
function Parts:flag(parent, name, letter, props)
	local P = self.P
	local blue, white, red = P.flagBlue, P.white, P.primary
	local flag = self:frame(parent, name or "HarborFlag", {BackgroundColor3 = white, BackgroundTransparency = 0, ClipsDescendants = true})
	for key, value in pairs(props or {}) do
		flag[key] = value
	end
	local function block(x, y, w, h, color)
		return self:frame(flag, "Field", {Position = UDim2.fromScale(x, y), Size = UDim2.fromScale(w, h), BackgroundColor3 = color, BackgroundTransparency = 0})
	end
	if letter == "C" then
		local bands = {blue, white, red, white, blue}
		for index, color in ipairs(bands) do
			block(0, (index - 1) / 5, 1, 1 / 5 + 0.002, color)
		end
	elseif letter == "N" then
		for row = 0, 3 do
			for column = 0, 3 do
				if (row + column) % 2 == 0 then block(column / 4, row / 4, 0.25, 0.25, blue) end
			end
		end
	elseif letter == "S" then
		block(0.32, 0.25, 0.36, 0.5, blue)
	elseif letter == "X" then
		block(0.41, 0, 0.18, 1, blue)
		block(0, 0.375, 1, 0.25, blue)
	end
	border(flag, P.outline, 1.5)
	return flag
end

-- Sailor-collar piping: three white stripes inset along the frame's edge.
function Parts:collar(frame, insets, color, thickness)
	for index, inset in ipairs(insets or {8, 14, 20}) do
		local stripe = self:frame(frame, "HarborCollar" .. index, {Position = UDim2.fromOffset(inset, inset), Size = UDim2.new(1, -2 * inset, 1, -2 * inset)})
		border(stripe, color or self.P.canvas, thickness or 2)
	end
end

-- Red sailor scarf knot with two short tails, centred on (x scale, y offset) of the parent.
function Parts:neckerchief(parent, props)
	local P = self.P
	local holder = self:frame(parent, "HarborNeckerchief", {AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(64, 44)})
	for key, value in pairs(props or {}) do
		holder[key] = value
	end
	local shade = P.primary:Lerp(P.outline, 0.25)
	for _, side in ipairs({-1, 1}) do
		local tail = self:frame(holder, "Tail", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, side * 11, 0, 12),
			Size = UDim2.fromOffset(13, 28), Rotation = side * 22, BackgroundColor3 = shade, BackgroundTransparency = 0})
		round(tail, UDim.new(0, 2))
	end
	local knot = self:frame(holder, "Knot", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(20, 20), Rotation = 45, BackgroundColor3 = P.primary, BackgroundTransparency = 0})
	round(knot, UDim.new(0, 3))
	border(knot, shade, 1.5)
	return holder
end

-- Deck lamp: brass cage with a glass that glows when lit. Returns the root and a setter.
function Parts:lamp(parent, name, size, props)
	local P = self.P
	local root = self:frame(parent, name or "HarborLamp", {AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(size + 16, size + 16)})
	for key, value in pairs(props or {}) do
		root[key] = value
	end
	-- glow first so it sits behind the brass cage
	local glow = self:circle(root, "Glow", size + 16, P.lamp, {Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 0.72})
	local cage = self:circle(root, "Cage", size, P.brass, {Position = UDim2.fromScale(0.5, 0.5)})
	border(cage, P.brassDark, 1.5)
	local glass = self:circle(cage, "Glass", size - 8, P.lamp, {Position = UDim2.fromScale(0.5, 0.5)})
	local function set(on)
		glass.BackgroundColor3 = on and P.lamp or P.disabled
		glow.Visible = on
	end
	return root, set
end

return Parts
