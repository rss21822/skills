-- UI theme shared by every screen.
-- Motif: 水墨画と書 (sumi-e and calligraphy). A screen is one sheet of washi; everything on it is
-- brushed in sumi ink; vermilion appears only as a seal (落款 / 印).
--
-- Palette rule: exactly three pigments (Theme.pigments). Every other tone is ink diluted on paper,
-- expressed as the *transparency* of SUMI over WASHI (墨の濃淡, Theme.ink) — never a new Color3.
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local Theme = {}

local WASHI = Color3.fromRGB(240, 234, 219) -- 和紙: unbleached kozo paper
local SUMI = Color3.fromRGB(27, 26, 24) -- 墨: warm lamp-black ink
local SHU = Color3.fromRGB(192, 55, 38) -- 朱: seal paste (印泥). Seals only.

Theme.pigments = {washi = WASHI, sumi = SUMI, shu = SHU}

-- 墨の濃淡: ink density as transparency of SUMI over WASHI.
-- Small text never goes lighter than `mid` (about 4.8:1 on washi).
Theme.ink = {
	jet = 0, -- 焦墨: titles, focused labels
	dark = 0.12, -- 濃墨: body text, resting buttons
	mid = 0.35, -- 中墨: secondary text (lightest density allowed for small text)
	pale = 0.62, -- 淡墨: hairlines, rules, frames
	mist = 0.88, -- 清墨: washes, distant mountains, paper grain
}

-- Colour3 names kept for older screens; all of them resolve to the three pigments.
-- `subtext` is 中墨 flattened onto washi for code that can only take a Color3 (same ink, diluted).
Theme.colors = {
	washi = WASHI,
	sumi = SUMI,
	shu = SHU,
	background = WASHI,
	panel = WASHI,
	panelLight = WASHI,
	accent = SUMI,
	text = SUMI,
	subtext = WASHI:Lerp(SUMI, 1 - Theme.ink.mid),
	danger = SHU,
	success = SUMI,
}

-- A quiet book serif for Latin and digits; Japanese falls back to Roblox's CJK face.
-- Emphasis comes from size and ink density, not weight.
Theme.font = Enum.Font.Garamond
Theme.fontBold = Enum.Font.Garamond

local function create(className, props)
	local object = Instance.new(className)
	for key, value in pairs(props) do
		if key ~= "Parent" then object[key] = value end
	end
	object.Parent = props.Parent
	return object
end
Theme.create = create

local function sequence(points)
	local keypoints = {}
	for _, point in ipairs(points) do
		table.insert(keypoints, NumberSequenceKeypoint.new(point[1], point[2]))
	end
	return NumberSequence.new(keypoints)
end
Theme.sequence = sequence

local function reducedMotion()
	local ok, value = pcall(function() return GuiService.ReducedMotionEnabled end)
	return ok and value == true
end

-- Tween, or snap when the player asked for reduced motion.
function Theme.tween(object, props, duration, delay)
	if reducedMotion() or not duration or duration <= 0 then
		for key, value in pairs(props) do object[key] = value end
		return nil
	end
	local tween = TweenService:Create(object,
		TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, false, delay or 0), props)
	tween:Play()
	return tween
end

-- "七転び" -> "七\n転\nび": one glyph per line for 縦書き columns (UTF-8 safe, no utf8 library needed).
function Theme.vertical(text)
	local glyphs = {}
	for glyph in string.gmatch(text, "[\1-\127\194-\244][\128-\191]*") do
		table.insert(glyphs, glyph)
	end
	return table.concat(glyphs, "\n")
end

function Theme.corner(object, radius)
	return create("UICorner", {CornerRadius = UDim.new(0, radius or 2), Parent = object})
end

function Theme.round(object)
	return create("UICorner", {CornerRadius = UDim.new(0.5, 0), Parent = object})
end

-- An ink hairline around a sheet. options: transparency, thickness, color
function Theme.stroke(object, options)
	options = options or {}
	return create("UIStroke", {Color = options.color or SUMI, Thickness = options.thickness or 1,
		Transparency = options.transparency or Theme.ink.pale, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = object})
end

-- A sheet of washi with an ink hairline. options.bare: no paper, no line (text sits on the page).
function Theme.panel(parent, name, size, position, options)
	options = options or {}
	local frame = create("Frame", {Name = name, Size = size, Position = position or UDim2.new(),
		BackgroundColor3 = WASHI, BackgroundTransparency = options.bare and 1 or 0, BorderSizePixel = 0, Parent = parent})
	if not options.bare then
		Theme.corner(frame, 2)
		Theme.stroke(frame)
	end
	return frame
end

-- options: bold, color, ink (Theme.ink density), align, frameSize
function Theme.label(parent, name, text, size, options)
	options = options or {}
	return create("TextLabel", {Name = name, Text = text, TextSize = size or 16, Font = options.bold and Theme.fontBold or Theme.font,
		TextColor3 = options.color or SUMI, TextTransparency = options.ink or 0, BackgroundTransparency = 1,
		Size = options.frameSize or UDim2.new(1, 0, 0, (size or 16) + 8),
		TextXAlignment = options.align or Enum.TextXAlignment.Left, TextWrapped = true, Parent = parent})
end

-- 一筆: a single horizontal brush stroke that presses in (起筆), travels (送筆) and lifts off dry (収筆).
-- options: anchor, transparency (overall density)
function Theme.brush(parent, name, size, position, options)
	options = options or {}
	local stroke = create("Frame", {Name = name, Size = size, Position = position or UDim2.new(),
		AnchorPoint = options.anchor or Vector2.new(0, 0), BackgroundColor3 = SUMI,
		BackgroundTransparency = options.transparency or 0, BorderSizePixel = 0, Parent = parent})
	Theme.corner(stroke, 2)
	create("UIGradient", {Transparency = sequence({{0, 0.5}, {0.07, 0}, {0.55, 0.08}, {0.86, 0.42}, {1, 1}}), Parent = stroke})
	return stroke
end

-- 罫線: a pale ink rule along the bottom of a row.
function Theme.rule(parent, name)
	local line = create("Frame", {Name = name or "Rule", Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1),
		BackgroundColor3 = SUMI, BackgroundTransparency = Theme.ink.pale, BorderSizePixel = 0, Parent = parent})
	create("UIGradient", {Transparency = sequence({{0, 0}, {0.8, 0.2}, {1, 1}}), Parent = line})
	return line
end

-- 落款 / 印: the only use of vermilion. Paper-coloured characters reversed out of the seal (白文印),
-- a paper-coloured frame line inside, and uneven seal paste.
local function dressSeal(object, rotation, rimThickness)
	object.BackgroundColor3 = SHU
	object.BackgroundTransparency = 0
	object.BorderSizePixel = 0
	object.Rotation = rotation
	Theme.corner(object, 3)
	create("UIGradient", {Rotation = 35,
		Transparency = sequence({{0, 0.02}, {0.28, 0.1}, {0.5, 0}, {0.78, 0.14}, {1, 0.04}}), Parent = object})
	local rim = create("Frame", {Name = "Rim", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.84, 0.84), BackgroundTransparency = 1, Parent = object})
	create("UIStroke", {Color = WASHI, Thickness = rimThickness or 1, Transparency = 0.15, Parent = rim})
	return rim
end

-- A decorative seal. options: anchor, rotation, textSize
function Theme.seal(parent, name, text, size, position, options)
	options = options or {}
	local seal = create("Frame", {Name = name, Size = size, Position = position or UDim2.new(),
		AnchorPoint = options.anchor or Vector2.new(0, 0), Parent = parent})
	dressSeal(seal, options.rotation or 0, options.rim)
	create("TextLabel", {Name = "Glyph", Text = text, Font = Theme.font, TextScaled = true, TextColor3 = WASHI,
		BackgroundTransparency = 1, Size = UDim2.fromScale(0.7, 0.7), Position = UDim2.fromScale(0.15, 0.15), Parent = seal})
	return seal
end

-- 文銭: an ink coin with a square hole, used as the unit mark after amounts.
function Theme.coin(parent, name, size, position, options)
	options = options or {}
	local coin = create("Frame", {Name = name, Size = UDim2.fromOffset(size, size), Position = position or UDim2.new(),
		AnchorPoint = options.anchor or Vector2.new(0, 0.5), BackgroundColor3 = SUMI,
		BackgroundTransparency = options.ink or Theme.ink.dark, BorderSizePixel = 0, Parent = parent})
	Theme.round(coin)
	local ring = create("Frame", {Name = "Ring", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.7, 0.7), BackgroundTransparency = 1, Parent = coin})
	Theme.round(ring)
	create("UIStroke", {Color = WASHI, Thickness = 1, Transparency = 0.35, Parent = ring})
	create("Frame", {Name = "Hole", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.28, 0.28), BackgroundColor3 = WASHI, BorderSizePixel = 0, Parent = coin})
	return coin
end

-- 円相: one breath of the brush, drawn as a chain of overlapping ink capsules along a slightly
-- wandering arc. The brush lands heavy (起筆), travels, thins, and splits into dry hairs (飛白) before
-- it lifts, leaving the circle open. Everything is in scale units of a square root frame, so the
-- ensō keeps its shape at any size. Deterministic (seeded), so every player sees the same stroke.
-- options: weight (thickness as a fraction of the diameter), transparency (overall density),
--          start / sweep (degrees, clockwise from 3 o'clock), segments, hairs, seed, anchor
function Theme.enso(parent, name, size, position, options)
	options = options or {}
	local weight = options.weight or 0.034
	local density = options.transparency or 0
	local start = math.rad(options.start or 112)
	local sweep = math.rad(options.sweep or 324)
	local segments = options.segments or 84
	local hairs = options.hairs or 4
	local seed = options.seed or 7
	-- A translucent ensō is painted into a CanvasGroup so overlapping dabs do not stack into beads.
	local root = create(density > 0 and "CanvasGroup" or "Frame", {Name = name, Size = size, Position = position or UDim2.new(),
		AnchorPoint = options.anchor or Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Parent = parent})
	if density > 0 then root.GroupTransparency = density end
	create("UIAspectRatioConstraint", {AspectRatio = 1, Parent = root})

	local function noise(i)
		local v = math.sin(i * 12.9898 + seed * 78.233) * 43758.5453
		return v - math.floor(v)
	end
	local stepAngle = sweep / segments
	local function dab(t, radial, thickness, transparency)
		local angle = start + sweep * t
		local radius = 0.44 * (1 + 0.03 * t + 0.01 * math.sin(3 * angle + seed) + 0.006 * math.sin(7 * angle)) + radial
		local length = radius * stepAngle * 1.6
		local piece = create("Frame", {Name = "Ink", AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5 + radius * math.cos(angle), 0.5 + radius * math.sin(angle)),
			Size = UDim2.fromScale(length + thickness, thickness), Rotation = math.deg(angle) + 90,
			BackgroundColor3 = SUMI, BackgroundTransparency = transparency, BorderSizePixel = 0, Parent = root})
		Theme.round(piece)
	end

	-- The body: pressure swells and eases like a hand (heavy landing, lighter over the top, a second
	-- press on the way down), each dab a little uneven so the edge is not machined.
	for i = 0, segments do
		local t = i / segments
		local pressure = 1 + 0.18 * math.sin(t * math.pi * 2.2 + 0.6) + 0.5 * math.max(0, 1 - t / 0.06)
		local lift = t < 0.62 and 1 or math.max(0.12, 1 - (t - 0.62) / 0.38 * 0.95)
		local rough = 0.9 + 0.2 * noise(i)
		local fading = math.max(0, (t - 0.7) / 0.3)
		dab(t, (noise(i + 99) - 0.5) * weight * 0.12, weight * pressure * lift * rough, fading * 0.5)
	end
	-- 飛白: the brush runs dry and its hairs separate into broken streaks (runs of dabs, not dots).
	local offsets = {-0.44, 0.42, -0.16, 0.2, 0.02}
	local steps = math.floor(segments * 0.5)
	for h = 1, math.min(hairs, #offsets) do
		for j = 0, steps do
			local t = 0.55 + 0.45 * j / steps
			local dry = (t - 0.55) / 0.45
			local run = math.floor(j / 5) -- streaks of about five dabs
			if noise(run * 13 + h * 31) > 0.3 + dry * 0.35 then
				dab(t, offsets[h] * weight * (1 - dry * 0.3), weight * (0.13 + 0.05 * noise(j + h)), 0.1 + dry * 0.5)
			end
		end
	end
	return root
end

-- 淡墨の刷毛: a soft wash of dilute ink whose density runs top→bottom on screen even when the frame is
-- rotated. props: size, position, rotation, fade ({{t, transparency}...}), square, corner (UDim)
function Theme.wash(parent, name, props)
	local rotation = props.rotation or 0
	local frame = create("Frame", {Name = name, Size = props.size, Position = props.position or UDim2.new(),
		AnchorPoint = props.anchor or Vector2.new(0.5, 0.5), Rotation = rotation, BackgroundColor3 = SUMI,
		BackgroundTransparency = 0, BorderSizePixel = 0, Parent = parent})
	if props.square then create("UIAspectRatioConstraint", {AspectRatio = 1, Parent = frame}) end
	if props.corner then create("UICorner", {CornerRadius = props.corner, Parent = frame}) end
	create("UIGradient", {Rotation = (props.direction or 90) - rotation, Transparency = sequence(props.fade), Parent = frame})
	return frame
end

local function isPress(input)
	local kind = input and input.UserInputType
	return kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch
end

-- Three button voices:
--   seal    (options.seal / options.danger): a vermilion stamp. One per screen — the main action.
--   outline (options.primary): ink-ruled box; fills with ink on hover.
--   quiet   (default): ink text on the paper; a brush stroke is drawn under it on hover / when Selected.
-- options: size (UDim2), order, textSize, align, rotation (seal), mark (false = no brush stroke)
-- Quiet buttons show the stroke while the attribute "Selected" is true (e.g. the open page's nav item).
function Theme.button(parent, name, text, onClick, options)
	options = options or {}
	local style = (options.seal or options.danger) and "seal" or options.primary and "outline" or "quiet"
	local button = create("TextButton", {Name = name, Text = text, TextSize = options.textSize or 20, Font = Theme.font,
		TextColor3 = SUMI, TextTransparency = Theme.ink.dark, BackgroundColor3 = SUMI, BackgroundTransparency = 1,
		AutoButtonColor = false, BorderSizePixel = 0, TextXAlignment = options.align or Enum.TextXAlignment.Center,
		Size = options.size or UDim2.new(1, 0, 0, 48), LayoutOrder = options.order or 0, Parent = parent})
	local hovered, pressed = false, false
	local refresh

	if style == "seal" then
		local rotation = options.rotation or -2
		dressSeal(button, rotation, 2)
		button.TextColor3 = WASHI
		button.TextTransparency = 0
		button.TextScaled = true
		button.LineHeight = 0.95
		create("UITextSizeConstraint", {MaxTextSize = options.textSize or 56, Parent = button})
		create("UIPadding", {PaddingTop = UDim.new(0.16, 0), PaddingBottom = UDim.new(0.16, 0),
			PaddingLeft = UDim.new(0.16, 0), PaddingRight = UDim.new(0.16, 0), Parent = button})
		local press = create("UIScale", {Name = "Press", Scale = 1, Parent = button})
		refresh = function()
			Theme.tween(press, {Scale = pressed and 0.94 or hovered and 1.03 or 1}, 0.12)
			Theme.tween(button, {Rotation = hovered and 0 or rotation}, 0.2)
		end
	elseif style == "outline" then
		Theme.corner(button, 2)
		local stroke = Theme.stroke(button, {transparency = Theme.ink.dark})
		refresh = function()
			local on = hovered or pressed
			Theme.tween(button, {BackgroundTransparency = on and 0 or 1, TextColor3 = on and WASHI or SUMI,
				TextTransparency = on and 0 or Theme.ink.dark}, 0.15)
			stroke.Transparency = on and 0 or Theme.ink.dark
		end
	else
		local mark = nil
		if options.mark ~= false then
			mark = Theme.brush(button, "InkMark", UDim2.new(0.12, 0, 0, 3), UDim2.new(0.2, 0, 1, -9),
				{anchor = Vector2.new(0, 0.5), transparency = 1})
		end
		refresh = function()
			local on = hovered or pressed or button:GetAttribute("Selected") == true
			Theme.tween(button, {TextTransparency = on and Theme.ink.jet or Theme.ink.dark}, 0.15)
			if mark then
				Theme.tween(mark, {BackgroundTransparency = on and 0 or 1, Size = UDim2.new(on and 0.6 or 0.12, 0, 0, 3)}, 0.28)
			end
		end
		button:GetAttributeChangedSignal("Selected"):Connect(refresh)
	end

	local function setHover(value) hovered = value; if not value then pressed = false end; refresh() end
	button.MouseEnter:Connect(function() setHover(true) end)
	button.MouseLeave:Connect(function() setHover(false) end)
	button.SelectionGained:Connect(function() setHover(true) end)
	button.SelectionLost:Connect(function() setHover(false) end)
	button.InputBegan:Connect(function(input)
		if isPress(input) then pressed = true; refresh() end
	end)
	button.InputEnded:Connect(function(input)
		if isPress(input) then pressed = false; refresh() end
	end)
	button.Activated:Connect(function() onClick(button) end)
	return button
end

return Theme
