-- UI theme shared by every screen.
-- Motif: "The Grand Hotel" lobby. Black Nero Marquina marble (near-black stone with fine white veins),
-- antique-gold hairlines and art-deco ornaments, warm light from a crystal chandelier.
-- House rules: square 2 px corners (no pills except switches), 1 px gold rules, one serif display face,
-- letter-spaced English small caps over Japanese labels (bilingual hotel signage), and a single
-- solid-gold call to action per screen. No emoji, no saturated colour, no bounce.
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local Theme = {}

Theme.colors = {
	background = Color3.fromRGB(8, 8, 9), -- onyx
	panel = Color3.fromRGB(15, 15, 17), -- polished black marble
	panelLight = Color3.fromRGB(28, 27, 29), -- marble catching light (hover / selected)
	accent = Color3.fromRGB(201, 165, 94), -- antique gold: hairlines, captions, prices
	goldBright = Color3.fromRGB(240, 219, 160), -- polished edge of gold leaf
	goldDeep = Color3.fromRGB(150, 113, 52), -- gold in shadow
	vein = Color3.fromRGB(222, 216, 204), -- white veining in the marble
	crystal = Color3.fromRGB(250, 244, 228), -- chandelier crystal
	glow = Color3.fromRGB(246, 214, 152), -- warm candle light
	text = Color3.fromRGB(238, 231, 216), -- ivory
	subtext = Color3.fromRGB(158, 150, 137), -- taupe
	ink = Color3.fromRGB(20, 16, 10), -- text printed on gold
	danger = Color3.fromRGB(150, 52, 48), -- oxblood
	success = Color3.fromRGB(64, 122, 96), -- emerald
}

-- One serif family carries everything Latin; Japanese falls back to Roblox's CJK sans at regular weight,
-- which pairs the way bilingual hotel signage does (serif Latin + clean gothic Japanese).
Theme.font = Enum.Font.Bodoni
Theme.fontBold = Enum.Font.Bodoni -- the serif has one weight: hierarchy comes from size, caps and gold
Theme.fontDisplay = Enum.Font.Bodoni
Theme.fontCaps = Enum.Font.JosefinSans -- geometric art-deco sans for spaced small caps

Theme.radius = 2
local FADE_ENDS = {{0, 1}, {0.2, 0}, {0.8, 0}, {1, 1}}
Theme.FADE_ENDS = FADE_ENDS

local function create(className, props)
	local object = Instance.new(className)
	for key, value in pairs(props) do
		if key ~= "Parent" then object[key] = value end
	end
	object.Parent = props.Parent
	return object
end
Theme.create = create

local function colorSequence(points)
	local keys = {}
	for _, point in ipairs(points) do table.insert(keys, ColorSequenceKeypoint.new(point[1], point[2])) end
	return ColorSequence.new(keys)
end
local function numberSequence(points)
	local keys = {}
	for _, point in ipairs(points) do table.insert(keys, NumberSequenceKeypoint.new(point[1], point[2])) end
	return NumberSequence.new(keys)
end

-- Short property transitions (hover, switches). Instant when the player asked for reduced motion.
local QUICK = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
function Theme.tween(object, props, instant)
	local reduced = false
	pcall(function() reduced = GuiService.ReducedMotionEnabled == true end)
	if instant or reduced or not TweenService then
		for key, value in pairs(props) do object[key] = value end
		return
	end
	TweenService:Create(object, QUICK, props):Play()
end

-- Text helpers ----------------------------------------------------------------------------------------
-- Letter-spaced capitals ("tracking"): Roblox text has no letter-spacing, so spaces stand in.
-- ASCII captions only (never Japanese, never numbers other scripts parse).
function Theme.track(text)
	local words = {}
	for word in string.gmatch(string.upper(text), "%S+") do
		table.insert(words, (string.gsub(word, "(.)", "%1 ")):sub(1, -2))
	end
	return table.concat(words, "   ")
end

-- Rough advance width used to place ornaments next to text (TextService is not available everywhere
-- this module runs): CJK characters are full-width, everything else ~0.58 em.
function Theme.textWidth(text, size)
	local width = 0
	for char in string.gmatch(text, "[\1-\127\194-\244][\128-\191]*") do
		width += (#char >= 3) and size or size * 0.58
	end
	return width
end

-- 1250 -> "1,250"
function Theme.formatNumber(value)
	local formatted = tostring(math.floor(tonumber(value) or 0))
	local count
	repeat
		formatted, count = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
	until count == 0
	return formatted
end

-- Primitives --------------------------------------------------------------------------------------------
function Theme.corner(object, radius)
	return create("UICorner", {CornerRadius = typeof(radius) == "UDim" and radius or UDim.new(0, radius or Theme.radius),
		Parent = object})
end

-- Gold hairline border drawn outside the element. transparency 0 = solid gold.
function Theme.stroke(object, transparency, color, thickness)
	return create("UIStroke", {Color = color or Theme.colors.accent, Thickness = thickness or 1,
		Transparency = transparency or 0.35, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = object})
end

-- colors / transparency: {{time, value}, ...} from 0 to 1. Note: a UIGradient tints the element's own
-- background AND its text, never its children.
function Theme.gradient(object, colors, rotation, transparency)
	return create("UIGradient", {Color = colors and colorSequence(colors) or nil,
		Transparency = transparency and numberSequence(transparency) or nil, Rotation = rotation or 0, Parent = object})
end

-- Gold leaf. Put it on an element whose BackgroundColor3 / TextColor3 is white (shows as gold) or ink
-- (stays ink, so dark text stays readable on a gold button).
function Theme.goldLeaf(object, rotation)
	return Theme.gradient(object, {{0, Theme.colors.goldBright}, {0.45, Color3.fromRGB(216, 182, 110)},
		{1, Color3.fromRGB(164, 125, 60)}}, rotation or 90)
end

-- 1 px gold rule. length: UDim along the rule. options: vertical, transparency, color, fade (default true),
-- fadeCurve, anchor, thickness.
function Theme.hairline(parent, name, length, position, options)
	options = options or {}
	local thickness = options.thickness or 1
	local size = options.vertical and UDim2.new(0, thickness, length.Scale, length.Offset)
		or UDim2.new(length.Scale, length.Offset, 0, thickness)
	local line = create("Frame", {Name = name, Size = size, Position = position,
		AnchorPoint = options.anchor or Vector2.new(0.5, 0.5), BackgroundColor3 = options.color or Theme.colors.accent,
		BackgroundTransparency = options.transparency or 0.35, BorderSizePixel = 0, Active = false, Parent = parent})
	if options.fade ~= false then
		Theme.gradient(line, nil, options.vertical and 90 or 0, options.fadeCurve or FADE_ENDS)
	end
	return line
end

-- Square turned 45 degrees: the house ornament. options: color, transparency, outline (onyx fill, gold edge).
function Theme.diamond(parent, name, size, position, options)
	options = options or {}
	local diamond = create("Frame", {Name = name, Size = UDim2.new(0, size, 0, size), Position = position,
		AnchorPoint = Vector2.new(0.5, 0.5), Rotation = 45, BorderSizePixel = 0, Active = false,
		BackgroundColor3 = options.outline and Theme.colors.background or (options.color or Theme.colors.accent),
		BackgroundTransparency = options.transparency or 0, Parent = parent})
	if options.outline then Theme.stroke(diamond, options.strokeTransparency or 0.1) end
	return diamond
end

-- Gold rule with a centred diamond (outlined, with a gold pip), e.g. under a title or above the directory.
function Theme.rule(parent, name, width, position, options)
	options = options or {}
	local holder = create("Frame", {Name = name, Size = UDim2.new(width.Scale, width.Offset, 0, 11), Position = position,
		AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, BorderSizePixel = 0, Active = false, Parent = parent})
	Theme.hairline(holder, "Line", UDim.new(1, 0), UDim2.new(0.5, 0, 0.5, 0), {transparency = options.transparency or 0.3})
	Theme.diamond(holder, "Ornament", 7, UDim2.new(0.5, 0, 0.5, 0), {outline = true})
	Theme.diamond(holder, "Pip", 3, UDim2.new(0.5, 0, 0.5, 0))
	return holder
end

-- Polished black marble: a slow diagonal sheen plus a few fine white veins, clipped to the frame.
local VEINS = { -- {x, y, length (scale of width), rotation, transparency}
	{{0.22, 0.34, 0.9, 27, 0.88}, {0.42, 0.52, 0.32, 9, 0.92}, {0.86, 0.9, 0.7, -33, 0.9}},
	{{0.7, 0.24, 0.95, -21, 0.88}, {0.52, 0.4, 0.3, -52, 0.92}, {0.16, 0.86, 0.6, 18, 0.91}},
	{{0.4, 0.7, 1.1, -14, 0.89}, {0.78, 0.58, 0.28, 38, 0.92}, {0.1, 0.18, 0.5, 31, 0.91}},
}
function Theme.marble(frame, seed)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	Theme.gradient(frame, {{0, Color3.fromRGB(31, 31, 34)}, {0.38, Color3.fromRGB(13, 13, 15)},
		{0.64, Color3.fromRGB(22, 22, 25)}, {1, Color3.fromRGB(9, 9, 10)}}, 28)
	local stone = create("Frame", {Name = "Marble", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
		BorderSizePixel = 0, ClipsDescendants = true, Active = false, ZIndex = 0, Parent = frame})
	for index, vein in ipairs(VEINS[((seed or 0) % #VEINS) + 1]) do
		local line = create("Frame", {Name = "Vein" .. index, Size = UDim2.new(vein[3], 0, 0, 1),
			Position = UDim2.new(vein[1], 0, vein[2], 0), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = vein[4],
			BackgroundColor3 = Theme.colors.vein, BackgroundTransparency = vein[5], BorderSizePixel = 0, Active = false,
			Parent = stone})
		Theme.gradient(line, nil, 0, {{0, 1}, {0.25, 0.35}, {0.5, 0}, {0.72, 0.5}, {1, 1}})
	end
	return stone
end

-- Inner gold frame with diamond corners: the double border of a hotel menu card.
function Theme.inlay(frame, inset, transparency)
	inset = inset or 8
	local inlay = create("Frame", {Name = "Inlay", Size = UDim2.new(1, -2 * inset, 1, -2 * inset),
		Position = UDim2.new(0, inset, 0, inset), BackgroundTransparency = 1, BorderSizePixel = 0, Active = false,
		Parent = frame})
	Theme.stroke(inlay, transparency or 0.62)
	for index, corner in ipairs({{0, 0}, {1, 0}, {0, 1}, {1, 1}}) do
		Theme.diamond(inlay, "Corner" .. index, 5, UDim2.new(corner[1], 0, corner[2], 0))
	end
	return inlay
end

-- Gold coin mark (replaces the coin emoji): gold-leaf disc with an engraved rim.
function Theme.coin(parent, name, size, position)
	local coin = create("Frame", {Name = name, Size = UDim2.new(0, size, 0, size), Position = position,
		AnchorPoint = Vector2.new(1, 0.5), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Active = false,
		Parent = parent})
	Theme.corner(coin, UDim.new(0.5, 0))
	Theme.goldLeaf(coin, 45)
	local rim = create("Frame", {Name = "Rim", Size = UDim2.new(1, -6, 1, -6), Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, BorderSizePixel = 0, Active = false, Parent = coin})
	Theme.corner(rim, UDim.new(0.5, 0))
	Theme.stroke(rim, 0.45, Theme.colors.goldDeep)
	return coin
end

-- Surfaces -----------------------------------------------------------------------------------------------
-- Black-marble panel with a gold hairline edge. options: seed (vein pattern), transparency, strokeTransparency.
function Theme.panel(parent, name, size, position, options)
	options = options or {}
	local frame = create("Frame", {Name = name, Size = size, Position = position or UDim2.new(),
		BackgroundColor3 = Theme.colors.panel, BackgroundTransparency = options.transparency or 0.04, BorderSizePixel = 0,
		Parent = parent})
	Theme.corner(frame)
	Theme.stroke(frame, options.strokeTransparency or 0.2)
	Theme.marble(frame, options.seed)
	return frame
end

-- options: bold, color, align, yAlign, frameSize, font, rich, transparency
function Theme.label(parent, name, text, size, options)
	options = options or {}
	return create("TextLabel", {Name = name, Text = text, TextSize = size or 16,
		Font = options.font or (options.bold and Theme.fontBold or Theme.font),
		TextColor3 = options.color or Theme.colors.text, TextTransparency = options.transparency or 0,
		BackgroundTransparency = 1, BorderSizePixel = 0, Size = options.frameSize or UDim2.new(1, 0, 0, (size or 16) + 8),
		TextXAlignment = options.align or Enum.TextXAlignment.Left,
		TextYAlignment = options.yAlign or Enum.TextYAlignment.Center, RichText = options.rich == true,
		TextWrapped = true, Parent = parent})
end

-- English signage line: spaced small caps in gold. Same options as Theme.label; centred by default.
function Theme.caption(parent, name, text, size, options)
	options = options or {}
	options.font = Theme.fontCaps
	options.color = options.color or Theme.colors.accent
	options.align = options.align or Enum.TextXAlignment.Center
	return Theme.label(parent, name, Theme.track(text), size or 11, options)
end

-- Buttons ----------------------------------------------------------------------------------------------
local LOOKS = {
	-- Solid gold leaf, ink text: the one call to action per screen.
	primary = {bg = Color3.fromRGB(232, 232, 232), bgHot = Color3.new(1, 1, 1), bgT = 0, bgTHot = 0,
		text = Theme.colors.ink, stroke = Theme.colors.goldBright, strokeT = 0.35, strokeTHot = 0},
	-- Gold hairline, gold text, fills with a whisper of gold on hover (purchases, close).
	outline = {bg = Theme.colors.accent, bgHot = Theme.colors.accent, bgT = 1, bgTHot = 0.86,
		text = Theme.colors.accent, textHot = Theme.colors.goldBright, stroke = Theme.colors.accent, strokeT = 0.25, strokeTHot = 0},
	-- Black lacquer placard with a faint gold edge that lights up on hover / when selected.
	plain = {bg = Theme.colors.panel, bgHot = Theme.colors.panelLight, bgT = 0.1, bgTHot = 0.02,
		text = Theme.colors.text, stroke = Theme.colors.accent, strokeT = 0.58, strokeTHot = 0.08},
	danger = {bg = Theme.colors.danger, bgHot = Color3.fromRGB(168, 64, 58), bgT = 0.05, bgTHot = 0,
		text = Theme.colors.text, stroke = Theme.colors.accent, strokeT = 0.5, strokeTHot = 0.15},
}

-- Holder for a button's decoration (caption, inlay, underline, switch). It cancels the button's UIPadding
-- so decoration is laid out against the full button while the label text stays padded.
function Theme.trim(button)
	local trim = button:FindFirstChild("Trim")
	if trim then return trim end
	local padding = button:FindFirstChildOfClass("UIPadding")
	local function offset(key)
		local value = padding and padding[key]
		return value and value.Offset or 0
	end
	local left, right, top, bottom = offset("PaddingLeft"), offset("PaddingRight"), offset("PaddingTop"), offset("PaddingBottom")
	return create("Frame", {Name = "Trim", Size = UDim2.new(1, left + right, 1, top + bottom),
		Position = UDim2.new(0, -left, 0, -top), BackgroundTransparency = 1, BorderSizePixel = 0, Active = false,
		Parent = button})
end

-- options: primary | outline | danger (default: plain placard), size (UDim2), order, textSize,
-- caption (short ASCII small-caps line above the label), captionAlign, padLeft, align, rich, selectable
function Theme.button(parent, name, text, onClick, options)
	options = options or {}
	local variant = options.primary and "primary" or options.outline and "outline" or options.danger and "danger" or "plain"
	local look = LOOKS[variant]
	local button = create("TextButton", {Name = name, Text = text, TextSize = options.textSize or 18, Font = Theme.fontBold,
		TextColor3 = look.text, BackgroundColor3 = look.bg, BackgroundTransparency = look.bgT, AutoButtonColor = false,
		BorderSizePixel = 0, RichText = options.rich == true, TextXAlignment = options.align or Enum.TextXAlignment.Center,
		Size = options.size or UDim2.new(1, 0, 0, 48), LayoutOrder = options.order or 0, Parent = parent})
	Theme.corner(button)
	local stroke = Theme.stroke(button, look.strokeT, look.stroke)
	if variant == "primary" then Theme.goldLeaf(button, 90) end

	local padTop = options.caption and (options.captionPad or 20) or 0
	local padLeft = options.padLeft or 0
	if padTop > 0 or padLeft > 0 then
		create("UIPadding", {PaddingTop = UDim.new(0, padTop), PaddingLeft = UDim.new(0, padLeft),
			PaddingRight = UDim.new(0, padLeft), Parent = button})
	end
	local trim = Theme.trim(button)
	if variant == "primary" then
		local inlay = create("Frame", {Name = "Inlay", Size = UDim2.new(1, -8, 1, -8), Position = UDim2.new(0, 4, 0, 4),
			BackgroundTransparency = 1, BorderSizePixel = 0, Active = false, Parent = trim})
		Theme.stroke(inlay, 0.62, Theme.colors.ink)
	end
	if options.caption then
		local alignLeft = options.captionAlign == Enum.TextXAlignment.Left
		local caption = Theme.caption(trim, "Caption", options.caption, options.captionSize or 10, {
			color = variant == "primary" and Theme.colors.ink or Theme.colors.accent,
			transparency = variant == "primary" and 0.3 or 0,
			align = options.captionAlign, frameSize = UDim2.new(1, -2 * math.max(padLeft, 6), 0, 14)})
		caption.AnchorPoint = Vector2.new(alignLeft and 0 or 0.5, 0)
		caption.Position = alignLeft and UDim2.new(0, padLeft, 0, 11) or UDim2.new(0.5, 0, 0, 11)
	end
	local underline
	if options.selectable then
		underline = create("Frame", {Name = "Underline", Size = UDim2.new(0, 28, 0, 2), AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -6), BackgroundColor3 = Theme.colors.accent, BorderSizePixel = 0,
			Visible = false, Active = false, Parent = trim})
	end

	local hovering = false
	local function paint(instant)
		local selected = button:GetAttribute("Selected") == true
		local hot = hovering or selected
		Theme.tween(button, {BackgroundColor3 = hot and look.bgHot or look.bg,
			BackgroundTransparency = hot and look.bgTHot or look.bgT,
			TextColor3 = hovering and look.textHot or look.text}, instant)
		Theme.tween(stroke, {Transparency = hot and look.strokeTHot or look.strokeT}, instant)
		if underline then underline.Visible = selected end
	end
	paint(true)
	button.MouseEnter:Connect(function() hovering = true; paint() end)
	button.MouseLeave:Connect(function() hovering = false; paint() end)
	button:GetAttributeChangedSignal("Selected"):Connect(function() paint() end)
	button.Activated:Connect(function() onClick(button) end)
	return button
end

-- Marks a placard as the current one (gold edge + underline).
function Theme.setSelected(button, selected)
	button:SetAttribute("Selected", selected == true)
end

-- On/off switch drawn inside a button's Trim (right-hand side); call again to update.
function Theme.switch(button, on, instant)
	local trim = Theme.trim(button)
	local track = trim:FindFirstChild("Track")
	if not track then
		track = create("Frame", {Name = "Track", Size = UDim2.new(0, 52, 0, 26), AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -20, 0.5, 0), BorderSizePixel = 0, Active = false, Parent = trim})
		Theme.corner(track, UDim.new(0.5, 0))
		Theme.stroke(track, 0.3)
		local knob = create("Frame", {Name = "Knob", Size = UDim2.new(0, 18, 0, 18), AnchorPoint = Vector2.new(0.5, 0.5),
			BorderSizePixel = 0, Active = false, Parent = track})
		Theme.corner(knob, UDim.new(0.5, 0))
		instant = true
	end
	local knob = track:FindFirstChild("Knob")
	Theme.tween(track, {BackgroundColor3 = on and Theme.colors.accent or Theme.colors.background,
		BackgroundTransparency = on and 0.72 or 0.1}, instant)
	Theme.tween(knob, {Position = on and UDim2.new(1, -13, 0.5, 0) or UDim2.new(0, 13, 0.5, 0),
		BackgroundColor3 = on and Theme.colors.goldBright or Theme.colors.subtext}, instant)
	return track
end

return Theme
