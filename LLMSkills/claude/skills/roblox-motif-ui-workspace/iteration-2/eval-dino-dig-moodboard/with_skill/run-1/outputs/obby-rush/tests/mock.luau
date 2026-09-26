--!nocheck
-- Minimal Roblox GUI mock used by test_main_menu.luau (no rendering, no layout engine).
-- Instances: properties are plain fields; children, FindFirstChild(WhichIsA/OfClass), IsA with the
-- common GUI class tree, attributes, Get(Property|Attribute)ChangedSignal, Destroy/Destroying and
-- GUI input signals the test can :Fire(...) (Activated, MouseEnter, InputBegan...).
-- Unset properties read as nil. Vector2 / UDim2 / Color3 come from @lune/roblox (float32 inside).
local rb = require("@lune/roblox")

local Mock = {}

function Mock.signal()
	local s = {listeners = {}}
	function s:Connect(fn)
		local connection = {Connected = true}
		function connection:Disconnect() connection.Connected = false end
		table.insert(self.listeners, {connection = connection, fn = fn})
		return connection
	end
	function s:Fire(...)
		for _, entry in ipairs(table.clone(self.listeners)) do
			if entry.connection.Connected then entry.fn(...) end
		end
	end
	function s:Wait() end
	return s
end
local signal = Mock.signal

local BASES = {
	TextButton = {GuiButton = true, GuiObject = true, GuiBase2d = true},
	ImageButton = {GuiButton = true, GuiObject = true, GuiBase2d = true},
	TextLabel = {GuiObject = true, GuiBase2d = true}, TextBox = {GuiObject = true, GuiBase2d = true},
	ImageLabel = {GuiObject = true, GuiBase2d = true}, Frame = {GuiObject = true, GuiBase2d = true},
	ScrollingFrame = {GuiObject = true, GuiBase2d = true}, ViewportFrame = {GuiObject = true, GuiBase2d = true},
	CanvasGroup = {GuiObject = true, GuiBase2d = true},
	ScreenGui = {LayerCollector = true, GuiBase2d = true}, BillboardGui = {LayerCollector = true}, SurfaceGui = {LayerCollector = true},
	UIListLayout = {UIGridStyleLayout = true, UILayout = true}, UIGridLayout = {UIGridStyleLayout = true, UILayout = true},
	Script = {BaseScript = true, LuaSourceContainer = true}, LocalScript = {BaseScript = true, Script = true, LuaSourceContainer = true},
	ModuleScript = {LuaSourceContainer = true},
}
local SIGNALS = {"Activated", "MouseButton1Click", "Destroying", "MouseEnter", "MouseLeave", "InputBegan", "InputEnded",
	"SelectionGained", "SelectionLost", "FocusLost", "ChildAdded", "ChildRemoved"}
local GUI = {TextButton = true, TextLabel = true, TextBox = true, Frame = true, ImageLabel = true, ImageButton = true,
	ScrollingFrame = true, ViewportFrame = true, CanvasGroup = true}

-- Mock.node(className, props): one instance. Pass AbsoluteSize for layout-dependent code.
function Mock.node(className, props)
	local data = {ClassName = className, Name = className}
	if GUI[className] then
		data.Visible, data.Active, data.Selectable, data.ZIndex, data.Rotation = true, className ~= "Frame", className == "TextButton" or className == "ImageButton", 1, 0
		data.AbsoluteSize, data.AbsolutePosition = rb.Vector2.new(200, 50), rb.Vector2.new(0, 0)
		data.AnchorPoint, data.Size, data.Position = rb.Vector2.new(0, 0), rb.UDim2.new(0, 200, 0, 50), rb.UDim2.new()
		data.BackgroundColor3, data.BackgroundTransparency, data.BorderSizePixel = rb.Color3.new(1, 1, 1), 0, 1
		if className ~= "Frame" and className ~= "ScrollingFrame" and className ~= "ViewportFrame" and className ~= "CanvasGroup"
			and className ~= "ImageLabel" and className ~= "ImageButton" then
			data.Text, data.TextSize, data.TextColor3, data.TextScaled, data.TextWrapped = "", 14, rb.Color3.new(0, 0, 0), false, false
			data.TextTransparency, data.TextFits = 0, true
		end
	elseif className == "ScreenGui" then
		data.Enabled = true
	elseif className == "UIListLayout" or className == "UIGridLayout" then
		data.Padding = rb.UDim.new(0, 0)
	end
	local children, attributes, attributeSignals, propertySignals, signals = {}, {}, {}, {}, {}
	for _, name in ipairs(SIGNALS) do signals[name] = signal() end
	local object, methods = {}, {}
	function methods:GetChildren() return table.clone(children) end
	function methods:FindFirstChild(name, recursive)
		for _, child in ipairs(children) do if child.Name == name then return child end end
		if recursive then
			for _, child in ipairs(children) do
				local found = child:FindFirstChild(name, true)
				if found then return found end
			end
		end
		return nil
	end
	function methods:WaitForChild(name) return object:FindFirstChild(name) end
	function methods:FindFirstChildOfClass(class)
		for _, child in ipairs(children) do if child.ClassName == class then return child end end
		return nil
	end
	function methods:IsA(class) return class == "Instance" or class == data.ClassName or (BASES[data.ClassName] or {})[class] == true end
	function methods:FindFirstChildWhichIsA(class, recursive)
		for _, child in ipairs(children) do if child:IsA(class) then return child end end
		if recursive then
			for _, child in ipairs(children) do
				local found = child:FindFirstChildWhichIsA(class, true)
				if found then return found end
			end
		end
		return nil
	end
	function methods:FindFirstAncestor(name)
		local parent = data.Parent
		while parent do
			if parent.Name == name then return parent end
			parent = parent.Parent
		end
		return nil
	end
	function methods:IsDescendantOf(root)
		local parent = data.Parent
		while parent do
			if parent == root then return true end
			parent = parent.Parent
		end
		return false
	end
	function methods:GetDescendants()
		local result = {}
		local function add(item)
			for _, child in ipairs(item:GetChildren()) do table.insert(result, child); add(child) end
		end
		add(object)
		return result
	end
	function methods:GetFullName()
		local parts, node = {}, object
		while node do table.insert(parts, 1, node.Name); node = node.Parent end
		return table.concat(parts, ".")
	end
	function methods:SetAttribute(name, value)
		local old = attributes[name]
		attributes[name] = value
		if old ~= value and attributeSignals[name] then attributeSignals[name]:Fire() end
	end
	function methods:GetAttribute(name) return attributes[name] end
	function methods:GetAttributes() return table.clone(attributes) end
	function methods:GetAttributeChangedSignal(name)
		attributeSignals[name] = attributeSignals[name] or signal()
		return attributeSignals[name]
	end
	function methods:GetPropertyChangedSignal(name)
		propertySignals[name] = propertySignals[name] or signal()
		return propertySignals[name]
	end
	function methods:Destroy()
		signals.Destroying:Fire()
		for _, child in ipairs(table.clone(children)) do child:Destroy() end
		object.Parent = nil
	end
	function methods:ClearAllChildren()
		for _, child in ipairs(table.clone(children)) do child:Destroy() end
	end
	function methods:Clone()
		local copy = Mock.node(data.ClassName)
		for key, value in pairs(data) do if key ~= "Parent" then copy[key] = value end end
		for _, child in ipairs(children) do child:Clone().Parent = copy end
		return copy
	end
	setmetatable(object, {
		__index = function(_, key)
			if methods[key] then return methods[key] end
			if signals[key] then return signals[key] end
			if key == "__children" then return children end
			local value = data[key]
			if value == nil and type(key) == "string" then return object:FindFirstChild(key) end
			return value
		end,
		__newindex = function(_, key, value)
			if key == "Parent" then
				local old = data.Parent
				if old == value then return end
				if old then
					for index, child in ipairs(old.__children) do
						if child == object then table.remove(old.__children, index); break end
					end
					old.ChildRemoved:Fire(object)
				end
				data.Parent = value
				if value then table.insert(value.__children, object); value.ChildAdded:Fire(object) end
				return
			end
			local old = data[key]
			data[key] = value
			if old ~= value and propertySignals[key] then propertySignals[key]:Fire() end
		end,
		__tostring = function() return "<" .. data.ClassName .. " " .. tostring(data.Name) .. ">" end,
	})
	for key, value in pairs(props or {}) do object[key] = value end
	return object
end

-- Tweens complete instantly (target values applied) so tests can assert end states.
function Mock.tweenService()
	local created = {}
	local service = {created = created}
	function service:Create(instance, info, props)
		local tween = {Completed = signal(), instance = instance, info = info, props = props, cancelled = false, played = false}
		function tween:Play()
			self.played = true
			for key, value in pairs(props) do instance[key] = value end
			self.Completed:Fire(Enum and Enum.PlaybackState and Enum.PlaybackState.Completed)
		end
		function tween:Cancel() self.cancelled = true end
		function tween:Pause() end
		table.insert(created, tween)
		return tween
	end
	return service
end

-- Globals for luau.load. options: {services = {Name = table}, reducedMotion = bool, now = fn}
function Mock.environment(options)
	options = options or {}
	local services = options.services or {}
	services.TweenService = services.TweenService or Mock.tweenService()
	services.GuiService = services.GuiService or {ReducedMotionEnabled = options.reducedMotion == true, SelectedObject = nil}
	services.Players = services.Players or {LocalPlayer = {PlayerGui = Mock.node("PlayerGui"), UserId = 1}}
	services.UserInputService = services.UserInputService or {TouchEnabled = false, GetLastInputType = function() return rb.Enum.UserInputType.MouseMovement end}
	local fakeGame = {GetService = function(_, name) return services[name] end}
	return {
		game = fakeGame, workspace = {CurrentCamera = {ViewportSize = rb.Vector2.new(1280, 720)}},
		Instance = {new = function(className, parent) local n = Mock.node(className); if parent then n.Parent = parent end; return n end},
		Color3 = rb.Color3, UDim = rb.UDim, UDim2 = rb.UDim2, Vector2 = rb.Vector2, Vector3 = rb.Vector3, CFrame = rb.CFrame,
		Enum = rb.Enum, ColorSequence = rb.ColorSequence, ColorSequenceKeypoint = rb.ColorSequenceKeypoint,
		NumberSequence = rb.NumberSequence, NumberSequenceKeypoint = rb.NumberSequenceKeypoint, NumberRange = rb.NumberRange,
		TweenInfo = {new = function(...) return {...} end},
		Font = {new = function(family, weight) return {Family = family, Weight = weight} end,
			fromEnum = function(item) return {Family = "enum:" .. tostring(item), Weight = nil} end},
		typeof = function(value)
			local ok, kind = pcall(function() return typeof(value) end)
			return ok and kind or type(value)
		end,
		task = {spawn = function() end, defer = function() end, delay = function() end, wait = function() return 0 end},
		os = {clock = options.now or os.clock, time = os.time},
		math = math, string = string, table = table, pairs = pairs, ipairs = ipairs, pcall = pcall, error = error,
		print = print, warn = function() end, tostring = tostring, tonumber = tonumber, type = type, setmetatable = setmetatable,
		getmetatable = getmetatable, select = select, assert = assert, next = next, rawget = rawget, rawset = rawset,
		require = options.require or function(module) return module end,
	}
end

return Mock
