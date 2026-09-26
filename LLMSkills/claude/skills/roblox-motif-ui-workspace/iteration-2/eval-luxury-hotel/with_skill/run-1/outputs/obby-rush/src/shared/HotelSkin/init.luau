-- Grand Hotel skin for UITheme: black marble, opaque hairline gold double rules, engraved captions.
--
-- Runtime adapter (applied once by UITheme): rewrites Theme.colors in place and wraps the builders
-- (corner, stroke, panel, label, button, hover). The wrapped builders let the originals create the
-- instance first, then change presentation only: Name, Parent, Size, callbacks and enabled logic
-- stay exactly as the original theme made them (tests/test_main_menu.luau pins them).
-- Every step is pcall-guarded: a failure leaves the original look instead of a missing screen.
local Kit = require(script:WaitForChild("MotifSkinKit"))
local spec = require(script:WaitForChild("MotifSpec"))
local kit = Kit.new(spec)
local P = kit.P
local O = require(script:WaitForChild("Ornaments"))(kit)

local Skin = {kit = kit, P = P, O = O}

-- Button presentation state, keyed weakly by the button.
local states = setmetatable({}, {__mode = "k"})
Skin.states = states

-- Role by instance name (exact, then the prefix before "_").
local NAME_ROLES = {Nav = "plaque", Toggle = "ghost", CloseButton = "ghost", PlayButton = "cta"}
local function roleFor(name, options)
	options = options or {}
	if NAME_ROLES[name] then return NAME_ROLES[name] end
	local prefix = string.match(name or "", "^([^_]+)_")
	if prefix and NAME_ROLES[prefix] then return NAME_ROLES[prefix] end
	if options.primary then return "reserve" end
	if options.danger then return "danger" end
	return "ghost"
end
Skin.roleFor = roleFor

-- Faces per role and state. No squash, no gloss, no lip: a lit brass plate only brightens.
function Skin.paint(button)
	local state = states[button]
	if not state then return end
	pcall(function()
		local enabled = button.Active ~= false
		local lit = enabled and (state.hover or state.pressed)
		local edge = button:FindFirstChild("HotelEdge")
		local rule = button:FindFirstChild("HotelRule")
		local ruleLine = rule and rule:FindFirstChild("HotelRuleLine")
		local role = state.role
		local face, faceT, text, edgeColor, ruleColor = P.plaque, 0, P.ink, P.gold, P.goldDeep
		if not enabled then
			face, faceT, text, edgeColor = P.disabled, 0, P.muted, P.goldDeep
		elseif role == "cta" then
			-- Brass elevator doors: the only solid gold on the lobby screen.
			face = state.pressed and P.gold or (lit and P.primary:Lerp(P.goldLight, 0.3) or P.primary)
			text, edgeColor, ruleColor = P.onLight, P.goldLight, P.goldDeep
		elseif role == "reserve" then
			-- Menu-card action: an outlined brass plate that fills when touched.
			face, faceT = P.primary, lit and 0 or 1
			text, edgeColor = lit and P.onLight or P.primary, lit and P.goldLight or P.gold
		elseif role == "plaque" then
			-- Hotel directory plaque: black lacquer, gold double rule; the open page's plaque is lit.
			face = (lit or state.selected) and P.quiet or P.plaque
			text = state.selected and P.goldLight or P.ink
			edgeColor = (lit or state.selected) and P.goldLight or P.gold
			ruleColor = state.selected and P.gold or P.goldDeep
		elseif role == "danger" then
			face = lit and P.danger:Lerp(P.white, 0.08) or P.danger
			text, edgeColor = P.white, P.gold
		else -- ghost: close, settings rows
			face, faceT = P.gold, lit and 0.86 or 1
			text = P.ink
		end
		button.BackgroundColor3, button.BackgroundTransparency, button.TextColor3 = face, faceT, text
		if edge then edge.Color = edgeColor end
		if ruleLine then ruleLine.Color = ruleColor end
	end)
end

function Skin.select(button, selected)
	local state = states[button]
	if state and state.selected ~= selected then
		state.selected = selected
		Skin.paint(button)
	end
end

-- Style one button built by the original Theme.button.
function Skin.styleButton(button, options)
	options = options or {}
	local role = roleFor(button.Name, options)
	states[button] = {role = role, hover = false, pressed = false, selected = false}
	pcall(function()
		button.AutoButtonColor = false
		O.corner(button)
		O.stroke(button, P.gold, 1)
		kit:setFont(button, role == "cta" and "strong" or "button")
		if role == "cta" then
			O.rule(button, 6, P.goldDeep)
		elseif role == "plaque" then
			O.rule(button, 4, P.goldDeep)
		end
	end)
	pcall(function()
		button.InputBegan:Connect(function(input)
			local kind = input.UserInputType
			if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
				states[button].pressed = true
				Skin.paint(button)
			end
		end)
		button.InputEnded:Connect(function(input)
			local kind = input.UserInputType
			if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
				states[button].pressed = false
				Skin.paint(button)
			end
		end)
		button:GetPropertyChangedSignal("Active"):Connect(function() Skin.paint(button) end)
	end)
	Skin.paint(button)
	return button
end

-- "1,250": ledger digits for the coin token (the coin emoji draws as tofu in Roblox).
function Skin.formatCoins(amount)
	local text = tostring(math.floor(tonumber(amount) or 0))
	local sign, digits = string.match(text, "^(%-?)(%d+)$")
	if not digits then return text end
	local grouped = string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")))
	grouped = string.gsub(grouped, "^,", "")
	return sign .. grouped
end

function Skin.apply(Theme)
	if type(Theme) ~= "table" or type(Theme.button) ~= "function" or type(Theme.colors) ~= "table" then
		return false
	end
	if Theme.skin == Skin then return true end -- idempotent: never wrap twice
	local original = {
		corner = Theme.corner, stroke = Theme.stroke, panel = Theme.panel, label = Theme.label,
		button = Theme.button, hover = Theme.hover,
	}

	-- 1) Colours in place: modules that already hold Theme.colors see the hotel palette.
	local C = Theme.colors
	C.background, C.panel, C.panelLight = P.paper, P.panel, P.plaque
	C.accent, C.text, C.subtext = P.primary, P.ink, P.muted
	C.danger, C.success = P.danger, P.success

	-- 2) Shape: near-square corners, opaque gold hairlines.
	Theme.corner = function(object, radius)
		local corner = original.corner(object, radius)
		pcall(function() corner.CornerRadius = UDim.new(0, kit.shape.corner or 2) end)
		return corner
	end
	Theme.stroke = function(object)
		local stroke = original.stroke(object)
		pcall(function()
			stroke.Name = "HotelEdge"
			stroke.Color, stroke.Thickness, stroke.Transparency = P.gold, 1, 0
		end)
		return stroke
	end

	-- 3) Panels by name: the top bar is a cornice, pages are framed marble, shop rows are menu lines.
	Theme.panel = function(parent, name, size, position)
		local frame = original.panel(parent, name, size, position)
		pcall(function()
			frame.BackgroundTransparency = 0
			local edge = frame:FindFirstChild("HotelEdge")
			if name == "TopBar" then
				frame.BackgroundTransparency = 1
				if edge then edge.Transparency = 1 end
			elseif string.match(name or "", "^Product_") then
				frame.BackgroundTransparency = 1
				if edge then edge.Transparency = 1 end
				O.frame(frame, {
					Name = "HotelRowRule", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1),
					Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = P.goldDeep,
				})
			else
				frame.BackgroundColor3 = P.panel
				O.rule(frame, 6, P.goldDeep)
				O.cornerDiamonds(frame, 6, 7, P.gold)
			end
		end)
		return frame
	end

	Theme.label = function(parent, name, text, size, options)
		local label = original.label(parent, name, text, size, options)
		pcall(function() kit:setFont(label, options and options.bold and "strong" or "body") end)
		return label
	end

	Theme.button = function(parent, name, text, onClick, options)
		local button = original.button(parent, name, text, onClick, options)
		pcall(Skin.styleButton, button, options)
		return button
	end

	-- Hover goes through the painter (the original lerps the face toward white).
	Theme.hover = function(button, base, hovered)
		local state = states[button]
		if not state then
			if original.hover then return original.hover(button, base, hovered) end
			return
		end
		state.hover = hovered == true
		Skin.paint(button)
	end

	Theme.formatCoins = Skin.formatCoins
	Theme.skin = Skin
	return true
end

-- The lobby scene for the main menu (decorative children only).
function Skin.decorateMainMenu(gui)
	local Lobby = require(script:WaitForChild("Lobby"))
	return Lobby.decorate(Skin, gui)
end

return Skin
