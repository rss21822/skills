-- Configured copy of roblox-motif-ui/scripts/studio_ui_audit.luau for obby-rush (not run: Studio was unavailable).
-- Studio UI audit: paste into execute_luau (datamodel "Client", during Play) and edit CONFIG.
-- Reports, per screen and size: text that does not fit (TextFits == false), buttons smaller than
-- the touch minimum, buttons sticking out of their clipping container or the screen, and
-- overlapping buttons. Only visible objects count (every ancestor Visible, gui Enabled).
-- Returns "PASS ..." or one line per unique failure.
-- obby-rush MainMenu (deep-sea skin). Run once per device in Studio's Device Simulator
-- (e.g. 1080x720 desktop, a landscape phone ~828x369, a portrait phone ~366x820): the pages live
-- on the ScreenGui itself, so resizing one Frame cannot emulate a device here.
local function openPage(root, id)
	for _, name in ipairs({"ShopPage", "SettingsPage", "InventoryPage", "QuestsPage"}) do
		local frame = root:FindFirstChild(name)
		if frame then frame.Visible = (id ~= nil and name == id .. "Page") end
	end
end
local CONFIG = {
	root = function()
		return game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("MainMenu")
	end,
	-- Same effect as MainMenu.open(gui, id) (the skin's scrim / selected tile follow Visible).
	screens = {
		{name = "main", open = function(root) openPage(root, nil) end},
		{name = "shop", open = function(root) openPage(root, "Shop") end},
		{name = "inventory", open = function(root) openPage(root, "Inventory") end},
		{name = "quests", open = function(root) openPage(root, "Quests") end},
		{name = "settings", open = function(root) openPage(root, "Settings") end},
	},
	sizes = nil,
	resize = function(root, width, height) end,
	minTouch = 48,
	overlapShare = 0.2,
}

local RunService = game:GetService("RunService")
local root = assert(CONFIG.root(), "audit root not found")
local failures, seen = {}, {}
local function add(key, line)
	if not seen[key] then
		seen[key] = true
		table.insert(failures, line)
	end
end
local function shown(object)
	local node = object
	while node and node ~= root.Parent do
		if node:IsA("GuiObject") and not node.Visible then return false end
		if node:IsA("LayerCollector") and not node.Enabled then return false end
		node = node.Parent
	end
	return true
end
local function clipOf(object)
	local node = object.Parent
	while node and node ~= root.Parent do
		if node:IsA("ScrollingFrame") or (node:IsA("GuiObject") and node.ClipsDescendants) then return node end
		node = node.Parent
	end
	return nil
end
local function rect(object)
	local p, s = object.AbsolutePosition, object.AbsoluteSize
	return p.X, p.Y, p.X + s.X, p.Y + s.Y
end
local function path(object)
	local full = object:GetFullName()
	local at = string.find(full, root:GetFullName(), 1, true)
	return at and string.sub(full, at + #root:GetFullName() + 1) or full
end
local viewport = workspace.CurrentCamera.ViewportSize

local function audit(tag)
	local buttons = {}
	for _, object in ipairs(root:GetDescendants()) do
		if object:IsA("GuiObject") and shown(object) then
			local isText = object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox")
			if isText and object.Text ~= "" and not object.TextFits then
				add(tag .. "fit" .. path(object), string.format("%s FIT %s \"%s\" %dx%d ts%d%s", tag, path(object),
					string.sub(object.Text, 1, 32), object.AbsoluteSize.X, object.AbsoluteSize.Y, object.TextSize, object.TextScaled and " scaled" or ""))
			end
			if object:IsA("GuiButton") and object.Active then
				table.insert(buttons, object)
				local w, h = object.AbsoluteSize.X, object.AbsoluteSize.Y
				if w < CONFIG.minTouch or h < CONFIG.minTouch then
					add(tag .. "small" .. path(object), string.format("%s SMALL %s %dx%d", tag, path(object), w, h))
				end
				local x0, y0, x1, y1 = rect(object)
				local clip = clipOf(object)
				if clip and not clip:IsA("ScrollingFrame") then
					local cx0, cy0, cx1, cy1 = rect(clip)
					if x0 < cx0 - 1 or x1 > cx1 + 1 or y0 < cy0 - 1 or y1 > cy1 + 1 then
						add(tag .. "clip" .. path(object), string.format("%s CLIPPED %s by %s", tag, path(object), clip.Name))
					end
				elseif clip then -- scrolling: only horizontal overflow is a bug
					local cx0, _, cx1 = rect(clip)
					if x0 < cx0 - 1 or x1 > cx1 + 1 then
						add(tag .. "over" .. path(object), string.format("%s OVERFLOW-X %s in %s", tag, path(object), clip.Name))
					end
				end
				if x0 < -1 or y0 < -1 or x1 > viewport.X + 1 or y1 > viewport.Y + 1 then
					add(tag .. "off" .. path(object), string.format("%s OFFSCREEN %s", tag, path(object)))
				end
			end
		end
	end
	for i = 1, #buttons do
		for j = i + 1, #buttons do
			local a, b = buttons[i], buttons[j]
			if not a:IsDescendantOf(b) and not b:IsDescendantOf(a) then
				local ax0, ay0, ax1, ay1 = rect(a)
				local bx0, by0, bx1, by1 = rect(b)
				local ix, iy = math.min(ax1, bx1) - math.max(ax0, bx0), math.min(ay1, by1) - math.max(ay0, by0)
				if ix > 0 and iy > 0 then
					local smaller = math.min((ax1 - ax0) * (ay1 - ay0), (bx1 - bx0) * (by1 - by0))
					if smaller > 0 and ix * iy / smaller > CONFIG.overlapShare then
						add(tag .. "lap" .. path(a) .. path(b), string.format("%s OVERLAP %s / %s", tag, path(a), path(b)))
					end
				end
			end
		end
	end
end

local checked = 0
for _, size in ipairs(CONFIG.sizes or {false}) do
	if size then CONFIG.resize(root, size[1], size[2]) end
	for _, screen in ipairs(CONFIG.screens) do
		local ok, err = pcall(screen.open, root)
		RunService.Heartbeat:Wait()
		RunService.Heartbeat:Wait()
		local tag = (size and (size[1] .. "x" .. size[2] .. "/") or "") .. screen.name
		if not ok then add(tag .. "err", tag .. " OPEN-ERROR " .. tostring(err)) end
		audit(tag)
		checked += 1
	end
end
if #failures == 0 then
	return string.format("PASS %d screen states, viewport %dx%d", checked, viewport.X, viewport.Y)
end
return string.format("%d failure(s) over %d screen states\n", #failures, checked) .. table.concat(failures, "\n", 1, math.min(#failures, 80))
