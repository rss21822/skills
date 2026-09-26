local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MainMenu = require(script.Parent:WaitForChild("MainMenu"))

local remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
local function fire(name, ...)
	local remote = remotes and remotes:FindFirstChild(name)
	if remote then remote:FireServer(...) end
end

MainMenu.build(Players.LocalPlayer:WaitForChild("PlayerGui"), {
	play = function() fire("RequestPlay") end,
	buy = function(productId) fire("RequestPurchase", productId) end,
	toggle = function(settingId, on) fire("SetSetting", settingId, on) end,
}, {
	coins = 1250,
	products = {
		{id = "speed_coil", name = "スピードコイル", price = 300},
		{id = "rainbow_trail", name = "虹のトレイル", price = 450},
		{id = "double_jump", name = "ダブルジャンプ", price = 800},
	},
	settings = {music = true, sfx = true},
})
