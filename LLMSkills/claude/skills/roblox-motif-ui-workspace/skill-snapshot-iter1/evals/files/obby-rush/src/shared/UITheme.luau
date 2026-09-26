-- UI theme shared by every screen.
local Theme = {}

Theme.colors = {
	background = Color3.fromRGB(11, 20, 38),
	panel = Color3.fromRGB(19, 35, 63),
	panelLight = Color3.fromRGB(28, 50, 86),
	accent = Color3.fromRGB(63, 169, 245),
	text = Color3.fromRGB(230, 240, 255),
	subtext = Color3.fromRGB(140, 160, 190),
	danger = Color3.fromRGB(229, 72, 77),
	success = Color3.fromRGB(48, 164, 108),
}

Theme.font = Enum.Font.GothamMedium
Theme.fontBold = Enum.Font.GothamBold

local function create(className, props)
	local object = Instance.new(className)
	for key, value in pairs(props) do
		if key ~= "Parent" then object[key] = value end
	end
	object.Parent = props.Parent
	return object
end
Theme.create = create

function Theme.corner(object, radius)
	return create("UICorner", {CornerRadius = UDim.new(0, radius or 8), Parent = object})
end

function Theme.stroke(object)
	return create("UIStroke", {Color = Theme.colors.accent, Thickness = 1, Transparency = 0.6,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = object})
end

function Theme.panel(parent, name, size, position)
	local frame = create("Frame", {Name = name, Size = size, Position = position or UDim2.new(),
		BackgroundColor3 = Theme.colors.panel, BackgroundTransparency = 0.1, BorderSizePixel = 0, Parent = parent})
	Theme.corner(frame, 10)
	Theme.stroke(frame)
	return frame
end

function Theme.label(parent, name, text, size, options)
	options = options or {}
	return create("TextLabel", {Name = name, Text = text, TextSize = size or 16, Font = options.bold and Theme.fontBold or Theme.font,
		TextColor3 = options.color or Theme.colors.text, BackgroundTransparency = 1, Size = options.frameSize or UDim2.new(1, 0, 0, (size or 16) + 8),
		TextXAlignment = options.align or Enum.TextXAlignment.Left, TextWrapped = true, Parent = parent})
end

-- options: primary, danger, size (UDim2), order, textSize
function Theme.button(parent, name, text, onClick, options)
	options = options or {}
	local base = options.primary and Theme.colors.accent or options.danger and Theme.colors.danger or Theme.colors.panelLight
	local button = create("TextButton", {Name = name, Text = text, TextSize = options.textSize or 18, Font = Theme.fontBold,
		TextColor3 = Theme.colors.text, BackgroundColor3 = base, AutoButtonColor = false, BorderSizePixel = 0,
		Size = options.size or UDim2.new(1, 0, 0, 48), LayoutOrder = options.order or 0, Parent = parent})
	Theme.corner(button, 8)
	Theme.stroke(button)
	button.MouseEnter:Connect(function() button.BackgroundColor3 = base:Lerp(Color3.new(1, 1, 1), 0.08) end)
	button.MouseLeave:Connect(function() button.BackgroundColor3 = base end)
	button.Activated:Connect(function() onClick(button) end)
	return button
end

return Theme
