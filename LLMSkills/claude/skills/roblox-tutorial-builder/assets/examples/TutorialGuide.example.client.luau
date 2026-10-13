-- TutorialGuide (example from the roblox-tutorial-builder skill): the client wiring. Lines marked PROJECT come from
-- the context sheet. The view is NOT a generic card: build it from the game's own UI kit (its HUD panels, fonts,
-- colours, icons, the safe areas its HUD keeps) -- references/ui-and-text.md. Text comes from TutorialConfig in the
-- game's source language.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Tutorial") -- PROJECT
local Config = require(Shared.TutorialConfig)
local Detector = require(Shared.BasicControlsDetector)
local Controller = require(Shared.TutorialGuideController)
local remote = Shared:WaitForChild("TutorialAction")

local player = Players.LocalPlayer
local humanoid = nil
local jumped = false

local function onCharacter(character)
	humanoid = character:WaitForChild("Humanoid")
	Detector.watchJumps(humanoid, function()
		jumped = true
	end)
end
if player.Character then
	task.spawn(onCharacter, player.Character)
end
player.CharacterAdded:Connect(onCharacter)

-- PROJECT: the view, from the game's UI kit. Four calls; keep them cheap (build the UI once, update text/size).
local view = {
	stage = function(stage)
		-- show the welcome cards / the basics panel / the completion card for `stage`; hide the rest
	end,
	step = function(step, index, total, label)
		-- the step card: step.title, label (the device prompt), "index / total"
	end,
	progress = function(fraction)
		-- the step's meter (0..1); never shrink it back
	end,
	hide = function()
		-- the tutorial ended or never ran here
	end,
}

local controller = Controller.new({
	config = Config,
	detector = Detector,
	read = function()
		return player:GetAttribute("TutorialStage"), player:GetAttribute("TutorialStepId")
	end,
	sample = function()
		local jumpedNow = jumped
		jumped = false
		local camera = Workspace.CurrentCamera
		return {
			moveDirection = humanoid and humanoid.MoveDirection or nil,
			lookVector = camera and camera.CFrame.LookVector or nil,
			jumping = jumpedNow,
			actions = {}, -- PROJECT: the game's own held / pressed actions (e.g. GameInput.held()) for custom steps
		}
	end,
	device = function()
		return Detector.device(UserInputService)
	end,
	keyString = function(name)
		return UserInputService:GetStringForKeyCode(Enum.KeyCode[name])
	end,
	report = function(payload)
		remote:FireServer(payload)
	end,
	view = view,
})

RunService.RenderStepped:Connect(function(dt)
	controller:update(dt)
end)

-- PROJECT: the welcome card's last button calls controller:confirm()
