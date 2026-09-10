local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))

local ZOMBIE_NAME = "Drooling Zombie"
local LADDER_NAME = "Pool Ladder"
local SPAWN_INTERVAL = 60
local MAX_MONSTERS = 150
local STOP_SPAWNING_AT_OR_BELOW = 25

local SIDE_OFFSET = 5
local BACK_OFFSET = 4
local HEIGHT_OFFSET = 3
local RANDOM_JITTER = 2
local NO_SPAWN_WINDOW_SECONDS = 12 * 60 -- no zombie spawning in the final 12 minutes

local function isInNoSpawnWindow()
	if Workspace:GetAttribute("GameStopped") == true then return true end
	local endsAt = tonumber(Workspace:GetAttribute("RoundEndsAt"))
	if not endsAt then return false end
	return Workspace:GetServerTimeNow() >= endsAt - NO_SPAWN_WINDOW_SECONDS
end

local connectedLadders = {}
local zombieTemplate = nil

local function isMonsterAlive(model)
	local humanoid = MonsterManager.getMonsterHumanoid(model)
	return humanoid and humanoid.Health > 0
end

local function countLivingMonsters()
	local count = 0

	for _, item in Workspace:GetDescendants() do
		if item:IsA("Model")
			and MonsterManager.isRoundTracked(item)
			and isMonsterAlive(item)
		then
			count += 1
		end
	end

	return count
end

local function countNonLavaLivingMonsters()
	local count = 0

	for _, item in Workspace:GetDescendants() do
		if item:IsA("Model")
			and not item:GetAttribute("LavaPoolSpawned")
			and MonsterManager.isRoundTracked(item)
			and isMonsterAlive(item)
		then
			count += 1
		end
	end

	return count
end

local function findZombieTemplate()
	if zombieTemplate then
		return zombieTemplate
	end

	for _, item in Workspace:GetDescendants() do
		if item:IsA("Model") and item.Name == ZOMBIE_NAME and MonsterManager.getConfig(item) then
			zombieTemplate = item:Clone()
			zombieTemplate.Parent = nil
			return zombieTemplate
		end
	end

	warn("LavaPoolZombieSpawner could not find a zombie template named", ZOMBIE_NAME)
	return nil
end

local function getSpawnCFrame(ladder)
	local pivot = ladder:GetPivot()
	local side = math.random(0, 1) == 0 and -1 or 1
	local jitterX = math.random(-RANDOM_JITTER, RANDOM_JITTER)
	local jitterZ = math.random(-RANDOM_JITTER, RANDOM_JITTER)

	return pivot
		* CFrame.new(side * SIDE_OFFSET + jitterX, HEIGHT_OFFSET, BACK_OFFSET + jitterZ)
end

local function spawnZombieAtLadder(ladder)
	if Workspace:GetAttribute("RoundActive") == false or Workspace:GetAttribute("UndergroundPhaseActive") == true then return end
	if isInNoSpawnWindow() then return end
	local livingCount = countLivingMonsters()
	if livingCount <= STOP_SPAWNING_AT_OR_BELOW or livingCount >= MAX_MONSTERS then
		return
	end

	if countNonLavaLivingMonsters() <= 0 then
		return
	end

	local template = findZombieTemplate()
	if not template then
		return
	end

	local zombie = template:Clone()
	zombie:SetAttribute("LavaPoolSpawned", true)
	zombie:SetAttribute("NoAutoRespawn", true)
	zombie:PivotTo(getSpawnCFrame(ladder))
	zombie.Parent = Workspace
end

local function connectLadder(ladder)
	if connectedLadders[ladder] then return end
	if not ladder:IsA("Model") or ladder.Name ~= LADDER_NAME then return end

	connectedLadders[ladder] = true

	task.spawn(function()
		task.wait(math.random(1, SPAWN_INTERVAL))

		while ladder.Parent do
			spawnZombieAtLadder(ladder)
			task.wait(SPAWN_INTERVAL)
		end

		connectedLadders[ladder] = nil
	end)
end

findZombieTemplate()

for _, item in Workspace:GetDescendants() do
	connectLadder(item)
end

Workspace.DescendantAdded:Connect(function(item)
	connectLadder(item)
end)
