-- LaserEnergySystem
-- Server owner for the shared laser-weapon reserve and map energy pickups.
-- Place this Script in ServerScriptService.

local Players = game:GetService("Players")

local MAX_LASER_ENERGY = 600
local PICKUP_RESPAWN_SECONDS = 60
local ENERGY_TYPES = {
	SmallEnergy = 100,
	LargeEnergy = 300,
}

local pickupStates = {}

local function setEnergy(player, energy)
	player:SetAttribute("LaserEnergy", math.clamp(energy, 0, MAX_LASER_ENERGY))
end

local function initialisePlayer(player)
	setEnergy(player, MAX_LASER_ENERGY)
end

local function getEnergyAmount(part)
	local explicitAmount = tonumber(part:GetAttribute("EnergyAmount"))
	if explicitAmount then return math.max(0, explicitAmount) end
	local energyType = part:GetAttribute("EnergyType")
	if type(energyType) ~= "string" then energyType = part.Name end
	return ENERGY_TYPES[energyType]
end

local function getState(part)
	local state = pickupStates[part]
	if state then return state end
	state = {
		available = true,
		transparency = part.Transparency,
		canCollide = part.CanCollide,
		canTouch = part.CanTouch,
	}
	pickupStates[part] = state
	return state
end

local function setPickupVisible(part, state, visible)
	part.Transparency = visible and state.transparency or 1
	part.CanCollide = visible and state.canCollide or false
	part.CanTouch = visible and state.canTouch or false
end

local function setupPickup(part)
	if not part:IsA("BasePart") then return end
	local amount = getEnergyAmount(part)
	if not amount or amount <= 0 then return end
	local state = getState(part)
	part.Touched:Connect(function(hit)
		if not state.available then return end
		local character = hit:FindFirstAncestorOfClass("Model")
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player then return end
		state.available = false
		setEnergy(player, (tonumber(player:GetAttribute("LaserEnergy")) or MAX_LASER_ENERGY) + amount)
		setPickupVisible(part, state, false)
		task.delay(PICKUP_RESPAWN_SECONDS, function()
			if not part.Parent then pickupStates[part] = nil return end
			state.available = true
			setPickupVisible(part, state, true)
		end)
	end)
end

for _, player in Players:GetPlayers() do initialisePlayer(player) end
Players.PlayerAdded:Connect(initialisePlayer)

local folder = workspace:FindFirstChild("EnergySpawnPoints")
if folder then
	for _, child in folder:GetChildren() do setupPickup(child) end
	folder.ChildAdded:Connect(function(child) task.defer(setupPickup, child) end)
else
	workspace.ChildAdded:Connect(function(child)
		if child.Name ~= "EnergySpawnPoints" then return end
		for _, pickup in child:GetChildren() do setupPickup(pickup) end
		child.ChildAdded:Connect(function(pickup) task.defer(setupPickup, pickup) end)
	end)
end
