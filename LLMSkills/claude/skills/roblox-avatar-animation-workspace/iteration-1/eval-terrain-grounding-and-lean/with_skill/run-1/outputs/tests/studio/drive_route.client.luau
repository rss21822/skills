-- Studio (execute_luau, "Client" during Play of tools/make_sandbox.py's Place): walk the local character over the
-- same route twice, layer OFF then ON, while tests/studio/contact_probe.luau and bank_probe.client.luau record.
-- Route: flat -> climb the 22 deg slope -> back down -> climb the stairs -> back down -> 3 laps of an R=8 circle.
-- Returns when done (about 2 x 60 s). If a MoveTo stalls it gives up after 8 s and continues.
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
humanoid.WalkSpeed = 16

local ROUTE = {
	Vector3.new(40, 0, -4), Vector3.new(40, 20, 62), Vector3.new(40, 0, -4), -- slope (x = 40, rises toward +Z)
	Vector3.new(-40, 0, 14), Vector3.new(-40, 8, 52), Vector3.new(-40, 0, 14), -- stairs (x = -40)
}
for lap = 1, 3 do -- circle R = 8 around (0, 0, -30), 16 points per lap
	for i = 0, 15 do
		local a = (lap * 16 + i) / 16 * 2 * math.pi
		table.insert(ROUTE, Vector3.new(8 * math.cos(a), 0, -30 + 8 * math.sin(a)))
	end
end

local function go(point)
	humanoid:MoveTo(point)
	local done = false
	local conn = humanoid.MoveToFinished:Connect(function() done = true end)
	local t0 = os.clock()
	while not done and os.clock() - t0 < 8 do task.wait() end
	conn:Disconnect()
end

local log = {}
for _, off in { true, false } do
	player:SetAttribute("TerrainPoseOff", off)
	task.wait(0.5)
	local t0 = os.clock()
	for _, p in ROUTE do go(p) end
	table.insert(log, string.format("%s route %.1f s", off and "OFF" or "ON", os.clock() - t0))
end
player:SetAttribute("TerrainPoseOff", false)
return table.concat(log, "\n")
