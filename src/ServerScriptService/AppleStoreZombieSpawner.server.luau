-- AppleStoreZombieSpawner > ServerScriptService
--
-- Add a BasePart named AppleStoreZombieSpawnPoint anywhere beneath Workspace.
-- Its top face is the spawn area. New zombies are introduced every 15 seconds
-- while the round is active and the broad living-monster safety cap permits it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))

local SPAWN_POINT_NAME = "AppleStoreZombieSpawnPoint"
local ZOMBIE_NAME = "Drooling Zombie"
local SPAWN_INTERVAL = 30
local BURST_INTERVAL = 5
local MAX_LIVING_MONSTERS = 120
local STOP_SPAWNING_AT_OR_BELOW = 25
local DEFAULT_HEIGHT_OFFSET = 2
local DEFAULT_SPAWN_RADIUS = 20 -- studs; random horizontal offset from spawn point center
local NO_SPAWN_WINDOW_SECONDS = 12 * 60 -- no zombie spawning in the final 12 minutes

local function isInNoSpawnWindow()
	if Workspace:GetAttribute("GameStopped") == true then return true end
	local endsAt = tonumber(Workspace:GetAttribute("RoundEndsAt"))
	if not endsAt then return false end
	return Workspace:GetServerTimeNow() >= endsAt - NO_SPAWN_WINDOW_SECONDS
end

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

	local template = ServerStorage:FindFirstChild("MonsterTemplates")
		and ServerStorage.MonsterTemplates:FindFirstChild("Drooling Zombie")
	if template and template:IsA("Model") then
		zombieTemplate = template:Clone()
		zombieTemplate.Parent = nil
		return zombieTemplate
	end

	return nil
end

local function getSpawnCFrame(spawnPoint)
	local height = tonumber(spawnPoint:GetAttribute("SpawnHeight")) or DEFAULT_HEIGHT_OFFSET
	local radius = tonumber(spawnPoint:GetAttribute("SpawnRadius")) or DEFAULT_SPAWN_RADIUS
	-- Pick a random point within a circle of the given radius around the spawn point.
	local angle = math.random() * math.pi * 2
	local distance = math.sqrt(math.random()) * radius -- uniform distribution across the disc
	local offsetX = math.cos(angle) * distance
	local offsetZ = math.sin(angle) * distance
	return spawnPoint.CFrame * CFrame.new(offsetX, spawnPoint.Size.Y * 0.5 + height, offsetZ)
end

local function spawnZombie(spawnPoint)
	if Workspace:GetAttribute("RoundActive") == false or Workspace:GetAttribute("UndergroundPhaseActive") == true then return end
	if spawnPoint:GetAttribute("ZombieTotemDestroyed") == true then return end
	if isInNoSpawnWindow() then return end
	local burst = (tonumber(spawnPoint:GetAttribute("ZombieTotemBurstUntil")) or 0) > Workspace:GetServerTimeNow()
	local livingCount = countLivingMonsters()
	-- The late-round population is intentionally allowed to shrink. Do not
	-- refill the last twenty canonical hostile contacts from this generator.
	if not burst and (livingCount <= STOP_SPAWNING_AT_OR_BELOW or livingCount >= MAX_LIVING_MONSTERS) then return end

	local template = findZombieTemplate()
	if not template then
		warn("[AppleStoreZombieSpawner] ServerStorage.MonsterTemplates.DroolingZombie is not available as a template")
		return
	end

	local zombie = template:Clone()
	-- The template lives in ServerStorage as "Drooling Zombie" but every game
	-- system (MonsterManager, ZombieAISystem, MonsterSystem) keys on the exact
	-- name "DroolingZombie (with a space).  Rename the clone so it is
	-- recognised as a real monster and receives AI, HP, and lifecycle tracking.
	zombie.Name = ZOMBIE_NAME
	-- Continuous generator output receives one life. It must not enlarge the
	-- round-restart template list or recursively enter the normal respawn pool.
	zombie:SetAttribute("AppleStoreSpawned", true)
	zombie:SetAttribute("NoAutoRespawn", true)
	local owner = spawnPoint:GetAttribute("ZombieTotemSpawnPoint")
	if typeof(owner) == "string" and owner ~= "" then zombie:SetAttribute("ZombieTotemSpawnOwner", owner) end
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
		local generation = tonumber(Workspace:GetAttribute("RoundGeneration"))
		local nextSpawnAt = Workspace:GetServerTimeNow() + SPAWN_INTERVAL
		while spawnPoint.Parent and spawnPoint:IsDescendantOf(Workspace) do
			local now = Workspace:GetServerTimeNow()
			local burst = (tonumber(spawnPoint:GetAttribute("ZombieTotemBurstUntil")) or 0) > now
			if burst and nextSpawnAt > now + BURST_INTERVAL then nextSpawnAt = now + BURST_INTERVAL end
			if now >= nextSpawnAt and Workspace:GetAttribute("RoundActive") == true then
				spawnZombie(spawnPoint)
				burst = (tonumber(spawnPoint:GetAttribute("ZombieTotemBurstUntil")) or 0) > Workspace:GetServerTimeNow()
				nextSpawnAt = Workspace:GetServerTimeNow() + (burst and BURST_INTERVAL or SPAWN_INTERVAL)
			end
			generation = tonumber(Workspace:GetAttribute("RoundGeneration"))
			task.wait(0.5)
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
