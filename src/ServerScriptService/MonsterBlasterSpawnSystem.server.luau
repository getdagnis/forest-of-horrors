-- MonsterBlasterSpawnSystem
-- Owns world-pickup replacement for the canonical
-- ServerStorage.WeaponTemplates.MonsterBlaster Tool.

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local templates = ServerStorage:WaitForChild("WeaponTemplates")
local WEAPON_NAME = "MonsterBlaster"
local RESPAWN_DELAY = 12
local RECONCILE_RADIUS = 2
local states = {}

local function isHeldByPlayer(tool)
	local parent = tool.Parent
	return parent and (
		(parent:IsA("Backpack") and parent.Parent:IsA("Player"))
		or (parent:IsA("Model") and Players:GetPlayerFromCharacter(parent) ~= nil)
	)
end

local function getSpawnPointWeaponName(spawnPoint)
	return spawnPoint:GetAttribute("WeaponName") == WEAPON_NAME and WEAPON_NAME or nil
end

local function hasToolJoint(tool, first, second)
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
	for _, item in tool:GetDescendants() do
		if item:IsA("BaseScript") and (
			item.Name == "AnchorScript"
			or item.Name == "GunSpawner"
			or item.Name == "MonsterBlasterGunSpawner"
			or item.Name == "WeaponSpawnSystem"
			or item.Name == "WeaponRuntimeSystem"
			or item.Name == "MonsterGunServer"
		) then
			item.Disabled = true
		end
	end

	local handle = tool:FindFirstChild("Handle", true)
	if not handle or not handle:IsA("BasePart") then
		warn("MonsterBlaster template needs a BasePart named Handle:", tool:GetFullName())
		return false
	end

	for _, item in tool:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = not held
			item.CanCollide = false
			item.CanTouch = not held and item == handle
			item.Massless = true
			if item ~= handle and not hasToolJoint(tool, handle, item) then
				local weld = Instance.new("WeldConstraint")
				weld.Name = "MonsterBlasterAssemblyWeld"
				weld.Part0 = handle
				weld.Part1 = item
				weld.Parent = handle
			end
		end
	end
	return true
end

local function getState(spawnPoint)
	local state = states[spawnPoint]
	if not state then
		state = { spawnPoint = spawnPoint, activeTool = nil, respawnScheduled = false }
		states[spawnPoint] = state
	end
	return state
end

local function findExistingTool(state)
	for _, item in workspace:GetDescendants() do
		if item:IsA("Tool") and item.Name == WEAPON_NAME and not isHeldByPlayer(item) then
			local ok, pivot = pcall(function() return item:GetPivot() end)
			if ok and (pivot.Position - state.spawnPoint.Position).Magnitude <= RECONCILE_RADIUS then
				return item
			end
		end
	end
end

local scheduleRespawn

local function bindWorldTool(state, tool)
	state.activeTool = tool
	if not prepareTool(tool, false) then return end
	tool.AncestryChanged:Connect(function()
		if state.activeTool ~= tool or state.respawnScheduled or not isHeldByPlayer(tool) then return end
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
		local existing = findExistingTool(state)
		if existing then
			bindWorldTool(state, existing)
			return
		end
		local template = templates:FindFirstChild(WEAPON_NAME)
		if not template or not template:IsA("Tool") then
			warn("Missing canonical Tool: ServerStorage.WeaponTemplates.MonsterBlaster")
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
		bindWorldTool(state, tool)
	end)
end

local function setupSpawnPoint(spawnPoint)
	if not spawnPoint:IsA("BasePart") or not getSpawnPointWeaponName(spawnPoint) then return end
	local state = getState(spawnPoint)
	local existing = findExistingTool(state)
	if existing then
		bindWorldTool(state, existing)
	else
		scheduleRespawn(state, 0)
	end
end

local function observeSpawnFolder(folder)
	for _, child in folder:GetChildren() do setupSpawnPoint(child) end
	folder.ChildAdded:Connect(function(child)
		task.defer(setupSpawnPoint, child)
	end)
end

local spawnFolder = workspace:FindFirstChild("WeaponSpawnPoints")
if spawnFolder then
	observeSpawnFolder(spawnFolder)
else
	workspace.ChildAdded:Connect(function(child)
		if child.Name == "WeaponSpawnPoints" then observeSpawnFolder(child) end
	end)
end
