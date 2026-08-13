-- WeaponSpawnSystem
--
-- This controller deliberately owns only LightSaber pickups.  Other weapons
-- retain their existing systems until they have been audited independently.
-- A spawn point is any BasePart named LightSaberSpawnPoint (optionally with a
-- numeric suffix) or a BasePart with WeaponName = "LightSaber".  Its Studio
-- name is the stable key, so duplicating a spawn point cannot duplicate state.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local templates = ServerStorage:WaitForChild("WeaponTemplates")
local spawnFolder = workspace:WaitForChild("WeaponSpawnPoints")

local WEAPON_NAME = "LightSaber"
local RESPAWN_DELAY = 12
local RECONCILE_RADIUS = 8
local RUNTIME_FOLDER_NAME = "WeaponSpawnSystemRuntime"

-- A second enabled copy of this Script used to double every scheduled spawn.
-- Keep a small server-only lease so an accidental duplicate fails closed.
local runtime = ServerStorage:FindFirstChild(RUNTIME_FOLDER_NAME)
if runtime then
	local owner = runtime:FindFirstChild("Owner")
	if owner and owner:IsA("ObjectValue") and owner.Value and owner.Value ~= script then
		warn("WeaponSpawnSystem is already owned by", owner.Value:GetFullName())
		return
	end
else
	runtime = Instance.new("Folder")
	runtime.Name = RUNTIME_FOLDER_NAME
	runtime.Parent = ServerStorage
end

local owner = runtime:FindFirstChild("Owner") or Instance.new("ObjectValue")
owner.Name = "Owner"
owner.Value = script
owner.Parent = runtime

script.AncestryChanged:Connect(function(_, parent)
	if not parent and runtime.Parent and owner.Value == script then
		runtime:Destroy()
	end
end)

local states = {}

local function isSaberSpawnPoint(spawnPoint)
	return spawnPoint:IsA("BasePart") and (
		spawnPoint:GetAttribute("WeaponName") == WEAPON_NAME
		or string.match(spawnPoint.Name, "^LightSaberSpawnPoint%d*$") ~= nil
	)
end

local function isHeldByPlayer(tool)
	local parent = tool.Parent
	return parent and (
		(parent:IsA("Backpack") and parent.Parent:IsA("Player"))
		or (parent:IsA("Model") and Players:GetPlayerFromCharacter(parent) ~= nil)
	)
end

local function setWorldPhysics(tool)
	for _, item in tool:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.Massless = true
			item.CanTouch = item.Name == "Handle"
		end
	end
end

local function setHeldPhysics(tool)
	for _, item in tool:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = false
			item.CanCollide = false
			item.Massless = true
			-- The Saber damage script listens on the blade and hilt, not just Handle.
			item.CanTouch = true
		end
	end
end

local function getState(spawnPoint)
	-- Spawn-point names are already unique among Workspace siblings.  Unlike a
	-- copied SpawnId attribute, they cannot cause eight copied points to collapse
	-- into one state.
	local spawnKey = spawnPoint.Name
	local state = states[spawnKey]
	if not state then
		state = {
			spawnPoint = spawnPoint,
			spawnKey = spawnKey,
			activeTool = nil,
			respawnScheduled = false,
		}
		states[spawnKey] = state
	elseif state.spawnPoint ~= spawnPoint then
		warn("LightSaber spawn-point name is used more than once:", spawnKey)
		return nil
	end
	return state
end

local function isWorldSaber(tool)
	return tool:IsA("Tool") and tool.Name == WEAPON_NAME and tool:IsDescendantOf(workspace) and not isHeldByPlayer(tool)
end

local function isNearSpawnPoint(tool, spawnPoint)
	local ok, pivot = pcall(function()
		return tool:GetPivot()
	end)
	return ok and (pivot.Position - spawnPoint.Position).Magnitude <= RECONCILE_RADIUS
end

local function findExistingWorldSaber(state)
	for _, instance in workspace:GetDescendants() do
		if isWorldSaber(instance) then
			if instance:GetAttribute("WeaponSpawnKey") == state.spawnKey then
				return instance
			end

			if instance:GetAttribute("WeaponSpawnKey") == nil and isNearSpawnPoint(instance, state.spawnPoint) then
				warn("Legacy LightSaber blocks managed spawn; remove it or add WeaponSpawnKey:", state.spawnPoint:GetFullName())
				return instance
			end
		end
	end
	return nil
end

local scheduleRespawn

local function disableLegacySpawner(tool)
	local legacySpawner = tool:FindFirstChild("SaberSpawner")
	if legacySpawner and legacySpawner:IsA("BaseScript") then
		legacySpawner.Disabled = true
	end
end

local function bindWorldSaber(state, tool)
	state.activeTool = tool
	tool:SetAttribute("WeaponSpawnKey", state.spawnKey)
	setWorldPhysics(tool)

	-- Backup 13 put an independent respawner inside every Saber.  Disable it
	-- defensively for an existing migrated pickup; new templates must omit it.
	disableLegacySpawner(tool)

	tool.AncestryChanged:Connect(function()
		if state.activeTool ~= tool or state.respawnScheduled then return end

		if isHeldByPlayer(tool) then
			-- Remove all anchors before Roblox creates/uses RightGrip.
			setHeldPhysics(tool)
			task.defer(setHeldPhysics, tool)
			state.activeTool = nil
			scheduleRespawn(state)
		elseif not tool.Parent then
			state.activeTool = nil
			scheduleRespawn(state)
		end
	end)
end

scheduleRespawn = function(state, delay)
	if state.respawnScheduled then return end
	state.respawnScheduled = true

	task.delay(delay == nil and RESPAWN_DELAY or delay, function()
		state.respawnScheduled = false
		if state.spawnPoint.Parent then
			local existing = findExistingWorldSaber(state)
			if existing then
				bindWorldSaber(state, existing)
				return
			end

			local template = templates:FindFirstChild(WEAPON_NAME)
			if not template or not template:IsA("Tool") then
				warn("Missing Light Saber Tool template in ServerStorage.WeaponTemplates")
				return
			end

			local tool = template:Clone()
			tool:SetAttribute("ManagedWeaponSpawn", true)
			tool:SetAttribute("WeaponSpawnKey", state.spawnKey)
			tool.CanBeDropped = false
			disableLegacySpawner(tool)
			setWorldPhysics(tool)
			tool:PivotTo(state.spawnPoint.CFrame)
			tool.Parent = workspace
			bindWorldSaber(state, tool)
		end
	end)
end

local function setupSpawnPoint(spawnPoint)
	if not isSaberSpawnPoint(spawnPoint) then
		return
	end

	local state = getState(spawnPoint)
	if not state then return end

	local existing = findExistingWorldSaber(state)
	if existing then
		bindWorldSaber(state, existing)
		return
	end

	scheduleRespawn(state, 0)
end

for _, spawnPoint in spawnFolder:GetChildren() do
	setupSpawnPoint(spawnPoint)
end

spawnFolder.ChildAdded:Connect(function(spawnPoint)
	task.defer(setupSpawnPoint, spawnPoint)
end)
