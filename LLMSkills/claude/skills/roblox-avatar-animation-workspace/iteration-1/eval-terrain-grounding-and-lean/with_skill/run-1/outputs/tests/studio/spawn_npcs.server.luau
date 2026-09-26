-- Studio (execute_luau, "Server" during Play of the sandbox): spawns 3 R15 NPCs (default blocky body, scales 0.8 / 1.0
-- / 1.3) animated by a server copy of the default Animate, and walks them over the slope / stairs / circle for 90 s.
-- The client's TerrainPose layer picks them up automatically (Workspace.DescendantAdded). In your own game use your
-- real NPCs instead; they only need to be R15 Humanoid models in Workspace.
local Players = game:GetService("Players")
local ROUTE = {
	Vector3.new(40, 0, -4), Vector3.new(40, 20, 62), Vector3.new(40, 0, -4),
	Vector3.new(-40, 0, 14), Vector3.new(-40, 8, 52), Vector3.new(-40, 0, 14),
	Vector3.new(8, 0, -30), Vector3.new(0, 0, -22), Vector3.new(-8, 0, -30), Vector3.new(0, 0, -38),
}
local made = {}
for i, scale in { 0.8, 1.0, 1.3 } do
	local desc = Instance.new("HumanoidDescription")
	desc.HeightScale, desc.WidthScale, desc.DepthScale, desc.HeadScale = scale, scale, scale, scale
	local npc = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	npc.Name = "NPC_" .. i
	-- the model's Animate is a LocalScript (does not run on a server-owned NPC): run the same source as a Script
	local animate = npc:FindFirstChild("Animate")
	if animate and animate:IsA("LocalScript") then
		local s = Instance.new("Script")
		s.Name = "Animate"
		s.Source = animate.Source
		for _, child in animate:GetChildren() do child.Parent = s end
		animate:Destroy()
		s.Parent = npc
	end
	npc:PivotTo(CFrame.new(-6 + 6 * i, 5, 6))
	npc.Parent = workspace
	table.insert(made, npc)
	task.spawn(function()
		local humanoid = npc:WaitForChild("Humanoid")
		humanoid.WalkSpeed = 12 + 2 * i
		local t0, k = os.clock(), i
		while os.clock() - t0 < 90 and npc.Parent do
			humanoid:MoveTo(ROUTE[(k - 1) % #ROUTE + 1])
			local done = false
			local conn = humanoid.MoveToFinished:Connect(function() done = true end)
			local t1 = os.clock()
			while not done and os.clock() - t1 < 8 do task.wait() end
			conn:Disconnect()
			k += 1
		end
	end)
end
return "spawned " .. #made .. " NPCs"
