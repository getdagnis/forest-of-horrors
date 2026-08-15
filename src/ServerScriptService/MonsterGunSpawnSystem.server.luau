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
local states = {}

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
	state.activeTool = tool
	if not prepareTool(tool, false) then return end

	tool.AncestryChanged:Connect(function()
		if state.activeTool ~= tool or state.respawnScheduled then return end
		if not isHeldByPlayer(tool) then return end
		-- Do this immediately so RightGrip never carries the anchored pickup.
		prepareTool(tool, true)
		task.defer(function()
			if state.activeTool ~= tool or state.respawnScheduled or not isHeldByPlayer(tool) then return end
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
		if not state.spawnPoint.Parent then
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
	for _, child in folder:GetChildren() do
		setupSpawnPoint(child)
	end
	folder.ChildAdded:Connect(function(child)
		task.defer(setupSpawnPoint, child)
	end)
end

local spawnFolder = workspace:FindFirstChild("WeaponSpawnPoints")
if spawnFolder then
	observeSpawnFolder(spawnFolder)
else
	workspace.ChildAdded:Connect(function(child)
		if child.Name == "WeaponSpawnPoints" then
			observeSpawnFolder(child)
		end
	end)
end
