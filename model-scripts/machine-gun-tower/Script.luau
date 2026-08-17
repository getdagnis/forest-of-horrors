-- MountedTurretSeat > gun > Seat (server Script)
--
-- Keep this Script enabled.  Its disabled `control` child is a LocalScript
-- template; it is cloned only for the player currently seated at this tower.
-- The old version listened to every Seat property change and could leave stale
-- controllers behind after a player got out or died.

local Players = game:GetService("Players")

local seat = script.Parent
local controlTemplate = script:WaitForChild("control")
local CONTROLLER_NAME = "MountedTurretController"
local ACTIVE_TURRET_VALUE_NAME = "ActiveMountedTurret"

local function getTurret()
	-- The project marks the outer playable turret Model with Turret=true.  The
	-- fallback preserves this marketplace model's existing Seat > gun > Turret
	-- hierarchy while the attribute is being added to old tower copies.
	local current = seat.Parent
	while current do
		if current:IsA("Model") and current:GetAttribute("Turret") == true then
			return current
		end
		current = current.Parent
	end
	return seat.Parent and seat.Parent.Parent
end

local function removeController(character)
	local controller = character and character:FindFirstChild(CONTROLLER_NAME)
	if controller then controller:Destroy() end
end

local function clearActiveTurret(player, turret)
	if not player then return end
	local value = player:FindFirstChild(ACTIVE_TURRET_VALUE_NAME)
	if value and value:IsA("ObjectValue") and value.Value == turret then
		value:Destroy()
	end
end

local function setActiveTurret(player, turret)
	local value = player:FindFirstChild(ACTIVE_TURRET_VALUE_NAME)
	if not (value and value:IsA("ObjectValue")) then
		if value then value:Destroy() end
		value = Instance.new("ObjectValue")
		value.Name = ACTIVE_TURRET_VALUE_NAME
		value.Parent = player
	end
	value.Value = turret
end

local function syncOccupant()
	local turret = getTurret()
	local humanoid = seat.Occupant
	local character = humanoid and humanoid.Parent
	local player = character and Players:GetPlayerFromCharacter(character)

	-- Remove any controller tied to a player who left this particular seat.
	for _, candidate in ipairs(Players:GetPlayers()) do
		if candidate ~= player then
			removeController(candidate.Character)
			clearActiveTurret(candidate, turret)
		end
	end
	if not player or not character then return end

	if not (turret and turret:IsA("Model")) then
		warn("[MountedTurret] Seat has no outer turret Model:", seat:GetFullName())
		return
	end
	setActiveTurret(player, turret)

	local existing = character:FindFirstChild(CONTROLLER_NAME)
	if existing then return end

	local controller = controlTemplate:Clone()
	controller.Name = CONTROLLER_NAME
	controller.Disabled = true
	local turretValue = controller:FindFirstChild("Value")
	if not (turretValue and turretValue:IsA("ObjectValue")) then
		turretValue = Instance.new("ObjectValue")
		turretValue.Name = "Value"
		turretValue.Parent = controller
	end
	turretValue.Value = turret
	controller.Parent = character
	controller.Disabled = false
end

seat:GetPropertyChangedSignal("Occupant"):Connect(syncOccupant)
task.defer(syncOccupant)
