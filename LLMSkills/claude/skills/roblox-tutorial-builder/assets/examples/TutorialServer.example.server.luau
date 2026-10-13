-- TutorialServer (example from the roblox-tutorial-builder skill): the server wiring of a tutorial that runs in the
-- player's own server (a single-Place game, or the Lobby's own tutorial area). Lines marked PROJECT must be
-- replaced from the context sheet. A dedicated tutorial Place uses TutorialRouting in the Lobby instead of the
-- PlayerAdded block below, and this file's flow part in the tutorial Place.
--
-- The order matters: decide (read the record) -> begin (count the start) -> flow:start (show it). The start is
-- counted before anything is shown, so leaving half-way never brings the tutorial back at the next login.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Tutorial") -- PROJECT: where the shared modules live
local Config = require(Shared.TutorialConfig)
local Record = require(Shared.TutorialRecord)
local Gate = require(Shared.TutorialGate)
local Flow = require(Shared.TutorialFlow)

local PRODUCTION_GAME_ID = 0 -- PROJECT: the production universe (game.GameId); 0 = not published yet
local STAGING_GAME_ID = 0 -- PROJECT: the staging universe, if the game has one

-- PROJECT: use the game's own environment check if it has one.
local function environment()
	if RunService:IsStudio() then
		return "studio"
	elseif game.GameId == PRODUCTION_GAME_ID then
		return "production"
	elseif game.GameId == STAGING_GAME_ID then
		return "staging"
	end
	return "unknown"
end

local env = environment()

-- Studio has no DataStore in an unpublished file: a memory store (every Play starts as a first login). To see a
-- returning player in Studio, seed it: Record.newMemoryStore({ data = { ["u:<UserId>"] = { v = 1, starts = 1 } } }).
local store
if env == "studio" then
	store = Record.newMemoryStore()
elseif env ~= "unknown" then
	local ok, value = pcall(Record.newStore, { name = Record.storeName(Config.STORE_PREFIX, env) })
	if ok then
		store = value
	else
		warn("[Tutorial] record store unavailable: " .. tostring(value))
	end
end

local remote = Instance.new("RemoteEvent")
remote.Name = "TutorialAction" -- PROJECT: the game's remote naming / folder
remote.Parent = Shared

local gate = store and Gate.new({
	store = store,
	testers = Config.testersFor(env),
	ownPlaceIds = {}, -- PROJECT: every PlaceId of the experience (the Lobby, matches, the tutorial Place ...)
	-- PROJECT: the game's "played before" signal, if the profile keeps one (nil = not loaded yet):
	-- isExperienced = function(player) local p = Profiles.get(player); return p and p.matchesPlayed > 0 or nil end,
	log = function(event, player, detail)
		warn(string.format("[Tutorial] %s uid=%d %s", event, player.UserId, tostring(detail)))
	end,
})

local flow = Flow.new(Config, {
	clock = os.clock,
	onChange = function(player, state, why)
		player:SetAttribute("TutorialStage", state.stage)
		player:SetAttribute("TutorialStepId", state.stepId)
		player:SetAttribute("TutorialWhy", why)
	end,
	onComplete = function(player)
		if gate then
			gate:complete(player) -- testers write nothing
		end
		-- PROJECT: hand the player to the real game (open the lobby UI, queue the first match, ...)
	end,
})

remote.OnServerEvent:Connect(function(player, payload)
	flow:report(player, payload) -- validates stage, step, timing and rate itself
end)

RunService.Heartbeat:Connect(function()
	flow:tick()
end)

local function consider(player)
	if not gate then
		return -- no store: never block the game; nothing was counted
	end
	for _ = 1, 40 do -- wait for the game's "played before" signal (isExperienced = nil means not loaded)
		local verdict, why = gate:decide(player)
		if player.Parent ~= Players then
			return
		end
		if verdict == "tester" or verdict == "first_time" then
			local ok = gate:begin(player)
			if ok and player.Parent == Players then
				flow:start(player)
			elseif ok then
				gate:refund(player) -- left before anything was shown
			end
			return
		end
		if why ~= "not_loaded" then
			return -- arrival / experienced / completed / attempts / store error: no tutorial this visit
		end
		task.wait(0.5)
	end
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(consider, player)
end)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(consider, player)
end

Players.PlayerRemoving:Connect(function(player)
	flow:remove(player)
	if gate then
		gate:forget(player)
	end
end)
