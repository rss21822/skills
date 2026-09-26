-- Studio (execute_luau, "Client" during Play): records, per frame, for the local character AND every R15 NPC:
--   * drawn lean (Root joint Transform roll) vs the expected atan(1.4 * v * w / g) (clamped 20 deg, faded below 14 stud/s)
--   * the largest one-frame joint rotation (pop) of any joint, split by layer ON / OFF
-- START: run this file. Drive (drive_route.client.luau / NPCs). READ: run the snippet at the bottom separately.
-- Expected with the layer ON: |drawn - expected| mean < 1.5 deg in steady turns, sign = into the turn (+ = left);
-- OFF: drawn ~ 0 (the default Animate does not lean). Pop ON should not exceed OFF by more than ~6 deg at 60 fps.
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
if _G.__bankProbe then _G.__bankProbe.conn:Disconnect() end
local GAIN, MAX, MIN_SPEED, SPAN = 1.4, math.rad(20), 4, 10
local stats = { groups = {} }
local prev = {} -- [model] = { dir, joints = { [name] = Transform } }

local function smoothstep(t) t = math.clamp(t, 0, 1) return t * t * (3 - 2 * t) end
local function bodies()
	local list = {}
	for _, h in workspace:GetDescendants() do
		if h:IsA("Humanoid") and h.RigType == Enum.HumanoidRigType.R15 and h.Parent:FindFirstChild("LowerTorso") then
			table.insert(list, h.Parent)
		end
	end
	return list
end
local tracked, lastScan = bodies(), os.clock()
stats.conn = RunService.RenderStepped:Connect(function(dt)
	if os.clock() - lastScan > 2 then tracked, lastScan = bodies(), os.clock() end
	local layer = Players.LocalPlayer:GetAttribute("TerrainPoseOff") and "OFF" or "ON"
	for _, c in tracked do
		local root, lower = c:FindFirstChild("HumanoidRootPart"), c:FindFirstChild("LowerTorso")
		local rootJoint = lower and (lower:FindFirstChild("Root") or lower:FindFirstChildWhichIsA("Motor6D"))
		if root and rootJoint and dt > 0 then
			local v = root.AssemblyLinearVelocity
			local flat = Vector3.new(v.X, 0, v.Z)
			local speed = flat.Magnitude
			local p = prev[c] or { joints = {} }
			prev[c] = p
			local omega = 0
			if p.dir and speed > 2 then
				local a, b = p.dir, flat.Unit
				omega = math.atan2(a.Z * b.X - a.X * b.Z, a.X * b.X + a.Z * b.Z) / dt
			end
			p.dir = speed > 1e-3 and flat.Unit or p.dir
			p.omega = (p.omega or 0) + (omega - (p.omega or 0)) * math.min(1, dt / 0.1)
			local expected = math.clamp(math.atan(GAIN * speed * p.omega / workspace.Gravity), -MAX, MAX)
				* smoothstep((speed - MIN_SPEED) / SPAN)
			local _, _, roll = rootJoint.Transform:ToEulerAnglesYXZ()
			local pop = 0
			for _, j in c:GetDescendants() do
				if j:IsA("Motor6D") or j:IsA("AnimationConstraint") then
					local last = p.joints[j.Name]
					if last then
						local _, angle = last:ToObjectSpace(j.Transform):ToAxisAngle()
						pop = math.max(pop, math.abs(angle))
					end
					p.joints[j.Name] = j.Transform
				end
			end
			local key = c.Name .. "|" .. layer .. "|" .. (math.abs(expected) > math.rad(3) and "turning" or "straight")
			local g = stats.groups[key] or { n = 0, err = 0, drawn = 0, exp = 0, pop = 0 }
			stats.groups[key] = g
			g.n += 1
			g.err += math.abs(roll - expected)
			g.drawn += roll
			g.exp += expected
			g.pop = math.max(g.pop, pop)
		end
	end
end)
_G.__bankProbe = stats
return "bank probe started on " .. #tracked .. " bodies"

--[[ READ (separate execute_luau call):
local s = _G.__bankProbe
if not s then return "not running" end
local out = {}
for k, g in s.groups do
	table.insert(out, string.format("%s n=%d drawnMean=%.2f expMean=%.2f |err|mean=%.2f deg maxPop=%.1f deg", k, g.n,
		math.deg(g.drawn / g.n), math.deg(g.exp / g.n), math.deg(g.err / g.n), math.deg(g.pop)))
end
table.sort(out)
return table.concat(out, "\n")
]]
