-- Boot (LocalScript): StarterPlayer/StarterPlayerScripts/TerrainPose/Boot
-- Starts the TerrainPose layer for the local player, other players and R15 NPCs.
-- A/B: set the LocalPlayer attribute "TerrainPoseOff" = true to see Animate alone (Studio measurement).
local Players = game:GetService("Players")
local Layer = require(script.Parent:WaitForChild("TerrainPoseLayer"))

Layer.trackAll()

local player = Players.LocalPlayer
local function apply()
	Layer.setEnabled(player:GetAttribute("TerrainPoseOff") ~= true)
end
player:GetAttributeChangedSignal("TerrainPoseOff"):Connect(apply)
apply()
