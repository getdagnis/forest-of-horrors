local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))

local VARIANTS = {
	creepyMonster = { damage = 60 },
	creepyMonsterOrange = { damage = 120 },
	creepyMonsterWhite = { damage = 240 },
}

local PLAYER_AGGRO_RANGE = 260
local ATTACK_RANGE = 5
local PLAYER_HIT_COOLDOWN = 1
local MONSTER_HIT_COOLDOWN = 3
local HUNT_CHECK_MIN = 20
local HUNT_CHECK_MAX = 35
local HUNT_CHANCE = 0.10
local HUNT_DURATION = 5
local UPDATE_INTERVAL = 0.25

local managed = {}

local function isCreepy(model)
	return model:IsA("Model") and VARIANTS[model.Name] ~= nil
end

local function getRoot(model)
	local root = model:FindFirstChild("HumanoidRootPart", true)
	return root and root:IsA("BasePart") and root or nil
end

local function disableLegacyScripts(model)
	for _, item in model:GetDescendants() do
		if item:IsA("Script") and (item.Name == "Follow" or item.Name == "Damage Script") then
			item.Disabled = true
		end
	end
end

local function findNearestPlayerRoot(origin)
	local nearestRoot
	local nearestDistance = PLAYER_AGGRO_RANGE

	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and root and humanoid.Health > 0 then
			local distance = (root.Position - origin).Magnitude
			if distance < nearestDistance then
				nearestRoot = root
				nearestDistance = distance
			end
		end
	end

	return nearestRoot
end

local function findLowerHealthMonster(model, ownHp, origin)
	local nearestModel
	local nearestRoot
	local nearestHumanoid
	local nearestDistance = math.huge

	for _, candidate in Workspace:GetDescendants() do
		if candidate:IsA("Model") and candidate ~= model then
			local config = MonsterManager.getConfig(candidate)
			if config and config.hp < ownHp then
				local humanoid = MonsterManager.getMonsterHumanoid(candidate)
				local root = getRoot(candidate)
				if humanoid and root and humanoid.Health > 0 then
					local distance = (root.Position - origin).Magnitude
					if distance < nearestDistance then
						nearestModel = candidate
						nearestRoot = root
						nearestHumanoid = humanoid
						nearestDistance = distance
					end
				end
			end
		end
	end

	return nearestModel, nearestRoot, nearestHumanoid
end

local function setupCreepy(model)
	if not isCreepy(model) or managed[model] then return end

	local humanoid = MonsterManager.getMonsterHumanoid(model)
	local root = getRoot(model)
	local config = MonsterManager.getConfig(model)
	if not humanoid or not root or not config then return end

	disableLegacyScripts(model)
	managed[model] = true
	model:SetAttribute("CentralCreepyAI", true)

	local state = {
		nextHuntCheck = os.clock() + math.random(HUNT_CHECK_MIN, HUNT_CHECK_MAX),
		huntUntil = 0,
		lastPlayerHit = 0,
		lastMonsterHit = 0,
	}
	local damage = VARIANTS[model.Name].damage

	task.spawn(function()
		while model.Parent and humanoid.Parent and humanoid.Health > 0 do
			local now = os.clock()
			if now >= state.nextHuntCheck then
				state.nextHuntCheck = now + math.random(HUNT_CHECK_MIN, HUNT_CHECK_MAX)
				if math.random() < HUNT_CHANCE then
					state.huntUntil = now + HUNT_DURATION
				end
			end

			local playerRoot = findNearestPlayerRoot(root.Position)
			if playerRoot then
				humanoid:MoveTo(playerRoot.Position)
				if (playerRoot.Position - root.Position).Magnitude <= ATTACK_RANGE and now - state.lastPlayerHit >= PLAYER_HIT_COOLDOWN then
					local character = playerRoot.Parent
					local targetHumanoid = character and character:FindFirstChildOfClass("Humanoid")
					if targetHumanoid and targetHumanoid.Health > 0 then
						targetHumanoid:TakeDamage(damage)
						state.lastPlayerHit = now
					end
				end
			elseif now < state.huntUntil then
				local _, targetRoot, targetHumanoid = findLowerHealthMonster(model, config.hp, root.Position)
				if targetRoot and targetHumanoid then
					humanoid:MoveTo(targetRoot.Position)
					if (targetRoot.Position - root.Position).Magnitude <= ATTACK_RANGE and now - state.lastMonsterHit >= MONSTER_HIT_COOLDOWN then
						targetHumanoid:TakeDamage(damage)
						state.lastMonsterHit = now
					end
				end
			end

			task.wait(UPDATE_INTERVAL)
		end

		managed[model] = nil
	end)
end

for _, item in Workspace:GetDescendants() do
	setupCreepy(item)
end

Workspace.DescendantAdded:Connect(function(item)
	if item:IsA("Model") then
		task.defer(setupCreepy, item)
	end
end)
