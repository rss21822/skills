-- UI theme shared by every screen: "Retro Toy Box".
-- Palette sampled from the mood board (moodboard-retro-toys.png): warm cream paper, chocolate-brown
-- outlines, mustard / teal / coral / sky / mint toy colours. Everything is flat (no gradients, no
-- glow); depth comes from thick brown outlines and a brown "toy block" base under buttons.
--
-- Readability rule: text only ever sits on a cream window (brown text, >= 9:1) or on a brown pill
-- (cream text, 10:1). Coloured surfaces (coral, teal...) are frames around the text, never behind it.
--
-- API kept compatible with the previous theme: Theme.colors.* keys, Theme.font / Theme.fontBold
-- (Enum.Font values), Theme.create / corner / stroke / panel / label / button with the same
-- arguments. Theme.button still returns the TextButton and its .Text is still the source of truth
-- (the visible label mirrors it), so scripts that find buttons by name and read/write .Text keep working.
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local Theme = {}

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

-- Raw palette (hex values from the mood board).
Theme.palette = {
	cream = rgb(246, 236, 214), -- #F6ECD6 page / background paper
	creamLight = rgb(255, 244, 222), -- #FFF4DE inner windows, cards
	creamDark = rgb(230, 213, 182), -- #E6D5B6 "off" switch track, pressed windows
	brown = rgb(86, 52, 38), -- #563426 outlines, text, pills
	brownSoft = rgb(126, 94, 74), -- #7E5E4A secondary text (5.4:1 on creamLight)
	mustard = rgb(232, 176, 52), -- #E8B034 stripes, stars, coins
	teal = rgb(38, 150, 150), -- #269696 donut ring
	coral = rgb(238, 108, 84), -- #EE6C54 the "frame" toy, primary actions
	sky = rgb(120, 190, 220), -- #78BEDC robot
	mint = rgb(150, 205, 160), -- #96CDA0 confetti
	white = rgb(255, 255, 255), -- robot eyes, hover highlight
}
local P = Theme.palette

-- Legacy semantic keys (other screens read these) remapped onto the new palette, plus new ones.
Theme.colors = {
	background = P.cream,
	panel = P.creamLight,
	panelLight = P.cream,
	accent = P.coral,
	secondary = P.sky,
	text = P.brown,
	subtext = P.brownSoft,
	danger = rgb(214, 78, 60),
	success = P.teal,
	outline = P.brown,
	window = P.creamLight,
}

-- Fonts. FredokaOne (chunky rounded) for Latin display text and numbers; Nunito ExtraBold/Black for
-- labels. Japanese glyphs come from Roblox's CJK fallback; asking for a heavy weight is what lets
-- that fallback render bold kana (FredokaOne only ships a Regular face).
Theme.font = Enum.Font.Nunito
Theme.fontBold = Enum.Font.FredokaOne
local fredoka = Font.fromEnum(Enum.Font.FredokaOne).Family
local nunito = Font.fromEnum(Enum.Font.Nunito).Family
Theme.fonts = {
	display = Font.new(fredoka, Enum.FontWeight.Bold),
	label = Font.new(nunito, Enum.FontWeight.ExtraBold),
	heavy = Font.new(nunito, Enum.FontWeight.Heavy),
	body = Font.new(nunito, Enum.FontWeight.Bold),
}

-- Shape tokens.
Theme.outline = 4 -- px, big shapes
Theme.outlineSmall = 3 -- px, buttons / rows
Theme.depth = 5 -- px, brown toy-block base under buttons

local function create(className, props)
	local object = Instance.new(className)
	for key, value in pairs(props) do
		if key ~= "Parent" then object[key] = value end
	end
	object.Parent = props.Parent
	return object
end
Theme.create = create

function Theme.reducedMotion()
	local ok, value = pcall(function() return GuiService.ReducedMotionEnabled end)
	return ok and value == true
end

function Theme.tween(instance, seconds, goal, style, direction)
	local tween = TweenService:Create(instance, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
	tween:Play()
	return tween
end

-- Endless gentle ping-pong (idle bob, twinkle, breathing). Skipped when the player asked for reduced motion.
function Theme.idle(instance, seconds, goal)
	if Theme.reducedMotion() then return nil end
	local tween = TweenService:Create(instance, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), goal)
	tween:Play()
	return tween
end

function Theme.corner(object, radius)
	local value = typeof(radius) == "UDim" and radius or UDim.new(0, radius or 12)
	return create("UICorner", {CornerRadius = value, Parent = object})
end

-- Outline in the mood-board brown. Legacy call Theme.stroke(object) still works.
function Theme.stroke(object, thickness, color)
	return create("UIStroke", {Color = color or P.brown, Thickness = thickness or Theme.outlineSmall, Transparency = 0,
		LineJoinMode = Enum.LineJoinMode.Round, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = object})
end

function Theme.padding(object, left, right, top, bottom)
	return create("UIPadding", {PaddingLeft = UDim.new(0, left or 0), PaddingRight = UDim.new(0, right or left or 0),
		PaddingTop = UDim.new(0, top or 0), PaddingBottom = UDim.new(0, bottom or top or 0), Parent = object})
end

-- 1234567 -> "1,234,567"
function Theme.formatNumber(value)
	local text = tostring(math.floor(tonumber(value) or 0))
	local sign, digits = string.match(text, "^(-?)(%d+)$")
	if not digits then return text end
	local out = digits
	while true do
		local replaced, count = string.gsub(out, "^(%d+)(%d%d%d)", "%1,%2")
		out = replaced
		if count == 0 then break end
	end
	return sign .. out
end

-- options: color (fill, default creamLight), radius, stroke (px, 0 = none)
function Theme.panel(parent, name, size, position, options)
	options = options or {}
	local frame = create("Frame", {Name = name, Size = size, Position = position or UDim2.new(),
		BackgroundColor3 = options.color or P.creamLight, BackgroundTransparency = 0, BorderSizePixel = 0, Parent = parent})
	Theme.corner(frame, options.radius or 18)
	if options.stroke ~= 0 then Theme.stroke(frame, options.stroke or Theme.outline) end
	return frame
end

-- options: bold, color, align, frameSize, font ("display" | "label" | "heavy" | "body"), valign
function Theme.label(parent, name, text, size, options)
	options = options or {}
	local face = options.font and Theme.fonts[options.font] or (options.bold and Theme.fonts.label or Theme.fonts.body)
	return create("TextLabel", {Name = name, Text = text, TextSize = size or 16, FontFace = face,
		TextColor3 = options.color or Theme.colors.text, BackgroundTransparency = 1, Size = options.frameSize or UDim2.new(1, 0, 0, (size or 16) + 8),
		TextXAlignment = options.align or Enum.TextXAlignment.Left, TextYAlignment = options.valign or Enum.TextYAlignment.Center,
		TextWrapped = true, Parent = parent})
end

-- A TextLabel that is itself a capsule: brown pill + cream text by default, like the "RETRO TOY BOX"
-- label on the mood board. Grows with its text (AutomaticSize X); an optional icon sits in the left padding.
-- options: color (fill), textColor, font, stroke (px outline), icon (fn(holder, px)), iconSize, padLeft, padRight
function Theme.tag(parent, name, text, textSize, height, options)
	options = options or {}
	local tag = create("TextLabel", {Name = name, Text = text, TextSize = textSize, FontFace = Theme.fonts[options.font or "heavy"],
		TextColor3 = options.textColor or P.creamLight, BackgroundColor3 = options.color or P.brown, BackgroundTransparency = 0,
		BorderSizePixel = 0, Size = UDim2.new(0, 0, 0, height), AutomaticSize = Enum.AutomaticSize.X, TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center, Parent = parent})
	Theme.corner(tag, UDim.new(0.5, 0))
	if options.stroke then Theme.stroke(tag, options.stroke) end
	local left = options.padLeft or math.floor(height * 0.42)
	if options.icon then
		local iconSize = options.iconSize or math.floor(height * 0.62)
		-- Children are placed inside the padded box, so a negative offset puts the icon in the left padding.
		local holder = create("Frame", {Name = "Icon", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, -(iconSize + 8), 0.5, 0),
			Size = UDim2.fromOffset(iconSize, iconSize), BackgroundTransparency = 1, Parent = tag})
		options.icon(holder, iconSize)
		left += iconSize + 8
	end
	Theme.padding(tag, left, options.padRight or math.floor(height * 0.45), 0, 0)
	return tag
end

-- Chunky toy button: a coloured bezel (like the coral frame on the mood board) around a cream window
-- that holds the brown label, sitting on a brown base that it presses down into.
-- options (old): primary, danger, size (UDim2, the whole hit area incl. base), order, textSize
-- options (new): color (bezel), depth (base px), inset (bezel px), radius, solid (no window: fill =
--   color, text = textColor), textColor, align (TextXAlignment), icon (fn(holder, px) drawing an icon
--   left of the label), iconSize, font
function Theme.button(parent, name, text, onClick, options)
	options = options or {}
	local bezel = options.color or (options.primary and Theme.colors.accent) or (options.danger and Theme.colors.danger)
		or Theme.colors.secondary
	local depth = options.depth or Theme.depth
	local radius = options.radius or 16
	local inset = options.inset or 6
	local textSize = options.textSize or 20

	local button = create("TextButton", {Name = name, Text = text, TextTransparency = 1, TextSize = textSize, FontFace = Theme.fonts.label,
		TextColor3 = P.brown, BackgroundTransparency = 1, AutoButtonColor = false, BorderSizePixel = 0,
		Size = options.size or UDim2.new(1, 0, 0, 56), LayoutOrder = options.order or 0, Parent = parent})

	local base = create("Frame", {Name = "Base", Position = UDim2.new(0, 0, 0, depth), Size = UDim2.new(1, 0, 1, -depth),
		BackgroundColor3 = P.brown, BorderSizePixel = 0, Parent = button})
	Theme.corner(base, radius)
	Theme.stroke(base, Theme.outlineSmall)

	local face = create("Frame", {Name = "Face", Position = UDim2.new(0, 0, 0, 0), Size = UDim2.new(1, 0, 1, -depth),
		BackgroundColor3 = bezel, BorderSizePixel = 0, Parent = button})
	Theme.corner(face, radius)
	Theme.stroke(face, Theme.outlineSmall)

	local window = face
	local windowColor = bezel
	if not options.solid then
		windowColor = P.creamLight
		window = create("Frame", {Name = "Window", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -inset * 2, 1, -inset * 2), BackgroundColor3 = windowColor, BorderSizePixel = 0, Parent = face})
		Theme.corner(window, math.max(4, radius - inset))
		Theme.stroke(window, 2)
	end

	local content = create("Frame", {Name = "Content", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = window})
	local align = options.align or Enum.TextXAlignment.Center
	create("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
		HorizontalAlignment = align == Enum.TextXAlignment.Left and Enum.HorizontalAlignment.Left or Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content})
	if align == Enum.TextXAlignment.Left then Theme.padding(content, 14, 14, 0, 0) end
	if options.icon then
		local iconSize = options.iconSize or math.floor(textSize * 1.35)
		local holder = create("Frame", {Name = "Icon", Size = UDim2.fromOffset(iconSize, iconSize), BackgroundTransparency = 1,
			LayoutOrder = 1, Parent = content})
		options.icon(holder, iconSize)
	end
	local label = create("TextLabel", {Name = "Label", Text = text, TextSize = textSize, FontFace = options.font or Theme.fonts.label,
		TextColor3 = options.textColor or P.brown, BackgroundTransparency = 1, Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2, Parent = content})
	-- The TextButton's own Text stays authoritative: whoever sets button.Text updates the visible label.
	button:GetPropertyChangedSignal("Text"):Connect(function() label.Text = button.Text end)

	-- States: rest / hover (window brightens, block lifts 1 px) / pressed (block sinks onto its base) / active.
	local hovered, pressed = false, false
	local function restColor()
		if button:GetAttribute("Active") == true and not options.solid then
			return P.creamLight:Lerp(bezel, 0.38)
		end
		return windowColor
	end
	local faceTween
	local function render(animated)
		local y = pressed and (depth - 1) or (hovered and -1 or 0)
		local target = UDim2.new(0, 0, 0, y)
		if faceTween then faceTween:Cancel() end -- a running hover tween must not undo a press
		faceTween = nil
		if animated and not pressed and not Theme.reducedMotion() then
			faceTween = Theme.tween(face, 0.14, {Position = target}, Enum.EasingStyle.Back)
		else
			face.Position = target
		end
		local color = restColor()
		if hovered and not pressed then color = color:Lerp(P.white, options.solid and 0.12 or 0.6) end
		window.BackgroundColor3 = color
	end
	button:GetAttributeChangedSignal("Active"):Connect(function() render(false) end)
	button.MouseEnter:Connect(function() hovered = true; render(true) end)
	button.MouseLeave:Connect(function() hovered = false; pressed = false; render(true) end)
	button.SelectionGained:Connect(function() hovered = true; render(true) end)
	button.SelectionLost:Connect(function() hovered = false; render(true) end)
	button.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			pressed = true
			render(false)
		end
	end)
	button.InputEnded:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			pressed = false
			render(true)
		end
	end)
	button.Activated:Connect(function()
		if pressed then -- a touch released somewhere odd must not leave the block stuck down
			pressed = false
			render(true)
		end
		onClick(button)
	end)
	return button
end

-- Marks a toy button as the current one (nav tab of the open page): its window takes a tint of the bezel colour.
function Theme.setActive(button, on)
	button:SetAttribute("Active", on == true)
end

return Theme
