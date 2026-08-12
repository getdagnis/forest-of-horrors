-- WeaponSpawnSystem
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")

local templates = ServerStorage:WaitForChild("WeaponTemplates")
local spawnFolder = workspace:WaitForChild("WeaponSpawnPoints")

local RESPAWN_DELAY = 12

local scheduled = {}
local activeTools = {}

local function isHeldByPlayer(tool)
	local parent = tool.Parent

	if not parent then
		return false
	end

	if parent:IsA("Backpack") and parent.Parent:IsA("Player") then
		return true
	end

	if parent:IsA("Model") and Players:GetPlayerFromCharacter(parent) then
		return true
	end

	return false
end

local function prepareToolPhysics(tool, inWorkspace)
	for _, item in tool:GetDescendants() do
		if item:IsA("BasePart") then
			item.Anchored = inWorkspace
			item.CanCollide = false
			item.Massless = true

			if item.Name == "Handle" and inWorkspace then
				item.CanTouch = true
			else
				item.CanTouch = false
			end
		end
	end
end

local function spawnWeapon(spawnPoint)
	local weaponName = spawnPoint:GetAttribute("WeaponName")
	if not weaponName then return end

	local template = templates:FindFirstChild(weaponName)
	if not template or not template:IsA("Tool") then
		warn("Missing weapon template:", weaponName)
		return
	end

	local spawnId = spawnPoint:GetAttribute("SpawnId")
	if not spawnId then
		spawnId = HttpService:GenerateGUID(false)
		spawnPoint:SetAttribute("SpawnId", spawnId)
	end

	local tool = template:Clone()
	tool:SetAttribute("ManagedWeaponSpawn", true)
	tool:SetAttribute("SpawnId", spawnId)
	tool.CanBeDropped = false

	prepareToolPhysics(tool, true)

	tool:PivotTo(spawnPoint.CFrame)
	tool.Parent = workspace

	activeTools[spawnId] = tool
	scheduled[spawnId] = false

	tool.AncestryChanged:Connect(function()
		if scheduled[spawnId] then return end

		if isHeldByPlayer(tool) then
			scheduled[spawnId] = true
			activeTools[spawnId] = nil

			task.delay(RESPAWN_DELAY, function()
				spawnWeapon(spawnPoint)
			end)
		elseif not tool.Parent then
			scheduled[spawnId] = true
			activeTools[spawnId] = nil

			task.delay(RESPAWN_DELAY, function()
				spawnWeapon(spawnPoint)
			end)
		end
	end)
end

local function setupSpawnPoint(spawnPoint)
	if not spawnPoint:IsA("BasePart") then return end
	if not spawnPoint:GetAttribute("WeaponName") then return end

	local spawnId = spawnPoint:GetAttribute("SpawnId")
	if not spawnId then
		spawnId = HttpService:GenerateGUID(false)
		spawnPoint:SetAttribute("SpawnId", spawnId)
	end

	if activeTools[spawnId] then
		return
	end

	spawnWeapon(spawnPoint)
end

for _, item in workspace:GetDescendants() do
	if item:IsA("Tool") and item.Name == "MonsterGun" and not item:GetAttribute("ManagedWeaponSpawn") then
		item:Destroy()
	end
end

for _, spawnPoint in spawnFolder:GetChildren() do
	setupSpawnPoint(spawnPoint)
end

spawnFolder.ChildAdded:Connect(function(spawnPoint)
	task.defer(function()
		setupSpawnPoint(spawnPoint)
	end)
end)
