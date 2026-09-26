-- ServerScriptService/SwordComboRelay: makes a player's combo visible to everyone else.
-- The client plays its own combo immediately; the server only bumps a cosmetic counter on the character
-- (SwordComboSeq), which every other client replays through SwordCombo/Layer. No pose, no physics, no damage here.
-- Hits: when YOUR server-side hit detection confirms a hit, bump SwordComboHitSeq on the attacker (see bumpHit) so
-- every client shows the hit-stop. NPCs: call SwordComboRelay-style bumps from the NPC AI (same two attributes).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remote = ReplicatedStorage:FindFirstChild("SwordComboRemote")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "SwordComboRemote"
	remote.Parent = ReplicatedStorage
end

local MIN_INTERVAL = 0.12 -- s between accepted presses per player (the combo itself ignores early presses too)
local lastPress = {}

local function bump(character, attr)
	local now = character:GetAttribute(attr)
	character:SetAttribute(attr, (typeof(now) == "number" and now or 0) + 1)
end

remote.OnServerEvent:Connect(function(player, kind)
	if kind ~= "attack" then return end -- only one message type; anything else is ignored
	local t = os.clock()
	if lastPress[player] and t - lastPress[player] < MIN_INTERVAL then return end
	lastPress[player] = t
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	local tool = character:FindFirstChildOfClass("Tool")
	if not tool or not (tool:GetAttribute("SwordCombo") == true or tool.Name == "Sword") then return end
	bump(character, "SwordComboSeq")
end)

game:GetService("Players").PlayerRemoving:Connect(function(player) lastPress[player] = nil end)

-- For server gameplay code: require-free helper through a BindableFunction is overkill; copy these two lines:
--   character:SetAttribute("SwordComboHitSeq", (character:GetAttribute("SwordComboHitSeq") or 0) + 1)  -- on a hit
--   character:SetAttribute("SwordComboSeq", (character:GetAttribute("SwordComboSeq") or 0) + 1)        -- NPC attack
