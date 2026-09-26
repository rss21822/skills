-- StarterPlayerScripts/SwordComboClient: local input -> SwordCombo layer (instant) + server relay (so others see it).
-- Any Tool with the attribute SwordCombo = true (or named "Sword") drives the combo when activated.
-- Animate is untouched: it keeps playing idle/walk/toolnone; the layer draws over it only while a combo runs.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Layer = require(ReplicatedStorage:WaitForChild("SwordCombo"):WaitForChild("Layer"))
local remote = ReplicatedStorage:WaitForChild("SwordComboRemote")

Layer.trackAll()

local localPlayer = Players.LocalPlayer

local function isSword(tool)
	return tool:IsA("Tool") and (tool:GetAttribute("SwordCombo") == true or tool.Name == "Sword")
end

local function hookTool(tool)
	if not isSword(tool) or tool:GetAttribute("_SwordComboHooked") then return end
	tool:SetAttribute("_SwordComboHooked", true)
	tool.Activated:Connect(function()
		local character = localPlayer.Character
		if character and tool.Parent == character and Layer.attack(character) then
			remote:FireServer("attack")
		end
	end)
end

local function hookCharacter(character)
	for _, child in character:GetChildren() do hookTool(child) end
	character.ChildAdded:Connect(hookTool)
end
if localPlayer.Character then hookCharacter(localPlayer.Character) end
localPlayer.CharacterAdded:Connect(hookCharacter)

-- Hook points for gameplay (examples, keep or replace):
-- Layer.setHitTest(function(character, strikeIndex) return <your client-side hit prediction> end)
-- Layer.onEvent(function(character, kind, strikeIndex) -- "strike" | "contact" | "hit" | "exit" | "done"
-- 	if kind == "hit" and character == localPlayer.Character then <camera shake / hit SFX> end
-- end)
