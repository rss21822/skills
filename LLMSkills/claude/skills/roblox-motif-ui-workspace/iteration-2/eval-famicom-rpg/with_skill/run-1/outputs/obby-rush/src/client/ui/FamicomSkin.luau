--!nocheck
-- Famicom-era RPG skin for the Obby Rush UI (client only, no image assets).
--
-- Motif (owner's words): 「ファミコン時代のRPGっぽく。黒い画面に白い枠のウィンドウ、▶のカーソル、ドット文字みたいな感じ」
--
--   Skin.apply(Theme)            repaints UITheme.colors in place and wraps Theme.corner / stroke / panel /
--                                label / button, so every screen built through UITheme becomes opaque black
--                                windows with a white pixel frame (notched corners) and text commands.
--   Skin.decorateMainMenu(gui)   lays the main menu out as a Famicom title screen (logo, stepping sprite,
--                                START window, command window, page titles set into the frame line).
--                                If anything fails, every change it made is reverted.
--
-- Contract: Name, Parent, attributes, callbacks and enabled logic of existing instances are never changed.
-- Only presentation properties change, and every added child is named "Motif...".
-- Motion is stepwise (a 1 Hz blinking cursor and a 2-frame stepping sprite on one 0.5 s tick); under reduced
-- motion the cursor stays lit and the sprite stands still.
local Kit = require(script.Parent:WaitForChild("MotifSkinKit"))
local spec = require(script.Parent:WaitForChild("FamicomSpec"))

local kit = Kit.new(spec)
local P = kit.P
local C = kit.candies
local DOT = (spec.shape and spec.shape.dot) or 4 -- one "Famicom pixel" of window chrome, in screen pixels
local create = Kit.create

local Skin = {kit = kit, P = P, DOT = DOT}

-- Famicom RPG wording: kana only, words separated by spaces, Latin/numbers for what the pixel font can draw.
-- MainMenu reads these with the original Japanese as fallback, so removing the skin restores the old copy.
Skin.copy = {
	play = "START",
	nav_Shop = "おみせ", nav_Inventory = "どうぐ", nav_Quests = "クエスト", nav_Settings = "せってい",
	page_Shop = "おみせ", page_Inventory = "どうぐ", page_Quests = "クエスト", page_Settings = "せってい",
	close = "とじる",
	buy = "かう",
	setting_music = "おんがく",
	setting_sfx = "こうかおん",
	empty_Inventory = "まだ なにも もっていない。",
	empty_Quests = "きょうの クエストは じゅんびちゅう。",
	-- 🪙 (Unicode 13) draws as a tofu box in Roblox; Famicom RPGs wrote gold as "G".
	coins = function(amount) return "G " .. tostring(amount) end,
	price = function(amount) return tostring(amount) .. "G" end,
}

local weak = {__mode = "k"}
local windows = setmetatable({}, weak) -- Frame -> true: drawn as a window
local commands = setmetatable({}, weak) -- GuiButton -> {role, framed, pressed, dot, wide, edges, cursor}
local texts = setmetatable({}, weak) -- text object -> {base = requested size, bold = bool}
local painting = setmetatable({}, weak)
local screens = setmetatable({}, weak) -- LayerCollector -> focus state
Skin._windows, Skin._commands, Skin._screens = windows, commands, screens

-- Text ------------------------------------------------------------------------------------------------
local function cjkCount(text)
	return select(2, string.gsub(text, "[\227-\237\239][\128-\191][\128-\191]", ""))
end
local function charCount(text)
	return select(2, string.gsub(text, "[^\128-\191]", ""))
end

-- Rough advance width (TextBounds is not available until the text renders).
function Skin.estimateWidth(text, size, pixel)
	text = tostring(text or "")
	local cjk = cjkCount(text)
	local other = charCount(text) - cjk
	return math.ceil((cjk + other * (pixel and 1 or 0.62)) * (size or 16))
end

local function textWidth(object)
	local ok, bounds = pcall(function() return object.TextBounds end)
	if ok and typeof(bounds) == "Vector2" and bounds.X > 0 then return bounds.X end
	return Skin.estimateWidth(object.Text, object.TextSize, not Kit.cjk(object.Text))
end

-- Latin and numbers use the pixel face (PressStart2P) on the 8 px grid it was drawn for. Japanese has no
-- pixel face in Roblox: it falls back to the system CJK font at the requested weight, so ask for Heavy/Bold.
local function face(object, bold)
	local info = texts[object]
	if not info then
		info = {base = object.TextSize or 16, bold = bold == true}
		texts[object] = info
	end
	if Kit.cjk(object.Text) then
		kit:setFont(object, info.bold and "title" or "body")
		object.TextSize = info.base
	else
		kit:setFont(object, "display")
		object.TextSize = math.max(8, math.floor(info.base / 8 + 0.5) * 8)
	end
end
Skin.face = face

-- Surfaces ----------------------------------------------------------------------------------------------
local SIDES = {"Top", "Bottom", "Left", "Right"}

-- White pixel frame: four edge bars that stop one dot short of each corner, so every corner is a notched
-- pixel curve like the NES window tiles (no UICorner, no UIStroke).
function Skin.pixelFrame(frame, color, thickness, notch)
	local t, n = thickness or DOT, notch or DOT
	local geometry = {
		Top = {UDim2.new(0, n, 0, 0), UDim2.new(1, -2 * n, 0, t)},
		Bottom = {UDim2.new(0, n, 1, -t), UDim2.new(1, -2 * n, 0, t)},
		Left = {UDim2.new(0, 0, 0, n), UDim2.new(0, t, 1, -2 * n)},
		Right = {UDim2.new(1, -t, 0, n), UDim2.new(0, t, 1, -2 * n)},
	}
	local edges = {}
	for _, side in ipairs(SIDES) do
		local edge = frame:FindFirstChild("MotifEdge" .. side) or create("Frame", frame, {Name = "MotifEdge" .. side})
		edge.BorderSizePixel, edge.BackgroundTransparency, edge.Active = 0, 0, false
		edge.BackgroundColor3 = color or P.ink
		edge.Position, edge.Size = geometry[side][1], geometry[side][2]
		edge.ZIndex = frame.ZIndex
		edge.Visible = true
		edges[side] = edge
	end
	return edges
end

local function hideStrokes(object)
	for _, child in ipairs(object:GetChildren()) do
		if child.ClassName == "UIStroke" then
			child.Transparency = 1
			pcall(function() child.Enabled = false end)
		end
	end
end

local function square(object)
	local corner = object:FindFirstChildOfClass("UICorner")
	if corner then corner.CornerRadius = UDim.new(0, 0) end
end

local function insideWindow(object)
	local node = object
	while node do
		if windows[node] then return true end
		node = node.Parent
	end
	return false
end
Skin.insideWindow = insideWindow

function Skin.window(frame)
	windows[frame] = true
	frame.BackgroundColor3, frame.BackgroundTransparency, frame.BorderSizePixel = P.paper, 0, 0
	square(frame)
	hideStrokes(frame)
	Skin.pixelFrame(frame, P.ink)
	return frame
end

-- A panel inside a window is a line of that window, not a window of its own (windows never nest).
function Skin.line(frame)
	frame.BackgroundTransparency, frame.BorderSizePixel = 1, 0
	square(frame)
	hideStrokes(frame)
	return frame
end

function Skin.surface(frame)
	if frame.Parent and insideWindow(frame.Parent) then return Skin.line(frame) end
	return Skin.window(frame)
end

-- Pixel ▶ cursor: four columns 7-5-3-1 dots tall. Drawn with frames so it never becomes a colour emoji and
-- its dot matches the pixel size of the text next to it.
local CURSOR = {7, 5, 3, 1}
function Skin.cursor(parent, dot, color)
	local holder = parent:FindFirstChild("MotifCursor") or create("Frame", parent, {Name = "MotifCursor"})
	holder.BackgroundTransparency, holder.BorderSizePixel, holder.Active = 1, 0, false
	holder.AnchorPoint = Vector2.new(0, 0) -- whole-pixel placement: no half-pixel fringe on odd heights
	holder.Size = UDim2.fromOffset(4 * dot, 7 * dot)
	holder.ZIndex = parent.ZIndex
	for index, height in ipairs(CURSOR) do
		local column = holder:FindFirstChild("Column" .. index) or create("Frame", holder, {Name = "Column" .. index})
		column.BorderSizePixel, column.Active = 0, false
		column.BackgroundColor3 = color or P.ink
		column.Position = UDim2.fromOffset((index - 1) * dot, (7 - height) / 2 * dot)
		column.Size = UDim2.fromOffset(dot, height * dot)
		column.ZIndex = parent.ZIndex
	end
	return holder
end

-- Pixel art from rows of palette letters ("." = the black screen). Each run of one colour is one Frame, and
-- everything is placed in scale so the art follows the holder's size.
function Skin.pixelArt(parent, name, rows, colors, props)
	local height, width = #rows, 0
	for _, row in ipairs(rows) do width = math.max(width, #row) end
	local art = create("Frame", parent, {Name = name, BackgroundTransparency = 1, BorderSizePixel = 0, Active = false})
	for key, value in pairs(props or {}) do art[key] = value end
	for y, row in ipairs(rows) do
		local x = 1
		while x <= #row do
			local letter = string.sub(row, x, x)
			local run = 1
			while string.sub(row, x + run, x + run) == letter do run += 1 end
			if letter ~= "." and colors[letter] then
				create("Frame", art, {
					Name = "Px", BorderSizePixel = 0, Active = false, BackgroundColor3 = colors[letter], ZIndex = art.ZIndex,
					Position = UDim2.fromScale((x - 1) / width, (y - 1) / height), Size = UDim2.fromScale(run / width, 1 / height),
				})
			end
			x += run
		end
	end
	return art, width, height
end

-- Commands (buttons) --------------------------------------------------------------------------------------
local blank = create("Frame", nil, {Name = "MotifNoSelectionImage", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1)})

-- Cursor dot: the pixel size of the pixel font next to it (TextSize / 8), or 3-4 px beside Japanese so the
-- ▶ stays about one character tall.
local function cursorDot(object)
	local size = object.TextSize or 18
	if Kit.cjk(object.Text) then return math.clamp(math.floor(size / 6.5 + 0.5), 3, 4) end
	return math.max(2, math.floor(size / 8 + 0.5))
end

local function enabled(button)
	return button.Active ~= false
end

function Skin.placeCursor(button)
	local st = commands[button]
	if not st or not st.cursor then return end
	local d = st.dot
	local w = 4 * d
	local up = -math.floor(7 * d / 2)
	if st.wide then
		-- Left-aligned line: the cursor sits in the UIPadding slot in front of the text.
		local pad = button:FindFirstChild("MotifPadding")
		if pad then pad.PaddingLeft = UDim.new(0, w + 2 * d + 12) end
		st.cursor.Position = UDim2.new(0, -(w + 2 * d), 0.5, up)
	else
		local x = -textWidth(button) / 2 - 2 * d - w
		local size = button.Size
		if size and size.X.Scale == 0 and size.X.Offset / 2 + x < d then x = d - size.X.Offset / 2 end
		st.cursor.Position = UDim2.new(0.5, math.floor(x), 0.5, up)
	end
end

-- Colours from role and state. Idle: black face (opaque when framed, see-through inside a window), text in
-- the role colour. Pressed: inverted (role colour face, black text). Disabled: grey text and frame.
function Skin.paint(button)
	local st = commands[button]
	if not st then return end
	painting[button] = true
	pcall(function()
		local on = enabled(button)
		local accent = st.role == "primary" and P.primary or st.role == "danger" and P.danger or P.ink
		local ink = on and accent or P.disabled
		local pressed = on and st.pressed
		if pressed then
			button.BackgroundColor3, button.BackgroundTransparency, button.TextColor3 = accent, 0, P.onLight
		else
			button.BackgroundColor3, button.BackgroundTransparency, button.TextColor3 = P.paper, st.framed and 0 or 1, ink
		end
		for _, edge in pairs(st.edges or {}) do
			edge.Visible = st.framed == true
			edge.BackgroundColor3 = on and P.ink or P.disabled
		end
		if st.cursor then
			-- The ▶ is the system cursor, not part of the label: always white (grey when disabled).
			local mark = pressed and P.onLight or (on and P.ink or P.disabled)
			for _, column in ipairs(st.cursor:GetChildren()) do column.BackgroundColor3 = mark end
		end
	end)
	painting[button] = nil
end

-- Focus: one blinking cursor per screen. Order: hovered/selected command > first command of an open page >
-- the screen's default (the main menu's START).
local function screenOf(object)
	local node = object
	while node do
		if node:IsA("LayerCollector") then return node end
		node = node.Parent
	end
	return nil
end

local function shown(object, root)
	local node = object
	while node and node ~= root do
		if node:IsA("GuiObject") and node.Visible == false then return false end
		node = node.Parent
	end
	return node == root
end

function Skin.step(screen)
	local s = screens[screen]
	if not s then return end
	s.tick += 1
	local calm = kit:reduceMotion()
	local st = s.shown and commands[s.shown]
	if st and st.cursor then
		s.blinkOn = calm or not s.blinkOn
		st.cursor.Visible = s.blinkOn
	end
	for _, ticker in ipairs(s.tickers) do pcall(ticker, calm and 0 or s.tick) end
end

local function startLoop(screen)
	pcall(function()
		task.spawn(function()
			while screen.Parent do
				task.wait(0.5)
				if screen.Parent and screen.Enabled ~= false then Skin.step(screen) end
			end
		end)
	end)
end

local function stateFor(screen)
	local s = screens[screen]
	if not s then
		s = {hover = nil, default = nil, pages = {}, marks = {}, shown = nil, blinkOn = true, tick = 0, tickers = {}}
		screens[screen] = s
		startLoop(screen)
	end
	return s
end
Skin.stateFor = stateFor

function Skin.pageDefault(page)
	local close
	for _, object in ipairs(page:GetDescendants()) do
		if commands[object] and enabled(object) then
			if object.Name == "CloseButton" then
				close = close or object
			else
				return object
			end
		end
	end
	return close
end

local function target(screen, s)
	if s.hover and commands[s.hover] and enabled(s.hover) and shown(s.hover, screen) then return s.hover end
	for _, page in ipairs(s.pages) do
		if page.Parent and page.Visible then
			local pick = Skin.pageDefault(page)
			if pick then return pick end
		end
	end
	if s.default and commands[s.default] and enabled(s.default) and shown(s.default, screen) then return s.default end
	return nil
end

function Skin.focus(screen)
	local s = stateFor(screen)
	local pick = target(screen, s)
	if s.shown ~= pick then
		local old = s.shown and commands[s.shown]
		if old and old.cursor then old.cursor.Visible = false end
		s.shown = pick
		s.blinkOn = true
	end
	-- The command that opened a window keeps a steady ▶ while that window is open (only the active one blinks).
	for page, chosen in pairs(s.marks or {}) do
		local mark = commands[chosen]
		if mark and mark.cursor and chosen ~= pick then
			if page.Parent ~= nil and page.Visible == true then Skin.placeCursor(chosen) end
			mark.cursor.Visible = page.Parent ~= nil and page.Visible == true
		end
	end
	local st = pick and commands[pick]
	if st and st.cursor then
		Skin.placeCursor(pick)
		st.cursor.Visible = s.blinkOn or kit:reduceMotion()
	end
	return pick
end

function Skin.hover(button, on)
	local screen = screenOf(button)
	if not screen then return end
	local s = stateFor(screen)
	if on then
		s.hover = button
	elseif s.hover == button then
		s.hover = nil
	end
	Skin.focus(screen)
end

local function isPress(input)
	return input ~= nil and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch)
end

local function hook(button)
	local function on(signal, fn) pcall(function() button[signal]:Connect(fn) end) end
	local function changed(prop, fn) pcall(function() button:GetPropertyChangedSignal(prop):Connect(fn) end) end
	on("MouseEnter", function() Skin.hover(button, true) end)
	on("MouseLeave", function()
		local st = commands[button]
		if st then st.pressed = false end
		Skin.paint(button)
		Skin.hover(button, false)
	end)
	on("SelectionGained", function() Skin.hover(button, true) end)
	on("SelectionLost", function() Skin.hover(button, false) end)
	on("InputBegan", function(input)
		if isPress(input) and enabled(button) then
			commands[button].pressed = true
			Skin.paint(button)
			Skin.hover(button, true) -- touch has no hover: the cursor jumps to what was tapped
		end
	end)
	on("InputEnded", function(input)
		if isPress(input) then
			commands[button].pressed = false
			Skin.paint(button)
		end
	end)
	changed("Active", function()
		Skin.paint(button)
		local screen = screenOf(button)
		if screen then Skin.focus(screen) end
	end)
	changed("Text", function()
		face(button, true)
		local st = commands[button]
		if st and st.cursor and cursorDot(button) ~= st.dot then
			st.dot = cursorDot(button)
			Skin.cursor(button, st.dot, P.ink)
			Skin.paint(button)
		end
		Skin.placeCursor(button)
	end)
	changed("TextBounds", function() Skin.placeCursor(button) end)
	-- UITheme's own hover handler repaints BackgroundColor3; put the window colours back.
	changed("BackgroundColor3", function()
		if not painting[button] then Skin.paint(button) end
	end)
end

-- options: role = "primary" | "danger" | "plain"; framed = boolean (default: framed unless inside a window)
function Skin.command(button, options)
	options = options or {}
	local st = commands[button]
	if not st then
		st = {}
		commands[button] = st
	end
	st.role = options.role or st.role or "plain"
	st.pressed = false
	st.framed = options.framed
	if st.framed == nil then st.framed = not (button.Parent ~= nil and insideWindow(button.Parent)) end
	button.AutoButtonColor, button.BorderSizePixel = false, 0
	square(button)
	hideStrokes(button)
	face(button, true)
	st.dot = cursorDot(button)
	local size = button.Size
	st.wide = size ~= nil and size.X.Scale > 0
	if st.wide then
		button.TextXAlignment = Enum.TextXAlignment.Left
		local pad = button:FindFirstChild("MotifPadding") or create("UIPadding", button, {Name = "MotifPadding"})
		pad.PaddingLeft = UDim.new(0, 6 * st.dot + 12)
	else
		button.TextXAlignment = Enum.TextXAlignment.Center
	end
	st.edges = Skin.pixelFrame(button, P.ink)
	st.cursor = Skin.cursor(button, st.dot, P.ink)
	st.cursor.Visible = false
	pcall(function() button.SelectionImageObject = blank end)
	Skin.placeCursor(button)
	Skin.paint(button)
	if not st.hooked then
		st.hooked = true
		hook(button)
	end
	return st
end

function Skin.text(object, options)
	options = options or {}
	face(object, options.bold)
	if texts[object] and not texts[object].hooked then
		texts[object].hooked = true
		pcall(function()
			object:GetPropertyChangedSignal("Text"):Connect(function() face(object, texts[object].bold) end)
		end)
	end
	return object
end

-- Theme adapter ---------------------------------------------------------------------------------------------
function Skin.apply(Theme)
	if type(Theme) ~= "table" or type(Theme.button) ~= "function" or type(Theme.panel) ~= "function"
		or type(Theme.label) ~= "function" then
		return false
	end
	if Theme.skin == Skin then return true end -- idempotent
	local colors = Theme.colors
	if type(colors) == "table" then
		-- In place: modules that kept a reference to Theme.colors see the new values.
		colors.background, colors.panel, colors.panelLight = P.paper, P.panel, P.paper
		colors.accent, colors.text, colors.subtext = P.primary, P.ink, P.muted
		colors.danger, colors.success = P.danger, P.success
	end
	local corner, stroke, panel, label, button = Theme.corner, Theme.stroke, Theme.panel, Theme.label, Theme.button
	if type(corner) == "function" then
		Theme.corner = function(object, radius)
			local made = corner(object, radius)
			pcall(function() made.CornerRadius = UDim.new(0, 0) end)
			return made
		end
	end
	if type(stroke) == "function" then
		Theme.stroke = function(object)
			local made = stroke(object)
			pcall(function()
				made.Color, made.Thickness, made.Transparency = P.ink, DOT, 0
				made.LineJoinMode = Enum.LineJoinMode.Miter
			end)
			return made
		end
	end
	Theme.panel = function(parent, name, size, position)
		local frame = panel(parent, name, size, position)
		pcall(Skin.surface, frame)
		return frame
	end
	Theme.label = function(parent, name, text, size, options)
		local object = label(parent, name, text, size, options)
		pcall(Skin.text, object, options)
		return object
	end
	Theme.button = function(parent, name, text, onClick, options)
		local object = button(parent, name, text, onClick, options)
		local role = options and (options.primary and "primary" or options.danger and "danger") or "plain"
		pcall(Skin.command, object, {role = role})
		return object
	end
	Theme.skin = Skin
	return true
end

-- Main menu as a Famicom title screen ------------------------------------------------------------------------
local PAGES = {"ShopPage", "SettingsPage", "InventoryPage", "QuestsPage"}

-- Every change goes through the recorder so a failure can put the original screen back exactly.
local function recorder()
	local r = {sets = {}, made = {}, undo = {}}
	function r.set(object, key, value)
		table.insert(r.sets, {object, key, object[key]})
		object[key] = value
	end
	function r.try(object, key, value) -- optional properties (older clients may not have them)
		return (pcall(r.set, object, key, value))
	end
	function r.keep(object, keys)
		for _, key in ipairs(keys) do r.set(object, key, object[key]) end
	end
	function r.make(className, parent, props)
		local object = create(className, parent, props)
		table.insert(r.made, object)
		return object
	end
	function r.revert()
		for index = #r.sets, 1, -1 do
			local entry = r.sets[index]
			pcall(function() entry[1][entry[2]] = entry[3] end)
		end
		for index = #r.made, 1, -1 do pcall(function() r.made[index]:Destroy() end) end
		for _, fn in ipairs(r.undo) do pcall(fn) end
	end
	return r
end

-- Height a page window needs for what is in it (Famicom windows are sized to their text). Offset-placed
-- children count by their bottom edge; a page-relative ScrollingFrame counts by its rows.
function Skin.contentHeight(page)
	local need = 0
	for _, child in ipairs(page:GetChildren()) do
		if child:IsA("GuiObject") and child.Visible ~= false and string.sub(child.Name, 1, 5) ~= "Motif" and child.Name ~= "Title" then
			local size, pos = child.Size, child.Position
			if child.ClassName == "ScrollingFrame" then
				local list = child:FindFirstChildOfClass("UIListLayout")
				local gap = list and list.Padding and list.Padding.Offset or 0
				local total, count = 0, 0
				for _, row in ipairs(child:GetChildren()) do
					if row:IsA("GuiObject") then
						total += row.Size.Y.Offset
						count += 1
					end
				end
				total += math.max(0, count - 1) * gap
				if size.Y.Scale > 0 then
					need = math.max(need, (total - size.Y.Offset) / size.Y.Scale)
				else
					need = math.max(need, pos.Y.Offset + total + 16)
				end
			elseif size.Y.Scale == 0 and pos.Y.Scale == 0 then
				need = math.max(need, pos.Y.Offset + size.Y.Offset + 20)
			end
		end
	end
	return math.ceil(need)
end

local function viewport(gui)
	local ok, size = pcall(function() return gui.AbsoluteSize end)
	if ok and typeof(size) == "Vector2" and size.X > 0 and size.Y > 0 then return size.X, size.Y end
	local camera = workspace and workspace.CurrentCamera
	local view = camera and camera.ViewportSize
	if typeof(view) == "Vector2" and view.X > 0 then return view.X, view.Y end
	return 1280, 720
end
Skin.viewport = viewport

-- A title-screen vignette: the obby runner (Roblox's classic blocky avatar) stepping on a platform between
-- floating blocks and a red kill brick, under a few stars. 60 x 16 dots; the legs have two frames.
local SCENE_COLS, SCENE_ROWS = 60, 16
local SCENE = {
	{"Stars", 0, 0, {
		"....M................................................M......",
		"...................M........................................",
		"..............................................M.............",
		"M.........................M.................................",
	}},
	{"LeftBlock", 3, 10, {"SSSSSSSS", "RRRRRRRR", "EEEEEEEE"}},
	{"CenterBlock", 23, 13, {"SSSSSSSSSSSS", "RRRRRRRRRRRR", "EEEEEEEEEEEE"}},
	{"KillBrick", 48, 6, {"WDDDDD", "DDDDDD", "DDDDDD", "EEEEEE"}},
	{"RunnerBody", 24, 1, {
		"..SSSSSS..",
		"..S.SS.S..",
		"..SSSSSS..",
		"..SS..SS..",
		"..SSSSSS..",
		"SSBBBBBBSS",
		"SSBBBBBBSS",
		"SSBBBBBBSS",
		"SSBBBBBBSS",
	}},
	{"RunnerLegsA", 24, 10, {"..GG..GG..", "..GG..GG..", "..GG..GG.."}},
	{"RunnerLegsB", 24, 10, {"..GG..GG..", ".GG....GG.", "GG......GG"}},
}

local function buildScene(parent, r)
	local colors = {S = C.straw, B = C.cobalt, G = C.leaf, R = C.brick, E = C.ember, D = P.danger, W = P.ink, M = P.muted}
	local holder = r.make("Frame", parent, {
		Name = "MotifPixelScene", BackgroundTransparency = 1, BorderSizePixel = 0, Active = false,
		AnchorPoint = Vector2.new(0.5, 0), ZIndex = 1,
	})
	local pieces = {}
	for _, piece in ipairs(SCENE) do
		local name, x, y, rows = piece[1], piece[2], piece[3], piece[4]
		local art, width, height = Skin.pixelArt(holder, name, rows, colors, {ZIndex = 1})
		art.Position = UDim2.fromScale(x / SCENE_COLS, y / SCENE_ROWS)
		art.Size = UDim2.fromScale(width / SCENE_COLS, height / SCENE_ROWS)
		pieces[name] = art
	end
	pieces.RunnerLegsB.Visible = false
	return holder, pieces
end

function Skin.decorateMainMenu(gui)
	local r = recorder()
	local ok, err = pcall(function()
		local background = assert(gui:FindFirstChild("Background"), "no Background")
		local top = assert(background:FindFirstChild("TopBar"), "no TopBar")
		local title = assert(top:FindFirstChild("Title"), "no Title")
		local coins = assert(top:FindFirstChild("CoinLabel"), "no CoinLabel")
		local play = assert(background:FindFirstChild("PlayButton"), "no PlayButton")
		local nav = assert(background:FindFirstChild("NavBar"), "no NavBar")
		assert(commands[play], "UITheme was not skinned")

		local function retext(object, size, bold)
			local info = texts[object] or {base = object.TextSize, bold = bold}
			texts[object] = info
			r.keep(object, {"TextSize", "FontFace"})
			r.set(info, "base", size)
			if bold ~= nil then r.set(info, "bold", bold) end
			face(object, info.bold)
			if commands[object] then
				r.set(commands[object], "dot", cursorDot(object))
				Skin.cursor(object, commands[object].dot, P.ink)
				Skin.paint(object)
				Skin.placeCursor(object)
			end
		end
		local function repaintable(button)
			local st = commands[button]
			r.keep(button, {"BackgroundColor3", "BackgroundTransparency", "TextColor3"})
			for _, edge in pairs(st.edges or {}) do r.keep(edge, {"Visible", "BackgroundColor3"}) end
			table.insert(r.undo, function() Skin.paint(button) end)
			return st
		end

		r.set(gui, "ZIndexBehavior", Enum.ZIndexBehavior.Sibling)
		-- 黒い画面: the menu is a black screen, not a tinted overlay.
		r.set(background, "BackgroundColor3", P.paper)
		r.set(background, "BackgroundTransparency", 0)

		-- Top band: no window of its own; it holds the gold counter window and the logo.
		r.set(windows, top, nil)
		r.set(top, "BackgroundTransparency", 1)
		for _, side in ipairs(SIDES) do
			local edge = top:FindFirstChild("MotifEdge" .. side)
			if edge then r.set(edge, "Visible", false) end
		end
		local coinWindow = r.make("Frame", top, {
			Name = "MotifCoinWindow", BackgroundColor3 = P.paper, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0), ZIndex = 1,
		})
		Skin.pixelFrame(coinWindow, P.ink)
		r.set(coins, "AnchorPoint", Vector2.new(1, 0))
		r.set(coins, "ZIndex", 2)
		r.set(coins, "BackgroundTransparency", 1)
		r.set(coins, "TextColor3", P.ink)
		r.set(coins, "TextXAlignment", Enum.TextXAlignment.Right)
		r.set(coins, "TextYAlignment", Enum.TextYAlignment.Center)
		r.set(coins, "TextWrapped", false)
		r.set(coins, "TextScaled", true)
		r.make("UITextSizeConstraint", coins, {Name = "MotifHeadingSize", MaxTextSize = 24, MinTextSize = 10})
		r.make("UIPadding", coins, {Name = "MotifPadding", PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, 20)})

		-- Logo: white pixel letters extruded one and two dots with brick and ember, like a cartridge title.
		r.set(title, "ZIndex", 3)
		r.set(title, "TextColor3", P.ink)
		r.set(title, "TextWrapped", false)
		r.set(title, "TextScaled", true)
		r.set(title, "TextYAlignment", Enum.TextYAlignment.Center)
		local titleSize = r.make("UITextSizeConstraint", title, {Name = "MotifHeadingSize", MaxTextSize = 56, MinTextSize = 16})
		local shadows = {}
		for index, color in ipairs({C.brick, C.ember}) do
			local shadow = r.make("TextLabel", top, {
				Name = "MotifTitleShadow" .. index, BackgroundTransparency = 1, Text = title.Text, TextColor3 = color,
				TextScaled = true, TextWrapped = false, ZIndex = 3 - index, Active = false,
			})
			pcall(function() shadow.FontFace = title.FontFace end)
			r.make("UITextSizeConstraint", shadow, {Name = "MotifHeadingSize", MaxTextSize = 56, MinTextSize = 16})
			shadows[index] = shadow
		end
		pcall(function()
			title:GetPropertyChangedSignal("Text"):Connect(function()
				for _, shadow in ipairs(shadows) do
					shadow.Text = title.Text
					pcall(function() shadow.FontFace = title.FontFace end)
				end
			end)
		end)

		local scene, pieces = buildScene(background, r)

		-- START: the one gold thing on screen, in its own window, with the default cursor.
		retext(play, 32)

		-- Command window: the nav buttons become text commands inside one window.
		local navWindow = r.make("Frame", background, {
			Name = "MotifNavWindow", BackgroundColor3 = P.paper, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 1), ZIndex = 1,
		})
		Skin.pixelFrame(navWindow, P.ink)
		r.set(nav, "ZIndex", 2)
		local navList = nav:FindFirstChildOfClass("UIListLayout")
		if navList then r.try(navList, "VerticalAlignment", Enum.VerticalAlignment.Center) end
		for _, button in ipairs(nav:GetChildren()) do
			if commands[button] then
				local st = repaintable(button)
				r.set(st, "framed", false)
				retext(button, 20)
				Skin.paint(button)
			end
		end

		-- Pages: the heading sits in the top frame line, the list reads like a shop window.
		local pages = {}
		for _, name in ipairs(PAGES) do
			local page = gui:FindFirstChild(name)
			if page then
				table.insert(pages, page)
				local heading = page:FindFirstChild("Title")
				if heading then
					r.set(heading, "AnchorPoint", Vector2.new(0.5, 0.5))
					r.set(heading, "Position", UDim2.new(0.5, 0, 0, DOT / 2))
					r.set(heading, "Size", UDim2.new(0, 0, 0, 32))
					r.set(heading, "AutomaticSize", Enum.AutomaticSize.X)
					r.set(heading, "TextWrapped", false)
					r.set(heading, "TextXAlignment", Enum.TextXAlignment.Center)
					r.set(heading, "BackgroundColor3", P.paper)
					r.set(heading, "BackgroundTransparency", 0)
					r.set(heading, "ZIndex", 2)
					r.make("UIPadding", heading, {Name = "MotifPadding", PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12)})
					retext(heading, 24, true)
				end
				local list = page:FindFirstChild("ProductList")
				if list then
					r.set(list, "ScrollBarThickness", DOT)
					r.try(list, "ScrollBarImageColor3", P.ink)
					for _, row in ipairs(list:GetChildren()) do
						local productName, price = row:FindFirstChild("ProductName"), row:FindFirstChild("Price")
						if productName then
							r.set(productName, "Position", UDim2.new(0, 12, 0, 0))
							r.set(productName, "Size", UDim2.new(1, -248, 1, 0))
						end
						if price then
							r.set(price, "AnchorPoint", Vector2.new(1, 0))
							r.set(price, "Position", UDim2.new(1, -124, 0, 0))
							r.set(price, "Size", UDim2.new(0, 112, 1, 0))
							r.set(price, "TextXAlignment", Enum.TextXAlignment.Right)
						end
					end
				end
			end
		end

		-- Responsive layout (IgnoreGuiInset screen: keep text below Roblox's top bar).
		local function layout(set)
			local width, height = viewport(gui)
			local bar = kit:topbar()
			local compact = height < 520
			local narrow = width < 700
			local topY = bar.height + 12
			local titleMax
			set(top, "Position", UDim2.new(0, 16, 0, topY))
			if compact then
				titleMax = 32
				set(top, "Size", UDim2.new(1, -32, 0, 56))
				set(title, "Position", UDim2.new(0, 0, 0, 0))
				set(title, "Size", UDim2.new(1, -(narrow and 216 or 248), 0, 56))
				set(title, "TextXAlignment", Enum.TextXAlignment.Left)
			else
				titleMax = narrow and 40 or 56
				set(top, "Size", UDim2.new(1, -32, 0, 160))
				set(title, "Position", UDim2.new(0, 0, 0, 80))
				set(title, "Size", UDim2.new(1, 0, 0, 64))
				set(title, "TextXAlignment", Enum.TextXAlignment.Center)
			end
			set(titleSize, "MaxTextSize", titleMax)
			local logoDot = math.max(2, math.floor(titleMax / 8))
			for index, shadow in ipairs(shadows) do
				local p = title.Position
				set(shadow, "Position", UDim2.new(p.X.Scale, p.X.Offset + logoDot * index, p.Y.Scale, p.Y.Offset + logoDot * index))
				set(shadow, "Size", title.Size)
				set(shadow, "TextXAlignment", title.TextXAlignment)
				set(shadow:FindFirstChild("MotifHeadingSize"), "MaxTextSize", titleMax)
			end
			local coinSize = UDim2.new(0, narrow and 200 or 232, 0, 56)
			set(coinWindow, "Position", UDim2.new(1, 0, 0, 0))
			set(coinWindow, "Size", coinSize)
			set(coins, "Position", UDim2.new(1, 0, 0, 0))
			set(coins, "Size", coinSize)

			local navSize = narrow and UDim2.new(0, 280, 0, 124) or UDim2.new(0, 560, 0, 64)
			set(nav, "Size", navSize)
			set(nav, "Position", UDim2.new(0.5, 0, 1, -32))
			if navList then
				pcall(set, navList, "Wraps", narrow) -- 2 x 2 command grid on narrow screens
			end
			set(navWindow, "Size", UDim2.new(0, navSize.X.Offset + 40, 0, navSize.Y.Offset + 24))
			set(navWindow, "Position", UDim2.new(0.5, 0, 1, -20))
			local navTop = height - 20 - (navSize.Y.Offset + 24)

			local playHalf = 36
			local playY
			if compact then
				playY = math.floor((topY + 56 + navTop) / 2)
				set(play, "Position", UDim2.new(0.5, 0, 0, playY))
			else
				playY = math.floor(height * 0.6)
				set(play, "Position", UDim2.new(0.5, 0, 0.6, 0))
			end

			-- The vignette only where it fits between the logo and START (2-8 px per dot).
			local sceneTop = topY + 168
			local room = playY - playHalf - 12 - sceneTop
			local dot = math.min(8, math.floor(room / SCENE_ROWS), math.floor((width - 32) / SCENE_COLS))
			set(scene, "Visible", not compact and dot >= 2)
			dot = math.max(dot, 1)
			set(scene, "Size", UDim2.fromOffset(SCENE_COLS * dot, SCENE_ROWS * dot))
			set(scene, "Position", UDim2.new(0.5, 0, 0, sceneTop + math.max(0, math.floor((room - SCENE_ROWS * dot) / 2))))

			-- Pages: sized to their content (Famicom windows hug their text) but never smaller than the band
			-- they open over (sprite + START), so nothing behind is cut in half; below the logo, above the
			-- command window. Short screens use the full height so the command window is not cut either.
			local sceneY = sceneTop + math.max(0, math.floor((room - SCENE_ROWS * dot) / 2))
			local bandTop = (not compact and dot >= 2) and sceneY or (playY - playHalf)
			local bandBottom = playY + playHalf
			local pageWidth = compact and math.min(width - 24, 720) or (narrow and (width - 24) or math.floor(width * 0.6))
			local minTop = compact and (topY + 56 + 28) or (topY + 80 + 64 + 28) -- room for the heading set into the top line
			local limit = compact and (height - 12) or (navTop - 12)
			local maxHeight = math.max(140, limit - minTop)
			for _, page in ipairs(pages) do
				local pageHeight
				if compact then
					pageHeight = maxHeight
				else
					local need = math.max(Skin.contentHeight(page), 140, bandBottom - bandTop + 24)
					pageHeight = math.min(need, maxHeight)
				end
				local pageTop = math.floor((bandTop + bandBottom) / 2 - pageHeight / 2)
				pageTop = math.clamp(pageTop, minTop, math.max(minTop, limit - pageHeight))
				set(page, "Size", UDim2.new(0, pageWidth, 0, pageHeight))
				set(page, "Position", UDim2.new(0.5, -math.floor(pageWidth / 2), 0, pageTop))
			end
		end
		layout(r.set)

		local s = stateFor(gui)
		r.set(s, "default", play)
		r.set(s, "pages", pages)
		local marks = {}
		for _, page in ipairs(pages) do
			local id = string.gsub(page.Name, "Page$", "")
			local chosen = nav:FindFirstChild("Nav_" .. id)
			if chosen and commands[chosen] then marks[page] = chosen end
		end
		r.set(s, "marks", marks)
		local tickers = table.clone(s.tickers)
		table.insert(tickers, function(tick)
			local stride = tick % 2 == 1
			pieces.RunnerLegsA.Visible = not stride
			pieces.RunnerLegsB.Visible = stride
		end)
		r.set(s, "tickers", tickers)

		for _, page in ipairs(pages) do
			pcall(function()
				page:GetPropertyChangedSignal("Visible"):Connect(function()
					-- Choosing a command moves the cursor into the window it opened (as in a Famicom RPG).
					if page.Visible then stateFor(gui).hover = nil end
					Skin.focus(gui)
				end)
			end)
		end
		local function relayout()
			pcall(layout, function(object, key, value) object[key] = value end)
		end
		pcall(function() gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout) end)
		Skin.focus(gui)
	end)
	if not ok then
		r.revert()
		return false, err
	end
	return true
end

return Skin
