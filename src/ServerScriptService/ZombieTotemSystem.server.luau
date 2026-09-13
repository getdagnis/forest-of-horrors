local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))
local damageLabelEvent = ReplicatedStorage:FindFirstChild("MonsterDamageLabel")
if not damageLabelEvent then
	damageLabelEvent = Instance.new("RemoteEvent")
	damageLabelEvent.Name = "MonsterDamageLabel"
	damageLabelEvent.Parent = ReplicatedStorage
end
local totemAnnouncementEvent = ReplicatedStorage:FindFirstChild("ZombieTotemDestroyedAnnouncement")
if not totemAnnouncementEvent then
	totemAnnouncementEvent = Instance.new("RemoteEvent")
	totemAnnouncementEvent.Name = "ZombieTotemDestroyedAnnouncement"
	totemAnnouncementEvent.Parent = ReplicatedStorage
end
local totemScoreAward = ReplicatedStorage:FindFirstChild("ZombieTotemScoreAward")
if not totemScoreAward then
	totemScoreAward = Instance.new("BindableEvent")
	totemScoreAward.Name = "ZombieTotemScoreAward"
	totemScoreAward.Parent = ReplicatedStorage
end

-- These are the tested gameplay values; do not replace them with the earlier
-- planning guesses without an explicit playtest decision.
local TOTEM_MAX_HEALTH = 2400
local REGEN_RATE_PER_SECOND = 40
local REGEN_STEP = 1
local BURST_SECONDS = 10

local states = {}

local function findSpawnPoint(pole)
	for _, item in ipairs(Workspace:GetDescendants()) do
		if item:IsA("BasePart") and item.Name == "AppleStoreZombieSpawnPoint"
			and item:GetAttribute("ZombieTotemSpawnPoint") == pole
		then
			return item
		end
	end
	return nil
end

local function scatterAndDestroy(model)
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("JointInstance") or item:IsA("WeldConstraint") or item:IsA("Constraint") then
			item:Destroy()
		end
	end
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") then
			item.Material = Enum.Material.Neon
			item.Color = Color3.fromRGB(255, 70, 140)
			item.Anchored = false
			item.CanTouch = false
			item.CanQuery = false
			item.AssemblyLinearVelocity = Vector3.new(math.random(-30, 30), math.random(20, 45), math.random(-30, 30))
		end
	end
	task.delay(2, function()
		if model.Parent then model:Destroy() end
	end)
end

local function cascadeKill(state)
	local pole = state.pole
	for _, item in ipairs(Workspace:GetDescendants()) do
		if item:IsA("Model") and item:GetAttribute("ZombieTotemSpawnOwner") == pole then
			local humanoid = MonsterManager.getMonsterHumanoid(item)
			if humanoid and humanoid.Health > 0 then
				item:SetAttribute("TotemCascadeKill", true)
				item:SetAttribute("NoAutoRespawn", true)
				humanoid:SetAttribute("PermanentMonsterKill", true)
				humanoid.Health = 0
			end
		end
	end
end

local function destroyTotem(state)
	if state.destroyed then return end
	state.destroyed = true
	local attackerId = tonumber(state.model:GetAttribute("TotemLastAttackerId"))
	local attacker = attackerId and Players:GetPlayerByUserId(attackerId)
	if attacker then
		totemScoreAward:Fire(attacker, 10, Workspace:GetAttribute("RoundGeneration"),
			state.model:GetAttribute("TotemLastWeapon"), state.model, state.model:GetAttribute("TotemLastScoreColor"))
	end
	if state.spawnPoint then
		state.spawnPoint:SetAttribute("ZombieTotemDestroyed", true)
		state.spawnPoint:SetAttribute("ZombieTotemBurstUntil", nil)
	end
	cascadeKill(state)
	local sound = SoundService:FindFirstChild("ZombieTotemDestroyed", true)
	if sound and sound:IsA("Sound") then
		local clone = sound:Clone()
		clone.Looped = false
		clone.Parent = SoundService
		clone:Play()
		Debris:AddItem(clone, math.max(3, clone.TimeLength + 1))
	end
	totemAnnouncementEvent:FireAllClients(state.pole, Workspace:GetAttribute("RoundGeneration"))
	if state.pole == "Apple" then
		for _, item in ipairs(Workspace:GetDescendants()) do
			if item:GetAttribute("AppleTotemLight") == true then
				item:Destroy()
			end
		end
	end
	scatterAndDestroy(state.model)
end

local function awardDamageThresholds(model)
	local rewardUnits = math.max(0, math.floor(tonumber(model:GetAttribute("TotemDamageRewardDelta")) or 0))
	if rewardUnits <= 0 then return end
	local attackerId = tonumber(model:GetAttribute("TotemLastAttackerId"))
	local attacker = attackerId and Players:GetPlayerByUserId(attackerId)
	if attacker then
		totemScoreAward:Fire(attacker, rewardUnits, Workspace:GetAttribute("RoundGeneration"),
			model:GetAttribute("TotemLastWeapon"), model, model:GetAttribute("TotemLastScoreColor"))
	end
	model:SetAttribute("TotemDamageRewardDelta", 0)
end

local function setup(model)
	if not MonsterManager.isZombieTotem(model) or states[model] then return end
	local pole = model:GetAttribute("ZombieTotemPole")
	local spawnPoint = findSpawnPoint(pole)
	local state = { model = model, pole = pole, spawnPoint = spawnPoint, destroyed = false }
	states[model] = state
	model:SetAttribute("TotemMaxHealth", TOTEM_MAX_HEALTH)
	model:SetAttribute("TotemDamageDealt", 0)
	model:SetAttribute("TotemDamageRewardDelta", 0)
	if tonumber(model:GetAttribute("TotemHealth")) == nil then model:SetAttribute("TotemHealth", TOTEM_MAX_HEALTH) end
	if spawnPoint then spawnPoint:SetAttribute("ZombieTotemDestroyed", false) end
	model:GetAttributeChangedSignal("TotemHealth"):Connect(function()
		if state.destroyed then return end
		local health = tonumber(model:GetAttribute("TotemHealth")) or 0
		local lastDamageAt = tonumber(model:GetAttribute("TotemLastDamageAt")) or 0
		if spawnPoint and Workspace:GetServerTimeNow() - lastDamageAt < 0.25 then
			spawnPoint:SetAttribute("ZombieTotemBurstUntil", Workspace:GetServerTimeNow() + BURST_SECONDS)
		end
		if Workspace:GetServerTimeNow() - lastDamageAt < 0.25 then
			awardDamageThresholds(model)
			if health <= 0 then destroyTotem(state) return end
			local attackerId = tonumber(model:GetAttribute("TotemLastAttackerId"))
			local attacker = attackerId and Players:GetPlayerByUserId(attackerId)
			if attacker then
				damageLabelEvent:FireClient(attacker, model, health, TOTEM_MAX_HEALTH, Workspace:GetAttribute("RoundGeneration"))
			end
		end
	end)
	task.spawn(function()
		while model.Parent and not state.destroyed do
			task.wait(REGEN_STEP)
			if Workspace:GetAttribute("RoundState") == "Active" then
				local health = tonumber(model:GetAttribute("TotemHealth")) or 0
				if health > 0 and health < TOTEM_MAX_HEALTH then
					model:SetAttribute("TotemHealth", math.min(TOTEM_MAX_HEALTH, health + REGEN_RATE_PER_SECOND * REGEN_STEP))
				end
			end
		end
	end)
end

for _, item in ipairs(Workspace:GetDescendants()) do if item:IsA("Model") then setup(item) end end
Workspace.DescendantAdded:Connect(function(item) if item:IsA("Model") then task.defer(setup, item) end end)
