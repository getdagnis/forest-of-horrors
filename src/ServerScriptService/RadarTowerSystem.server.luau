-- RadarTowerSystem: explicit, copy-safe radar tower controls.
-- Every tower is identified by RadarTower=true. Its actual Seat and display
-- part are marked with RadarTowerSeat=true and RadarTowerScreen=true.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ACTIVATION_DISTANCE = 16
local event = ReplicatedStorage:FindFirstChild("RadarTowerUse")
if not event then
	event = Instance.new("RemoteEvent")
	event.Name = "RadarTowerUse"
	event.Parent = ReplicatedStorage
end

local activeSources = {}
local boundTowers = {}
local boundSeats = {}

local function isMarked(instance, attribute)
	return instance:GetAttribute(attribute) == true
end

local function towerFor(instance)
	local current = instance
	while current and current ~= Workspace do
		if current:IsA("Model") and isMarked(current, "RadarTower") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function firstMarkedDescendant(tower, attribute, className)
	for _, instance in ipairs(tower:GetDescendants()) do
		if isMarked(instance, attribute) and (not className or instance:IsA(className)) then
			return instance
		end
	end
	return nil
end

local function firstNamedDescendant(tower, name, className)
	for _, instance in ipairs(tower:GetDescendants()) do
		if instance.Name == name and (not className or instance:IsA(className)) then
			return instance
		end
	end
	return nil
end

local function playerFromOccupant(occupant)
	local character = occupant and occupant.Parent
	return character and Players:GetPlayerFromCharacter(character) or nil
end

local function hideRadar(player, source)
	local active = activeSources[player]
	if source and (not active or active.source ~= source) then return end
	activeSources[player] = nil
	event:FireClient(player, false)
	warn("[RadarTower] closed for", player.Name)
end

local function showRadar(player, source, tower, kind)
	if not (player and source and source.Parent and tower and tower.Parent) then return end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or (root.Position - source.Position).Magnitude > ACTIVATION_DISTANCE then return end
	activeSources[player] = { source = source, tower = tower, kind = kind }
	event:FireClient(player, true, tower)
	warn("[RadarTower] opened for", player.Name, "at", tower:GetFullName(), "via", kind)
end

local function disableLegacyRadarScripts(tower)
	for _, instance in ipairs(tower:GetDescendants()) do
		if instance:IsA("Script") and instance.Name == "RadarScript" then
			instance.Disabled = true
			warn("[RadarTower] disabled legacy RadarScript:", instance:GetFullName())
		end
	end
end

local function prepareAudio(tower)
	for _, soundName in ipairs({ "RadarYacht", "RadarLoop" }) do
		local sound = firstNamedDescendant(tower, soundName, "Sound")
		if sound then
			sound.Looped = true
			sound.Playing = false
			warn("[RadarTower] prepared " .. soundName .. ":", sound:GetFullName())
		end
	end
end

local function bindSeat(tower, seat)
	if boundSeats[seat] or not seat:IsA("Seat") or not isMarked(seat, "RadarTowerSeat") then return end
	boundSeats[seat] = true
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local previous = seat:GetAttribute("RadarOccupantUserId")
		local player = playerFromOccupant(seat.Occupant)
		local userId = player and player.UserId or 0
		seat:SetAttribute("RadarOccupantUserId", userId)
		if previous and previous ~= 0 and previous ~= userId then
			local previousPlayer = Players:GetPlayerByUserId(previous)
			if previousPlayer then hideRadar(previousPlayer, seat) end
		end
		if player then showRadar(player, seat, tower, "seat") end
	end)
	end

local function createConsole(tower, displayPart)
	local console = tower:FindFirstChild("RadarTowerConsole")
	if console and not console:IsA("BasePart") then
		warn("[RadarTower] invalid RadarTowerConsole:", console:GetFullName())
		return
	end
	if not console then
		console = Instance.new("Part")
		console.Name = "RadarTowerConsole"
		console.Size = Vector3.new(3, 3, 0.5)
		console.CFrame = displayPart.CFrame
		console.Anchored = true
		console.CanCollide = false
		console.CanTouch = false
		console.CanQuery = false
		console.Transparency = 1
		console.Parent = tower
		warn("[RadarTower] created console:", console:GetFullName())
	end
	local prompt = console:FindFirstChild("RadarTowerPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "RadarTowerPrompt"
		prompt.ActionText = "Use Radar"
		prompt.ObjectText = "Radar Console"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.MaxActivationDistance = ACTIVATION_DISTANCE
		prompt.RequiresLineOfSight = false
		prompt.Parent = console
		prompt.Triggered:Connect(function(player)
			showRadar(player, console, tower, "console prompt")
		end)
	end
	local detector = console:FindFirstChild("RadarTowerClick")
	if not detector then
		detector = Instance.new("ClickDetector")
		detector.Name = "RadarTowerClick"
		detector.MaxActivationDistance = ACTIVATION_DISTANCE
		detector.Parent = console
		detector.MouseClick:Connect(function(player)
			showRadar(player, console, tower, "console click")
		end)
	end
	console:SetAttribute("RadarTowerScreen", true)
end

local function bindTower(tower)
	if boundTowers[tower] or not tower:IsA("Model") or not isMarked(tower, "RadarTower") then return end
	boundTowers[tower] = true
	disableLegacyRadarScripts(tower)
	prepareAudio(tower)
	local seat = firstMarkedDescendant(tower, "RadarTowerSeat", "Seat")
	local displayPart = firstMarkedDescendant(tower, "RadarTowerScreen", "BasePart")
	if seat then bindSeat(tower, seat) else warn("[RadarTower] missing marked Seat:", tower:GetFullName()) end
	if displayPart then createConsole(tower, displayPart) else warn("[RadarTower] missing marked screen:", tower:GetFullName()) end
	warn("[RadarTower] tower ready:", tower:GetFullName())
end

for _, instance in ipairs(Workspace:GetDescendants()) do
	if instance:IsA("Model") and isMarked(instance, "RadarTower") then bindTower(instance) end
end
Workspace.DescendantAdded:Connect(function(instance)
	if instance:IsA("Model") and isMarked(instance, "RadarTower") then task.defer(bindTower, instance) end
end)

warn("[RadarTower] server started; scanning marked towers")

event.OnServerEvent:Connect(function(player, enabled)
	if enabled == false then hideRadar(player) end
end)

task.spawn(function()
	while true do
		task.wait(0.5)
		for player, active in pairs(activeSources) do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local source = active.source
			local stillSeated = active.kind ~= "seat" or playerFromOccupant(source.Occupant) == player
			if not source or not source.Parent or not root or not stillSeated
				or (root.Position - source.Position).Magnitude > ACTIVATION_DISTANCE
			then
				hideRadar(player, source)
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	activeSources[player] = nil
end)
