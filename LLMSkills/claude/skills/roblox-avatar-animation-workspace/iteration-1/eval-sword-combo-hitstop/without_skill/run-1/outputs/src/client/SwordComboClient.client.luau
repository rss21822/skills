--!strict
-- StarterPlayer > StarterPlayerScripts に置く LocalScript。
-- ReplicatedStorage.SwordCombo（Folder: PoseMath / ComboData / ComboPlayer / SwordComboLayer の ModuleScript）が必要。
-- 左クリック / ゲームパッド R2 / F キーで攻撃。押すたびに 1→2→3 撃目へつながる（先行入力 OK）。
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local folder = ReplicatedStorage:WaitForChild("SwordCombo")
local SwordComboLayer = require(folder:WaitForChild("SwordComboLayer"))

local player = Players.LocalPlayer
local layer: any = nil

local function onCharacter(character: Model)
	if layer then
		layer:Destroy()
		layer = nil
	end
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		warn("SwordCombo: R15 専用です")
		return
	end
	layer = SwordComboLayer.new(character, {
		createSword = true,
		hitShake = true,
		onStrikeStart = function(i: number)
			character:SetAttribute("SwordComboStrike", i)
		end,
		onHit = function(i: number, hit: Instance, pos: Vector3, hitStop: number)
			-- 検証用: 何段目が何に当たり、何秒止めたかを属性とログに残す
			character:SetAttribute("SwordComboLastHit", string.format("%d:%s:%.2f", i, hit.Name, hitStop))
			print(string.format("[SwordCombo] strike %d hit %s at %s, hitstop %.3fs", i, hit:GetFullName(), tostring(pos), hitStop))
		end,
	})
	humanoid.Died:Connect(function()
		if layer then
			layer:Destroy()
			layer = nil
		end
	end)
end

player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed or not layer then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.KeyCode == Enum.KeyCode.ButtonR2
		or input.KeyCode == Enum.KeyCode.F then
		layer:press()
	end
end)
