-- UI theme shared by every screen: "night harbour & navy".
-- Navy is the cloth (uniform wool, night water), white is the piping and the rope, red is the
-- neckerchief and the one action colour. Brass is the only metal and is kept for round hardware
-- (portholes, coins, bolts) so it reads as a material, not as a fourth UI colour.
-- The ornaments themselves (signal flags, portholes, rope...) live in NavalMotif.luau.
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local Theme = {}

local rgb = Color3.fromRGB

Theme.palette = {
	night = rgb(6, 11, 26), -- zenith of the night sky, deepest navy
	deep = rgb(11, 21, 46), -- harbour water, sunken wells
	navy = rgb(19, 36, 76), -- uniform wool: panels
	navyRaised = rgb(29, 52, 104), -- buttons and rows sitting on a panel
	navyLine = rgb(52, 82, 146), -- glass highlight, hairlines on navy
	flagBlue = rgb(30, 66, 158), -- signal-flag blue, a step brighter than the cloth so flags read at night
	white = rgb(243, 240, 231), -- uniform white (warm, never pure #FFF)
	whiteDim = rgb(172, 186, 216), -- secondary text on navy
	red = rgb(204, 34, 49), -- neckerchief / signal red: the action colour
	redDeep = rgb(140, 20, 34),
	brass = rgb(201, 160, 72),
	brassLight = rgb(245, 218, 146),
	brassDark = rgb(112, 80, 26),
	rope = rgb(232, 223, 201),
	ropeShade = rgb(150, 138, 110),
	ink = rgb(4, 8, 19),
}
local P = Theme.palette

-- Role names other screens already use. "accent" is now the neckerchief red; "success" is white
-- (the affirmative flag C is navy/white/red, there is no green in this world).
Theme.colors = {
	background = P.night,
	panel = P.navy,
	panelLight = P.navyRaised,
	accent = P.red,
	text = P.white,
	subtext = P.whiteDim,
	danger = P.red,
	success = P.white,
	piping = P.white,
}

local OSWALD = "rbxasset://fonts/families/Oswald.json"
local SOURCE_SANS = "rbxasset://fonts/families/SourceSansPro.json"
Theme.fonts = {
	display = Font.new(OSWALD, Enum.FontWeight.Bold), -- condensed stencil-like caps: title, numbers, captions
	displayLight = Font.new(OSWALD, Enum.FontWeight.Medium),
	body = Font.new(SOURCE_SANS, Enum.FontWeight.SemiBold),
	bodyBold = Font.new(SOURCE_SANS, Enum.FontWeight.Bold),
}
-- Legacy Enum.Font values for screens that still assign .Font directly.
Theme.font = Enum.Font.SourceSansSemibold
Theme.fontBold = Enum.Font.SourceSansBold

local function create(className, props)
	local object = Instance.new(className)
	for key, value in pairs(props) do
		if key ~= "Parent" then object[key] = value end
	end
	object.Parent = props.Parent
	return object
end
Theme.create = create

-- Motion ---------------------------------------------------------------------------------------------
function Theme.reducedMotion()
	local ok, value = pcall(function() return GuiService.ReducedMotionEnabled end)
	return ok and value == true
end

-- Short state tween (hover / press). Applies instantly under Reduced Motion.
function Theme.tween(object, seconds, goal)
	if Theme.reducedMotion() or not seconds or seconds <= 0 then
		for key, value in pairs(goal) do object[key] = value end
		return nil
	end
	local tween = TweenService:Create(object, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
	tween:Play()
	return tween
end

-- Endless back-and-forth ambient motion (flag sway, lamp shimmer). Skipped under Reduced Motion.
function Theme.loop(object, seconds, goal, delaySeconds)
	if Theme.reducedMotion() then return nil end
	local tween = TweenService:Create(object,
		TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, delaySeconds or 0), goal)
	tween:Play()
	return tween
end

-- Primitives -----------------------------------------------------------------------------------------
-- radius: pixels (number) or a UDim (UDim.new(0.5, 0) for a full circle).
function Theme.corner(object, radius)
	local value = type(radius) == "number" and UDim.new(0, radius) or radius or UDim.new(0, 8)
	return create("UICorner", {CornerRadius = value, Parent = object})
end

-- Border stroke (defaults to the white piping). Always Border mode so it never outlines text.
function Theme.stroke(object, color, thickness, transparency)
	return create("UIStroke", {Color = color or P.white, Thickness = thickness or 1.5, Transparency = transparency or 0.2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, LineJoinMode = Enum.LineJoinMode.Round, Parent = object})
end

-- stops: {{time, Color3}, ...}; transparency: optional {{time, number}, ...}. Parent may be a UIStroke.
function Theme.gradient(object, stops, rotation, transparency)
	local keys = {}
	for _, stop in ipairs(stops) do table.insert(keys, ColorSequenceKeypoint.new(stop[1], stop[2])) end
	local props = {Color = ColorSequence.new(keys), Rotation = rotation or 0, Parent = object}
	if transparency then
		local tkeys = {}
		for _, stop in ipairs(transparency) do table.insert(tkeys, NumberSequenceKeypoint.new(stop[1], stop[2])) end
		props.Transparency = NumberSequence.new(tkeys)
	end
	return create("UIGradient", props)
end

-- Sailor-collar piping: `count` thin lines running just inside the edge of `frame`.
-- options: count, inset, gap, radius, color, thickness, transparency,
--          pad = {left, right} when the frame also has a UIPadding (keeps the lines on the true edge).
function Theme.piping(frame, options)
	options = options or {}
	local count, inset, gap = options.count or 1, options.inset or 5, options.gap or 4
	local radius = options.radius or 10
	local padLeft = options.pad and options.pad.left or 0
	local padRight = options.pad and options.pad.right or 0
	for index = 1, count do
		local offset = inset + (index - 1) * gap
		local line = create("Frame", {Name = "Piping" .. index, BackgroundTransparency = 1, BorderSizePixel = 0,
			Position = UDim2.fromOffset(offset - padLeft, offset),
			Size = UDim2.new(1, padLeft + padRight - offset * 2, 1, -offset * 2), Parent = frame})
		Theme.corner(line, math.max(radius - offset, 2))
		create("UIStroke", {Color = options.color or P.white, Thickness = options.thickness or 1,
			Transparency = options.transparency or 0.55, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = line})
	end
end

-- Panels -----------------------------------------------------------------------------------------------
-- A panel is a piece of navy uniform cloth: white edge + one inner line of piping.
-- options.variant = "row" gives the lighter, quieter card used for list rows.
function Theme.panel(parent, name, size, position, options)
	options = options or {}
	local row = options.variant == "row"
	local frame = create("Frame", {Name = name, Size = size, Position = position or UDim2.new(),
		BackgroundColor3 = row and P.navyRaised or P.navy, BackgroundTransparency = 0, BorderSizePixel = 0, Parent = parent})
	Theme.corner(frame, row and 8 or 12)
	if row then
		Theme.stroke(frame, P.white, 1, 0.72)
	else
		Theme.stroke(frame, P.white, 2, 0.1)
		Theme.gradient(frame, {{0, Color3.new(1, 1, 1)}, {1, rgb(205, 210, 222)}}, 90) -- wool falls into shadow
		Theme.piping(frame, {inset = 6, radius = 12, transparency = 0.6})
	end
	return frame
end

-- options: bold, display (Oswald caps), font (FontFace), color, frameSize, align, yAlign, transparency
function Theme.label(parent, name, text, size, options)
	options = options or {}
	local face = options.font or (options.display and Theme.fonts.display) or (options.bold and Theme.fonts.bodyBold) or Theme.fonts.body
	return create("TextLabel", {Name = name, Text = text, TextSize = size or 16, FontFace = face,
		TextColor3 = options.color or P.white, TextTransparency = options.transparency or 0, BackgroundTransparency = 1,
		Size = options.frameSize or UDim2.new(1, 0, 0, (size or 16) + 8),
		TextXAlignment = options.align or Enum.TextXAlignment.Left, TextYAlignment = options.yAlign or Enum.TextYAlignment.Center,
		TextWrapped = true, Parent = parent})
end

-- Buttons ----------------------------------------------------------------------------------------------
local VARIANTS = {
	-- the neckerchief: red cloth, ink edge, white piping
	primary = {fill = P.red, text = P.white, stroke = P.ink, strokeWidth = 2, strokeT = 0.15, piping = 0.35},
	-- navy with a red warning edge; never a second filled red
	danger = {fill = P.deep, text = rgb(255, 136, 144), stroke = P.red, strokeWidth = 2, strokeT = 0},
	-- raised navy with the white double line of the sailor collar
	default = {fill = P.navyRaised, text = P.white, stroke = P.white, strokeWidth = 1.5, strokeT = 0.25, piping = 0.7},
}

local function isPress(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

-- options: primary, danger, size (UDim2), order, textSize, radius, align (TextXAlignment),
--          padding = {left, right} (text inset), piping = false to omit the inner line
function Theme.button(parent, name, text, onClick, options)
	options = options or {}
	local style = options.primary and VARIANTS.primary or options.danger and VARIANTS.danger or VARIANTS.default
	local base = style.fill
	local radius = options.radius or 8
	local button = create("TextButton", {Name = name, Text = text, TextSize = options.textSize or 18, FontFace = Theme.fonts.bodyBold,
		TextColor3 = style.text, BackgroundColor3 = base, AutoButtonColor = false, BorderSizePixel = 0,
		TextXAlignment = options.align or Enum.TextXAlignment.Center,
		Size = options.size or UDim2.new(1, 0, 0, 48), LayoutOrder = options.order or 0, Parent = parent})
	Theme.corner(button, radius)
	Theme.stroke(button, style.stroke, style.strokeWidth, style.strokeT)
	if options.padding then
		create("UIPadding", {PaddingLeft = UDim.new(0, options.padding.left or 0), PaddingRight = UDim.new(0, options.padding.right or 0),
			Parent = button})
	end
	if style.piping and options.piping ~= false then
		Theme.piping(button, {inset = 4, radius = radius, transparency = style.piping, pad = options.padding})
	end
	local scale = create("UIScale", {Scale = 1, Parent = button})

	local hovered, pressed = false, false
	local function refresh()
		local color = base
		if pressed then
			color = base:Lerp(Color3.new(0, 0, 0), 0.2)
		elseif hovered then
			color = base:Lerp(Color3.new(1, 1, 1), 0.1)
		end
		Theme.tween(button, 0.12, {BackgroundColor3 = color})
		Theme.tween(scale, 0.08, {Scale = pressed and 0.97 or 1})
	end
	button.MouseEnter:Connect(function() hovered = true; refresh() end)
	button.MouseLeave:Connect(function() hovered = false; pressed = false; refresh() end)
	button.InputBegan:Connect(function(input) if isPress(input) then pressed = true; refresh() end end)
	button.InputEnded:Connect(function(input) if isPress(input) then pressed = false; refresh() end end)
	button.Activated:Connect(function() onClick(button) end)
	return button
end

return Theme
