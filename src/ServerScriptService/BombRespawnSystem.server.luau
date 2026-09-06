-- BombRespawnSystem
--
-- Sole owner of BombMonster returns.  The warning/explosion remains in
-- MonsterBombSystem; this script only remembers a living bomb's source model,
-- original position, and finite return budget before it dies.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))
local Config = require(ReplicatedStorage:WaitForChild("MonsterBombConfig"))

local RETURNS_ATTRIBUTE = "BombRespawnsRemaining"
local MIN_RETURNS = 2
local MAX_RETURNS = 3

local states = {}

local function isBomb(model)
	return model:IsA("Model") and model.Name == Config.MODEL_NAME
end

local function prepareBomb(model, returnsRemaining)
	model:SetAttribute("NoAutoRespawn", true)
	model:SetAttribute(RETURNS_ATTRIBUTE, returnsRemaining)
	local humanoid = MonsterManager.getMonsterHumanoid(model)
	if humanoid then
		humanoid.MaxHealth = Config.HEALTH
		humanoid.Health = Config.HEALTH
	end
end

local function registerBomb(model)
	if states[model] or not isBomb(model) then return end

	local humanoid = MonsterManager.getMonsterHumanoid(model)
	local parent = model.Parent
	if not humanoid or not parent then return end

	local returnsRemaining = tonumber(model:GetAttribute(RETURNS_ATTRIBUTE))
	if returnsRemaining == nil then
		returnsRemaining = math.random(MIN_RETURNS, MAX_RETURNS)
	end
	returnsRemaining = math.max(0, math.floor(returnsRemaining))
	prepareBomb(model, returnsRemaining)

	-- Capture before death: old imported bombs can fade or be removed by their
	-- presentation script, so nothing after death is used as a respawn source.
	local state = {
		parent = parent,
		spawnCFrame = model:GetPivot(),
		template = model:Clone(),
		returnsRemaining = returnsRemaining,
		queued = false,
	}
	state.template.Parent = nil
	states[model] = state

	local function scheduleReturn()
		if state.queued or state.returnsRemaining <= 0 then return end
		state.queued = true
		state.returnsRemaining -= 1
		model:SetAttribute(RETURNS_ATTRIBUTE, state.returnsRemaining)

		warn(("[BombRespawn] %s returning in %ds; %d return(s) remain")
			:format(model:GetFullName(), Config.RESPAWN_TIME, state.returnsRemaining))

		task.delay(Config.RESPAWN_TIME, function()
			if not state.parent or not state.parent.Parent then return end

			local replacement = state.template:Clone()
			prepareBomb(replacement, state.returnsRemaining)
			replacement:PivotTo(state.spawnCFrame)
			replacement.Parent = state.parent
			warn(("[BombRespawn] returned: %s"):format(replacement:GetFullName()))
		end)
	end

	-- HealthChanged catches both normal weapon deaths and the existing bomb
	-- explosion script setting Health to zero; no dependence on a particular
	-- Died-event order or on a legacy model-local script.
	humanoid.HealthChanged:Connect(function(health)
		if health <= 0 then
			scheduleReturn()
		end
	end)

	model.Destroying:Connect(function()
		states[model] = nil
	end)
end

for _, item in Workspace:GetDescendants() do
	if item:IsA("Model") then
		registerBomb(item)
	end
end

Workspace.DescendantAdded:Connect(function(item)
	if item:IsA("Model") then
		task.defer(function()
			if item.Parent then registerBomb(item) end
		end)
	end
end)
