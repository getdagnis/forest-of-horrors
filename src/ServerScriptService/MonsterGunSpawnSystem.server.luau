-- GunSpawnSystem
-- Optional world pickups for MonsterGun, MonsterGun2, and MonsterGun3.
-- A BasePart in Workspace.WeaponSpawnPoints opts in with WeaponName set to one
-- of those names.  Legacy MonsterGunSpawnPoint names remain supported.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local templates = ServerStorage:WaitForChild("WeaponTemplates")
local WEAPONS = {
	MonsterGun = true,
	MonsterGun2 = true,
	MonsterGun3 = true,
}
local RESPAWN_DELAY = 12
local RECONCILE_RADIUS = 8
local RECONCILE_INTERVAL = 1
local states = {}
local observedSpawnFolders = {}

local function getWeaponName(spawnPoint)
	local attributed = spawnPoint:GetAttribute("WeaponName")
	if type(attributed) == "string" and WEAPONS[attributed] then
		return attributed
	end

	for weaponName in pairs(WEAPONS) do
		if string.match(spawnPoint.Name, "^" .. weaponName .. "SpawnPoint%d*$") then
			return weaponName
		end
	end
	return nil
end

local function isHeldByPlayer(tool)
	local parent = tool.Parent
	return parent and (
		(parent:IsA("Backpack") and parent.Parent:IsA("Player"))
		or (parent:IsA("Model") and Players:GetPlayerFromCharacter(parent) ~= nil)
	)
end

local function hasJoint(tool, first, second)
	for _, item in tool:GetDescendants() do
		if item:IsA("WeldConstraint") or item:IsA("Weld") or item:IsA("Motor6D") then
			if (item.Part0 == first and item.Part1 == second) or (item.Part0 == second and item.Part1 == first) then
				return true
			end
		end
	end
	return false
end

local function prepareTool(tool, held)
	local legacyAnchor = tool:FindFirstChild("AnchorScript")
	if legacyAnchor and legacyAnchor:IsA("BaseScript") then
		legacyAnchor.Disabled = true
	end

	for _, item in tool:GetDescendants() do
		if item:IsA("BaseScript") and (item.Name == "ClientScript" or item.Name == "Crosshair" or item.Name == "WeaponCrosshairClient" or item.Name == "MonsterGunClient") then
			item.Disabled = true
		end
	end

	local handle = tool:FindFirstChild("Handle", true)
	if not handle or not handle:IsA("BasePart") then
		warn("Gun template needs a BasePart named Handle:", tool:GetFullName())
		return false
	end

	for _, item in tool:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = not held
			item.CanCollide = false
			item.CanTouch = not held and item == handle
			item.Massless = true
			if item ~= handle and not hasJoint(tool, handle, item) then
				local weld = Instance.new("WeldConstraint")
				weld.Name = "GunAssemblyWeld"
				weld.Part0 = handle
				weld.Part1 = item
				weld.Parent = handle
			end
		end
	end
	return true
end

local function getState(spawnPoint, weaponName)
	local state = states[spawnPoint]
	if not state then
		state = {
			spawnPoint = spawnPoint,
			weaponName = weaponName,
			activeTool = nil,
			respawnScheduled = false,
		}
		states[spawnPoint] = state
	end
	return state
end

local function findExistingGun(state)
	for _, item in workspace:GetDescendants() do
		if item:IsA("Tool") and item.Name == state.weaponName and not isHeldByPlayer(item) then
			local ok, pivot = pcall(function()
				return item:GetPivot()
			end)
			if ok and (pivot.Position - state.spawnPoint.Position).Magnitude <= RECONCILE_RADIUS then
				return item
			end
		end
	end
	return nil
end

local scheduleRespawn

local function bindWorldGun(state, tool)
	if state.activeTool == tool then return end
	state.activeTool = tool
	if not prepareTool(tool, false) then return end

	tool.AncestryChanged:Connect(function()
		if state.activeTool ~= tool or state.respawnScheduled then return end
		local held = isHeldByPlayer(tool)
		if held then
			-- Do this immediately so RightGrip never carries the anchored pickup.
			prepareTool(tool, true)
		end
		task.defer(function()
			if state.activeTool ~= tool or state.respawnScheduled then return end
			-- WeaponInventoryGuard may consume the incoming MG2 while promoting MG1
			-- in place. Treat that destroyed pickup exactly like a normal transfer.
			if not isHeldByPlayer(tool) and tool.Parent and tool:IsDescendantOf(workspace) then return end
			state.activeTool = nil
			scheduleRespawn(state)
		end)
	end)
end

scheduleRespawn = function(state, delay)
	if state.respawnScheduled then return end
	state.respawnScheduled = true

	task.delay(delay == nil and RESPAWN_DELAY or delay, function()
		state.respawnScheduled = false
		if not state.spawnPoint.Parent or not state.spawnPoint:IsDescendantOf(workspace) then
			states[state.spawnPoint] = nil
			return
		end

		local existing = findExistingGun(state)
		if existing then
			bindWorldGun(state, existing)
			return
		end

		local template = templates:FindFirstChild(state.weaponName)
		if not template or not template:IsA("Tool") then
			warn("Missing Gun Tool template in ServerStorage.WeaponTemplates:", state.weaponName)
			return
		end

		local tool = template:Clone()
		tool.CanBeDropped = false
		if not prepareTool(tool, false) then
			tool:Destroy()
			return
		end
		tool:PivotTo(state.spawnPoint.CFrame)
		tool.Parent = workspace
		bindWorldGun(state, tool)
	end)
end

local function setupSpawnPoint(spawnPoint)
	if not spawnPoint:IsA("BasePart") then return end
	local weaponName = getWeaponName(spawnPoint)
	if not weaponName then return end
	local state = getState(spawnPoint, weaponName)
	local existing = findExistingGun(state)
	if existing then
		bindWorldGun(state, existing)
	else
		scheduleRespawn(state, 0)
	end
end

local function observeSpawnFolder(folder)
	if observedSpawnFolders[folder] then return end
	observedSpawnFolders[folder] = true
	for _, descendant in folder:GetDescendants() do
		setupSpawnPoint(descendant)
	end
	folder.DescendantAdded:Connect(function(descendant)
		task.defer(setupSpawnPoint, descendant)
	end)
end

-- Spawn folders are allowed inside map buildings as well as directly under
-- Workspace. Search all existing descendants and watch future additions so a
-- nested MG2/MG3 point is not silently ignored.
for _, instance in workspace:GetDescendants() do
	if instance.Name == "WeaponSpawnPoints" and (instance:IsA("Folder") or instance:IsA("Model")) then
		observeSpawnFolder(instance)
	end
end

workspace.DescendantAdded:Connect(function(instance)
	if instance.Name == "WeaponSpawnPoints" and (instance:IsA("Folder") or instance:IsA("Model")) then
		observeSpawnFolder(instance)
	end
end)

-- Default pickup transfer and in-place tier promotion can happen within one
-- scheduler turn. This bounded watchdog repairs a missed ancestry transition
-- without creating a second spawn owner or duplicating an available world gun.
task.spawn(function()
	while true do
		task.wait(RECONCILE_INTERVAL)
		for spawnPoint, state in pairs(states) do
			if not spawnPoint.Parent or not spawnPoint:IsDescendantOf(workspace) then
				states[spawnPoint] = nil
			elseif not state.respawnScheduled then
				local activeTool = state.activeTool
				local available = activeTool
					and activeTool.Parent
					and activeTool:IsDescendantOf(workspace)
					and not isHeldByPlayer(activeTool)
				if not available then
					state.activeTool = nil
					local existing = findExistingGun(state)
					if existing then
						bindWorldGun(state, existing)
					else
						scheduleRespawn(state)
					end
				end
			end
		end
	end
end)
