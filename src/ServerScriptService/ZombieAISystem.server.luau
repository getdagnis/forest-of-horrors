local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ZombieAI = require(ServerStorage:WaitForChild("ROBLOX_ZombieAI"))
local MonsterManager = require(ReplicatedStorage:WaitForChild("MonsterManager"))

local ZOMBIE_NAME = "Drooling Zombie"
local managed = {}
local brains = {}

-- All map-scale decisions are deliberately slow.  The per-zombie module only
-- asks for a waypoint occasionally, so this never becomes a crowd hot loop.
local CENTER_RADIUS = 200
local PLAYER_OVERRIDE_RADIUS = 80
local APPLE_INDOOR_RADIUS = 45
local APPLE_NEARBY_RADIUS = 120
local MAX_APPLE_INDOOR = 4
local MAX_APPLE_NEARBY = 12
local PRESSURE_INTERVAL = 20
local MAX_PRESSURE_TOTAL = 6
local MAX_PRESSURE_PER_PLAYER = 2
local pressureTargets = {}
local appleAssignments = {}
local cachedMcDonaldsCenter = nil
local cachedAppleCenter = nil
local nextAnchorRefresh = 0

local function rootOf(model)
	local root = model and model:FindFirstChild("HumanoidRootPart")
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
		cachedAppleCenter = findNavigationAnchor("ZombieAppleCenter", { "Apple Center", "AppleCenter", "Apple" })
		nextAnchorRefresh = time() + 60
	end
	return cachedMcDonaldsCenter, cachedAppleCenter
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
		appleAssignments[model] = nil
		return nil
	end

	local mcdonaldsCenter, appleCenter = getAnchors()
	if appleCenter then
		local indoor, nearby = 0, 0
		for _, zombie in ipairs(livingManagedZombies()) do
			local root = rootOf(zombie)
			if root then
				local distance = (root.Position - appleCenter).Magnitude
				if distance <= APPLE_NEARBY_RADIUS then nearby += 1 end
				if distance <= APPLE_INDOOR_RADIUS then indoor += 1 end
			end
		end

		local assignment = appleAssignments[model]
		if assignment == "indoor" or (not assignment and indoor < MAX_APPLE_INDOOR) then
			appleAssignments[model] = "indoor"
			return appleCenter + randomFlatOffset(8, APPLE_INDOOR_RADIUS - 5)
		elseif assignment == "nearby" or (not assignment and nearby < MAX_APPLE_NEARBY) then
			appleAssignments[model] = "nearby"
			return appleCenter + randomFlatOffset(APPLE_INDOOR_RADIUS + 10, APPLE_NEARBY_RADIUS - 10)
		end
	end

	appleAssignments[model] = nil
	if not mcdonaldsCenter or (position - mcdonaldsCenter).Magnitude <= CENTER_RADIUS then
		return nil
	end

	-- A 6-14 stud centreward step every 12+ seconds makes this background flow,
	-- not a rush: typical map distances take roughly 10-30 minutes to converge.
	local towardCenter = mcdonaldsCenter - position
	local flat = Vector3.new(towardCenter.X, 0, towardCenter.Z)
	if flat.Magnitude < 1 then return nil end
	local sideways = Vector3.new(-flat.Z, 0, flat.X).Unit * math.random(-8, 8)
	return position + flat.Unit * math.random(6, 14) + sideways
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
			appleAssignments[model] = nil
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
		task.wait(PRESSURE_INTERVAL)
	end
end)
