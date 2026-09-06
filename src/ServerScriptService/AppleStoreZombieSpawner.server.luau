-- AppleStoreZombieSpawner > ServerScriptService
--
-- Add a BasePart named AppleStoreZombieSpawnPoint anywhere beneath Workspace.
-- Its top face is the spawn area. New zombies are introduced every 15 seconds
-- while the round is active and the broad living-monster safety cap permits it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))

local SPAWN_POINT_NAME = "AppleStoreZombieSpawnPoint"
local ZOMBIE_NAME = "Drooling Zombie"
local SPAWN_INTERVAL = 15
local MAX_LIVING_MONSTERS = 150
local STOP_SPAWNING_AT_OR_BELOW = 20
local DEFAULT_HEIGHT_OFFSET = 3

local activeSpawnPoints = {}
local zombieTemplate

local function getLivingHumanoid(model)
	local humanoid = MonsterManager.getMonsterHumanoid(model)
	return humanoid and humanoid.Health > 0 and humanoid or nil
end

local function countLivingMonsters()
	local count = 0
	for _, instance in Workspace:GetDescendants() do
		if instance:IsA("Model")
			and MonsterManager.isRoundTracked(instance)
			and getLivingHumanoid(instance)
		then
			count += 1
		end
	end
	return count
end

local function findZombieTemplate()
	if zombieTemplate then return zombieTemplate end

	for _, instance in Workspace:GetDescendants() do
		if instance:IsA("Model")
			and instance.Name == ZOMBIE_NAME
			and not instance:GetAttribute("AppleStoreSpawned")
			and MonsterManager.getConfig(instance)
		then
			zombieTemplate = instance:Clone()
			zombieTemplate.Parent = nil
			return zombieTemplate
		end
	end

	return nil
end

local function getSpawnCFrame(spawnPoint)
	local height = tonumber(spawnPoint:GetAttribute("SpawnHeight")) or DEFAULT_HEIGHT_OFFSET
	-- The marker is deliberately the exact authored interior point. A random
	-- offset across its old footprint could put a new zombie beyond a shop wall.
	return spawnPoint.CFrame * CFrame.new(0, spawnPoint.Size.Y * 0.5 + height, 0)
end

local function spawnZombie(spawnPoint)
	if Workspace:GetAttribute("RoundActive") == false then return end
	local livingCount = countLivingMonsters()
	-- The late-round population is intentionally allowed to shrink. Do not
	-- refill the last twenty canonical hostile contacts from this generator.
	if livingCount <= STOP_SPAWNING_AT_OR_BELOW or livingCount >= MAX_LIVING_MONSTERS then return end

	local template = findZombieTemplate()
	if not template then
		warn("[AppleStoreZombieSpawner] no live Drooling Zombie is available as a template")
		return
	end

	local zombie = template:Clone()
	-- Continuous generator output receives one life. It must not enlarge the
	-- round-restart template list or recursively enter the normal respawn pool.
	zombie:SetAttribute("AppleStoreSpawned", true)
	zombie:SetAttribute("NoAutoRespawn", true)
	zombie:PivotTo(getSpawnCFrame(spawnPoint))
	zombie.Parent = Workspace
end

local function startSpawnPoint(spawnPoint)
	if not spawnPoint:IsA("BasePart") or spawnPoint.Name ~= SPAWN_POINT_NAME then return end
	if activeSpawnPoints[spawnPoint] then return end
	activeSpawnPoints[spawnPoint] = true

	task.spawn(function()
		-- Stagger startup so the central monster and zombie owners can register the
		-- original population before the first generated zombie enters Workspace.
		task.wait(SPAWN_INTERVAL)
		while spawnPoint.Parent and spawnPoint:IsDescendantOf(Workspace) do
			spawnZombie(spawnPoint)
			task.wait(SPAWN_INTERVAL)
		end
		activeSpawnPoints[spawnPoint] = nil
	end)
end

for _, instance in Workspace:GetDescendants() do
	startSpawnPoint(instance)
end

Workspace.DescendantAdded:Connect(function(instance)
	startSpawnPoint(instance)
end)
