local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ZombieAI = require(ServerStorage:WaitForChild("ROBLOX_ZombieAI"))
local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))
local AIUtilities = require(ServerStorage:WaitForChild("ROBLOX_AIUtilities"))

local ZOMBIE_NAME = "Drooling Zombie"
local managed = {}
local brains = {}

-- The coordinator only makes slow, bounded target assignments. It never
-- invents map waypoints or changes a zombie's physical position.

-- Nearby players always win over map-scale flow. This keeps a zombie that can
-- plausibly threaten a player from ignoring them just to satisfy a late-round
-- pressure assignment. Increasing this radius reduces artificial pressure,
-- but also makes the late round less able to pull distant zombies into play.
local PLAYER_OVERRIDE_RADIUS = 80

-- Phase 1 parks the former global pressure experiment. It made a small set of
-- remote zombies share one player target; MonsterWorldDirector will later
-- schedule local centre scenes instead.
local ENABLE_LEGACY_GLOBAL_PRESSURE = false
local PRESSURE_INTERVAL = 20
local MAX_PRESSURE_TOTAL = 6
local MAX_PRESSURE_PER_PLAYER = 2

-- Idle browsing must look alive even in the broad central region. Every search
-- decision gets a different local waypoint, so zombies do not all converge on
-- one point or simply stand still after reaching the centre.
-- Infighting is a rare ambient event: one nearby group of exactly three
-- zombies may harass one non-guardian monster. Low damage lives in
-- MonsterManager; these limits prevent NPCs from clearing the map themselves.
local INFIGHT_CHECK_CHANCE = 0
local INFIGHT_GROUP_SIZE = 3
local INFIGHT_MAX_DISTANCE = 160
local INFIGHT_DURATION = 14

-- These tables hold short-lived map-scale choices. They are cleared/rebuilt by
-- the slow coordinator, not by every individual zombie movement update.
local pressureTargets = {}
local infightTargets = {}

-- The broad central anchor is cached and refreshed only when needed. This
-- avoids repeatedly scanning the map for the same McDonald's marker.

local function rootOf(model)
	local root = model and model:FindFirstChild("HumanoidRootPart", true)
	return root and root:IsA("BasePart") and root or nil
end

local function livingPlayerCharacters()
	local characters = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = rootOf(character)
		if humanoid and humanoid.Health > 0 and root then
			table.insert(characters, character)
		end
	end
	return characters
end

local function hasNearbyPlayer(position, radius)
	for _, character in ipairs(livingPlayerCharacters()) do
		local root = rootOf(character)
		if root and (root.Position - position).Magnitude <= radius then
			return true
		end
	end
	return false
end

local function livingManagedZombies()
	local zombies = {}
	for model in pairs(managed) do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if model.Parent and humanoid and humanoid.Health > 0 and rootOf(model) then
			table.insert(zombies, model)
		end
	end
	return zombies
end

local navigation = {}

function navigation:GetNearbyZombiePositions(model, position, radius)
	local positions = {}
	for _, other in ipairs(livingManagedZombies()) do
		if other ~= model then
			local root = rootOf(other)
			if root and (root.Position - position).Magnitude <= radius then
				table.insert(positions, root.Position)
			end
		end
	end
	return positions
end

function navigation:GetPressureTarget(model)
	local target = pressureTargets[model]
	if target and target.Parent == Workspace then
		return target
	end
	pressureTargets[model] = nil
	return nil
end

function navigation:GetInfightTarget(model)
	local assignment = infightTargets[model]
	local target = assignment and assignment.target
	local humanoid = target and MonsterManager.getMonsterHumanoid(target)
	if assignment and os.clock() < assignment.expiresAt and target and target.Parent == Workspace
		and humanoid and humanoid.Health > 0 then
		return target
	end
	infightTargets[model] = nil
	return nil
end

function navigation:GetGuardianPetRetaliationTarget(model)
	local untilTime = tonumber(model:GetAttribute("WMTGuardianPetRetaliationUntil")) or 0
	if Workspace:GetServerTimeNow() >= untilTime then return nil end
	local marker = model:FindFirstChild("WMTGuardianPetRetaliationTarget")
	local target = marker and marker:IsA("ObjectValue") and marker.Value or nil
	local targetHumanoid = target and MonsterManager.getMonsterHumanoid(target)
	local targetRoot = target and rootOf(target)
	if target and target.Parent and target:GetAttribute("WMTGuardianPet") == true
		and targetHumanoid and targetHumanoid.Health > 0 and targetRoot
	then
		return target
	end
	return nil
end

function navigation:ReportStuck(model)
	local failures = (model:GetAttribute("ZombieStuckFailures") or 0) + 1
	model:SetAttribute("ZombieStuckFailures", failures)
	model:SetAttribute("ZombieStuckAt", Workspace:GetServerTimeNow())

	if failures >= 2 then
		-- A blocked route is recoverable gameplay state, not a dead or stale
		-- monster. Let the AI choose a fresh destination instead of retiring a
		-- healthy zombie and polluting the event feed.
		model:SetAttribute("ZombieStuckFailures", 0)
		return false
	end

	return false
end

function navigation:GetIdleDestination(model, position)
	-- A local walking choice restores visible everyday activity without imposing
	-- a centre quota or pulling any zombie across the map. The imported brain
	-- owns the actual path and may abandon this destination if it is blocked.
	return AIUtilities:FindCloseEmptySpace(model)
end

local function refreshInfightTargets()
	table.clear(infightTargets)
	if math.random() > INFIGHT_CHECK_CHANCE then return end

	local targets = {}
	for _, model in ipairs(Workspace:GetDescendants()) do
		if model:IsA("Model") and MonsterManager.isZombieGroupTarget(model) then
			local humanoid = MonsterManager.getMonsterHumanoid(model)
			local root = rootOf(model)
			if humanoid and humanoid.Health > 0 and root and not hasNearbyPlayer(root.Position, PLAYER_OVERRIDE_RADIUS) then
				table.insert(targets, model)
			end
		end
	end
	if #targets == 0 then return end

	local target = targets[math.random(1, #targets)]
	local targetRoot = rootOf(target)
	if not targetRoot then return end

	local candidates = {}
	for _, zombie in ipairs(livingManagedZombies()) do
		local root = rootOf(zombie)
		if root
			and not hasNearbyPlayer(root.Position, PLAYER_OVERRIDE_RADIUS)
			and (root.Position - targetRoot.Position).Magnitude <= INFIGHT_MAX_DISTANCE
		then
			table.insert(candidates, zombie)
		end
	end
	if #candidates < INFIGHT_GROUP_SIZE then return end

	table.sort(candidates, function(a, b)
		return (rootOf(a).Position - targetRoot.Position).Magnitude < (rootOf(b).Position - targetRoot.Position).Magnitude
	end)
	local expiresAt = os.clock() + INFIGHT_DURATION
	for index = 1, INFIGHT_GROUP_SIZE do
		infightTargets[candidates[index]] = { target = target, expiresAt = expiresAt }
	end
end

local function refreshPressureTargets()
	table.clear(pressureTargets)
	if not ENABLE_LEGACY_GLOBAL_PRESSURE then return end
	local roundStartedAt = tonumber(Workspace:GetAttribute("RoundStartedAt"))
	local elapsed = roundStartedAt and math.max(0, Workspace:GetServerTimeNow() - roundStartedAt) or 0
	local lureFraction = elapsed < 180 and 0
		or elapsed < 420 and 0.10
		or elapsed < 660 and 0.25
		or elapsed < 1020 and 0.40
		or 0.70
	if Workspace:GetAttribute("LateRound") ~= true and lureFraction <= 0 then return end

	local candidates = {}
	for _, zombie in ipairs(livingManagedZombies()) do
		local root = rootOf(zombie)
		if root and not hasNearbyPlayer(root.Position, PLAYER_OVERRIDE_RADIUS) then
			table.insert(candidates, zombie)
		end
	end

	local assigned = 0
	local assignmentLimit = math.min(MAX_PRESSURE_TOTAL, math.floor(#candidates * lureFraction))
	if assignmentLimit <= 0 then return end
	for _, character in ipairs(livingPlayerCharacters()) do
		if assigned >= assignmentLimit then break end
		local targetRoot = rootOf(character)
		if targetRoot then
			table.sort(candidates, function(a, b)
				return (rootOf(a).Position - targetRoot.Position).Magnitude > (rootOf(b).Position - targetRoot.Position).Magnitude
			end)
			for _ = 1, math.min(MAX_PRESSURE_PER_PLAYER, assignmentLimit - assigned) do
				local zombie = table.remove(candidates, 1)
				if not zombie or assigned >= MAX_PRESSURE_TOTAL then break end
				pressureTargets[zombie] = character
				assigned += 1
			end
		end
	end
end

local function disableOldLocalZombieScript(model)
	local oldScript = model:FindFirstChild("Script")

	if oldScript and oldScript:IsA("Script") then
		oldScript.Enabled = false
		oldScript.Disabled = true
	end
end

local function setupZombie(model)
	if not model:IsA("Model") or model.Name ~= ZOMBIE_NAME then return end
	if managed[model] then return end
	if not model:FindFirstChildOfClass("Humanoid") then return end
	if not model:FindFirstChild("HumanoidRootPart") then return end
	if not model:FindFirstChild("Configurations") then return end

	managed[model] = true
	model:SetAttribute("CentralZombieAI", true)
	disableOldLocalZombieScript(model)
	brains[model] = ZombieAI.new(model, navigation)

	model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			local brain = brains[model]
			if brain then brain.Stop() end
			brains[model] = nil
			managed[model] = nil
			pressureTargets[model] = nil
			infightTargets[model] = nil
		end
	end)
end

for _, item in Workspace:GetDescendants() do
	setupZombie(item)
end

Workspace.DescendantAdded:Connect(function(item)
	if item:IsA("Model") then
		task.defer(function()
			setupZombie(item)
		end)
	end
end)

task.spawn(function()
	while true do
		refreshPressureTargets()
		refreshInfightTargets()
		task.wait(PRESSURE_INTERVAL)
	end
end)
