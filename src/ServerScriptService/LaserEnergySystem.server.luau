-- LaserEnergySystem
-- Server owner for the shared laser-weapon reserve, map pickups, and permanent
-- charge stations. Place this Script in ServerScriptService.

-- The round has no player-facing recharge loop yet.  Keep this legacy system
-- parked until pickups and stations are deliberately reintroduced as gameplay.
local ENABLED = false
if not ENABLED then return end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MAX_LASER_ENERGY = 600
local PICKUP_RESPAWN_SECONDS = 60
-- An empty reserve reaches full in exactly this long. A partly charged reserve
-- finishes sooner at the same 600/9 energy-per-second rate.
local STATION_FULL_CHARGE_SECONDS = 9
local STATION_MAX_DISTANCE = 6
local ENERGY_TYPES = {
	SmallEnergy = 100,
	LargeEnergy = 300,
}

local chargeEvent = ReplicatedStorage:FindFirstChild("LaserEnergyChargeState")
if not chargeEvent then
	chargeEvent = Instance.new("RemoteEvent")
	chargeEvent.Name = "LaserEnergyChargeState"
	chargeEvent.Parent = ReplicatedStorage
end

local pickupStates = {}
local stationStates = {}
local chargingPlayers = {}

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

local function getPickupState(part)
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
	local state = getPickupState(part)
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

local function getStationPart(station)
	if station:IsA("BasePart") then return station end
	return station:FindFirstChildWhichIsA("BasePart", true)
end

local function stationSound(station, name)
	local sound = station:FindFirstChild(name, true)
	return sound and sound:IsA("Sound") and sound or nil
end

local function finishCharge(player, station, completed)
	local state = stationStates[station]
	if not state or state.player ~= player then return end
	stationStates[station] = nil
	chargingPlayers[player] = nil
	if state.prompt and state.prompt.Parent then state.prompt.Enabled = true end
	local chargeSound = stationSound(station, "BonusChargeUp")
	if chargeSound then chargeSound:Stop() end
	if completed then
		setEnergy(player, MAX_LASER_ENERGY)
		local ding = stationSound(station, "DING")
		if ding then ding:Play() end
		chargeEvent:FireClient(player, "Complete")
	else
		chargeEvent:FireClient(player, "Cancel")
	end
end

local function startCharge(player, station, part, prompt)
	if stationStates[station] or chargingPlayers[player] then return end
	local initialEnergy = math.clamp(tonumber(player:GetAttribute("LaserEnergy")) or MAX_LASER_ENERGY, 0, MAX_LASER_ENERGY)
	if initialEnergy >= MAX_LASER_ENERGY then return end

	local state = { player = player, prompt = prompt }
	stationStates[station] = state
	chargingPlayers[player] = station
	prompt.Enabled = false
	local chargeSound = stationSound(station, "BonusChargeUp")
	if chargeSound then chargeSound:Play() end
	chargeEvent:FireClient(player, "Start", initialEnergy, MAX_LASER_ENERGY, STATION_FULL_CHARGE_SECONDS)

	task.spawn(function()
		local startedAt = os.clock()
		local rate = MAX_LASER_ENERGY / STATION_FULL_CHARGE_SECONDS
		while stationStates[station] == state do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not root or not humanoid or humanoid.Health <= 0
				or (root.Position - part.Position).Magnitude > STATION_MAX_DISTANCE
			then
				finishCharge(player, station, false)
				return
			end

			local energy = initialEnergy + ((os.clock() - startedAt) * rate)
			setEnergy(player, energy)
			if energy >= MAX_LASER_ENERGY then
				finishCharge(player, station, true)
				return
			end
			task.wait(0.1)
		end
	end)
end

local function isChargeStation(instance)
	return instance.Name == "Power Box" or instance:GetAttribute("EnergyChargeStation") == true
end

local function setupStation(station)
	if not isChargeStation(station) or station:GetAttribute("EnergyChargeStationBound") then return end
	local part = getStationPart(station)
	if not part then return end
	station:SetAttribute("EnergyChargeStationBound", true)
	local prompt = part:FindFirstChild("EnergyChargePrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "EnergyChargePrompt"
		prompt.ActionText = "Charge energy"
		prompt.ObjectText = "Power Box"
		prompt.MaxActivationDistance = STATION_MAX_DISTANCE
		prompt.RequiresLineOfSight = false
		prompt.HoldDuration = 0
		prompt.Parent = part
	end
	prompt.Triggered:Connect(function(player)
		startCharge(player, station, part, prompt)
	end)
end

for _, player in Players:GetPlayers() do initialisePlayer(player) end
Players.PlayerAdded:Connect(initialisePlayer)
Players.PlayerRemoving:Connect(function(player)
	local station = chargingPlayers[player]
	if station then finishCharge(player, station, false) end
end)

local folder = Workspace:FindFirstChild("EnergySpawnPoints")
if folder then
	for _, child in folder:GetChildren() do setupPickup(child) end
	folder.ChildAdded:Connect(function(child) task.defer(setupPickup, child) end)
else
	Workspace.ChildAdded:Connect(function(child)
		if child.Name ~= "EnergySpawnPoints" then return end
		for _, pickup in child:GetChildren() do setupPickup(pickup) end
		child.ChildAdded:Connect(function(pickup) task.defer(setupPickup, pickup) end)
	end)
end

for _, instance in ipairs(Workspace:GetDescendants()) do
	if instance:IsA("Model") or instance:IsA("BasePart") then setupStation(instance) end
end
Workspace.DescendantAdded:Connect(function(instance)
	if instance:IsA("Model") or instance:IsA("BasePart") then
		task.defer(setupStation, instance)
	end
end)
