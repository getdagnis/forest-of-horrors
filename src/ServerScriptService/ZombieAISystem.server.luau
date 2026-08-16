local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ZombieAI = require(ServerStorage:WaitForChild("ROBLOX_ZombieAI"))
local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))

local ZOMBIE_NAME = "Drooling Zombie"
local managed = {}
local brains = {}

-- All map-scale decisions are deliberately slow. The per-zombie module only
-- asks for a waypoint occasionally, so this never becomes a crowd hot loop.
--
-- Central flow: zombies outside this radius take small, indirect steps toward
-- the broad McDonald's area. Once inside it, they browse locally rather than
-- piling onto one exact point. Raising CENTER_RADIUS makes that relaxed region
-- larger; lowering it keeps more zombies travelling inward.
local CENTER_RADIUS = 200

-- Nearby players always win over map-scale flow. This keeps a zombie that can
-- plausibly threaten a player from ignoring them just to satisfy a late-round
-- pressure assignment. Increasing this radius reduces artificial pressure,
-- but also makes the late round less able to pull distant zombies into play.
local PLAYER_OVERRIDE_RADIUS = 80

-- Late-round pressure is reassigned infrequently and capped globally/per
-- player. This adds urgency after the crowd thins without turning every zombie
-- into an immediate swarm or creating a repeated all-zombies scan every frame.
local PRESSURE_INTERVAL = 20
local MAX_PRESSURE_TOTAL = 6
local MAX_PRESSURE_PER_PLAYER = 2

-- Idle browsing must look alive even in the broad central region. Every search
-- decision gets a different local waypoint, so zombies do not all converge on
-- one point or simply stand still after reaching the centre.
local IDLE_WANDER_MIN_DISTANCE = 18
local IDLE_WANDER_MAX_DISTANCE = 55

-- Infighting is a rare ambient event: one nearby group of exactly three
-- zombies may harass one non-guardian monster. Low damage lives in
-- MonsterManager; these limits prevent NPCs from clearing the map themselves.
local INFIGHT_CHECK_CHANCE = 0.35
local INFIGHT_GROUP_SIZE = 3
local INFIGHT_MAX_DISTANCE = 160
local INFIGHT_DURATION = 14

-- These tables hold short-lived map-scale choices. They are cleared/rebuilt by
-- the slow coordinator, not by every individual zombie movement update.
local pressureTargets = {}
local infightTargets = {}

-- The broad central anchor is cached and refreshed only when needed. This
-- avoids repeatedly scanning the map for the same McDonald's marker.
local cachedMcDonaldsCenter = nil
local nextAnchorRefresh = 0

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

local function findNavigationAnchor(attributeName, names)
	for _, instance in ipairs(Workspace:GetDescendants()) do
		if instance:GetAttribute(attributeName) == true then
			if instance:IsA("BasePart") then return instance.Position end
			if instance:IsA("Model") then return instance:GetPivot().Position end
		end
	end

	for _, name in ipairs(names) do
		local instance = Workspace:FindFirstChild(name, true)
		if instance then
			if instance:IsA("BasePart") then return instance.Position end
			if instance:IsA("Model") then return instance:GetPivot().Position end
		end
	end

	return nil
end

local function getAnchors()
	if time() >= nextAnchorRefresh then
		cachedMcDonaldsCenter = findNavigationAnchor("ZombieMcDonaldsCenter", { "McDonalds", "McDonald's", "McDonald" })
		nextAnchorRefresh = time() + 60
	end
	return cachedMcDonaldsCenter
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

local function randomFlatOffset(minRadius, maxRadius)
	local angle = math.random() * math.pi * 2
	local radius = minRadius + math.random() * (maxRadius - minRadius)
	return Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
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

function navigation:ReportStuck(model)
	local failures = (model:GetAttribute("ZombieStuckFailures") or 0) + 1
	model:SetAttribute("ZombieStuckFailures", failures)
	model:SetAttribute("ZombieStuckAt", Workspace:GetServerTimeNow())

	if failures >= 2 then
		model:SetAttribute("MonsterRetireRequested", true)
		model:SetAttribute("MonsterRetirementReason", "ZombieUnreachable")
		return true
	end

	return false
end

function navigation:GetIdleDestination(model, position)
	-- Real nearby players always win over ambient map movement.
	if hasNearbyPlayer(position, PLAYER_OVERRIDE_RADIUS) then
		return nil
	end

	local mcdonaldsCenter = getAnchors()
	if not mcdonaldsCenter or (position - mcdonaldsCenter).Magnitude <= CENTER_RADIUS then
		-- Different random local destinations make the central region feel browsed
		-- rather than empty, without using any player-directed global lure.
		return position + randomFlatOffset(IDLE_WANDER_MIN_DISTANCE, IDLE_WANDER_MAX_DISTANCE)
	end

	-- A 6-14 stud centreward step every 12+ seconds makes this background flow,
	-- not a rush: typical map distances take roughly 10-30 minutes to converge.
	local towardCenter = mcdonaldsCenter - position
	local flat = Vector3.new(towardCenter.X, 0, towardCenter.Z)
	if flat.Magnitude < 1 then return nil end
	local sideways = Vector3.new(-flat.Z, 0, flat.X).Unit * math.random(-8, 8)
	return position + flat.Unit * math.random(6, 14) + sideways
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

local function isLateRound()
	if Workspace:GetAttribute("LateRound") == true then return true end
	local maximum = Workspace:GetAttribute("MonsterMaxCount") or 90
	if maximum <= 0 then return false end

	local alive = 0
	for _, instance in ipairs(Workspace:GetDescendants()) do
		if instance:IsA("Model") and MonsterManager.getConfig(instance) then
			local humanoid = MonsterManager.getMonsterHumanoid(instance)
			if humanoid and humanoid.Health > 0 then alive += 1 end
		end
	end
	return alive <= math.floor(maximum * 0.25)
end

local function refreshPressureTargets()
	table.clear(pressureTargets)
	if not isLateRound() then return end

	local candidates = {}
	for _, zombie in ipairs(livingManagedZombies()) do
		local root = rootOf(zombie)
		if root and not hasNearbyPlayer(root.Position, PLAYER_OVERRIDE_RADIUS) then
			table.insert(candidates, zombie)
		end
	end

	local assigned = 0
	for _, character in ipairs(livingPlayerCharacters()) do
		if assigned >= MAX_PRESSURE_TOTAL then break end
		local targetRoot = rootOf(character)
		if targetRoot then
			table.sort(candidates, function(a, b)
				return (rootOf(a).Position - targetRoot.Position).Magnitude > (rootOf(b).Position - targetRoot.Position).Magnitude
			end)
			for _ = 1, MAX_PRESSURE_PER_PLAYER do
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
