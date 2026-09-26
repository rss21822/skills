-- UI theme shared by every screen: 夏祭りの縁日 (a summer-festival night market).
--
-- Palette: 提灯の朱 (lantern vermilion), 生成りの和紙 (unbleached washi), 墨 (sumi ink), 屋台の木 (stall wood),
-- ラムネ (ramune bottle aqua), 金魚 (goldfish orange), りんご飴 (candy-apple red) over a dusk sky.
-- Backward compatible with the previous theme: Theme.colors keys, Theme.font / Theme.fontBold,
-- Theme.create / corner / stroke / panel / label / button keep their signatures.
local Theme = {}

local function hex(value)
	return Color3.fromRGB(math.floor(value / 65536) % 256, math.floor(value / 256) % 256, value % 256)
end
Theme.hex = hex

local P = {
	vermilion = hex(0xE0382B), -- 提灯の朱
	vermilionLight = hex(0xF4633F),
	vermilionDeep = hex(0x9E1F18),
	lanternGlow = hex(0xFFB547), -- 灯りのにじみ
	lanternCore = hex(0xFFE3A1),
	lacquer = hex(0x24140F), -- 提灯の上輪・下輪 (black lacquer)
	washi = hex(0xFFF4DE), -- 生成り
	washiWhite = hex(0xFFFBF2),
	washiShade = hex(0xEFD9B4),
	ink = hex(0x2B1A14), -- 墨
	inkSoft = hex(0x6B4F40),
	wood = hex(0xB5743C), -- 屋台の木
	woodLight = hex(0xE8B676),
	woodDark = hex(0x6A3B1C),
	ramune = hex(0x74D4E4), -- ラムネ瓶
	ramuneDeep = hex(0x1F8FAD),
	ramuneFoam = hex(0xE6FAFF),
	water = hex(0x66C9DE), -- 金魚すくいの水
	waterDeep = hex(0x2A8EB0),
	tubRim = hex(0xD8F4FA),
	goldfish = hex(0xFF5A2C), -- 金魚
	goldfishLight = hex(0xFF9C4A),
	demekin = hex(0x2C2326), -- 出目金
	candy = hex(0xD8122C), -- りんご飴
	candyDeep = hex(0x8A0A1C),
	leaf = hex(0x4E9E57),
	bamboo = hex(0x3C8A4F), -- 若竹
	wisteria = hex(0x7B55A3), -- 藤
	gold = hex(0xEDB83E), -- 五円玉
	goldDeep = hex(0x9C6A12),
	duskTop = hex(0x3E1A57), -- 夕暮れ (plum, deliberately not navy)
	duskMid = hex(0x9C3A6A),
	duskLow = hex(0xE8854A),
	ground = hex(0x4A1E2C), -- 境内の地面
	night = hex(0x1E0B1F),
}
Theme.palette = P

-- Legacy keys other screens may read (remapped to the festival palette).
Theme.colors = {
	background = P.duskTop,
	panel = P.washi,
	panelLight = P.woodLight,
	accent = P.vermilion,
	text = P.ink,
	subtext = P.inkSoft,
	danger = P.candy,
	success = P.bamboo,
}

-- Fonts. Latin/numbers use the rounded FredokaOne and the chunky, hand-painted-sign LuckiestGuy;
-- Japanese glyphs fall back to Roblox's CJK font, so every face asks for a heavy weight.
local FREDOKA = "rbxasset://fonts/families/FredokaOne.json"
local LUCKIEST = "rbxasset://fonts/families/LuckiestGuy.json"
Theme.font = Enum.Font.FredokaOne
Theme.fontBold = Enum.Font.FredokaOne
Theme.fontDisplay = Enum.Font.LuckiestGuy
Theme.faces = {
	body = Font.new(FREDOKA, Enum.FontWeight.Medium),
	bold = Font.new(FREDOKA, Enum.FontWeight.Bold),
	display = Font.new(LUCKIEST, Enum.FontWeight.Regular),
}

local function create(className, props)
	local object = Instance.new(className)
	for key, value in pairs(props) do
		if key ~= "Parent" then object[key] = value end
	end
	object.Parent = props.Parent
	return object
end
Theme.create = create

-- radius: pixels (number) or a UDim (UDim.new(0.5, 0) = pill / circle).
function Theme.corner(object, radius)
	local value = (radius == nil or type(radius) == "number") and UDim.new(0, radius or 10) or radius
	return create("UICorner", {CornerRadius = value, Parent = object})
end

function Theme.round(object)
	return Theme.corner(object, UDim.new(0.5, 0))
end

-- Border stroke. Theme.stroke(object) keeps working (dark wood, 2 px).
function Theme.stroke(object, color, thickness, transparency)
	return create("UIStroke", {Color = color or P.woodDark, Thickness = thickness or 2, Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, LineJoinMode = Enum.LineJoinMode.Round, Parent = object})
end

-- Outline around a TextLabel's glyphs (Contextual stroke).
function Theme.textStroke(label, color, thickness, transparency)
	return create("UIStroke", {Name = "TextStroke", Color = color or P.ink, Thickness = thickness or 2,
		Transparency = transparency or 0, LineJoinMode = Enum.LineJoinMode.Round, Parent = label})
end

-- stops: {{time, Color3}, ...}; rotation 90 = top to bottom. Colours multiply the background colour.
function Theme.gradient(object, stops, rotation, transparencyStops)
	local keypoints = {}
	for _, stop in ipairs(stops) do table.insert(keypoints, ColorSequenceKeypoint.new(stop[1], stop[2])) end
	local props = {Color = ColorSequence.new(keypoints), Rotation = rotation or 90, Parent = object}
	if transparencyStops then
		local numbers = {}
		for _, stop in ipairs(transparencyStops) do table.insert(numbers, NumberSequenceKeypoint.new(stop[1], stop[2])) end
		props.Transparency = NumberSequence.new(numbers)
	end
	return create("UIGradient", props)
end

-- Soft volume: lighter on one side, darker on the other (multiplies whatever colour the object has).
function Theme.shade(object, rotation, dark)
	local low = 1 - (dark or 0.22)
	return Theme.gradient(object, {{0, Color3.new(1, 1, 1)}, {1, Color3.new(low, low, low)}}, rotation or 90)
end

-- A sheet of washi paper framed in dark stall wood.
function Theme.panel(parent, name, size, position)
	local frame = create("Frame", {Name = name, Size = size, Position = position or UDim2.new(),
		BackgroundColor3 = P.washi, BackgroundTransparency = 0, BorderSizePixel = 0, Parent = parent})
	Theme.corner(frame, 12)
	Theme.stroke(frame, P.woodDark, 2)
	Theme.gradient(frame, {{0, Color3.new(1, 1, 1)}, {1, Color3.fromRGB(246, 236, 220)}}, 90)
	return frame
end

-- options: bold, display, color, align, alignY, frameSize, stroke (Color3), strokeThickness, face (Font)
function Theme.label(parent, name, text, size, options)
	options = options or {}
	local face = options.face or (options.display and Theme.faces.display) or (options.bold and Theme.faces.bold) or Theme.faces.body
	local label = create("TextLabel", {Name = name, Text = text, TextSize = size or 16, FontFace = face,
		TextColor3 = options.color or P.ink, BackgroundTransparency = 1, BorderSizePixel = 0,
		Size = options.frameSize or UDim2.new(1, 0, 0, (size or 16) + 8),
		TextXAlignment = options.align or Enum.TextXAlignment.Left, TextYAlignment = options.alignY or Enum.TextYAlignment.Center,
		TextWrapped = true, Parent = parent})
	if options.stroke then Theme.textStroke(label, options.stroke, options.strokeThickness or 2) end
	return label
end

-- Button looks: a chunky face sitting on a darker "lip" so it reads as something you can press.
Theme.buttonStyles = {
	primary = {face = P.vermilion, lip = P.vermilionDeep, text = P.washi, outline = hex(0x4A140F), textStroke = hex(0x5E1510)},
	danger = {face = P.candy, lip = P.candyDeep, text = P.washi, outline = hex(0x3E0710), textStroke = hex(0x4A0812)},
	wood = {face = P.woodLight, lip = P.wood, text = P.ink, outline = P.woodDark},
	washi = {face = P.washiWhite, lip = P.woodLight, text = P.ink, outline = P.woodDark},
	ramune = {face = P.ramune, lip = P.ramuneDeep, text = P.ink, outline = hex(0x155A6E)},
}

local LIP = 6
local PRESS = 4

local function services()
	local tweenService = game:GetService("TweenService")
	local guiService = game:GetService("GuiService")
	return tweenService, guiService
end

local function reducedMotion()
	local _, guiService = services()
	return guiService ~= nil and guiService.ReducedMotionEnabled == true
end
Theme.reducedMotion = reducedMotion

-- Tween when motion is allowed, otherwise snap to the end state.
function Theme.tween(object, seconds, props, style, direction)
	local tweenService = services()
	if reducedMotion() or not tweenService then
		for key, value in pairs(props) do object[key] = value end
		return nil
	end
	local tween = tweenService:Create(object, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	tween:Play()
	return tween
end

function Theme.setButtonStyle(button, styleName)
	local style = Theme.buttonStyles[styleName]
	if not style then return end
	button:SetAttribute("ThemeStyle", styleName)
	button.TextColor3 = style.text
	local face, lip = button:FindFirstChild("Face"), button:FindFirstChild("Lip")
	if face then
		face.BackgroundColor3 = style.face
		local label = face:FindFirstChild("Label")
		if label then
			label.TextColor3 = style.text
			local textStroke = label:FindFirstChild("TextStroke")
			if textStroke then
				textStroke.Color = style.textStroke or style.face
				textStroke.Transparency = style.textStroke and 0 or 1
			end
		end
	end
	if lip then
		lip.BackgroundColor3 = style.lip
		local outline = lip:FindFirstChild("Outline")
		if outline then outline.Color = style.outline end
	end
end

-- options: primary, danger, style ("primary"|"danger"|"wood"|"washi"|"ramune"), size (UDim2), order, textSize,
--          radius (px), align (TextXAlignment), iconSpace (px reserved left of the text for an icon)
-- The TextButton itself keeps Text / TextColor3 (other scripts read and write them); its own glyphs are hidden
-- and mirrored onto Face.Label so the face can be drawn above the lip.
function Theme.button(parent, name, text, onClick, options)
	options = options or {}
	local styleName = options.style or (options.primary and "primary") or (options.danger and "danger") or "wood"
	local style = Theme.buttonStyles[styleName] or Theme.buttonStyles.wood
	local radius = options.radius or 12
	local textSize = options.textSize or 18
	local iconSpace = options.iconSpace or 0

	local button = create("TextButton", {Name = name, Text = text, TextSize = textSize, FontFace = Theme.faces.bold,
		TextColor3 = style.text, TextTransparency = 1, BackgroundTransparency = 1, AutoButtonColor = false, BorderSizePixel = 0,
		Size = options.size or UDim2.new(1, 0, 0, 48), LayoutOrder = options.order or 0, Selectable = true, Parent = parent})

	local lip = create("Frame", {Name = "Lip", Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = style.lip,
		BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 1, Parent = button})
	Theme.corner(lip, radius)
	Theme.stroke(lip, style.outline, 2).Name = "Outline"

	local face = create("Frame", {Name = "Face", Size = UDim2.new(1, 0, 1, -LIP), Position = UDim2.new(0, 0, 0, 0),
		BackgroundColor3 = style.face, BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 2, Parent = button})
	Theme.corner(face, radius)
	local shine = create("Frame", {Name = "Shine", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 3),
		Size = UDim2.new(1, -10, 0.42, 0), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.8,
		BorderSizePixel = 0, ZIndex = 1, Parent = face})
	Theme.corner(shine, math.max(radius - 3, 2))

	local label = create("TextLabel", {Name = "Label", Text = text, TextSize = textSize, FontFace = Theme.faces.bold,
		TextColor3 = style.text, BackgroundTransparency = 1, BorderSizePixel = 0, TextWrapped = true,
		TextXAlignment = options.align or Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
		Position = UDim2.new(0, 10 + iconSpace, 0, 0), Size = UDim2.new(1, -(20 + iconSpace), 1, 0), ZIndex = 5, Parent = face})
	Theme.textStroke(label, style.textStroke or style.face, 2, style.textStroke and 0 or 1)

	button:SetAttribute("ThemeStyle", styleName)
	button:GetPropertyChangedSignal("Text"):Connect(function() label.Text = button.Text end)
	button:GetPropertyChangedSignal("TextColor3"):Connect(function() label.TextColor3 = button.TextColor3 end)

	local hovered, pressed = false, false
	local function currentStyle()
		return Theme.buttonStyles[button:GetAttribute("ThemeStyle")] or style
	end
	local function refresh()
		local s = currentStyle()
		face.BackgroundColor3 = hovered and s.face:Lerp(Color3.new(1, 1, 1), 0.12) or s.face
		Theme.tween(face, 0.07, {Position = UDim2.new(0, 0, 0, pressed and PRESS or 0)})
	end
	button.MouseEnter:Connect(function() hovered = true; refresh() end)
	button.MouseLeave:Connect(function() hovered = false; pressed = false; refresh() end)
	button.InputBegan:Connect(function(input)
		local kind = input and input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then pressed = true; refresh() end
	end)
	button.InputEnded:Connect(function(input)
		local kind = input and input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then pressed = false; refresh() end
	end)
	-- Gamepad / keyboard focus: a thick gold rim instead of the default grey box.
	button.SelectionImageObject = create("Frame", {Name = "NoSelectionBox", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1)})
	local outline = lip:FindFirstChild("Outline")
	button.SelectionGained:Connect(function() outline.Color = P.gold; outline.Thickness = 4 end)
	button.SelectionLost:Connect(function() outline.Color = currentStyle().outline; outline.Thickness = 2 end)
	button.Activated:Connect(function() onClick(button) end)
	return button
end

return Theme
