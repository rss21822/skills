-- Studio (execute_luau, "Client" during Play): per-frame foot-contact logger. Run once to START, drive the character
-- (MoveTo route, keyboard input, a lab hook, or just let NPCs play), then run the READ snippet at the bottom as a
-- separate execute_luau call. Works on flat floors, slopes and stairs: every foot gets its own ray, started at the
-- root's height above the foot (a ray that starts inside a step never hits it and would report a far floor).
--
-- Per group (body | floor part under the root | layer ON/OFF | mode attribute | moving/still), grounded frames only:
--   minGap    lowest foot corner minus the floor under THAT foot, over both feet (negative = inside the floor)
--   lower*    the lower foot's gap (the planted foot): mean / max; max > 0.1 means both feet float
--   sink      frames with any foot < -0.05 inside its floor;  float = frames with the lower foot > 0.1 above
-- Targets (anim-elite): sink = 0 (min >= -0.02) and float ~ 0 outside authored lifts, on every body and floor.
local TRACK = "all" -- "local" or "all" (every Humanoid with R15 feet: NPCs, remote players)
local MODE_ATTRIBUTE = "PoseMode" -- attribute your layer writes on the character (nil = no split)
local LAYER_OFF_ATTRIBUTE = "PoseLayerOff" -- LocalPlayer attribute used for A/B (nil = no split)
local GROUP_STAIRS = { "^Step", "Stair" } -- floor part names folded into one group (edit for your map)

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
if _G.__contactProbe then _G.__contactProbe.conn:Disconnect() end
local stats = { groups = {}, started = os.clock() }
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

local function bottom(part)
	local cf, s = part.CFrame, part.Size
	return cf.Y - (math.abs(cf.RightVector.Y) * s.X + math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.LookVector.Y) * s.Z) * 0.5
end
local function floorName(inst)
	local name = inst and inst.Name or "?"
	for _, pattern in GROUP_STAIRS do if name:match(pattern) then return "Stairs" end end
	return name
end
local function bodies()
	if TRACK == "local" then return { Players.LocalPlayer.Character } end
	local list = {}
	for _, h in workspace:GetDescendants() do
		if h:IsA("Humanoid") and h.Parent:FindFirstChild("LeftFoot") and h.Parent:FindFirstChild("RightFoot") then table.insert(list, h.Parent) end
	end
	return list
end
local tracked, lastScan = bodies(), os.clock()
stats.conn = RunService.RenderStepped:Connect(function()
	if os.clock() - lastScan > 2 then tracked, lastScan = bodies(), os.clock() end
	params.FilterDescendantsInstances = tracked
	for _, c in tracked do
		local root, h = c and c.Parent and c:FindFirstChild("HumanoidRootPart"), c and c:FindFirstChildOfClass("Humanoid")
		if root and h and h.Health > 0 then
			local under = workspace:Raycast(root.Position, Vector3.new(0, -12, 0), params)
			local stand = h.HipHeight + root.Size.Y * 0.5
			local grounded = under and (root.Position.Y - under.Position.Y) < stand + 0.6 and math.abs(root.AssemblyLinearVelocity.Y) < 8
			if grounded then
				local gaps = {}
				for _, foot in { c.LeftFoot, c.RightFoot } do
					-- toe and heel rays; the foot stands on the higher surface (across a step edge = the upper step)
					local floorY
					for _, along in { 0.4, -0.4 } do
						local point = foot.Position + foot.CFrame.LookVector * (foot.Size.Z * along)
						local start = Vector3.new(point.X, root.Position.Y, point.Z)
						local hit = workspace:Raycast(start, Vector3.new(0, -(root.Position.Y - point.Y + 4), 0), params)
						if hit and (not floorY or hit.Position.Y > floorY) then floorY = hit.Position.Y end
					end
					if floorY then table.insert(gaps, bottom(foot) - floorY) end
				end
				if #gaps == 2 then
					local v = root.AssemblyLinearVelocity
					local key = table.concat({ c.Name, floorName(under.Instance),
						LAYER_OFF_ATTRIBUTE and (Players.LocalPlayer:GetAttribute(LAYER_OFF_ATTRIBUTE) and "OFF" or "ON") or "-",
						MODE_ATTRIBUTE and tostring(c:GetAttribute(MODE_ATTRIBUTE) or "-") or "-",
						Vector3.new(v.X, 0, v.Z).Magnitude > 2 and "move" or "still" }, "|")
					local b = stats.groups[key] or { n = 0, minGap = math.huge, lowerSum = 0, lowerMax = -math.huge, sink = 0, float = 0 }
					stats.groups[key] = b
					local lower = math.min(gaps[1], gaps[2])
					b.n += 1; b.minGap = math.min(b.minGap, lower); b.lowerSum += lower; b.lowerMax = math.max(b.lowerMax, lower)
					if lower < -0.05 then b.sink += 1 end
					if lower > 0.1 then b.float += 1 end
				end
			end
		end
	end
end)
_G.__contactProbe = stats
return "contact probe started on " .. #tracked .. " bodies"

--[[ READ (separate execute_luau call):
local s = _G.__contactProbe
if not s then return "probe not running" end
local keys, out = {}, { string.format("%.1f s", os.clock() - s.started) }
for k in s.groups do table.insert(keys, k) end
table.sort(keys)
for _, k in keys do
	local b = s.groups[k]
	table.insert(out, string.format("%s n=%d minGap=%.3f lowerMean=%.3f lowerMax=%.3f sink=%d float=%d", k, b.n, b.minGap, b.lowerSum / b.n, b.lowerMax, b.sink, b.float))
end
return table.concat(out, "\n")
]]
