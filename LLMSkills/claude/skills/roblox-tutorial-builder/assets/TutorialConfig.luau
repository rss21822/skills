-- TutorialConfig (template from the roblox-tutorial-builder skill). Fill it from the project's context sheet:
-- the real bindings, the real first wall, the project's source language. Shared (server + client).

local Config = {}

-- DataStore name prefix: TutorialRecord.storeName(Config.STORE_PREFIX, environment).
Config.STORE_PREFIX = "MyGame"

-- Testers: Roblox UserIds that get the tutorial on EVERY login (no record is read or written for them). Everyone else
-- gets it on the first login only. One list per environment; the environment name comes from the game's own
-- environment check (game.GameId -> "production" / "staging", Studio -> "studio"). Put a UserId in production only
-- when the Owner asks: those accounts will see the tutorial at every login there too.
Config.TESTER_USER_IDS = table.freeze({
	studio = table.freeze({}), -- Studio Play / Team Test: your own UserId here makes every Play start the tutorial
	staging = table.freeze({}),
	production = table.freeze({}),
})

function Config.testersFor(environment)
	return Config.TESTER_USER_IDS[environment] or {}
end

-- The stages, in order. "basics" (the basic controls) is required.
Config.STAGES = table.freeze({ "welcome", "basics", "core", "first_success", "complete" })

-- The basic controls: one action per step, in the order the game needs them. `detect` names a check the client
-- guide implements (TutorialGuideController: BasicControlsDetector's move_* actions, "jump", "camera", or one of the
-- game's own actions from its input module); `hold` (seconds of doing it), `count` (presses) or, for "camera", `turn`
-- (degrees of looking around, e.g. { id = "look", detect = "camera", turn = 120, ... }) is the goal. `prompt` gives the
-- line per device ({key:W} shows the key's label on the player's keyboard layout); it must name the game's REAL
-- bindings on each device (the context sheet), never keys the game does not use. All text is in the game's source
-- language. The values below are for Roblox's default character controls.
Config.BASICS = table.freeze({
	table.freeze({ id = "forward", detect = "move_forward", hold = 1.2, title = "MOVE", text = "Move forward.",
		prompt = table.freeze({ keyboard = "Hold {key:W}", gamepad = "Push the left stick up",
			touch = "Push the stick up" }) }),
	table.freeze({ id = "turn", detect = "move_side", hold = 1.0, title = "SIDESTEP", text = "Move to the side.",
		prompt = table.freeze({ keyboard = "Hold {key:A} or {key:D}", gamepad = "Push the left stick sideways",
			touch = "Push the stick sideways" }) }),
	table.freeze({ id = "back", detect = "move_back", hold = 0.8, title = "BACK UP", text = "Move back.",
		prompt = table.freeze({ keyboard = "Hold {key:S}", gamepad = "Pull the left stick down",
			touch = "Pull the stick down" }) }),
	table.freeze({ id = "jump", detect = "jump", count = 2, title = "JUMP", text = "Jump twice.",
		prompt = table.freeze({ keyboard = "Press {key:Space} twice", gamepad = "Press A twice",
			touch = "Tap the jump button twice" }) }),
})

-- Nobody gets stuck: a step the player cannot finish is passed over after STEP_FALLBACK_SECONDS, a stage after its
-- STAGE_FALLBACK_SECONDS (the server's clock).
Config.STEP_FALLBACK_SECONDS = 25
Config.STAGE_FALLBACK_SECONDS = table.freeze({ welcome = 60, basics = 180, core = 150, first_success = 240 })
-- The server ignores a step reported sooner than this after the step began (client reports are not trusted).
Config.MIN_STEP_SECONDS = 0.5

local function whole(n)
	return type(n) == "number" and n > 0 and n == math.floor(n)
end

-- true | false, { problem, ... }: the tests call this (a tutorial without its basic controls does not ship).
function Config.validate(config)
	config = config or Config
	local problems = {}
	local hasBasics = false
	for _, stage in ipairs(config.STAGES or {}) do
		if stage == "basics" then
			hasBasics = true
		end
	end
	if not hasBasics then
		table.insert(problems, "STAGES has no basics stage")
	end
	if type(config.BASICS) ~= "table" or #config.BASICS == 0 then
		table.insert(problems, "BASICS is empty")
	else
		for i, step in ipairs(config.BASICS) do
			if type(step.id) ~= "string" or type(step.detect) ~= "string" then
				table.insert(problems, "BASICS[" .. i .. "] needs id and detect")
			end
			if type(step.title) ~= "string" or step.title == "" or type(step.text) ~= "string" or step.text == "" then
				table.insert(problems, "BASICS[" .. i .. "] needs title and text")
			end
			local goal = (type(step.hold) == "number" and step.hold > 0) or whole(step.count)
				or (step.detect == "camera" and type(step.turn) == "number" and step.turn > 0)
			if not goal then
				table.insert(problems, "BASICS[" .. i .. "] needs hold > 0, a whole count, or (camera) turn > 0")
			end
			if step.prompt ~= nil then
				if type(step.prompt) ~= "table" then
					table.insert(problems, "BASICS[" .. i .. "].prompt must be a table of device -> text")
				else
					for _, device in ipairs({ "keyboard", "gamepad", "touch" }) do
						if type(step.prompt[device]) ~= "string" or step.prompt[device] == "" then
							table.insert(problems, "BASICS[" .. i .. "].prompt." .. device .. " is missing")
						end
					end
				end
			end
		end
	end
	for environment, ids in pairs(config.TESTER_USER_IDS or {}) do
		for _, id in ipairs(ids) do
			if not whole(id) then
				table.insert(problems, "TESTER_USER_IDS." .. tostring(environment) .. " has " .. tostring(id))
			end
		end
	end
	if not (type(config.STEP_FALLBACK_SECONDS) == "number" and config.STEP_FALLBACK_SECONDS > 0) then
		table.insert(problems, "STEP_FALLBACK_SECONDS must be > 0")
	end
	-- Nobody gets stuck: every stage but the last (the completion) ends by itself after a while.
	local stages = config.STAGES or {}
	local limits = config.STAGE_FALLBACK_SECONDS or {}
	for i = 1, #stages - 1 do
		local limit = limits[stages[i]]
		if not (type(limit) == "number" and limit > 0) then
			table.insert(problems, "STAGE_FALLBACK_SECONDS." .. tostring(stages[i]) .. " must be > 0")
		end
	end
	return #problems == 0, problems
end

return Config
