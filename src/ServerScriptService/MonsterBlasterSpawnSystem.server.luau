-- MonsterBlasterSpawnSystem
-- Owns world-pickup replacement for the canonical
-- ServerStorage.WeaponTemplates.MonsterBlaster Tool.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local templates = ServerStorage:WaitForChild("WeaponTemplates")
local MonsterBlasterConfig = require(ReplicatedStorage:WaitForChild("MonsterBlasterConfig"))
local WEAPON_NAME = "MonsterBlaster"
local RESPAWN_DELAY = 12
local RECONCILE_RADIUS = 2
local states = {}
local observedSpawnFolders = {}

local function roundIsActive(generation)
	return workspace:GetAttribute("RoundState") == "Active"
		and tonumber(workspace:GetAttribute("RoundGeneration")) == generation
end

local LEGACY_BLASTER_SPAWNER_NAMES = {
	BlasterSpawner = true,
	MonsterBlasterSpawner = true,
	MonsterBlasterGunSpawner = true,
}

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

local function findOwnedBlaster(player)
	for _, container in ipairs({ player.Character, player:FindFirstChild("Backpack") }) do
		if container then
			for _, item in ipairs(container:GetChildren()) do
				if item:IsA("Tool") and item.Name == WEAPON_NAME then
					return item
				end
			end
		end
	end
	return nil
end

local function rechargeBlaster(player, tool)
	player:SetAttribute(MonsterBlasterConfig.PLAYER_CHARGE_ATTRIBUTE, MonsterBlasterConfig.MAX_CHARGE_UNITS)
	tool:SetAttribute(MonsterBlasterConfig.CHARGE_ATTRIBUTE, MonsterBlasterConfig.MAX_CHARGE_UNITS)
	local nonce = (tonumber(tool:GetAttribute("MonsterBlasterRechargeNonce")) or 0) + 1
	tool:SetAttribute("MonsterBlasterRechargeNonce", nonce)
end

local function bindWorldTool(state, tool)
	state.activeTool = tool
	if not prepareTool(tool, false) then return end
	local handle = tool:FindFirstChild("Handle", true)
	if not handle or not handle:IsA("BasePart") then return end
	handle.CanTouch = false
	local prompt = handle:FindFirstChild("MonsterBlasterPickupPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "MonsterBlasterPickupPrompt"
		prompt.ActionText = "Pick up"
		prompt.ObjectText = "Monster Blaster"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = handle
	end
	prompt.Enabled = workspace:GetAttribute("RoundState") == "Active"
	prompt.Triggered:Connect(function(player)
		if state.activeTool ~= tool or workspace:GetAttribute("RoundState") ~= "Active" then return end
		local incumbent = findOwnedBlaster(player)
		if incumbent then
			-- A second pickup is a recharge, not a Tool transfer. Keep the incumbent
			-- in its current container/equipped state and consume only the world copy.
			rechargeBlaster(player, incumbent)
			tool:Destroy()
			return
		end
		local backpack = player:FindFirstChild("Backpack")
		if not backpack then return end
		prompt.Enabled = false
		tool:SetAttribute("BlasterChargeFromLoadout", false)
		if not prepareTool(tool, true) then return end
		tool.Parent = backpack
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then humanoid:EquipTool(tool) end
	end)
	tool.AncestryChanged:Connect(function()
		if state.activeTool ~= tool or state.respawnScheduled then return end
		task.defer(function()
			if state.activeTool ~= tool or state.respawnScheduled then return end
			-- A first pickup enters the player's Backpack. A recharge consumes the
			-- world copy. Both outcomes schedule its replacement.
			if isHeldByPlayer(tool) then prepareTool(tool, true) end
			if isHeldByPlayer(tool) or tool.Parent == nil then
				state.activeTool = nil
				scheduleRespawn(state)
			end
		end)
	end)
end

scheduleRespawn = function(state, delay)
	if state.respawnScheduled then return end
	local generation = tonumber(workspace:GetAttribute("RoundGeneration"))
	if not generation or workspace:GetAttribute("RoundState") ~= "Active" then return end
	state.respawnScheduled = true
	task.delay(delay == nil and RESPAWN_DELAY or delay, function()
		state.respawnScheduled = false
		if not roundIsActive(generation) then return end
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
		-- World spawns are new pickups, so accepting one restores a full reserve.
		tool:SetAttribute("BlasterChargeFromLoadout", false)
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
	if observedSpawnFolders[folder] then return end
	observedSpawnFolders[folder] = true
	for _, child in folder:GetChildren() do setupSpawnPoint(child) end
	folder.ChildAdded:Connect(function(child)
		task.defer(setupSpawnPoint, child)
	end)
end

local function disableLegacySpawner(instance)
	if instance:IsA("BaseScript") and LEGACY_BLASTER_SPAWNER_NAMES[instance.Name] then
		instance.Disabled = true
	end
end

-- WeaponSpawnPoints is sometimes nested inside a map building (for example
-- TreeHouse). The old root-only lookup silently ignored those points, so the
-- first pickup worked only when a separate legacy spawner happened to create it.
for _, instance in workspace:GetDescendants() do
	if instance.Name == "WeaponSpawnPoints" and (instance:IsA("Folder") or instance:IsA("Model")) then
		observeSpawnFolder(instance)
	end
	disableLegacySpawner(instance)
end

workspace.DescendantAdded:Connect(function(instance)
	disableLegacySpawner(instance)
	if instance.Name == "WeaponSpawnPoints" and (instance:IsA("Folder") or instance:IsA("Model")) then
		observeSpawnFolder(instance)
	end
end)

workspace:GetAttributeChangedSignal("RoundState"):Connect(function()
	local active = workspace:GetAttribute("RoundState") == "Active"
	for _, state in pairs(states) do
		local tool = state.activeTool
		local handle = tool and tool:FindFirstChild("Handle", true)
		local prompt = handle and handle:FindFirstChild("MonsterBlasterPickupPrompt")
		if prompt and prompt:IsA("ProximityPrompt") then prompt.Enabled = active end
		if active and not state.activeTool and not state.respawnScheduled then
			scheduleRespawn(state, 0)
		end
	end
end)
