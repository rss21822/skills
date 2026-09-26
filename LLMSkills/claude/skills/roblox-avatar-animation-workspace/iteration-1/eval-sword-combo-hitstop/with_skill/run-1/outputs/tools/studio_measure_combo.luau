-- Studio Play measurement (paste into execute_luau with datamodel Client, or a temporary LocalScript). Read-only:
-- samples the drawn pose every RenderStepped while the local character's attribute SwordComboStrike is set, and
-- prints a summary when the combo ends. Nothing here changes the game.
--   * max per-frame joint rotation (deg) outside the authored swing is not separable here, so it reports the
--     per-joint max and the frame it happened on; compare with the offline numbers (REPORT.md)
--   * planted-foot drift: horizontal world movement of LeftFoot / RightFoot while the sole is within 0.02 of the floor
--   * sole vs floor: raycast straight down from above each foot (min = sinking, want >= -0.02)
--   * hit-stop: frames on which SwordComboStrike is set and the right shoulder did not move more than the shake
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local character = Players.LocalPlayer.Character
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances = { character }
local joints = {}
for _, d in character:GetDescendants() do
	if d:IsA("Motor6D") or d:IsA("AnimationConstraint") then joints[d.Name] = d end
end
local function soleBottom(part)
	local cf, size = part.CFrame, part.Size
	return cf.Y - (math.abs(cf.RightVector.Y) * size.X + math.abs(cf.UpVector.Y) * size.Y + math.abs(cf.LookVector.Y) * size.Z) * 0.5
end
_G.SwordComboMeasure = { frames = 0, maxRot = {}, drift = 0, minSole = math.huge, still = 0 }
local m = _G.SwordComboMeasure
local last, lastFoot = {}, {}
local conn
conn = RunService.RenderStepped:Connect(function()
	local active = character:GetAttribute("SwordComboStrike") ~= nil
	if not active then
		if m.frames > 0 and not m.printed then
			m.printed = true
			local rows = {}
			for name, v in m.maxRot do table.insert(rows, string.format("%s %.1f", name, v)) end
			table.sort(rows)
			print(string.format("[SwordComboMeasure] frames=%d minSole=%.3f footDrift=%.4f stillFrames=%d", m.frames, m.minSole, m.drift, m.still))
			print("[SwordComboMeasure] max deg/frame: " .. table.concat(rows, ", "))
		end
		return
	end
	m.frames += 1
	for name, j in joints do
		local t = j.Transform
		if last[name] then
			local _, a = last[name]:ToObjectSpace(t):ToAxisAngle()
			m.maxRot[name] = math.max(m.maxRot[name] or 0, math.deg(math.abs(a)))
			if name == "RightShoulder" and math.deg(math.abs(a)) < 3.3 then m.still += 1 end
		end
		last[name] = t
	end
	for _, side in { "LeftFoot", "RightFoot" } do
		local foot = character:FindFirstChild(side)
		if foot then
			local hit = workspace:Raycast(foot.Position + Vector3.new(0, 3, 0), Vector3.new(0, -8, 0), params)
			if hit then
				local h = soleBottom(foot) - hit.Position.Y
				m.minSole = math.min(m.minSole, h)
				if h < 0.02 and lastFoot[side] then
					local d = foot.Position - lastFoot[side]
					m.drift = math.max(m.drift, Vector3.new(d.X, 0, d.Z).Magnitude)
				end
			end
			lastFoot[side] = foot.Position
		end
	end
end)
_G.SwordComboMeasureStop = function() conn:Disconnect() end
return "measuring; attack now, the summary prints when the combo ends"
